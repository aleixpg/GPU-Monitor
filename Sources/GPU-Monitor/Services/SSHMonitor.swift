import Foundation

enum ConnectionStatus { case disconnected, connecting, connected, error }

@MainActor @Observable
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

    private var pollTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var connectTask: Task<Void, Never>?
    private var reconnectDelay: TimeInterval = 1
    private var retryCount: Int = 0
    private var baseArgs: [String] = []

    // ─── Connect ───

    func connect(isRetry: Bool = false) {
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

        connectTask?.cancel()
        reconnectTask?.cancel()
        reconnectTask = nil
        stopPolling()

        if isRetry { teardownSocket() }

        status = .connecting; errorMessage = nil
        if !isRetry {
            reconnectDelay = 1
            retryCount = 0
        }
        baseArgs = AppSettings.sshArgs

        let args = baseArgs
        let socket = socketPath
        let knownHosts = knownHostsPath

        connectTask = Task {
            let masterErr = await Task.detached {
                SSHBackend.startMaster(socketPath: socket, knownHostsPath: knownHosts, baseArgs: args)
            }.value
            guard !Task.isCancelled else { return }

            if let msg = masterErr {
                status = .error; errorMessage = msg
                scheduleReconnect()
                return
            }

            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }

            let check = await Task.detached {
                SSHBackend.checkMaster(socketPath: socket, baseArgs: args)
            }.value
            guard !Task.isCancelled else { return }

            switch check {
            case .running:
                status = .connected
                retryCount = 0; reconnectDelay = 1
                startPolling()
            case .notRunning:
                status = .error
                errorMessage = "Connection failed"
                scheduleReconnect()
            case .failed(let msg):
                status = .error; errorMessage = msg
                scheduleReconnect()
            }
        }
    }

    // ─── Disconnect ───

    func disconnect() {
        connectTask?.cancel(); connectTask = nil
        reconnectTask?.cancel(); reconnectTask = nil
        stopPolling()
        teardownSocket()
        status = .disconnected; errorMessage = nil; gpus = []; driverVersion = nil
        baseArgs = []; retryCount = 0; reconnectDelay = 1
    }

    // ─── Polling ───

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task {
            var fetchedMetadata = false
            while !Task.isCancelled {
                let args = baseArgs
                let existing = gpus
                let outcome = await SSHBackend.runPoll(args: args, socketPath: socketPath)
                guard !Task.isCancelled else { break }

                switch outcome {
                case .success(let txt):
                    status = .connected; errorMessage = nil
                    gpus = SSHBackend.parseGPUs(txt, existing: existing)
                    lastUpdate = .now; reconnectDelay = 1
                    if !fetchedMetadata {
                        fetchedMetadata = true
                        await applyMetadata(args: args)
                    }
                case .connectionLost:
                    handleConnectionLost()
                    return
                case .failure(let msg):
                    handleError(msg)
                    return
                }

                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel(); pollTask = nil
    }

    private func handleConnectionLost() {
        stopPolling()
        status = .error; errorMessage = "Connection lost"; gpus = []
        scheduleReconnect()
    }

    private func handleError(_ msg: String) {
        stopPolling()
        status = .error; errorMessage = msg; gpus = []
    }

    private func scheduleReconnect() {
        guard reconnectTask == nil else { return }
        stopPolling()

        guard retryCount < 2 else {
            status = .error
            errorMessage = "Connection lost (retries exhausted)"
            gpus = []
            return
        }

        let delay = reconnectDelay
        reconnectDelay = min(delay * 2, 30)
        retryCount += 1

        reconnectTask = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            reconnectTask = nil
            connect(isRetry: true)
        }
    }

    private func applyMetadata(args: [String]) async {
        let existing = gpus
        let result = await SSHBackend.fetchMetadata(args: args, socketPath: socketPath, existing: existing)
        guard !Task.isCancelled, status == .connected else { return }
        gpus = result.gpus
        driverVersion = result.driver
    }

    private func teardownSocket() {
        SSHBackend.teardownSocket(socketPath: socketPath, baseArgs: baseArgs)
    }
}

// ─── Background SSH (no MainActor) ───

private enum SSHBackend {
    static let connectionLostMarkers = [
        "socket", "Connection", "Operation not possible", "Control socket connect"
    ]

    enum PollOutcome {
        case success(String)
        case connectionLost
        case failure(String)
    }

    enum MasterCheck {
        case running, notRunning, failed(String)
    }

    struct MetadataResult {
        var gpus: [GPUInfo]
        var driver: String?
    }

    static func startMaster(
        socketPath: String, knownHostsPath: String, baseArgs: [String]
    ) -> String? {
        let mp = sshProc()
        mp.arguments = ["-MN", "-S", socketPath, "-o", "ControlPersist=7200",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "UserKnownHostsFile=\(knownHostsPath)"] + baseArgs
        mp.standardOutput = FileHandle.nullDevice
        mp.standardError = FileHandle.nullDevice
        do { try mp.run() } catch { return "Failed to start SSH" }
        return nil
    }

