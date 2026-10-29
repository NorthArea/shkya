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
        # Цвет головы — ушанки: там, где рисунок прозрачен (затылок сверху, края клапанов), — мех, а не кожа.
        part("head", "loft", "body", G.P_HAT, rings=f.loft(head_f, head_s), power=2.4, decal="head"),
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
            # Повязка — на плече (середина плечевой части руки), а не у локтя (CHAR3D-02).
            lo = [round(b[i] + (a[i] - b[i]) * 0.35, 4) for i in range(3)]
            hi = [round(b[i] + (a[i] - b[i]) * 0.7, 4) for i in range(3)]
            parts.append(part("band", "capsule", group, G.P_BAND, a=hi, b=lo, r=f.L(32)))
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


# ------------------------------------------------------------------ CHAR3D-02: разбор готовых SVG и авто-паспорт
#
# Для всех, у кого нет ручного паспорта: формы берутся из файлов assets/art/characters/<имя>_<вид>_idle.svg (то, что
# видит игрок), а не из функций генератора, — поэтому паспорт совпадает с рисунком и после правок ART-08 достаточно
# перезапустить скрипт. Каждая залитая форма (path/ellipse/rect, с трансформами групп; тени-штрихи с opacity < 0,9 и
# блики/тени внутри clip-path не в счёт) режется горизонталями: на высоте y получается набор отрезков силуэта. Дальше:
# голова — центральный отрезок выше подбородка (таблица AUTO: chin), тело — центральный отрезок до промежности (где
# между ног появляется просвет), руки — боковые отрезки выше промежности (слева от оси рисунка — правая рука), ноги —
# левый и правый отрезки ниже промежности. Глубина каждого среза — по центральному отрезку бокового рисунка. Нос,
# торчащий в профиль вперёд, отделяется от головы своей деталью. Предметы и животные, которых автомат не выделит
# (собака, санки, бидон, пакеты…), — явные прямоугольники AUTO[...]["details"]: их отрезки забирает деталь.
# Всё тело покрыто деколью трёх рисунков (как платье Бабки), цвет детали — преобладающая заливка её области.

ART = ROOT / "assets" / "art" / "characters"
INK_HEX = "#141213"
_TAG = re.compile(r"<(/?)([a-zA-Z]+)([^>]*?)(/?)>")
_ATTR = re.compile(r'([a-zA-Z:-]+)="([^"]*)"')
_TF = re.compile(r"(translate|scale|rotate|matrix)\(([^)]*)\)")


def _mat_mul(m, n):
    a, b, c, d, e, f = m
    a2, b2, c2, d2, e2, f2 = n
    return (a * a2 + c * b2, b * a2 + d * b2, a * c2 + c * d2, b * c2 + d * d2, a * e2 + c * f2 + e, b * e2 + d * f2 + f)


def parse_transform(s: str):
    m = (1.0, 0.0, 0.0, 1.0, 0.0, 0.0)
    for kind, args in _TF.findall(s or ""):
        v = [float(t) for t in re.split(r"[\s,]+", args.strip()) if t]
        if kind == "translate":
            n = (1, 0, 0, 1, v[0], v[1] if len(v) > 1 else 0.0)
        elif kind == "scale":
            n = (v[0], 0, 0, v[1] if len(v) > 1 else v[0], 0, 0)
        elif kind == "rotate":
            r = math.radians(v[0])
            cs, sn = math.cos(r), math.sin(r)
            n = (cs, sn, -sn, cs, 0, 0)
            if len(v) == 3:
                n = _mat_mul(_mat_mul((1, 0, 0, 1, v[1], v[2]), n), (1, 0, 0, 1, -v[1], -v[2]))
        else:
            n = tuple(v)
        m = _mat_mul(m, n)
    return m


def _apply(m, p):
    return (m[0] * p[0] + m[2] * p[1] + m[4], m[1] * p[0] + m[3] * p[1] + m[5])


