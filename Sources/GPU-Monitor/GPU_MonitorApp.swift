import SwiftUI
import AppKit

@main
struct GPU_MonitorApp: App {
    @NSApplicationDelegateAdaptor(GPUAppDelegate.self) var appDelegate
    var body: some Scene { MenuBarExtra("") {} }
}

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
            stack.frame.size.width = stack.computeWidth()
            stack.autoresizingMask = [.width, .height]
            button.addSubview(stack)
            button.action = #selector(togglePopover)
            statusItem.length = stack.frame.size.width
        }

        NotificationCenter.default.addObserver(self, selector: #selector(updateStack),
            name: .gpuDataChanged, object: nil)
        AppSettings.migrate()
        monitor.connect()
    }

    @objc private func updateStack() {
        stackView?.update(gpus: monitor.gpus, status: monitor.status)
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
            pop.contentViewController = NSHostingController(rootView: GPUPopupView(monitor: monitor))
            popover = pop
        }
        popover?.show(relativeTo: statusItem.button!.bounds, of: statusItem.button!, preferredEdge: .minY)
    }
}