    static func checkMaster(socketPath: String, baseArgs: [String]) -> MasterCheck {
        let cp = sshProc()
        cp.arguments = ["-S", socketPath, "-O", "check"] + baseArgs
        let (o, e) = (Pipe(), Pipe())
        cp.standardOutput = o; cp.standardError = e
        do { try cp.run() } catch { return .failed("SSH check failed") }
        waitWithTimeout(for: cp, seconds: 5)
        let out = (readPipe(o) + readPipe(e)).trimmingCharacters(in: .whitespacesAndNewlines)
        return out.contains("Master running") ? .running : .notRunning
    }

    static func runPoll(args: [String], socketPath: String) async -> PollOutcome {
        await Task.detached {
            let p = sshProc()
            p.arguments = ["-S", socketPath] + args + [
                "nvidia-smi --query-gpu=temperature.gpu,power.draw,memory.used,memory.total,fan.speed --format=csv,noheader,nounits"
            ]
            let (out, err) = (Pipe(), Pipe())
            p.standardOutput = out; p.standardError = err
            do { try p.run() } catch { return .failure("SSH failed") }
            waitWithTimeout(for: p, seconds: 5)
            let txt = readPipe(out)
            let rawErr = readPipe(err)
            if connectionLostMarkers.contains(where: { rawErr.contains($0) }) {
                return .connectionLost
            }
            if p.terminationStatus != 0, !rawErr.isEmpty {
                return .failure(rawErr)
            }
            return .success(txt)
        }.value
    }

    static func fetchMetadata(
        args: [String], socketPath: String, existing: [GPUInfo]
    ) async -> MetadataResult {
        await Task.detached {
            let p = sshProc()
            p.arguments = ["-S", socketPath] + args + [
                "nvidia-smi --query-gpu=pcie.link.gen.current,pcie.link.width.current,driver_version --format=csv,noheader,nounits"
            ]
            let (o, _) = (Pipe(), Pipe())
            p.standardOutput = o; p.standardError = Pipe()
            guard (try? p.run()) != nil else { return MetadataResult(gpus: existing, driver: nil) }
            waitWithTimeout(for: p, seconds: 5)
            var gpus = existing
            var drv: String?
            for (i, line) in readPipe(o).components(separatedBy: "\n").enumerated() {
                let pt = csv(line)
                guard !pt.isEmpty else { continue }
                if i < gpus.count {
                    let e = gpus[i]
                    let pg = pt.count >= 1 ? Int(pt[0]) : e.pcieGen
                    let pw = pt.count >= 2 ? Int(pt[1]) : e.pcieWidth
                    gpus[i] = GPUInfo(index: e.index, temperature: e.temperature,
                        power: e.power, memoryPercent: e.memoryPercent,
                        fanPercent: e.fanPercent, pcieGen: pg, pcieWidth: pw)
                }
                if pt.count >= 3 { drv = pt[2] }
            }
            return MetadataResult(gpus: gpus, driver: drv)
        }.value
    }

    static func teardownSocket(socketPath: String, baseArgs: [String]) {
        if !baseArgs.isEmpty {
            let c = sshProc()
            c.arguments = ["-S", socketPath, "-O", "exit"] + baseArgs
            try? c.run()
            waitWithTimeout(for: c, seconds: 2)
        }
        try? FileManager.default.removeItem(atPath: socketPath)
    }

    static func parseGPUs(_ txt: String, existing: [GPUInfo]) -> [GPUInfo] {
        var r: [GPUInfo] = []
        for (i, l) in txt.components(separatedBy: "\n").enumerated() {
            let p = csv(l)
            guard p.count >= 4 else { continue }
            let t = Int(p[0]) ?? 0, pw = Double(p[1]) ?? 0
            let mu = Double(p[2]) ?? 0, mt = max(Double(p[3]) ?? 1, 1)
            let e = existing.indices.contains(i) ? existing[i] : nil
            let fan: Int?
            if p.count >= 5, let v = Int(p[4]), !p[4].contains("Not") {
                fan = v
            } else {
                fan = e?.fanPercent
            }
            r.append(GPUInfo(index: i, temperature: t, power: pw,
                memoryPercent: round(mu / mt * 1000) / 10,
                fanPercent: fan, pcieGen: e?.pcieGen, pcieWidth: e?.pcieWidth))
        }
        return r
    }

    private static func sshProc() -> Process {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        p.standardInput = FileHandle.nullDevice
        return p
    }

    private static func readPipe(_ p: Pipe) -> String {
        String(data: p.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    private static func csv(_ l: String) -> [String] {
        l.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

private func waitWithTimeout(for p: Process, seconds: TimeInterval) {
    let d = Date(timeIntervalSinceNow: seconds)
    while p.isRunning, Date() < d { Thread.sleep(forTimeInterval: 0.05) }
    if p.isRunning { p.interrupt(); Thread.sleep(forTimeInterval: 0.1) }
}
