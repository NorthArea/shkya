#!/usr/bin/env python3
"""Паспорта объёмных персонажей CHAR3D-01 (вариант A): формы и цвета берутся из tools/generate_characters.py.

Запуск: uv run --no-project python -I tools/character_passports.py
Пишет assets/art/characters/passports.json — его читает game/characters/character_body3d.gd.

Метод: голова и тело — «лофт» по двум силуэтам рисунка: ширина каждого среза — по фронтальному SVG, глубина —
по боковому (те же кривые, что рисует генератор, сэмплированные по Безье). Поэтому спереди и сбоку объём
повторяет силуэт спрайта, а рост совпадает с рисунком. Руки, ноги, обувь, воротники и предметы — капсулы,
эллипсоиды и скруглённые коробки по габаритам тех же форм. Лицо — деколь: вырезки фронтального, бокового и
заднего SVG (прямоугольники в единицах холста 400×600, как PORTRAIT_REGION в game/ui/dialog_panel.gd).

Оси объёма (метры, узел облика): X — правая рука персонажа (на фронтальном рисунке — слева от зрителя),
Y — вверх от подошв (y холста 590), Z — назад (персонаж смотрит в −Z, как CharacterSprite). Только stdlib.
"""

from __future__ import annotations

import importlib.util
import json
import math
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "art" / "characters" / "passports.json"
FEET_Y = 590.0
AXIS = 200.0
SIDE_AXIS = 200.0
RINGS = 28

_spec = importlib.util.spec_from_file_location("generate_characters", ROOT / "tools" / "generate_characters.py")
G = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(G)


# ------------------------------------------------------------------ геометрия путей SVG

_TOKEN = re.compile(r"[MLCQZmlcqzAaHhVvSsTt]|-?\d*\.?\d+(?:e-?\d+)?")


def sample_d(d: str, steps: int = 12) -> list[tuple[float, float]]:
    """Точки контура пути (абсолютные M/L/C/Q/Z — так пишет генератор): кривые сэмплируются по Безье."""
    tokens = _TOKEN.findall(d)
    pts: list[tuple[float, float]] = []
    i, cmd = 0, ""
    cur = (0.0, 0.0)

    def num() -> float:
        nonlocal i
        v = float(tokens[i])
        i += 1
        return v

    while i < len(tokens):
        if tokens[i].isalpha():
            cmd = tokens[i]
            i += 1
            if cmd in "Zz":
                continue
        if cmd not in "MLCQ":
            raise ValueError(f"команда пути {cmd!r} не поддержана: {d[:60]}")
        if cmd == "M" or cmd == "L":
            cur = (num(), num())
            pts.append(cur)
        elif cmd == "C":
            c1, c2, p = (num(), num()), (num(), num()), (num(), num())
            for s in range(1, steps + 1):
                t = s / steps
                a, b, c, e = (1 - t) ** 3, 3 * (1 - t) ** 2 * t, 3 * (1 - t) * t * t, t ** 3
                pts.append((a * cur[0] + b * c1[0] + c * c2[0] + e * p[0], a * cur[1] + b * c1[1] + c * c2[1] + e * p[1]))
            cur = p
        elif cmd == "Q":
            c1, p = (num(), num()), (num(), num())
            for s in range(1, steps + 1):
                t = s / steps
                a, b, c = (1 - t) ** 2, 2 * (1 - t) * t, t * t
                pts.append((a * cur[0] + b * c1[0] + c * p[0], a * cur[1] + b * c1[1] + c * p[1]))
            cur = p
    return pts


def ellipse_pts(cx: float, cy: float, rx: float, ry: float, n: int = 24) -> list[tuple[float, float]]:
    return [(cx + rx * math.cos(2 * math.pi * k / n), cy + ry * math.sin(2 * math.pi * k / n)) for k in range(n)]


def find_d(svg_text: str, prefix: str) -> str:
    """Путь рисунка по началу атрибута d (формы, объявленные внутри функций генератора)."""
    m = re.search(r'd="(' + re.escape(prefix) + r'[^"]*)"', svg_text)
    if not m:
        raise KeyError(f"нет пути {prefix!r}")
    return m.group(1)


def grid(k: float, dy: float = 580.0):
    """Сетка кропа e03 (P_GRID, O_GRID): translate(200,590) scale(k) translate(-200,-dy)."""
    return lambda p: (200 + k * (p[0] - 200), 590 + k * (p[1] - dy))


