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

    /// Seek to `milliseconds` in.
    func seek(milliseconds: libvlc_time_t) {
        libvlc_media_player_set_time(handle, milliseconds)
    }

    /// Seek to `position` (0…1) through the media.
    func seek(position: Float) {
        libvlc_media_player_set_position(handle, position)
    }
}
#endif
