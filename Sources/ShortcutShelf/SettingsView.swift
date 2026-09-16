import SwiftUI
import Carbon.HIToolbox

struct SettingsView: View {
    @EnvironmentObject private var store: ShortcutStore
    @State private var selection: UUID?
    @State private var showingEditor = false
    @State private var draft = ShortcutItem.example

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(store.items) { item in
                    HStack { Text(item.name); Spacer(); Text(item.shortcut.display).foregroundStyle(.secondary) }
                        .tag(item.id)
                }
            }
            .navigationTitle("快捷键")
            .toolbar {
                Button { draft = ShortcutItem.example; showingEditor = true } label: { Image(systemName: "plus") }
                Button { if let selected = store.items.first(where: { $0.id == selection }) { store.delete(selected); selection = nil } } label: { Image(systemName: "minus") }
                    .disabled(selection == nil)
            }
        } detail: {
            if let item = store.items.first(where: { $0.id == selection }) {
                ShortcutDetail(item: item, onEdit: { draft = item; showingEditor = true })
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "command").font(.largeTitle).foregroundStyle(.secondary)
                    Text("选择一个快捷键").font(.headline)
                    Text("或点 + 创建新快捷键").foregroundStyle(.secondary)
                }
            }
        }
        .frame(minWidth: 720, minHeight: 440)
        .sheet(isPresented: $showingEditor) { ShortcutEditor(item: $draft) { saved in store.save(saved); selection = saved.id } }
        .alert("ShortcutShelf", isPresented: Binding(get: { store.lastError != nil }, set: { if !$0 { store.lastError = nil } })) { Button("好", role: .cancel) {} } message: { Text(store.lastError ?? "") }
        .alert("登录启动", isPresented: Binding(get: { store.statusMessage != nil }, set: { if !$0 { store.statusMessage = nil } })) { Button("好", role: .cancel) {} } message: { Text(store.statusMessage ?? "") }
    }
}

private struct ShortcutDetail: View {
    let item: ShortcutItem; let onEdit: () -> Void
    var body: some View { Form {
        LabeledContent("名称", value: item.name); LabeledContent("快捷键", value: item.shortcut.display); LabeledContent("动作", value: item.action.title)
        Text(item.payload).textSelection(.enabled)
        Toggle("已启用", isOn: .constant(item.isEnabled)).disabled(true)
        Button("编辑", action: onEdit)
    }.padding() }
}

private struct ShortcutEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: ShortcutStore
    @Binding var item: ShortcutItem
    let onSave: (ShortcutItem) -> Void
    @State private var isRecording = false
    @State private var warning: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("快捷键").font(.title2.bold())
            Form {
                TextField("名称", text: $item.name)
                Picker("动作", selection: $item.action) { ForEach(ShortcutAction.allCases) { Text($0.title).tag($0) } }
                payloadField
                HStack { Text("组合键"); Spacer(); KeyRecorder(shortcut: $item.shortcut, isRecording: $isRecording, onRecordingState: store.setHotKeyRecording) }
                Toggle("已启用", isOn: $item.isEnabled)
            }
            if let warning { Label(warning, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
            HStack { Spacer(); Button("取消") { dismiss() }; Button("保存") { save() }.keyboardShortcut(.defaultAction).disabled(item.name.trimmingCharacters(in: .whitespaces).isEmpty || item.payload.isEmpty) }
        }.padding().frame(width: 500)
    }
    @ViewBuilder
    private var payloadField: some View {
        switch item.action {
        case .application:
            HStack {
                TextField("", text: $item.payload, prompt: Text(item.action.placeholder))
                Button("选择应用…", action: chooseApplication)
            }
        case .url:
            HStack {
                TextField("", text: $item.payload, prompt: Text(item.action.placeholder))
                Button("选择文件…", action: chooseFile)
            }
        case .shell, .text:
            TextField(item.action.placeholder, text: $item.payload, axis: .vertical).lineLimit(2...4)
        }
    }
    private func save() { if let conflict = store.conflict(for: item) { warning = "与“\(conflict.name)”使用相同快捷键"; return }; onSave(item); dismiss() }
    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.title = "选择要打开的应用"
        panel.message = "选择一个 .app 应用程序"
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            item.payload = url.path
            if item.name == ShortcutItem.example.name { item.name = "打开 \(url.deletingPathExtension().lastPathComponent)" }
        }
    }
    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.title = "选择文件"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url { item.payload = url.path }
    }
}

private struct KeyRecorder: NSViewRepresentable {
    @Binding var shortcut: Shortcut
    @Binding var isRecording: Bool
    let onRecordingState: (Bool) -> Void
    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.onRecord = { code, modifiers in
            shortcut = Shortcut(keyCode: code, modifiers: modifiers)
            isRecording = false
            onRecordingState(false)
        }
        button.onState = { active in
            isRecording = active
            onRecordingState(active)
        }
        button.shortcut = shortcut
        return button
    }
    func updateNSView(_ view: RecorderButton, context: Context) { view.shortcut = shortcut; view.isRecording = isRecording }
}

private final class RecorderButton: NSButton {
    var shortcut = Shortcut(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(NSEvent.ModifierFlags.command.rawValue)) { didSet { if !isRecording { title = shortcut.display } } }
    var isRecording = false { didSet { title = isRecording ? "按下组合键…" : shortcut.display; if isRecording { window?.makeFirstResponder(self) } } }
    var onRecord: ((UInt32, UInt32) -> Void)?; var onState: ((Bool) -> Void)?
    override init(frame frameRect: NSRect) { super.init(frame: frameRect); bezelStyle = .rounded; target = self; action = #selector(start) }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func start() { isRecording = true; onState?(true) }
    override func keyDown(with event: NSEvent) {
        guard isRecording else { super.keyDown(with: event); return }
        if event.keyCode == UInt16(kVK_Escape) { isRecording = false; onState?(false); return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let allowed: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        guard !flags.intersection(allowed).isEmpty else { NSSound.beep(); return }
        onRecord?(UInt32(event.keyCode), carbonModifiers(from: flags))
    }
}
