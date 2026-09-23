// swift-tools-version:5.7
//
// Test harness for MiliControl's pure logic (grid layout + navigation).
// The app itself is built with MiliControl.xcodeproj; this package only
// exists so the core rules can be verified with:
//
//     swift test
//
import PackageDescription

let package = Package(
    name: "MiliCore",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "MiliCore", path: "MiliControl/Core"),
        .testTarget(name: "MiliCoreTests", dependencies: ["MiliCore"], path: "Tests/MiliCoreTests"),
    ]
)
