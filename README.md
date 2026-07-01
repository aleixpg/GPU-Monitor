# GPU Monitor ![Platform](https://img.shields.io/badge/macOS-14%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.9-orange) ![License](https://img.shields.io/badge/license-MIT-green)
This app was vibecoded on my local AI rig running Qwen 3.6 27B. I built it to keep a close eye on my GPU's performance during intensive, all-day workloads. Contributions, issues, and PRs are highly welcome!

macOS menu bar app that displays real-time GPU temperature, power draw, and memory usage from a remote NVIDIA server — connected via SSH.

No external dependencies. Pure Swift + AppKit + SwiftUI.

Compact version:

<img width="128" height="27" alt="image" src="https://github.com/user-attachments/assets/9ae6a5a0-0f35-4c3a-8821-1d234a0e3574" />

Full version:

<img width="272" height="25" alt="image" src="https://github.com/user-attachments/assets/eff668e8-63fd-4bca-a797-812428178141" />

---

## Features

- **Real-time monitoring** — refreshes every second via SSH ControlMaster (persistent connection, no per-request handshake)
- **Multi-GPU support** — displays all GPUs side by side in the menu bar
- **Color-coded metrics** — green / yellow / red thresholds for temperature and memory
- **Inline menu bar display** — lightweight "Stack 2 filas" layout directly in the menu bar (like exelban/stats)
- **Compact mode** — toggle between standard and compact menu bar layouts
- **Detailed popup** — click the menu bar item to see per-GPU columns with progress bars and live settings
- **Secure settings** — server credentials stored in macOS Keychain
- **SSH host key verification** — remembers server fingerprints, detects MITM attacks
- **Auto-reconnect** — up to 2 automatic retries with backoff (1s, then 2s) if the SSH connection drops; manual Reconnect after that
- **Zero dock presence** — menu bar only app (`LSUIElement = true`)

---

## Quick Start

### Prerequisites

- macOS 14+ (Sonoma or later)
- Swift 5.9+ toolchain
- OpenSSH on the remote server with `nvidia-smi` installed
- SSH key-based authentication (`~/.ssh/id_xxx` or custom path)

### Build

```bash
# Release build (creates GPU-Monitor.app)
./build.sh

# Or debug build
swift build
```

### Run

```bash
open GPU-Monitor.app
```

### Configure

1. Click the **GPU/SSH** label in the menu bar
2. Enter your server details:
   - **Host**: your server's IP or hostname
   - **Port**: SSH port (default `22`)
   - **User**: SSH username
   - **Key**: path to your private key (e.g., `~/.ssh/id_xxx`)
3. Click **Connect**

On first connection, SSH will accept and remember the server's host key fingerprint for future verification.

---

## Architecture

```
Sources/GPU-Monitor/
├── GPU_MonitorApp.swift        # App entry, NSStatusBar setup, NSPopover popup
├── Models/
│   └── GPUInfo.swift            # GPU data model with color thresholds
├── Services/
│   ├── AppSettings.swift        # Keychain-backed settings (host, port, user, key)
│   ├── DisplaySettings.swift    # Observable compact-mode preference (UserDefaults)
│   └── SSHMonitor.swift         # SSH ControlMaster, nvidia-smi parsing, refresh loop
└── Views/
    ├── GPUColumnView.swift      # Per-GPU column with progress bar (popup)
    ├── GPUPopupView.swift       # Main popup window (SwiftUI)
    └── GPUStackView.swift       # Custom AppKit view for inline menu bar rendering
```

### Stack

| Layer      | Technology                              |
|------------|-----------------------------------------|
| Platform   | macOS 14+ (Sonoma)                      |
| Language   | Swift 5.9                               |
| UI         | SwiftUI + AppKit (`NSStatusBar`, `NSPopover`) |
| SSH        | Native `Process` + OpenSSH ControlMaster |
| Storage    | macOS Keychain (credentials) + `UserDefaults` (preferences) |
| Dock       | `LSUIElement = true` (menu bar only)    |