def subpaths(d: str, steps: int = 8) -> list[list[tuple[float, float]]]:
    """Контуры пути SVG (M/L/H/V/C/S/Q/T/Z, абсолютные и относительные); каждое M — новый контур."""
    tokens = _TOKEN.findall(d)
    out: list[list[tuple[float, float]]] = []
    pts: list[tuple[float, float]] = []
    i, cmd = 0, ""
    cx = cy = sx = sy = 0.0
    last_c = None

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
                cx, cy = sx, sy
                if len(pts) >= 2:
                    out.append(pts)
                pts = []
                continue
        rel = cmd.islower()
        c = cmd.upper()
        ox, oy = (cx, cy) if rel else (0.0, 0.0)
        if c == "M":
            if len(pts) >= 2:
                out.append(pts)
            cx, cy = num() + ox, num() + oy
            sx, sy = cx, cy
            pts = [(cx, cy)]
            cmd = "l" if rel else "L"
            last_c = None
        elif c == "L":
            cx, cy = num() + ox, num() + oy
            pts.append((cx, cy))
            last_c = None
        elif c == "H":
            cx = num() + (cx if rel else 0.0)
            pts.append((cx, cy))
            last_c = None
        elif c == "V":
            cy = num() + (cy if rel else 0.0)
            pts.append((cx, cy))
            last_c = None
        elif c in "CS":
            if c == "C":
                c1 = (num() + ox, num() + oy)
            else:
                c1 = (2 * cx - last_c[0], 2 * cy - last_c[1]) if last_c else (cx, cy)
            c2 = (num() + ox, num() + oy)
            p = (num() + ox, num() + oy)
            for k in range(1, steps + 1):
                t = k / steps
                a_, b_, c_, e_ = (1 - t) ** 3, 3 * (1 - t) ** 2 * t, 3 * (1 - t) * t * t, t ** 3
                pts.append((a_ * cx + b_ * c1[0] + c_ * c2[0] + e_ * p[0], a_ * cy + b_ * c1[1] + c_ * c2[1] + e_ * p[1]))
            last_c = c2
            cx, cy = p
        elif c in "QT":
            if c == "Q":
                c1 = (num() + ox, num() + oy)
            else:
                c1 = (2 * cx - last_c[0], 2 * cy - last_c[1]) if last_c else (cx, cy)
            p = (num() + ox, num() + oy)
            for k in range(1, steps + 1):
                t = k / steps
                a_, b_, c_ = (1 - t) ** 2, 2 * (1 - t) * t, t * t
                pts.append((a_ * cx + b_ * c1[0] + c_ * p[0], a_ * cy + b_ * c1[1] + c_ * p[1]))
            last_c = c1
            cx, cy = p
        else:
            raise ValueError(f"команда пути {cmd!r} не поддержана: {d[:60]}")
    if len(pts) >= 2:
        out.append(pts)
    return out


class Shape:
    __slots__ = ("fill", "polys", "pad", "bbox", "tube")

    def __init__(self, fill, polys, pad, tube=False):
        self.fill, self.polys, self.pad, self.tube = fill, polys, pad, tube
        xs = [p[0] for q in polys for p in q]
        ys = [p[1] for q in polys for p in q]
        self.bbox = (min(xs) - pad, min(ys) - pad, max(xs) + pad, max(ys) + pad)


def _tube_polys(pts, w):
    """Штрих шириной w как цепочка четырёхугольников (рука-«трубка», полоз санок)."""
    out = []
    h = w / 2
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        dx, dy = x1 - x0, y1 - y0
        L = math.hypot(dx, dy)
        if L < 1e-6:
            continue
        nx, ny = -dy / L * h, dx / L * h
        out.append([(x0 + nx, y0 + ny), (x1 + nx, y1 + ny), (x1 - nx, y1 - ny), (x0 - nx, y0 - ny)])
    return out


