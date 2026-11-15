//
//  VlcPlayerTests.swift
//  NucleantVLCTests
//
//  A player driven through a remote: its events, in order, on the main
//  actor; its transport.
//

import Foundation
import Testing
@testable import NucleantVLC

@MainActor
struct VlcPlayerTests {

    @Test func aClipPlaysToItsEnd() async throws {
        let clip = TestClip()
        let remote = RecordingRemote()
        try remote.open(try clip.write())

        #expect(await waitUntil { remote.states.contains(.playing) }, "\(remote.states)")
        #expect(await waitUntil { remote.reachedEnd }, "\(remote.states)")
        // libvlc may report the input stopping after the end.
        let end = try #require(remote.states.firstIndex(of: .ended), "\(remote.states)")
        #expect(remote.states[end...].allSatisfy { $0 == .ended || $0 == .stopped }, "\(remote.states)")
        #expect(remote.states.firstIndex(of: .opening)! < remote.states.firstIndex(of: .playing)!)
        #expect(remote.mediaChanges == 1)
        #expect(remote.videoOutputs.contains(1), "one video output opened")

        let length = try #require(remote.length)
        #expect(abs((length - clip.duration).components.seconds) == 0, "\(length)")
        #expect(remote.times.count > 3)
        #expect(remote.times == remote.times.sorted(), "time only moves on")
    }

    @Test func pauseAndResume() async throws {
        let remote = RecordingRemote()
        try remote.open(try TestClip(frameCount: 250).write())
        #expect(await waitUntil { remote.states.last == .playing })
        #expect(remote.player.isPlaying)
        #expect(remote.player.canPause)

        remote.pause()
        #expect(await waitUntil { remote.states.last == .paused })
        #expect(!remote.player.isPlaying)

        remote.togglePause()
        #expect(await waitUntil { remote.states.last == .playing })
        remote.stop()
        let stopped = await waitUntil { remote.states.last == .stopped }
        #expect(stopped, "\(remote.states)")
    }

    @Test func seekingMovesTheTime() async throws {
        let remote = RecordingRemote()
        try remote.open(try TestClip(frameCount: 250).write())
        #expect(await waitUntil { remote.states.last == .playing && remote.player.isSeekable })
        remote.pause()
        #expect(await waitUntil { remote.states.last == .paused })

        remote.seek(to: .seconds(6))
        #expect(await waitUntil { remote.player.time >= .seconds(5) }, "\(remote.player.time)")
        remote.seek(by: .seconds(-4))
        #expect(await waitUntil { remote.player.time < .seconds(4) }, "\(remote.player.time)")
    }

    @Test func tracksAreListed() async throws {
        let remote = RecordingRemote()
        try remote.open(try TestClip.red().write())
        #expect(await waitUntil { remote.states.last == .playing && remote.player.videoTrack >= 0 })
        #expect(remote.tracksChanges > 0)
        let selected = remote.player.videoTrack
        #expect(remote.player.videoTracks.map(\.id) == [-1, selected], "\"Disable\", then the clip's one track")
        #expect(remote.player.audioTracks.isEmpty, "the clip has no audio")
        #expect(remote.player.subtitleTracks.isEmpty)
    }

    @Test func aPlayerGoesWhilePlaying() async throws {
        let url = try TestClip(frameCount: 250).write()
        var remote: RecordingRemote? = RecordingRemote()
        try remote?.open(url)
        #expect(await waitUntil { remote?.states.last == .playing })
        weak let player = remote?.player
        remote = nil
        #expect(player == nil, "stopped and released, frames and events still in flight")
        // Whatever was already queued for the main queue lands on nothing.
        try await Task.sleep(for: .milliseconds(200))
    }
}
