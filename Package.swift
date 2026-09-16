// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Veycomm",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Veycomm", targets: ["Veycomm"])],
    targets: [.executableTarget(name: "Veycomm")]
)
