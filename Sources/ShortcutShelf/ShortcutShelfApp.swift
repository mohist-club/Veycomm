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

        Settings {
            SettingsView()
                .environmentObject(store)
        }
    }
}

private struct MenuContent: View {
    @EnvironmentObject private var store: ShortcutStore

    var body: some View {
        ForEach(store.items.filter(\.isEnabled)) { item in
            Button(item.name) { store.perform(item) }
        }
        if !store.items.isEmpty { Divider() }
        Button("设置…") {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
            .keyboardShortcut(",")
        Divider()
        Button("退出 ShortcutShelf") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}
