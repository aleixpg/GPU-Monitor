import SwiftUI
import AppKit

@main
struct GPU_MonitorApp: App {
    @NSApplicationDelegateAdaptor(GPUAppDelegate.self) var appDelegate
    var body: some Scene { MenuBarExtra("") {} }
}

@MainActor
final class GPUAppDelegate: NSObject, NSApplicationDelegate {
    let monitor = SSHMonitor()
    private let statusItem = NSStatusBar.system.statusItem(withLength: -1)
    private var stackView: GPUStackView?
    private var popover: NSPopover?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let stack = GPUStackView()
        stackView = stack

        if let button = statusItem.button {
            stack.frame = button.bounds
            stack.autoresizingMask = [.width, .height]
            button.addSubview(stack)
            button.action = #selector(togglePopover)
        }

        observeMonitor()
        updateStack()
        AppSettings.migrate()
        monitor.connect()
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.disconnect()
    }

    private func observeMonitor() {
        withObservationTracking {
            _ = monitor.gpus
            _ = monitor.status
            _ = DisplaySettings.shared.isCompactMode
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.updateStack()
                self?.observeMonitor()
            }
        }
    }

    private func updateStack() {
        stackView?.update(
            gpus: monitor.gpus,
            status: monitor.status,
            compact: DisplaySettings.shared.isCompactMode
        )
        statusItem.length = stackView?.frame.size.width ?? statusItem.length
    }

    @objc private func togglePopover() {
        if popover?.isShown == true { popover?.performClose(nil) }
        else { showPopover() }
    }

    private func showPopover() {
        if popover == nil {
            let pop = NSPopover()
            pop.contentSize = NSSize(width: 320, height: 350)
            pop.behavior = .transient; pop.animates = false
            pop.contentViewController = NSHostingController(
                rootView: GPUPopupView(monitor: monitor)
            )
            popover = pop
        }
        popover?.show(relativeTo: statusItem.button!.bounds, of: statusItem.button!, preferredEdge: .minY)
    }
}
