//
//  VlcEnums.swift
//  NucleantVLC
//
//  libvlc's C enums as Swift enums: each case's raw value is the C
//  constant's, named next to it. A value from libvlc becomes a case with
//  `Vlc…(rawValue:)`, and goes back as `.rawValue`. Bit masks are option
//  sets.
//

/// `libvlc_state_t`: where a player, or a media, is in its life.
public enum VlcState: Int32, CaseIterable, Sendable {
    case nothingSpecial = 0 // libvlc_NothingSpecial
    case opening = 1        // libvlc_Opening
    case buffering = 2      // libvlc_Buffering — libvlc no longer reports it as a state; see `bufferingDidChange`
    case playing = 3        // libvlc_Playing
    case paused = 4         // libvlc_Paused
    case stopped = 5        // libvlc_Stopped
    case ended = 6          // libvlc_Ended
    case error = 7          // libvlc_Error
}

/// `libvlc_track_type_t`.
public enum VlcTrackType: Int32, CaseIterable, Sendable {
    case unknown = -1 // libvlc_track_unknown
    case audio = 0    // libvlc_track_audio
    case video = 1    // libvlc_track_video
    case text = 2     // libvlc_track_text
}

/// `libvlc_meta_t`: the metadata a media can carry.
public enum VlcMeta: Int32, CaseIterable, Sendable {
    case title = 0        // libvlc_meta_Title
    case artist = 1       // libvlc_meta_Artist
    case genre = 2        // libvlc_meta_Genre
    case copyright = 3    // libvlc_meta_Copyright
    case album = 4        // libvlc_meta_Album
    case trackNumber = 5  // libvlc_meta_TrackNumber
    case description = 6  // libvlc_meta_Description
    case rating = 7       // libvlc_meta_Rating
    case date = 8         // libvlc_meta_Date
    case setting = 9      // libvlc_meta_Setting
    case url = 10         // libvlc_meta_URL
    case language = 11    // libvlc_meta_Language
    case nowPlaying = 12  // libvlc_meta_NowPlaying
    case publisher = 13   // libvlc_meta_Publisher
    case encodedBy = 14   // libvlc_meta_EncodedBy
    case artworkURL = 15  // libvlc_meta_ArtworkURL
    case trackID = 16     // libvlc_meta_TrackID
    case trackTotal = 17  // libvlc_meta_TrackTotal
    case director = 18    // libvlc_meta_Director
    case season = 19      // libvlc_meta_Season
    case episode = 20     // libvlc_meta_Episode
    case showName = 21    // libvlc_meta_ShowName
    case actors = 22      // libvlc_meta_Actors
    case albumArtist = 23 // libvlc_meta_AlbumArtist
    case discNumber = 24  // libvlc_meta_DiscNumber
    case discTotal = 25   // libvlc_meta_DiscTotal
}

/// `libvlc_media_type_t`.
public enum VlcMediaType: Int32, CaseIterable, Sendable {
    case unknown = 0   // libvlc_media_type_unknown
    case file = 1      // libvlc_media_type_file
    case directory = 2 // libvlc_media_type_directory
    case disc = 3      // libvlc_media_type_disc
    case stream = 4    // libvlc_media_type_stream
    case playlist = 5  // libvlc_media_type_playlist
}

/// `libvlc_media_parsed_status_t`: how a parse ended.
public enum VlcParsedStatus: Int32, CaseIterable, Sendable {
    case skipped = 1 // libvlc_media_parsed_status_skipped
    case failed = 2  // libvlc_media_parsed_status_failed
    case timeout = 3 // libvlc_media_parsed_status_timeout
    case done = 4    // libvlc_media_parsed_status_done
}

/// `libvlc_media_parse_flag_t`: what a parse may do. Empty is
/// `libvlc_media_parse_local` — parse local files only.
public struct VlcParseOptions: OptionSet, Sendable, Hashable {
    public let rawValue: Int32
    public init(rawValue: Int32) { self.rawValue = rawValue }

    public static let network = VlcParseOptions(rawValue: 0x01)      // libvlc_media_parse_network
    public static let fetchLocal = VlcParseOptions(rawValue: 0x02)   // libvlc_media_fetch_local
    public static let fetchNetwork = VlcParseOptions(rawValue: 0x04) // libvlc_media_fetch_network
    public static let interact = VlcParseOptions(rawValue: 0x08)     // libvlc_media_do_interact
}

/// `libvlc_media_option_t`: how an option added to a media is trusted.
public struct VlcMediaOptionFlags: OptionSet, Sendable, Hashable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    public static let trusted = VlcMediaOptionFlags(rawValue: 0x2) // libvlc_media_option_trusted
    public static let unique = VlcMediaOptionFlags(rawValue: 0x100) // libvlc_media_option_unique
}

