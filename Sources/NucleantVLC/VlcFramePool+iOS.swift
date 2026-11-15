//
//  VlcFramePool+iOS.swift
//  NucleantVLC
//
//  libvlc's memory video output, on iOS, into IOSurfaces.
//
//  libvlc 3 renders into nothing a GPU API can hand it — its memory output
//  (`libvlc_video_set_callbacks`) decodes into buffers the app gives it, at
//  a size fixed when the output opens. So:
//
//    * Decode. Each frame lands, as BGRA, in an IOSurface-backed pixel
//      buffer from a small pool, at the video's own size. The pool is
//      touched on libvlc's video thread (setup, lock, unlock, display,
//      cleanup) and on the main thread (taking the newest frame), under one
//      lock; neither side ever waits for the other.
//    * Fit. On the main thread the newest frame is scaled by VideoToolbox
//      (`VTPixelTransferSession`, letterboxed) into a buffer of the view's
//      texture size, the video's shape kept and the rest black — or used as
//      it is when it already is that size and shape.
//    * Show. That buffer's IOSurface is copied into the view's texture,
//      GPU to GPU (`ViewTexture.write(ioSurface:)`), which returns once the
//      copy is done: the buffer is free again straight after.
//
//  Three frames are in use at most — the one libvlc writes, the one it
//  displayed and the main thread has not taken yet, and the one the views
//  show (kept, so a resized view gets it again). A frame displayed before
//  the last was taken is skipped.
//

#if os(iOS)
import CoreVideo
import Dispatch
import Foundation
import IOSurface
import LibVLC
import NucleantUI
import VideoToolbox

final class VlcFramePool: @unchecked Sendable {

    /// Told on the main thread about formats and frames.
    nonisolated(unsafe) weak var output: VlcVideoOutput?

    // Shared with libvlc's video thread — under `lock`.
    private let lock = NSLock()
    private var size: (width: Int, height: Int)?
    private var spare: [CVPixelBuffer] = []
    private var writing: CVPixelBuffer?
    private var displayed: CVPixelBuffer?
    private var deliveryScheduled = false

    // The main thread's own.
    private var shown: CVPixelBuffer?
    private var fitted: [ObjectIdentifier: CVPixelBuffer] = [:]
    private var transfer: VTPixelTransferSession?

