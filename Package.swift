// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import Foundation
import PackageDescription

/// Build against the sibling checkout (`../NucleantUI`) or against its
/// releases on GitHub.
///
/// GitHub unless `NUCLEANT_LOCAL_DEV=1` is in the environment: the sibling
/// checkout is used only when that turns it on, never just because it is
/// there.
let devMode: Bool = ["1", "true", "yes"].contains(
    (ProcessInfo.processInfo.environment["NUCLEANT_LOCAL_DEV"] ?? "").lowercased()
)

func getDependencies() -> [Package.Dependency] {
    if devMode {
        return [.package(path: "../NucleantUI")]
    }
    // By version, up to its next minor: its new 0.3.x releases are picked up
    // as they come; its 0.4.0 only once this line is moved to it.
    return [
        .package(url: "https://github.com/NucleantUI/NucleantUI.git", .upToNextMinor(from: "0.3.1")),
    ]
}

let package = Package(
    name: "NucleantVLC",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "NucleantVLC", targets: ["NucleantVLC"]),
        .executable(name: "NucleantVLCDemo", targets: ["NucleantVLCDemo"]),
    ],
    dependencies: getDependencies(),
    targets: [
        // libvlc 3.0.24 with libvlccore, its plugins and its headers, as one
        // framework — made by scripts/fetch_vlc.py. A binary target, so the
        // package links it without unsafe flags and builds as a dependency
        // as well as on its own.
        .binaryTarget(name: "LibVLC", path: "Dependencies/LibVLC.xcframework"),
        .target(
            name: "NucleantVLC",
            dependencies: [
                "LibVLC",
                .product(name: "NucleantUI", package: "NucleantUI"),
            ]
        ),
        .executableTarget(
            name: "NucleantVLCDemo",
            dependencies: [
                "NucleantVLC",
                .product(name: "NucleantUI", package: "NucleantUI"),
            ]
        ),
        .testTarget(
            name: "NucleantVLCTests",
            dependencies: [
                "NucleantVLC",
                "LibVLC",
                .product(name: "NucleantUI", package: "NucleantUI"),
            ],
            // A 64×36 H.264 clip: its stream is coded in 16-pixel blocks,
            // 64×48, and cropped back to 36 rows.
            resources: [.copy("Resources/padded.mp4")]
        ),
    ]
)
