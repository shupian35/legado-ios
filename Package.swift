// swift-tools-version: 6.0
import PackageDescription

// MARK: - Target layout
//
//  LegadoCore    pure-Swift, platform-independent engine (rule DSL, models, storage,
//                network pipeline, local-book parsing). Compiles and unit-tests on
//                Linux / Windows / macOS — this is what CI verifies on every push.
//
//  LegadoServer  cross-platform HTTP + WebSocket API (the `legado://` web-service
//                feature of the Android app), usable from a Mac as well as iOS.
//
//  LegadoUIShim  a tiny stand-in for SwiftUI so that the shared view layer can be
//                type-checked on Linux. It is only imported on non-Apple platforms.
//
//  LegadoUI      the shared SwiftUI view layer (bookshelf, book detail, reader,
//                discovery, RSS, settings). It imports the real SwiftUI on Apple
//                platforms and the shim everywhere else, so the same sources are
//                compiled by the Linux CI job.
//
//  LegadoApp     the `@main` app shell. On Apple platforms it drives the real
//                SwiftUI; on Linux it is compiled against the shim so the entry
//                point is type-checked by the CI as well.
//
// The Android source of truth lives in ../legado; every ported file records the
// upstream path it mirrors in its header comment.

// The SwiftUI stand-in only exists on the platforms without SwiftUI. When the
// package is built for iOS or macOS the manifest is compiled with `os(macOS)`
// true, so the shim is not even declared and never ships inside the app.
#if os(macOS)
let uiShimTarget: Target? = nil
let uiDependencies: [Target.Dependency] = ["LegadoCore"]
#else
let uiShimTarget: Target? = .target(
    name: "LegadoUIShim",
    swiftSettings: [.swiftLanguageMode(.v5)]
)
let uiDependencies: [Target.Dependency] = ["LegadoCore", "LegadoUIShim"]
#endif

var targets: [Target] = [
    // zlib bridge — the system zlib (present on iOS/macOS and on Linux via
    // zlib1g-dev) is used to inflate the DEFLATE entries of EPUB/UMD archives.
    .target(
        name: "CZlib",
        cSettings: [.headerSearchPath("include")],
        linkerSettings: [.linkedLibrary("z")]
    ),
    .target(
        name: "LegadoCore",
        dependencies: [
            // HTML parsing + CSS selection — the Swift port of jsoup, which the
            // Android app uses through `AnalyzeByJSoup`.
            .product(name: "SwiftSoup", package: "SwiftSoup"),
            "CZlib"
        ],
        swiftSettings: [.swiftLanguageMode(.v5)]
    ),
    .target(
        name: "LegadoServer",
        dependencies: ["LegadoCore"],
        // The upstream web bookshelf — the built Vue 3 bundle of
        // `modules/web`, copied verbatim from
        // `app/src/main/assets/web/vue`. It is served by the local API so the
        // port behaves exactly like the Android app in the browser.
        resources: [.copy("Resources/WebUI")],
        swiftSettings: [.swiftLanguageMode(.v5)]
    ),
    // The shared view layer.
    .target(
        name: "LegadoUI",
        dependencies: uiDependencies,
        swiftSettings: [.swiftLanguageMode(.v5)]
    ),
    .testTarget(
        name: "LegadoCoreTests",
        dependencies: ["LegadoCore", "CZlib"],
        swiftSettings: [.swiftLanguageMode(.v5)]
    ),
    .testTarget(
        name: "LegadoServerTests",
        dependencies: ["LegadoServer"],
        swiftSettings: [.swiftLanguageMode(.v5)]
    ),
    // The `@main` app shell. It is compiled on every platform: on Apple
    // platforms it drives the real SwiftUI, on Linux it is type-checked against
    // the shim (the executable itself does nothing there).
    .executableTarget(
        name: "LegadoApp",
        dependencies: ["LegadoCore", "LegadoServer", "LegadoUI"],
        path: "Sources/LegadoApp",
        swiftSettings: [.swiftLanguageMode(.v5)]
    ),
]

if let uiShimTarget {
    targets.append(uiShimTarget)
}

var products: [Product] = [
    .library(name: "LegadoCore", targets: ["LegadoCore"]),
    .library(name: "LegadoServer", targets: ["LegadoServer"]),
    .library(name: "LegadoUI", targets: ["LegadoUI"]),
    .executable(name: "LegadoApp", targets: ["LegadoApp"]),
]

let package = Package(
    name: "legado-ios",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: products,
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.8.0")
    ],
    targets: targets
)
