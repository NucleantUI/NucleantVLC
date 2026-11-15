//
//  Icons.swift
//  NucleantVLCDemo
//
//  The player's icons, drawn as paths — filled glyphs, and stroked ones
//  for the curved arrows.
//

import NucleantUI

enum PlayerIcon {
    case play, pause, skipBack, skipForward, speaker, speakerMuted, subtitles, audio, playlist, previous, next, close

    /// Drawn with a stroke, not filled.
    var isStroked: Bool {
        switch self {
        case .skipBack, .skipForward, .close: true
        default: false
        }
    }

    /// The icon in a `size` box.
    func path(in size: Size) -> Path {
        let w = size.width, h = size.height
        var path = Path()
        func point(_ x: Double, _ y: Double) -> Point { Point(x: w * x, y: h * y) }
        func polygon(_ points: Point...) {
            path.move(to: points[0])
            for p in points.dropFirst() { path.addLine(to: p) }
            path.closeSubpath()
        }
        switch self {
        case .play:
            polygon(point(0.24, 0.12), point(0.88, 0.5), point(0.24, 0.88))
        case .pause:
            path.addRoundedRect(in: Rect(x: w * 0.2, y: h * 0.14, width: w * 0.2, height: h * 0.72), cornerSize: Size(width: w * 0.04, height: w * 0.04))
            path.addRoundedRect(in: Rect(x: w * 0.6, y: h * 0.14, width: w * 0.2, height: h * 0.72), cornerSize: Size(width: w * 0.04, height: w * 0.04))
        case .skipBack, .skipForward:
            // Most of a circle, open at the top, with an arrowhead where it
            // starts: anti-clockwise back, clockwise forward.
            let forward = self == .skipForward
            let center = point(0.5, 0.54), radius = min(w, h) * 0.4
            path.addArc(
                center: center, radius: radius,
                startAngle: .degrees(forward ? -60 : -120), endAngle: .degrees(forward ? 240 : -300),
                clockwise: !forward
            )
            let tip = Point(x: center.x + (forward ? 0.5 : -0.5) * radius, y: center.y - 0.866 * radius)
            let head = radius * 0.42
            path.move(to: Point(x: tip.x + (forward ? -head : head), y: tip.y - head * 0.35))
            path.addLine(to: tip)
            path.addLine(to: Point(x: tip.x + (forward ? -head * 0.3 : head * 0.3), y: tip.y + head))
        case .speaker, .speakerMuted:
            polygon(point(0.08, 0.36), point(0.28, 0.36), point(0.52, 0.14), point(0.52, 0.86), point(0.28, 0.64), point(0.08, 0.64))
            if self == .speakerMuted {
                path.addRect(Rect(x: w * 0.62, y: h * 0.46, width: w * 0.32, height: h * 0.08))
            } else {
                path.addRoundedRect(in: Rect(x: w * 0.62, y: h * 0.38, width: w * 0.08, height: h * 0.24), cornerSize: Size(width: w * 0.04, height: w * 0.04))
                path.addRoundedRect(in: Rect(x: w * 0.78, y: h * 0.26, width: w * 0.08, height: h * 0.48), cornerSize: Size(width: w * 0.04, height: w * 0.04))
            }
        case .subtitles:
            // A speech bubble with two lines of text cut out.
            path.addRoundedRect(in: Rect(x: w * 0.06, y: h * 0.14, width: w * 0.88, height: h * 0.58), cornerSize: Size(width: w * 0.14, height: w * 0.14))
            polygon(point(0.24, 0.66), point(0.44, 0.66), point(0.26, 0.88))
        case .audio:
            // Five bars of a waveform.
            for (index, height) in [0.36, 0.7, 0.52, 0.86, 0.44].enumerated() {
                let x = w * (0.1 + Double(index) * 0.17)
                path.addRoundedRect(
                    in: Rect(x: x, y: h * (1 - height) / 2, width: w * 0.11, height: h * height),
                    cornerSize: Size(width: w * 0.05, height: w * 0.05)
                )
            }
        case .playlist:
            for row in 0..<3 {
                let y = h * (0.2 + Double(row) * 0.27)
                path.addRoundedRect(in: Rect(x: w * 0.08, y: y, width: w * 0.12, height: h * 0.12), cornerSize: Size(width: w * 0.03, height: w * 0.03))
                path.addRoundedRect(in: Rect(x: w * 0.3, y: y, width: w * 0.62, height: h * 0.12), cornerSize: Size(width: w * 0.03, height: w * 0.03))
            }
        case .previous:
            path.addRect(Rect(x: w * 0.14, y: h * 0.2, width: w * 0.1, height: h * 0.6))
            polygon(point(0.86, 0.2), point(0.26, 0.5), point(0.86, 0.8))
        case .next:
            path.addRect(Rect(x: w * 0.76, y: h * 0.2, width: w * 0.1, height: h * 0.6))
            polygon(point(0.14, 0.2), point(0.74, 0.5), point(0.14, 0.8))
        case .close:
            path.move(to: point(0.24, 0.24))
            path.addLine(to: point(0.76, 0.76))
            path.move(to: point(0.76, 0.24))
            path.addLine(to: point(0.24, 0.76))
        }
        return path
    }
}

/// An icon in `style`: filled, or stroked `lineWidth` wide.
@View
struct IconView<Style: ShapeStyle> {
    let icon: PlayerIcon
    let style: Style
    let lineWidth: Double

    init(icon: PlayerIcon, style: Style, lineWidth: Double = 2, _viewID: ViewID = #viewID) {
        self.icon = icon
        self.style = style
        self.lineWidth = lineWidth
        self._viewID = _viewID
    }

    var body: some View {
        if icon.isStroked {
            PathShape { size in icon.path(in: size) }
                .stroke(style, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        } else {
            PathShape { size in icon.path(in: size) }
                .fill(style)
        }
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
            IconView(icon: icon, style: Color.white, lineWidth: max(2, iconSize / 11))
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
