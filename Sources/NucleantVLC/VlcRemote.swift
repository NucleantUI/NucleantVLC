//
//  VlcRemote.swift
//  NucleantVLC
//
//  The model a `VlcView` shows: an object that owns a player, hears its
//  events, and is the remote control for it — the same shape as
//  NucleantCEF's `CEFBrowserModel`. A model is an `@Observable` class that
//  holds a `VlcMediaPlayer` and keeps whichever of its events it cares
//  about in properties of its own.
//

import Foundation
import NucleantUI

/// Something that owns one player and controls it.
///
/// ```swift
/// @MainActor @Observable
/// final class MyVlcRemote: VlcRemote {
///     @ObservationIgnored let player = VlcMediaPlayer()
///     private(set) var state = VlcState.nothingSpecial
///     private(set) var time = Duration.zero
///
///     func stateDidChange(_ state: VlcState) { self.state = state }
///     func timeDidChange(_ time: Duration) { self.time = time }
/// }
///
/// @State var remote = MyVlcRemote()
///
/// VlcView(remote: remote)
/// ```
///
/// The player's events reach the remote once it is used — through any of
/// the commands below, or a `VlcView` showing it. Everything else the
/// player does is on `player`.
@MainActor
public protocol VlcRemote: VlcPlayerEvents, TextureSource where Node == NucleantRenderNode {
    var player: VlcMediaPlayer { get }
}

public extension VlcRemote {

    // MARK: - Remote control

    /// Make `media` the one to play — playing it at once when `playing`.
    func open(_ media: VlcMedia, playing: Bool = true) {
        player.bind(to: self)
        player.media = media
        if playing { player.play() }
    }

    /// Open `url` — a file or any address libvlc plays.
    func open(_ url: URL, playing: Bool = true) throws {
        open(try VlcMedia(url: url, instance: player.instance), playing: playing)
    }

    func play() {
        player.bind(to: self)
        player.play()
    }

    func pause() {
        player.pause()
    }

    func togglePause() {
        player.bind(to: self)
        player.togglePause()
    }

    func stop() {
        player.stop()
    }

    func seek(to time: Duration) {
        player.time = time
    }

    /// Seek `offset` from where playback is — back when negative.
    func seek(by offset: Duration) {
        player.time = max(.zero, player.time + offset)
    }

    /// Seek to `position`, 0…1 through the media.
    func seek(toPosition position: Double) {
        player.position = position
    }

    func setRate(_ rate: Float) {
        player.rate = rate
    }

    /// 0…200, 100 the media's own level.
    func setVolume(_ volume: Int) {
        player.volume = volume
    }

    func setMuted(_ muted: Bool) {
        player.isMuted = muted
    }

    func toggleMute() {
        player.toggleMute()
    }

    func selectAudioTrack(_ id: Int32) {
        player.audioTrack = id
    }

    /// -1 turns subtitles off.
    func selectSubtitleTrack(_ id: Int32) {
        player.subtitleTrack = id
    }

    // MARK: - TextureSource

    func textureDidChange(_ texture: ViewTexture<NucleantRenderNode>) {
        player.bind(to: self)
        player.video.textureDidChange(texture)
    }

    /// Nothing to do: the video fills the texture, which goes wherever the
    /// view goes.
    func textureDidMove(_ texture: ViewTexture<NucleantRenderNode>) {}

    func textureDidDisappear(_ texture: ViewTexture<NucleantRenderNode>) {
        player.video.textureDidDisappear(texture)
    }
}
