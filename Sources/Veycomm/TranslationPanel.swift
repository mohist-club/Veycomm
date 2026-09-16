import SwiftUI

@MainActor
final class TranslationPanelPresenter {
    static let shared = TranslationPanelPresenter()
    private var panel: NSPanel?
    func show(text: String, settings: TranslationSettings) {
        let view = TranslationPanel(text: text, settings: settings)
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 620, height: 410), styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        panel.contentView = NSHostingView(rootView: view)
        panel.title = "Veycomm 翻译"; panel.isFloatingPanel = true; panel.level = .floating; panel.center(); panel.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        self.panel = panel
    }
}

private struct TranslationPanel: View {
    let text: String
    @ObservedObject var settings: TranslationSettings
    @State private var target = ""
    @State private var result = "正在翻译…"
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Image(systemName: "pin.fill"); Spacer(); Image(systemName: "scissors"); Image(systemName: "slider.horizontal.3") }
                .foregroundStyle(.secondary)
            Text(text).font(.title3).textSelection(.enabled).lineLimit(4)
            HStack { Text("自动检测"); Image(systemName: "arrow.left.arrow.right"); Picker("目标语言", selection: $target) { Text("自动选择").tag(""); Text("简体中文").tag("ZH"); Text("English").tag("EN") }.pickerStyle(.menu) }
                .padding(10).background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
            Divider()
            HStack { Image(systemName: "globe"); Text(settings.provider.title).font(.headline); Spacer(); ProgressView().opacity(result == "正在翻译…" ? 1 : 0) }
            Text(result).font(.title3).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            HStack { Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(result, forType: .string) } label: { Image(systemName: "doc.on.doc") }; Spacer(); Button("关闭") { NSApp.keyWindow?.close() } }
        }.padding(20).frame(width: 620, height: 410).task(id: target) { await translate() }
    }
    private func translate() async { result = "正在翻译…"; do { let value = try await Translator.translate(text, target: target.isEmpty ? Translator.targetLanguage(for: text) : target, settings: settings); result = value.translatedText } catch { result = error.localizedDescription } }
}
