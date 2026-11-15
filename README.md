# NucleantVLC

libvlc as a NucleantUI view: a Swift wrapper for libvlc 3 (instance, media, media player, events, every C enum as a Swift enum) and `VlcView`, which shows a player's video. Every decoded frame is fitted to the view's own pixel size and copied GPU to GPU into the view's Vulkan texture.

```swift
import NucleantUI
import NucleantVLC

@MainActor @Observable
final class MyVlcRemote: VlcRemote {
    @ObservationIgnored let player = VlcMediaPlayer()
    private(set) var state = VlcState.nothingSpecial
    private(set) var time = Duration.zero

    func stateDidChange(_ state: VlcState) { self.state = state }
    func timeDidChange(_ time: Duration) { self.time = time }
}

@View
struct Movie {
    @State private var remote = MyVlcRemote()

    var body: some View {
        VlcView(remote: remote)
            .onAppear { try? remote.open(URL(fileURLWithPath: "/Movies/clip.mkv")) }
    }
}
```

**macOS** (x86-64 and arm64) and **iOS** (arm64, and the iOS Simulator on arm64 and x86-64). iOS has the same frame path, decoded into IOSurfaces and copied into the view's texture, and is built from Xcode (below).

## Build and run

```sh
uv run scripts/fetch_vlc.py      # libvlc 3.0.24 → Dependencies/LibVLC.xcframework (pinned + checksummed)
swift build
.build/debug/NucleantVLCDemo     # Blender's open movies, or: NucleantVLCDemo <files, folders, URLs>
```

Add `NUCLEANT_LOCAL_DEV=1` to build against the sibling `../NucleantUI` checkout instead of its GitHub release.

### Xcode: iOS, and macOS as an app

[Xcode/NucleantVLC.xcodeproj](Xcode/NucleantVLC.xcodeproj) has the demo as an app, `NucleantVLCDemoApp`, for iOS (device and simulator) and macOS (a proper `.app`, with `LibVLC.framework` and its plugins embedded). It compiles `Sources/NucleantVLCDemo` unchanged and depends on this package (`path: ..`), so run `fetch_vlc.py` first. Open it, pick the **NucleantVLCDemoApp** scheme and a destination (a simulator, a device or *My Mac*), and run. The first build stops on NucleantUI's macro plugin until you choose *Trust & Enable*.

From the command line, where `-skipMacroValidation` stands in for that prompt:

```sh
cd Xcode
xcodebuild -scheme NucleantVLCDemoApp -destination 'platform=iOS Simulator,name=iPhone 17' -skipMacroValidation build
xcodebuild -scheme NucleantVLCDemoApp -destination 'platform=macOS' -skipMacroValidation build
cd ..
xcodebuild test -scheme NucleantVLC-Package -destination 'platform=iOS Simulator,name=iPhone 17' -skipMacroValidation
```

The last command runs the package's tests in the simulator.