/// `libvlc_media_slave_type_t`: an extra input played along a media.
public enum VlcSlaveType: Int32, CaseIterable, Sendable {
    case subtitle = 0 // libvlc_media_slave_type_subtitle
    case audio = 1    // libvlc_media_slave_type_audio
}

/// `libvlc_video_orient_t`.
public enum VlcVideoOrientation: Int32, CaseIterable, Sendable {
    case topLeft = 0     // libvlc_video_orient_top_left — normal
    case topRight = 1    // libvlc_video_orient_top_right — flipped horizontally
    case bottomLeft = 2  // libvlc_video_orient_bottom_left — flipped vertically
    case bottomRight = 3 // libvlc_video_orient_bottom_right — rotated 180°
    case leftTop = 4     // libvlc_video_orient_left_top — transposed
    case leftBottom = 5  // libvlc_video_orient_left_bottom — rotated 90° clockwise
    case rightTop = 6    // libvlc_video_orient_right_top — rotated 90° anti-clockwise
    case rightBottom = 7 // libvlc_video_orient_right_bottom — anti-transposed
}

/// `libvlc_video_projection_t`.
public enum VlcVideoProjection: Int32, CaseIterable, Sendable {
    case rectangular = 0               // libvlc_video_projection_rectangular
    case equirectangular = 1           // libvlc_video_projection_equirectangular — 360° spherical
    case cubemapLayoutStandard = 0x100 // libvlc_video_projection_cubemap_layout_standard
}

/// `libvlc_navigate_mode_t`: moves through a DVD-style menu.
public enum VlcNavigateMode: Int32, CaseIterable, Sendable {
    case activate = 0 // libvlc_navigate_activate
    case up = 1       // libvlc_navigate_up
    case down = 2     // libvlc_navigate_down
    case left = 3     // libvlc_navigate_left
    case right = 4    // libvlc_navigate_right
    case popup = 5    // libvlc_navigate_popup
}

/// `libvlc_position_t`: where on the video a text is shown.
public enum VlcPosition: Int32, CaseIterable, Sendable {
    case disable = -1    // libvlc_position_disable
    case center = 0      // libvlc_position_center
    case left = 1        // libvlc_position_left
    case right = 2       // libvlc_position_right
    case top = 3         // libvlc_position_top
    case topLeft = 4     // libvlc_position_top_left
    case topRight = 5    // libvlc_position_top_right
    case bottom = 6      // libvlc_position_bottom
    case bottomLeft = 7  // libvlc_position_bottom_left
    case bottomRight = 8 // libvlc_position_bottom_right
}

/// `libvlc_teletext_key_t`: teletext's colored keys and the index page.
public enum VlcTeletextKey: Int32, CaseIterable, Sendable {
    case red = 0x72_0000    // libvlc_teletext_key_red ('r' << 16)
    case green = 0x67_0000  // libvlc_teletext_key_green ('g' << 16)
    case yellow = 0x79_0000 // libvlc_teletext_key_yellow ('y' << 16)
    case blue = 0x62_0000   // libvlc_teletext_key_blue ('b' << 16)
    case index = 0x69_0000  // libvlc_teletext_key_index ('i' << 16)
}

/// `libvlc_audio_output_channel_t`.
public enum VlcAudioChannel: Int32, CaseIterable, Sendable {
    case error = -1        // libvlc_AudioChannel_Error
    case stereo = 1        // libvlc_AudioChannel_Stereo
    case reverseStereo = 2 // libvlc_AudioChannel_RStereo
    case left = 3          // libvlc_AudioChannel_Left
    case right = 4         // libvlc_AudioChannel_Right
    case dolbySurround = 5 // libvlc_AudioChannel_Dolbys
}

/// `libvlc_media_player_role_t`: what a player is for, as the system's
/// audio policy sees it.
public enum VlcPlayerRole: Int32, CaseIterable, Sendable {
    case none = 0          // libvlc_role_None
    case music = 1         // libvlc_role_Music
    case video = 2         // libvlc_role_Video
    case communication = 3 // libvlc_role_Communication
    case game = 4          // libvlc_role_Game
    case notification = 5  // libvlc_role_Notification
    case animation = 6     // libvlc_role_Animation
    case production = 7    // libvlc_role_Production
    case accessibility = 8 // libvlc_role_Accessibility
    case test = 9          // libvlc_role_Test
}

/// `libvlc_log_level`.
public enum VlcLogLevel: Int32, CaseIterable, Sendable, Comparable {
    case debug = 0   // LIBVLC_DEBUG
    case notice = 2  // LIBVLC_NOTICE
    case warning = 3 // LIBVLC_WARNING
    case error = 4   // LIBVLC_ERROR

