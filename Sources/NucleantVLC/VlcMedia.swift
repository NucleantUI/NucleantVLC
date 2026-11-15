//
//  VlcMedia.swift
//  NucleantVLC
//
//  `libvlc_media_t`: something to play — a file, a stream, a disc — with
//  its options, metadata and tracks.
//

import Foundation
import LibVLC

/// One thing to play.
///
/// ```swift
/// let media = try VlcMedia(url: URL(fileURLWithPath: "/Movies/clip.mkv"))
/// _ = await media.parse()
/// print(media.meta(.title) ?? "untitled", media.duration ?? .zero)
/// ```
public final class VlcMedia: @unchecked Sendable {

    let handle: OpaquePointer

    /// A file URL is opened by its path, anything else (`https:`, `rtsp:`,
    /// `screen:` …) by its address.
    public convenience init(url: URL, instance: VlcInstance = .shared) throws {
        if url.isFileURL {
            try self.init(path: url.path, instance: instance)
        } else {
            try self.init(location: url.absoluteString, instance: instance)
        }
    }

    /// A media by its MRL: `file:///…`, `https://…`, `rtsp://…`, `screen://`.
    public init(location: String, instance: VlcInstance = .shared) throws {
        guard let made = libvlc_media_new_location(instance.handle, location) else {
            throw VlcError.mediaFailed(location)
        }
        handle = made
    }

    /// A local file by its path.
    public init(path: String, instance: VlcInstance = .shared) throws {
        guard let made = libvlc_media_new_path(instance.handle, path) else {
            throw VlcError.mediaFailed(path)
        }
        handle = made
    }

    /// A media libvlc handed out already retained (`libvlc_media_player_get_media`)
    /// — released with this object.
    init(adopting handle: OpaquePointer) {
        self.handle = handle
    }

    deinit {
        libvlc_media_release(handle)
    }

    /// The media's address, as libvlc spells it.
    public var mrl: String {
        guard let mrl = libvlc_media_get_mrl(handle) else { return "" }
        defer { libvlc_free(mrl) }
        return String(cString: mrl)
    }

    /// Add a VLC option for this media only — `":start-time=30"`,
    /// `":no-audio"`, `":network-caching=1000"`.
    public func addOption(_ option: String, flags: VlcMediaOptionFlags? = nil) {
        if let flags {
            libvlc_media_add_option_flag(handle, option, flags.rawValue)
        } else {
            libvlc_media_add_option(handle, option)
        }
    }

    // MARK: - Metadata

    /// `key`'s value — after a parse, for anything not in the address.
    public func meta(_ key: VlcMeta) -> String? {
        guard let value = libvlc_media_get_meta(handle, libvlc_meta_t(rawValue: UInt32(key.rawValue))) else {
            return nil
        }
        defer { libvlc_free(value) }
        return String(cString: value)
    }

    /// Change `key` in memory; `saveMeta()` writes it to the file.
    public func setMeta(_ key: VlcMeta, _ value: String?) {
        libvlc_media_set_meta(handle, libvlc_meta_t(rawValue: UInt32(key.rawValue)), value)
    }

    /// Write changed metadata back to the file. False when it could not be.
    @discardableResult
    public func saveMeta() -> Bool {
        libvlc_media_save_meta(handle) != 0
    }

    public var state: VlcState {
        VlcState(rawValue: Int32(truncatingIfNeeded: libvlc_media_get_state(handle).rawValue)) ?? .nothingSpecial
    }

    /// `nil` until known — after a parse, or once it plays.
    public var duration: Duration? {
        let milliseconds = libvlc_media_get_duration(handle)
        return milliseconds < 0 ? nil : .milliseconds(milliseconds)
    }

    public var type: VlcMediaType {
        VlcMediaType(rawValue: Int32(truncatingIfNeeded: libvlc_media_get_type(handle).rawValue)) ?? .unknown
    }

    // MARK: - Parsing

