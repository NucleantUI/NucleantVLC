//
//  VlcMediaPlayer+Android.swift
//  NucleantVLC
//
//  The player's calls whose C side differs per platform. Android's libvlc is
//  VideoLAN's libvlc-all AAR: 3.0.25 with libvlcjni's patches, one of which
//  gives set_time and set_position a fast-seek argument — false here, the
//  precise seek the other platforms' libvlc does.
//

#if os(Android)
import LibVLC

extension VlcMediaPlayer {

    /// Deinterlace with `mode`, or not at all with `nil`.
    public func setDeinterlace(_ mode: VlcDeinterlaceMode?) {
        libvlc_video_set_deinterlace(handle, mode?.rawValue)
    }

    /// Seek to `milliseconds` in.
    func seek(milliseconds: libvlc_time_t) {
        libvlc_media_player_set_time(handle, milliseconds, false)
    }

    /// Seek to `position` (0…1) through the media.
    func seek(position: Float) {
        libvlc_media_player_set_position(handle, position, false)
    }
}
#endif
