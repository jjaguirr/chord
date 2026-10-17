// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Chord",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "ChordCore", targets: ["ChordCore"]),
        .executable(name: "Chord", targets: ["Chord"]),
    ],
    dependencies: [],
    targets: [
        .target(name: "ChordCore"),
        .executableTarget(name: "Chord", dependencies: ["ChordCore"]),
        .testTarget(name: "ChordCoreTests", dependencies: ["ChordCore"]),
        .testTarget(name: "ChordTests", dependencies: ["Chord", "ChordCore"]),
    ]
)
