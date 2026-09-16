import AppKit
import NaturalLanguage
import Security

enum TranslationProvider: String, CaseIterable, Identifiable {
    case openAI, deepL, google
    var id: String { rawValue }
    var title: String { switch self { case .openAI: "OpenAI"; case .deepL: "DeepL"; case .google: "Google Cloud" } }
}

@MainActor
final class TranslationSettings: ObservableObject {
    @Published var provider: TranslationProvider { didSet { defaults.set(provider.rawValue, forKey: "translation-provider") } }
    @Published var isEnabled: Bool { didSet { defaults.set(isEnabled, forKey: "translation-enabled") } }
    @Published var openAIModel: String { didSet { defaults.set(openAIModel, forKey: "openai-model") } }
    @Published var googleProjectID: String { didSet { defaults.set(googleProjectID, forKey: "google-project") } }
    private let defaults = UserDefaults.standard
    init() {
        provider = TranslationProvider(rawValue: UserDefaults.standard.string(forKey: "translation-provider") ?? "openAI") ?? .openAI
        isEnabled = UserDefaults.standard.bool(forKey: "translation-enabled")
        openAIModel = UserDefaults.standard.string(forKey: "openai-model") ?? "gpt-4.1-mini"
        googleProjectID = UserDefaults.standard.string(forKey: "google-project") ?? ""
    }
    func apiKey() -> String { Keychain.value(for: "translation-\(provider.rawValue)") ?? "" }
    func saveAPIKey(_ key: String) throws { try Keychain.save(key, for: "translation-\(provider.rawValue)") }
}

enum Keychain {
    static func value(for account: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.veycomm.translation", kSecAttrAccount as String: account, kSecReturnData as String: true]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func save(_ value: String, for account: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.veycomm.translation", kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        var item = query; item[kSecValueData as String] = Data(value.utf8)
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw CocoaError(.fileWriteUnknown) }
    }
}

struct TranslationResult { let sourceLanguage: String; let targetLanguage: String; let translatedText: String }

enum Translator {
    static func targetLanguage(for text: String) -> String {
        let recognizer = NLLanguageRecognizer(); recognizer.processString(text)
        let language = recognizer.dominantLanguage
        return language == .simplifiedChinese || language == .traditionalChinese ? "EN" : "ZH"
    }
    @MainActor static func translate(_ text: String, target: String, settings: TranslationSettings) async throws -> TranslationResult {
        let key = settings.apiKey(); guard !key.isEmpty else { throw TranslationError.missingKey(settings.provider) }
        switch settings.provider {
        case .deepL: return try await deepL(text, target, key)
        case .openAI: return try await openAI(text, target, key, settings.openAIModel)
        case .google: return try await google(text, target, key)
        }
    }
    private static func send(_ request: URLRequest) async throws -> Data { let (data, response) = try await URLSession.shared.data(for: request); guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { throw TranslationError.network }; return data }
    private static func deepL(_ text: String, _ target: String, _ key: String) async throws -> TranslationResult {
        var request = URLRequest(url: URL(string: "https://api.deepl.com/v2/translate")!); request.httpMethod = "POST"; request.setValue("DeepL-Auth-Key \(key)", forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = try JSONSerialization.data(withJSONObject: ["text": [text], "target_lang": target])
        let data = try await send(request); let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]; let first = (json?["translations"] as? [[String: Any]])?.first
        guard let translated = first?["text"] as? String else { throw TranslationError.network }; return TranslationResult(sourceLanguage: first?["detected_source_language"] as? String ?? "自动检测", targetLanguage: target, translatedText: translated)
    }
    private static func google(_ text: String, _ target: String, _ key: String) async throws -> TranslationResult {
        var parts = URLComponents(string: "https://translation.googleapis.com/language/translate/v2")!; parts.queryItems = [URLQueryItem(name: "key", value: key)]
        var request = URLRequest(url: parts.url!); request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = try JSONSerialization.data(withJSONObject: ["q": text, "target": target])
        let data = try await send(request); let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]; let first = ((json?["data"] as? [String: Any])?["translations"] as? [[String: Any]])?.first
        guard let translated = first?["translatedText"] as? String else { throw TranslationError.network }; return TranslationResult(sourceLanguage: first?["detectedSourceLanguage"] as? String ?? "自动检测", targetLanguage: target, translatedText: translated)
    }
    private static func openAI(_ text: String, _ target: String, _ key: String, _ model: String) async throws -> TranslationResult {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!); request.httpMethod = "POST"; request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let prompt = "Translate the following text to \(target). Return only the translation, preserving formatting. Text: \(text)"
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": model, "input": prompt])
        let data = try await send(request); let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let output = json?["output"] as? [[String: Any]], let content = output.first?["content"] as? [[String: Any]], let translated = content.first?["text"] as? String else { throw TranslationError.network }
        return TranslationResult(sourceLanguage: "自动检测", targetLanguage: target, translatedText: translated)
    }
}

enum TranslationError: LocalizedError { case missingKey(TranslationProvider), network
    var errorDescription: String? { switch self { case .missingKey(let provider): "请先在设置中填写 \(provider.title) API Key"; case .network: "翻译服务未返回有效结果" } }
}
