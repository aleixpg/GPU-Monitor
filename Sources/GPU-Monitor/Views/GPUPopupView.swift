import SwiftUI

struct GPUPopupView: View {
    @Bindable var monitor: SSHMonitor
    @Bindable private var display = DisplaySettings.shared

    @State private var host: String
    @State private var port: Int
    @State private var user: String
    @State private var sshKeyPath: String
    @State private var portFormatter = NumberFormatter()

    init(monitor: SSHMonitor) {
        self.monitor = monitor
        _host = State(initialValue: AppSettings.host)
        _port = State(initialValue: AppSettings.port)
        _user = State(initialValue: AppSettings.user)
        _sshKeyPath = State(initialValue: AppSettings.sshKeyPath)
    }

    private func saveSettings() {
        AppSettings.host = host
        AppSettings.port = port
        AppSettings.user = user
        AppSettings.sshKeyPath = sshKeyPath
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch monitor.status {
            case .connected:
                let gpus = monitor.gpus
                let errorMsg = monitor.errorMessage
                if gpus.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("No GPUs found")
                            .foregroundStyle(.secondary)

                        if let msg = errorMsg, !msg.isEmpty {
                            Text(msg)
                                .font(.caption2)
                                .foregroundStyle(.orange)
                                .lineLimit(3)
                        }
                    }
                } else {
                    ScrollView(.horizontal) {
                        HStack(spacing: 0) {
                            ForEach(Array(gpus.enumerated()), id: \.offset) { index, gpu in
                                GPUColumnView(gpu: gpu)
                                if index < gpus.count - 1 {
                                    Divider()
                                        .frame(height: 70)
                                }
                            }
                        }
                    }
                    .scrollIndicators(.never)
                }

                if let last = monitor.lastUpdate {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Last update: \(last.formatted(date: .omitted, time: .standard))")
                            .font(.caption2)
                            .foregroundStyle(.secondary.opacity(0.6))
                        if let driver = monitor.driverVersion {
                            Text("Driver: \(driver)")
                                .font(.caption2)
                                .foregroundStyle(.secondary.opacity(0.6))
                        }
                    }
                }

            case .connecting:
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Connecting…")
                        .foregroundStyle(.secondary)
                }
                .frame(height: 40)

            case .error:
                VStack(alignment: .leading, spacing: 4) {
                    Text("Error")
                        .foregroundStyle(.red)
                        .font(.headline)

                    if let msg = monitor.errorMessage, !msg.isEmpty {
                        Text(msg)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }

                    Button("Reconnect") {
                        monitor.connect()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(.vertical, 4)

            case .disconnected:
                EmptyView()
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Host").frame(width: 36, alignment: .leading)
                    TextField("", text: $host)
                }

                HStack {
                    Text("Port").frame(width: 36, alignment: .leading)
                    TextField("", value: $port, formatter: portFormatter)
                }

                HStack {
                    Text("User").frame(width: 36, alignment: .leading)
                    TextField("", text: $user)
                }

                HStack {
                    Text("Key").frame(width: 36, alignment: .leading)
                    TextField("", text: $sshKeyPath)
                        .help("Path to SSH private key (e.g. ~/.ssh/id_xxx)")
                }
            }
            .font(.body)
            .labelsHidden()

            Toggle("Compact mode", isOn: $display.isCompactMode)
                .toggleStyle(.switch)

            if monitor.status == .connected {
                Button(role: .destructive) {
                    monitor.disconnect()
                } label: {
                    Label("Disconnect", systemImage: "power")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else if !host.isEmpty && !user.isEmpty {
                Button {
                    saveSettings()
                    monitor.connect()
                } label: {
                    Label("Connect", systemImage: "link")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            Divider()

            Button(role: .destructive) {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit GPU Monitor", systemImage: "xmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.secondary)
        }
        .padding(12)
        .frame(minWidth: 240)
    }
}
