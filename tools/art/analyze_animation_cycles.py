#!/usr/bin/env python3
"""Measure source humanoid foot trajectories with glTF quaternion interpolation and FK."""

import argparse
import hashlib
import json
from pathlib import Path
import struct

import numpy as np

from inspect_animation_reference import transform


def read_glb(path):
    data = path.read_bytes()
    chunks = {}
    offset = 12
    while offset < len(data):
        size, kind = struct.unpack_from("<I4s", data, offset)
        chunks[kind] = data[offset + 8:offset + 8 + size]
        offset += 8 + size
    document = json.loads(chunks[b"JSON"])

    def accessor(index):
        spec = document["accessors"][index]
        view = document["bufferViews"][spec["bufferView"]]
        assert spec["componentType"] == 5126 and "sparse" not in spec
        width = {"SCALAR": 1, "VEC3": 3, "VEC4": 4}[spec["type"]]
        start = view.get("byteOffset", 0) + spec.get("byteOffset", 0)
        stride = view.get("byteStride", 4 * width)
        return np.ndarray((spec["count"], width), dtype="<f4", buffer=chunks[b"BIN\x00"], offset=start, strides=(stride, 4)).copy()

    return document, accessor, hashlib.sha256(data).hexdigest()


def sample_track(times, values, time, rotation, interpolation):
    index = min(max(int(np.searchsorted(times, time, side="right")) - 1, 0), len(times) - 1)
    if index == len(times) - 1 or interpolation == "STEP":
        return values[index]
    assert interpolation == "LINEAR", interpolation
    amount = float((time - times[index]) / (times[index + 1] - times[index]))
    a, b = values[index].astype(float), values[index + 1].astype(float)
    if not rotation:
        return (1 - amount) * a + amount * b
    dot = float(np.dot(a, b))
    if dot < 0:
        b, dot = -b, -dot
    if dot > 0.9995:
        result = (1 - amount) * a + amount * b
    else:
        angle = np.arccos(np.clip(dot, -1, 1))
        result = (np.sin((1 - amount) * angle) * a + np.sin(amount * angle) * b) / np.sin(angle)
    return result / np.linalg.norm(result)


def intervals(mask, phases):
    changes = np.flatnonzero(np.diff(np.r_[False, mask, False]))
    return [[round(float(phases[start]), 4), round(float(phases[min(end, len(phases)-1)]), 4)] for start, end in changes.reshape(-1, 2)]


def analyze(path):
    document, accessor, digest = read_glb(path)
    nodes = document["nodes"]
    parents = {child: parent for parent, node in enumerate(nodes) for child in node.get("children", [])}
    names = {node["name"]: index for index, node in enumerate(nodes)}
    tracked = ["root", "pelvis", "foot_l", "ball_l", "ball_leaf_l", "foot_r", "ball_r", "ball_leaf_r"]
    rest_matrices = {}

    def rest_fk(index):
        if index not in rest_matrices:
            local = np.array(transform(nodes[index]))
            rest_matrices[index] = rest_fk(parents[index]) @ local if index in parents else local
        return rest_matrices[index]

    ground_marker_y = {name: float(rest_fk(names[name])[1, 3]) for name in tracked}
    result = {"source": str(path), "sha256": digest, "samples_per_cycle": 601, "low_support_tolerance_m": .025, "low_support_reference": "rest global marker Y (ball/toe=.0152m), not each clip minimum", "clips": {}}
    for animation in document["animations"]:
        if animation["name"] not in {"Walk_Loop", "Jog_Fwd_Loop", "Sprint_Loop", "Idle_Loop"}:
            continue
        tracks = []
        duration = 0
        for channel in animation["channels"]:
            sampler = animation["samplers"][channel["sampler"]]
            times, values = accessor(sampler["input"])[:, 0], accessor(sampler["output"])
            duration = max(duration, float(times[-1]))
            target = channel["target"]
            tracks.append((target["node"], target["path"], times, values, sampler.get("interpolation", "LINEAR")))
        times = np.linspace(0, duration, 601)
        phases = times / duration
        positions = {name: [] for name in tracked}
        for time in times:
            poses = [dict(node) for node in nodes]
            for index, field, keys, values, interpolation in tracks:
                poses[index][field] = sample_track(keys, values, time, field == "rotation", interpolation)
            global_matrices = {}

            def fk(index):
                if index not in global_matrices:
                    local = np.array(transform(poses[index]))
                    global_matrices[index] = fk(parents[index]) @ local if index in parents else local
                return global_matrices[index]

            for name in tracked:
                positions[name].append(fk(names[name])[:3, 3])
        positions = {name: np.array(values) for name, values in positions.items()}
        clip = {"duration_s": duration, "root_delta": (positions["root"][-1] - positions["root"][0]).tolist(), "bones": {}}
        for name, values in positions.items():
            velocity = np.gradient(values[:, 2], times)
            support_ceiling = ground_marker_y[name] + .025
            contact = (values[:, 1] <= support_ceiling)
            low_backward = contact & (velocity < -.1)
            support_displacements = []
            changes = np.flatnonzero(np.diff(np.r_[False, contact, False]))
            for start, end in changes.reshape(-1, 2):
                last = min(end - 1, len(times) - 1)
                support_displacements.append({"phase_start_end": [float(phases[start]), float(phases[last])], "duration_s": float(times[last] - times[start]), "delta_xz_m": (values[last, [0, 2]] - values[start, [0, 2]]).tolist()})
            clip["bones"][name] = {
                "phase0_xyz": values[0].tolist(), "min_xyz": values.min(axis=0).tolist(), "max_xyz": values.max(axis=0).tolist(),
                "phase_min_y": float(phases[np.argmin(values[:, 1])]),
                "low_intervals_phase": intervals(contact, phases),
                "support_ceiling_y_m": support_ceiling,
                "support_displacements": support_displacements,
                "low_backward_intervals_phase": intervals(low_backward, phases),
                "low_z_velocity_median_mps": float(np.median(velocity[contact])),
                "low_z_velocity_q25_q75_mps": np.quantile(velocity[contact], [.25, .75]).tolist(),
                "backward_low_z_velocity_median_mps": float(np.median(velocity[low_backward])) if np.any(low_backward) else None,
            }
        result["clips"][animation["name"]] = clip
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("glb", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.output.write_text(json.dumps(analyze(args.glb), indent=2) + "\n")
