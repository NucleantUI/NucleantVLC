//
//  PlayerViews.swift
//  NucleantVLCDemo
//
//  The window: the video, its transport bar (seek, play/pause, stop,
//  previous/next, speed, audio and subtitle tracks, volume), and the
//  playlist beside it with a field to open files, folders and addresses.
//

import Foundation
import NucleantUI
import NucleantVLC

@View
struct PlayerScreen {
    @State private var player = Player()

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                VlcView(remote: player)
                NowPlaying(player: player)
                TransportBar(player: player)
            }
            Rectangle()
                .fill(.separator)
                .frame(width: 1)
            PlaylistPanel(player: player)
                .frame(width: 290)
        }
        .background(.background)
        .onAppear {
            if Verifier.scheduleIfRequested(player: player) { return }
            let urls = commandLineURLs()
            if urls.isEmpty {
                player.add(Player.bigBuckBunny, playing: true)
            } else {
                player.add(urls, playing: true)
            }
        }
    }
}

// MARK: - Under the video

@View
struct NowPlaying {
    let player: Player

    var body: some View {
        HStack(spacing: 8) {
            Text(player.current?.title ?? "Nothing playing")
                .font(.system(size: 13))
                .lineLimit(1)
            if player.state == .opening || player.buffering < 100 {
                Text(player.buffering < 100 ? "Buffering \(Int(player.buffering))%" : "Opening…")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let error = player.lastError {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: 0xE5484D))
                    .lineLimit(1)
            }
        }
        .padding(horizontal: 12, vertical: 6)
        .background(.secondaryBackground)
    }
}

@View
struct TransportBar {
    let player: Player

    /// Where the seek slider is while it is dragged; `nil` otherwise.
    @State private var scrubbing: Double?

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 10) {
                Text(Self.clock(scrubbing.map { player.length * $0 } ?? player.time))
                    .font(.system(size: 12))
                    .frame(width: 58, alignment: .trailing)
                Slider(
                    value: Binding(
                        get: { scrubbing ?? player.position },
                        set: { scrubbing = $0 }
                    ),
                    in: 0...1,
                    onEditingChanged: { editing in
                        if !editing, let scrubbing {
                            player.seek(toPosition: scrubbing)
                            self.scrubbing = nil
                        }
                    }
                )
                .disabled(!player.isSeekable)
                Text(Self.clock(player.length))
                    .font(.system(size: 12))
                    .frame(width: 58, alignment: .leading)
            }
            HStack(spacing: 4) {
                IconButton(icon: .previous, isEnabled: !player.items.isEmpty) { player.previous() }
                IconButton(icon: player.isPlaying ? .pause : .play, size: 20, isEnabled: !player.items.isEmpty) {
                    player.playPause()
                }
                .keyboardShortcut(.space, modifiers: [])
                IconButton(icon: .stop, isEnabled: player.state != .stopped && player.state != .nothingSpecial) {
                    player.stop()
                }
                IconButton(icon: .next, isEnabled: !player.items.isEmpty) { player.next() }
                Spacer()
                RateMenu(player: player)
                TrackMenu(title: "Audio", tracks: player.audioTracks, selected: player.audioTrack) {
                    player.chooseAudioTrack($0)
                }
                TrackMenu(title: "Subtitles", tracks: player.subtitleTracks, selected: player.subtitleTrack) {
                    player.chooseSubtitleTrack($0)
                }
                IconButton(icon: player.isMuted ? .speakerMuted : .speaker) { player.toggleMute() }
                Slider(
                    value: Binding(
                        get: { Double(player.volume) },
                        set: { player.changeVolume(Int($0.rounded())) }
                    ),
                    in: 0...150
                )
                .frame(width: 110)
            }
        }
        .padding(horizontal: 12, vertical: 8)
        .background(.tertiaryBackground)
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

@View
struct RateMenu {
    let player: Player

    var body: some View {
        Menu {
            ForEach(Player.rates, id: \.self) { rate in
                Button(Self.label(rate) + (rate == player.rate ? "  ✓" : "")) { player.changeRate(rate) }
            }
        } label: {
            Text(Self.label(player.rate))
                .font(.system(size: 12))
        }
        .frame(width: 64)
    }

    static func label(_ rate: Float) -> String {
        let text = rate == rate.rounded() ? "\(Int(rate))" : "\(rate)"
        return text + "×"
    }
}

@View
struct TrackMenu {
    let title: String
    let tracks: [VlcTrack]
    let selected: Int32
    let choose: (Int32) -> Void

    var body: some View {
        Menu {
            ForEach(tracks) { track in
                Button(track.name + (track.id == selected ? "  ✓" : "")) { choose(track.id) }
            }
        } label: {
            Text(title)
                .font(.system(size: 12))
        }
        .disabled(tracks.isEmpty)
        .frame(width: 118)
    }
}

// MARK: - Playlist

@View
struct PlaylistPanel {
    let player: Player

    /// What is being typed into the open field.
    @State private var location = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                TextField("File, folder or URL", text: $location)
                    .font(.system(size: 13))
                    .onSubmit {
                        player.add(typed: location)
                        location = ""
                    }
            }
            .padding(horizontal: 10, vertical: 8)
            .background(.secondaryBackground)

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
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle("Repeat", isOn: Bindable(player).repeatsAll)
                    .font(.system(size: 12))
            }
            .padding(horizontal: 10, vertical: 6)
            .background(.tertiaryBackground)
        }
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
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let duration = item.duration {
                Text(TransportBar.clock(duration))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            IconView(icon: .close, style: HierarchicalShapeStyle.secondary)
                .frame(width: 12, height: 12)
                .opacity(isHovered ? 1 : 0)
                .onTapGesture(perform: remove)
        }
        .padding(horizontal: 8, vertical: 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(.fill)
                .opacity(isCurrent ? 1 : isHovered ? 0.5 : 0)
        )
        .onHover { isHovered = $0 }
        .onTapGesture(count: 2, perform: play)
    }
}