    /// How the last parse ended — `nil` before one has.
    public var parsedStatus: VlcParsedStatus? {
        VlcParsedStatus(rawValue: Int32(truncatingIfNeeded: libvlc_media_get_parsed_status(handle).rawValue))
    }

    /// Read the media's metadata and tracks without playing it. A media
    /// already parsed answers at once.
    public func parse(_ options: VlcParseOptions = [], timeout: Duration = .seconds(5)) async -> VlcParsedStatus {
        if let status = parsedStatus, status == .done { return status }
        let waiter = ParseWaiter()
        let events = libvlc_media_event_manager(handle)
        let opaque = Unmanaged.passUnretained(waiter).toOpaque()
        let callback: libvlc_callback_t = { event, data in
            guard let event, let data else { return }
            let status = event.pointee.u.media_parsed_changed.new_status
            Unmanaged<ParseWaiter>.fromOpaque(data).takeUnretainedValue()
                .finish(VlcParsedStatus(rawValue: status) ?? .failed)
        }
        let type = VlcEventType.mediaParsedChanged.rawValue
        libvlc_event_attach(events, type, callback, opaque)
        let milliseconds = Int32(clamping: timeout.components.seconds * 1000
            + timeout.components.attoseconds / 1_000_000_000_000_000)
        let status: VlcParsedStatus
        if libvlc_media_parse_with_options(handle, libvlc_media_parse_flag_t(rawValue: UInt32(options.rawValue)), milliseconds) != 0 {
            status = .failed
        } else {
            status = await waiter.wait()
        }
        // Not from inside the callback: libvlc calls it holding the lock
        // detaching takes.
        libvlc_event_detach(events, type, callback, opaque)
        return status
    }

    /// Stop a parse under way; it ends as `.failed`.
    public func stopParsing() {
        libvlc_media_parse_stop(handle)
    }

    /// The tracks the media holds — known after a parse, or once it plays.
    public var tracks: [VlcMediaTrack] {
        var list: UnsafeMutablePointer<UnsafeMutablePointer<libvlc_media_track_t>?>?
        let count = libvlc_media_tracks_get(handle, &list)
        guard let list, count > 0 else { return [] }
        defer { libvlc_media_tracks_release(list, count) }
        return (0..<Int(count)).compactMap { list[$0].map { VlcMediaTrack($0.pointee) } }
    }

    /// What the media turned out to hold when it is a container of other
    /// media — a playlist file, a zip archive, a folder, a page a script
    /// resolves. Known after a parse, or once it has played (which, for
    /// such a media, ends straight away).
    public var subitems: [VlcMedia] {
        guard let list = libvlc_media_subitems(handle) else { return [] }
        defer { libvlc_media_list_release(list) }
        libvlc_media_list_lock(list)
        defer { libvlc_media_list_unlock(list) }
        let count = Int(libvlc_media_list_count(list))
        // Each item comes retained.
        return (0..<max(0, count)).compactMap { index in
            libvlc_media_list_item_at_index(list, Int32(index)).map { VlcMedia(adopting: $0) }
        }
    }

    // MARK: - Slaves

    /// Play `url` along with this media — a subtitle file or an audio track
    /// kept apart. `priority` 0…4; 4 is what a user picked by hand.
    @discardableResult
    public func addSlave(_ type: VlcSlaveType, url: URL, priority: UInt32 = 4) -> Bool {
        libvlc_media_slaves_add(
            handle, libvlc_media_slave_type_t(rawValue: UInt32(type.rawValue)), priority, url.absoluteString
        ) == 0
    }

    public func clearSlaves() {
        libvlc_media_slaves_clear(handle)
    }
}

/// Waits for one `libvlc_MediaParsedChanged`, which arrives on a libvlc
/// thread.
private final class ParseWaiter: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<VlcParsedStatus, Never>?
    private var result: VlcParsedStatus?

    func wait() async -> VlcParsedStatus {
        await withCheckedContinuation { continuation in
            lock.lock()
            if let result {
                lock.unlock()
                continuation.resume(returning: result)
            } else {
                self.continuation = continuation
                lock.unlock()
            }
        }
    }

    func finish(_ status: VlcParsedStatus) {
        lock.lock()
        guard result == nil else {
            lock.unlock()
            return
        }
        result = status
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: status)
    }
}

