// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Chord",
    products: [
        .library(name: "ChordCore", targets: ["ChordCore"]),
        .executable(name: "Chord", targets: ["Chord"]),
    ],
    dependencies: [],
    targets: [
        .target(name: "ChordCore"),
        .executableTarget(name: "Chord", dependencies: ["ChordCore"]),
        .testTarget(name: "ChordCoreTests", dependencies: ["ChordCore"]),
    ]
)
