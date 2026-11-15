//
//  VlcFramePool+Android.swift
//  NucleantVLC
//
//  libvlc's memory video output, on Android, into plain memory: the
//  software path, built with NUCLEANT_VLC_ANDROID_SOFTWARE=1 (see
//  Package.swift). The GPU path, to be the default, is not written yet.
//
//  The iOS and macOS pools hand the GPU IOSurfaces; Android has nothing to
//  share that way with libvlc 3, so the frames stay on the CPU until the
//  last step:
//
//    * Decode. Each frame lands, as BGRA, in a buffer from a small pool, at
//      the video's own size. The pool is touched on libvlc's video thread
//      (setup, lock, unlock, display, cleanup) and on the main thread
//      (taking the newest frame), under one lock; neither side ever waits
//      for the other.
//    * Fit. On the main thread the newest frame is scaled into a buffer of
//      the view's texture size, the video's shape kept and the rest black —
//      or used as it is when it already is that size and shape.
//    * Show. That buffer is uploaded into the view's texture
//      (`ViewTexture.write(bgra:)`), which copies it before returning: the
//      buffer is free again straight after.
//
//  Three frames are in use at most — the one libvlc writes, the one it
//  displayed and the main thread has not taken yet, and the one the views
//  show (kept, so a resized view gets it again). A frame displayed before
//  the last was taken is skipped.
//

#if os(Android) && !NUCLEANT_VLC_ANDROID_SOFTWARE
#error("NucleantVLC on Android: the GPU video path is not written yet. Build the software one with NUCLEANT_VLC_ANDROID_SOFTWARE=1 (nucleant.toml [swift.env]).")
#elseif os(Android)
import Dispatch
import Foundation
import LibVLC
import NucleantUI

/// One BGRA frame in memory, `bytesPerRow` apart.
final class VlcFrame: @unchecked Sendable {
    let width: Int
    let height: Int
    let bytesPerRow: Int
    let pixels: UnsafeMutableRawPointer

    /// Rows and row pitch rounded up to 32 lines and 64 bytes: libvlc asks
    /// for multiples of 32, for the optimized decoders and converters that
    /// write whole blocks.
    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        bytesPerRow = (width * 4 + 63) & ~63
        let lines = (height + 31) & ~31
        pixels = UnsafeMutableRawPointer.allocate(byteCount: bytesPerRow * lines, alignment: 64)
    }

    deinit { pixels.deallocate() }

    /// Opaque black, every pixel.
    func clear() {
        let rows = pixels.bindMemory(to: UInt32.self, capacity: bytesPerRow / 4 * height)
        rows.update(repeating: Self.black, count: bytesPerRow / 4 * height)
    }

    /// B, G, R, A = 0, 0, 0, 255, as one little-endian word.
    static let black: UInt32 = 0xFF00_0000
}

final class VlcFramePool: @unchecked Sendable {

    /// Told on the main thread about formats and frames.
    nonisolated(unsafe) weak var output: VlcVideoOutput?

    // Shared with libvlc's video thread — under `lock`.
    private let lock = NSLock()
    private var size: (width: Int, height: Int)?
    private var spare: [VlcFrame] = []
    private var writing: VlcFrame?
    private var displayed: VlcFrame?
    private var deliveryScheduled = false

    // The main thread's own.
    private var shown: VlcFrame?
    /// Counts the frames shown: frames are reused, so this, not the frame,
    /// tells a new picture from the last.
    private var shownGeneration = 0
    private var fitted: [ObjectIdentifier: Fitted] = [:]

    /// A view's frame: the shown frame scaled into it, and what it was
    /// scaled from, so an unchanged frame is not scaled again.
    private struct Fitted {
        let frame: VlcFrame
        /// The `shownGeneration` it holds.
        var generation: Int
        var aspect: Double
        /// For each destination column of the picture, its source column —
        /// for a source `columnsSourceWidth` wide.
        var columns: [Int32]
        var columnsSourceWidth: Int
    }