class Drawing:
    """Залитые формы одного SVG в порядке рисования (сверху — последние)."""

    def __init__(self, path: Path):
        text = path.read_text(encoding="utf-8")
        vb = re.search(r'viewBox="([^"]*)"', text).group(1).split()
        self.view = (float(vb[0]), float(vb[2]))
        text = re.sub(r"<defs>.*?</defs>", "", text, flags=re.S)
        self.shapes: list[Shape] = []
        stack = [((1.0, 0.0, 0.0, 1.0, 0.0, 0.0), False)]
        for close, tag, attrs, selfclose in _TAG.findall(text):
            if tag == "svg":
                continue
            if close:
                if tag == "g" and len(stack) > 1:
                    stack.pop()
                continue
            a = dict(_ATTR.findall(attrs))
            m, skip = stack[-1]
            m = _mat_mul(m, parse_transform(a.get("transform", "")))
            hidden = skip or "clip-path" in a or float(a.get("opacity", "1")) < 0.9
            if tag == "g":
                if not selfclose:
                    stack.append((m, hidden))
                continue
            if hidden:
                continue
            fill = a.get("fill", "#000000")
            stroke = a.get("stroke")
            sw = float(a.get("stroke-width", "0")) if stroke and stroke != "none" else 0.0
            polys = []
            if tag == "path":
                polys = subpaths(a["d"])
            elif tag == "ellipse":
                polys = [ellipse_pts(float(a["cx"]), float(a["cy"]), float(a["rx"]), float(a["ry"]), 20)]
            elif tag == "rect":
                x, y, w, h = (float(a.get(k, "0")) for k in ("x", "y", "width", "height"))
                polys = [[(x, y), (x + w, y), (x + w, y + h), (x, y + h)]]
            if not polys:
                continue
            polys = [[_apply(m, p) for p in q] for q in polys]
            k = math.sqrt(abs(m[0] * m[3] - m[1] * m[2]))
            if fill != "none" and not fill.startswith("url("):
                self.shapes.append(Shape(fill.upper(), polys, sw * k / 2))
            elif fill == "none" and sw * k >= 5.0 and tag == "path":
                # Толстый штрих — сама форма (рука-трубка, полоз, хвост); цвет — штриха.
                tp = [t for q in polys for t in _tube_polys(q, sw * k)]
                if tp:
                    self.shapes.append(Shape(stroke.upper(), tp, 0.0, tube=True))
        self.bounds = (min(s.bbox[0] for s in self.shapes), min(s.bbox[1] for s in self.shapes),
                       max(s.bbox[2] for s in self.shapes), max(s.bbox[3] for s in self.shapes))

    def intervals(self, y: float, min_w: float = 3.0, gap: float = 3.0) -> list[list[float]]:
        """Отрезки силуэта на высоте y (объединение всех форм), узкие (поводок, дымок) отброшены."""
        spans = []
        for s in self.shapes:
            if y < s.bbox[1] or y > s.bbox[3]:
                continue
            for poly in s.polys:
                xs = []
                n = len(poly)
                for j in range(n):
                    (x0, y0), (x1, y1) = poly[j], poly[(j + 1) % n]
                    if (y0 <= y < y1) or (y1 <= y < y0):
                        xs.append(x0 + (x1 - x0) * (y - y0) / (y1 - y0))
                xs.sort()
                for i in range(0, len(xs) - 1, 2):
                    spans.append([xs[i] - s.pad, xs[i + 1] + s.pad])
        spans.sort()
        merged: list[list[float]] = []
        for a, b in spans:
            if merged and a <= merged[-1][1] + gap:
                merged[-1][1] = max(merged[-1][1], b)
            else:
                merged.append([a, b])
        return [m for m in merged if m[1] - m[0] >= min_w]

    def color_at(self, x: float, y: float) -> str | None:
        for s in reversed(self.shapes):
            if not (s.bbox[0] <= x <= s.bbox[2] and s.bbox[1] <= y <= s.bbox[3]):
                continue
            for poly in s.polys:
                if _inside(poly, x, y):
                    return s.fill
        return None


def _inside(poly, x, y) -> bool:
    c = False
    n = len(poly)
    for j in range(n):
        (x0, y0), (x1, y1) = poly[j], poly[(j + 1) % n]
        if (y0 > y) != (y1 > y) and x < x0 + (x1 - x0) * (y - y0) / (y1 - y0):
            c = not c
    return c


def _median3(vals: list[float]) -> list[float]:
    if len(vals) < 3:
        return vals
    return [vals[0]] + [sorted(vals[i - 1:i + 2])[1] for i in range(1, len(vals) - 1)] + [vals[-1]]


def _pick(spans, center):
    """Отрезок, содержащий center, иначе ближайший."""
    best, dist = None, 1e9
    for s in spans:
        d = 0.0 if s[0] <= center <= s[1] else min(abs(s[0] - center), abs(s[1] - center))
        if d < dist:
            best, dist = s, d
    return best, dist


