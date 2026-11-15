//
//  Icons.swift
//  NucleantVLCDemo
//
//  The transport's icons, drawn as filled paths.
//

import NucleantUI

enum PlayerIcon {
    case play, pause, stop, previous, next, speaker, speakerMuted, close

    /// The icon in a `size` box.
    func path(in size: Size) -> Path {
        let w = size.width, h = size.height
        var path = Path()
        func point(_ x: Double, _ y: Double) -> Point { Point(x: w * x, y: h * y) }
        func triangle(_ a: Point, _ b: Point, _ c: Point) {
            path.move(to: a)
            path.addLine(to: b)
            path.addLine(to: c)
            path.closeSubpath()
        }
        switch self {
        case .play:
            triangle(point(0.25, 0.15), point(0.85, 0.5), point(0.25, 0.85))
        case .pause:
            path.addRect(Rect(x: w * 0.22, y: h * 0.17, width: w * 0.2, height: h * 0.66))
            path.addRect(Rect(x: w * 0.58, y: h * 0.17, width: w * 0.2, height: h * 0.66))
        case .stop:
            path.addRect(Rect(x: w * 0.22, y: h * 0.22, width: w * 0.56, height: h * 0.56))
        case .previous:
            path.addRect(Rect(x: w * 0.15, y: h * 0.2, width: w * 0.1, height: h * 0.6))
            triangle(point(0.85, 0.2), point(0.27, 0.5), point(0.85, 0.8))
        case .next:
            path.addRect(Rect(x: w * 0.75, y: h * 0.2, width: w * 0.1, height: h * 0.6))
            triangle(point(0.15, 0.2), point(0.73, 0.5), point(0.15, 0.8))
        case .speaker, .speakerMuted:
            path.move(to: point(0.12, 0.36))
            path.addLine(to: point(0.3, 0.36))
            path.addLine(to: point(0.52, 0.16))
            path.addLine(to: point(0.52, 0.84))
            path.addLine(to: point(0.3, 0.64))
            path.addLine(to: point(0.12, 0.64))
            path.closeSubpath()
            if self == .speakerMuted {
                path.addRect(Rect(x: w * 0.62, y: h * 0.46, width: w * 0.3, height: h * 0.08))
            } else {
                path.addRect(Rect(x: w * 0.62, y: h * 0.4, width: w * 0.07, height: h * 0.2))
                path.addRect(Rect(x: w * 0.78, y: h * 0.3, width: w * 0.07, height: h * 0.4))
            }
        case .close:
            path.addRect(Rect(x: w * 0.2, y: h * 0.45, width: w * 0.6, height: h * 0.1))
        }
        return path
    }
}

/// An icon, filled with `style`.
@View
struct IconView<Style: ShapeStyle> {
    let icon: PlayerIcon
    let style: Style

    init(icon: PlayerIcon, style: Style, _viewID: ViewID = #viewID) {
        self.icon = icon
        self.style = style
        self._viewID = _viewID
    }

    var body: some View {
        PathShape { size in icon.path(in: size) }
            .fill(style)
    }
}

/// A square transport button: an icon, lit on hover, dimmed when disabled.
@View
struct IconButton {
    let icon: PlayerIcon
    let size: Double
    let isEnabled: Bool
    let action: () -> Void

    @State private var isHovered = false

    init(icon: PlayerIcon, size: Double = 16, isEnabled: Bool = true, _viewID: ViewID = #viewID, action: @escaping () -> Void) {
        self.icon = icon
        self.size = size
        self.isEnabled = isEnabled
        self.action = action
        self._viewID = _viewID
    }

    var body: some View {
        IconView(icon: icon, style: isEnabled ? HierarchicalShapeStyle.primary : .tertiary)
            .frame(width: size, height: size)
            .padding(7)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(.fill)
                    .opacity(isHovered && isEnabled ? 1 : 0)
            )
            .onHover { isHovered = $0 }
            .onTapGesture { if isEnabled { action() } }
    }
}
