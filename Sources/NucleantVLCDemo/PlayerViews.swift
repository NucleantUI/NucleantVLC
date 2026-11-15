//
//  PlayerViews.swift
//  NucleantVLCDemo
//
//  The window: the video, edge to edge, and its controls floating over it
//  on glass — title and volume at the top, skip back / play-pause / skip
//  forward in the middle, speed, audio and subtitle menus and the seek bar
//  at the bottom. While a video plays the controls fade out a few seconds
//  after the last press; a press on the video brings them back (and
//  another hides them). The playlist slides in from the side.
//

import Foundation
import NucleantUI
import NucleantVLC

@View
struct PlayerScreen {
    @State private var player = Player()

    /// Whether the controls show.
    @State private var controlsShown = true
    /// Bumped by every press on the controls: starts the hide countdown
    /// over.
    @State private var lastPress = 0
    @State private var playlistShown = false

    var body: some View {
        ZStack {
            Color.black
            VlcView(remote: player)
            // A press on the video, anywhere the controls aren't.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { setControls(shown: !controlsShown) }
            PlayerControls(
                player: player,
                pressed: { pressed() },
                togglePlaylist: {
                    withAnimation(.easeInOut(duration: 0.25)) { playlistShown.toggle() }
                    pressed()
                }
            )
            .opacity(controlsShown ? 1 : 0)
            .allowsHitTesting(controlsShown)
            if playlistShown {
                HStack(spacing: 0) {
                    Spacer()
                    PlaylistPanel(player: player, close: {
                        withAnimation(.easeInOut(duration: 0.25)) { playlistShown = false }
                        pressed()
                    })
                    .frame(width: 340)
                }
                .transition(.move(edge: .trailing))
            }
        }
        // The countdown: restarted by every press, and when playback starts
        // or stops; the controls stay while paused or the playlist is open.
        .task(id: lastPress) {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, player.isPlaying, !playlistShown else { return }
            setControls(shown: false)
        }
        .onChange(of: player.isPlaying) { pressed() }
        .onAppear {
            if Verifier.scheduleIfRequested(player: player) { return }
            let urls = commandLineURLs()
            if urls.isEmpty {
                player.add(Player.blenderMovies, playing: true)
            } else {
                player.add(urls, playing: true)
            }
        }
    }

    private func pressed() {
        if !controlsShown { setControls(shown: true) }
        lastPress += 1
    }

    private func setControls(shown: Bool) {
        withAnimation(.easeInOut(duration: shown ? 0.15 : 0.4)) { controlsShown = shown }
        if shown { lastPress += 1 }
    }
}

// MARK: - The controls

@View
struct PlayerControls {
    let player: Player
    let pressed: () -> Void
    let togglePlaylist: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                RoundButton(icon: .playlist, iconSize: 16) { togglePlaylist() }
                TitleCapsule(player: player)
                Spacer()
                VolumeCapsule(player: player, pressed: pressed)
            }
            Spacer()
            HStack(spacing: 52) {
                RoundButton(icon: .skipBack, iconSize: 30, diameter: 56) {
                    player.seek(by: .seconds(-10))
                    pressed()
                }
                RoundButton(icon: player.isPlaying ? .pause : .play, iconSize: 30, diameter: 76) {
                    player.playPause()
                    pressed()
                }
                .keyboardShortcut(.space, modifiers: [])
                RoundButton(icon: .skipForward, iconSize: 30, diameter: 56) {
                    player.seek(by: .seconds(10))
                    pressed()
                }
            }
            Spacer()
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    if let error = player.lastError {
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .padding(horizontal: 12, vertical: 7)
                            .background(Capsule().fill(Color(hex: 0xE5484D, opacity: 0.85)))
                    }
                    Spacer()
                    RateMenu(player: player, pressed: pressed)
                    TrackMenu(icon: .audio, tracks: player.audioTracks, selected: player.audioTrack) {
                        player.chooseAudioTrack($0)
                        pressed()
                    }
                    TrackMenu(icon: .subtitles, tracks: player.subtitleTracks, selected: player.subtitleTrack) {
                        player.chooseSubtitleTrack($0)
                        pressed()
                    }
                }
                SeekBar(player: player, pressed: pressed)
            }
        }
        .padding(16)
    }
}