def _clip(spans, x0, x1):
    out = []
    for a, b in spans:
        a2, b2 = max(a, x0), min(b, x1)
        if b2 - a2 > 1.0:
            out.append([a2, b2])
    return out


def _cut(spans, x0, x1):
    out = []
    for a, b in spans:
        if b <= x0 or a >= x1:
            out.append([a, b])
            continue
        if a < x0 - 1.0:
            out.append([a, x0])
        if b > x1 + 1.0:
            out.append([x1, b])
    return out


# Таблица авто-паспортов: рост холста в игре (height_m) и всё, что автомат сам не знает.
#   chin — низ лица/головы на фронтальном рисунке (y холста): граница голова/тело;
#   details — предметы и животные: имя, тип (для сводки), группа, прямоугольник на фасе [x0, x1, y0, y1] и на боку
#             [x0, x1] (y — тот же) или None — глубина по ширине; power — форма среза (4 — коробка).
#   no_legs — ноги под одеждой без просвета: шагают только сапоги (низ, legs_from).
AUTO = {
    "vendor": {"height_m": 1.95, "chin": 258, "depth_k": 0.7, "tint": [1.0, 1.0, 1.0],
               "details": [], "note": "продавщица: фартук и платок — деколью"},
    "officer": {"height_m": 2.2, "chin": 158, "details": [
        {"name": "clipboard", "type": "планшет «военкома»", "group": "arm_l", "front": [200, 290, 220, 330], "side": None,
         "power": 5.0}]},
    "guard": {"height_m": 2.05, "chin": 150, "details": []},
    "resident_babka": {"height_m": 2.0, "chin": 312, "details": []},
    "resident_man": {"height_m": 2.0, "chin": 244, "details": []},
    "resident_woman": {"height_m": 2.0, "chin": 264, "details": [
        {"name": "sled", "type": "санки", "group": "body", "front": [244, 380, 526, 586], "side": [0, 204], "power": 4.0}]},
    "resident_boy": {"height_m": 2.0, "chin": 374, "details": []},
    "resident_shuba": {"height_m": 2.0, "chin": 265, "details": []},
    "resident_beret": {"height_m": 2.0, "chin": 252, "details": []},
    "resident_violet": {"height_m": 2.0, "chin": 288, "details": []},
    "resident_ushanka": {"height_m": 2.0, "chin": 175, "crotch": 420.0, "leg_axis": 206.0, "details": []},
    "resident_ushanka_walk": {"height_m": 2.0, "chin": 175, "crotch": 420.0, "leg_axis": 206.0, "details": []},
    "resident_tourist": {"height_m": 2.0, "chin": 204, "details": []},
    "resident_kid": {"height_m": 2.0, "chin": 256, "details": []},
    "resident_kid2": {"height_m": 2.0, "chin": 256, "details": []},
    "resident_dog": {"height_m": 2.0, "chin": 264, "details": [
        {"name": "dog", "type": "собачка на поводке", "group": "body", "front": [290, 400, 510, 592], "side": [296, 400],
         "power": 2.0}]},
    "resident_kolpak": {"height_m": 2.0, "chin": 290, "nose": False, "details": []},
    "resident_bow": {"height_m": 2.0, "chin": 292, "details": []},
    "resident_turban": {"height_m": 2.0, "chin": 258, "details": []},
}


def _dominant(drawing: Drawing, samples) -> str:
    count: dict[str, int] = {}
    for x, y in samples:
        c = drawing.color_at(x, y)
        if c and c != INK_HEX.upper():
            count[c] = count.get(c, 0) + 1
    return max(count, key=count.get) if count else "#808080"