---

## How It Works

### SSH ControlMaster

Instead of opening/closing an SSH connection every second (~200ms per handshake), GPU Monitor uses SSH ControlMaster for a single persistent connection:

```bash
# Persistent master (app launch)
ssh -MN -S ~/.gpu-bar.sock -o ControlPersist=7200 user@host

# Fast refresh (<50ms, reused channel)
ssh -S ~/.gpu-bar.sock user@host "nvidia-smi --query-gpu=..."
```

The connection persists for 2 hours of inactivity and is cleaned up when the app exits.

### Two-Phase nvidia-smi Queries

To minimize overhead, GPU Monitor splits queries into two phases:

**On connect (once):** Static metadata that doesn't change
```bash
nvidia-smi --query-gpu=pcie.link.gen.current,pcie.link.width.current,driver_version --format=csv,noheader,nounits
```

**Every second (refresh loop):** Only the fields that change
```bash
nvidia-smi --query-gpu=temperature.gpu,power.draw,memory.used,memory.total,fan.speed --format=csv,noheader,nounits
```

The first poll cycle runs both queries back-to-back; every subsequent cycle sends only the lightweight query. PCIe link info and driver version are fetched once per session. Fan speed is part of the live poll (when the GPU reports it) and is preserved across refreshes when `nvidia-smi` returns `[N/A]`.

### Color Thresholds

| Metric     | Green        | Yellow        | Red           |
|------------|--------------|---------------|---------------|
| Temperature| < 60°C       | 60–74°C       | ≥ 75°C        |
| Memory     | < 50%        | 50–80%        | > 80%         |

---

## Menu Bar Display

The app renders directly in the menu bar using a custom `NSView` (`GPUStackView`) with AppKit's `draw(_:)` — SwiftUI cannot render inline in `NSStatusItem` buttons natively.

**Connected** — per-GPU data in a compact 2-row layout:
- Row 1: temperature (color-coded) + memory % (color-coded)
- Row 2: power (W) + GPU index label

**Disconnected / Connecting** — shows "GPU" and "SSH" on two lines with muted styling.
**Error** — same placeholder layout with red text; details and Reconnect appear in the popup.

Two display modes are available:
- **Standard**: Full labels with "GPU N" identifiers
- **Compact**: Smaller font, single-column per metric, no labels (toggle in popup)

Clicking the menu bar item opens a popup panel (`NSPopover`) with detailed GPU columns and inline server settings.

---

## Security

### Host Key Verification

GPU Monitor uses a dedicated known_hosts file (`~/.gpu-bar-known-hosts`) instead of bypassing verification. On first connection, the server's host key is accepted and stored. Subsequent connections verify the key matches — a changed key (indicating a MITM attack) will cause the connection to fail.

### Keychain Storage

Server credentials (host, user, SSH key path) are stored in the macOS Keychain rather than plaintext `UserDefaults`. The Keychain provides:

- System-level encryption (tied to user login)
- Access control (only your app can read its own items)
- Automatic lock on screen lock
- No plaintext storage on disk

Non-sensitive preferences (port number) remain in `UserDefaults` for convenience. Compact mode is stored in `UserDefaults` via the shared `DisplaySettings` observable, which the app delegate observes alongside GPU data so the menu bar layout updates immediately when toggled.

### SSH Key Validation

Before connecting, the app validates that the SSH key file exists and isn't group or world-writable. Connection is blocked if the key file doesn't exist or has insecure permissions.

### Atomic Keychain Updates

Keychain writes use `SecItemUpdate` (atomic) instead of delete+add, preventing data loss if interrupted between operations.

### Concurrent Connection Guard

`connect()` rejects duplicate calls while already connecting or connected, preventing race conditions from rapid reconnection attempts.

### Clean Migration

