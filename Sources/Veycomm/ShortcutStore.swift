import AppKit
import Carbon.HIToolbox
import ServiceManagement
import ApplicationServices

@MainActor
final class ShortcutStore: ObservableObject {
    @Published private(set) var items: [ShortcutItem] = []
    @Published var launchAtLogin = false { didSet { updateLaunchAtLogin() } }
    @Published var lastError: String?
    @Published var statusMessage: String?
    let translationSettings = TranslationSettings()
    let updates = UpdateChecker()
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
        manager.onAccessibilityRequired = { [weak self] in
            self?.lastError = "若要覆盖已被其他应用占用的快捷键，请在“系统设置 → 隐私与安全性 → 辅助功能”中允许 Veycomm。"
        }
        refreshHotKeys()
        if updates.automaticallyChecks { Task { await updates.check() } }
    }

    func save(_ item: ShortcutItem) {
        if let existing = items.firstIndex(where: { $0.id == item.id }) { items[existing] = item } else { items.append(item) }
        persist(); refreshHotKeys()
    }
    func delete(_ item: ShortcutItem) { items.removeAll { $0.id == item.id }; persist(); refreshHotKeys() }
    func conflict(for item: ShortcutItem) -> ShortcutItem? {
        items.first { $0.id != item.id && $0.isEnabled && $0.shortcut == item.shortcut }
    }
    func setHotKeyRecording(_ isRecording: Bool) { manager.isSuspended = isRecording }
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
        case .translate:
            Task { await translateSelection() }
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
    private func translateSelection() async {
        guard translationSettings.isEnabled else { lastError = "请先在设置中启用一个翻译服务"; return }
        guard let text = selectedText(), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { lastError = "没有读取到选中的文本。请先选择文字，并在“辅助功能”中允许 Veycomm。"; return }
        TranslationPanelPresenter.shared.show(text: text, settings: translationSettings)
    }
    private func selectedText() -> String? {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let element = focused else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element as! AXUIElement, kAXSelectedTextAttribute as CFString, &value) == .success else { return nil }
        return value as? String
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
    private let label = "com.veycomm.app"
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
    var onAccessibilityRequired: (() -> Void)?
    private var refs: [EventHotKeyRef] = []
    private var ids: [UInt32: UUID] = [:]
    private var shortcuts: [Shortcut: UUID] = [:]
    private var handler: EventHandlerRef?
    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?
    private var nextID: UInt32 = 1
    var isSuspended = false

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
    deinit {
        refs.forEach { UnregisterEventHotKey($0) }
        if let eventTapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapSource, .commonModes) }
        if let handler { RemoveEventHandler(handler) }
    }
    func register(_ items: [ShortcutItem]) {
        refs.forEach { UnregisterEventHotKey($0) }; refs.removeAll(); ids.removeAll(); nextID = 1
        shortcuts = Dictionary(uniqueKeysWithValues: items.map { ($0.shortcut, $0.id) })
        if installEventTap() { return }
        DispatchQueue.main.async { [weak self] in self?.onAccessibilityRequired?() }
        for item in items {
            let id = nextID; nextID += 1
            var ref: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: OSType(0x53534846), id: id)
            if RegisterEventHotKey(item.shortcut.keyCode, item.shortcut.modifiers, hotKeyID, GetEventDispatcherTarget(), 0, &ref) == noErr, let ref {
                refs.append(ref); ids[id] = item.id
            }
        }
    }

    private func installEventTap() -> Bool {
        if eventTap != nil { return true }
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else { return false }
        let mask = CGEventMask(1) << CGEventType.keyDown.rawValue
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userInfo).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = manager.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
                    return Unmanaged.passUnretained(event)
                }
                if manager.isSuspended { return Unmanaged.passUnretained(event) }
                let shortcut = Shortcut(
                    keyCode: UInt32(event.getIntegerValueField(.keyboardEventKeycode)),
                    modifiers: carbonModifiers(from: event.flags)
                )
                if let uuid = manager.shortcuts[shortcut] {
                    DispatchQueue.main.async { manager.onHotKey?(uuid) }
                    return nil
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        eventTapSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }
}
