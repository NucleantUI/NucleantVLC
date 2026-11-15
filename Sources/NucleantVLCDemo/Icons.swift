//
//  Icons.swift
//  NucleantVLCDemo
//
//  The player's icons: Material Icons SVGs (Apache 2.0,
//  Resources/Icons/MaterialIcons-LICENSE.txt) from the icon catalog,
//  the target's resources (`.process("Resources/Icons")` in Package.swift),
//  loaded by URL.
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

/// The SVGs, each loaded once. They are this app's own files, so one that
/// is missing or does not parse is a broken build.
@MainActor
enum PlayerIconImages {
    static let play = load("play_arrow")
    static let pause = load("pause")
    static let skipBack = load("replay_10")
    static let skipForward = load("forward_10")
    static let speaker = load("volume_up")
    static let speakerMuted = load("volume_off")
    static let subtitles = load("subtitles")
    static let audio = load("audiotrack")
    static let playlist = load("playlist_play")
    static let previous = load("skip_previous")
    static let next = load("skip_next")
    static let close = load("close")

    private static func load(_ name: String) -> SvgImage {
        guard let url = url(of: name), let image = SvgImage(contentsOf: url) else {
            fatalError("icon \(name).svg is missing or not SVG")
        }
        return image
    }

    /// `name`.svg in the target's resources (`.process("Resources/Icons")`).
    private static func url(of name: String) -> URL? {
        #if os(Android)
        // Not `Bundle.module`: on Android its accessor looks next to the
        // executable (the zygote's) and fatalErrors. nucleant unpacks the
        // resource bundles beside the app's files instead, at
        // NUCLEANT_APP_PATH — as NucleantUI's own FontRegistry finds them.
        guard let root = ProcessInfo.processInfo.environment["NUCLEANT_APP_PATH"] else { return nil }
        return URL(fileURLWithPath: "\(root)/NucleantVLC_NucleantVLCDemo.resources/\(name).svg")
        #else
        return Bundle.module.url(forResource: name, withExtension: "svg")
        #endif
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
