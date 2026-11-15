//
//  VlcMediaPlayer+MacOS.swift
//  NucleantVLC
//
//  The player's calls whose C side differs per platform. macOS's libvlc is
//  VLC.app's, plain 3.0.24.
//

#if os(macOS)
import LibVLC

extension VlcMediaPlayer {

    /// Deinterlace with `mode`, or not at all with `nil`.
    public func setDeinterlace(_ mode: VlcDeinterlaceMode?) {
        libvlc_video_set_deinterlace(handle, mode?.rawValue)
    }
}
#endif