    /// Route `player`'s video into this pool. The pool outlives the
    /// player's callbacks: the player stops (joining libvlc's video thread)
    /// before its output goes.
    func install(on player: OpaquePointer) {
        let opaque = Unmanaged.passUnretained(self).toOpaque()
        libvlc_video_set_callbacks(
            player,
            { opaque, planes in
                guard let opaque, let planes else { return nil }
                return Unmanaged<VlcFramePool>.fromOpaque(opaque).takeUnretainedValue().lockFrame(planes)
            },
            { _, _, _ in
                // Nothing to release: the frame's memory is the pool's.
            },
            { opaque, picture in
                guard let opaque, let picture else { return }
                Unmanaged<VlcFramePool>.fromOpaque(opaque).takeUnretainedValue().displayFrame(picture)
            },
            opaque
        )
        libvlc_video_set_format_callbacks(
            player,
            { opaque, chroma, width, height, pitches, lines in
                guard let pool = opaque?.pointee, let chroma, let width, let height, let pitches, let lines else {
                    return 0
                }
                return Unmanaged<VlcFramePool>.fromOpaque(pool).takeUnretainedValue()
                    .setup(chroma: chroma, width: width, height: height, pitches: pitches, lines: lines)
            },
            { opaque in
                guard let opaque else { return }
                Unmanaged<VlcFramePool>.fromOpaque(opaque).takeUnretainedValue().cleanup()
            }
        )
    }

    // MARK: - libvlc's video thread

    /// The output opens: BGRA at the decoded size, the pool's pitch and line
    /// count. Returns how many buffers there are, 0 to refuse.
    private func setup(
        chroma: UnsafeMutablePointer<CChar>,
        width: UnsafeMutablePointer<UInt32>,
        height: UnsafeMutablePointer<UInt32>,
        pitches: UnsafeMutablePointer<UInt32>,
        lines: UnsafeMutablePointer<UInt32>
    ) -> UInt32 {
        let w = Int(width.pointee), h = Int(height.pointee)
        guard w > 0, h > 0 else { return 0 }
        let first = VlcFrame(width: w, height: h)
        for (index, byte) in "BGRA".utf8.enumerated() {
            chroma[index] = CChar(bitPattern: byte)
        }
        pitches[0] = UInt32(first.bytesPerRow)
        lines[0] = UInt32((h + 31) & ~31)

        lock.lock()
        size = (w, h)
        spare = [first]
        writing = nil
        displayed = nil
        lock.unlock()

        DispatchQueue.main.async { [self] in
            MainActor.assumeIsolated { output?.formatDidChange(width: w, height: h) }
        }
        return 1
    }

    /// A buffer to decode the next frame into — a spare one, or a new one;
    /// never one the main thread may still read.
    private func lockFrame(_ planes: UnsafeMutablePointer<UnsafeMutableRawPointer?>) -> UnsafeMutableRawPointer? {
        lock.lock()
        var frame = spare.popLast()
        if frame == nil, let size {
            frame = VlcFrame(width: size.width, height: size.height)
        }
        writing = frame
        lock.unlock()
        guard let frame else { return nil }
        planes[0] = frame.pixels
        return Unmanaged.passUnretained(frame).toOpaque()
    }

    /// The frame is due: it is the newest, and the main thread is told.
    private func displayFrame(_ picture: UnsafeMutableRawPointer) {
        let frame = Unmanaged<VlcFrame>.fromOpaque(picture).takeUnretainedValue()
        lock.lock()
        if writing === frame {
            if let skipped = displayed { recycle(skipped) }
            displayed = frame
            writing = nil
        }
        let schedule = !deliveryScheduled
        deliveryScheduled = true
        lock.unlock()
        if schedule {
            DispatchQueue.main.async { [self] in
                MainActor.assumeIsolated { output?.frameDidArrive() }
            }
        }
    }

    /// The output closed. The frame the views show stays theirs.
    private func cleanup() {
        lock.lock()
        size = nil
        spare = []
        writing = nil
        displayed = nil
        lock.unlock()
    }

    /// Back among the spares, if it still fits the format. Under `lock`.
    private func recycle(_ frame: VlcFrame) {
        guard let size, spare.count < 3, frame.width == size.width, frame.height == size.height else { return }
        spare.append(frame)
    }

    // MARK: - The main thread

    /// Make the newest displayed frame the one the views show. False when
    /// there is none newer.
    @MainActor
    func takeLatest() -> Bool {
        lock.lock()
        deliveryScheduled = false
        guard let next = displayed else {
            lock.unlock()
            return false
        }
        displayed = nil
        if let previous = shown { recycle(previous) }
        lock.unlock()
        shown = next
        shownGeneration += 1
        return true
    }

