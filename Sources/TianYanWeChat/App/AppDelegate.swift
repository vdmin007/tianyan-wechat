import AppKit

/// 应用委托：负责菜单、状态栏常驻、主窗口生命周期。
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var mainWindowController: MainWindowController?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        // 主窗口：记忆上次窗口状态，首次启动显示
        let controller = MainWindowController()
        mainWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 关闭窗口不退出应用（常驻菜单栏，F7 需求）。
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showMainWindow(nil)
        }
        return true
    }

    // MARK: - 菜单栏常驻

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }
        button.image = NSImage(systemSymbolName: "quote.bubble", accessibilityDescription: "天眼微信")
        button.imagePosition = .imageOnly

        let menu = NSMenu()
        let showItem = NSMenuItem(title: "打开天眼微信", action: #selector(showMainWindow(_:)), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)

        let newItem = NSMenuItem(title: "新建实例", action: #selector(newInstance(_:)), keyEquivalent: "")
        newItem.target = self
        menu.addItem(newItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出天眼微信", action: #selector(quit(_:)), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    @objc private func showMainWindow(_ sender: Any?) {
        mainWindowController?.showWindow(nil)
        mainWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func newInstance(_ sender: Any?) {
        showMainWindow(sender)
        // 触发主窗口的新建流程：通过通知让控制器处理
        NotificationCenter.default.post(name: .tianYanRequestNewInstance, object: nil)
    }

    @objc private func quit(_ sender: Any?) {
        NSApp.terminate(nil)
    }
}

extension Notification.Name {
    static let tianYanRequestNewInstance = Notification.Name("TianYanRequestNewInstance")
}