import SwiftUI

@main
struct VeycommApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = ShortcutStore()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem.button?.image = NSImage(systemSymbolName: "command", accessibilityDescription: "Veycomm")
        statusItem.menu = NSMenu()
        statusItem.menu?.delegate = self
        rebuildMenu()
    }

    func menuWillOpen(_ menu: NSMenu) { rebuildMenu() }

    private func rebuildMenu() {
        let menu = statusItem.menu ?? NSMenu()
        menu.removeAllItems()
        for item in store.items where item.isEnabled {
            let entry = NSMenuItem(title: item.name, action: #selector(runShortcut(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = item.id.uuidString
            menu.addItem(entry)
        }
        if !store.items.isEmpty { menu.addItem(.separator()) }
        let settings = NSMenuItem(title: "设置…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 Veycomm", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
    }

    @objc private func runShortcut(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let id = UUID(uuidString: raw),
              let item = store.items.first(where: { $0.id == id }) else { return }
        store.perform(item)
    }

    @objc private func showSettings() { SettingsWindowPresenter.shared.show(store: store) }
    @objc private func quit() { NSApp.terminate(nil) }

}

@MainActor
final class SettingsWindowPresenter {
    static let shared = SettingsWindowPresenter()
    private var window: NSWindow?

    func show(store: ShortcutStore) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let controller = NSHostingController(rootView: SettingsView().environmentObject(store))
        let window = NSWindow(contentViewController: controller)
        window.title = "Veycomm 设置"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 720, height: 440))
        window.center()
        window.isReleasedWhenClosed = false
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