def auto_passport(name: str, cfg: dict) -> dict:
    front = Drawing(ART / f"{name}_front_idle.svg")
    side = Drawing(ART / f"{name}_side_idle.svg")
    h = cfg["height_m"]
    f = Frame(h)
    x0, top, x1, bottom = front.bounds
    bottom = min(bottom, 592.0)
    # Ось тела — середина силуэта (от крайнего левого до крайнего правого) на 30–80 % высоты фигуры, медиана.
    cs = []
    for t in (0.3, 0.4, 0.5, 0.6, 0.7, 0.8):
        sp = front.intervals(top + (bottom - top) * t)
        if sp:
            cs.append((min(s[0] for s in sp) + max(s[1] for s in sp)) / 2)
    axis = sorted(cs)[len(cs) // 2] if cs else 200.0
    scs = []
    for t in (0.45, 0.55, 0.65, 0.75):
        sp = side.intervals(top + (bottom - top) * t)
        if sp:
            w = max(sp, key=lambda s: s[1] - s[0])
            scs.append((w[0] + w[1]) / 2)
    saxis = sorted(scs)[len(scs) // 2] if scs else 200.0
    details = cfg.get("details", [])

    def front_spans(y):
        sp = front.intervals(y)
        for d in details:
            fx0, fx1, fy0, fy1 = d["front"]
            if fy0 <= y <= fy1:
                sp = _cut(sp, fx0, fx1)
        return sp

    def side_spans(y):
        sp = side.intervals(y)
        for d in details:
            fy0, fy1 = d["front"][2], d["front"][3]
            if d.get("side") and fy0 <= y <= fy1:
                sp = _cut(sp, d["side"][0], d["side"][1])
        return sp

    # Ось ног — середина силуэта у подошв; промежность — снизу вверх, пока эта ось в просвете между ногами.
    low = front_spans(bottom - 12.0)
    leg_axis = cfg.get("leg_axis") or ((min(s[0] for s in low) + max(s[1] for s in low)) / 2 if low else axis)

    def crotch_for(ax):
        found, misses, y = None, 0, bottom - 8.0
        while y > top + (bottom - top) * 0.35 and misses < 4:
            if _pick(front_spans(y), ax)[1] > 0.5:
                found, misses = y, 0
            else:
                misses += 1
            y -= 2.0
        return found

    if "crotch" in cfg:
        crotch = cfg["crotch"]
    else:
        cands = [(c, ax) for ax in (leg_axis, axis) for c in [crotch_for(ax)] if c is not None]
        crotch, ax = min(cands) if cands else (None, leg_axis)
        leg_axis = ax
        if crotch is not None and crotch > bottom - 14.0:
            crotch = None    # просвет только у самых подошв — шага не видно
    legs_top = crotch if crotch is not None else bottom - 30.0
    chin = cfg.get("chin") or (top + (legs_top - top) * 0.3)

    # Ряды: центральный отрезок (тело/голова) и боковые. Боковые ближе ABSORB к центральному — его часть (рукав, клапан
    # ушанки, край шубы); боковые полосы короче ARM_MIN рядов — тоже (обрывки контура), иначе — рука своей стороны.
    ABSORB, ARM_MIN = 8.0, 5
    step = 4.0
    raw = []
    y = top + 0.6
    while y < bottom - 0.6:
        sp = front_spans(y)
        sc, _ = _pick(side_spans(y), saxis)
        c, dist = _pick(sp, axis) if y < legs_top else (None, 1e9)
        if c is not None and dist < (90.0 if y <= chin else 30.0):   # макушка: помпон, верх фуражки — не по оси
            c = list(c)
            changed = True
            rest = [s for s in sp if s[0] != c[0] or s[1] != c[1]]
            while changed:
                changed = False
                for s in list(rest):
                    if s[0] - c[1] < ABSORB and c[0] - s[1] < ABSORB:
                        c = [min(c[0], s[0]), max(c[1], s[1])]
                        rest.remove(s)
                        changed = True
        else:
            c, rest = None, (sp if y < legs_top else [])
        raw.append([y, c, rest, sc, sp])
        y += step
    side_rows = {"r": [], "l": []}
    for i, (y, c, rest, sc, sp) in enumerate(raw):
        for s in rest:
            side_rows["r" if (s[0] + s[1]) / 2 < axis else "l"].append((i, s))
    rows_arm = {"r": [], "l": []}
    for key in ("r", "l"):
        groups_, cur = [], []
        for i, s in side_rows[key]:
            if cur and i - cur[-1][0] > 1:
                groups_.append(cur)
                cur = []
            if cur and cur[-1][0] == i:   # два отрезка в ряду с одной стороны — общий
                j, s0 = cur.pop()
                s = [min(s0[0], s[0]), max(s0[1], s[1])]
            cur.append((i, s))
        if cur:
            groups_.append(cur)
        for g in groups_:
            if len(g) < ARM_MIN or max(s[1] - s[0] for _, s in g) < 8.0:
                for i, s in g:
                    c = raw[i][1]
                    if c is not None:
                        raw[i][1] = [min(c[0], s[0]), max(c[1], s[1])]
            else:
                rows_arm[key].extend((raw[i][0], s, raw[i][3]) for i, s in g)
    rows_head = [(y, c, sc) for y, c, rest, sc, sp in raw if c is not None and y <= chin]
    rows_body = [(y, c, sc) for y, c, rest, sc, sp in raw if c is not None and chin < y < legs_top]
    rows_leg = {"r": [], "l": []}
    for y, c, rest, sc, sp in raw:
        if y < legs_top - 4.0:
            continue
        halves = {"r": [], "l": []}
        for s0, s1 in sp:
            if s0 < leg_axis < s1:
                halves["r"].append([s0, leg_axis])
                halves["l"].append([leg_axis, s1])
            else:
                halves["r" if (s0 + s1) / 2 < leg_axis else "l"].append([s0, s1])
        for key in ("r", "l"):
            if halves[key]:
                rows_leg[key].append((y, [min(s[0] for s in halves[key]), max(s[1] for s in halves[key])], sc))

    parts: list[dict] = []
    pivots: dict = {}

    def runs(rows):
        out, cur = [], []
        for r in rows:
            if cur and r[0] - cur[-1][0] > step * 1.5:
                out.append(cur)
                cur = []
            cur.append(r)
        if cur:
            out.append(cur)
        return [r for r in out if len(r) >= 2]

    def rings_of(rows, depth_ratio=0.8, zc_default=None, rz_cap=None):
        ys, xc, rx, zc, rz = [], [], [], [], []
        for y, s, sc in rows:
            ys.append(y)
            xc.append((s[0] + s[1]) / 2)
            rx.append((s[1] - s[0]) / 2)
            if sc is not None and zc_default is None:
                zc.append((sc[0] + sc[1]) / 2)
                rz.append((sc[1] - sc[0]) / 2)
            else:
                zc.append(zc_default if zc_default is not None else saxis)
                rz.append((s[1] - s[0]) / 2 * depth_ratio)
            if rz_cap is not None:
                rz[-1] = min(rz[-1], rz_cap)
        xc, rx, zc, rz = _median3(xc), _median3(rx), _median3(zc), _median3(rz)
        return [[f.Y(y), f.X(a), f.L(b), f.Z(c), f.L(d)] for y, a, b, c, d in zip(ys, xc, rx, zc, rz)]

    def samples(rows):
        pts = []
        for y, s, _ in rows:
            for k in (0.2, 0.35, 0.5, 0.65, 0.8):
                pts.append((s[0] + (s[1] - s[0]) * k, y))
        return pts

    # Голова и нос: передний край головы в профиль выше базовой линии (медиана) больше чем на 14 — нос.
    nose_rows = []
    if rows_head:
        fronts = sorted(r[2][1] for r in rows_head if r[2] is not None)
        base = fronts[len(fronts) // 2] if fronts else saxis
        head_rows = []
        for y, s, sc in rows_head:
            hy = (y - rows_head[0][0]) / max(1.0, rows_head[-1][0] - rows_head[0][0])
            if sc is not None and sc[1] > base + 14.0 and 0.3 < hy < 0.88 and cfg.get("nose", True):
                nose_rows.append((y, [ (s[0] + s[1]) / 2 - 9, (s[0] + s[1]) / 2 + 9], [base - 10, sc[1]]))
                sc = [sc[0], base]
            head_rows.append((y, s, sc))
        # Голова и тело — один лофт (CHAR3D-02): у двух лофтов оболочка-контур головы проступала кольцом на шее.
        trunk = rings_of(head_rows + rows_body)
        chin_m = f.Y(chin)
        for r in trunk:   # рисунок бока совпадает с фасом (продавщица за прилавком) — тоньше по глубине
            if r[0] < chin_m:
                r[4] = round(r[4] * cfg.get("depth_k", 1.0), 4)
        parts.append(part("head", "loft", "body", _dominant(front, samples(rows_body or head_rows)), rings=trunk,
                          power=2.15, decal=True, top=True, covers="голова и тело"))
        for k, run in enumerate(r for r in runs(nose_rows) if len(r) >= 3 and cfg.get("nose", True)):
            parts.append(part("nose" if k == 0 else "nose_%d" % k, "loft", "body", _dominant(side, [
                ((r[2][0] + r[2][1]) / 2, r[0]) for r in run]), rings=rings_of(run), power=2.0, decal=True))
    body_rz = {round(r[0]): (r[2][1] - r[2][0]) / 2 for r in rows_body if r[2] is not None}
    body_zc = {round(r[0]): (r[2][0] + r[2][1]) / 2 for r in rows_body if r[2] is not None}
    for key in ("r", "l"):
        for k, run in enumerate(runs(rows_arm[key])):
            group = "arm_" + key
            zc = body_zc.get(round(run[0][0]), saxis)
            cap = max(6.0, min(body_rz.values()) if body_rz else 30.0)
            nm = group if k == 0 else "%s_%d" % (group, k)
            parts.append(part(nm, "loft", group, _dominant(front, samples(run)),
                              rings=rings_of([(y, s, None) for y, s, _ in run], 0.9, zc, cap), power=2.0, decal=True))
            if group not in pivots:
                y0, s0, _ = run[0]
                pivots[group] = f.P((s0[0] + s0[1]) / 2, y0, zc)
    for key in ("r", "l"):
        for k, run in enumerate(runs(rows_leg[key])):
            group = "leg_" + key
            nm = group if k == 0 else "%s_%d" % (group, k)
            parts.append(part(nm, "loft", group, _dominant(front, samples(run)), rings=rings_of(run), power=2.2,
                              decal=True))
            if group not in pivots:
                y0, s0, sc0 = run[0]
                pivots[group] = f.P((s0[0] + s0[1]) / 2, y0, (sc0[0] + sc0[1]) / 2 if sc0 else saxis)
    for d in details:
        fx0, fx1, fy0, fy1 = d["front"]
        rows = []
        y = fy0 + 0.5
        while y < fy1:
            sp = _clip(front.intervals(y), fx0, fx1)
            if sp:
                s = [min(a for a, _ in sp), max(b for _, b in sp)]
                sc = None
                if d.get("side"):
                    ss = _clip(side.intervals(y), d["side"][0], d["side"][1])
                    if ss:
                        sc = [min(a for a, _ in ss), max(b for _, b in ss)]
                rows.append((y, s, sc))
            y += 3.0
        group = d["group"]
        for k, run in enumerate(runs(rows)):
            if any(r[2] is None for r in run) and d.get("side"):
                run = [(y, s, sc if sc else [saxis - (s[1] - s[0]) / 2, saxis + (s[1] - s[0]) / 2]) for y, s, sc in run]
            zc = None if d.get("side") else body_zc.get(round(run[0][0]), saxis) - 20.0
            rings = rings_of(run if d.get("side") else [(y, s, None) for y, s, _ in run], 0.5, zc)
            parts.append(part(d["name"] if k == 0 else "%s_%d" % (d["name"], k), "loft",
                              group if group in pivots or group == "body" else "body",
                              _dominant(front, samples(run)), rings=rings, power=d.get("power", 2.0), decal=True))
    top_color = front.color_at(axis, top + 6.0) or (parts[0]["color"] if parts else "#808080")
    hb = [r for r in rows_head]
    head_w = max((r[1][1] - r[1][0]) for r in hb) if hb else 0.0
    head_d = max((r[2][1] - r[2][0]) for r in hb if r[2]) if hb else 0.0
    bw = lambda t: (lambda r: f.L(r[1][1] - r[1][0]))(rows_body[min(len(rows_body) - 1, int(len(rows_body) * t))]) \
        if rows_body else 0.0
    leg_parts = [p for p in parts if p["group"].startswith("leg")]
    arm_parts = [p for p in parts if p["group"].startswith("arm")]
    colors = {}
    for p in parts:
        colors.setdefault(p["name"], p["color"])
    return {
        "height_m": h, "tone": 0.72, "tint": cfg.get("tint", [1.0, 1.0, 1.0]),
        "walk": {"leg_swing_deg": 22.0 if crotch is not None else 14.0, "arm_swing_deg": 12.0,
                 "stride_m": 0.42 if crotch is not None else 0.32, "bob_m": 0.015},
        "decal": {"view": list(front.view), "top": top_color, "top_y": f.Y(chin)},
        "pivots": pivots, "parts": parts,
        "auto": {"axis": round(axis, 1), "side_axis": round(saxis, 1), "chin": round(chin, 1),
                 "crotch": round(crotch, 1) if crotch is not None else None,
                 "legs": "ноги с просветом" if crotch is not None else "под одеждой: шагают только низы"},
        "summary": {
            "figure_height_m": f.L(FEET_Y - top),
            "head": {"width_m": f.L(head_w), "height_m": f.L(chin - top), "depth_m": f.L(head_d),
                     "shape": "лофт по силуэтам", "nose": "отдельная деталь" if nose_rows else "в рисунке"},
            "body": {"shoulders_m": bw(0.12), "middle_m": bw(0.5), "hips_m": bw(0.88),
                     "height_m": f.L(((rows_body[-1][0] - rows_body[0][0]) if rows_body else 0.0)), "shape": "лофт"},
            "arms": {"parts": len(arm_parts), "note": "отдельные отрезки силуэта" if arm_parts else "в массе тела"},
            "legs": {"parts": len(leg_parts)},
            "colors": colors,
            "details": [{"type": d["type"], "group": d["group"]} for d in details],
        },
    }


def main() -> None:
    characters = {"ilyusha": ilyusha(), "babka": babka(), "police": police()}
    for name, cfg in AUTO.items():
        if (ART / f"{name}_front_idle.svg").exists() and (ART / f"{name}_side_idle.svg").exists():
            characters[name] = auto_passport(name, cfg)
        else:
            print(f"PASSPORT {name}: нет SVG — пропущен")
    plain = {"nose", "nose_tip", "pencil", "collar", "jabot", "band"}   # объём вместо рисунка: без деколи (фестоны — цветом)
    for name, c in characters.items():
        c["m_per_unit"] = round(c["height_m"] / 600.0, 6)
        if "decals" in c:   # ручной паспорт CHAR3D-01 → одна деколь на всё тело (CHAR3D-02)
            head = c.pop("decals")["head"]
            c["decal"] = {"view": [0.0, 400.0], "top": head.get("top", head["fallback"]), "erase": head.get("erase", {})}
            for p in c["parts"]:
                p["decal"] = p["name"] not in plain
                if name == "police" and p["group"].startswith("arm") and p["decal"]:
                    p["decal"] = "front_back"   # согнутые руки-капсулы сбоку не совпадают с рисунком бока
                p["top"] = p["name"] == "head"
                p.pop("lines", None)
        c["decal"]["textures"] = {v: f"res://assets/art/characters/{name}_{v}_idle.svg" for v in ("front", "back", "side")}
        c["decal"].setdefault("erase", {})
        c["decal"].setdefault("caps", {})
    # Нос Илюши в фас (CHAR3D-02): нарисованный хобот (трубка 26 ед. по пути M200,190 C194,214 194,236 208,242
    # C222,248 234,236 230,222 в face_front) стирается капсулами по его оси — нос показывает объём, в 3/4 он один.
    # Повязка полицейского нарисована у локтя (P_BAND_PTS в сетке e03 → x 298–382, y 279–333 фаса; спина зеркально):
    # на рисунке она стёрта, повязка — объём на плече.
    characters["police"]["decal"]["erase"] = {"front": [[296, 276, 90, 60]], "back": [[14, 276, 90, 60]]}
    characters["ilyusha"]["decal"]["caps"] = {"front": [[200, 190, 196, 214, 15], [196, 214, 200, 236, 15],
                                                        [200, 236, 214, 244, 15], [214, 244, 230, 222, 15]]}
    data = {
        "version": 2,
        "source": "tools/generate_characters.py и SVG assets/art/characters (формы и палитры), tools/character_passports.py (CHAR3D-01/02)",
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
