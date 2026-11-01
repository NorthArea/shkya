"""Software geometry viewer; never opens a display or claims GPU/gameplay acceptance.

Export with ip01_cpu_geometry.gd, then pass its JSON and an output PNG path.
Requires the local Python NumPy and Pillow packages.
"""

import argparse
import json
import math

import numpy as np
from PIL import Image, ImageDraw

WIDTH = 400
HEIGHT = 540
SCALE = 480
BACKGROUND = (197, 201, 204)


def raster_view(triangles, angle):
    cosine, sine = math.cos(angle), math.sin(angle)
    rotation = np.array([[cosine, 0, sine], [0, 1, 0], [-sine, 0, cosine]])
    vertices = triangles[:, :, :3] @ rotation.T
    normals = triangles[:, :, 3:6] @ rotation.T
    colors = triangles[:, :, 6:9]
    pixels = np.zeros((HEIGHT, WIDTH, 3))
    pixels[:] = BACKGROUND
    depth = np.full((HEIGHT, WIDTH), np.inf)
    light = np.array([-0.3, 0.65, -0.7])
    light /= np.linalg.norm(light)
    for points_3d, normal, color in zip(vertices, normals, colors):
        if np.mean(normal[:, 2]) > 0:
            continue
        points = np.stack(
            [WIDTH / 2 - points_3d[:, 0] * SCALE, HEIGHT - 25 - points_3d[:, 1] * SCALE],
            axis=-1,
        )
        x0 = max(0, int(points[:, 0].min()))
        x1 = min(WIDTH - 1, int(points[:, 0].max() + 1))
        y0 = max(0, int(points[:, 1].min()))
        y1 = min(HEIGHT - 1, int(points[:, 1].max() + 1))
        if x1 < x0 or y1 < y0:
            continue
        x, y = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        p, q, r = points
        denominator = (q[1] - r[1]) * (p[0] - r[0]) + (r[0] - q[0]) * (p[1] - r[1])
        if abs(denominator) < 1e-10:
            continue
        u = ((q[1] - r[1]) * (x - r[0]) + (r[0] - q[0]) * (y - r[1])) / denominator
        v = ((r[1] - p[1]) * (x - r[0]) + (p[0] - r[0]) * (y - r[1])) / denominator
        w = 1 - u - v
        z = u * points_3d[0, 2] + v * points_3d[1, 2] + w * points_3d[2, 2]
        current_depth = depth[y0 : y1 + 1, x0 : x1 + 1]
        mask = (u >= 0) & (v >= 0) & (w >= 0) & (z < current_depth)
        if not np.any(mask):
            continue
        interpolated_normal = (
            u[:, :, None] * normal[0]
            + v[:, :, None] * normal[1]
            + w[:, :, None] * normal[2]
        )
        interpolated_normal /= np.maximum(
            1e-6, np.linalg.norm(interpolated_normal, axis=-1)[:, :, None]
        )
        shade = 0.7 + 0.3 * np.maximum(0, interpolated_normal @ light)
        interpolated_color = (
            u[:, :, None] * color[0]
            + v[:, :, None] * color[1]
            + w[:, :, None] * color[2]
        ) * shade[:, :, None]
        pixels[y0 : y1 + 1, x0 : x1 + 1][mask] = (
            np.clip(interpolated_color[mask], 0, 1) * 255
        )
        current_depth[mask] = z[mask]
    return Image.fromarray(pixels.astype(np.uint8))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source")
    parser.add_argument("output")
    parser.add_argument("drawings", nargs="*", default=["ilyusha", "babka", "vendor"])
    parser.add_argument(
        "--pose", choices=["rest", "walk_left", "walk_right", "lada"], default="rest"
    )
    args = parser.parse_args()
    with open(args.source) as source:
        export = json.load(source)
    sheet = Image.new("RGB", (WIDTH * 3, HEIGHT * len(args.drawings)), BACKGROUND)
    for row, name in enumerate(args.drawings):
        triangles = np.array(export["models"][name + "/" + args.pose], dtype=np.float64)
        for column, angle in enumerate([0, math.pi / 3, math.pi]):
            view = raster_view(triangles, angle)
            ImageDraw.Draw(view).text(
                (8, 6), f"{name} / {args.pose} / CPU / {round(math.degrees(angle))}", fill="black"
            )
            sheet.paste(view, (column * WIDTH, row * HEIGHT))
    sheet.save(args.output)
    print(f"CPU geometry preview: {args.output}; GPU/gameplay NOT_RUN")


if __name__ == "__main__":
    main()
