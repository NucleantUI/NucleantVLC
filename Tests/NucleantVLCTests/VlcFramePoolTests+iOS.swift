//
//  VlcFramePoolTests+iOS.swift
//  NucleantVLCTests
//
//  The iOS frame path, up to the IOSurface a view's texture is written
//  from: decoded at the video's size, fitted to any other size with the
//  video's shape kept and black around it. The surfaces are read back on
//  the CPU — here only, to check them.
//

#if os(iOS)
import Foundation
import IOSurface
import Testing
@testable import NucleantVLC

@MainActor
struct VlcFramePoolTests {

    /// A surface's pixel, as (r, g, b).
    private func pixel(_ surface: IOSurfaceRef, _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
        let p = bgra(surface, x, y)
        return (p[2], p[1], p[0])
    }

    private func alpha(_ surface: IOSurfaceRef, _ x: Int, _ y: Int) -> Int {
        bgra(surface, x, y)[3]
    }

    private func bgra(_ surface: IOSurfaceRef, _ x: Int, _ y: Int) -> [Int] {
        IOSurfaceLock(surface, .readOnly, nil)
        defer { IOSurfaceUnlock(surface, .readOnly, nil) }
        let row = IOSurfaceGetBaseAddress(surface).advanced(by: y * IOSurfaceGetBytesPerRow(surface))
        let bytes = row.advanced(by: x * 4).assumingMemoryBound(to: UInt8.self)
        return (0..<4).map { Int(bytes[$0]) }
    }

    private func isRed(_ p: (r: Int, g: Int, b: Int)) -> Bool { p.r > 200 && p.g < 60 && p.b < 60 }
    private func isGreen(_ p: (r: Int, g: Int, b: Int)) -> Bool { p.g > 150 && p.r < 80 && p.b < 80 }
    private func isBlack(_ p: (r: Int, g: Int, b: Int)) -> Bool { p.r < 16 && p.g < 16 && p.b < 16 }

    /// A remote playing `clip`, once its first frame has been taken.
    private func playing(_ clip: TestClip) async throws -> RecordingRemote {
        try await playing(try clip.write())
    }

    private func playing(_ url: URL) async throws -> RecordingRemote {
        let remote = RecordingRemote()
        try remote.open(url)
        let key = ObjectIdentifier(remote)
        let arrived = await waitUntil {
            remote.player.video.format != nil
                && remote.player.video.frames.frame(width: 8, height: 8, aspect: 1, for: key) != nil
        }
        try #require(arrived, "no frame")
        remote.player.video.frames.forget(key)
        return remote
    }

