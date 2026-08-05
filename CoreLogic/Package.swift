// swift-tools-version:5.9
// GymLogCore — pure-Swift, platform-independent core of the Gym Log app.
// Contains: NumberNormalizer, SetParser, ExerciseCatalog (spec §7, §17).
// No iOS dependencies, so it builds & tests on macOS, Linux, and Windows.
// The Xcode app target will depend on this package.
import PackageDescription

let package = Package(
    name: "GymLogCore",
    products: [
        .library(name: "GymLogCore", targets: ["GymLogCore"])
    ],
    targets: [
        .target(name: "GymLogCore"),
        .testTarget(name: "GymLogCoreTests", dependencies: ["GymLogCore"])
    ]
)
