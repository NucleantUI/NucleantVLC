# /// script
# requires-python = ">=3.13"
# ///
"""Package Ubuntu 24.04's libvlc as a SwiftPM artifact bundle for Linux.

    uv run scripts/fetch_vlc_linux.py --output DIR

Runs as root in a throwaway Ubuntu 24.04 container (build-deps.yml's), one
per architecture: it points apt at a fixed date of Ubuntu's archive and
installs packages. It refuses to run anywhere else.

VideoLAN ships no libvlc for Linux that fits. Its snap is amd64 only, and
its Flatpak needs a newer glibc than Ubuntu 24.04. So this takes Ubuntu's
own libvlc, the build every Ubuntu 24.04 machine installs. Ubuntu's packages
are signed, and apt checks them. The archive is Ubuntu's snapshot of it at
SNAPSHOT, so the same packages (with the same dependencies) come every time.
Their versions are checked too.

The bundle holds everything libvlc needs but the machine's own C and C++
runtime (glibc, libstdc++, libgcc_s) and its GPU driver (GL, EGL, GBM,
Vulkan), the same split as NucleantVulkan's Linux bundles:

    LibVLC-linux-<x86_64|aarch64>.artifactbundle/
      info.json
      lib/libvlc.so                  libvlc, with its headers and module map
      lib/libvlccore.so
      lib/lib*_plugin.so             the plugins
      lib/lib*.so                    every library they need
      include/vlc/*.h                libvlc's headers (Ubuntu's libvlc-dev)
      include/module.modulemap       module LibVLC

Every library is an artifact: SwiftPM copies each one next to the product
and links it, and each finds the others there (RUNPATH $ORIGIN). libvlc then
finds the plugins through VLC_PLUGIN_PATH. SwiftPM links a bundle's library
as -l<name> from a file named lib<name>.so, so every library is renamed that
way, with its soname and every reference to it rewritten to match. The plugins
are the ones from vlc-plugin-base and vlc-plugin-video-output, apart from
those that need the GPU driver (OpenGL and Vulkan video outputs and
converters). NucleantVLC draws through its own texture, not through them.

The archive is written with fixed timestamps and in a fixed order, so the
same inputs always give the same bytes and the same checksum.
"""

import argparse
import json
import os
import platform
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

VLC_VERSION = "3.0.20"
UBUNTU_VERSION = "3.0.20-3build6"

# Ubuntu's archive as it was then (snapshot.ubuntu.com serves every
# architecture under ubuntu/).
SNAPSHOT = "20261115T000000Z"
SOURCES = f"""Types: deb
URIs: http://snapshot.ubuntu.com/ubuntu/{SNAPSHOT}
Suites: noble noble-updates noble-security
Components: main universe
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
Check-Valid-Until: no
"""

# libvlc, its core, its plugins and its headers, at UBUNTU_VERSION.
PACKAGES = ("libvlc5", "libvlccore9", "vlc-plugin-base", "vlc-plugin-video-output", "libvlc-dev")

ARCHITECTURES = {
    "x86_64": ("x86_64-linux-gnu", "x86_64-unknown-linux-gnu"),
    "aarch64": ("aarch64-linux-gnu", "aarch64-unknown-linux-gnu"),
}

# What every Linux machine has, and has to be its own: the C and C++ runtime.
RUNTIME = re.compile(
    r"^(ld-linux.*|libc|libm|libdl|libpthread|librt|libresolv|libutil|libanl|libmvec|"
    r"libstdc\+\+|libgcc_s)\.so(\.\d+)*$"
)
# The GPU driver's: a plugin that needs one of these is left out.
GPU_DRIVER = re.compile(r"^lib(GL|GLX|GLdispatch|OpenGL|EGL|GLESv1_CM|GLESv2|gbm|vulkan)\.so(\.\d+)*$")

MODULE_MAP = """module LibVLC {
    umbrella header "vlc/vlc.h"
    export *
}
"""

PACKAGE_ROOT = Path(__file__).resolve().parent.parent
DEPENDENCIES = PACKAGE_ROOT / "Dependencies"


