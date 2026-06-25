import Foundation

// O6: no raw value needed
enum ConnectionStatus { case disconnected, connecting, connected, error }

@Observable
final class SSHMonitor {
    var gpus: [GPUInfo] = []
    var status: ConnectionStatus = .disconnected
    var errorMessage: String?
    var lastUpdate: Date?
    var driverVersion: String?

    private let socketPath = NSString("~/.gpu-bar.sock").expandingTildeInPath
    private let knownHostsPath: String = {
        let p = NSString("~/.gpu-bar-known-hosts").expandingTildeInPath
        if !FileManager.default.fileExists(atPath: p) {
            FileManager.default.createFile(atPath: p, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        return p
    }()
    private var pollTimer: Timer?
    private var reconnectDelay: TimeInterval = 1

    private var baseArgs: [String] = []

    // ─── Connect ───

    func connect() {
        guard status != .connecting, status != .connected else { return }
        guard AppSettings.hasConfig else {
            status = .error; errorMessage = "Configure server first"; return
        }

        let kv = AppSettings.validateKey()
        guard case .ok = kv else {
            status = .error
            if case .fail(let m) = kv { errorMessage = m }
            return
        }

        status = .connecting; errorMessage = nil; reconnectDelay = 1
        baseArgs = AppSettings.sshArgs

        let mp = sshProc()
        mp.arguments = ["-MN", "-S", socketPath, "-o", "ControlPersist=7200",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "UserKnownHostsFile=\(knownHostsPath)"] + baseArgs
        mp.standardOutput = FileHandle.nullDevice; mp.standardError = FileHandle.nullDevice

        do {
            try mp.run()
        } catch {
            status = .error; errorMessage = "Failed to start SSH"; scheduleReconnect(); return
        }

        let ba = baseArgs
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            let cp = self.sshProc()
            cp.arguments = ["-S", self.socketPath, "-O", "check"] + ba
            let (o, e) = (Pipe(), Pipe())
            cp.standardOutput = o; cp.standardError = e
            do { try cp.run() } catch { return }
            waitWithTimeout(for: cp, seconds: 5)
            let out = (self.readPipe(o) + self.readPipe(e)).trimmingCharacters(in: .whitespacesAndNewlines)
            let ok = out.contains("Master running")
            Task { @MainActor in
                if ok {
                    self.status = .connected; self.fetchMetadata(); self.startPolling()
                } else {
                    self.status = .error
                    self.errorMessage = out.isEmpty ? "Connection failed" : out
                    self.scheduleReconnect()
                }
            }
        }
    }

    // ─── Disconnect ───

    func disconnect() {
        stopPolling()
        let c = sshProc()
        c.arguments = ["-S", socketPath, "-O", "exit"] + baseArgs
        try? c.run(); waitWithTimeout(for: c, seconds: 2)
        try? FileManager.default.removeItem(atPath: socketPath)
        status = .disconnected; errorMessage = nil; gpus = []; baseArgs = []
    }

    // ─── Metadata (once on connect) ───

    private nonisolated func fetchMetadata() {
        let p = sshProc()
        p.arguments = ["-S", socketPath] + baseArgs + ["nvidia-smi --query-gpu=fan.speed,pcie.link.gen.current,pcie.link.width.current,driver_version --format=csv,noheader,nounits"]
        guard let (o, _) = runCmd(p) else { return }
        waitWithTimeout(for: p, seconds: 5)
        let lines = readPipe(o).components(separatedBy: "\n")
        var gpus = self.gpus; var drv: String?
        for (i, line) in lines.enumerated() {
            let pt = csv(line)
            guard !pt.isEmpty else { continue }
            if i < gpus.count {
                let e = gpus[i]
                let fan: Int?
                if pt.count >= 1, let v = Int(pt[0]), !pt[0].contains("Not") { fan = v } else { fan = e.fanPercent }
                let pg = pt.count >= 2 ? Int(pt[1]) : e.pcieGen
                let pw = pt.count >= 2 ? Int(pt[2]) : e.pcieWidth
                gpus[i] = GPUInfo(index: e.index, temperature: e.temperature,
                    power: e.power, memoryPercent: e.memoryPercent,
                    fanPercent: fan, pcieGen: pg, pcieWidth: pw)
            }
            if pt.count >= 4 { drv = pt[3] }
        }
        Task { @MainActor in self.gpus = gpus; self.driverVersion = drv }
    }

    // ─── Polling ───

    private func startPolling() {
        stopPolling(); refresh()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
    }

    private func stopPolling() { pollTimer?.invalidate(); pollTimer = nil }

    private func scheduleReconnect() {
        let delay = reconnectDelay
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
            Task { @MainActor in self?.connect() }
            self?.reconnectDelay = min(delay * 2, 30)
        }
    }

