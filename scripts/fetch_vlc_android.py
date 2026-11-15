# /// script
# requires-python = ">=3.13"
# ///
"""Fetch libvlc for Android and package it as SwiftPM artifact bundles.

    uv run scripts/fetch_vlc_android.py [--output DIR]

VideoLAN ships libvlc for Android as the libvlc-all AAR on Maven Central.
Each ABI's libvlc.so in it is libvlc and libvlccore with every plugin
built in (Android loads no plugins at run time), and it exports libvlc's
whole C API. The Java bindings' JNI glue is a separate libvlcjni.so,
which is not taken. The pinned AAR is checked against a SHA-256 pinned
here, taken from the file whose SHA-1 matched the one Maven Central
publishes (Maven Central publishes no SHA-256 for it).

The AAR has no headers. Its libvlc is VLC's 3.0.x branch at the commit
VideoLAN's libvlcjni pins (buildsystem/get-vlc.sh), with libvlcjni's
patches applied, and some of the patches change libvlc's API: recording,
a fast-seek argument to set_time and set_position, and libvlc_picture.h.
So the headers are made the same way. VLC's include/vlc at that commit
comes from VideoLAN's GitHub mirror, and the patches from libvlcjni at
its commit are applied with `git apply`, limited to include/vlc. Both are
pinned by commit, and the result is checked against a SHA-256 pinned
here. Every function the headers declare must also be one the library
exports.

One archive per ABI, <output>/LibVLC-android-<abi>.artifactbundle.zip,
as NucleantVulkan packages its Android libraries:

    LibVLC-android-<abi>.artifactbundle/
      info.json
      lib/libvlc.so          a "staticLibrary" SwiftPM links as -lvlc
                             and copies next to the product
      include/vlc/*.h        libvlc's headers, for this libvlc

libvlc.so needs libc++_shared.so. That is the NDK's, which every Swift
Android app ships already, so VideoLAN's copy is left out.

The archives are written with fixed timestamps and in a fixed order, so
the same inputs always give the same bytes and the same checksum.
"""

import argparse
import hashlib
import json
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import urllib.request
import zipfile
from pathlib import Path

LIBVLC_ANDROID_VERSION = "3.7.7"
AAR = f"libvlc-all-{LIBVLC_ANDROID_VERSION}.aar"
AAR_SHA256 = "b48dab96e0e90e34cce3861963500c144a5aadb1b249d501d6a4b104d849e61b"
AAR_URL = f"https://repo1.maven.org/maven2/org/videolan/android/libvlc-all/{LIBVLC_ANDROID_VERSION}/{AAR}"

# The libvlc it is: VLC's 3.0.x branch past 3.0.24, as configure.ac at
# VLC_COMMIT says (AC_INIT(vlc, 3.0.25), VERSION_EXTRA=0), and as the
# binary's libvlc_get_version string says.
VLC_VERSION = "3.0.25"
VERSION_EXTRA = "0"

# vlc-android's libvlc-3.7.7 tag pins libvlcjni (buildsystem/compile.sh,
# LIBVLCJNI_TESTED_HASH), and libvlcjni pins VLC (buildsystem/get-vlc.sh,
# VLC_TESTED_HASH).
LIBVLCJNI_COMMIT = "0b8dc65efb203c86a0476bc337ddd99ecf1c0ef6"
VLC_COMMIT = "84177b2273abc5c4300234e6e18b55a4d2dd5a03"
VLC_RAW = f"https://raw.githubusercontent.com/videolan/vlc/{VLC_COMMIT}"
PATCH_RAW = f"https://code.videolan.org/videolan/libvlcjni/-/raw/{LIBVLCJNI_COMMIT}/libvlc/patches"

# VLC's include/vlc at VLC_COMMIT (libvlc_version.h is made from its .in).
HEADERS = (
    "deprecated.h",
    "libvlc.h",
    "libvlc_dialog.h",
    "libvlc_events.h",
    "libvlc_media.h",
    "libvlc_media_discoverer.h",
    "libvlc_media_library.h",
    "libvlc_media_list.h",
    "libvlc_media_list_player.h",
    "libvlc_media_player.h",
    "libvlc_renderer_discoverer.h",
    "libvlc_version.h.in",
    "libvlc_vlm.h",
    "vlc.h",
)