/// What plays, and whether it is still loading.
@View
struct TitleCapsule {
    let player: Player

    var body: some View {
        HStack(spacing: 8) {
            Text(player.current?.title ?? "Nothing playing")
                .font(.system(size: 13))
                .foregroundColor(.white)
                .lineLimit(1)
            if player.state == .opening || player.buffering < 100 {
                Text(player.buffering < 100 ? "\(Int(player.buffering))%" : "Opening…")
                    .font(.system(size: 12))
                    .foregroundColor(Color(white: 1, opacity: 0.6))
            }
        }
        .padding(horizontal: 14, vertical: 9)
        .background(Capsule().fill(glass))
    }
}

/// Mute, and the volume as a bar to drag.
@View
struct VolumeCapsule {
    let player: Player
    let pressed: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            IconView(icon: player.isMuted ? .speakerMuted : .speaker, style: Color.white)
                .frame(width: 16, height: 16)
                .onTapGesture {
                    player.toggleMute()
                    pressed()
                }
            DragBar(fraction: player.isMuted ? 0 : Double(player.volume) / 150) { fraction, _ in
                player.changeVolume(Int((fraction * 150).rounded()))
                pressed()
            }
            .frame(width: 110)
        }
        .padding(horizontal: 14, vertical: 9)
        .background(Capsule().fill(glass))
    }
}

/// Time played, the bar to seek with, time left.
@View
struct SeekBar {
    let player: Player
    let pressed: () -> Void

    /// Where the bar is held while it is dragged; `nil` otherwise.
    @State private var scrubbing: Double?

    var body: some View {
        let shown = scrubbing.map { player.length * $0 } ?? player.time
        HStack(spacing: 12) {
            Text(Self.clock(shown))
                .font(.system(size: 12))
                .foregroundColor(.white)
                .frame(width: 56, alignment: .leading)
            DragBar(fraction: scrubbing ?? player.position, isHeld: scrubbing != nil) { fraction, ended in
                if ended {
                    if player.isSeekable { player.seek(toPosition: fraction) }
                    scrubbing = nil
                } else {
                    scrubbing = fraction
                }
                pressed()
            }
            Text("-" + Self.clock(max(.zero, player.length - shown)))
                .font(.system(size: 12))
                .foregroundColor(.white)
                .frame(width: 60, alignment: .trailing)
        }
        .padding(horizontal: 16, vertical: 10)
        .background(Capsule().fill(glass))
    }

    /// 1:02:03 or 2:03.
    static func clock(_ duration: Duration) -> String {
        let seconds = max(0, Int(duration.components.seconds))
        let h = seconds / 3600, m = seconds / 60 % 60, s = seconds % 60
        let ss = s < 10 ? "0\(s)" : "\(s)"
        if h > 0 {
            return "\(h):\(m < 10 ? "0\(m)" : "\(m)"):\(ss)"
        }
        return "\(m):\(ss)"
    }
}

/// A thin bar filled to `fraction`, taller while held. Pressing or
/// dragging anywhere along it reports the fraction there — `ended` on
/// release.
@View
struct DragBar {
    let fraction: Double
    let isHeld: Bool
    let changed: (Double, Bool) -> Void

    init(fraction: Double, isHeld: Bool = false, _viewID: ViewID = #viewID, changed: @escaping (Double, Bool) -> Void) {
        self.fraction = fraction
        self.isHeld = isHeld
        self.changed = changed
        self._viewID = _viewID
    }

    var body: some View {
        GeometryReader { proxy in
            let height = isHeld ? 8.0 : 4.0
            let filled = proxy.size.width * min(max(fraction, 0), 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(white: 1, opacity: 0.3))
                    .frame(height: height)
                Capsule()
                    .fill(Color.white)
                    .frame(width: max(height, filled), height: height)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .frame(height: 18)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { changed(Self.fraction(of: $0), false) }
                .onEnded { changed(Self.fraction(of: $0), true) }
        )
    }

