//
//  VlcMediaPlayer.swift
//  NucleantVLC
//
//  `libvlc_media_player_t`: plays one media at a time — transport, time,
//  tracks, audio, picture adjustments — and sends its video to `video`,
//  from where every `VlcView` showing it is filled.
//

import Foundation
import LibVLC

/// `libvlc_track_description_t`: a track a player can switch to.
public struct VlcTrack: Sendable, Hashable, Identifiable {
    /// What `audioTrack`, `videoTrack`, `subtitleTrack` take; -1 is "none".
    public let id: Int32
    public let name: String
}

/// `libvlc_title_description_t`.
public struct VlcTitle: Sendable, Hashable {
    public let duration: Duration
    public let name: String?
    public let flags: VlcTitleFlags
}

/// `libvlc_chapter_description_t`.
public struct VlcChapter: Sendable, Hashable {
    public let timeOffset: Duration
    public let duration: Duration
    public let name: String?
}

/// `libvlc_audio_output_device_t`.
public struct VlcAudioDevice: Sendable, Hashable, Identifiable {
    /// What `setAudioOutputDevice` takes.
    public let id: String
    public let description: String
}

/// One libvlc media player.
///
/// ```swift
/// let player = VlcMediaPlayer()
/// player.media = try VlcMedia(url: movieURL)
/// player.play()
/// ```
///
/// Its events go to the model it is bound to (`bind(to:)`, which a
/// `VlcRemote` does as soon as it is used). Its frames go to `video`.
@MainActor
public final class VlcMediaPlayer {

    let handle: OpaquePointer
    public let instance: VlcInstance

    /// Where the player's frames go — into every view that shows it.
    public let video: VlcVideoOutput

    private let events: VlcEventRelay
    private var current: VlcMedia?

    public init(instance: VlcInstance = .shared) {
        guard let handle = libvlc_media_player_new(instance.handle) else {
            fatalError("NucleantVLC: libvlc_media_player_new failed: \(VlcError.lastMessage)")
        }
        self.handle = handle
        self.instance = instance
        video = VlcVideoOutput(player: handle)
        events = VlcEventRelay(player: handle)
    }

    isolated deinit {
        events.detach()
        // Joins libvlc's threads: the video output's callbacks are over once
        // this returns, before `video` goes.
        libvlc_media_player_stop(handle)
        libvlc_media_player_release(handle)
    }

    /// Send this player's events to `events`. The first model bound keeps
    /// them; later calls do nothing.
    public func bind<Events: VlcPlayerEvents>(to events: Events) {
        guard !self.events.isBound else { return }
        self.events.bind(VlcPlayerHandlers(events))
    }

    // MARK: - Media and transport

    /// What plays next. Setting it stops what plays now.
    public var media: VlcMedia? {
        get { current }
        set {
            current = newValue
            libvlc_media_player_set_media(handle, newValue?.handle)
        }
    }

    /// Start, or resume when paused. False when it could not start.
    @discardableResult
    public func play() -> Bool {
        libvlc_media_player_play(handle) == 0
    }

    /// Pause; does nothing for media that cannot pause (`canPause`).
    public func pause() {
        libvlc_media_player_set_pause(handle, 1)
    }

    /// Pause when playing, resume when paused.
    public func togglePause() {
        libvlc_media_player_pause(handle)
    }

    /// Stop, and go back to the start. Waits for libvlc's threads.
    public func stop() {
        libvlc_media_player_stop(handle)
    }

    public var isPlaying: Bool { libvlc_media_player_is_playing(handle) != 0 }

    public var state: VlcState {
        VlcState(rawValue: Int32(truncatingIfNeeded: libvlc_media_player_get_state(handle).rawValue)) ?? .nothingSpecial
    }

    /// There is a media, and it is not at its end or failed.
    public var willPlay: Bool { libvlc_media_player_will_play(handle) != 0 }
    public var isSeekable: Bool { libvlc_media_player_is_seekable(handle) != 0 }
    public var canPause: Bool { libvlc_media_player_can_pause(handle) != 0 }
    public var isScrambled: Bool { libvlc_media_player_program_scrambled(handle) != 0 }

