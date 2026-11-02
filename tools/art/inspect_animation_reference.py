#!/usr/bin/env python3
"""Read a GLB without importing it or opening a renderer; emit rig/clip evidence."""

import argparse
import collections
import hashlib
import json
from pathlib import Path
import struct


def multiply(a, b):
    return [[sum(a[r][k] * b[k][c] for k in range(4)) for c in range(4)] for r in range(4)]


def transform(node):
    if "matrix" in node:
        return [[node["matrix"][c * 4 + r] for c in range(4)] for r in range(4)]
    x, y, z, w = node.get("rotation", [0, 0, 0, 1])
    rotation = [
        [1 - 2 * (y*y + z*z), 2 * (x*y - z*w), 2 * (x*z + y*w)],
        [2 * (x*y + z*w), 1 - 2 * (x*x + z*z), 2 * (y*z - x*w)],
        [2 * (x*z - y*w), 2 * (y*z + x*w), 1 - 2 * (x*x + y*y)],
    ]
    scale = node.get("scale", [1, 1, 1])
    position = node.get("translation", [0, 0, 0])
    return [[rotation[r][c] * scale[c] for c in range(3)] + [position[r]] for r in range(3)] + [[0, 0, 0, 1]]


def inspect(path):
    data = path.read_bytes()
    magic, version, size = struct.unpack_from("<4sII", data)
    if magic != b"glTF" or version != 2 or size != len(data):
        raise ValueError("Expected an intact glTF 2 GLB")
    chunks = {}
    offset = 12
    while offset < size:
        length, kind = struct.unpack_from("<I4s", data, offset)
        chunks[kind] = data[offset + 8:offset + 8 + length]
        offset += 8 + length
    document = json.loads(chunks[b"JSON"])
    binary = chunks.get(b"BIN\x00", b"")

    def accessor(index):
        spec = document["accessors"][index]
        if "sparse" in spec:
            raise ValueError("Sparse accessors need an explicit inspection adapter")
        view = document["bufferViews"][spec["bufferView"]]
        if view["buffer"] != 0:
            raise ValueError("External GLB buffers are not supported")
        code = {5120: "b", 5121: "B", 5122: "h", 5123: "H", 5125: "I", 5126: "f"}[spec["componentType"]]
        width = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}[spec["type"]]
        layout = struct.Struct("<" + code * width)
        stride = view.get("byteStride", layout.size)
        start = view.get("byteOffset", 0) + spec.get("byteOffset", 0)
        return [layout.unpack_from(binary, start + i * stride) for i in range(spec["count"])]

    nodes = document.get("nodes", [])
    parents = {child: index for index, node in enumerate(nodes) for child in node.get("children", [])}
    global_rest = {}

    def rest(index):
        if index not in global_rest:
            local = transform(nodes[index])
            global_rest[index] = multiply(rest(parents[index]), local) if index in parents else local
        return global_rest[index]

    joints = set(index for skin in document.get("skins", []) for index in skin["joints"])
    bones = []
    for index in sorted(joints):
        node = nodes[index]
        matrix = rest(index)
        bones.append({
            "index": index,
            "name": node.get("name"),
            "parent": nodes[parents[index]].get("name") if index in parents else None,
            "local_translation": node.get("translation", [0, 0, 0]),
            "local_rotation_xyzw": node.get("rotation", [0, 0, 0, 1]),
            "local_scale": node.get("scale", [1, 1, 1]),
            "global_position": [matrix[r][3] for r in range(3)],
            "global_axes": [[matrix[r][c] for r in range(3)] for c in range(3)],
        })

    animations = []
    for animation in document.get("animations", []):
        paths = collections.Counter()
        root_channels = []
        max_time = 0
        for channel in animation["channels"]:
            sampler = animation["samplers"][channel["sampler"]]
            target = channel["target"]
            paths[target["path"]] += 1
            times = accessor(sampler["input"])
            max_time = max(max_time, max(t[0] for t in times))
            if nodes[target["node"]].get("name", "").lower() in {"root", "pelvis", "hips"}:
                values = accessor(sampler["output"])
                root_channels.append({
                    "bone": nodes[target["node"]].get("name"),
                    "path": target["path"],
                    "interpolation": sampler.get("interpolation", "LINEAR"),
                    "samples": len(values),
                    "first": values[0],
                    "last": values[-1],
                    "min": [min(row[c] for row in values) for c in range(len(values[0]))],
                    "max": [max(row[c] for row in values) for c in range(len(values[0]))],
                })
        animations.append({"name": animation.get("name"), "duration": max_time, "track_counts": dict(paths), "root_channels": root_channels})
    return {
        "path": str(path), "sha256": hashlib.sha256(data).hexdigest(),
        "asset": document.get("asset"), "joint_count": len(joints),
        "bones": bones, "animations": animations,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("glb", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    output = json.dumps(inspect(args.glb), indent=2) + "\n"
    if args.output:
        args.output.write_text(output)
    else:
        print(output, end="")


if __name__ == "__main__":
    main()
