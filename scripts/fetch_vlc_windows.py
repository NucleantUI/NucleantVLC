# /// script
# requires-python = ">=3.13"
# ///
"""Fetch libvlc for Windows and package it as a SwiftPM artifact bundle.

    uv run scripts/fetch_vlc_windows.py [--output DIR]

Windows is the one platform VideoLAN ships a libvlc SDK for. Each
release's 7-Zip archive (not its .zip, which leaves the SDK out) carries
`sdk/` (libvlc's headers and its import library) next to libvlc.dll,
libvlccore.dll and every plugin. The pinned release is checked against
the SHA-256 VideoLAN publishes for it.

It is unpacked with bsdtar (libarchive), because the archive's
executables are BCJ2-filtered, which no Python 7-Zip reader undoes.
bsdtar comes with macOS and with Windows (as tar.exe); on Linux it is in
libarchive-tools.

Packaged as <output>/LibVLC-windows-x86_64.artifactbundle.zip, for a
binary target, the way NucleantVulkan packages its Windows libraries:

    LibVLC-windows-x86_64.artifactbundle/
      info.json
      lib/libvlc.lib                 the import library: a "staticLibrary"
                                     SwiftPM links as -llibvlc
      bin/libvlc.dll                 \\
      bin/libvlccore.dll              | each an "experimentalWindowsDLL",
      bin/plugins/<kind>/*.dll       /  copied next to the product
      include/vlc/*.h                libvlc's headers, as the SDK has them

The plugins are every module but the app's own interfaces (plugins/gui:
Qt and skins). SwiftPM copies each DLL flat into the product's directory.
libvlc then finds the plugins there through VLC_PLUGIN_PATH, and loads
only the `lib*_plugin.dll` files from it. The Lua scripts (playlist
parsers for web sites) are left out, because a binary target has no way
to ship a directory of them.

The archive is written with fixed timestamps and in a fixed order, so
the same inputs always give the same bytes and the same checksum.
"""

import argparse
import hashlib
import json
import mmap
import shutil
import subprocess
import sys
import tempfile
import urllib.request
import zipfile
from pathlib import Path

VLC_VERSION = "3.0.24"
ARCHIVE = f"vlc-{VLC_VERSION}-win64.7z"
# vlc-3.0.24-win64.7z.sha256, next to the archive on VideoLAN's server.
SHA256 = "1ed59c09152e78aff84663fa76efab26057716576db74332858810e5ef54ae1f"
URL = f"https://download.videolan.org/pub/videolan/vlc/{VLC_VERSION}/win64/{ARCHIVE}"

TRIPLE = "x86_64-unknown-windows-msvc"
NAME = "LibVLC-windows-x86_64"

PACKAGE_ROOT = Path(__file__).resolve().parent.parent
DEPENDENCIES = PACKAGE_ROOT / "Dependencies"
DOWNLOADS = DEPENDENCIES / "downloads"

# What is taken out of the archive (its top directory, vlc-<version>/).
ROOT = f"vlc-{VLC_VERSION}"
MEMBERS = (
    f"{ROOT}/libvlc.dll",
    f"{ROOT}/libvlccore.dll",
    f"{ROOT}/plugins",
    f"{ROOT}/sdk/include/vlc",
    f"{ROOT}/sdk/lib/libvlc.lib",
)
# The app's own interfaces.
LEFT_OUT = (f"{ROOT}/plugins/gui",)


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


def bsdtar() -> str:
    """bsdtar: libarchive's tar, by that name or as Windows' own tar.exe."""
    for name in ("bsdtar", "tar"):
        tool = shutil.which(name)
        if tool:
            version = subprocess.run([tool, "--version"], capture_output=True, text=True).stdout
            if "libarchive" in version:
                return tool
    sys.exit("error: no bsdtar (libarchive): on Linux, install libarchive-tools")


def extract(archive: Path, into: Path) -> Path:
    print(f"unpacking {archive.name}")
    excludes = [arg for path in LEFT_OUT for arg in ("--exclude", path)]
    subprocess.run([bsdtar(), "-xf", str(archive), "-C", str(into), *excludes, *MEMBERS], check=True)
    return into / ROOT


def is_libvlc(dll: Path) -> bool:
    """Whether `dll` is libvlc VLC_VERSION: libvlc_get_version's string,
    compiled in."""
    with dll.open("rb") as file, mmap.mmap(file.fileno(), 0, access=mmap.ACCESS_READ) as data:
        return data.find(f"{VLC_VERSION} Vetinari".encode()) >= 0


def entry(name: str) -> zipfile.ZipInfo:
    info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
    info.compress_type = zipfile.ZIP_DEFLATED
    info.external_attr = 0o644 << 16
    return info


def package(vlc: Path, output: Path) -> Path:
    bundle = f"{NAME}.artifactbundle"
    files: dict[str, Path] = {"lib/libvlc.lib": vlc / "sdk" / "lib" / "libvlc.lib"}
    for header in sorted((vlc / "sdk" / "include" / "vlc").glob("*.h")):
        files[f"include/vlc/{header.name}"] = header
    dlls = [vlc / "libvlc.dll", vlc / "libvlccore.dll"]
    plugins = sorted((vlc / "plugins").rglob("*.dll"))
    dlls += plugins

    artifacts: dict[str, dict] = {
        "libvlc": {
            "type": "staticLibrary",
            "version": VLC_VERSION,
            "variants": [{"path": "lib/libvlc.lib", "supportedTriples": [TRIPLE]}],
        },
    }
    for dll in dlls:
        path = f"bin/{dll.relative_to(vlc).as_posix()}"
        if dll.name in artifacts:
            sys.exit(f"error: two DLLs named {dll.name}: SwiftPM copies them to one place")
        artifacts[dll.name] = {
            "type": "experimentalWindowsDLL",
            "version": VLC_VERSION,
            "variants": [{"path": path, "supportedTriples": [TRIPLE]}],
        }
        files[path] = dll
    info = json.dumps({"schemaVersion": "1.0", "artifacts": artifacts}, indent=2) + "\n"

    output.mkdir(parents=True, exist_ok=True)
    archive = output / f"{bundle}.zip"
    partial = archive.with_suffix(".zip.part")
    with zipfile.ZipFile(partial, "w") as zip_file:
        zip_file.writestr(entry(f"{bundle}/info.json"), info)
        for path in sorted(files):
            zip_file.writestr(entry(f"{bundle}/{path}"), files[path].read_bytes())
    partial.replace(archive)
    print(f"  windows-x86_64: libvlc {VLC_VERSION}, {len(plugins)} plugins, "
          f"{archive.stat().st_size // (1024 * 1024)} MB")
    return archive


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--output", type=Path, default=DEPENDENCIES,
                        help="where the artifact bundle goes (default: Dependencies/)")
    args = parser.parse_args()

    archive = download(ARCHIVE, URL, SHA256)
    with tempfile.TemporaryDirectory() as stage:
        vlc = extract(archive, Path(stage))
        if not is_libvlc(vlc / "libvlc.dll"):
            sys.exit(f"{ARCHIVE}: libvlc.dll is not libvlc {VLC_VERSION}")
        written = package(vlc, args.output.resolve())
    print(f"{written}: libvlc {VLC_VERSION} for Windows x86-64")


if __name__ == "__main__":
    main()