    /// `nil` until known.
    public var length: Duration? {
        let milliseconds = libvlc_media_player_get_length(handle)
        return milliseconds < 0 ? nil : .milliseconds(milliseconds)
    }

    /// Where playback is; setting it seeks (when `isSeekable`).
    public var time: Duration {
        get { .milliseconds(max(0, libvlc_media_player_get_time(handle))) }
        set { seek(milliseconds: Self.milliseconds(newValue)) }
    }

    /// 0…1 through the media; setting it seeks.
    public var position: Double {
        get { Double(max(0, libvlc_media_player_get_position(handle))) }
        set { seek(position: Float(min(max(newValue, 0), 1))) }
    }

    /// Playback speed, 1 normal. Not every media takes every rate.
    public var rate: Float {
        get { libvlc_media_player_get_rate(handle) }
        set { _ = libvlc_media_player_set_rate(handle, newValue) }
    }

    /// One frame on, while paused.
    public func nextFrame() {
        libvlc_media_player_next_frame(handle)
    }

    /// Move through a DVD-style menu.
    public func navigate(_ mode: VlcNavigateMode) {
        libvlc_media_player_navigate(handle, UInt32(mode.rawValue))
    }

    /// Show the media's title over the video, at `position`, for `duration`.
    public func showTitle(at position: VlcPosition, for duration: Duration) {
        libvlc_media_player_set_video_title_display(
            handle, libvlc_position_t(rawValue: position.rawValue), UInt32(Self.milliseconds(duration))
        )
    }

    // MARK: - Titles and chapters

    public var title: Int {
        get { Int(libvlc_media_player_get_title(handle)) }
        set { libvlc_media_player_set_title(handle, Int32(newValue)) }
    }

    public var titleCount: Int { max(0, Int(libvlc_media_player_get_title_count(handle))) }

    public var titles: [VlcTitle] {
        var list: UnsafeMutablePointer<UnsafeMutablePointer<libvlc_title_description_t>?>?
        let count = libvlc_media_player_get_full_title_descriptions(handle, &list)
        guard let list, count > 0 else { return [] }
        defer { libvlc_title_descriptions_release(list, UInt32(count)) }
        return (0..<Int(count)).compactMap { index in
            list[index].map { title in
                VlcTitle(
                    duration: .milliseconds(title.pointee.i_duration),
                    name: title.pointee.psz_name.map { String(cString: $0) },
                    flags: VlcTitleFlags(rawValue: title.pointee.i_flags)
                )
            }
        }
    }

    public var chapter: Int {
        get { Int(libvlc_media_player_get_chapter(handle)) }
        set { libvlc_media_player_set_chapter(handle, Int32(newValue)) }
    }

    public var chapterCount: Int { max(0, Int(libvlc_media_player_get_chapter_count(handle))) }

    /// The chapters of `title` — the current title when `nil`.
    public func chapters(ofTitle title: Int? = nil) -> [VlcChapter] {
        var list: UnsafeMutablePointer<UnsafeMutablePointer<libvlc_chapter_description_t>?>?
        let count = libvlc_media_player_get_full_chapter_descriptions(handle, Int32(title ?? -1), &list)
        guard let list, count > 0 else { return [] }
        defer { libvlc_chapter_descriptions_release(list, UInt32(count)) }
        return (0..<Int(count)).compactMap { index in
            list[index].map { chapter in
                VlcChapter(
                    timeOffset: .milliseconds(chapter.pointee.i_time_offset),
                    duration: .milliseconds(chapter.pointee.i_duration),
                    name: chapter.pointee.psz_name.map { String(cString: $0) }
                )
            }
        }
    }

    public func nextChapter() {
        libvlc_media_player_next_chapter(handle)
    }

    public func previousChapter() {
        libvlc_media_player_previous_chapter(handle)
    }

    // MARK: - Tracks

