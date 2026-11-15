//
//  Verifier.swift
//  NucleantVLCDemo
//
//  NUCLEANT_VLC_DEMO_VERIFY=<file.ppm>: play a test video with known
//  colors in the real window and read the view's texture back — that
//  frames arrive and keep arriving, in the right colors, the right way up,
//  fitted with black bars — then save the last frame read to <file.ppm>
//  and quit with the result.
//

import Foundation
import NucleantUI

@MainActor
final class Verifier {

    /// Start the check when the environment asks for it. True when it does.
    static func scheduleIfRequested(player: Player) -> Bool {
        guard let output = ProcessInfo.processInfo.environment["NUCLEANT_VLC_DEMO_VERIFY"] else { return false }
        let verifier = Verifier(player: player, output: URL(fileURLWithPath: output))
        Task { await verifier.run() }
        return true
    }

    private let player: Player
    private let output: URL
    private let video = TestVideo()
    private var report: [String] = []

    private init(player: Player, output: URL) {
        self.player = player
        self.output = output
    }

    /// A texture read back, top row first.
    private struct Frame {
        let width: Int, height: Int, stride: Int
        let bgra: [UInt8]

        func pixel(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
            let i = (y * stride + x) * 4
            return (Int(bgra[i + 2]), Int(bgra[i + 1]), Int(bgra[i]))
        }
    }

    private func run() async {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("nucleantvlc-verify.y4m")
        do {
            try video.write(to: file)
        } catch {
            finish("could not write the test video: \(error)", passed: false)
        }
        player.add([file], playing: true)

        var sawRed = false, sawBlue = false
        var last: Frame?
        var fitted = (x: 0, y: 0, width: 0, height: 0)
        let deadline = ContinuousClock.now + .seconds(15)
        while ContinuousClock.now < deadline, !(sawRed && sawBlue) {
            try? await Task.sleep(for: .milliseconds(40))
            guard let texture = player.player.video.textures.first, let read = texture.readPixels() else { continue }
            let frame = Frame(width: texture.pixelWidth, height: texture.pixelHeight, stride: read.width, bgra: read.bgra)
            last = frame
            fitted = video.fitted(in: frame.width, frame.height)
            let ground = frame.pixel(fitted.x + fitted.width * 3 / 4, fitted.y + fitted.height * 3 / 4)
            if ground.r > 200, ground.g < 60, ground.b < 60 { sawRed = true }
            if sawRed, ground.b > 200, ground.r < 60, ground.g < 60 { sawBlue = true }
        }

        report.append("frames: red \(sawRed ? "seen" : "MISSING"), then blue \(sawBlue ? "seen" : "MISSING")")
        var passed = sawRed && sawBlue
        guard let frame = last else {
            finish("no texture was ever written", passed: false)
        }
        let corner = frame.pixel(fitted.x + fitted.width / 16, fitted.y + fitted.height / 16)
        let upright = corner.g > 150 && corner.r < 80 && corner.b < 80
        report.append("top-left block green (upright, not mirrored): \(upright) \(corner)")
        passed = passed && upright
        if fitted.x > 2 || fitted.y > 2 {
            let bar = fitted.x > 2 ? frame.pixel(fitted.x / 2, frame.height / 2) : frame.pixel(frame.width / 2, fitted.y / 2)
            let black = bar.r < 16 && bar.g < 16 && bar.b < 16
            report.append("letterbox bars black: \(black) \(bar)")
            passed = passed && black
        }
        report.append("texture \(frame.width)×\(frame.height), picture fitted at \(fitted)")
        save(frame)
        finish("saved \(output.path)", passed: passed)
    }

    /// The frame as a binary PPM.
    private func save(_ frame: Frame) {
        var data = Data("P6\n\(frame.width) \(frame.height)\n255\n".utf8)
        data.reserveCapacity(data.count + frame.width * frame.height * 3)
        for y in 0..<frame.height {
            for x in 0..<frame.width {
                let p = frame.pixel(x, y)
                data.append(contentsOf: [UInt8(p.r), UInt8(p.g), UInt8(p.b)])
            }
        }
        try? data.write(to: output)
    }

    private func finish(_ last: String, passed: Bool) -> Never {
        report.append(last)
        print("NucleantVLC verify: \(passed ? "PASSED" : "FAILED")")
        report.forEach { print("  " + $0) }
        exit(passed ? 0 : 1)
    }
}

/// The test video, as YUV4MPEG2 — raw 4:2:0 frames libvlc plays without a
/// codec: 16:9, red for its first half and blue for its second, with a
/// green block in its top-left corner (a quarter of its width and height).
final class TestVideo {
    let width = 320
    let height = 180
    let frameCount = 50

    // BT.601, limited range, as (Y, Cb, Cr).
    private let red: (UInt8, UInt8, UInt8) = (81, 90, 240)
    private let blue: (UInt8, UInt8, UInt8) = (41, 240, 110)
    private let green: (UInt8, UInt8, UInt8) = (145, 54, 34)

    func write(to url: URL) throws {
        var data = Data("YUV4MPEG2 W\(width) H\(height) F25:1 Ip A1:1 C420jpeg\n".utf8)
        for index in 0..<frameCount {
            let ground = index < frameCount / 2 ? red : blue
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
    }

    /// Where the picture fits, kept 16:9, in a `width × height` texture.
    func fitted(in textureWidth: Int, _ textureHeight: Int) -> (x: Int, y: Int, width: Int, height: Int) {
        let scale = min(Double(textureWidth) / Double(width), Double(textureHeight) / Double(height))
        let w = Int((Double(width) * scale).rounded()), h = Int((Double(height) * scale).rounded())
        return ((textureWidth - w) / 2, (textureHeight - h) / 2, w, h)
    }
}
