#!/usr/bin/env python3
"""Point GLB models at a shared external texture (e.g. a 3D kit's colormap palette).

Kits like Kenney's ship GLBs that reference `Textures/colormap.png` next to the model. Instead of copying
that texture beside every model, keep one copy (e.g. assets/textures/palettes/dungeon_colormap.png) and
rewrite each GLB's image URI to point at it (relative path, so it works inside Godot).

Usage: tools/glb_set_texture.py <texture.png> <model.glb> [model.glb ...]
"""
import json, os, struct, sys


def set_texture(glb_path, texture_path):
    data = open(glb_path, "rb").read()
    if data[:4] != b"glTF":
        raise ValueError(f"{glb_path} is not a GLB file")
    json_len = struct.unpack("<I", data[12:16])[0]
    doc = json.loads(data[20:20 + json_len])
    rel = os.path.relpath(texture_path, os.path.dirname(os.path.abspath(glb_path)))
    for image in doc.get("images", []):
        if "uri" in image:
            image["uri"] = rel
    chunk = json.dumps(doc, separators=(",", ":")).encode()
    chunk += b" " * (-len(chunk) % 4)
    body = struct.pack("<I4s", len(chunk), b"JSON") + chunk + data[20 + json_len:]
    with open(glb_path, "wb") as f:
        f.write(struct.pack("<4sII", b"glTF", 2, 12 + len(body)) + body)


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    texture = os.path.abspath(sys.argv[1])
    for glb in sys.argv[2:]:
        set_texture(glb, texture)
    print(f"{len(sys.argv) - 2} model(s) now use {os.path.basename(texture)}")