def run(*args: str) -> str:
    return subprocess.run(args, check=True, capture_output=True, text=True).stdout


def in_ubuntu_container() -> bool:
    release = Path("/etc/os-release")
    return (
        sys.platform == "linux"
        and os.geteuid() == 0
        and (Path("/.dockerenv").exists() or Path("/run/.containerenv").exists())
        and release.exists()
        and 'VERSION_ID="24.04"' in release.read_text()
    )


def install() -> None:
    """The pinned packages and patchelf, from Ubuntu's archive at SNAPSHOT."""
    print(f"apt: Ubuntu's archive at {SNAPSHOT}")
    for sources in Path("/etc/apt/sources.list.d").glob("*.sources"):
        sources.unlink()
    Path("/etc/apt/sources.list").write_text("")
    Path("/etc/apt/sources.list.d/snapshot.sources").write_text(SOURCES)
    env = {**os.environ, "DEBIAN_FRONTEND": "noninteractive"}
    subprocess.run(["apt-get", "update", "-q"], check=True, env=env, stdout=subprocess.DEVNULL)
    subprocess.run(
        ["apt-get", "install", "-y", "-q", "--no-install-recommends", "patchelf",
         *(f"{package}={UBUNTU_VERSION}" for package in PACKAGES)],
        check=True, env=env, stdout=subprocess.DEVNULL,
    )


def needed(library: Path) -> list[str]:
    return run("patchelf", "--print-needed", str(library)).split()


def runpath(library: Path) -> list[Path]:
    paths = run("patchelf", "--print-rpath", str(library)).strip()
    return [Path(p.replace("$ORIGIN", str(library.parent))) for p in paths.split(":") if p]


def system_libraries() -> dict[str, Path]:
    """Every library ldconfig knows, by soname."""
    libraries = {}
    for line in run("ldconfig", "-p").splitlines()[1:]:
        name, _, path = line.strip().partition(" => ")
        libraries.setdefault(name.split(" (")[0], Path(path))
    return libraries


def resolve(soname: str, library: Path, system: dict[str, Path]) -> Path | None:
    for directory in runpath(library):
        if (directory / soname).exists():
            return (directory / soname).resolve()
    found = system.get(soname)
    return found.resolve() if found else None


def closure(root: Path, system: dict[str, Path], cache: dict[Path, set[Path] | str]) -> set[Path] | str:
    """`root` and every library it needs (but the runtime), or why it can't
    be bundled: a GPU driver library, or one that isn't there."""
    if root in cache:
        return cache[root]
    cache[root] = {root}  # cycles
    libraries = {root}
    for soname in needed(root):
        if RUNTIME.match(soname):
            continue
        if GPU_DRIVER.match(soname):
            cache[root] = f"needs {soname} (GPU driver)"
            return cache[root]
        path = resolve(soname, root, system)
        if path is None:
            cache[root] = f"needs {soname}, which isn't there"
            return cache[root]
        below = closure(path, system, cache)
        if isinstance(below, str):
            cache[root] = below
            return below
        libraries |= below
    cache[root] = libraries
    return libraries


def link_name(library: Path) -> str:
    """lib<name>.so, the file SwiftPM links as -l<name>."""
    soname = run("patchelf", "--print-soname", str(library)).strip() or library.name
    match = re.match(r"^(lib.+?)\.so(\.\d+)*$", soname)
    if not match:
        sys.exit(f"error: {library}: soname {soname} isn't lib<name>.so")
    return f"{match.group(1)}.so"


