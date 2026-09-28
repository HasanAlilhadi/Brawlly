#!/usr/bin/env python3
"""Install only the export templates you need for a Godot version instead of the whole ~1.3 GB archive.

Downloads just the needed files out of the official .tpz archive using HTTP range requests.
Resumable: if it stops (network drop, reboot), run it again and it continues where it left off.

Usage: tools/install_export_templates.py [platform ...] [--version 4.7.2]
  platforms: windows, android, ios, macos, linux   (default: windows android ios)
  version:   default = the installed editor's version
"""
import os, re, struct, subprocess, sys, time, urllib.request, zlib

GODOT = "/Users/hasanalilhadi/My Data/Godot/Godot.app/Contents/MacOS/Godot"
COMMON = ["templates/version.txt", "templates/icudt_godot.dat"]
PLATFORMS = {
    "windows": ["templates/windows_debug_x86_64.exe", "templates/windows_release_x86_64.exe"],
    "android": ["templates/android_debug.apk", "templates/android_release.apk", "templates/android_source.zip"],
    "ios": ["templates/ios.zip"],
    "macos": ["templates/macos.zip"],
    "linux": ["templates/linux_debug.x86_64", "templates/linux_release.x86_64"],
}
DEFAULT_PLATFORMS = ["windows", "android", "ios"]
CACHE = os.path.expanduser("~/Library/Caches/godot_template_parts")


def editor_version():
    out = subprocess.run([GODOT, "--version"], capture_output=True, text=True).stdout
    return re.match(r"(\d+\.\d+(?:\.\d+)?)\.stable", out).group(1)


def get_range(url, start, end, out=None):
    """Fetch bytes [start, end] inclusive. With `out`, append to that file, resuming from its size."""
    while True:
        have = os.path.getsize(out) if out and os.path.exists(out) else 0
        if out and start + have > end:
            return
        try:
            req = urllib.request.Request(url, headers={"Range": f"bytes={start + have}-{end}"})
            with urllib.request.urlopen(req, timeout=60) as r:
                if out is None:
                    return r.read()
                with open(out, "ab") as f:
                    while chunk := r.read(65536):
                        f.write(chunk)
        except Exception as e:
            print(f"  network error ({e}), retrying...", flush=True)
            time.sleep(5)


def central_directory(url):
    with urllib.request.urlopen(urllib.request.Request(url, method="HEAD"), timeout=60) as r:
        total = int(r.headers["Content-Length"])
    tail = get_range(url, total - 65536, total - 1)
    i = tail.rfind(b"PK\x05\x06")
    count = struct.unpack("<H", tail[i + 10:i + 12])[0]
    p = struct.unpack("<I", tail[i + 16:i + 20])[0] - (total - len(tail))
    entries = {}
    for _ in range(count):
        method = struct.unpack("<H", tail[p + 10:p + 12])[0]
        csize, usize = struct.unpack("<II", tail[p + 20:p + 28])
        fl, el, cl = struct.unpack("<HHH", tail[p + 28:p + 34])
        off = struct.unpack("<I", tail[p + 42:p + 46])[0]
        entries[tail[p + 46:p + 46 + fl].decode()] = (method, csize, usize, off)
        p += 46 + fl + el + cl
    return entries


def main():
    args = sys.argv[1:]
    version = None
    if "--version" in args:
        i = args.index("--version")
        version = args[i + 1]
        del args[i:i + 2]
    version = version or editor_version()
    platforms = args or DEFAULT_PLATFORMS
    unknown = [p for p in platforms if p not in PLATFORMS]
    if unknown:
        sys.exit(f"Unknown platform(s): {', '.join(unknown)}. Choose from: {', '.join(PLATFORMS)}")
    want = COMMON + [f for p in platforms for f in PLATFORMS[p]]
    url = (f"https://github.com/godotengine/godot/releases/download/{version}-stable/"
           f"Godot_v{version}-stable_export_templates.tpz")
    dest = os.path.expanduser(f"~/Library/Application Support/Godot/export_templates/{version}.stable")
    work = os.path.join(CACHE, version)
    os.makedirs(work, exist_ok=True)
    os.makedirs(dest, exist_ok=True)
    print(f"Godot {version} export templates ({', '.join(platforms)}) -> {dest}", flush=True)

    entries = central_directory(url)
    for name in want:
        if name not in entries:
            print(f"{name}: not in this Godot version's archive, skipped", flush=True)
            continue
        method, csize, usize, off = entries[name]
        final = os.path.join(dest, os.path.basename(name))
        if os.path.exists(final) and os.path.getsize(final) == usize:
            print(f"{name}: already installed", flush=True)
            continue
        fl, el = struct.unpack("<HH", get_range(url, off, off + 29)[26:30])
        data_start = off + 30 + fl + el
        part = os.path.join(work, os.path.basename(name) + ".part")
        print(f"{name}: downloading {csize / 1e6:.1f} MB", flush=True)
        get_range(url, data_start, data_start + csize - 1, out=part)
        tmp = final + ".tmp"
        with open(part, "rb") as src, open(tmp, "wb") as dst:
            d = zlib.decompressobj(-15) if method == 8 else None
            while chunk := src.read(1 << 20):
                dst.write(d.decompress(chunk) if d else chunk)
            if d:
                dst.write(d.flush())
        if os.path.getsize(tmp) != usize:
            os.remove(part)
            sys.exit(f"{name}: corrupt download, run again to re-fetch it")
        os.replace(tmp, final)
        os.remove(part)
        print(f"{name}: installed", flush=True)
    print("ALL TEMPLATES INSTALLED", flush=True)


if __name__ == "__main__":
    main()
