// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "PlaybookWorkbench", platforms: [.macOS(.v14)], products: [.executable(name: "PlaybookWorkbench", targets: ["PlaybookWorkbench"])], targets: [.executableTarget(name: "PlaybookWorkbench")])
