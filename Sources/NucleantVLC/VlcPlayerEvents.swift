//
//  VlcPlayerEvents.swift
//  NucleantVLC
//
//  What a media player reports, as a protocol whose methods all do nothing
//  by default — a model keeps the ones it cares about in properties of its
//  own. libvlc reports on its own threads; the methods are called on the
//  main actor, in the order libvlc sent them.
//

import Dispatch
import LibVLC

/// A media player's events (`libvlc_MediaPlayer…`). Every method does
/// nothing by default.
@MainActor
public protocol VlcPlayerEvents: AnyObject {
    /// Another media was set (`libvlc_MediaPlayerMediaChanged`).
    func mediaDidChange()
    /// Opening, playing, paused, stopped, ended, error.
    func stateDidChange(_ state: VlcState)
    /// 0…100: how full the input's cache is while it buffers.
    func bufferingDidChange(_ percent: Float)
    func timeDidChange(_ time: Duration)
    /// 0…1 through the media.
    func positionDidChange(_ position: Double)
    func lengthDidChange(_ length: Duration)
    func seekableDidChange(_ isSeekable: Bool)
    func pausableDidChange(_ canPause: Bool)
    /// A track was added, removed or selected — the player's track lists
    /// and selections are worth reading again.
    func tracksDidChange()
    /// 0…2 (1 is 100%), as the audio output reports it.
    func volumeDidChange(_ volume: Float)
    func mutedDidChange(_ isMuted: Bool)
    /// How many video outputs are open — 0 for audio only.
    func videoOutputsDidChange(_ count: Int)
    func titleDidChange(_ title: Int)
    func chapterDidChange(_ chapter: Int)
    /// `takeSnapshot` wrote `path`.
    func snapshotTaken(_ path: String)
    /// The media played to its end (also reported as `.ended`).
    func didReachEnd()
    /// The media could not be played (also reported as `.error`).
    func didFail()
}

public extension VlcPlayerEvents {
    func mediaDidChange() {}
    func stateDidChange(_ state: VlcState) {}
    func bufferingDidChange(_ percent: Float) {}
    func timeDidChange(_ time: Duration) {}
    func positionDidChange(_ position: Double) {}
    func lengthDidChange(_ length: Duration) {}
    func seekableDidChange(_ isSeekable: Bool) {}
    func pausableDidChange(_ canPause: Bool) {}
    func tracksDidChange() {}
    func volumeDidChange(_ volume: Float) {}
    func mutedDidChange(_ isMuted: Bool) {}
    func videoOutputsDidChange(_ count: Int) {}
    func titleDidChange(_ title: Int) {}
    func chapterDidChange(_ chapter: Int) {}
    func snapshotTaken(_ path: String) {}
    func didReachEnd() {}
    func didFail() {}
}

/// One `libvlc_event_t`, copied out of libvlc on the thread that sent it —
/// nothing in it points back into libvlc.
enum VlcPlayerEvent: Sendable {
    case mediaChanged
    case state(VlcState)
    case buffering(Float)
    case time(Int64)
    case position(Float)
    case length(Int64)
    case seekable(Bool)
    case pausable(Bool)
    case tracks
    case volume(Float)
    case muted(Bool)
    case videoOutputs(Int)
    case title(Int)
    case chapter(Int)
    case snapshot(String)
    case endReached
    case failed

    init?(_ event: libvlc_event_t) {
        guard let type = VlcEventType(rawValue: event.type) else { return nil }
        let u = event.u
        switch type {
        case .mediaPlayerMediaChanged: self = .mediaChanged
        case .mediaPlayerNothingSpecial: self = .state(.nothingSpecial)
        case .mediaPlayerOpening: self = .state(.opening)
        case .mediaPlayerBuffering: self = .buffering(u.media_player_buffering.new_cache)
        case .mediaPlayerPlaying: self = .state(.playing)
        case .mediaPlayerPaused: self = .state(.paused)
        case .mediaPlayerStopped: self = .state(.stopped)
        case .mediaPlayerEndReached: self = .endReached
        case .mediaPlayerEncounteredError: self = .failed
        case .mediaPlayerTimeChanged: self = .time(u.media_player_time_changed.new_time)
        case .mediaPlayerPositionChanged: self = .position(u.media_player_position_changed.new_position)
        case .mediaPlayerSeekableChanged: self = .seekable(u.media_player_seekable_changed.new_seekable != 0)
        case .mediaPlayerPausableChanged: self = .pausable(u.media_player_pausable_changed.new_pausable != 0)
        case .mediaPlayerTitleChanged: self = .title(Int(u.media_player_title_changed.new_title))
        case .mediaPlayerChapterChanged: self = .chapter(Int(u.media_player_chapter_changed.new_chapter))
        case .mediaPlayerSnapshotTaken:
            self = .snapshot(u.media_player_snapshot_taken.psz_filename.map { String(cString: $0) } ?? "")
        case .mediaPlayerLengthChanged: self = .length(u.media_player_length_changed.new_length)
        case .mediaPlayerVout: self = .videoOutputs(Int(u.media_player_vout.new_count))
        case .mediaPlayerESAdded, .mediaPlayerESDeleted, .mediaPlayerESSelected: self = .tracks
        case .mediaPlayerMuted: self = .muted(true)
        case .mediaPlayerUnmuted: self = .muted(false)
        case .mediaPlayerAudioVolume: self = .volume(u.media_player_audio_volume.volume)
        default: return nil
        }
    }

