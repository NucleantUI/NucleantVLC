//
//  TestClip.swift
//  NucleantVLCTests
//
//  Videos with known colors, written as YUV4MPEG2 — raw 4:2:0 frames
//  libvlc plays with no codec at all: red for the first half, blue for the
//  second, a green block in the top-left corner (a quarter of the width
//  and height). And a recording remote that keeps what the player reports.
//

import Foundation
@testable import NucleantVLC

final class TestClip {
    let width: Int
    let height: Int
    let frameCount: Int
    /// 25 frames per second.
    let frameRate = 25
    /// The pixels' shape, as YUV4MPEG2's "A" field.
    let sampleAspect: (Int, Int)
    /// The first blue frame — `frameCount` for a clip red throughout.
    let blueFrom: Int

    // BT.601, limited range, as (Y, Cb, Cr).
    private let red: (UInt8, UInt8, UInt8) = (81, 90, 240)
    private let blue: (UInt8, UInt8, UInt8) = (41, 240, 110)
    private let green: (UInt8, UInt8, UInt8) = (145, 54, 34)

    init(
        width: Int = 320,
        height: Int = 180,
        frameCount: Int = 50,
        sampleAspect: (Int, Int) = (1, 1),
        blueFrom: Int? = nil
    ) {
        self.width = width
        self.height = height
        self.frameCount = frameCount
        self.sampleAspect = sampleAspect
        self.blueFrom = blueFrom ?? frameCount / 2
    }

    /// Red throughout: what a frame shows doesn't depend on when it is read.
    static func red(frameCount: Int = 250, sampleAspect: (Int, Int) = (1, 1)) -> TestClip {
        TestClip(frameCount: frameCount, sampleAspect: sampleAspect, blueFrom: frameCount)
    }

    var duration: Duration { .milliseconds(frameCount * 1000 / frameRate) }

    /// Write the clip to a file of its own; returns where.
    func write() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nucleantvlc-\(UUID().uuidString).y4m")
        var data = Data("YUV4MPEG2 W\(width) H\(height) F\(frameRate):1 Ip A\(sampleAspect.0):\(sampleAspect.1) C420jpeg\n".utf8)
        for index in 0..<frameCount {
            let ground = index < blueFrom ? red : blue
            data.append(contentsOf: Array("FRAME\n".utf8))
            for plane in 0..<3 {
                let w = plane == 0 ? width : width / 2, h = plane == 0 ? height : height / 2
                for y in 0..<h {
                    for x in 0..<w {
                        let color = x < w / 4 && y < h / 4 ? green : ground
                        data.append(plane == 0 ? color.0 : plane == 1 ? color.1 : color.2)
                    }
                }
            }
        }
        try data.write(to: url)
        return url
    }
}

/// Keeps every event its player sends.
@MainActor
final class RecordingRemote: VlcRemote {
    let player = VlcMediaPlayer()

    var states: [VlcState] = []
    var times: [Duration] = []
    var length: Duration?
    var videoOutputs: [Int] = []
    var mediaChanges = 0
    var tracksChanges = 0
    var reachedEnd = false

    func stateDidChange(_ state: VlcState) { states.append(state) }
    func timeDidChange(_ time: Duration) { times.append(time) }
    func lengthDidChange(_ length: Duration) { self.length = length }
    func videoOutputsDidChange(_ count: Int) { videoOutputs.append(count) }
    func mediaDidChange() { mediaChanges += 1 }
    func tracksDidChange() { tracksChanges += 1 }
    func didReachEnd() { reachedEnd = true }
}

/// Wait, letting the main queue run (where events arrive), until `done`
/// or `timeout`. Returns `done()`.
@MainActor
func waitUntil(_ timeout: Duration = .seconds(10), _ done: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while !done(), ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(20))
    }
    return done()
}
