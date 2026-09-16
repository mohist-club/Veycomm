import AppKit
import Carbon.HIToolbox

enum ShortcutAction: String, Codable, CaseIterable, Identifiable {
    case application, url, shell, text, translate

    var id: String { rawValue }
    var title: String {
        switch self {
        case .application: "打开应用"
        case .url: "打开链接或文件"
        case .shell: "执行 Shell 脚本"
        case .text: "粘贴文本"
        case .translate: "划词翻译"
        }
    }
    var placeholder: String {
        switch self {
        case .application: "/Applications/Safari.app"
        case .url: "https://example.com 或 /Users/name/file"
        case .shell: "open -a Safari"
        case .text: "要输入的文字"
        case .translate: "无需填写"
        }
    }
}

struct Shortcut: Codable, Hashable {
    var keyCode: UInt32
    var modifiers: UInt32

    var display: String {
        var result = ""
        if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        return result + keyName(keyCode)
    }

    private func keyName(_ code: UInt32) -> String {
        let names: [UInt32: String] = [
            UInt32(kVK_Return): "↩", UInt32(kVK_Space): "Space", UInt32(kVK_Tab): "⇥",
            UInt32(kVK_Escape): "⎋", UInt32(kVK_Delete): "⌫",
            UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3", UInt32(kVK_F4): "F4",
            UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6", UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8",
            UInt32(kVK_F9): "F9", UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12"
        ]
        if let known = names[code] { return known }
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let data = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return "?" }
        let layout = unsafeBitCast(data, to: CFData.self)
        guard let ptr = CFDataGetBytePtr(layout) else { return "?" }
        return ptr.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { keyboardLayout in
            var deadKeyState: UInt32 = 0
            var chars: [UniChar] = [0, 0, 0, 0]
            var length = 0
            let result = UCKeyTranslate(keyboardLayout, UInt16(code), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()), 0, &deadKeyState, chars.count, &length, &chars)
            return result == noErr && length > 0 ? String(utf16CodeUnits: chars, count: length).uppercased() : "?"
        }
    }
}

func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
    var result: UInt32 = 0
    if flags.contains(.command) { result |= UInt32(cmdKey) }
    if flags.contains(.option) { result |= UInt32(optionKey) }
    if flags.contains(.control) { result |= UInt32(controlKey) }
    if flags.contains(.shift) { result |= UInt32(shiftKey) }
    return result
}

func carbonModifiers(from flags: CGEventFlags) -> UInt32 {
    var result: UInt32 = 0
    if flags.contains(.maskCommand) { result |= UInt32(cmdKey) }
    if flags.contains(.maskAlternate) { result |= UInt32(optionKey) }
    if flags.contains(.maskControl) { result |= UInt32(controlKey) }
    if flags.contains(.maskShift) { result |= UInt32(shiftKey) }
    return result
}

struct ShortcutItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var action: ShortcutAction
    var payload: String
    var shortcut: Shortcut
    var isEnabled = true

    static let example = ShortcutItem(name: "打开 Safari", action: .application, payload: "/Applications/Safari.app", shortcut: Shortcut(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(cmdKey)))
}
