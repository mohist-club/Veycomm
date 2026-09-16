import AppKit
import Carbon.HIToolbox
import ServiceManagement

@MainActor
final class ShortcutStore: ObservableObject {
    @Published private(set) var items: [ShortcutItem] = []
    @Published var launchAtLogin = false { didSet { updateLaunchAtLogin() } }
    @Published var lastError: String?
    @Published var statusMessage: String?
    private let defaultsKey = "shortcut-items"
    private let manager = GlobalHotKeyManager()
    private let fallbackLoginAgent = UserLaunchAgent()

    init() {
        load()
        launchAtLogin = SMAppService.mainApp.status == .enabled || fallbackLoginAgent.isInstalled
        manager.onHotKey = { [weak self] id in
            guard let self, let item = self.items.first(where: { $0.id == id && $0.isEnabled }) else { return }
            self.perform(item)
        }
        refreshHotKeys()
    }

    func save(_ item: ShortcutItem) {
        if let existing = items.firstIndex(where: { $0.id == item.id }) { items[existing] = item } else { items.append(item) }
        persist(); refreshHotKeys()
    }
    func delete(_ item: ShortcutItem) { items.removeAll { $0.id == item.id }; persist(); refreshHotKeys() }
    func conflict(for item: ShortcutItem) -> ShortcutItem? {
        items.first { $0.id != item.id && $0.isEnabled && $0.shortcut == item.shortcut }
    }
    func perform(_ item: ShortcutItem) {
        switch item.action {
        case .application:
            NSWorkspace.shared.open(URL(fileURLWithPath: item.payload))
        case .url:
            let localPath = (item.payload as NSString).expandingTildeInPath
            let url = URL(string: item.payload) ?? URL(fileURLWithPath: localPath)
            NSWorkspace.shared.open(url)
        case .shell:
            let task = Process(); task.executableURL = URL(fileURLWithPath: "/bin/zsh")
            task.arguments = ["-lc", item.payload]
            do { try task.run() } catch { lastError = "无法执行脚本：\(error.localizedDescription)" }
        case .text:
            paste(item.payload)
        }
    }
    private func paste(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents(); pasteboard.setString(text, forType: .string)
        let source = CGEventSource(stateID: .hidSystemState)
        let vDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        let vUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        vDown?.flags = .maskCommand; vUp?.flags = .maskCommand
        vDown?.post(tap: .cghidEventTap); vUp?.post(tap: .cghidEventTap)
    }
    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey), let saved = try? JSONDecoder().decode([ShortcutItem].self, from: data) else { return }
        items = saved
    }
    private func persist() { UserDefaults.standard.set(try? JSONEncoder().encode(items), forKey: defaultsKey) }
    private func refreshHotKeys() { manager.register(items.filter(\.isEnabled)) }
    private func updateLaunchAtLogin() {
        if launchAtLogin {
            do {
                try SMAppService.mainApp.register()
                try? fallbackLoginAgent.remove()
                statusMessage = "已使用 macOS 登录项启动。"
            } catch {
                do {
                    try fallbackLoginAgent.install()
                    statusMessage = "已使用兼容登录启动方式（当前用户）。"
                } catch {
                    launchAtLogin = false
                    lastError = "无法更新登录启动：\(error.localizedDescription)"
                }
            }
        } else {
            try? SMAppService.mainApp.unregister()
            do { try fallbackLoginAgent.remove() }
            catch { lastError = "无法移除登录启动：\(error.localizedDescription)" }
        }
    }
}

/// A per-user fallback for development and ad-hoc-signed builds. Production,
/// Developer-ID-signed builds use SMAppService above.
private struct UserLaunchAgent {
    private let label = "com.shortcutshelf.app"
    private var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(label).plist")
    }
    var isInstalled: Bool { FileManager.default.fileExists(atPath: fileURL.path) }

    func install() throws {
        guard let executable = Bundle.main.executableURL?.path else {
            throw CocoaError(.fileNoSuchFile)
        }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executable],
            "RunAtLoad": true,
            "ProcessType": "Interactive"
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: fileURL, options: .atomic)
    }

    func remove() throws {
        guard !FileManager.default.fileExists(atPath: fileURL.path) else {
            try FileManager.default.removeItem(at: fileURL)
            return
        }
    }
}

// Carbon delivers hot-key events through the application's event dispatcher.
// Registration and the callback are serialized on that dispatcher.
private final class GlobalHotKeyManager: @unchecked Sendable {
    var onHotKey: ((UUID) -> Void)?
    private var refs: [EventHotKeyRef] = []
    private var ids: [UInt32: UUID] = [:]
    private var handler: EventHandlerRef?
    private var nextID: UInt32 = 1

    init() {
        let spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, userData in
            guard let event, let userData else { return noErr }
            let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            var id = EventHotKeyID(); GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            if let uuid = manager.ids[id.id] { DispatchQueue.main.async { manager.onHotKey?(uuid) } }
            return noErr
        }, 1, [spec], Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
    deinit { refs.forEach { UnregisterEventHotKey($0) }; if let handler { RemoveEventHandler(handler) } }
    func register(_ items: [ShortcutItem]) {
        refs.forEach { UnregisterEventHotKey($0) }; refs.removeAll(); ids.removeAll(); nextID = 1
        for item in items {
            let id = nextID; nextID += 1
            var ref: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: OSType(0x53534846), id: id)
            if RegisterEventHotKey(item.shortcut.keyCode, item.shortcut.modifiers, hotKeyID, GetEventDispatcherTarget(), 0, &ref) == noErr, let ref {
                refs.append(ref); ids[id] = item.id
            }
        }
    }
}