    private static func fraction(of value: DragGesture.Value) -> Double {
        guard value.bounds.width > 0 else { return 0 }
        return min(max((value.location.x - value.bounds.minX) / value.bounds.width, 0), 1)
    }
}

@View
struct RateMenu {
    let player: Player
    let pressed: () -> Void

    var body: some View {
        Menu {
            ForEach(Player.rates, id: \.self) { rate in
                Button(Self.label(rate) + (rate == player.rate ? "  ✓" : "")) {
                    player.changeRate(rate)
                    pressed()
                }
            }
        } label: {
            Text(Self.label(player.rate))
                .font(.system(size: 12))
        }
        .tint(glass)
    }

    static func label(_ rate: Float) -> String {
        let text = rate == rate.rounded() ? "\(Int(rate))" : "\(rate)"
        return text + "×"
    }
}

@View
struct TrackMenu {
    let icon: PlayerIcon
    let tracks: [VlcTrack]
    let selected: Int32
    let choose: (Int32) -> Void

    var body: some View {
        Menu {
            ForEach(tracks) { track in
                Button(track.name + (track.id == selected ? "  ✓" : "")) { choose(track.id) }
            }
        } label: {
            IconView(icon: icon, style: Color.white)
                .frame(width: 16, height: 16)
        }
        .tint(glass)
        .disabled(tracks.isEmpty)
    }
}

// MARK: - Playlist

@View
struct PlaylistPanel {
    let player: Player
    let close: () -> Void

    /// What is being typed into the open field.
    @State private var location = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text("Playlist")
                    .font(.system(size: 15))
                    .foregroundColor(.white)
                Spacer()
                RoundButton(icon: .previous, iconSize: 12, diameter: 28) { player.previous() }
                RoundButton(icon: .next, iconSize: 12, diameter: 28) { player.next() }
                RoundButton(icon: .close, iconSize: 12, diameter: 28) { close() }
            }
            .padding(horizontal: 14, vertical: 10)

            TextField("Open a file, folder or URL", text: $location)
                .font(.system(size: 13))
                .onSubmit {
                    player.add(typed: location)
                    location = ""
                }
                .padding(horizontal: 12)
                .padding(.bottom, 8)

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(player.items) { item in
                        PlaylistRow(
                            item: item,
                            isCurrent: item.id == player.currentID,
                            play: { player.play(item) },
                            remove: { player.remove(item) }
                        )
                    }
                }
                .padding(6)
            }

            HStack {
                Text(player.items.count == 1 ? "1 item" : "\(player.items.count) items")
                    .font(.system(size: 12))
                    .foregroundColor(Color(white: 1, opacity: 0.6))
                Spacer()
                Toggle("Repeat", isOn: Bindable(player).repeatsAll)
                    .font(.system(size: 12))
            }
            .padding(horizontal: 14, vertical: 8)
        }
        .background(Color(white: 0.08, opacity: 0.88))
    }
}

@View
struct PlaylistRow {
    let item: PlaylistItem
    let isCurrent: Bool
    let play: () -> Void
    let remove: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            IconView(icon: .play, style: Color(hex: 0x4C8DFF))
                .frame(width: 10, height: 10)
                .opacity(isCurrent ? 1 : 0)
            Text(item.title)
                .font(.system(size: 13))
                .foregroundColor(.white)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let duration = item.duration {
                Text(SeekBar.clock(duration))
                    .font(.system(size: 12))
                    .foregroundColor(Color(white: 1, opacity: 0.6))
            }
            IconView(icon: .close, style: Color(white: 1, opacity: 0.7))
                .frame(width: 12, height: 12)
                .opacity(isHovered ? 1 : 0)
                .onTapGesture(perform: remove)
        }
        .padding(horizontal: 8, vertical: 7)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(white: 1, opacity: isCurrent ? 0.14 : 0.07))
                .opacity(isCurrent || isHovered ? 1 : 0)
        )
        .onHover { isHovered = $0 }
        .onTapGesture(count: 2, perform: play)
    }
}