    /// The player events this relays — what `VlcPlayerEvents` has a method for.
    static let types: [VlcEventType] = [
        .mediaPlayerMediaChanged, .mediaPlayerNothingSpecial, .mediaPlayerOpening, .mediaPlayerBuffering,
        .mediaPlayerPlaying, .mediaPlayerPaused, .mediaPlayerStopped, .mediaPlayerEndReached,
        .mediaPlayerEncounteredError, .mediaPlayerTimeChanged, .mediaPlayerPositionChanged,
        .mediaPlayerSeekableChanged, .mediaPlayerPausableChanged, .mediaPlayerTitleChanged,
        .mediaPlayerChapterChanged, .mediaPlayerSnapshotTaken, .mediaPlayerLengthChanged,
        .mediaPlayerVout, .mediaPlayerESAdded, .mediaPlayerESDeleted, .mediaPlayerESSelected,
        .mediaPlayerMuted, .mediaPlayerUnmuted, .mediaPlayerAudioVolume,
    ]
}

/// A model's event methods, as closures — how `VlcMediaPlayer` reaches its
/// model without being generic over it. Weakly: the model holds the player,
/// not the other way round.
@MainActor
struct VlcPlayerHandlers {
    let deliver: (VlcPlayerEvent) -> Void

    init<Events: VlcPlayerEvents>(_ events: Events) {
        deliver = { [weak events] event in
            guard let events else { return }
            switch event {
            case .mediaChanged: events.mediaDidChange()
            case .state(let state): events.stateDidChange(state)
            case .buffering(let percent): events.bufferingDidChange(percent)
            case .time(let milliseconds): events.timeDidChange(.milliseconds(milliseconds))
            case .position(let position): events.positionDidChange(Double(position))
            case .length(let milliseconds): events.lengthDidChange(.milliseconds(milliseconds))
            case .seekable(let seekable): events.seekableDidChange(seekable)
            case .pausable(let pausable): events.pausableDidChange(pausable)
            case .tracks: events.tracksDidChange()
            case .volume(let volume): events.volumeDidChange(volume)
            case .muted(let muted): events.mutedDidChange(muted)
            case .videoOutputs(let count): events.videoOutputsDidChange(count)
            case .title(let title): events.titleDidChange(title)
            case .chapter(let chapter): events.chapterDidChange(chapter)
            case .snapshot(let path): events.snapshotTaken(path)
            case .endReached:
                events.stateDidChange(.ended)
                events.didReachEnd()
            case .failed:
                events.stateDidChange(.error)
                events.didFail()
            }
        }
    }
}

/// Attached to a player's event manager for every type in
/// `VlcPlayerEvent.types`; hands each event to the main queue, which keeps
/// their order, and from there to the handlers.
final class VlcEventRelay: @unchecked Sendable {
    private let manager: OpaquePointer
    private nonisolated(unsafe) var handlers: VlcPlayerHandlers?

    init(player: OpaquePointer) {
        manager = libvlc_media_player_event_manager(player)
        let opaque = Unmanaged.passUnretained(self).toOpaque()
        for type in VlcPlayerEvent.types {
            libvlc_event_attach(manager, type.rawValue, VlcEventRelay.callback, opaque)
        }
    }

    /// Where events go from now on — once.
    @MainActor
    func bind(_ handlers: VlcPlayerHandlers) {
        if self.handlers == nil { self.handlers = handlers }
    }

    @MainActor
    var isBound: Bool { handlers != nil }

    /// Called before the player is released: no event arrives after this.
    func detach() {
        let opaque = Unmanaged.passUnretained(self).toOpaque()
        for type in VlcPlayerEvent.types {
            libvlc_event_detach(manager, type.rawValue, VlcEventRelay.callback, opaque)
        }
    }

    private static let callback: libvlc_callback_t = { event, data in
        guard let event, let data, let copied = VlcPlayerEvent(event.pointee) else { return }
        // Alive here — it is detached before it goes — and kept alive by
        // the closure until the event is delivered.
        let relay = Unmanaged<VlcEventRelay>.fromOpaque(data).takeUnretainedValue()
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                relay.handlers?.deliver(copied)
            }
        }
    }
}