def tf(polys: list[list[tuple[float, float]]], f) -> list[list[tuple[float, float]]]:
    return [[f(p) for p in poly] for poly in polys]


def extent(polys: list[list[tuple[float, float]]], y: float) -> tuple[float, float] | None:
    xs: list[float] = []
    for poly in polys:
        n = len(poly)
        for j in range(n):
            (x0, y0), (x1, y1) = poly[j], poly[(j + 1) % n]
            if y0 == y1:
                continue
            if (y0 - y) * (y1 - y) <= 0:
                xs.append(x0 + (x1 - x0) * (y - y0) / (y1 - y0))
    return (min(xs), max(xs)) if xs else None


def bbox(polys: list[list[tuple[float, float]]]) -> tuple[float, float, float, float]:
    xs = [p[0] for poly in polys for p in poly]
    ys = [p[1] for poly in polys for p in poly]
    return min(xs), min(ys), max(xs), max(ys)


# ------------------------------------------------------------------ перевод холста в метры

class Frame:
    def __init__(self, height_m: float) -> None:
        self.k = height_m / 600.0

    def X(self, x_front: float) -> float:   # фронтальный рисунок: слева от зрителя — +X (правая рука персонажа)
        return round((AXIS - x_front) * self.k, 4)

    def Y(self, y: float) -> float:
        return round((FEET_Y - y) * self.k, 4)

    def Z(self, x_side: float) -> float:    # боковой рисунок смотрит вправо: правее — вперёд, то есть −Z
        return round(-(x_side - SIDE_AXIS) * self.k, 4)

    def L(self, units: float) -> float:
        return round(units * self.k, 4)

    def P(self, x_front: float, y: float, x_side: float = SIDE_AXIS) -> list[float]:
        return [self.X(x_front), self.Y(y), self.Z(x_side)]

    def loft(self, front: list, side: list | None, depth_ratio: float = 0.8, n: int = RINGS,
             y_range: tuple[float, float] | None = None) -> list[list[float]]:
        """Срезы [y, xc, rx, zc, rz] (м) по фронтальному и боковому силуэтам, сверху вниз."""
        x0, top, x1, bottom = bbox(front)
        if y_range:
            top, bottom = max(top, y_range[0]), min(bottom, y_range[1])
        raw = []
        for s in range(n):
            y = top + 0.3 + (bottom - top - 0.6) * s / (n - 1)
            fe = extent(front, y)
            if not fe:
                continue
            se = extent(side, y) if side else None
            raw.append((y, fe, se))
        ratios = [(se[1] - se[0]) / max(1e-3, fe[1] - fe[0]) for _, fe, se in raw if se]
        ratio = sorted(ratios)[len(ratios) // 2] if ratios else depth_ratio
        centers = [(se[0] + se[1]) / 2 for _, _, se in raw if se]
        zc_default = sum(centers) / len(centers) if centers else SIDE_AXIS
        rings = []
        for y, fe, se in raw:
            rx = (fe[1] - fe[0]) / 2
            if se:
                zc, rz = (se[0] + se[1]) / 2, (se[1] - se[0]) / 2
            else:
                zc, rz = zc_default, rx * ratio
            rings.append([self.Y(y), self.X((fe[0] + fe[1]) / 2), self.L(rx), self.Z(zc), self.L(rz)])
        return rings


def rect(polys, margin: float = 4.0) -> list[float]:
    x0, y0, x1, y1 = bbox(polys)
    return [round(x0 - margin, 1), round(y0 - margin, 1), round(x1 - x0 + 2 * margin, 1), round(y1 - y0 + 2 * margin, 1)]


def shape_name(front: list, kind: str) -> str:
    """Форма по фронтальному силуэту: голова — шар/яйцо/груша, тело — капсула/бочка/колокол."""
    x0, top, x1, bottom = bbox(front)
    h = bottom - top

    def w(t: float) -> float:
        e = extent(front, top + h * t)
        return (e[1] - e[0]) if e else 0.0

    if kind == "head":
        upper, lower = w(0.3), w(0.72)
        r = lower / max(1e-3, upper)
        return "груша" if r > 1.12 else ("яйцо" if r > 1.03 else "шар")
    shoulders, middle, hips = w(0.12), w(0.5), w(0.88)
    if hips > shoulders * 1.2 and hips >= middle * 0.98:
        return "колокол"
    if middle > max(shoulders, hips) * 1.04:
        return "бочка"
    return "капсула"


def widths(front: list, f: Frame) -> dict:
    x0, top, x1, bottom = bbox(front)
    h = bottom - top

    def w(t: float) -> float:
        e = extent(front, top + h * t)
        return f.L(e[1] - e[0]) if e else 0.0

    return {"shoulders_m": w(0.12), "middle_m": w(0.5), "hips_m": w(0.88), "height_m": f.L(h)}


def part(name: str, kind: str, group: str, color: str, **kw) -> dict:
    d = {"name": name, "kind": kind, "group": group, "color": color}
    d.update(kw)
    return d


def capsule_len(a: list[float], b: list[float]) -> float:
    return round(math.dist(a, b), 4)


# ------------------------------------------------------------------ персонажи

def ilyusha() -> dict:
    h = 2.0
    f = Frame(h)
    side_svg = G.ilyusha("side", -1)
    head_f = [sample_d(G.HEAD_FRONT)]
    head_s = [sample_d(find_d(side_svg, "M140,108 C160,82"))]
    tuft_svg = G.Svg()
    G.tuft(tuft_svg, 200, 44)
    tuft_f = [sample_d(re.search(r'd="([^"]*)"', tuft_svg.parts[0]).group(1))]
    body_f = [sample_d("M95,300 C68,332 72,420 102,442 L298,442 C328,420 332,332 305,300 C270,282 130,282 95,300 Z")]
    body_s = [sample_d(find_d(side_svg, "M126,292 C88,306"))]
    nose_s = sample_d(find_d(side_svg, "M264,200 C292,194"))
    sleeve = [sample_d("M112,304 C78,306 56,342 58,402 C60,424 88,430 96,414 C100,376 106,342 118,318 Z")]
    head_z = (bbox(head_s)[0] + bbox(head_s)[2]) / 2
    head_front_z = bbox(head_s)[2]   # лоб и лицо в профиль
    parts = [
        part("head", "loft", "body", G.SKIN, rings=f.loft(head_f, head_s), power=2.0, decal="head"),
        part("tuft", "loft", "body", G.TUFT, rings=f.loft(tuft_f, None, 0.7), power=2.0),
        # Нос-хобот (V02 0:09, 0:25): из лица вперёд, кончик загнут вверх — как в профиль генератора.
        part("nose", "capsule", "body", G.SKIN, a=f.P(198, 206, head_front_z - 14), b=f.P(194, 200, 318), r=f.L(13)),
        part("nose_tip", "capsule", "body", G.SKIN, a=f.P(194, 200, 318), b=f.P(190, 160, 338), r=f.L(12)),
        # Стёжка куртки (две дуги jacket_front на y 344/392 с провисом 8) и молния спереди (x 200, 300…440).
        part("jacket", "loft", "body", G.JACKET, rings=f.loft(body_f, body_s), power=2.2,
             lines={"y": [f.Y(344), f.Y(392)], "sag": f.L(8), "half": f.L(116), "seam": [0.0, f.Y(300), f.Y(440)],
                    "width": f.L(3.2)}),
        part("collar", "scallops", "body", G.FUR, center=f.P(200, 274, 205), rx=f.L(90), rz=f.L(68), r=f.L(17), n=14),
        part("hips", "ellipsoid", "body", G.PANTS, center=f.P(200, 450, 205), radii=[f.L(86), f.L(18), f.L(48)]),
    ]
    sx0, sy0, sx1, sy1 = bbox(sleeve)
    pivots = {}
    for side, xs in (("r", 1), ("l", -1)):
        sh = (200 - (200 - 104) * xs, 314)
        wr = (200 - (200 - 78) * xs, 410)
        group = "arm_" + side
        pivots[group] = f.P(sh[0], sh[1], 200)
        parts.append(part("sleeve_" + side, "capsule", group, G.JACKET, a=f.P(sh[0], sh[1], 200),
                          b=f.P(wr[0], wr[1], 200), r=f.L(25)))
        parts.append(part("hand_" + side, "ellipsoid", group, G.SKIN, center=f.P(200 - (200 - 74) * xs, 432, 196),
                          radii=[f.L(20), f.L(22), f.L(20)]))
    for side, xc in (("r", 152), ("l", 248)):
        group = "leg_" + side
        pivots[group] = f.P(xc, 444, 205)
        parts.append(part("leg_" + side, "capsule", group, G.PANTS, a=f.P(xc, 452, 205), b=f.P(xc, 540, 205), r=f.L(42)))
        parts.append(part("boot_" + side, "ellipsoid", group, G.BOOT, center=f.P(xc, 570, 226),
                          radii=[f.L(46), f.L(20), f.L(60)]))
    hx0, hy0, hx1, hy1 = bbox(head_f)
    return {
        "height_m": h, "tone": 0.72, "tint": [1.0, 1.0, 1.0],
        "walk": {"leg_swing_deg": 30.0, "arm_swing_deg": 26.0, "stride_m": 0.62, "bob_m": 0.025},
        # С деколи стёрт нарисованный хохолок (его заменяет объёмный) и кончик хобота в профиль (объёмный нос);
        # на фасе хобот остаётся рисунком: его загиб заходит на правый глаз, вырезать прямоугольником нельзя.
        "decals": {"head": {"front": rect(head_f), "back": rect(head_f), "side": rect(head_s),
                            "fallback": G.SKIN, "top": G.SKIN, "texture": "ilyusha",
                            "erase": {"front": [[138, 38, 124, 82]], "back": [[138, 38, 124, 82]],
                                      "side": [[258, 136, 30, 68], [134, 38, 124, 84]]}}},
        "pivots": pivots, "parts": parts,
        "summary": {
            "figure_height_m": f.L(FEET_Y - bbox(tuft_f)[1]),
            "head": {"width_m": f.L(hx1 - hx0), "height_m": f.L(hy1 - hy0),
                     "depth_m": f.L(bbox(head_s)[2] - bbox(head_s)[0]), "shape": shape_name(head_f, "head"),
                     "nose": "хобот вперёд и вверх, %.2f м" % f.L(max(p[0] for p in nose_s) - head_front_z)},
            "body": dict(widths(body_f, f), depth_m=f.L(bbox(body_s)[2] - bbox(body_s)[0]),
                         shape=shape_name(body_f, "body")),
            "arms": {"length_m": f.L(math.dist((104, 314), (74, 432))), "thickness_m": f.L(50)},
            "legs": {"length_m": f.L(556 - 436), "thickness_m": f.L(84)},
            "shoes": {"length_m": f.L(120), "width_m": f.L(92), "height_m": f.L(40)},
            "colors": {"skin": G.SKIN, "jacket": G.JACKET, "pants": G.PANTS, "boots": G.BOOT, "tuft": G.TUFT,
                       "collar": G.FUR},
            "details": [{"type": "меховой воротник", "color": G.FUR, "size_m": f.L(184)},
                        {"type": "хохолок", "color": G.TUFT, "size_m": f.L(bbox(tuft_f)[2] - bbox(tuft_f)[0])},
                        {"type": "нос-хобот", "color": G.SKIN, "size_m": f.L(88)}],
        },
    }


def babka() -> dict:
    h = 2.17
    f = Frame(h)
    side_svg = G.babka("side")
    head_f = [sample_d(G.FACE_PEAR), sample_d(G.CAP_FRONT)]
    head_s = [sample_d(find_d(side_svg, "M142,110 L262,112")), sample_d(find_d(side_svg, "M264,114 C258,94"))]
    body_f = [sample_d(G.BARREL)]
    body_s = [sample_d(find_d(side_svg, "M150,245 C120,252"))]
    parts = [
        part("head", "loft", "body", G.B_SKIN, rings=f.loft(head_f, head_s), power=2.0, decal="head"),
        # Тело-бочонок с руками в массе (ART-01): деколь фронта/спины/бока — кисти, пуговицы, мягкие пятна.
        part("dress", "loft", "body", G.B_DRESS, rings=f.loft(body_f, body_s), power=2.0, decal="body"),
        part("jabot", "scallops", "body", G.LACE, center=f.P(200, 236, 212), rx=f.L(80), rz=f.L(70), r=f.L(13), n=16),
    ]
    pivots = {}
    for side, xc in (("r", 165), ("l", 235)):
        group = "leg_" + side
        pivots[group] = f.P(xc, 540, 214)
        parts.append(part("stocking_" + side, "capsule", group, G.B_STOCK, a=f.P(xc, 540, 214), b=f.P(xc, 572, 214),
                          r=f.L(15)))
        parts.append(part("boot_" + side, "ellipsoid", group, G.B_BOOT, center=f.P(xc, 580, 230),
                          radii=[f.L(21), f.L(12), f.L(34)]))
    hx0, hy0, hx1, hy1 = bbox(head_f)
    return {
        "height_m": h, "tone": 0.72, "tint": [1.06, 1.02, 0.88],
        "walk": {"leg_swing_deg": 18.0, "arm_swing_deg": 0.0, "stride_m": 0.35, "bob_m": 0.015},
        "decals": {"head": {"front": rect(head_f), "back": rect(head_f), "side": rect(head_s), "fallback": G.B_SKIN,
                            "top": G.B_HAT, "texture": "babka"},
                   "body": {"front": rect(body_f, 2), "back": rect(body_f, 2), "side": rect(body_s, 2),
                            "fallback": G.B_DRESS, "texture": "babka"}},
        "pivots": pivots, "parts": parts,
        "summary": {
            "figure_height_m": f.L(FEET_Y - hy0),
            "head": {"width_m": f.L(hx1 - hx0), "height_m": f.L(hy1 - hy0),
                     "depth_m": f.L(bbox(head_s)[2] - bbox(head_s)[0]), "shape": shape_name([head_f[0]], "head"),
                     "face_h_to_w": round((bbox([head_f[0]])[3] - bbox([head_f[0]])[1]) /
                                          (bbox([head_f[0]])[2] - bbox([head_f[0]])[0]), 2)},
            "body": dict(widths(body_f, f), depth_m=f.L(bbox(body_s)[2] - bbox(body_s)[0]),
                         shape=shape_name(body_f, "body")),
            "arms": {"length_m": 0.0, "thickness_m": 0.0, "note": "руки в массе тела, кисти у бока — на деколи"},
            "legs": {"length_m": f.L(34), "thickness_m": f.L(30)},
            "shoes": {"length_m": f.L(68), "width_m": f.L(42), "height_m": f.L(26)},
            "colors": {"skin": G.B_SKIN, "cap": G.B_HAT, "dress": G.B_DRESS, "jabot": G.LACE, "stockings": G.B_STOCK,
                       "boots": G.B_BOOT},
            "details": [{"type": "чепец", "color": G.B_HAT, "size_m": f.L(128)},
                        {"type": "жабо", "color": G.LACE, "size_m": f.L(168)},
                        {"type": "пуговицы (12)", "color": G.INK, "size_m": f.L(6)}],
        },
    }


def police() -> dict:
    h = 2.05
    f = Frame(h)
    g = grid(G.P_GRID_K)
    side_svg = G.police("side")
    head_f = tf([sample_d(G.fur_d(G.P_CROWN, 7)), sample_d(G.fur_d(G.P_FOLD, 6))] +
                [sample_d(G.fur_d(p, 7)) for p in G.P_FLAPS] + [sample_d(G.smooth_d(G.P_FACE))], g)
    head_s = tf([sample_d(G.fur_d(G.superellipse(206, 60, 88, 40, 3.2, 26), 7)),
                 sample_d(G.fur_d(G.superellipse(150, 136, 34, 44, 2.4, 16, rot=10), 6)),
                 sample_d(G.fur_d(G.superellipse(270, 72, 30, 27, 3.2, 16), 6)),
                 sample_d(find_d(side_svg, "M196.0,92.0 C"))], g)
    coat_f = tf([sample_d(G.smooth_d(G.P_COAT_PTS))], g)
    coat_s_raw = [sample_d(find_d(side_svg, "M150.0,186.0 C"))]
    coat_s = tf(coat_s_raw, g)
    power = 3.0
    coat_rings = f.loft(coat_f, coat_s)

    def coat_front_z(y_raw: float) -> float:
        """Перед шинели в профиль на высоте y (координаты сетки e03, до P_GRID)."""
        e = extent(coat_s_raw, y_raw)
        return e[1] if e else 330.0

    def P(x, y, xs=200.0):
        a = g((x, y))
        b = g((xs, y))
        return f.P(a[0], a[1], b[0])

    parts = [
        part("head", "loft", "body", G.P_SKIN, rings=f.loft(head_f, head_s), power=2.4, decal="head"),
        part("coat", "loft", "body", G.P_COAT, rings=coat_rings, power=power,
             lines={"seam": [f.X(g((184, 0))[0]), f.Y(g((0, 262))[1]), f.Y(g((0, 482))[1])], "width": f.L(2.8)}),   # борт
    ]
    for i, (x, y) in enumerate(((172, 352), (170, 396), (234, 396), (236, 440))):
        parts.append(part("button_%d" % i, "ellipsoid", "body", G.BRASS, outline=False,
                          center=P(x, y, coat_front_z(y) + 1), radii=[f.L(5), f.L(5), f.L(3)]))
    cx, cy, w, hh, tilt = G.P_NOTE
    zf = coat_front_z(cy)
    pivots = {}
    # Правая рука персонажа (слева от зрителя, P_ARM_L): карандаш; левая (P_ARM_R): повязка и блокнот.
    arms = (("r", (90, 192), (24, 300), (112, 276), "pencil"), ("l", (320, 192), (386, 300), (222, 312), "note"))
    for side, sh, el, hand, holds in arms:
        group = "arm_" + side
        pivots[group] = P(sh[0], sh[1], 205)
        a, b = P(sh[0], sh[1], 205), P(el[0], el[1], 222)
        c = P(hand[0], hand[1], zf + 10)
        parts.append(part("upper_" + side, "capsule", group, G.P_COAT, a=a, b=b, r=f.L(30)))
        parts.append(part("fore_" + side, "capsule", group, G.P_COAT, a=b, b=c, r=f.L(27)))
        parts.append(part("hand_" + side, "ellipsoid", group, G.P_SKIN, center=c,
                          radii=[f.L(24), f.L(21), f.L(22)]))
        if side == "l":
            mid = [round(b[i] + (a[i] - b[i]) * 0.28, 4) for i in range(3)]
            parts.append(part("band", "capsule", group, G.P_BAND, a=mid, b=b, r=f.L(32)))
            nc = P(cx, cy, zf + 16)
            parts.append(part("note", "box", group, G.NOTE_PAPER, center=nc, size=[f.L(w), f.L(hh), f.L(8)],
                              rot=[0.0, 0.0, tilt]))
        else:
            pa, pb = G.P_PENCIL
            parts.append(part("pencil", "capsule", group, G.PENCIL, a=P(pa[0], pa[1], zf + 14),
                              b=P(pb[0], pb[1], zf + 14), r=f.L(4.5)))
    for side, pts in (("r", G.P_PANTS_L), ("l", G.mirror_pts(G.P_PANTS_L, G.P_LEG_AXIS))):
        x0, y0, x1, y1 = bbox([pts])
        xc = (x0 + x1) / 2
        group = "leg_" + side
        pivots[group] = P(xc, 470, 214)
        parts.append(part("pants_" + side, "capsule", group, G.P_PANTS, a=P(xc, 474, 214), b=P(xc, 516, 214),
                          r=f.L((x1 - x0) / 2 * G.P_GRID_K)))
    for side, pts in (("r", G.P_BOOT_L), ("l", G.P_BOOT_R)):
        x0, y0, x1, y1 = bbox([pts])
        group = "leg_" + side
        a = g(((x0 + x1) / 2, (y0 + y1) / 2))
        parts.append(part("boot_" + side, "ellipsoid", group, G.P_BOOT,
                          center=[f.X(a[0]), f.Y(a[1]), f.Z(g((236, 0))[0])],
                          radii=[f.L((x1 - x0) / 2 * G.P_GRID_K), f.L((y1 - y0) / 2 * G.P_GRID_K), f.L(70)]))
    hx0, hy0, hx1, hy1 = bbox(head_f)
    return {
        "height_m": h, "tone": 0.72, "tint": [1.0, 1.0, 1.0],
        "walk": {"leg_swing_deg": 24.0, "arm_swing_deg": 6.0, "stride_m": 0.5, "bob_m": 0.02},
        "decals": {"head": {"front": rect(head_f), "back": rect(head_f), "side": rect(head_s), "fallback": G.P_HAT,
                            "top": G.P_HAT, "texture": "police"}},
        "pivots": pivots, "parts": parts,
        "summary": {
            "figure_height_m": f.L(FEET_Y - hy0),
            "head": {"width_m": f.L(hx1 - hx0), "height_m": f.L(hy1 - hy0),
                     "depth_m": f.L(bbox(head_s)[2] - bbox(head_s)[0]),
                     "shape": shape_name(tf([sample_d(G.smooth_d(G.P_FACE))], g), "head"),
                     "note": "голова вместе с ушанкой: корона, клапаны до челюсти"},
            "body": dict(widths(coat_f, f), depth_m=f.L(bbox(coat_s)[2] - bbox(coat_s)[0]),
                         shape=shape_name(coat_f, "body")),
            "arms": {"length_m": f.L((math.dist((90, 192), (24, 300)) + math.dist((24, 300), (112, 276))) * G.P_GRID_K),
                     "thickness_m": f.L(60 * G.P_GRID_K), "pose": "согнуты к груди: блокнот и карандаш"},
            "legs": {"length_m": f.L(59 * G.P_GRID_K), "thickness_m": f.L(84 * G.P_GRID_K)},
            "shoes": {"length_m": f.L(142 * G.P_GRID_K), "width_m": f.L(98 * G.P_GRID_K), "height_m": f.L(62 * G.P_GRID_K)},
            "colors": {"skin": G.P_SKIN, "ushanka": G.P_HAT, "coat": G.P_COAT, "band": G.P_BAND, "pants": G.P_PANTS,
                       "boots": G.P_BOOT, "notebook": G.NOTE_PAPER, "pencil": G.PENCIL, "buttons": G.BRASS},
            "details": [{"type": "ушанка с клапанами", "color": G.P_HAT, "size_m": f.L(hx1 - hx0)},
                        {"type": "повязка на левом рукаве", "color": G.P_BAND, "size_m": f.L(90 * G.P_GRID_K)},
                        {"type": "блокнот", "color": G.NOTE_PAPER, "size_m": f.L(70 * G.P_GRID_K)},
                        {"type": "пуговицы (4)", "color": G.BRASS, "size_m": f.L(8.4)}],
        },
    }


def resident_shuba() -> dict:
    h = 2.0
    f = Frame(h)
    side_svg = G.resident_shuba("side")
    head_f = [sample_d(G.smooth_d(G.RS_TURBAN_PTS)), sample_d(G.smooth_d(G.RS_FACE_PTS)), ellipse_pts(150, 176, 14, 12)]
    head_s = [sample_d(find_d(side_svg, "M158.0,192.0 C")), sample_d(find_d(side_svg, "M214.0,182.0 C")),
              ellipse_pts(170, 178, 14, 12)]
    fur_f = [sample_d(G.smooth_d(G.RS_FUR_PTS))]
    fur_s = [sample_d(find_d(side_svg, "M150.0,222.0 C"))]
    coat_f = [sample_d(G.smooth_d(G.RS_COAT_PTS))]
    coat_s = [sample_d(find_d(side_svg, "M162.0,222.0 C"))]
    parts = [
        part("head", "loft", "body", G.RS_SKIN, rings=f.loft(head_f, head_s), power=2.0, decal="head"),
        # Воротник-шаль начинается под подбородком: на рисунке лицо лежит поверх меха, объёмом мех его не закрывает.
        part("fur", "loft", "body", G.RS_FUR, rings=f.loft(fur_f, fur_s, y_range=(250, 600)), power=2.0),
        part("coat", "loft", "body", G.RS_COAT, rings=f.loft(coat_f, coat_s, y_range=(250, 600)), power=2.0,
             lines={"seam": [0.0, f.Y(330), f.Y(526)], "width": f.L(2.6)}),   # борт шубы
    ]
    pivots = {}
    for side, (sh, cuff, bag) in (("r", ((126, 262), (106, 436), G.RS_BAGS[0])), ("l", ((278, 280), (300, 436), G.RS_BAGS[1]))):
        group = "arm_" + side
        pivots[group] = f.P(sh[0], sh[1], 205)
        parts.append(part("sleeve_" + side, "capsule", group, G.RS_COAT, a=f.P(sh[0], sh[1], 205),
                          b=f.P(cuff[0], cuff[1], 205), r=f.L(24)))
        hx, hy, w, hh, dx = bag
        parts.append(part("hand_" + side, "ellipsoid", group, G.RS_SKIN, center=f.P(hx, hy - 2, 205),
                          radii=[f.L(10), f.L(11), f.L(10)]))
        parts.append(part("bag_" + side, "box", group, G.RS_BAG, center=f.P(hx + dx, hy + hh * 0.58, 205),
                          size=[f.L(w * 0.92), f.L(hh * 0.84), f.L(w * 0.42)], rot=[0.0, 0.0, 0.0]))
    for side, (xc, w, toe) in (("r", G.RS_BOOTS[0]), ("l", G.RS_BOOTS[1])):
        group = "leg_" + side
        pivots[group] = f.P(xc, 500, 205)
        parts.append(part("boot_" + side, "ellipsoid", group, G.RS_BOOT, center=f.P(xc, 556, 210),
                          radii=[f.L(w / 2), f.L(32), f.L(34)]))
    hx0, hy0, hx1, hy1 = bbox(head_f)
    return {
        "height_m": h, "tone": 0.72, "tint": [1.0, 1.0, 1.0],
        "walk": {"leg_swing_deg": 18.0, "arm_swing_deg": 10.0, "stride_m": 0.4, "bob_m": 0.015},
        "decals": {"head": {"front": rect(head_f), "back": rect(head_f), "side": rect(head_s), "fallback": G.RS_SKIN,
                            "top": G.RS_TURBAN, "texture": "resident_shuba"}},
        "pivots": pivots, "parts": parts,
        "summary": {
            "figure_height_m": f.L(FEET_Y - hy0),
            "head": {"width_m": f.L(hx1 - hx0), "height_m": f.L(hy1 - hy0),
                     "depth_m": f.L(bbox(head_s)[2] - bbox(head_s)[0]),
                     "shape": shape_name([sample_d(G.smooth_d(G.RS_FACE_PTS))], "head"),
                     "note": "голова вместе с голубой «чалмой»"},
            "body": dict(widths(coat_f, f), depth_m=f.L(bbox(coat_s)[2] - bbox(coat_s)[0]),
                         shape=shape_name(coat_f, "body")),
            "arms": {"length_m": f.L(176), "thickness_m": f.L(48), "pose": "вдоль тела, пакеты в кулаках"},
            "legs": {"length_m": 0.0, "thickness_m": 0.0, "note": "ноги под шубой, видны сапоги"},
            "shoes": {"length_m": f.L(68), "width_m": f.L(50), "height_m": f.L(74)},
            "colors": {"skin": G.RS_SKIN, "turban": G.RS_TURBAN, "hair": G.RS_HAIR, "coat": G.RS_COAT, "fur": G.RS_FUR,
                       "boots": G.RS_BOOT, "bags": G.RS_BAG},
            "details": [{"type": "меховой воротник-шаль", "color": G.RS_FUR,
                         "size_m": f.L(bbox(fur_f)[2] - bbox(fur_f)[0])},
                        {"type": "чалма", "color": G.RS_TURBAN, "size_m": f.L(110)},
                        {"type": "пакеты (2)", "color": G.RS_BAG, "size_m": f.L(94)}],
        },
    }


def main() -> None:
    characters = {"ilyusha": ilyusha(), "babka": babka(), "police": police(), "resident_shuba": resident_shuba()}
    for name, c in characters.items():
        c["m_per_unit"] = round(c["height_m"] / 600.0, 6)
        for key, decal in c["decals"].items():
            tex = decal.pop("texture")
            decal["textures"] = {v: f"res://assets/art/characters/{tex}_{v}_idle.svg" for v in ("front", "back", "side")}
    data = {
        "version": 1,
        "source": "tools/generate_characters.py (формы и палитры), tools/character_passports.py (CHAR3D-01)",
        "canvas": {"width": 400, "height": 600, "feet_y": FEET_Y, "axis": AXIS, "side_axis": SIDE_AXIS},
        "axes": "X — правая рука персонажа, Y — вверх от подошв, Z — назад (взгляд в −Z), метры",
        "characters": characters,
    }
    OUT.write_text(json.dumps(data, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    for name, c in characters.items():
        s = c["summary"]
        print(f"PASSPORT {name}: рост {s['figure_height_m']:.2f} м, голова {s['head']['width_m']:.2f}×"
              f"{s['head']['height_m']:.2f}×{s['head']['depth_m']:.2f} ({s['head']['shape']}), тело "
              f"{s['body']['shoulders_m']:.2f}/{s['body']['middle_m']:.2f}/{s['body']['hips_m']:.2f} × "
              f"{s['body']['height_m']:.2f} ({s['body']['shape']}), деталей {len(c['parts'])}")
    print(f"PASSPORTS: {len(characters)} -> {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
