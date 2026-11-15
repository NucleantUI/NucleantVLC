//
//  VlcMediaPlayer+iOS.swift
//  NucleantVLC
//
//  The player's calls whose C side differs per platform. iOS's libvlc is
//  MobileVLCKit's, 3.0.24 with VideoLAN's patches from the libvlc 4 branch:
//  `libvlc_video_set_deinterlace` takes whether to deinterlace (-1 auto,
//  0 off, 1 on) besides the filter.
//

#if os(iOS)
import LibVLC

extension VlcMediaPlayer {

    /// Deinterlace with `mode`, or not at all with `nil`.
    public func setDeinterlace(_ mode: VlcDeinterlaceMode?) {
        libvlc_video_set_deinterlace(handle, mode == nil ? 0 : 1, mode?.rawValue)
    }
}
#endif
