// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Core",
    defaultLocalization: "en",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "ProviderKit", targets: ["ProviderKit"]),
        .library(name: "ClaudeProvider", targets: ["ClaudeProvider"]),
        .library(name: "CodexProvider", targets: ["CodexProvider"]),
        .library(name: "Credentials", targets: ["Credentials"]),
        .library(name: "Monitoring", targets: ["Monitoring"]),
        .library(name: "Preferences", targets: ["Preferences"]),
        .library(name: "StatusUI", targets: ["StatusUI"]),
        .library(name: "Updates", targets: ["Updates"]),
    ],
    targets: [
        .target(name: "ProviderKit"),
        .target(name: "ClaudeProvider", dependencies: ["ProviderKit"]),
        .target(name: "CodexProvider", dependencies: ["ProviderKit"]),
        .target(name: "Credentials", dependencies: ["ProviderKit", "ClaudeProvider"]),
        .target(name: "Monitoring", dependencies: ["ProviderKit", "Preferences"]),
        .target(name: "Preferences", dependencies: ["ProviderKit"]),
        // Depends on ClaudeProvider for HTTPClient: that file is the one
        // place in the project where a URL becomes traffic, and Credentials
        // depends on it for the same reason.
        .target(name: "Updates", dependencies: ["ProviderKit", "ClaudeProvider"]),
        .target(
            name: "StatusUI",
            dependencies: ["ProviderKit", "Preferences", "Monitoring"],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "ProviderKitTests", dependencies: ["ProviderKit"]),
        .testTarget(name: "ClaudeProviderTests", dependencies: ["ClaudeProvider"]),
        .testTarget(name: "CodexProviderTests", dependencies: ["CodexProvider"]),
        .testTarget(name: "CredentialsTests", dependencies: ["Credentials"]),
        .testTarget(name: "MonitoringTests", dependencies: ["Monitoring"]),
        .testTarget(name: "PreferencesTests", dependencies: ["Preferences"]),
        .testTarget(name: "StatusUITests", dependencies: ["StatusUI"]),
        .testTarget(name: "UpdatesTests", dependencies: ["Updates"]),
    ]
)