    public static func < (lhs: VlcLogLevel, rhs: VlcLogLevel) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// `libvlc_video_adjust_option_t`: the picture's color adjustments.
public enum VlcAdjustOption: Int32, CaseIterable, Sendable {
    case enable = 0     // libvlc_adjust_Enable — 0 or 1
    case contrast = 1   // libvlc_adjust_Contrast — 0…2, 1 unchanged
    case brightness = 2 // libvlc_adjust_Brightness — 0…2, 1 unchanged
    case hue = 3        // libvlc_adjust_Hue — degrees, -180…180
    case saturation = 4 // libvlc_adjust_Saturation — 0…3, 1 unchanged
    case gamma = 5      // libvlc_adjust_Gamma — 0.01…10, 1 unchanged
}

/// `libvlc_video_marquee_option_t`: a text drawn over the video.
public enum VlcMarqueeOption: Int32, CaseIterable, Sendable {
    case enable = 0  // libvlc_marquee_Enable
    case text = 1    // libvlc_marquee_Text — string option
    case color = 2   // libvlc_marquee_Color — 0xRRGGBB
    case opacity = 3 // libvlc_marquee_Opacity — 0…255
    case position = 4 // libvlc_marquee_Position — a `VlcPosition`
    case refresh = 5 // libvlc_marquee_Refresh — milliseconds
    case size = 6    // libvlc_marquee_Size — pixels
    case timeout = 7 // libvlc_marquee_Timeout — milliseconds, 0 for always
    case x = 8       // libvlc_marquee_X
    case y = 9       // libvlc_marquee_Y
}

/// `libvlc_video_logo_option_t`: an image drawn over the video.
public enum VlcLogoOption: Int32, CaseIterable, Sendable {
    case enable = 0   // libvlc_logo_enable
    case file = 1     // libvlc_logo_file — string option: "file,d,t;file,d,t;…"
    case x = 2        // libvlc_logo_x
    case y = 3        // libvlc_logo_y
    case delay = 4    // libvlc_logo_delay — milliseconds per image
    case `repeat` = 5 // libvlc_logo_repeat — -1 forever, 0 never
    case opacity = 6  // libvlc_logo_opacity — 0…255
    case position = 7 // libvlc_logo_position — a `VlcPosition`
}

/// `libvlc_title_description_t`'s flags.
public struct VlcTitleFlags: OptionSet, Sendable, Hashable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    public static let menu = VlcTitleFlags(rawValue: 0x01)        // libvlc_title_menu
    public static let interactive = VlcTitleFlags(rawValue: 0x02) // libvlc_title_interactive
}

/// The modes `libvlc_video_set_deinterlace` takes — strings in libvlc,
/// listed here.
public enum VlcDeinterlaceMode: String, CaseIterable, Sendable {
    case blend, bob, discard, linear, mean, x, yadif, yadif2x, phosphor, ivtc
}

/// `libvlc_event_e`: what an event manager reports, by category — media,
/// media player, media list, media list player, discoverers, VLM.
public enum VlcEventType: Int32, CaseIterable, Sendable {
    case mediaMetaChanged = 0             // libvlc_MediaMetaChanged
    case mediaSubItemAdded = 1            // libvlc_MediaSubItemAdded
    case mediaDurationChanged = 2         // libvlc_MediaDurationChanged
    case mediaParsedChanged = 3           // libvlc_MediaParsedChanged
    case mediaFreed = 4                   // libvlc_MediaFreed
    case mediaStateChanged = 5            // libvlc_MediaStateChanged
    case mediaSubItemTreeAdded = 6        // libvlc_MediaSubItemTreeAdded

