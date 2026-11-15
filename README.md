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
swift run NucleantVLCDemo        # Blender's open movies, or: NucleantVLCDemo <files, folders, URLs>
```

libvlc comes prebuilt from the release's assets: SwiftPM downloads the archive for the platform it builds for (see [Releases](#releases)).

### Xcode: iOS, and macOS as an app

[Xcode/NucleantVLC.xcodeproj](Xcode/NucleantVLC.xcodeproj) has the demo as an app, `NucleantVLCDemoApp`, for iOS (device and simulator) and macOS (a proper `.app`, with `LibVLC.framework` and its plugins embedded). It compiles `Sources/NucleantVLCDemo` unchanged and depends on this package (`path: ..`). Open it, pick the **NucleantVLCDemoApp** scheme and a destination (a simulator, a device or *My Mac*), and run. The first build stops on NucleantUI's macro plugin until you choose *Trust & Enable*.

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

**Known problems in the iOS 26 Simulator (2026-11-15).** The video plays there, letterboxed as on a device, but none of the controls show:

1. **With MoltenVK 1.2.11 (NucleantVulkan before 0.1.2) it aborted at start.** MoltenVK's `vkCreateInstance` asks the simulator's Metal device for the texture buffer alignment of a pixel format the simulator doesn't have, and the simulator aborts on an assertion (`-[MTLSimDevice minimumTextureBufferAlignmentForPixelFormat:]: MTLPixelFormatInvalid is not supported on this device`). It is a hard assertion, not Metal API or shader validation, so turning those off doesn't help. NucleantVulkan 0.1.2 ships MoltenVK 1.3.0, which leaves those formats out.
2. **With MoltenVK 1.3.0 the engine starts, but what Skia draws doesn't show.** The simulator's Metal device reports GPU Family Apple 2, and MoltenVK allows draws with a non-zero base vertex or base instance only from Apple 3. Skia's Vulkan backend uses both, so MoltenVK fails the command buffers Skia records (`VK_ERROR_FEATURE_NOT_PRESENT`). The video still gets to the window, because its texture isn't drawn through Skia. The controls and their text are, so they stay invisible. iPhones and iPads from the A9 on are Apple 3 or newer.

Both happen in NucleantUI's engine, not in NucleantVLC, and NucleantUI's own examples hit them too. The package tests run in the simulator: libvlc itself, and the frame path up to the IOSurface (`VlcFramePoolTests+iOS`).

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

The package builds for macOS and iOS only so far. The archives for Windows and Android are made and published already, ready for those platforms' files:

**Windows** (`scripts/fetch_vlc_windows.py`). The one platform with a libvlc SDK: the `sdk/` folder in VideoLAN's 3.0.24 7-Zip archive (the `.zip` leaves it out), checked against VideoLAN's SHA-256. It is unpacked with `bsdtar`, because the archive's DLLs are BCJ2-compressed, which no Python 7-Zip reader can undo. The result is `LibVLC-windows-x86_64.artifactbundle.zip`, packaged the way NucleantVulkan packages its Windows libraries:

- `libvlc.lib`, the import library the product links;
- `libvlc.dll`, `libvlccore.dll` and 358 plugins (all but the Qt and skins interfaces), each a DLL SwiftPM copies flat next to the product, where libvlc finds the plugins through `VLC_PLUGIN_PATH`;
- the SDK's headers.

The Lua scripts (playlist parsers for web sites) are left out: a binary target can't ship a folder of them.

**Android** (`scripts/fetch_vlc_android.py`). VideoLAN's `libvlc-all` 3.7.7 AAR from Maven Central. Each ABI's `libvlc.so` is libvlc with every plugin built in, and it exports libvlc's whole C API (the Java bindings' JNI code is a separate library, which is left out). It is libvlc 3.0.25: VLC's 3.0.x branch at the commit VideoLAN's libvlcjni pins, plus libvlcjni's patches. The AAR has no headers, so they are made the same way, from that VLC commit with the patches that change `include/vlc`, and pinned by SHA-256. They differ from macOS's:

- `libvlc_media_player_set_time` and `_set_position` take a `b_fast` argument;
- there are recording and attached-thumbnail APIs (`libvlc_picture.h`).

The script fails unless every function the headers declare is one the library exports. Three VLM functions are the exception: no libvlc 3 build exports them, on any platform. The result is `LibVLC-android-<arm64-v8a|x86_64>.artifactbundle.zip`, the library and its headers. `libvlc.so` needs `libc++_shared.so`, the NDK one every Swift Android app ships already.

**Linux** (`scripts/fetch_vlc_linux.py`). VideoLAN ships no libvlc for Linux that fits: its snap is amd64 only, and its Flatpak needs a newer glibc than Ubuntu 24.04. So this is Ubuntu 24.04's own libvlc 3.0.20, from Ubuntu's archive as it was on a fixed date, for x86-64 and aarch64. `LibVLC-linux-<arch>.artifactbundle.zip` holds libvlc, its plugins and every library they need, except the machine's C/C++ runtime and GPU driver (as NucleantVulkan's Linux bundles), plus the headers and a `LibVLC` module map. Plugins that need the GPU driver (OpenGL and Vulkan video outputs) are left out. Every library is an artifact SwiftPM copies next to the product, found there through `$ORIGIN`, and the plugins through `VLC_PLUGIN_PATH`.

### Releases

[.github/workflows/release.yml](.github/workflows/release.yml) (run by hand on `main`, with the version) works like NucleantVulkan's:

1. [build-deps.yml](.github/workflows/build-deps.yml) makes every platform's archives and checks them. On macOS the package builds and its tests run against the zipped xcframework. On Windows a C program ([scripts/libvlc_smoke.c](scripts/libvlc_smoke.c)) plays a file through the bundle, laid out as SwiftPM lays out a product. For Android the same program is compiled and linked for each ABI.
2. The release commit writes each archive's URL and checksum into `Package.swift` (`releasedVLC`), tags it, publishes the release with the archives, and pushes the commit to `main`.
3. A new package that depends on the release by its version builds and runs on macOS.

Each release also publishes `deps.json`, a fingerprint per platform of the fetch script that made its archives. The next release takes a platform's archives straight from the last release when its script is unchanged ([scripts/reuse_release_libraries.py](scripts/reuse_release_libraries.py)). They are the same bytes, so their checksums don't change either. Pass `rebuild` to make them all again. The Windows and Android scripts also write their archives with fixed timestamps and in a fixed order, so making them again gives the same bytes.

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