    // ─── Refresh (1s loop) ───

    nonisolated func refresh() {
        let p = sshProc()
        p.arguments = ["-S", socketPath] + baseArgs + ["nvidia-smi --query-gpu=temperature.gpu,power.draw,memory.used,memory.total --format=csv,noheader,nounits"]
        guard let (out, err) = runCmd(p) else { return }
        waitWithTimeout(for: p, seconds: 5)
        let txt = readPipe(out)
        let rawErr = readPipe(err)
        let lost = ["socket", "Connection", "Operation not possible", "Control socket connect"].contains { rawErr.contains($0) }
        let parsed = parseGPUs(txt, existing: self.gpus, lost: lost)
        let hasErr = lost || (p.terminationStatus != 0 && !rawErr.isEmpty)

        Task { @MainActor in
            if hasErr {
                status = .error
                errorMessage = lost ? "Connection lost" : rawErr.isEmpty ? "Command failed" : rawErr
                if lost { scheduleReconnect() }
                return
            }
            gpus = parsed; lastUpdate = .now; reconnectDelay = 1
            NotificationCenter.default.post(name: .gpuDataChanged, object: nil)
        }
    }

    // ─── Helpers ───

    private nonisolated func sshProc() -> Process {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        p.standardInput = FileHandle.nullDevice
        return p
    }

    private nonisolated func runCmd(_ p: Process) -> (Pipe, Pipe)? {
        let (o, e) = (Pipe(), Pipe()); p.standardOutput = o; p.standardError = e
        do { try p.run() } catch {
            Task { @MainActor in self.status = .error; self.errorMessage = "SSH failed"; self.scheduleReconnect() }
            return nil
        }
        return (o, e)
    }

    private nonisolated func readPipe(_ p: Pipe) -> String {
        String(data: p.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    private nonisolated func csv(_ l: String) -> [String] {
        l.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private nonisolated func parseGPUs(_ txt: String, existing: [GPUInfo], lost: Bool) -> [GPUInfo] {
        guard !lost else { return [] }
        var r: [GPUInfo] = []
        for (i, l) in txt.components(separatedBy: "\n").enumerated() {
            let p = csv(l)
            guard p.count >= 4 else { continue }
            let t = Int(p[0]) ?? 0, pw = Double(p[1]) ?? 0
            let mu = Double(p[2]) ?? 0, mt = max(Double(p[3]) ?? 1, 1)
            let e = existing.indices.contains(i) ? existing[i] : nil
            r.append(GPUInfo(index: i, temperature: t, power: pw,
                memoryPercent: round(mu / mt * 1000) / 10,
                fanPercent: e?.fanPercent, pcieGen: e?.pcieGen, pcieWidth: e?.pcieWidth))
        }
        return r
    }
}

extension Notification.Name { static let gpuDataChanged = Notification.Name("GPUDataChanged") }

private func waitWithTimeout(for p: Process, seconds: TimeInterval) {
    let d = Date(timeIntervalSinceNow: seconds)
    while p.isRunning, Date() < d { Thread.sleep(forTimeInterval: 0.05) }
    if p.isRunning { p.interrupt(); Thread.sleep(forTimeInterval: 0.1) }
}