def entry(name: str, executable: bool = False) -> zipfile.ZipInfo:
    info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
    info.compress_type = zipfile.ZIP_DEFLATED
    info.external_attr = (0o755 if executable else 0o644) << 16
    return info


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--output", type=Path, default=DEPENDENCIES,
                        help="where the artifact bundle goes (default: Dependencies/)")
    args = parser.parse_args()

    if not in_ubuntu_container():
        sys.exit("error: this installs packages: run it as root in an Ubuntu 24.04 container "
                 "(build-deps.yml does)")
    architecture = platform.machine()
    if architecture not in ARCHITECTURES:
        sys.exit(f"error: no Linux bundle for {architecture}")
    multiarch, triple = ARCHITECTURES[architecture]
    name = f"LibVLC-linux-{architecture}"

    install()
    for package in PACKAGES:
        version = run("dpkg-query", "-W", "-f", "${Version}", package)
        if version != UBUNTU_VERSION:
            sys.exit(f"error: {package} is {version}, not {UBUNTU_VERSION}")

    lib = Path("/usr/lib") / multiarch
    libvlc = (lib / "libvlc.so.5").resolve()
    if f"{VLC_VERSION} Vetinari".encode() not in libvlc.read_bytes():
        sys.exit(f"error: {libvlc} is not libvlc {VLC_VERSION}")

    system = system_libraries()
    cache: dict[Path, set[Path] | str] = {}
    core = closure(libvlc, system, cache)
    if isinstance(core, str):
        sys.exit(f"error: libvlc {core}")

    libraries = set(core)
    plugins, left_out = [], {}
    for plugin in sorted((lib / "vlc" / "plugins").rglob("*_plugin.so")):
        result = closure(plugin.resolve(), system, cache)
        if isinstance(result, str):
            left_out[plugin.name] = result
            continue
        plugins.append(plugin.resolve())
        libraries |= result

    with tempfile.TemporaryDirectory() as stage:
        stage = Path(stage)
        flat = stage / "lib"
        flat.mkdir()
        # Each library under the name SwiftPM links it by.
        names = {library: link_name(library) for library in libraries}
        if len(set(names.values())) != len(names):
            sys.exit("error: two libraries would have the same lib<name>.so")
        renames = {}
        for library, new in names.items():
            soname = run("patchelf", "--print-soname", str(library)).strip()
            if soname and soname != new:
                renames[soname] = new
            shutil.copy2(library, flat / new)
        for library in sorted(flat.iterdir()):
            replaces = [arg for old in needed(library) if old in renames for arg in ("--replace-needed", old, renames[old])]
            subprocess.run(
                ["patchelf", "--set-soname", library.name, "--set-rpath", "$ORIGIN", *replaces, str(library)],
                check=True,
            )

        bundle = f"{name}.artifactbundle"
        artifacts = {}
        for library in sorted(flat.iterdir()):
            artifact = library.name[len("lib"):-len(".so")]
            artifacts[artifact] = {
                "type": "staticLibrary",
                "version": VLC_VERSION,
                "variants": [{"path": f"lib/{library.name}", "supportedTriples": [triple]}],
            }
        artifacts["vlc"]["variants"][0]["staticLibraryMetadata"] = {
            "headerPaths": ["include"],
            "moduleMapPath": "include/module.modulemap",
        }
        info = json.dumps({"schemaVersion": "1.0", "artifacts": artifacts}, indent=2) + "\n"

        files = {f"lib/{library.name}": library for library in flat.iterdir()}
        for header in sorted(Path("/usr/include/vlc").glob("*.h")):
            files[f"include/vlc/{header.name}"] = header

        output = args.output.resolve()
        output.mkdir(parents=True, exist_ok=True)
        archive = output / f"{bundle}.zip"
        partial = archive.with_suffix(".zip.part")
        with zipfile.ZipFile(partial, "w") as zip_file:
            zip_file.writestr(entry(f"{bundle}/info.json"), info)
            zip_file.writestr(entry(f"{bundle}/include/module.modulemap"), MODULE_MAP)
            for path in sorted(files):
                zip_file.writestr(entry(f"{bundle}/{path}", path.startswith("lib/")), files[path].read_bytes())
        partial.replace(archive)

    print(f"  linux-{architecture}: libvlc {VLC_VERSION} (Ubuntu {UBUNTU_VERSION}), {len(plugins)} plugins, "
          f"{len(libraries) - len(plugins)} libraries, {archive.stat().st_size // (1024 * 1024)} MB")
    for plugin, reason in sorted(left_out.items()):
        print(f"    left out {plugin}: {reason}")
    print(f"{archive}: libvlc {VLC_VERSION} for Linux {architecture}")


if __name__ == "__main__":
    main()