# libvlcjni's libvlc/patches at LIBVLCJNI_COMMIT, in the order get-vlc.sh
# applies them (all of them; only their include/vlc changes are used).
PATCHES = (
    "0001-compat-Workaround-sendmsg-bug-on-android.patch",
    "0002-libvlc-events-Add-callbacks-for-record.patch",
    "0003-network-tls-Handle-errors-from-older-kernels.patch",
    "0004-access_output-file-Add-error-dialog-for-write-open.patch",
    "0005-libvlc-media_player-Add-record-method.patch",
    "0006-input-es_out-set-video-exclusive.patch",
    "0007-stream_ReadLine-increase-line-length-limit.patch",
    "0008-input-Extract-attachment-also-when-preparsing.patch",
    "0009-input-display-discoverer-preparsers-logs.patch",
    "0010-media_player-backport-fast-seek-argument.patch",
    "0011-audiotrack-rework-DynamicsProcessing-stop.patch",
    "0012-freetype-android-process-formatted-text-nodes.patch",
    "0013-keystore-use-the-system-keystore-from-the-first-try.patch",
    "0014-keystore-return-false-when-interrupted.patch",
    "0015-modules-access-handle-vlc_credential_get-interruptio.patch",
    "0016-access-add-a-cache-helper.patch",
    "0017-dsm-use-the-cache-helper.patch",
    "0018-smb2-use-the-cache-helper.patch",
    "0019-upnp-android-implement-net-intf-priority.patch",
    "0020-upnp-add-and-use-a-callback-listener-interface.patch",
)

# Over the finished headers: each file's name and SHA-256, a line each,
# sorted (headers_digest).
HEADERS_SHA256 = "b9db02b8353fd864fe06e6995c0dd95d64d266b71c36a26989379ec168ba6d95"

# Declared in libvlc_vlm.h but never written: no libvlc 3 exports them,
# on any platform (VLC's lib/libvlc.sym leaves them out).
NEVER_EXPORTED = {
    "libvlc_vlm_get_media_instance_chapter",
    "libvlc_vlm_get_media_instance_seekable",
    "libvlc_vlm_get_media_instance_title",
}

# The ABIs NucleantVulkan builds for Android, with the triple their
# libraries are for.
ABIS = {
    "arm64-v8a": "aarch64-unknown-linux-android28",
    "x86_64": "x86_64-unknown-linux-android28",
}

PACKAGE_ROOT = Path(__file__).resolve().parent.parent
DEPENDENCIES = PACKAGE_ROOT / "Dependencies"
DOWNLOADS = DEPENDENCIES / "downloads"


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


def fetch(url: str) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": "NucleantVLC-fetch"})
    with urllib.request.urlopen(request, timeout=60) as response:
        return response.read()


def touches_headers(patch: bytes) -> bool:
    return re.search(rb"^diff --git a/include/vlc/", patch, re.MULTILINE) is not None


def make_headers(into: Path) -> Path:
    """libvlc's headers as this libvlc was built with them, in
    `into`/include/vlc."""
    print(f"headers: VLC {VLC_COMMIT[:8]} + libvlcjni {LIBVLCJNI_COMMIT[:8]} patches")
    headers = into / "include" / "vlc"
    headers.mkdir(parents=True)
    for name in HEADERS:
        (headers / name).write_bytes(fetch(f"{VLC_RAW}/include/vlc/{name}"))

    patches = into / "patches"
    patches.mkdir()
    applied = []
    for name in PATCHES:
        patch = fetch(f"{PATCH_RAW}/{name}")
        if not touches_headers(patch):
            continue
        (patches / name).write_bytes(patch)
        subprocess.run(
            ["git", "apply", "--include=include/vlc/*", str(patches / name)],
            cwd=into,
            check=True,
        )
        applied.append(name[:4])
    print(f"  applied {', '.join(applied)} (the patches that change include/vlc)")

    template = headers / "libvlc_version.h.in"
    major, minor, revision = VLC_VERSION.split(".")
    text = template.read_text()
    for key, value in {
        "VERSION_MAJOR": major,
        "VERSION_MINOR": minor,
        "VERSION_REVISION": revision,
        "VERSION_EXTRA": VERSION_EXTRA,
    }.items():
        text = text.replace(f"@{key}@", value)
    if re.search(r"@\w+@", text):
        sys.exit("error: libvlc_version.h.in has a placeholder this script does not fill in")
    (headers / "libvlc_version.h").write_text(text)
    template.unlink()
    shutil.rmtree(patches)
    return headers


def headers_digest(headers: Path) -> str:
    lines = "".join(f"{path.name} {sha256_of(path)}\n" for path in sorted(headers.glob("*.h")))
    return hashlib.sha256(lines.encode()).hexdigest()


