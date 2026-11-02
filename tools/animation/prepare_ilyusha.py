#!/usr/bin/env python3
"""Prepare CC0 animation-only glTF and the official Godot humanoid BoneMaps.

Run before tools/godot.sh --headless --editor --import. The local downloaded
mannequin is deliberately excluded; only joint transforms and animations remain.
"""
import json
import pathlib
import shutil
import struct

ROOT = pathlib.Path(__file__).resolve().parents[2]
LOCAL = ROOT / "tools/local/references/animation"
OUT = ROOT / "assets/animations/ilyusha"
SOURCE = LOCAL / "quaternius/Universal Animation Library[Standard]/Unreal-Godot/UAL1_Standard.glb"


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    raw = SOURCE.read_bytes()
    json_length = struct.unpack_from("<I", raw, 12)[0]
    doc = json.loads(raw[20:20 + json_length])
    binary = raw[28 + json_length:]
    # Retain skins so the glTF importer recognizes the joint hierarchy, but no
    # mesh, material, texture or foreign character geometry enters the project.
    for node in doc["nodes"]:
        node.pop("mesh", None)
        node.pop("skin", None)
    for field in ("meshes", "materials", "textures", "images", "samplers"):
        doc.pop(field, None)
    # Remove the now-unreferenced vertex/index buffers, not merely their nodes.
    used = {skin["inverseBindMatrices"] for skin in doc["skins"]}
    for animation in doc["animations"]:
        for sampler in animation["samplers"]:
            used.update((sampler["input"], sampler["output"]))
    remap = {old: new for new, old in enumerate(sorted(used))}
    accessors = [doc["accessors"][old] for old in sorted(used)]
    used_views = sorted({a["bufferView"] for a in accessors})
    view_remap = {old: new for new, old in enumerate(used_views)}
    compact = bytearray()
    views = []
    for index in used_views:
        view = doc["bufferViews"][index].copy()
        start = view.get("byteOffset", 0)
        data = binary[start:start + view["byteLength"]]
        compact.extend(b"\0" * (-len(compact) % 4))
        view["byteOffset"] = len(compact)
        compact.extend(data)
        views.append(view)
    compact.extend(b"\0" * (-len(compact) % 4))
    binary = bytes(compact)
    for accessor in accessors:
        accessor["bufferView"] = view_remap[accessor["bufferView"]]
    for skin in doc["skins"]:
        skin["inverseBindMatrices"] = remap[skin["inverseBindMatrices"]]
    for animation in doc["animations"]:
        for sampler in animation["samplers"]:
            sampler["input"] = remap[sampler["input"]]
            sampler["output"] = remap[sampler["output"]]
    doc["accessors"] = accessors
    doc["bufferViews"] = views
    doc["buffers"] = [{"byteLength": len(binary)}]
    encoded = json.dumps(doc, separators=(",", ":")).encode()
    encoded += b" " * (-len(encoded) % 4)
    glb = struct.pack("<4sII", b"glTF", 2, 28 + len(encoded) + len(binary))
    glb += struct.pack("<I4s", len(encoded), b"JSON") + encoded
    glb += struct.pack("<I4s", len(binary), b"BIN\0") + binary
    (OUT / "quaternius_in_place.glb").write_bytes(glb)
    mapping = json.loads((LOCAL / "quaternius-humanoid-map.json").read_text())
    target = json.loads((ROOT / "assets/models/characters/ilyusha/rig_contract.json").read_text())["joints"]
    for name, entries in (("source", mapping), ("target", {k: v for k, v in mapping.items() if v in target})):
        lines = ['[gd_resource type="BoneMap" load_steps=2 format=3]', '', '[sub_resource type="SkeletonProfileHumanoid" id="Humanoid"]', '', '[resource]', 'profile = SubResource("Humanoid")']
        lines += [f'bone_map/{key} = &"{value}"' for key, value in entries.items()]
        (OUT / f"{name}_bone_map.tres").write_text("\n".join(lines) + "\n")
    shutil.copyfile(LOCAL / "quaternius/Universal Animation Library[Standard]/License.txt", OUT / "LICENSE-Quaternius.txt")
    shutil.copyfile(LOCAL / "provenance.json", OUT / "provenance.json")
    print("Prepared animation-only glTF and source/target humanoid maps")


if __name__ == "__main__":
    main()
