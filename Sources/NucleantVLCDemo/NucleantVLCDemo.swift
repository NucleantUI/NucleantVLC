//
//  NucleantVLCDemo.swift
//  NucleantVLCDemo
//
//  A media player on NucleantUI + libvlc: the video, a transport bar and a
//  playlist. Files, folders and addresses given on the command line are
//  queued and the first one plays; more are opened from the field above the
//  playlist. Double-click a playlist entry to play it; space plays and
//  pauses.
//
//      uv run scripts/fetch_vlc.py      # once: LibVLC.xcframework
//      swift build && .build/debug/NucleantVLCDemo ~/Movies/clip.mkv
//
//  NUCLEANT_VLC_DEMO_VERIFY=<file.ppm> runs the self-check in `Verifier`
//  against a test video it writes, saving the frame it read back to that
//  file, then quits.
//

import Foundation
import NucleantUI

@main
struct NucleantVLCDemo: NucleantApp {
    var body: some Scene {
        WindowGroup("NucleantVLC Player") {
            PlayerScreen()
        }
        .defaultSize(width: 1200, height: 720)
    }
}

/// What the command line asked to play.
func commandLineURLs() -> [URL] {
    CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-") }.map { argument in
        if argument.contains("://"), let url = URL(string: argument) { return url }
        return URL(fileURLWithPath: (argument as NSString).expandingTildeInPath)
    }
}
