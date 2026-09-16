// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ShortcutShelf",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "ShortcutShelf", targets: ["ShortcutShelf"])],
    targets: [.executableTarget(name: "ShortcutShelf")]
)
