//
//  Player.swift
//  NucleantVLCDemo
//
//  The app's model: a playlist and the player playing it — a `VlcRemote`
//  that keeps the player's events in observable properties, for the views
//  to read.
//

import Foundation
import NucleantUI
import NucleantVLC
import Observation

/// One entry of the playlist.
struct PlaylistItem: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    var title: String
    /// The title was given, not made up from the address: the media's own
    /// title doesn't replace it.
    var keepsTitle = false
    var duration: Duration?
}

@MainActor
@Observable
final class Player: VlcRemote {

    @ObservationIgnored let player = VlcMediaPlayer()

    private(set) var items: [PlaylistItem] = []
    private(set) var currentID: PlaylistItem.ID?

    private(set) var state = VlcState.nothingSpecial
    private(set) var time = Duration.zero
    private(set) var length = Duration.zero
    private(set) var position = 0.0
    private(set) var isSeekable = false
    private(set) var canPause = false
    /// 0…100 while the input fills its cache.
    private(set) var buffering: Float = 100
    private(set) var volume = 100
    private(set) var isMuted = false
    private(set) var rate: Float = 1
    private(set) var audioTracks: [VlcTrack] = []
    private(set) var subtitleTracks: [VlcTrack] = []
    private(set) var audioTrack: Int32 = -1
    private(set) var subtitleTrack: Int32 = -1
    /// The last thing that could not be opened or played.
    private(set) var lastError: String?
    /// Start over from the first item after the last one ends.
    var repeatsAll = false

    static let rates: [Float] = [0.25, 0.5, 0.75, 1, 1.25, 1.5, 2, 4]

    var current: PlaylistItem? { items.first { $0.id == currentID } }
    var isPlaying: Bool { state == .playing || state == .opening }

    /// What plays when the app is started with nothing to play: Blender's
    /// open movies as plain files, streamed over HTTPS, in versions the GPU
    /// decodes (H.264, through VideoToolbox) at full size — the Big Buck
    /// Bunny trailer, and Sintel, whose subtitle tracks fill the subtitle
    /// menu.
    static let blenderMovies: [PlaylistItem] = [
        ("Big Buck Bunny · trailer 1080p", "peach/trailer/trailer_1080p.mov"),
        ("Big Buck Bunny · trailer 720p", "peach/trailer/trailer_720p.mov"),
        ("Sintel · 1080p", "demo/movies/Sintel.2010.1080p.mkv"),
    ].map { title, path in
        PlaylistItem(url: URL(string: "https://download.blender.org/" + path)!, title: title, keepsTitle: true)
    }

    // MARK: - Playlist

    /// Add files, folders (their media files, sorted) and addresses; play
    /// the first one added when `playing`.
    func add(_ urls: [URL], playing: Bool) {
        let added = urls.flatMap(Self.mediaFiles(at:)).map {
            PlaylistItem(url: $0, title: $0.isFileURL ? $0.deletingPathExtension().lastPathComponent : $0.absoluteString)
        }
        guard !added.isEmpty else {
            lastError = "Nothing to play in \(urls.map(\.relativeString).joined(separator: ", "))"
            return
        }
        add(added, playing: playing)
    }

    func add(_ added: [PlaylistItem], playing: Bool) {
        items.append(contentsOf: added)
        for item in added { describe(item) }
        if playing, let first = added.first { play(first) }
    }

    /// What was typed in the open field: an address with a scheme, or a
    /// path (`~` for home).
    func add(typed text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if text.contains("://"), let url = URL(string: text) {
            add([url], playing: true)
        } else {
            add([URL(fileURLWithPath: (text as NSString).expandingTildeInPath)], playing: true)
        }
    }

    func play(_ item: PlaylistItem) {
        do {
            currentID = item.id
            lastError = nil
            try open(item.url)
        } catch {
            lastError = "\(error)"
        }
    }

    func remove(_ item: PlaylistItem) {
        let wasCurrent = item.id == currentID
        items.removeAll { $0.id == item.id }
        if wasCurrent {
            currentID = nil
            stop()
        }
    }

    func next() {
        guard let index = currentIndex else {
            if let first = items.first { play(first) }
            return
        }
        if index + 1 < items.count {
            play(items[index + 1])
        } else if repeatsAll, let first = items.first {
            play(first)
        }
    }

    func previous() {
        // Back to the start of this one first, as players do.
        if time > .seconds(3) {
            seek(to: .zero)
            return
        }
        guard let index = currentIndex, index > 0 else { return }
        play(items[index - 1])
    }

    private var currentIndex: Int? { items.firstIndex { $0.id == currentID } }

    // MARK: - Transport

