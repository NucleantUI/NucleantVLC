//
//  VlcEnumTests.swift
//  NucleantVLCTests
//
//  Every Swift case against the C constant it stands for.
//

import LibVLC
import Testing
@testable import NucleantVLC

struct VlcEnumTests {

    @Test func statesAreLibvlcs() {
        let pairs: [(VlcState, libvlc_state_t)] = [
            (.nothingSpecial, libvlc_NothingSpecial), (.opening, libvlc_Opening), (.buffering, libvlc_Buffering),
            (.playing, libvlc_Playing), (.paused, libvlc_Paused), (.stopped, libvlc_Stopped),
            (.ended, libvlc_Ended), (.error, libvlc_Error),
        ]
        for (swift, c) in pairs { #expect(swift.rawValue == Int32(c.rawValue), "\(swift)") }
        #expect(pairs.count == VlcState.allCases.count)
    }

    @Test func trackTypesAreLibvlcs() {
        #expect(VlcTrackType.unknown.rawValue == libvlc_track_unknown.rawValue)
        #expect(VlcTrackType.audio.rawValue == libvlc_track_audio.rawValue)
        #expect(VlcTrackType.video.rawValue == libvlc_track_video.rawValue)
        #expect(VlcTrackType.text.rawValue == libvlc_track_text.rawValue)
    }

    @Test func metaKeysAreLibvlcs() {
        #expect(VlcMeta.title.rawValue == Int32(libvlc_meta_Title.rawValue))
        #expect(VlcMeta.artworkURL.rawValue == Int32(libvlc_meta_ArtworkURL.rawValue))
        #expect(VlcMeta.discTotal.rawValue == Int32(libvlc_meta_DiscTotal.rawValue))
        #expect(VlcMeta.allCases.count == Int(libvlc_meta_DiscTotal.rawValue) + 1)
    }

    @Test func mediaEnumsAreLibvlcs() {
        #expect(VlcMediaType.playlist.rawValue == Int32(libvlc_media_type_playlist.rawValue))
        #expect(VlcParsedStatus.skipped.rawValue == Int32(libvlc_media_parsed_status_skipped.rawValue))
        #expect(VlcParsedStatus.done.rawValue == Int32(libvlc_media_parsed_status_done.rawValue))
        #expect(VlcParseOptions.network.rawValue == Int32(libvlc_media_parse_network.rawValue))
        #expect(VlcParseOptions.interact.rawValue == Int32(libvlc_media_do_interact.rawValue))
        // Untyped C enums: their constants come in as Int.
        #expect(Int(VlcMediaOptionFlags.trusted.rawValue) == libvlc_media_option_trusted)
        #expect(Int(VlcMediaOptionFlags.unique.rawValue) == libvlc_media_option_unique)
        #expect(VlcSlaveType.audio.rawValue == Int32(libvlc_media_slave_type_audio.rawValue))
        #expect(VlcVideoOrientation.rightBottom.rawValue == Int32(libvlc_video_orient_right_bottom.rawValue))
        #expect(VlcVideoProjection.cubemapLayoutStandard.rawValue == Int32(libvlc_video_projection_cubemap_layout_standard.rawValue))
    }

    @Test func playerEnumsAreLibvlcs() {
        #expect(VlcNavigateMode.popup.rawValue == Int32(libvlc_navigate_popup.rawValue))
        #expect(VlcPosition.disable.rawValue == libvlc_position_disable.rawValue)
        #expect(VlcPosition.bottomRight.rawValue == libvlc_position_bottom_right.rawValue)
        #expect(VlcTeletextKey.red.rawValue == Int32(libvlc_teletext_key_red.rawValue))
        #expect(VlcTeletextKey.index.rawValue == Int32(libvlc_teletext_key_index.rawValue))
        #expect(VlcAudioChannel.error.rawValue == libvlc_AudioChannel_Error.rawValue)
        #expect(VlcAudioChannel.dolbySurround.rawValue == libvlc_AudioChannel_Dolbys.rawValue)
        #expect(VlcPlayerRole.test.rawValue == Int32(libvlc_role_Test.rawValue))
        #expect(VlcLogLevel.notice.rawValue == Int32(LIBVLC_NOTICE.rawValue))
        #expect(VlcLogLevel.error.rawValue == Int32(LIBVLC_ERROR.rawValue))
        #expect(VlcAdjustOption.gamma.rawValue == Int32(libvlc_adjust_Gamma.rawValue))
        #expect(VlcMarqueeOption.text.rawValue == Int32(libvlc_marquee_Text.rawValue))
        #expect(VlcMarqueeOption.y.rawValue == Int32(libvlc_marquee_Y.rawValue))
        #expect(VlcLogoOption.position.rawValue == Int32(libvlc_logo_position.rawValue))
        #expect(VlcLogoOption.file.rawValue == Int32(libvlc_logo_file.rawValue))
        #expect(Int(VlcTitleFlags.interactive.rawValue) == libvlc_title_interactive)
    }

    @Test func eventTypesAreLibvlcs() {
        let pairs: [(VlcEventType, libvlc_event_e)] = [
            (.mediaMetaChanged, libvlc_MediaMetaChanged), (.mediaSubItemTreeAdded, libvlc_MediaSubItemTreeAdded),
            (.mediaPlayerMediaChanged, libvlc_MediaPlayerMediaChanged), (.mediaPlayerPlaying, libvlc_MediaPlayerPlaying),
            (.mediaPlayerEndReached, libvlc_MediaPlayerEndReached), (.mediaPlayerTimeChanged, libvlc_MediaPlayerTimeChanged),
            (.mediaPlayerVout, libvlc_MediaPlayerVout), (.mediaPlayerESSelected, libvlc_MediaPlayerESSelected),
            (.mediaPlayerAudioVolume, libvlc_MediaPlayerAudioVolume), (.mediaPlayerChapterChanged, libvlc_MediaPlayerChapterChanged),
            (.mediaListItemAdded, libvlc_MediaListItemAdded), (.mediaListEndReached, libvlc_MediaListEndReached),
            (.mediaListViewWillDeleteItem, libvlc_MediaListViewWillDeleteItem),
            (.mediaListPlayerStopped, libvlc_MediaListPlayerStopped),
            (.mediaDiscovererEnded, libvlc_MediaDiscovererEnded),
            (.rendererDiscovererItemDeleted, libvlc_RendererDiscovererItemDeleted),
            (.vlmMediaAdded, libvlc_VlmMediaAdded), (.vlmMediaInstanceStatusError, libvlc_VlmMediaInstanceStatusError),
        ]
        for (swift, c) in pairs { #expect(swift.rawValue == Int32(c.rawValue), "\(swift)") }
    }

    @Test func everyRelayedEventHasACase() {
        for type in VlcPlayerEvent.types {
            #expect(VlcEventType(rawValue: type.rawValue) != nil)
        }
    }
}
