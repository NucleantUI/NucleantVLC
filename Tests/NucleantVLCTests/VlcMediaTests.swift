//
//  VlcMediaTests.swift
//  NucleantVLCTests
//
//  libvlc starting from the framework's plugins, and media read without
//  playing.
//

import Foundation
import Testing
@testable import NucleantVLC

struct VlcMediaTests {

    @Test func libvlcIsTheFetchedOne() {
        #expect(VlcInstance.version.hasPrefix("3.0.24"), "\(VlcInstance.version)")
    }

    @Test func anInstanceStartsWithItsArguments() throws {
        let instance = try VlcInstance(arguments: ["--no-audio", "--no-video-title-show"])
        let media = try VlcMedia(location: "file:///nowhere.mkv", instance: instance)
        #expect(media.mrl == "file:///nowhere.mkv")
    }

    @Test func parsingReadsDurationAndTracks() async throws {
        let clip = TestClip()
        let media = try VlcMedia(url: try clip.write())
        #expect(media.parsedStatus == nil, "not parsed yet")

        let status = await media.parse()
        #expect(status == .done)
        #expect(media.parsedStatus == .done)
        #expect(media.type == .file)
        let duration = try #require(media.duration)
        #expect(abs((duration - clip.duration).components.seconds) == 0, "\(duration)")

        let video = try #require(media.tracks.first { $0.type == .video }?.video)
        #expect(video.width == clip.width)
        #expect(video.height == clip.height)
        #expect(video.sampleAspect == 1)
        #expect(abs(video.frameRate - 25) < 0.01)
    }

    @Test func aParsedMediaAnswersAtOnce() async throws {
        let media = try VlcMedia(url: try TestClip(frameCount: 4).write())
        #expect(await media.parse() == .done)
        #expect(await media.parse() == .done)
    }

    @Test func parsingReadsTheSampleAspect() async throws {
        let media = try VlcMedia(url: try TestClip(sampleAspect: (2, 1)).write())
        _ = await media.parse()
        let video = try #require(media.tracks.compactMap(\.video).first)
        #expect(video.sampleAspect == 2)
    }

    @Test func aPlaylistsEntriesAreItsSubitems() async throws {
        let clips = try [TestClip(frameCount: 4).write(), TestClip(frameCount: 4).write()]
        let playlist = FileManager.default.temporaryDirectory.appendingPathComponent("nucleantvlc-\(UUID().uuidString).m3u")
        try ("#EXTM3U\n" + clips.map(\.path).joined(separator: "\n") + "\n").write(to: playlist, atomically: true, encoding: .utf8)

        let media = try VlcMedia(url: playlist)
        #expect(media.subitems.isEmpty, "not known before a parse")
        #expect(await media.parse() == .done)
        let entries = media.subitems
        #expect(entries.count == 2)
        #expect(entries.map(\.mrl) == clips.map(\.absoluteString), "\(entries.map(\.mrl))")
    }

    @Test func metadataRoundTripsInMemory() throws {
        let media = try VlcMedia(url: try TestClip(frameCount: 2).write())
        media.setMeta(.title, "A test clip")
        #expect(media.meta(.title) == "A test clip")
    }

    @Test func aMissingFileFailsToParse() async throws {
        let media = try VlcMedia(path: "/nowhere/at/all.y4m")
        #expect(await media.parse() != .done)
    }
}
