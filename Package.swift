// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Cardfile",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "LibraryCore", targets: ["LibraryCore"]),
        .executable(name: "Cardfile", targets: ["Cardfile"]),
        .executable(name: "CardfileTool", targets: ["CardfileTool"]),
        .executable(name: "CardfileExtension", targets: ["CardfileExtension"]),
        .executable(name: "CardfileShare", targets: ["CardfileShare"]),
        .executable(name: "CardfileChromeHost", targets: ["CardfileChromeHost"]),
    ],
    targets: [
        .target(
            name: "LibraryCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "Cardfile",
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
            name: "CardfileTool",
            dependencies: ["LibraryCore"]
        ),
        .executableTarget(
            name: "CardfileExtension",
            dependencies: ["LibraryCore"],
            swiftSettings: [.unsafeFlags(["-application-extension"])],
            linkerSettings: [
                .linkedFramework("SafariServices"),
                .unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain"]),
            ]
        ),
        .executableTarget(
            name: "CardfileShare",
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
            name: "CardfileChromeHost",
            dependencies: ["LibraryCore"],
            linkerSettings: [.linkedFramework("AppKit")]
        ),
        .testTarget(name: "LibraryCoreTests", dependencies: ["LibraryCore"]),
    ]
)