    @Test func framesArriveAtTheVideosSize() async throws {
        let clip = TestClip.red()
        let remote = try await playing(clip)
        let format = try #require(remote.player.video.format)
        #expect(format.width == clip.width)
        #expect(format.height == clip.height)
        #expect(format.sampleAspect == 1)

        let surface = try #require(remote.player.video.frames.frame(
            width: clip.width, height: clip.height, aspect: format.displayAspect, for: ObjectIdentifier(remote)
        ))
        #expect(IOSurfaceGetWidth(surface) == clip.width)
        #expect(IOSurfaceGetHeight(surface) == clip.height)
        #expect(isRed(pixel(surface, clip.width * 3 / 4, clip.height * 3 / 4)), "\(pixel(surface, 240, 135))")
        #expect(isGreen(pixel(surface, 10, 10)), "upright, not mirrored: \(pixel(surface, 10, 10))")
        #expect(alpha(surface, 200, 100) == 255, "opaque, or the view's background would show through")
    }

    @Test func aSquareTextureGetsTheVideoLetterboxed() async throws {
        let clip = TestClip.red()
        let remote = try await playing(clip)
        let format = try #require(remote.player.video.format)
        let surface = try #require(remote.player.video.frames.frame(
            width: 400, height: 400, aspect: format.displayAspect, for: ObjectIdentifier(remote)
        ))
        #expect(IOSurfaceGetWidth(surface) == 400)
        #expect(IOSurfaceGetHeight(surface) == 400)
        // 16:9 in 400×400: 400×225, from y 87 to 312.
        #expect(isBlack(pixel(surface, 200, 40)), "bar above: \(pixel(surface, 200, 40))")
        #expect(isBlack(pixel(surface, 200, 360)), "bar below: \(pixel(surface, 200, 360))")
        #expect(isRed(pixel(surface, 300, 250)), "\(pixel(surface, 300, 250))")
        #expect(isGreen(pixel(surface, 20, 100)), "the block, top-left of the picture: \(pixel(surface, 20, 100))")
    }

    @Test func aWideTextureGetsThePictureBetweenBars() async throws {
        let clip = TestClip.red()
        let remote = try await playing(clip)
        let surface = try #require(remote.player.video.frames.frame(
            width: 900, height: 300, aspect: 16.0 / 9, for: ObjectIdentifier(remote)
        ))
        // 16:9 in 900×300: 533×300, from x 183 to 717.
        #expect(isBlack(pixel(surface, 80, 150)), "bar left: \(pixel(surface, 80, 150))")
        #expect(isBlack(pixel(surface, 820, 150)), "bar right: \(pixel(surface, 820, 150))")
        #expect(isRed(pixel(surface, 600, 200)))
    }

    @Test func anAspectOfItsOwnFillsTheTexture() async throws {
        let clip = TestClip.red()
        let remote = try await playing(clip)
        let surface = try #require(remote.player.video.frames.frame(
            width: 400, height: 400, aspect: 1, for: ObjectIdentifier(remote)
        ))
        #expect(isRed(pixel(surface, 200, 380)), "no bars at the video's shape overridden to square")
        #expect(isGreen(pixel(surface, 20, 20)))
    }

    @Test func nonSquarePixelsAreShownWide() async throws {
        // 320×180 pixels twice as wide as tall: shown 640:180.
        let clip = TestClip.red(sampleAspect: (2, 1))
        let remote = try await playing(clip)
        let format = try #require(remote.player.video.format)
        #expect(format.sampleAspect == 2)
        #expect(abs(format.displayAspect - 640.0 / 180) < 0.001)

        let surface = try #require(remote.player.video.frames.frame(
            width: 640, height: 640, aspect: format.displayAspect, for: ObjectIdentifier(remote)
        ))
        // 640:180 in 640×640: 640×180, from y 230 to 410.
        #expect(isBlack(pixel(surface, 320, 200)), "bar above: \(pixel(surface, 320, 200))")
        #expect(isRed(pixel(surface, 320, 380)), "\(pixel(surface, 320, 380))")
        #expect(isBlack(pixel(surface, 320, 440)), "bar below: \(pixel(surface, 320, 440))")
    }

    @Test func paddedFramesShowThePictureAtItsShape() async throws {
        let url = try #require(Bundle.module.url(forResource: "padded", withExtension: "mp4"))
        let remote = try await playing(url)
        let format = try #require(remote.player.video.format)
        #expect(format.visibleWidth == 64)
        #expect(format.visibleHeight == 36)
        #expect(format.height > 36, "the decoder pads: \(format.width)×\(format.height)")
        #expect(abs(format.displayAspect - 64.0 / 36) < 0.001)
        let frames = remote.player.video.frames
        let key = ObjectIdentifier(remote)

        // At its own shape it fills the texture, top to bottom: the green
        // block at the top-left, the blue strip along the bottom.
        let own = try #require(frames.frame(width: 64, height: 36, aspect: format.displayAspect, for: key))
        #expect(isGreen(pixel(own, 4, 2)), "\(pixel(own, 4, 2))")
        #expect(isRed(pixel(own, 1, 18)), "\(pixel(own, 1, 18))")
        #expect(isRed(pixel(own, 62, 18)), "\(pixel(own, 62, 18))")
        let bottom = pixel(own, 40, 34)
        #expect(bottom.b > 150 && bottom.r < 90, "\(bottom)")

        // In a square, 16:9 — not the padded frame's shape.
        let square = try #require(frames.frame(width: 64, height: 64, aspect: format.displayAspect, for: key))
        #expect(isBlack(pixel(square, 32, 6)), "bar above: \(pixel(square, 32, 6))")
        #expect(isRed(pixel(square, 32, 30)), "\(pixel(square, 32, 30))")
        #expect(isBlack(pixel(square, 32, 58)), "bar below: \(pixel(square, 32, 58))")
    }

    @Test func subtitlesAreDrawnIntoTheFrames() async throws {
        let srt = FileManager.default.temporaryDirectory.appendingPathComponent("nucleantvlc-\(UUID().uuidString).srt")
        try "1\n00:00:00,000 --> 00:00:30,000\nWWWWWWWWWW\n\n".write(to: srt, atomically: true, encoding: .utf8)
        let media = try VlcMedia(url: try TestClip.red().write())
        #expect(media.addSlave(.subtitle, url: srt))

        let remote = RecordingRemote()
        remote.open(media)
        let key = ObjectIdentifier(remote)
        let frames = remote.player.video.frames
        // libvlc blends the text into the picture before the memory output
        // gets it: white letters over the red, along the bottom.
        let lettered = await waitUntil {
            guard let surface = frames.frame(width: 320, height: 180, aspect: 16.0 / 9, for: key) else { return false }
            var white = 0
            for y in stride(from: 120, to: 180, by: 2) {
                for x in stride(from: 0, to: 320, by: 2) {
                    let p = pixel(surface, x, y)
                    if p.r > 200, p.g > 200, p.b > 200 { white += 1 }
                }
            }
            return white > 20
        }
        #expect(lettered, "subtitle text in the frames")
        #expect(remote.player.subtitleTrack >= 0, "the subtitle file's track is selected")
    }

    @Test func framesKeepComing() async throws {
        let clip = TestClip(frameCount: 50)
        let remote = try await playing(clip)
        let key = ObjectIdentifier(remote)
        let frames = remote.player.video.frames
        let turnedBlue = await waitUntil {
            _ = remote.player.video.frames.takeLatest()
            guard let surface = frames.frame(width: 64, height: 36, aspect: 16.0 / 9, for: key) else { return false }
            let p = pixel(surface, 48, 27)
            return p.b > 200 && p.r < 60
        }
        #expect(turnedBlue, "the second second's frames reached the pool")
    }
}
#endif
