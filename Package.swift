// swift-tools-version: 5.9
import PackageDescription

// The package graph is platform-conditional on purpose.
//
// `CadenceCore` holds the entire domain — storage, habit inference, statistics,
// export — and imports nothing but Foundation and the system SQLite. It therefore
// compiles and runs its full test suite on Linux, which is what lets continuous
// integration verify the business logic on every commit.
//
// The `Cadence` executable is the macOS shell (SwiftUI, AppKit, EventKit) and only
// exists in the graph on macOS.

var products: [Product] = [
    .library(name: "CadenceCore", targets: ["CadenceCore"])
]

var targets: [Target] = [
    .systemLibrary(name: "CSQLite", path: "Sources/CSQLite"),
    .target(
        name: "CadenceCore",
        dependencies: ["CSQLite"],
        path: "Sources/CadenceCore"
    ),
    .testTarget(
        name: "CadenceCoreTests",
        dependencies: ["CadenceCore"],
        path: "Tests/CadenceCoreTests"
    ),
]

#if os(macOS)
products.append(.executable(name: "Cadence", targets: ["Cadence"]))
targets.append(
    .executableTarget(
        name: "Cadence",
        dependencies: ["CadenceCore"],
        path: "Sources/Cadence"
    )
)
#endif

let package = Package(
    name: "Cadence",
    platforms: [.macOS(.v14)],
    products: products,
    targets: targets
)
