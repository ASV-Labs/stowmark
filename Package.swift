// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MyMind",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "LibraryCore", targets: ["LibraryCore"]),
        .executable(name: "MyMind", targets: ["MyMind"]),
        .executable(name: "MyMindTool", targets: ["MyMindTool"]),
        .executable(name: "MyMindExtension", targets: ["MyMindExtension"]),
    ],
    targets: [
        .target(
            name: "LibraryCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "MyMind",
            dependencies: ["LibraryCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AppIntents"),
                .linkedFramework("SafariServices"),
                .linkedFramework("LinkPresentation"),
                .linkedFramework("WebKit"),
            ]
        ),
        .executableTarget(
            name: "MyMindTool",
            dependencies: ["LibraryCore"]
        ),
        .executableTarget(
            name: "MyMindExtension",
            dependencies: ["LibraryCore"],
            swiftSettings: [.unsafeFlags(["-application-extension"])],
            linkerSettings: [
                .linkedFramework("SafariServices"),
                .unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain"]),
            ]
        ),
        .testTarget(name: "LibraryCoreTests", dependencies: ["LibraryCore"]),
    ]
)
