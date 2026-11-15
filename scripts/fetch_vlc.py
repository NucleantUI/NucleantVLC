# /// script
# requires-python = ">=3.13"
# ///
"""Fetch libvlc and package it as LibVLC.xcframework.

    uv run scripts/fetch_vlc.py

libvlc for macOS comes with VideoLAN's build of VLC: the release disk image
(pinned, and checked against the SHA-256 VideoLAN publishes) carries libvlc,
libvlccore, every plugin and libvlc's headers inside VLC.app/Contents/MacOS.
Only those are taken — nothing of the app itself — and packaged as
Dependencies/LibVLC.xcframework, the binary target Package.swift links:

    LibVLC.framework/
      Versions/A/LibVLC              libvlc (x86-64 + arm64)
      Versions/A/lib/libvlccore.dylib
      Versions/A/plugins/*.dylib     every module
      Versions/A/share/lua           lua scripts (playlist parsers, …)
      Versions/A/Headers/            libvlc's headers, as <LibVLC/…>
      Versions/A/Modules/module.modulemap
      Versions/A/Resources/Info.plist

libvlc finds its plugins and lua scripts through VLC_PLUGIN_PATH and
VLC_DATA_PATH, which `VlcInstance` points into the framework before it
creates an instance.

Re-running with the framework already in place does nothing; pass --force
to replace it.
"""

import argparse
import hashlib
import shutil
import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path

VLC_VERSION = "3.0.24"
DISK_IMAGE = f"vlc-{VLC_VERSION}-universal.dmg"
SHA256 = "2c8e89f7f42e53c2fb0e87b6dfa39b49f1364b25080aaa2e476ac74c0d7beb3c"
URL = f"https://download.videolan.org/pub/videolan/vlc/{VLC_VERSION}/macosx/{DISK_IMAGE}"

PACKAGE_ROOT = Path(__file__).resolve().parent.parent
DEPENDENCIES = PACKAGE_ROOT / "Dependencies"
DOWNLOADS = DEPENDENCIES / "downloads"
XCFRAMEWORK = DEPENDENCIES / "LibVLC.xcframework"

# How the dylibs in VLC.app name libvlccore: through the app's own rpath.
CORE_NAME = "@rpath/libvlccore.dylib"

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


def download() -> Path:
    image = DOWNLOADS / DISK_IMAGE
    if image.exists() and sha256_of(image) == SHA256:
        print(f"using {image.name} (already downloaded)")
        return image
    print(f"downloading {URL}")
    DOWNLOADS.mkdir(parents=True, exist_ok=True)
    partial = image.with_suffix(image.suffix + ".part")
    with urllib.request.urlopen(URL) as response, partial.open("wb") as out:
        shutil.copyfileobj(response, out)
    actual = sha256_of(partial)
    if actual != SHA256:
        partial.unlink()
        sys.exit(f"checksum mismatch: expected {SHA256}, got {actual}")
    partial.rename(image)
    return image


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


def package(macos: Path) -> None:
    """Build LibVLC.framework from VLC.app/Contents/MacOS, then the
    xcframework around it."""
    print(f"packaging {XCFRAMEWORK.relative_to(PACKAGE_ROOT)}")
    with tempfile.TemporaryDirectory() as stage:
        framework = Path(stage) / "LibVLC.framework"
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

        for header in sorted((macos / "include" / "vlc").glob("*.h")):
            text = header.read_text().replace("<vlc/", "<LibVLC/")
            (version / "Headers" / header.name).write_text(text)
        (version / "Modules" / "module.modulemap").write_text(MODULE_MAP)
        (version / "Resources" / "Info.plist").write_text(FRAMEWORK_PLIST)

        (framework / "Versions" / "Current").symlink_to("A")
        for name in ("LibVLC", "Headers", "Modules", "Resources"):
            (framework / name).symlink_to(f"Versions/Current/{name}")

        # install_name_tool invalidated the signatures, and arm64 code does
        # not load unsigned: the nested dylibs are signed above, the bundle
        # (with its binary) here — ad hoc.
        sign(framework)

        shutil.rmtree(XCFRAMEWORK, ignore_errors=True)
        subprocess.run(
            ["xcodebuild", "-create-xcframework", "-framework", str(framework), "-output", str(XCFRAMEWORK)],
            check=True,
            capture_output=True,
        )
    print(f"{XCFRAMEWORK.relative_to(PACKAGE_ROOT)}: libvlc {VLC_VERSION}, {taken} plugins"
          + (f" (left out: {', '.join(left)})" if left else ""))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--force", action="store_true", help="replace an existing framework")
    args = parser.parse_args()

    if XCFRAMEWORK.exists() and not args.force:
        print(f"{XCFRAMEWORK.relative_to(PACKAGE_ROOT)} already exists (--force to replace)")
        return

    image = download()
    with tempfile.TemporaryDirectory() as mount:
        subprocess.run(
            ["hdiutil", "attach", "-nobrowse", "-readonly", "-mountpoint", mount, str(image)],
            check=True,
            capture_output=True,
        )
        try:
            package(Path(mount) / "VLC.app" / "Contents" / "MacOS")
        finally:
            subprocess.run(["hdiutil", "detach", mount], check=True, capture_output=True)


if __name__ == "__main__":
    main()
