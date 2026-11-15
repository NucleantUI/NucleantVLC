# /// script
# requires-python = ">=3.13"
# ///
"""Take a platform's archives from the last release when nothing they are
made from has changed since, instead of making them again.

Each platform's archives are made by its fetch script, which pins the
VideoLAN release it takes libvlc from (and its checksum) and decides how
it is packaged. So the archives only change when that script changes.
Each release records a fingerprint of the scripts per platform in its
`deps.json` asset. The next build of a platform whose fingerprint is
unchanged downloads that release's archives instead, the very same
bytes, so the checksums in Package.swift stay the same too:

    fetch <platform> --output dist
                                the last release's archives for the platform,
                                into dist/, if its fingerprint is unchanged
                                and it has them all; writes reused=true|false
                                to $GITHUB_OUTPUT
    record <platform> --output dist
                                dist/fingerprint-<platform>.txt, uploaded with
                                the archives by the job that made (or
                                reused) them
    collect dist                print deps.json from those files, for the
                                release to publish
    fingerprint <platform>      print the platform's fingerprint

The fingerprints cannot see how build-deps.yml calls the scripts (their
arguments, the runners). After changing that, bump DEPS_REVISION there,
or run with `rebuild`.
"""

import argparse
import hashlib
import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent

# Each platform build-deps.yml makes: the script that makes its archives,
# and the archives (the names release.yml publishes).
PLATFORMS: dict[str, dict] = {
    "apple": {
        "scripts": ["fetch_vlc.py"],
        "archives": ["LibVLC.xcframework.zip"],
    },
    "windows-x86_64": {
        "scripts": ["fetch_vlc_windows.py"],
        "archives": ["LibVLC-windows-x86_64.artifactbundle.zip"],
    },
    "android": {
        "scripts": ["fetch_vlc_android.py"],
        "archives": [f"LibVLC-android-{abi}.artifactbundle.zip" for abi in ("arm64-v8a", "x86_64")],
    },
}


def log(message: str) -> None:
    print(f"[reuse] {message}", file=sys.stderr, flush=True)


def fingerprint(platform: str) -> str:
    digest = hashlib.sha256()
    digest.update(f"revision={os.environ.get('DEPS_REVISION', '')}\n".encode())
    for script in PLATFORMS[platform]["scripts"]:
        # Line endings normalized: a Windows checkout has CRLF, and its
        # fingerprint has to match the one the release recorded elsewhere.
        content = (SCRIPTS / script).read_bytes().replace(b"\r\n", b"\n")
        digest.update(f"{script}\n".encode())
        digest.update(hashlib.sha256(content).hexdigest().encode())
    return digest.hexdigest()


def _request(url: str, accept: str = "application/octet-stream") -> urllib.request.Request:
    request = urllib.request.Request(url, headers={"Accept": accept, "User-Agent": "NucleantVLC-build-deps"})
    token = os.environ.get("GITHUB_TOKEN")
    if token and url.startswith("https://api.github.com/"):
        request.add_header("Authorization", f"Bearer {token}")
    return request


def latest_release(repository: str) -> dict | None:
    url = f"https://api.github.com/repos/{repository}/releases/latest"
    try:
        with urllib.request.urlopen(_request(url, "application/vnd.github+json"), timeout=60) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        if error.code == 404:
            return None
        raise


def download(url: str) -> bytes:
    with urllib.request.urlopen(_request(url), timeout=600) as response:
        return response.read()


def fetch(platform: str, output: Path) -> bool:
    repository = os.environ.get("GITHUB_REPOSITORY")
    if not repository:
        log("GITHUB_REPOSITORY is not set: making them")
        return False
    release = latest_release(repository)
    if release is None:
        log("no release yet: making them")
        return False
    tag = release["tag_name"]
    assets = {asset["name"]: asset["browser_download_url"] for asset in release.get("assets", [])}
    if "deps.json" not in assets:
        log(f"{tag} has no deps.json: making them")
        return False
    recorded = json.loads(download(assets["deps.json"])).get(platform)
    current = fingerprint(platform)
    if recorded != current:
        log(f"{platform} changed since {tag} ({recorded} → {current}): making them")
        return False
    missing = [name for name in PLATFORMS[platform]["archives"] if name not in assets]
    if missing:
        log(f"{tag} lacks {', '.join(missing)}: making them")
        return False

    # All of them or none: a platform half reused would be made over.
    archives = {}
    for name in PLATFORMS[platform]["archives"]:
        archives[name] = download(assets[name])
        log(f"{name} from {tag} ({len(archives[name]) // (1024 * 1024)} MB)")
    output.mkdir(parents=True, exist_ok=True)
    for name, data in archives.items():
        (output / name).write_bytes(data)
    log(f"{platform}: unchanged since {tag}, its archives reused")
    return True


def set_output(name: str, value: str) -> None:
    path = os.environ.get("GITHUB_OUTPUT")
    if path:
        with open(path, "a") as file:
            file.write(f"{name}={value}\n")
    print(f"{name}={value}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    fetch_parser = commands.add_parser("fetch")
    fetch_parser.add_argument("platform", choices=sorted(PLATFORMS))
    fetch_parser.add_argument("--output", type=Path, required=True)
    record_parser = commands.add_parser("record")
    record_parser.add_argument("platform", choices=sorted(PLATFORMS))
    record_parser.add_argument("--output", type=Path, required=True)
    commands.add_parser("collect").add_argument("directory", type=Path)
    commands.add_parser("fingerprint").add_argument("platform", choices=sorted(PLATFORMS))
    args = parser.parse_args()

    if args.command == "fetch":
        try:
            reused = fetch(args.platform, args.output)
        except Exception as error:  # a network hiccup costs a remake, not the job
            log(f"could not check the last release ({error}): making them")
            reused = False
        set_output("reused", "true" if reused else "false")
    elif args.command == "record":
        args.output.mkdir(parents=True, exist_ok=True)
        (args.output / f"fingerprint-{args.platform}.txt").write_text(fingerprint(args.platform) + "\n")
    elif args.command == "collect":
        recorded = {
            path.stem.removeprefix("fingerprint-"): path.read_text().strip()
            for path in sorted(args.directory.glob("fingerprint-*.txt"))
        }
        missing = sorted(set(PLATFORMS) - set(recorded))
        if missing:
            sys.exit(f"error: no fingerprint for {', '.join(missing)}")
        print(json.dumps(recorded, indent=2))
    else:
        print(fingerprint(args.platform))
    return 0


if __name__ == "__main__":
    sys.exit(main())