    case mediaPlayerMediaChanged = 0x100  // libvlc_MediaPlayerMediaChanged
    case mediaPlayerNothingSpecial = 0x101 // libvlc_MediaPlayerNothingSpecial
    case mediaPlayerOpening = 0x102       // libvlc_MediaPlayerOpening
    case mediaPlayerBuffering = 0x103     // libvlc_MediaPlayerBuffering
    case mediaPlayerPlaying = 0x104       // libvlc_MediaPlayerPlaying
    case mediaPlayerPaused = 0x105        // libvlc_MediaPlayerPaused
    case mediaPlayerStopped = 0x106       // libvlc_MediaPlayerStopped
    case mediaPlayerForward = 0x107       // libvlc_MediaPlayerForward
    case mediaPlayerBackward = 0x108      // libvlc_MediaPlayerBackward
    case mediaPlayerEndReached = 0x109    // libvlc_MediaPlayerEndReached
    case mediaPlayerEncounteredError = 0x10A // libvlc_MediaPlayerEncounteredError
    case mediaPlayerTimeChanged = 0x10B   // libvlc_MediaPlayerTimeChanged
    case mediaPlayerPositionChanged = 0x10C // libvlc_MediaPlayerPositionChanged
    case mediaPlayerSeekableChanged = 0x10D // libvlc_MediaPlayerSeekableChanged
    case mediaPlayerPausableChanged = 0x10E // libvlc_MediaPlayerPausableChanged
    case mediaPlayerTitleChanged = 0x10F  // libvlc_MediaPlayerTitleChanged
    case mediaPlayerSnapshotTaken = 0x110 // libvlc_MediaPlayerSnapshotTaken
    case mediaPlayerLengthChanged = 0x111 // libvlc_MediaPlayerLengthChanged
    case mediaPlayerVout = 0x112          // libvlc_MediaPlayerVout
    case mediaPlayerScrambledChanged = 0x113 // libvlc_MediaPlayerScrambledChanged
    case mediaPlayerESAdded = 0x114       // libvlc_MediaPlayerESAdded
    case mediaPlayerESDeleted = 0x115     // libvlc_MediaPlayerESDeleted
    case mediaPlayerESSelected = 0x116    // libvlc_MediaPlayerESSelected
    case mediaPlayerCorked = 0x117        // libvlc_MediaPlayerCorked
    case mediaPlayerUncorked = 0x118      // libvlc_MediaPlayerUncorked
    case mediaPlayerMuted = 0x119         // libvlc_MediaPlayerMuted
    case mediaPlayerUnmuted = 0x11A       // libvlc_MediaPlayerUnmuted
    case mediaPlayerAudioVolume = 0x11B   // libvlc_MediaPlayerAudioVolume
    case mediaPlayerAudioDevice = 0x11C   // libvlc_MediaPlayerAudioDevice
    case mediaPlayerChapterChanged = 0x11D // libvlc_MediaPlayerChapterChanged

    case mediaListItemAdded = 0x200       // libvlc_MediaListItemAdded
    case mediaListWillAddItem = 0x201     // libvlc_MediaListWillAddItem
    case mediaListItemDeleted = 0x202     // libvlc_MediaListItemDeleted
    case mediaListWillDeleteItem = 0x203  // libvlc_MediaListWillDeleteItem
    case mediaListEndReached = 0x204      // libvlc_MediaListEndReached

    case mediaListViewItemAdded = 0x300   // libvlc_MediaListViewItemAdded
    case mediaListViewWillAddItem = 0x301 // libvlc_MediaListViewWillAddItem
    case mediaListViewItemDeleted = 0x302 // libvlc_MediaListViewItemDeleted
    case mediaListViewWillDeleteItem = 0x303 // libvlc_MediaListViewWillDeleteItem

    case mediaListPlayerPlayed = 0x400    // libvlc_MediaListPlayerPlayed
    case mediaListPlayerNextItemSet = 0x401 // libvlc_MediaListPlayerNextItemSet
    case mediaListPlayerStopped = 0x402   // libvlc_MediaListPlayerStopped

    case mediaDiscovererStarted = 0x500   // libvlc_MediaDiscovererStarted
    case mediaDiscovererEnded = 0x501     // libvlc_MediaDiscovererEnded
    case rendererDiscovererItemAdded = 0x502 // libvlc_RendererDiscovererItemAdded
    case rendererDiscovererItemDeleted = 0x503 // libvlc_RendererDiscovererItemDeleted

    case vlmMediaAdded = 0x600            // libvlc_VlmMediaAdded
    case vlmMediaRemoved = 0x601          // libvlc_VlmMediaRemoved
    case vlmMediaChanged = 0x602          // libvlc_VlmMediaChanged
    case vlmMediaInstanceStarted = 0x603  // libvlc_VlmMediaInstanceStarted
    case vlmMediaInstanceStopped = 0x604  // libvlc_VlmMediaInstanceStopped
    case vlmMediaInstanceStatusInit = 0x605 // libvlc_VlmMediaInstanceStatusInit
    case vlmMediaInstanceStatusOpening = 0x606 // libvlc_VlmMediaInstanceStatusOpening
    case vlmMediaInstanceStatusPlaying = 0x607 // libvlc_VlmMediaInstanceStatusPlaying
    case vlmMediaInstanceStatusPause = 0x608 // libvlc_VlmMediaInstanceStatusPause
    case vlmMediaInstanceStatusEnd = 0x609 // libvlc_VlmMediaInstanceStatusEnd
    case vlmMediaInstanceStatusError = 0x60A // libvlc_VlmMediaInstanceStatusError
}
