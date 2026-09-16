import SwiftUI

@main
struct ShortcutShelfApp: App {
    @StateObject private var store = ShortcutStore()

    init() {
        // A background utility should not occupy a Dock slot or app-switcher entry.
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra("ShortcutShelf", systemImage: "command") {
            MenuContent()
                .environmentObject(store)
        }
        .menuBarExtraStyle(.menu)

    }
}

private struct MenuContent: View {
    @EnvironmentObject private var store: ShortcutStore

    var body: some View {
        ForEach(store.items.filter(\.isEnabled)) { item in
            Button(item.name) { store.perform(item) }
        }
        if !store.items.isEmpty { Divider() }
        Button("设置…") { SettingsWindowPresenter.shared.show(store: store) }
            .keyboardShortcut(",")
        Divider()
        Button("退出 ShortcutShelf") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}

@MainActor
private final class SettingsWindowPresenter {
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
        window.title = "ShortcutShelf 设置"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 720, height: 440))
        window.center()
        window.isReleasedWhenClosed = false
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
