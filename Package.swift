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

/// Each libvlc archive on the latest GitHub release, by file name: its URL
/// and checksum. Written here by .github/workflows/release.yml, which commits
/// it to main with the release, so main and the release's tag both build
/// from exactly the archives on that release. In this file, not one it reads,
/// because SwiftPM caches a manifest's evaluation by its text (and
/// environment), not by the files it looks at. Empty only before the first
/// release.
let releasedVLC: [String: (url: String, checksum: String)] = [:]

/// With NUCLEANT_VLC_ARTIFACTS=1, the archives in Artifacts/: the ones
/// .github/workflows/build-deps.yml has just made, put there to build and
/// test against. They come before the release's, which they are about to
/// replace.
let localArtifacts = ProcessInfo.processInfo.environment["NUCLEANT_VLC_ARTIFACTS"] == "1"

/// libvlc 3.0.24 with libvlccore, its plugins and its headers, as one
/// framework per Apple platform: from Artifacts/ (above), else from the
/// release. Before the first release, it is the one scripts/fetch_vlc.py
/// makes in Dependencies/. A binary target, so the package links it without
/// unsafe flags and builds as a dependency as well as on its own.
func libVLC() -> Target {
    let archive = "LibVLC.xcframework.zip"
    if localArtifacts {
        return .binaryTarget(name: "LibVLC", path: "Artifacts/\(archive)")
    }
    if let release = releasedVLC[archive] {
        return .binaryTarget(name: "LibVLC", url: release.url, checksum: release.checksum)
    }
    return .binaryTarget(name: "LibVLC", path: "Dependencies/LibVLC.xcframework")
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
        libVLC(),
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
