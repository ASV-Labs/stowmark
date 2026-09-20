// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Stowmark",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "LibraryCore", targets: ["LibraryCore"]),
        .executable(name: "Stowmark", targets: ["Stowmark"]),
        .executable(name: "StowmarkTool", targets: ["StowmarkTool"]),
        .executable(name: "StowmarkExtension", targets: ["StowmarkExtension"]),
        .executable(name: "StowmarkShare", targets: ["StowmarkShare"]),
        .executable(name: "StowmarkChromeHost", targets: ["StowmarkChromeHost"]),
    ],
    targets: [
        .target(
            name: "LibraryCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "Stowmark",
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
            name: "StowmarkTool",
            dependencies: ["LibraryCore"]
        ),
        .executableTarget(
            name: "StowmarkExtension",
            dependencies: ["LibraryCore"],
            swiftSettings: [.unsafeFlags(["-application-extension"])],
            linkerSettings: [
                .linkedFramework("SafariServices"),
                .unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain"]),
            ]
        ),
        .executableTarget(
            name: "StowmarkShare",
            dependencies: ["LibraryCore"],
            swiftSettings: [.unsafeFlags(["-application-extension"])],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("UniformTypeIdentifiers"),
                .unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain"]),
            ]
        ),
        .executableTarget(
            name: "StowmarkChromeHost",
            dependencies: ["LibraryCore"],
            linkerSettings: [.linkedFramework("AppKit")]
        ),
        .testTarget(name: "LibraryCoreTests", dependencies: ["LibraryCore"]),
    ]
)
