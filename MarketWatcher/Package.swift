// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MarketWatcher",
    platforms: [.macOS(.v13)],
    targets: [
        // Library — all models, networking, viewmodels, and views.
        // The App/ subdirectory is excluded here; it lives in MarketWatcherApp below.
        // Assets.xcassets is processed here so the AppIcon is bundled with the library.
        .target(
            name: "MarketWatcher",
            path: "Sources/SP500Widget",
            exclude: ["App"],
            resources: [.process("Assets.xcassets")]
        ),
        // Executable — the app entry point and NSPanel shell.
        // Imports MarketWatcher as a library (types must be public there).
        .executableTarget(
            name: "MarketWatcherApp",
            dependencies: ["MarketWatcher"],
            path: "Sources/SP500Widget/App",
            exclude: ["Info.plist"]
        ),
        .testTarget(
            name: "MarketWatcherTests",
            dependencies: ["MarketWatcher"],
            path: "Tests/SP500WidgetTests",
            resources: [.copy("Fixtures")]
        )
    ]
)