    func playPause() {
        if state == .nothingSpecial || state == .stopped || state == .ended || state == .error {
            if let current { play(current) } else { next() }
        } else {
            togglePause()
        }
    }

    func changeVolume(_ volume: Int) {
        setVolume(volume)
        self.volume = volume
    }

    func changeRate(_ rate: Float) {
        setRate(rate)
        self.rate = player.rate
    }

    func chooseAudioTrack(_ id: Int32) {
        selectAudioTrack(id)
        refreshTracks()
    }

    func chooseSubtitleTrack(_ id: Int32) {
        selectSubtitleTrack(id)
        refreshTracks()
    }

    // MARK: - VlcPlayerEvents

    func mediaDidChange() {
        time = .zero
        length = .zero
        position = 0
        audioTracks = []
        subtitleTracks = []
    }

    func stateDidChange(_ state: VlcState) {
        self.state = state
        if state == .playing {
            refreshTracks()
            rate = player.rate
        }
    }

    func timeDidChange(_ time: Duration) { self.time = time }
    func lengthDidChange(_ length: Duration) { self.length = length }
    func positionDidChange(_ position: Double) { self.position = position }
    func seekableDidChange(_ isSeekable: Bool) { self.isSeekable = isSeekable }
    func pausableDidChange(_ canPause: Bool) { self.canPause = canPause }
    func bufferingDidChange(_ percent: Float) { buffering = percent }
    func tracksDidChange() { refreshTracks() }
    func mutedDidChange(_ isMuted: Bool) { self.isMuted = isMuted }

    func volumeDidChange(_ volume: Float) {
        self.volume = Int((volume * 100).rounded())
    }

    /// The end of a movie — or of a playlist file, which "plays" by listing
    /// what it holds: then what it holds plays.
    func didReachEnd() {
        let entries = player.media?.subitems ?? []
        guard let first = entries.first else {
            next()
            return
        }
        if let listed = items.first(where: { $0.url.absoluteString == first.mrl }) {
            play(listed)
        } else if let current, let opened = open(current, holding: entries) {
            play(opened)
        } else {
            next()
        }
    }

    func didFail() {
        lastError = "Could not play \(current?.title ?? "this")"
    }

    // MARK: -

    private func refreshTracks() {
        audioTracks = player.audioTracks
        subtitleTracks = player.subtitleTracks
        audioTrack = player.audioTrack
        subtitleTrack = player.subtitleTrack
    }

    /// Title and duration for the playlist, from a parse that plays nothing
    /// — and a playlist file opened up into what it holds.
    private func describe(_ item: PlaylistItem) {
        guard let media = try? VlcMedia(url: item.url, instance: player.instance) else { return }
        Task {
            _ = await media.parse(item.url.isFileURL ? [] : .network)
            let entries = media.subitems
            if !entries.isEmpty {
                open(item, holding: entries)
                return
            }
            guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
            if !items[index].keepsTitle, let title = media.meta(.title), !title.isEmpty {
                items[index].title = title
            }
            items[index].duration = media.duration
        }
    }

    /// Put what `container` holds in its place in the playlist. One entry
    /// keeps the container's title. Returns the first entry.
    @discardableResult
    private func open(_ container: PlaylistItem, holding entries: [VlcMedia]) -> PlaylistItem? {
        guard let index = items.firstIndex(where: { $0.id == container.id }) else { return nil }
        let opened = entries.compactMap { entry -> PlaylistItem? in
            guard let url = URL(string: entry.mrl) else { return nil }
            if entries.count == 1 {
                return PlaylistItem(url: url, title: container.title, keepsTitle: container.keepsTitle)
            }
            let file = entry.mrl.split(separator: "/").last.map(String.init) ?? entry.mrl
            let name = (file.removingPercentEncoding ?? file) as NSString
            return PlaylistItem(url: url, title: name.deletingPathExtension)
        }
        items.replaceSubrange(index...index, with: opened)
        if currentID == container.id { currentID = opened.first?.id }
        for item in opened { describe(item) }
        return opened.first
    }

    /// `url` itself, or a folder's media files by name.
    private static func mediaFiles(at url: URL) -> [URL] {
        guard url.isFileURL else { return [url] }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return [] }
        guard isDirectory.boolValue else { return [url] }
        let contents = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
        return contents
            .filter { mediaExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private static let mediaExtensions: Set<String> = [
        "mp4", "m4v", "mkv", "mov", "avi", "webm", "wmv", "flv", "ts", "m2ts", "mts", "mpg", "mpeg", "ogv", "3gp",
        "y4m", "mp3", "m4a", "aac", "flac", "wav", "ogg", "opus", "wma", "aiff",
    ]
}
