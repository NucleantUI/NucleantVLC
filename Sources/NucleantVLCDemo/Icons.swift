//
//  Icons.swift
//  NucleantVLCDemo
//
//  The player's icons: Material Icons SVGs (Apache 2.0,
//  Resources/Icons/MaterialIcons-LICENSE.txt) from the icon catalog,
//  compiled into the app (`.embedInCode` in Package.swift), so every
//  platform has them with no file to find at run time.
//

import Foundation
import NucleantUI

enum PlayerIcon {
    case play, pause, skipBack, skipForward, speaker, speakerMuted, subtitles, audio, playlist, previous, next, close

    /// The icon's SVG, parsed once.
    @MainActor
    var image: SvgImage {
        switch self {
        case .play: PlayerIconImages.play
        case .pause: PlayerIconImages.pause
        case .skipBack: PlayerIconImages.skipBack
        case .skipForward: PlayerIconImages.skipForward
        case .speaker: PlayerIconImages.speaker
        case .speakerMuted: PlayerIconImages.speakerMuted
        case .subtitles: PlayerIconImages.subtitles
        case .audio: PlayerIconImages.audio
        case .playlist: PlayerIconImages.playlist
        case .previous: PlayerIconImages.previous
        case .next: PlayerIconImages.next
        case .close: PlayerIconImages.close
        }
    }
}

/// The SVGs, each parsed once. They are this app's own files, so one that
/// does not parse is a broken build.
@MainActor
enum PlayerIconImages {
    static let play = parse(PackageResources.play_arrow_svg)
    static let pause = parse(PackageResources.pause_svg)
    static let skipBack = parse(PackageResources.replay_10_svg)
    static let skipForward = parse(PackageResources.forward_10_svg)
    static let speaker = parse(PackageResources.volume_up_svg)
    static let speakerMuted = parse(PackageResources.volume_off_svg)
    static let subtitles = parse(PackageResources.subtitles_svg)
    static let audio = parse(PackageResources.audiotrack_svg)
    static let playlist = parse(PackageResources.playlist_play_svg)
    static let previous = parse(PackageResources.skip_previous_svg)
    static let next = parse(PackageResources.skip_next_svg)
    static let close = parse(PackageResources.close_svg)

    private static func parse(_ bytes: [UInt8]) -> SvgImage {
        guard let image = SvgImage(data: Data(bytes)) else { fatalError("a bundled icon is not SVG") }
        return image
    }
}

/// An icon, tinted `style`.
@View
struct IconView<Style: ShapeStyle> {
    let icon: PlayerIcon
    let style: Style

    var body: some View {
        SvgView(icon.image)
            .resizable()
            .renderingMode(.template)
            .foregroundStyle(style)
    }
}

/// The translucent dark the controls sit on, over the video.
let glass = Color(white: 0, opacity: 0.5)

/// A round control over the video: an icon (and an optional caption in
/// it, like the 10 of the skip buttons) on glass, lit on hover.
@View
struct RoundButton {
    let icon: PlayerIcon
    let iconSize: Double
    let diameter: Double
    let caption: String?
    let action: () -> Void

    @State private var isHovered = false

    init(
        icon: PlayerIcon,
        iconSize: Double = 18,
        diameter: Double = 38,
        caption: String? = nil,
        _viewID: ViewID = #viewID,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.iconSize = iconSize
        self.diameter = diameter
        self.caption = caption
        self.action = action
        self._viewID = _viewID
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(white: isHovered ? 0.18 : 0, opacity: isHovered ? 0.65 : 0.5))
            IconView(icon: icon, style: Color.white)
                .frame(width: iconSize, height: iconSize)
            if let caption {
                Text(caption)
                    .font(.system(size: iconSize * 0.36))
                    .foregroundColor(.white)
                    .offset(y: iconSize * 0.06)
            }
        }
        .frame(width: diameter, height: diameter)
        .onHover { isHovered = $0 }
        .onTapGesture(perform: action)
    }
}