def declared_functions(headers: Path) -> set[str]:
    """Every function the headers declare (LIBVLC_API … name(…);)."""
    names = set()
    for header in headers.glob("*.h"):
        text = re.sub(r"/\*.*?\*/", "", header.read_text(), flags=re.DOTALL)
        names |= set(re.findall(r"\bLIBVLC_API\b[^;{}()]*?\b(libvlc_\w+)\s*\(", text))
    return names


def exported_functions(library: Path) -> set[str]:
    """The functions an ELF64 little-endian shared library defines in its
    dynamic symbol table."""
    data = library.read_bytes()
    if data[:4] != b"\x7fELF" or data[4] != 2 or data[5] != 1:
        sys.exit(f"error: {library} is not a 64-bit little-endian ELF file")
    section_offset, = struct.unpack_from("<Q", data, 0x28)
    section_size, section_count = struct.unpack_from("<HH", data, 0x3A)
    sections = [struct.unpack_from("<IIQQQQIIQQ", data, section_offset + i * section_size)
                for i in range(section_count)]
    names = set()
    for _, kind, _, _, offset, size, link, _, _, entry_size in sections:
        if kind != 11:  # SHT_DYNSYM
            continue
        strings = sections[link][4]
        for at in range(offset, offset + size, entry_size):
            name, info, _, index = struct.unpack_from("<IBBH", data, at)
            if index != 0 and info & 0xF == 2:  # defined, STT_FUNC
                end = data.index(b"\0", strings + name)
                names.add(data[strings + name:end].decode())
    return names


def is_libvlc(library: Path) -> bool:
    """Whether `library` is libvlc VLC_VERSION: libvlc_get_version's string,
    compiled in."""
    return f"{VLC_VERSION} Vetinari".encode() in library.read_bytes()


def entry(name: str) -> zipfile.ZipInfo:
    info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
    info.compress_type = zipfile.ZIP_DEFLATED
    info.external_attr = 0o644 << 16
    return info


def package(abi: str, library: Path, headers: Path, output: Path) -> Path:
    name = f"LibVLC-android-{abi}"
    bundle = f"{name}.artifactbundle"
    info = {
        "schemaVersion": "1.0",
        "artifacts": {
            "vlc": {
                "type": "staticLibrary",
                "version": VLC_VERSION,
                "variants": [{"path": "lib/libvlc.so", "supportedTriples": [ABIS[abi]]}],
            },
        },
    }
    files = {"lib/libvlc.so": library}
    for header in sorted(headers.glob("*.h")):
        files[f"include/vlc/{header.name}"] = header

    output.mkdir(parents=True, exist_ok=True)
    archive = output / f"{bundle}.zip"
    partial = archive.with_suffix(".zip.part")
    with zipfile.ZipFile(partial, "w") as zip_file:
        zip_file.writestr(entry(f"{bundle}/info.json"), json.dumps(info, indent=2) + "\n")
        for path in sorted(files):
            zip_file.writestr(entry(f"{bundle}/{path}"), files[path].read_bytes())
    partial.replace(archive)
    print(f"  android-{abi}: libvlc {VLC_VERSION}, {archive.stat().st_size // (1024 * 1024)} MB")
    return archive


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--output", type=Path, default=DEPENDENCIES,
                        help="where the artifact bundles go (default: Dependencies/)")
    args = parser.parse_args()

    aar = download(AAR, AAR_URL, AAR_SHA256)
    with tempfile.TemporaryDirectory() as stage:
        stage = Path(stage)
        headers = make_headers(stage / "headers")
        digest = headers_digest(headers)
        if digest != HEADERS_SHA256:
            sys.exit(f"error: the headers are not the pinned ones: expected {HEADERS_SHA256}, got {digest}")
        declared = declared_functions(headers) - NEVER_EXPORTED

        with zipfile.ZipFile(aar) as zip_file:
            for abi in ABIS:
                library = stage / abi / "libvlc.so"
                library.parent.mkdir()
                library.write_bytes(zip_file.read(f"jni/{abi}/libvlc.so"))
                if not is_libvlc(library):
                    sys.exit(f"{AAR}: {abi}'s libvlc.so is not libvlc {VLC_VERSION}")
                missing = sorted(declared - exported_functions(library))
                if missing:
                    sys.exit(f"{AAR}: {abi}'s libvlc.so lacks what the headers declare: {', '.join(missing)}")
                package(abi, library, headers, args.output.resolve())
    print(f"{args.output}: libvlc {VLC_VERSION} for Android {', '.join(ABIS)} "
          f"({len(declared)} functions, all exported)")


if __name__ == "__main__":
    main()
