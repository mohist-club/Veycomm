import Foundation
import AppKit

@MainActor
final class UpdateChecker: ObservableObject {
    @Published var automaticallyChecks = true { didSet { UserDefaults.standard.set(automaticallyChecks, forKey: "update-auto-check") } }
    @Published private(set) var state: State = .idle
    enum State: Equatable { case idle, checking, upToDate, available(String, URL), failed(String) }
    private let latestURL = URL(string: "https://api.github.com/repos/mohist-club/Veycomm/releases/latest")!
    init() { automaticallyChecks = !UserDefaults.standard.objectIsForced(forKey: "update-auto-check") ? UserDefaults.standard.object(forKey: "update-auto-check") as? Bool ?? true : true }
    func check() async {
        state = .checking
        do {
            var request = URLRequest(url: latestURL); request.setValue("Veycomm", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { throw UpdateError.network }
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let latest = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
            let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
            guard isNewer(latest, than: current) else { state = .upToDate; return }
            guard let url = release.assets.first(where: { $0.name.hasSuffix(".dmg") })?.browserDownloadURL else { throw UpdateError.noAsset }
            state = .available(latest, url)
        } catch { state = .failed("无法检查更新") }
    }
    func download() { if case .available(_, let url) = state { NSWorkspace.shared.open(url) } }
    private func isNewer(_ lhs: String, than rhs: String) -> Bool {
        let a = lhs.split(separator: ".").map { Int($0) ?? 0 }, b = rhs.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(a.count, b.count) { let x = index < a.count ? a[index] : 0, y = index < b.count ? b[index] : 0; if x != y { return x > y } }
        return false
    }
    private struct GitHubRelease: Decodable { let tagName: String; let assets: [Asset]; enum CodingKeys: String, CodingKey { case tagName = "tag_name", assets }; struct Asset: Decodable { let name: String; let browserDownloadURL: URL; enum CodingKeys: String, CodingKey { case name; case browserDownloadURL = "browser_download_url" } } }
    private enum UpdateError: Error { case network, noAsset }
}