    /// Draw the shown frame into `texture`, fitted at `aspect` (width ÷
    /// height).
    @MainActor
    func draw(into texture: ViewTexture<NucleantRenderNode>, aspect: Double) {
        guard let frame = frame(width: texture.pixelWidth, height: texture.pixelHeight,
                                aspect: aspect, for: ObjectIdentifier(texture))
        else { return }
        texture.write(bgra: frame.pixels, width: frame.width, height: frame.height, bytesPerRow: frame.bytesPerRow)
    }

    /// The shown frame as `width × height` pixels with its picture at
    /// `aspect`, the rest black: the decoded frame itself when it already
    /// is exactly that, else a frame kept for `key` (one per view) scaled
    /// into. `nil` before the first frame.
    @MainActor
    func frame(width: Int, height: Int, aspect: Double, for key: ObjectIdentifier) -> VlcFrame? {
        guard let source = shown, width > 0, height > 0, aspect > 0 else { return nil }
        let sourceAspect = Double(source.width) / Double(source.height)
        if source.width == width, source.height == height, abs(sourceAspect - aspect) < 0.001 {
            return source
        }

        var target = fitted[key]
        if let existing = target, existing.frame.width != width || existing.frame.height != height {
            target = nil
        }
        if target == nil {
            let frame = VlcFrame(width: width, height: height)
            frame.clear()
            target = Fitted(frame: frame, generation: -1, aspect: 0, columns: [], columnsSourceWidth: 0)
        }
        guard var target else { return nil }
        if target.generation == shownGeneration, target.aspect == aspect {
            return target.frame
        }

        // The picture's rectangle: as big as fits at `aspect`, centred.
        // libvlc spread the picture over the whole decoded frame, padding
        // included, so the whole frame goes into it — which also undoes
        // that stretch.
        let fitWidth: Int, fitHeight: Int
        if Double(width) / Double(height) > aspect {
            fitHeight = height
            fitWidth = max(1, min(width, Int((Double(height) * aspect).rounded())))
        } else {
            fitWidth = width
            fitHeight = max(1, min(height, Int((Double(width) / aspect).rounded())))
        }
        let x = (width - fitWidth) / 2, y = (height - fitHeight) / 2

        // A new shape leaves bars where the picture was: black again.
        if target.aspect != aspect || target.columns.count != fitWidth {
            target.frame.clear()
        }
        // The table follows the source as well as the picture's width: a
        // video of the same shape at another size (1080p, then 720p) keeps
        // the rectangle, and the old table would read past the new frame's
        // rows — into the next row's pixels, which shows as the picture
        // repeated.
        if target.columns.count != fitWidth || target.columnsSourceWidth != source.width {
            target.columns = (0..<fitWidth).map { Int32($0 * source.width / fitWidth) }
            target.columnsSourceWidth = source.width
        }
        target.columns.withUnsafeBufferPointer { columns in
            Self.scale(source, into: target.frame, x: x, y: y, width: fitWidth, height: fitHeight, columns: columns)
        }
        target.generation = shownGeneration
        target.aspect = aspect
        fitted[key] = target
        return target.frame
    }

    /// Nearest-neighbour scale of all of `source` into `width × height` at
    /// (`x`, `y`) of `target`. Optimized even in a debug build: it runs for
    /// every pixel of every frame.
    @_optimize(speed)
    private static func scale(
        _ source: VlcFrame,
        into target: VlcFrame,
        x: Int, y: Int, width: Int, height: Int,
        columns: UnsafeBufferPointer<Int32>
    ) {
        let sourceRow = source.bytesPerRow / 4, targetRow = target.bytesPerRow / 4
        let from = source.pixels.assumingMemoryBound(to: UInt32.self)
        let to = target.pixels.assumingMemoryBound(to: UInt32.self)
        for row in 0..<height {
            let sourceLine = from + (row * source.height / height) * sourceRow
            let targetLine = to + (y + row) * targetRow + x
            for column in 0..<width {
                targetLine[column] = sourceLine[Int(columns[column])]
            }
        }
    }

    /// A view went: its fitted frame goes too.
    @MainActor
    func forget(_ key: ObjectIdentifier) {
        fitted[key] = nil
    }
}
#endif
