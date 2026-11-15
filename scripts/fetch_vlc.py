# /// script
# requires-python = ">=3.13"
# ///
"""Fetch libvlc and package it as LibVLC.xcframework.

    uv run scripts/fetch_vlc.py

Neither macOS nor iOS has a libvlc SDK of its own; VideoLAN ships libvlc
inside its own builds, and the pinned releases are checked against the
SHA-256 VideoLAN publishes for them:

* macOS — VLC's release disk image, which carries libvlc, libvlccore, every
  plugin and libvlc's headers inside VLC.app/Contents/MacOS. Only those are
  taken, nothing of the app itself.
* iOS and the iOS Simulator — the MobileVLCKit release archive, whose
  framework is libvlc with its plugins built in (iOS loads no plugins at
  run time). The binary and libvlc's headers are taken, nothing else:
  VLCKit's own Objective-C headers are left out.

They are packaged as Dependencies/LibVLC.xcframework, the binary target
Package.swift links. On macOS:

    LibVLC.framework/
      Versions/A/LibVLC              libvlc (x86-64 + arm64)
      Versions/A/lib/libvlccore.dylib
      Versions/A/plugins/*.dylib     every module
      Versions/A/share/lua           lua scripts (playlist parsers, …)
      Versions/A/Headers/            libvlc's headers, as <LibVLC/…>
      Versions/A/Modules/module.modulemap
      Versions/A/Resources/Info.plist

On iOS (arm64) and the iOS Simulator (arm64 + x86-64), flat, as iOS
frameworks are:

    LibVLC.framework/
      LibVLC                         libvlc, libvlccore and every module
      Headers/                       libvlc's headers, as <LibVLC/…>
      Modules/module.modulemap
      Info.plist

Each platform keeps the headers that came with its binary: MobileVLCKit's
libvlc carries VideoLAN's patches from the libvlc 4 branch (thumbnails,
recording, loudness, async stop), and with them a different
`libvlc_video_set_deinterlace`.

On macOS libvlc finds its plugins and lua scripts through VLC_PLUGIN_PATH
and VLC_DATA_PATH, which `VlcInstance` points into the framework before it
creates an instance.

Re-running with every platform's framework already in place does nothing;
pass --force to replace it.
"""

import argparse
import hashlib
import mmap
import plistlib
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.request
from fnmatch import fnmatch
from pathlib import Path

VLC_VERSION = "3.0.24"
DISK_IMAGE = f"vlc-{VLC_VERSION}-universal.dmg"
SHA256 = "2c8e89f7f42e53c2fb0e87b6dfa39b49f1364b25080aaa2e476ac74c0d7beb3c"
URL = f"https://download.videolan.org/pub/videolan/vlc/{VLC_VERSION}/macosx/{DISK_IMAGE}"

# MobileVLCKit 3.7.5 is libvlc 3.0.24, as its binary says. Its SHA-256 is
# the one VideoLAN's podspec (CocoaPods trunk, MobileVLCKit 3.7.5) gives.
MOBILE_VLCKIT_VERSION = "3.7.5"
MOBILE_ARCHIVE = f"MobileVLCKit-{MOBILE_VLCKIT_VERSION}-a213fd11-6de05adc.tar.xz"
MOBILE_SHA256 = "a76f7a6cfcde4209b56f943e6e18400659d8a7a93ff482f8b1d059468d11e6be"
MOBILE_URL = f"https://download.videolan.org/pub/cocoapods/prod/{MOBILE_ARCHIVE}"

PACKAGE_ROOT = Path(__file__).resolve().parent.parent
DEPENDENCIES = PACKAGE_ROOT / "Dependencies"
DOWNLOADS = DEPENDENCIES / "downloads"
XCFRAMEWORK = DEPENDENCIES / "LibVLC.xcframework"

# The (platform, variant) slices the xcframework holds.
SLICES = {("macos", None), ("ios", None), ("ios", "simulator")}

# How the dylibs in VLC.app name libvlccore: through the app's own rpath.
CORE_NAME = "@rpath/libvlccore.dylib"