After migrating from UserDefaults to Keychain, old UserDefaults entries are removed to prevent stale data from re-syncing if Keychain is reset.

### Socket Security

The SSH ControlMaster socket (`~/.gpu-bar.sock`) is created by OpenSSH with default permissions (0600) — only the current user can access it.

---

## Important Notes

### SSH Key Without Passphrase

The app relies on SSH key authentication. If your key has a passphrase, it must be loaded into `ssh-agent` before launching the app. Keys without a passphrase work out of the box.

### Running from Terminal vs Finder

If you launch the app with `open GPU-Monitor.app` and the SSH key has a passphrase, macOS sandboxing may prevent the app from accessing your `ssh-agent`. In that case, run from the terminal:

```bash
./GPU-Monitor.app/Contents/MacOS/GPU-Monitor
```

### Multiple GPUs

The menu bar display scales horizontally with each GPU. Separator lines divide GPU columns. If you have many GPUs, the popup's horizontal scroll handles overflow.

### Connection Recovery

If the SSH control socket is lost, polling stops immediately, GPU data is cleared, and the app retries automatically twice (after 1s, then 2s). If both retries fail, the popup shows "Connection lost (retries exhausted)" and the **Reconnect** button. A successful poll resets the retry counter and delay.

---

## Project Structure

```
GPU-Monitor/
├── Package.swift                 # SPM manifest (macOS 14+, Swift 5.9)
├── build.sh                      # Release build script
├── README.md                     # This file
├── GPU-Monitor.app/              # Built application bundle
└── Sources/GPU-Monitor/
    ├── GPU_MonitorApp.swift      # Entry point, NSStatusBar, NSPopover
    ├── Models/
    │   └── GPUInfo.swift         # Data model + color logic
    ├── Services/
    │   ├── AppSettings.swift     # Keychain-backed settings + key validation
    │   ├── DisplaySettings.swift # Observable compact-mode state
    │   └── SSHMonitor.swift      # SSH ControlMaster + two-phase nvidia-smi
    └── Views/
        ├── GPUColumnView.swift   # SwiftUI GPU column (popup)
        ├── GPUPopupView.swift    # Popup window content
        └── GPUStackView.swift    # AppKit inline menu bar view
```

---

## Development

```bash
# Debug build
swift build

# Run from terminal (captures stdout/stderr)
.build/debug/GPU-Monitor

# Release build with codesign
./build.sh
```

### Key Design Decisions

- **AppKit `NSStatusBar` + custom `NSView`** — SwiftUI's `MenuBarExtra` cannot render inline content in the menu bar. A custom `GPUStackView` using `draw(_:)` gives full control.
- **`NSPopover` popup** — used for the popup panel with transient behavior (click outside to dismiss).
- **Async poll loop** — `SSHMonitor` runs a serial `Task` loop on `@MainActor`; blocking SSH I/O runs in `Task.detached` so the menu bar stays responsive during timeouts.
- **`waitWithTimeout`** — uses polling with `Thread.sleep` instead of `NotificationCenter` (which requires a runloop not available on background queues).
- **Two-phase queries** — static metadata (driver, PCIe) fetched once on connect; live metrics (temp, power, memory, fan speed) polled every second.
- **`DisplaySettings` observable** — single source of truth for compact mode; observed by `GPUAppDelegate` so the menu bar redraws when the popup toggle changes, without callbacks.
- **Keychain storage** — server credentials protected by macOS Keychain; automatic migration from UserDefaults on first run.
- **Cached SSH args** — `AppSettings.sshArgs` (Keychain lookups) is cached at connect time, avoiding ~3 I/O operations per refresh cycle.
- **Static font cache** — `NSFont` instances are cached in a static enum, eliminating per-frame allocations during menu bar redraws.
- **SIGINT over SIGTERM** — `waitWithTimeout` sends SIGINT (`p.interrupt()`) to stale SSH processes, which OpenSSH handles more cleanly than SIGTERM.

---

## License

MIT