- **Signing.** The simulator and macOS need nothing. A device needs a team: set it under *Signing & Capabilities*, or as `DEVELOPMENT_TEAM` in `project.yml`.
- **Changing the project.** [Xcode/project.yml](Xcode/project.yml) is the source. Regenerate the checked-in project with [xcodegen](https://github.com/yonaskolb/XcodeGen): `cd Xcode && xcodegen`.

**Known problems in the iOS 26 Simulator (2026-11-15).** The app doesn't draw there yet, for two reasons, one after the other:

1. **With the released NucleantVulkan, which ships MoltenVK 1.2.11, it aborts at start.** MoltenVK's `vkCreateInstance` asks the simulator's Metal device for the texture buffer alignment of a pixel format the simulator doesn't have, and the simulator aborts on an assertion (`-[MTLSimDevice minimumTextureBufferAlignmentForPixelFormat:]: MTLPixelFormatInvalid is not supported on this device`). It is a hard assertion, not Metal API or shader validation, so turning those off doesn't help. MoltenVK 1.3.0 leaves those formats out. NucleantVulkan's `scripts/build_vulkan.py` builds 1.3.0 now, but no release ships it yet. To try it first, build MoltenVK with that script, zip `Dependencies/macos/MoltenVK.xcframework` into NucleantVulkan's `Artifacts/` as its release workflow does (with the release's other Apple archives beside it), and build with `NUCLEANT_LOCAL_DEV=1 NUCLEANT_VULKAN_ARTIFACTS=1`.
2. **With MoltenVK 1.3.0 the engine starts, but nothing is drawn.** The simulator's Metal device reports GPU Family Apple 2, and MoltenVK allows draws with a non-zero base vertex or base instance only from Apple 3. Skia's Vulkan backend uses both, so MoltenVK fails its command buffers (`VK_ERROR_FEATURE_NOT_PRESENT`) and the screen stays empty. iPhones and iPads from the A9 on are Apple 3 or newer.

Both happen in NucleantUI's engine, not in NucleantVLC. NucleantUI's own examples hit the first too, and they draw through the same Skia backend. The simulator runs only what doesn't draw:

- libvlc itself, which the package tests cover;
- the frame path up to the IOSurface (`VlcFramePoolTests+iOS`).

On this Intel Mac the player and frame-pool tests pass one at a time. When they all run at once, several time out waiting for frames, because every test decodes on the CPU at the same time. A real device is untested.

### Where libvlc comes from

Neither macOS nor iOS has a separate libvlc SDK. VideoLAN ships libvlc inside its own builds, and only Windows gets an SDK archive of its own. So `fetch_vlc.py` takes two pinned VideoLAN releases and checks each one against the SHA-256 VideoLAN publishes for it.

**macOS.** VideoLAN's signed 3.0.24 disk image. Four things are copied out of `VLC.app/Contents/MacOS`:

- `libvlc`
- `libvlccore`
- the plugins (all but the app's own interface)
- libvlc's headers

Nothing else from the app is kept.

**iOS and the iOS Simulator.** The MobileVLCKit 3.7.5 release archive, the one VideoLAN's CocoaPods podspec points to (the podspec also gives its SHA-256). Its framework is libvlc 3.0.24 with every plugin built in, because iOS loads no plugins at run time. Two things are taken from it:

- **The binary.** Thinned to arm64 for devices and to arm64 and x86-64 for the Simulator (no 32-bit ARM). VLCKit's own Objective-C layer is linked into the same binary and can't be separated, but its headers are left out, so Swift sees only libvlc.
- **libvlc's headers, the ones that came with this binary.** VideoLAN's iOS libvlc carries patches from the libvlc 4 branch (attached thumbnails, recording, loudness, asynchronous stop, text renderer options). One existing function changes with them: `libvlc_video_set_deinterlace` takes an extra `deinterlace` argument. Its `libvlc_version.h` also still says 3.0.17, though the binary is 3.0.24.

Each platform gets its own `LibVLC.framework` inside `LibVLC.xcframework`:

- **Libraries.** On macOS the dylibs are relinked to find each other inside the framework, then re-signed ad hoc. On iOS the one binary is renamed `LibVLC` in a flat framework, as iOS frameworks are, and re-signed ad hoc.
- **Headers.** Rewritten as `<LibVLC/…>`.
- **Module map.** Lets Swift `import LibVLC`.

`Package.swift` takes the xcframework as a binary target, so it links without unsafe flags. At runtime on macOS, `VlcInstance` points `VLC_PLUGIN_PATH` and `VLC_DATA_PATH` into the framework before the first instance starts. iOS needs no such step, because the plugins are in the binary.

## The demo

`NucleantVLCDemo` is a media player. The video fills the window and the controls float over it on glass:

- **Top.** A playlist button, the title (with loading progress), and mute with a volume bar.
- **Middle.** Skip back 10 s, play/pause (also space), skip forward 10 s.
- **Bottom.** Speed, audio track and subtitle menus, then time played, the seek bar and time left.

While a video plays, the controls fade out a few seconds after the last press. A press on the video brings them back, and another hides them. They stay while paused or while the playlist is open.

The playlist slides in from the side:

- A field opens files, folders (their media files) and addresses.
- Previous and next, and double-click an entry to play it.
- Entries show the title and duration read without playing.
- Playlist files open up into the entries they hold.
- Optional repeat.

With nothing on the command line it queues Blender's open movies, streamed over HTTPS from `download.blender.org` as plain files:

- the Big Buck Bunny trailer, in 1080p and 720p;
- Sintel in 1080p, whose ten subtitle tracks fill the subtitle menu.

All are H.264, which VideoToolbox decodes on the GPU.

`NUCLEANT_VLC_DEMO_VERIFY=<file.ppm>` runs a self-check in the real window:

1. It writes a test video with known colors and plays it.
2. It reads the view's texture back and checks that frames keep arriving, in the right colors, the right way up, fitted with black bars.
3. It saves the last frame read to `<file.ppm>` and quits with the result.

## How frames get to the view

libvlc can't render into a Vulkan image. libvlc 3 has two outputs: memory (frames into buffers the app hands it) or a native window. libvlc 4's GPU outputs are OpenGL, GLES2, D3D11, D3D9 and Android windows, with no Vulkan. So the frames come through memory, and from there it is GPU all the way:

1. **Decode.** libvlc's memory output (`libvlc_video_set_callbacks`) decodes, through VideoToolbox where the codec allows, into IOSurface-backed BGRA buffers from a small pool (`VlcFramePool`, one file per platform). The pool is shared between libvlc's video thread and the main thread under one lock, and neither side ever waits for the other: a frame shown before the last one was taken is skipped.
2. **Fit.** libvlc's memory output is opened once, at a fixed size. So on the main thread the newest frame is scaled by VideoToolbox (`VTPixelTransferSession`, letterboxed) to the view texture's `pixelWidth × pixelHeight`. The video's shape is kept and the rest is black. The shape comes from the media's track: the picture's own size and its sample aspect ratio, or `VlcVideoOutput.aspectRatio` when set. Decoders pad their frames (whole codec blocks, aligned rows, so 1080 lines decode as 1088), and libvlc stretches the picture over the padded size. Fitting at the picture's real shape undoes that stretch.
3. **Show.** The fitted buffer's IOSurface is copied into the view's texture with `ViewTexture.write(ioSurface:)`, the `TextureView` / `ExternalTextureNode` path NucleantCEF uses too. Resizing the view refits the frame it already has, so a paused video follows its view too.

## Layout

| File | What |
|---|---|
| `VlcEnums.swift` | libvlc's C enums as Swift enums (raw value = the C constant, named beside it), bit masks as option sets |
| `VlcInstance.swift` (+ `+MacOS`, `+iOS`) | `libvlc_instance_t`: arguments, version, user agent, log handler; where the plugins are |
| `VlcMedia.swift` | `libvlc_media_t`: locations, options, metadata, async parsing, tracks, sub-items, slaves |
| `VlcMediaPlayer.swift` (+ `+MacOS`, `+iOS`) | `libvlc_media_player_t`: transport, time, titles and chapters, tracks, audio, picture adjustments, marquee, logo, snapshots; the platform files hold the calls whose C signature differs (deinterlace) |
| `VlcPlayerEvents.swift` | the player's events as a protocol with no-op defaults, delivered on the main actor in libvlc's order |
| `VlcRemote.swift` | the model protocol: owns a player, hears its events, remote-control commands; the `TextureSource` side of `VlcView` |
| `VlcView.swift` | the view |
| `VlcVideoOutput.swift` (+ `VlcFramePool+MacOS`, `VlcFramePool+iOS`) | frames into the views' textures |
