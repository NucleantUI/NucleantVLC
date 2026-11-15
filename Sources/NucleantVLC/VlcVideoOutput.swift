//
//  VlcVideoOutput.swift
//  NucleantVLC
//
//  A player's video, on its way into the views that show it. libvlc
//  decodes into `VlcFramePool` — one per platform, each in its own file —
//  and every frame it hands over is drawn into every `VlcView`'s texture:
//  at the texture's own size (`ViewTexture.pixelWidth × pixelHeight`),
//  fitted to the video's shape, the rest black. The same frame is drawn
//  again when a view is resized, so a paused video follows its view too.
//

import LibVLC
import NucleantUI

/// The video a player decodes: its frames' size, the picture's own size,
/// and the shape of one pixel.
public struct VlcVideoFormat: Sendable, Equatable {
    /// The frames' size in pixels, as libvlc's memory output opened. That
    /// is the decoder's size, which can be more than the picture's — codecs
    /// decode in whole blocks (a 1080-line H.264 video is 1088), decoders
    /// align their rows — and libvlc then stretches the picture over all of
    /// it.
    public let width: Int
    public let height: Int
    /// The picture's own size, which sets its shape.
    public let visibleWidth: Int
    public let visibleHeight: Int
    /// The sample aspect ratio — 1 for square pixels.
    public let sampleAspect: Double

    /// Width ÷ height as the picture is meant to be shown.
    public var displayAspect: Double {
        Double(visibleWidth) * sampleAspect / Double(visibleHeight)
    }
}

/// Where a `VlcMediaPlayer`'s frames go.
@MainActor
public final class VlcVideoOutput {

    /// What is being decoded — `nil` until a video starts.
    public private(set) var format: VlcVideoFormat?

    /// Show the video at this width ÷ height instead of its own.
    public var aspectRatio: Double? {
        didSet {
            if aspectRatio != oldValue { redraw() }
        }
    }

    /// The textures of the views showing the player, each filled with
    /// every frame.
    public private(set) var textures: [ViewTexture<NucleantRenderNode>] = []

    private let player: OpaquePointer
    let frames: VlcFramePool

    init(player: OpaquePointer) {
        self.player = player
        frames = VlcFramePool()
        frames.output = self
        frames.install(on: player)
    }

    // MARK: - The views

    /// A view showing the player appeared, or changed size or scale.
    func textureDidChange(_ texture: ViewTexture<NucleantRenderNode>) {
        if !textures.contains(where: { $0 === texture }) {
            textures.append(texture)
        }
        draw(into: texture)
    }

    func textureDidDisappear(_ texture: ViewTexture<NucleantRenderNode>) {
        textures.removeAll { $0 === texture }
        frames.forget(ObjectIdentifier(texture))
    }

    // MARK: - From the frame pool

    /// libvlc opened its video output at `width × height`.
    func formatDidChange(width: Int, height: Int) {
        let track = videoTrack(width: width, height: height)
        format = VlcVideoFormat(
            width: width,
            height: height,
            visibleWidth: track?.width ?? width,
            visibleHeight: track?.height ?? height,
            sampleAspect: track?.sampleAspect ?? 1
        )
    }

    /// A new frame is waiting: draw it everywhere.
    func frameDidArrive() {
        guard frames.takeLatest() else { return }
        redraw()
    }

    // MARK: -

    /// The shape the video is shown at.
    private var shownAspect: Double? {
        aspectRatio ?? format?.displayAspect
    }

    private func redraw() {
        for texture in textures {
            draw(into: texture)
        }
    }

    private func draw(into texture: ViewTexture<NucleantRenderNode>) {
        guard let aspect = shownAspect, texture.isAttached else { return }
        frames.draw(into: texture, aspect: aspect)
    }

    /// The media's video track that `width × height` frames hold: its
    /// picture size and pixel shape, which libvlc's memory output does not
    /// pass on. Decoders pad (whole codec blocks, aligned rows), so the
    /// frames can be bigger than the picture: the largest track that fits
    /// inside them.
    private func videoTrack(width: Int, height: Int) -> VlcMediaTrack.Video? {
        guard let handle = libvlc_media_player_get_media(player) else { return nil }
        return VlcMedia(adopting: handle).tracks
            .compactMap(\.video)
            .filter { $0.width > 0 && $0.height > 0 && $0.width <= width && $0.height <= height }
            .max { $0.width * $0.height < $1.width * $1.height }
    }
}
