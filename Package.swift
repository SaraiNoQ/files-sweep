// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FileSweep",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "FileSweepCore", targets: ["FileSweepCore"]),
        .executable(name: "filesweep-bench", targets: ["FileSweepBench"]),
        .executable(name: "FileSweep", targets: ["FileSweep"]),
        .executable(name: "filesweep-checks", targets: ["FileSweepChecks"])
    ],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .target(name: "FileSweepCore", dependencies: ["CSQLite"]),
        .executableTarget(name: "FileSweepBench", dependencies: ["FileSweepCore"]),
        .executableTarget(name: "FileSweep", dependencies: ["FileSweepCore"]),
        .executableTarget(name: "FileSweepChecks", dependencies: ["FileSweepCore", "CSQLite"], path: "Tests/FileSweepCoreTests")
    ]
)