    public var audioTracks: [VlcTrack] { Self.tracks(libvlc_audio_get_track_description(handle)) }
    public var videoTracks: [VlcTrack] { Self.tracks(libvlc_video_get_track_description(handle)) }
    public var subtitleTracks: [VlcTrack] { Self.tracks(libvlc_video_get_spu_description(handle)) }

    /// The selected track's id, -1 for none.
    public var audioTrack: Int32 {
        get { libvlc_audio_get_track(handle) }
        set { _ = libvlc_audio_set_track(handle, newValue) }
    }

    public var videoTrack: Int32 {
        get { libvlc_video_get_track(handle) }
        set { _ = libvlc_video_set_track(handle, newValue) }
    }

    public var subtitleTrack: Int32 {
        get { libvlc_video_get_spu(handle) }
        set { _ = libvlc_video_set_spu(handle, newValue) }
    }

    /// Add a subtitle file or an audio track to what plays now, and select
    /// it when `select`.
    @discardableResult
    public func addSlave(_ type: VlcSlaveType, url: URL, select: Bool = true) -> Bool {
        libvlc_media_player_add_slave(
            handle, libvlc_media_slave_type_t(rawValue: UInt32(type.rawValue)), url.absoluteString, select
        ) == 0
    }

    /// Positive delays the subtitles.
    public var subtitleDelay: Duration {
        get { .microseconds(libvlc_video_get_spu_delay(handle)) }
        set { _ = libvlc_video_set_spu_delay(handle, Self.microseconds(newValue)) }
    }

    /// Teletext page, 0 for none.
    public var teletextPage: Int {
        get { Int(libvlc_video_get_teletext(handle)) }
        set { libvlc_video_set_teletext(handle, Int32(newValue)) }
    }

    public func pressTeletextKey(_ key: VlcTeletextKey) {
        libvlc_video_set_teletext(handle, key.rawValue)
    }

    private static func tracks(_ list: UnsafeMutablePointer<libvlc_track_description_t>?) -> [VlcTrack] {
        guard let list else { return [] }
        defer { libvlc_track_description_list_release(list) }
        var tracks: [VlcTrack] = []
        var entry: UnsafeMutablePointer<libvlc_track_description_t>? = list
        while let current = entry {
            tracks.append(VlcTrack(
                id: current.pointee.i_id,
                name: current.pointee.psz_name.map { String(cString: $0) } ?? ""
            ))
            entry = current.pointee.p_next
        }
        return tracks
    }

    // MARK: - Audio

    /// 0…200 (100 is the media's own level); -1 while there is no audio
    /// output.
    public var volume: Int {
        get { Int(libvlc_audio_get_volume(handle)) }
        set { _ = libvlc_audio_set_volume(handle, Int32(min(max(newValue, 0), 200))) }
    }

    public var isMuted: Bool {
        get { libvlc_audio_get_mute(handle) == 1 }
        set { libvlc_audio_set_mute(handle, newValue ? 1 : 0) }
    }

    public func toggleMute() {
        libvlc_audio_toggle_mute(handle)
    }

    /// Positive delays the audio.
    public var audioDelay: Duration {
        get { .microseconds(libvlc_audio_get_delay(handle)) }
        set { _ = libvlc_audio_set_delay(handle, Self.microseconds(newValue)) }
    }

    public var audioChannel: VlcAudioChannel {
        get { VlcAudioChannel(rawValue: libvlc_audio_get_channel(handle)) ?? .error }
        set { _ = libvlc_audio_set_channel(handle, newValue.rawValue) }
    }

    /// The devices the current audio output can play to.
    public var audioOutputDevices: [VlcAudioDevice] {
        guard let list = libvlc_audio_output_device_enum(handle) else { return [] }
        defer { libvlc_audio_output_device_list_release(list) }
        var devices: [VlcAudioDevice] = []
        var entry: UnsafeMutablePointer<libvlc_audio_output_device_t>? = list
        while let current = entry {
            if let id = current.pointee.psz_device {
                devices.append(VlcAudioDevice(
                    id: String(cString: id),
                    description: current.pointee.psz_description.map { String(cString: $0) } ?? ""
                ))
            }
            entry = current.pointee.p_next
        }
        return devices
    }