    deinit {
        if let transfer { VTPixelTransferSessionInvalidate(transfer) }
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
            { opaque, picture, _ in
                guard let opaque, let picture else { return }
                Unmanaged<VlcFramePool>.fromOpaque(opaque).takeUnretainedValue().unlockFrame(picture)
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

    /// The output opens: BGRA at the decoded size, the pitch of the pool's
    /// buffers. Returns how many buffers there are, 0 to refuse.
    private func setup(
        chroma: UnsafeMutablePointer<CChar>,
        width: UnsafeMutablePointer<UInt32>,
        height: UnsafeMutablePointer<UInt32>,
        pitches: UnsafeMutablePointer<UInt32>,
        lines: UnsafeMutablePointer<UInt32>
    ) -> UInt32 {
        let w = Int(width.pointee), h = Int(height.pointee)
        guard w > 0, h > 0, let first = Self.makeBuffer(width: w, height: h) else { return 0 }
        for (index, byte) in "BGRA".utf8.enumerated() {
            chroma[index] = CChar(bitPattern: byte)
        }
        pitches[0] = UInt32(CVPixelBufferGetBytesPerRow(first))
        lines[0] = UInt32(h)

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
        var buffer = spare.popLast()
        if buffer == nil, let size {
            buffer = Self.makeBuffer(width: size.width, height: size.height)
        }
        writing = buffer
        lock.unlock()
        guard let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        planes[0] = CVPixelBufferGetBaseAddress(buffer)
        return Unmanaged.passUnretained(buffer).toOpaque()
    }

    private func unlockFrame(_ picture: UnsafeMutableRawPointer) {
        let buffer = Unmanaged<CVPixelBuffer>.fromOpaque(picture).takeUnretainedValue()
        CVPixelBufferUnlockBaseAddress(buffer, [])
    }

    /// The frame is due: it is the newest, and the main thread is told.
    private func displayFrame(_ picture: UnsafeMutableRawPointer) {
        let buffer = Unmanaged<CVPixelBuffer>.fromOpaque(picture).takeUnretainedValue()
        lock.lock()
        if writing === buffer {
            if let skipped = displayed { recycle(skipped) }
            displayed = buffer
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
    private func recycle(_ buffer: CVPixelBuffer) {
        guard let size, spare.count < 3,
              CVPixelBufferGetWidth(buffer) == size.width, CVPixelBufferGetHeight(buffer) == size.height
        else { return }
        spare.append(buffer)
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
        return true
    }

    /// Draw the shown frame into `texture`, fitted at `aspect` (width ÷
    /// height).
    @MainActor
    func draw(into texture: ViewTexture<NucleantRenderNode>, aspect: Double) {
        guard let surface = frame(width: texture.pixelWidth, height: texture.pixelHeight,
                                  aspect: aspect, for: ObjectIdentifier(texture))
        else { return }
        texture.write(ioSurface: Unmanaged.passUnretained(surface).toOpaque())
    }

    /// The shown frame as `width × height` pixels with its picture at
    /// `aspect`, the rest black: the decoded buffer itself when it already
    /// is exactly that, else a buffer kept for `key` (one per view) scaled
    /// into. `nil` before the first frame.
    @MainActor
    func frame(width: Int, height: Int, aspect: Double, for key: ObjectIdentifier) -> IOSurfaceRef? {
        guard let source = shown, width > 0, height > 0 else { return nil }
        let sourceWidth = CVPixelBufferGetWidth(source), sourceHeight = CVPixelBufferGetHeight(source)
        let sourceAspect = Double(sourceWidth) / Double(sourceHeight)
        if sourceWidth == width, sourceHeight == height, abs(sourceAspect - aspect) < 0.001 {
            return CVPixelBufferGetIOSurface(source)?.takeUnretainedValue()
        }

        var target = fitted[key]
        if let existing = target,
           CVPixelBufferGetWidth(existing) != width || CVPixelBufferGetHeight(existing) != height {
            target = nil
        }
        if target == nil {
            target = Self.makeBuffer(width: width, height: height)
            fitted[key] = target
        }
        guard let target, let transfer = transferSession() else { return nil }

        // The shape to keep, told as the shape of one source pixel — which
        // also undoes the stretch of a picture libvlc spread over a padded
        // frame.
        let pixelAspect = aspect / sourceAspect
        let spacing: [CFString: Int] = [
            kCVImageBufferPixelAspectRatioHorizontalSpacingKey: Int((pixelAspect * 10_000).rounded()),
            kCVImageBufferPixelAspectRatioVerticalSpacingKey: 10_000,
        ]
        CVBufferSetAttachment(source, kCVImageBufferPixelAspectRatioKey, spacing as CFDictionary, .shouldNotPropagate)
        guard VTPixelTransferSessionTransferImage(transfer, from: source, to: target) == noErr else { return nil }
        return CVPixelBufferGetIOSurface(target)?.takeUnretainedValue()
    }

    /// A view went: its fitted buffer goes too.
    @MainActor
    func forget(_ key: ObjectIdentifier) {
        fitted[key] = nil
    }

    @MainActor
    private func transferSession() -> VTPixelTransferSession? {
        if let transfer { return transfer }
        var session: VTPixelTransferSession?
        guard VTPixelTransferSessionCreate(allocator: nil, pixelTransferSessionOut: &session) == noErr,
              let session
        else { return nil }
        VTSessionSetProperty(session, key: kVTPixelTransferPropertyKey_ScalingMode, value: kVTScalingMode_Letterbox)
        // Square destination pixels: only with the destination's pixel
        // aspect known does the letterbox take the source's into account.
        let square: [CFString: Int] = [
            kCVImageBufferPixelAspectRatioHorizontalSpacingKey: 1,
            kCVImageBufferPixelAspectRatioVerticalSpacingKey: 1,
        ]
        VTSessionSetProperty(session, key: kVTPixelTransferPropertyKey_DestinationPixelAspectRatio, value: square as CFDictionary)
        transfer = session
        return session
    }

    /// An IOSurface-backed BGRA buffer, laid out as Metal (and so MoltenVK's
    /// IOSurface import) wants it.
    static func makeBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        let attributes: [CFString: CFTypeRef] = [
            kCVPixelBufferIOSurfacePropertiesKey: [CFString: CFTypeRef]() as CFDictionary,
            kCVPixelBufferMetalCompatibilityKey: kCFBooleanTrue,
        ]
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, attributes as CFDictionary, &buffer)
        return status == kCVReturnSuccess ? buffer : nil
    }
}
#endif