# What the iOS frameworks keep of each architecture MobileVLCKit has: no
# 32-bit ARM, which nothing Swift 6 builds for runs on.
IOS_ARCHITECTURES = ("arm64", "x86_64")

# Out of the MobileVLCKit archive: its xcframework's Info.plist, and each
# framework's binary, Info.plist and libvlc headers (Headers/vlc).
MOBILE_MEMBERS = (
    "*/MobileVLCKit.xcframework/Info.plist",
    "*/MobileVLCKit.xcframework/*/MobileVLCKit.framework/MobileVLCKit",
    "*/MobileVLCKit.xcframework/*/MobileVLCKit.framework/Info.plist",
    "*/MobileVLCKit.xcframework/*/MobileVLCKit.framework/Headers/vlc/*.h",
)

FRAMEWORK_PLIST = f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>LibVLC</string>
    <key>CFBundleIdentifier</key>
    <string>org.videolan.LibVLC</string>
    <key>CFBundleName</key>
    <string>LibVLC</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleVersion</key>
    <string>{VLC_VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>{VLC_VERSION}</string>
    <key>MinimumOSVersion</key>
    <string>10.13</string>
</dict>
</plist>
"""

# {platform}: iPhoneOS or iPhoneSimulator; {minimum}: the iOS version
# MobileVLCKit's own framework names.
IOS_FRAMEWORK_PLIST = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>LibVLC</string>
    <key>CFBundleIdentifier</key>
    <string>org.videolan.LibVLC</string>
    <key>CFBundleName</key>
    <string>LibVLC</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleVersion</key>
    <string>{version}</string>
    <key>CFBundleShortVersionString</key>
    <string>{version}</string>
    <key>CFBundleSupportedPlatforms</key>
    <array>
        <string>{platform}</string>
    </array>
    <key>MinimumOSVersion</key>
    <string>{minimum}</string>
</dict>
</plist>
"""

MODULE_MAP = """framework module LibVLC {
    umbrella header "vlc.h"
    export *
}
"""


def sha256_of(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as file:
        for chunk in iter(lambda: file.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def download(name: str, url: str, sha256: str) -> Path:
    file = DOWNLOADS / name
    if file.exists() and sha256_of(file) == sha256:
        print(f"using {file.name} (already downloaded)")
        return file
    print(f"downloading {url}")
    DOWNLOADS.mkdir(parents=True, exist_ok=True)
    partial = file.with_suffix(file.suffix + ".part")
    with urllib.request.urlopen(url) as response, partial.open("wb") as out:
        shutil.copyfileobj(response, out)
    actual = sha256_of(partial)
    if actual != sha256:
        partial.unlink()
        sys.exit(f"{name}: checksum mismatch: expected {sha256}, got {actual}")
    partial.rename(file)
    return file


def run(*args: str) -> str:
    return subprocess.run(args, check=True, capture_output=True, text=True).stdout


def dependencies(dylib: Path) -> list[str]:
    """What `dylib` links, its own install name first."""
    lines = run("otool", "-L", str(dylib)).splitlines()[1:]
    return [line.strip().split(" (")[0] for line in lines]


def relink(dylib: Path, new_id: str | None, core: str) -> None:
    args = ["install_name_tool"]
    if new_id:
        args += ["-id", new_id]
    if CORE_NAME in dependencies(dylib)[1:]:
        args += ["-change", CORE_NAME, core]
    if len(args) > 1:
        subprocess.run([*args, str(dylib)], check=True, capture_output=True)


def links_only_the_system_and_core(dylib: Path) -> bool:
    return all(
        dependency.startswith(("/usr/lib/", "/System/")) or dependency == CORE_NAME
        for dependency in dependencies(dylib)[1:]
    )


def sign(path: Path) -> None:
    subprocess.run(["codesign", "--force", "--sign", "-", str(path)], check=True, capture_output=True)


def copy_headers(source: Path, headers: Path) -> None:
    """libvlc's headers, their includes rewritten as <LibVLC/…>."""
    for header in sorted(source.glob("*.h")):
        text = header.read_text().replace("<vlc/", "<LibVLC/")
        (headers / header.name).write_text(text)


def stage_macos(macos: Path, stage: Path) -> Path:
    """LibVLC.framework for macOS, from VLC.app/Contents/MacOS."""
    framework = stage / "macos" / "LibVLC.framework"
    version = framework / "Versions" / "A"
    for directory in ("Headers", "Modules", "Resources", "lib", "plugins", "share"):
        (version / directory).mkdir(parents=True)

    binary = version / "LibVLC"
    core = version / "lib" / "libvlccore.dylib"
    shutil.copy2((macos / "lib" / "libvlc.dylib").resolve(), binary)
    shutil.copy2((macos / "lib" / "libvlccore.dylib").resolve(), core)
    relink(binary, "@rpath/LibVLC.framework/Versions/A/LibVLC", "@loader_path/lib/libvlccore.dylib")
    relink(core, "@rpath/LibVLC.framework/Versions/A/lib/libvlccore.dylib", "")

    # Every module but the app's own: the macOS interface (and whatever
    # else links the app's Sparkle or Growl) has no place in a library.
    # plugins.dat is left out too — it describes the files as they were.
    taken, left = 0, []
    for plugin in sorted((macos / "plugins").glob("*.dylib")):
        if not links_only_the_system_and_core(plugin):
            left.append(plugin.name)
            continue
        target = version / "plugins" / plugin.name
        shutil.copy2(plugin, target)
        relink(target, None, "@loader_path/../lib/libvlccore.dylib")
        sign(target)
        taken += 1
    sign(core)

    shutil.copytree(macos / "share" / "lua", version / "share" / "lua")

    copy_headers(macos / "include" / "vlc", version / "Headers")
    (version / "Modules" / "module.modulemap").write_text(MODULE_MAP)
    (version / "Resources" / "Info.plist").write_text(FRAMEWORK_PLIST)

    (framework / "Versions" / "Current").symlink_to("A")
    for name in ("LibVLC", "Headers", "Modules", "Resources"):
        (framework / name).symlink_to(f"Versions/Current/{name}")

    # install_name_tool invalidated the signatures, and arm64 code does
    # not load unsigned: the nested dylibs are signed above, the bundle
    # (with its binary) here — ad hoc.
    sign(framework)
    print(f"  macos: libvlc {VLC_VERSION}, {taken} plugins"
          + (f" (left out: {', '.join(left)})" if left else ""))
    return framework


def extract_mobile(archive: Path, into: Path) -> Path:
    """Unpack only MOBILE_MEMBERS of the MobileVLCKit archive; the
    MobileVLCKit.xcframework they are in."""
    print(f"unpacking {archive.name}")
    with tarfile.open(archive, "r|xz") as tar:
        tar.extractall(
            into,
            members=(
                member for member in tar
                if member.isfile() and any(fnmatch(member.name, pattern) for pattern in MOBILE_MEMBERS)
            ),
            filter="data",
        )
    found = list(into.glob("*/MobileVLCKit.xcframework"))
    if len(found) != 1:
        sys.exit(f"{archive.name}: no MobileVLCKit.xcframework in it")
    return found[0]


def stage_ios(mobile: Path, stage: Path) -> list[Path]:
    """LibVLC.framework for iOS and the iOS Simulator, one for each of
    MobileVLCKit's own."""
    frameworks = []
    libraries = plistlib.loads((mobile / "Info.plist").read_bytes())["AvailableLibraries"]
    for library in libraries:
        variant = library.get("SupportedPlatformVariant")
        if (library["SupportedPlatform"], variant) not in SLICES:
            continue
        source = mobile / library["LibraryIdentifier"] / library["LibraryPath"]
        name = "ios-simulator" if variant == "simulator" else "ios"
        framework = stage / name / "LibVLC.framework"
        for directory in ("Headers", "Modules"):
            (framework / directory).mkdir(parents=True)

        # The libvlc this is: libvlc_get_version's string, compiled in.
        # (Its libvlc_version.h says otherwise; that header is stale.)
        with (source / "MobileVLCKit").open("rb") as file, mmap.mmap(file.fileno(), 0, access=mmap.ACCESS_READ) as data:
            if data.find(f"{VLC_VERSION} Vetinari".encode()) < 0:
                sys.exit(f"{MOBILE_ARCHIVE}: {library['LibraryIdentifier']} is not libvlc {VLC_VERSION}")

        binary = framework / "LibVLC"
        architectures = [a for a in IOS_ARCHITECTURES if a in library["SupportedArchitectures"]]
        if set(architectures) == set(library["SupportedArchitectures"]):
            shutil.copy2(source / "MobileVLCKit", binary)
        elif len(architectures) == 1:
            run("lipo", str(source / "MobileVLCKit"), "-thin", architectures[0], "-output", str(binary))
        else:
            extract = [arg for a in architectures for arg in ("-extract", a)]
            run("lipo", str(source / "MobileVLCKit"), *extract, "-output", str(binary))
        subprocess.run(
            ["install_name_tool", "-id", "@rpath/LibVLC.framework/LibVLC", str(binary)],
            check=True,
            capture_output=True,
        )

        copy_headers(source / "Headers" / "vlc", framework / "Headers")
        (framework / "Modules" / "module.modulemap").write_text(MODULE_MAP)
        minimum = plistlib.loads((source / "Info.plist").read_bytes())["MinimumOSVersion"]
        (framework / "Info.plist").write_text(IOS_FRAMEWORK_PLIST.format(
            version=VLC_VERSION,
            platform="iPhoneSimulator" if variant == "simulator" else "iPhoneOS",
            minimum=minimum,
        ))

        # As on macOS: install_name_tool invalidated the signature.
        sign(framework)
        print(f"  {name}: libvlc {VLC_VERSION} ({' + '.join(architectures)}), "
              f"from MobileVLCKit {MOBILE_VLCKIT_VERSION}")
        frameworks.append(framework)
    return frameworks


def slices_in_place() -> bool:
    """Whether the xcframework is there with every platform's slice."""
    plist = XCFRAMEWORK / "Info.plist"
    if not plist.exists():
        return False
    libraries = plistlib.loads(plist.read_bytes())["AvailableLibraries"]
    return SLICES <= {
        (library["SupportedPlatform"], library.get("SupportedPlatformVariant")) for library in libraries
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--force", action="store_true", help="replace an existing framework")
    args = parser.parse_args()

    if slices_in_place() and not args.force:
        print(f"{XCFRAMEWORK.relative_to(PACKAGE_ROOT)} already exists (--force to replace)")
        return

    image = download(DISK_IMAGE, URL, SHA256)
    archive = download(MOBILE_ARCHIVE, MOBILE_URL, MOBILE_SHA256)
    with tempfile.TemporaryDirectory() as stage, tempfile.TemporaryDirectory() as mount:
        stage = Path(stage)
        print(f"packaging {XCFRAMEWORK.relative_to(PACKAGE_ROOT)}")
        subprocess.run(
            ["hdiutil", "attach", "-nobrowse", "-readonly", "-mountpoint", mount, str(image)],
            check=True,
            capture_output=True,
        )
        try:
            frameworks = [stage_macos(Path(mount) / "VLC.app" / "Contents" / "MacOS", stage)]
        finally:
            subprocess.run(["hdiutil", "detach", mount], check=True, capture_output=True)

        frameworks += stage_ios(extract_mobile(archive, stage / "mobile"), stage)

        shutil.rmtree(XCFRAMEWORK, ignore_errors=True)
        subprocess.run(
            ["xcodebuild", "-create-xcframework",
             *[arg for framework in frameworks for arg in ("-framework", str(framework))],
             "-output", str(XCFRAMEWORK)],
            check=True,
            capture_output=True,
        )
    print(f"{XCFRAMEWORK.relative_to(PACKAGE_ROOT)}: libvlc {VLC_VERSION} for "
          + ", ".join(framework.parent.name for framework in frameworks))


if __name__ == "__main__":
    main()