    /// The device played to, `nil` when unknown.
    public var audioOutputDevice: String? {
        guard let device = libvlc_audio_output_device_get(handle) else { return nil }
        defer { libvlc_free(device) }
        return String(cString: device)
    }

    public func setAudioOutputDevice(_ id: String) {
        libvlc_audio_output_device_set(handle, nil, id)
    }

    public var role: VlcPlayerRole {
        get { VlcPlayerRole(rawValue: libvlc_media_player_get_role(handle)) ?? .none }
        set { _ = libvlc_media_player_set_role(handle, UInt32(newValue.rawValue)) }
    }

    // MARK: - Picture

    /// The color adjustments are applied while this is on.
    public var isAdjustEnabled: Bool {
        get { libvlc_video_get_adjust_int(handle, UInt32(VlcAdjustOption.enable.rawValue)) != 0 }
        set { libvlc_video_set_adjust_int(handle, UInt32(VlcAdjustOption.enable.rawValue), newValue ? 1 : 0) }
    }

    public func adjust(_ option: VlcAdjustOption) -> Float {
        libvlc_video_get_adjust_float(handle, UInt32(option.rawValue))
    }

    public func setAdjust(_ option: VlcAdjustOption, to value: Float) {
        libvlc_video_set_adjust_float(handle, UInt32(option.rawValue), value)
    }

    public func marquee(_ option: VlcMarqueeOption) -> Int {
        Int(libvlc_video_get_marquee_int(handle, UInt32(option.rawValue)))
    }

    public func setMarquee(_ option: VlcMarqueeOption, to value: Int) {
        libvlc_video_set_marquee_int(handle, UInt32(option.rawValue), Int32(value))
    }

    /// The marquee's text (`VlcMarqueeOption.text`).
    public var marqueeText: String? {
        get {
            guard let text = libvlc_video_get_marquee_string(handle, UInt32(VlcMarqueeOption.text.rawValue)) else {
                return nil
            }
            defer { libvlc_free(text) }
            return String(cString: text)
        }
        set { libvlc_video_set_marquee_string(handle, UInt32(VlcMarqueeOption.text.rawValue), newValue) }
    }

    public func logo(_ option: VlcLogoOption) -> Int {
        Int(libvlc_video_get_logo_int(handle, UInt32(option.rawValue)))
    }

    public func setLogo(_ option: VlcLogoOption, to value: Int) {
        libvlc_video_set_logo_int(handle, UInt32(option.rawValue), Int32(value))
    }

    /// The logo's image files (`VlcLogoOption.file`): "file,d,t;file,d,t;…".
    public func setLogoFile(_ files: String) {
        libvlc_video_set_logo_string(handle, UInt32(VlcLogoOption.file.rawValue), files)
    }

    /// Save the current picture as an image at `path` — `width` × `height`,
    /// either 0 to keep the video's proportions. Reported by `snapshotTaken`.
    @discardableResult
    public func takeSnapshot(to path: String, width: Int = 0, height: Int = 0) -> Bool {
        libvlc_video_take_snapshot(handle, 0, path, UInt32(width), UInt32(height)) == 0
    }

    /// The video's size in pixels, as libvlc's output reports it.
    public var videoSize: (width: Int, height: Int)? {
        var width: UInt32 = 0
        var height: UInt32 = 0
        guard libvlc_video_get_size(handle, 0, &width, &height) == 0, width > 0, height > 0 else { return nil }
        return (Int(width), Int(height))
    }

    // MARK: -

    static func milliseconds(_ duration: Duration) -> Int64 {
        duration.components.seconds * 1000 + duration.components.attoseconds / 1_000_000_000_000_000
    }

    static func microseconds(_ duration: Duration) -> Int64 {
        duration.components.seconds * 1_000_000 + duration.components.attoseconds / 1_000_000_000_000
    }
}