/// `libvlc_media_track_t`: one elementary stream of a media.
public struct VlcMediaTrack: Sendable, Hashable, Identifiable {
    public let id: Int32
    public let type: VlcTrackType
    /// The codec's fourcc, e.g. "h264", "mp4a".
    public let codec: String
    /// What the codec is, in words — e.g. "H264 - MPEG-4 AVC (part 10)".
    public let codecDescription: String
    public let profile: Int32
    public let level: Int32
    /// Bits per second, 0 when unknown.
    public let bitrate: UInt32
    public let language: String?
    public let description: String?
    public let video: Video?
    public let audio: Audio?
    /// A text track's character encoding.
    public let subtitleEncoding: String?

    /// `libvlc_video_track_t`.
    public struct Video: Sendable, Hashable {
        public let width: Int
        public let height: Int
        /// Sample aspect ratio, numerator ÷ denominator: the shape of one
        /// pixel. 1 for square pixels.
        public let sampleAspectNumerator: Int
        public let sampleAspectDenominator: Int
        /// Frames per second, 0 when unknown.
        public let frameRate: Double
        public let orientation: VlcVideoOrientation
        public let projection: VlcVideoProjection

        /// `sampleAspectNumerator ÷ sampleAspectDenominator`, 1 when either
        /// is unknown.
        public var sampleAspect: Double {
            sampleAspectNumerator > 0 && sampleAspectDenominator > 0
                ? Double(sampleAspectNumerator) / Double(sampleAspectDenominator) : 1
        }
    }

    /// `libvlc_audio_track_t`.
    public struct Audio: Sendable, Hashable {
        public let channels: Int
        public let rate: Int
    }

    init(_ track: libvlc_media_track_t) {
        id = track.i_id
        type = VlcTrackType(rawValue: track.i_type.rawValue) ?? .unknown
        codec = VlcMediaTrack.fourcc(track.i_codec)
        codecDescription = libvlc_media_get_codec_description(track.i_type, track.i_codec)
            .map { String(cString: $0) } ?? ""
        profile = track.i_profile
        level = track.i_level
        bitrate = track.i_bitrate
        language = track.psz_language.map { String(cString: $0) }
        description = track.psz_description.map { String(cString: $0) }
        switch type {
        case .video:
            video = track.video.map { video in
                let track = video.pointee
                return Video(
                    width: Int(track.i_width),
                    height: Int(track.i_height),
                    sampleAspectNumerator: Int(track.i_sar_num),
                    sampleAspectDenominator: Int(track.i_sar_den),
                    frameRate: track.i_frame_rate_den > 0
                        ? Double(track.i_frame_rate_num) / Double(track.i_frame_rate_den) : 0,
                    orientation: VlcVideoOrientation(rawValue: Int32(truncatingIfNeeded: track.i_orientation.rawValue)) ?? .topLeft,
                    projection: VlcVideoProjection(rawValue: Int32(truncatingIfNeeded: track.i_projection.rawValue)) ?? .rectangular
                )
            }
            audio = nil
            subtitleEncoding = nil
        case .audio:
            audio = track.audio.map { Audio(channels: Int($0.pointee.i_channels), rate: Int($0.pointee.i_rate)) }
            video = nil
            subtitleEncoding = nil
        case .text:
            subtitleEncoding = track.subtitle.flatMap { $0.pointee.psz_encoding.map { String(cString: $0) } }
            video = nil
            audio = nil
        case .unknown:
            video = nil
            audio = nil
            subtitleEncoding = nil
        }
    }

    /// A fourcc's four characters, as stored (little-endian).
    static func fourcc(_ code: UInt32) -> String {
        let bytes = [code, code >> 8, code >> 16, code >> 24].map { UInt8(truncatingIfNeeded: $0) }
        return String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespaces)
    }
}
