#!/usr/bin/env python3
"""Рисунки персонажей ART-01: Илюша, Бабка, продавщица; EXT-01: полицейский, «военком»; PEOPLE-01: жители — SVG собственной работы.

Запуск: uv run tools/generate_characters.py
Пишет assets/art/characters/<имя>_<ракурс>_<кадр>.svg.

Манера по паспорту ART-01 (V01, V02 и кадры 01–10): чёрный контур от руки, плоская заливка
с одной светлой полосой, мелкие тонкие линии лица. Холст 400×600 условных единиц,
ноги стоят на y=590, ось персонажа x=200. Ракурсы: front (лицом к камере), back, side
(смотрит вправо; левый бок — зеркало в игре). Только стандартная библиотека Python.

Контур для игры (LOOK-01): все чернильные линии толще в GAME_LINE_K раз — с игровой камеры персонаж занимает
140–290 px по росту, и линия LINE 1,8 ед. выходила 0,35–0,95 px и пропадала. Трубки «чернила под цветом»
(пальцы, карандаш, лямки) сохраняют ширину цветной части, толще только их кайма. Для листа — --line-k 1:
  uv run tools/generate_characters.py --line-k 1 --out <каталог>
"""

from __future__ import annotations

import math
import re
import sys
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "assets" / "art" / "characters"
W, H = 400, 600
SCALE = 2  # пиксели текстуры на единицу холста
GAME_LINE_K = 2.0   # толщина чернил в игре к листу: 1,8 ед. → 3,6 ед. (LOOK-01; ≈0,7 % роста фигуры, как контур e03)
TUBE_MIN = 3.0      # чернильный штрих от этой ширины — внешняя часть «трубки» (за ним тот же путь цветом)

INK = "#141213"
LINE = 1.8   # внешний контур тонкий, как в роликах V01/V02: ≈0,013 ширины лица (решение владельца 28.10.2026)
THIN = 1.6   # детали лица и складки

# Илюша
SKIN, SKIN_HI, SKIN_LO, BLUSH = "#F4B3CD", "#FAD3E3", "#E296B6", "#EE8DA8"
TUFT, TUFT_LO = "#EBC458", "#CFA43A"
JACKET, JACKET_HI, JACKET_LO = "#A2F03A", "#C8FF78", "#7FCB22"
FUR = "#F6F3EA"
PANTS, PANTS_LO = "#2F8A36", "#226A29"
BOOT, SOLE = "#3A3436", "#1C1819"

# Бабка
B_SKIN, B_SKIN_HI, B_SKIN_LO = "#F6F2CC", "#FFFDE9", "#DCD6A2"
B_HAT, B_HAT_LO = "#97A052", "#7A8440"
B_DRESS, B_DRESS_HI, B_DRESS_LO = "#A3AD62", "#BCC57E", "#848E48"
LACE = "#FFFFFF"
B_SHOE = "#3A3330"

# Продавщица
V_SKIN, V_SKIN_HI, V_SKIN_LO = "#F1E4B0", "#FBF3D2", "#D8C98E"
V_SCARF, V_SCARF_LO = "#8C3B3B", "#6E2A2C"
V_KNIT, V_KNIT_LO = "#5B4737", "#46362A"
V_NECK = "#C9433A"


class Svg:
    def __init__(self, view_x: float = 0, view_w: float = W) -> None:
        self.view_x, self.view_w = view_x, view_w   # viewBox по x (ART-08: росгвардеец шире холста 400)
        self.parts: list[str] = []
        self.defs: list[str] = []
        self._clip = 0

    def add(self, s: str) -> None:
        self.parts.append(s)

    def path(self, d: str, fill: str = "none", stroke: str | None = INK, width: float = LINE,
             extra: str = "") -> None:
        st = f' stroke="{stroke}" stroke-width="{width}" stroke-linejoin="round" stroke-linecap="round"' if stroke else ""
        self.add(f'<path d="{d}" fill="{fill}"{st}{extra}/>')

    def ellipse(self, cx: float, cy: float, rx: float, ry: float, fill: str, stroke: str | None = INK,
                width: float = LINE, extra: str = "") -> None:
        st = f' stroke="{stroke}" stroke-width="{width}"' if stroke else ""
        self.add(f'<ellipse cx="{cx:.1f}" cy="{cy:.1f}" rx="{rx:.1f}" ry="{ry:.1f}" fill="{fill}"{st}{extra}/>')

    def shape(self, d: str, fill: str, hi: str | None = None, hi_d: str | None = None,
              lo: str | None = None, lo_d: str | None = None, width: float = LINE) -> None:
        """Залитая форма с бликом и тенью внутри контура, затем контур поверх."""
        self._clip += 1
        cid = f"c{self._clip}"
        self.defs.append(f'<clipPath id="{cid}"><path d="{d}"/></clipPath>')
        self.path(d, fill, None)
        if lo and lo_d:
            self.add(f'<g clip-path="url(#{cid})"><path d="{lo_d}" fill="{lo}"/></g>')
        if hi and hi_d:
            self.add(f'<g clip-path="url(#{cid})"><path d="{hi_d}" fill="{hi}"/></g>')
        self.path(d, "none", INK, width)

    def group(self, transform: str) -> "Group":
        return Group(self, transform)

    def text(self) -> str:
        defs = f"<defs>{''.join(self.defs)}</defs>" if self.defs else ""
        parts = thicken(self.parts, LINE_K)
        vx, vw = self.view_x, self.view_w
        return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{vw * SCALE:g}" height="{H * SCALE}" '
                f'viewBox="{vx:g} 0 {vw:g} {H}">{defs}{"".join(parts)}</svg>\n')


LINE_K = GAME_LINE_K
_INK_W = re.compile(r'stroke="' + INK + r'" stroke-width="([0-9.]+)"')
_PATH = re.compile(r'<path d="([^"]*)" fill="none" stroke="([^"]+)" stroke-width="([0-9.]+)"')


def _fmt(w: float) -> str:
    return f"{w:.3f}".rstrip("0").rstrip(".")


def thicken(parts: list[str], k: float) -> list[str]:
    """Чернила толще в k раз: тонкие штрихи INK (< TUBE_MIN) — умножением; «трубка» (INK ≥ TUBE_MIN и сразу за ней
    тот же путь цветным штрихом уже) — цветная часть прежняя, кайма (внешняя − цветная)/2 в k раз шире."""
    if k == 1.0:
        return parts
    out = list(parts)
    i = 0
    while i < len(out):
        outer = _PATH.match(out[i])
        if outer and outer.group(2) == INK and float(outer.group(3)) >= TUBE_MIN and i + 1 < len(out):
            inner = _PATH.match(out[i + 1])
            w_out = float(outer.group(3))
            if inner and inner.group(1) == outer.group(1) and inner.group(2) != INK and float(inner.group(3)) < w_out:
                w_in = float(inner.group(3))
                rim = (w_out - w_in) / 2.0
                out[i] = out[i].replace(f'stroke-width="{outer.group(3)}"', f'stroke-width="{_fmt(w_in + 2.0 * rim * k)}"', 1)
                i += 2
                continue
        m = _INK_W.search(out[i])
        if m and float(m.group(1)) < TUBE_MIN:
            out[i] = _INK_W.sub(lambda g: f'stroke="{INK}" stroke-width="{_fmt(float(g.group(1)) * k)}"'
                                if float(g.group(1)) < TUBE_MIN else g.group(0), out[i])
        i += 1
    return out


class Group:
    def __init__(self, svg: Svg, transform: str) -> None:
        self.svg, self.transform = svg, transform

    def __enter__(self) -> Svg:
        self.svg.add(f'<g transform="{self.transform}">')
        return self.svg

    def __exit__(self, *_exc) -> None:
        self.svg.add("</g>")


def scallops(svg: Svg, points: list[tuple[float, float]], r: float, fill: str) -> None:
    """Кружевная оборка или мех: цепочка кругов с общим внешним контуром."""
    for x, y in points:
        svg.ellipse(x, y, r, r, fill, INK, LINE * 0.8)
    for x, y in points:
        svg.ellipse(x, y, r - LINE * 0.45, r - LINE * 0.45, fill, None)


def frill_band(svg: Svg, cx: float, cy: float, rx: float, ry: float, a0: float, a1: float, n: int,
               depth: float = 12.0, width: float = LINE * 0.7) -> None:
    """Кружевная лента: ровный верхний край по дуге, нижний — фестонами (оборка шапки Бабки)."""
    top = arc_points(cx, cy - depth, rx, ry, a0, a1, n)
    low = arc_points(cx, cy, rx, ry, a0, a1, n)
    d = f"M{top[0][0]:.1f},{top[0][1]:.1f} "
    d += " ".join(f"L{x:.1f},{y:.1f}" for x, y in top[1:])
    d += f" L{low[-1][0]:.1f},{low[-1][1]:.1f}"
    for i in range(n - 1, 0, -1):
        (x1, y1), (x0, y0) = low[i], low[i - 1]
        mx, my = (x0 + x1) / 2, (y0 + y1) / 2 + depth * 0.9
        d += f" Q{mx:.1f},{my:.1f} {x0:.1f},{y0:.1f}"
    d += " Z"
    svg.path(d, LACE, INK, width)


def arc_points(cx: float, cy: float, rx: float, ry: float, a0: float, a1: float, n: int) -> list[tuple[float, float]]:
    return [(cx + rx * math.cos(a0 + (a1 - a0) * i / (n - 1)), cy + ry * math.sin(a0 + (a1 - a0) * i / (n - 1)))
            for i in range(n)]


def mirror_d(d: str) -> str:
    """Отразить путь из абсолютных команд M/C/L/Q относительно оси x=200."""
    out, tokens = [], re.findall(r"[A-Za-z]|-?\d+(?:\.\d+)?", d)
    i = 0
    while i < len(tokens):
        t = tokens[i]
        if t.isalpha():
            out.append(t)
            i += 1
            continue
        x, y = float(tokens[i]), float(tokens[i + 1])
        out.append(f"{400 - x:.1f},{y:.1f}")
        i += 2
    return " ".join(out)


# ---------------------------------------------------------------- Илюша

HEAD_FRONT = "M200,86 C258,86 278,150 294,206 C308,264 262,302 200,302 C138,302 92,264 106,206 C122,150 142,86 200,86 Z"
HEAD_FRONT_HI = "M146,104 C114,170 104,250 146,296 L96,306 L90,96 Z"
HEAD_FRONT_LO = "M266,136 C300,210 290,276 236,306 L312,306 L312,120 Z"


def tuft(svg: Svg, cx: float, top: float, w: float = 1.0) -> None:
    d = (f"M{cx - 44 * w:.1f},{top + 62} C{cx - 56 * w:.1f},{top + 44} {cx - 40 * w:.1f},{top + 26} {cx - 24 * w:.1f},{top + 30} "
         f"C{cx - 22 * w:.1f},{top + 10} {cx - 2 * w:.1f},{top - 2} {cx + 10 * w:.1f},{top + 10} "
         f"C{cx + 28 * w:.1f},{top + 6} {cx + 44 * w:.1f},{top + 22} {cx + 38 * w:.1f},{top + 36} "
         f"C{cx + 56 * w:.1f},{top + 42} {cx + 54 * w:.1f},{top + 62} {cx + 40 * w:.1f},{top + 64} "
         f"C{cx + 10 * w:.1f},{top + 70} {cx - 20 * w:.1f},{top + 70} {cx - 44 * w:.1f},{top + 62} Z")
    lo = f"M{cx + 10 * w:.1f},{top + 30} C{cx + 40 * w:.1f},{top + 30} {cx + 60 * w:.1f},{top + 50} {cx + 50 * w:.1f},{top + 75} L{cx - 50 * w:.1f},{top + 75} C{cx - 20 * w:.1f},{top + 66} {cx},{top + 50} {cx + 10 * w:.1f},{top + 30} Z"
    svg.shape(d, TUFT, lo=TUFT_LO, lo_d=lo)
    for dx, dy, s in ((-22, 44, 1.0), (6, 38, 1.0), (-6, 22, 0.7), (24, 52, 0.8)):
        x, y = cx + dx * w, top + dy
        svg.path(f"M{x - 12 * s * w:.1f},{y:.1f} Q{x:.1f},{y - 9 * s:.1f} {x + 12 * s * w:.1f},{y:.1f}", width=THIN)


def fur_collar_front(svg: Svg, cy: float = 286) -> None:
    pts = arc_points(200, cy - 18, 92, 26, math.radians(200), math.radians(-20), 11)
    pts += arc_points(200, cy - 8, 88, 22, math.radians(160), math.radians(20), 9)
    scallops(svg, pts, 17, FUR)


def jacket_front(svg: Svg, arm_l: float, arm_r: float, back: bool) -> None:
    body = "M95,300 C68,332 72,420 102,442 L298,442 C328,420 332,332 305,300 C270,282 130,282 95,300 Z"
    body_hi = "M100,300 C80,340 84,410 110,440 L140,440 C118,400 116,340 132,296 Z"
    body_lo = "M300,300 C324,340 320,410 292,442 L330,442 L330,290 Z"
    for side, swing in ((-1, arm_l), (1, arm_r)):
        d = "M112,304 C78,306 56,342 58,402 C60,424 88,430 96,414 C100,376 106,342 118,318 Z"
        if side > 0:
            d = mirror_d(d)
        with svg.group(f"translate(0,{swing:.1f})"):
            svg.shape(d, JACKET, lo=JACKET_LO, lo_d="M0,380 L400,380 L400,440 L0,440 Z")
            x = 76 if side < 0 else 324
            svg.path(f"M{x - 18},{372} Q{x},{380} {x + 18},{372}", width=THIN)
    svg.shape(body, JACKET, hi=JACKET_HI, hi_d=body_hi, lo=JACKET_LO, lo_d=body_lo)
    for y in (344, 392):
        svg.path(f"M84,{y} Q200,{y + 16} 316,{y}", width=THIN)
    if not back:
        svg.path("M200,300 L200,440", width=THIN)
    else:
        hood = "M136,298 C134,268 266,268 264,298 C266,334 236,350 200,350 C164,350 134,334 136,298 Z"
        svg.shape(hood, JACKET, lo=JACKET_LO, lo_d="M136,326 C170,344 230,344 264,326 L264,360 L136,360 Z")
        svg.path("M158,300 Q200,326 242,300", width=THIN)


def hands_front(svg: Svg, arm_l: float, arm_r: float) -> None:
    for x, swing in ((74, arm_l), (326, arm_r)):
        y = 428 + swing
        svg.shape(f"M{x - 20},{y - 18} C{x - 26},{y + 4} {x - 16},{y + 26} {x},{y + 26} C{x + 16},{y + 26} {x + 24},{y + 4} {x + 18},{y - 18} Z",
                  SKIN, lo=SKIN_LO, lo_d=f"M{x + 4},{y - 20} L{x + 30},{y - 20} L{x + 30},{y + 30} L{x + 4},{y + 30} Z")
        svg.path(f"M{x - 6},{y + 8} Q{x - 2},{y + 18} {x + 4},{y + 20}", width=THIN * 0.8)


def legs_front(svg: Svg, lift_l: float, lift_r: float, back: bool) -> None:
    for xc, lift in ((152, lift_l), (248, lift_r)):
        bottom = 556 - lift
        leg = (f"M{xc - 46},436 L{xc + 46},436 C{xc + 48},480 {xc + 46},520 {xc + 42},{bottom} "
               f"L{xc - 42},{bottom} C{xc - 46},520 {xc - 48},480 {xc - 46},436 Z")
        svg.shape(leg, PANTS, lo=PANTS_LO, lo_d=f"M{xc + 18},430 L{xc + 60},430 L{xc + 60},{bottom + 10} L{xc + 18},{bottom + 10} Z")
        by = 568 - lift
        boot = (f"M{xc - 46},{by - 14} C{xc - 48},{by + 16} {xc - 30},{by + 22} {xc},{by + 22} "
                f"C{xc + 30},{by + 22} {xc + 48},{by + 16} {xc + 46},{by - 14} C{xc + 20},{by - 24} {xc - 20},{by - 24} {xc - 46},{by - 14} Z")
        svg.shape(boot, BOOT, lo=SOLE, lo_d=f"M{xc - 60},{by + 10} L{xc + 60},{by + 10} L{xc + 60},{by + 30} L{xc - 60},{by + 30} Z")
        if not back:
            svg.path(f"M{xc - 20},{by - 6} L{xc + 20},{by - 6}", width=THIN * 0.8)
    svg.path("M114,436 L286,436 L286,462 L114,462 Z", PANTS, None)
    svg.path("M200,452 L200,490", width=THIN)


def face_front(svg: Svg) -> None:
    for x, s in ((162, -1), (238, 1)):
        svg.ellipse(x, 206, 17, 13, SKIN_LO, None)
        svg.ellipse(x, 206, 9, 5, "#FFFFFF", INK, THIN * 0.8)
        svg.ellipse(x + 2 * s, 207, 3.2, 3.2, INK, None)
        svg.path(f"M{x - 13},{201} Q{x},{196} {x + 13},{201}", width=THIN)
        svg.path(f"M{x - 18},{176} Q{x},{166} {x + 18},{178}", width=THIN)
        svg.ellipse(x + 24 * s, 236, 15, 12, BLUSH, None, extra=' opacity="0.75"')
    # Нос-хобот спереди: толстая трубка от переносицы вниз с загибом кончика вверх-вбок (V02 0:09, 0:25).
    trunk = "M200,190 C194,214 194,236 208,242 C222,248 234,236 230,222"
    svg.path(trunk, "none", INK, 26)
    svg.path(trunk, "none", SKIN, 26 - LINE * 1.2)
    svg.path("M196,196 C192,216 194,232 204,238", "none", SKIN_HI, 5)
    svg.ellipse(229, 222, 3.2, 3.2, INK, None)
    svg.path("M168,258 C182,250 218,250 234,258 C220,266 182,266 168,258 Z", "#FFFFFF", INK, THIN)
    for x in (180, 190, 200, 210, 220):
        svg.path(f"M{x},253 L{x},262", width=THIN * 0.6)
    svg.path("M178,276 Q200,290 222,276", width=THIN)
    for x, s in ((104, 1), (296, -1)):
        svg.path(f"M{x},{196} C{x - 14 * s},{198} {x - 14 * s},{226} {x},{228}", width=THIN)


def ilyusha(view: str, frame: int) -> str:
    """frame -1 — стойка, 0..3 — цикл ходьбы."""
    svg = Svg()
    walking = frame >= 0
    phase = frame * math.pi / 2 if walking else 0.0
    bob = -6.0 if walking and frame % 2 == 1 else 0.0
    if view in ("front", "back"):
        lift_l = max(0.0, math.sin(phase)) * 16 if walking else 0.0
        lift_r = max(0.0, -math.sin(phase)) * 16 if walking else 0.0
        arm_l = math.sin(phase) * 6 if walking else 0.0
        arm_r = -arm_l
        back = view == "back"
        legs_front(svg, lift_l, lift_r, back)
        with svg.group(f"translate(0,{bob})"):
            jacket_front(svg, arm_l, arm_r, back)
            if back:
                svg.shape(HEAD_FRONT, SKIN, hi=SKIN_HI, hi_d=HEAD_FRONT_HI, lo=SKIN_LO, lo_d=HEAD_FRONT_LO)
                svg.path("M170,262 Q200,272 230,262", width=THIN)
                for x, s in ((106, -1), (294, 1)):
                    svg.path(f"M{x},196 C{x + 16 * s},{198} {x + 16 * s},{226} {x},{228}", SKIN, INK, THIN)
            else:
                svg.shape(HEAD_FRONT, SKIN, hi=SKIN_HI, hi_d=HEAD_FRONT_HI, lo=SKIN_LO, lo_d=HEAD_FRONT_LO)
                face_front(svg)
            fur_collar_front(svg)
            tuft(svg, 200, 44)
            hands_front(svg, arm_l, arm_r)
    else:
        ilyusha_side(svg, phase if walking else None, bob)
    return svg.text()


def ilyusha_side(svg: Svg, phase: float | None, bob: float) -> None:
    stride = math.sin(phase) * 20 if phase is not None else 0.0
    arm = -math.sin(phase) * 14 if phase is not None else 0.0
    lift = abs(math.cos(phase)) * 0 if phase is not None else 0.0

    def leg(angle: float, fill: str, lo: str) -> None:
        with svg.group(f"rotate({angle:.1f} 205 448)"):
            svg.shape("M168,440 L244,440 C246,490 242,530 238,552 L176,552 C170,530 166,490 168,440 Z", fill,
                      lo=lo, lo_d="M222,430 L260,430 L260,560 L222,560 Z")
            boot = "M168,546 C166,574 176,584 196,584 L262,584 C282,584 286,562 268,552 C250,546 236,542 232,540 L172,540 Z"
            svg.shape(boot, BOOT, lo=SOLE, lo_d="M150,574 L300,574 L300,600 L150,600 Z")

    leg(-stride, PANTS_LO, "#1B5521")  # дальняя нога
    leg(stride, PANTS, PANTS_LO)
    svg.path("M160,436 L250,436 L250,466 L160,466 Z", PANTS, None)
    with svg.group(f"translate(0,{bob - lift})"):
        body = "M126,292 C88,306 82,372 96,442 L298,442 C316,400 314,326 280,292 C246,278 160,278 126,292 Z"
        svg.shape(body, JACKET, hi=JACKET_HI, hi_d="M250,296 C284,330 290,400 276,442 L310,442 L310,290 Z",
                  lo=JACKET_LO, lo_d="M100,300 L150,300 C130,340 128,400 140,442 L100,442 Z")
        for y in (344, 392):
            svg.path(f"M106,{y} Q200,{y + 14} 296,{y}", width=THIN)
        hood = "M114,298 C84,302 80,348 104,360 C126,366 138,332 136,302 Z"
        svg.shape(hood, JACKET, lo=JACKET_LO, lo_d="M90,330 L160,330 L160,370 L90,370 Z")
        # голова в профиль, лицом вправо
        head = ("M140,108 C160,82 236,80 254,114 C268,140 268,172 276,198 C288,234 280,278 244,298 "
                "C210,310 150,308 126,288 C102,266 108,212 114,180 C118,150 128,124 140,108 Z")
        svg.shape(head, SKIN, hi=SKIN_HI, hi_d="M236,100 C262,140 270,220 262,290 L300,300 L300,90 Z",
                  lo=SKIN_LO, lo_d="M110,120 L148,120 C134,170 134,240 156,300 L110,300 Z")
        svg.path("M156,186 C140,188 140,220 156,222", SKIN, INK, THIN)
        svg.ellipse(238, 196, 14, 11, SKIN_LO, None)
        svg.ellipse(240, 196, 7, 4.5, "#FFFFFF", INK, THIN * 0.8)
        svg.ellipse(243, 197, 3, 3, INK, None)
        svg.path("M228,191 Q240,186 252,192", width=THIN)
        svg.path("M222,168 Q238,160 254,170", width=THIN)
        svg.ellipse(218, 232, 15, 12, BLUSH, None, extra=' opacity="0.75"')
        nose = ("M264,200 C292,194 320,202 334,192 C350,180 350,152 336,142 C324,136 312,144 318,156 "
                "C324,166 316,174 302,174 C286,174 274,172 262,176 Z")
        svg.shape(nose, SKIN, hi=SKIN_HI, hi_d="M250,186 C280,180 300,184 316,180 L320,170 L250,170 Z", width=THIN * 1.4)
        svg.path("M236,252 C246,248 260,246 268,244 C266,256 248,262 236,252 Z", "#FFFFFF", INK, THIN)
        svg.path("M248,248 L248,256 M257,246 L257,254", width=THIN * 0.6)
        svg.path("M226,276 Q246,286 262,268", width=THIN)
        pts = arc_points(205, 282, 70, 14, math.radians(185), math.radians(-5), 9)
        pts += arc_points(205, 296, 64, 10, math.radians(170), math.radians(10), 7)
        scallops(svg, pts, 16, FUR)
        tuft(svg, 196, 46, 0.95)
        with svg.group(f"rotate({arm:.1f} 196 306)"):
            sleeve = "M176,300 C156,306 154,362 162,404 C170,420 206,420 212,404 C218,362 216,320 208,300 Z"
            svg.shape(sleeve, JACKET, hi=JACKET_HI, hi_d="M200,300 C214,330 214,380 208,410 L230,410 L230,300 Z",
                      lo=JACKET_LO, lo_d="M150,380 L230,380 L230,430 L150,430 Z")
            svg.path("M164,372 Q186,380 210,372", width=THIN)
            svg.shape("M168,410 C162,432 172,450 188,450 C204,450 212,432 206,410 Z", SKIN,
                      lo=SKIN_LO, lo_d="M150,410 L180,410 L180,460 L150,460 Z")


# ---------------------------------------------------------------- Бабка и продавщица
# Пропорции — по независимой сверке с V01/V02 (ART-01, раздел «Сверка по роликам»): голова ≈0,32 роста,
# лицо — высокая груша с брылями (рот на 0,43 высоты лица), низкий мягкий чепец, шеи нет,
# тело-бочонок в 2,4–3 ширины лица, руки входят в массу тела, свет — мягкие пятна.

FACE = 1.6  # тонкие черты лица у старших персонажей

B_SKIN, B_SKIN_LO = "#FFFDE2", "#F1EECB"
B_NAPE = "#EBDC9E"
B_HAT, B_HAT_LIGHT = "#A9AD6E", "#C4C68C"
B_DRESS, B_DRESS_LIGHT, B_DRESS_DARK = "#B6BA78", "#CDCF92", "#9A9E66"
B_STOCK, B_BOOT = "#C2BF96", "#3A332B"


def soft_spot(svg: Svg, clip_d: str, cx: float, cy: float, rx: float, ry: float, color: str,
              opacity: float = 0.85, core: float = 0.0) -> None:
    """Мягкое пятно света или тени с размытым краем внутри формы (манера V01: пятна, не полосы)."""
    svg._clip += 1
    gid, cid = f"g{svg._clip}", f"s{svg._clip}"
    svg.defs.append(f'<radialGradient id="{gid}"><stop offset="0" stop-color="{color}" stop-opacity="{opacity}"/>'
                    f'<stop offset="{core}" stop-color="{color}" stop-opacity="{opacity}"/>'
                    f'<stop offset="1" stop-color="{color}" stop-opacity="0"/></radialGradient>')
    svg.defs.append(f'<clipPath id="{cid}"><path d="{clip_d}"/></clipPath>')
    svg.add(f'<g clip-path="url(#{cid})"><ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}" fill="url(#{gid})"/></g>')


def soft_shape(svg: Svg, d: str, fill: str, spots: list[tuple],
               width: float = LINE) -> None:
    svg.path(d, fill, None)
    for spot in spots:
        cx, cy, rx, ry, color = spot[:5]
        soft_spot(svg, d, cx, cy, rx, ry, color, core=spot[5] if len(spot) > 5 else 0.0)
    svg.path(d, "none", INK, width)


def jabot(svg: Svg, cx: float, top: float, bottom: float, half: float, n: int, depth: float,
          width: float = LINE * 0.7) -> None:
    """Воротник-жабо одной лентой: боковины поднимаются за брылями, наружный край — фестоны."""
    outer = []
    for i in range(n + 1):
        t = math.pi - math.pi * i / n
        # Концы ленты стянуты внутрь на 20 %: прячутся за брылями, без чёрных «крючков» (сверка v5).
        outer.append((cx + half * math.cos(t) * (0.8 + 0.2 * math.sin(t)), top + (bottom - top) * math.sin(t)))
    d = f"M{outer[0][0]:.1f},{outer[0][1]:.1f}"
    for (x0, y0), (x1, y1) in zip(outer, outer[1:]):
        mx, my = (x0 + x1) / 2, (y0 + y1) / 2
        nx, ny = mx - cx, my - top
        k = depth / max(1.0, math.hypot(nx, ny))
        d += f" Q{mx + nx * k:.1f},{my + ny * k:.1f} {x1:.1f},{y1:.1f}"
    inner = half - depth * 1.2
    d += f" C{cx + inner:.1f},{bottom - 8:.1f} {cx - inner:.1f},{bottom - 8:.1f} {outer[0][0]:.1f},{outer[0][1]:.1f} Z"
    svg.path(d, LACE, INK, width)


def cuff_and_hand(svg: Svg, x: float, y: float, side: int, fingers: bool = True) -> None:
    """Кружевная манжета и пухлая кисть с четырьмя длинными пальцами (V01 0:25, 0:41)."""
    svg.ellipse(x + side * 2, y + 26, 22, 18, B_SKIN, INK, LINE * 0.8)
    if fingers:
        for k in range(4):
            fx = x + side * 2 - 13 + k * 8.7
            tip = y + 66 - abs(k - 1.5) * 5
            svg.path(f"M{fx:.1f},{y + 32} L{fx + side * 2:.1f},{tip:.1f}", "none", INK, 10)
            svg.path(f"M{fx:.1f},{y + 32} L{fx + side * 2:.1f},{tip:.1f}", "none", B_SKIN, 10 - LINE * 0.6)
            svg.ellipse(fx + side * 2, tip - 4, 2.0, 2.6, B_SKIN_LO, INK, 1.2)
        svg.ellipse(x + side * 2, y + 26, 20, 15, B_SKIN, None)
        svg.path(f"M{x + side * 2 - 14:.1f},{y + 30} Q{x + side * 2:.1f},{y + 36} {x + side * 2 + 14:.1f},{y + 30}", width=1.6)
    frill_band(svg, x, y + 8, 24, 3, math.radians(190), math.radians(-10), 6, 10)


def boots(svg: Svg, xs: list[float], spread: float) -> None:
    for x, s in zip(xs, (-1, 1)):
        svg.path(f"M{x - 12},548 L{x + 12},548 L{x + 12},570 L{x - 12},570 Z", B_STOCK, INK, LINE * 0.6)
        with svg.group(f"rotate({s * spread:.1f} {x} 580)"):
            svg.path(f"M{x - 20},566 C{x - 22},586 {x - 14},592 {x},592 C{x + 16},592 {x + 24},586 {x + 20},566 "
                     f"C{x + 8},560 {x - 8},560 {x - 20},566 Z", B_BOOT, INK, LINE * 0.8)
            svg.path(f"M{x - 6},568 L{x + 6},572 M{x + 6},568 L{x - 6},572", width=1.6)


def babka_front_face(svg: Svg) -> None:
    for x in (180, 220):
        svg.path(f"M{x - 7},110 Q{x},104 {x + 7},110 Q{x},114 {x - 7},110 Z", "#FFFFFF", INK, FACE * 0.8)
        svg.ellipse(x, 110, 2.2, 2.2, INK, None)
        svg.path(f"M{x - 9},104 Q{x},99 {x + 9},104", width=FACE)
        svg.path(f"M{x - 7},117 Q{x},121 {x + 7},117", width=FACE * 0.7)
    svg.path("M194,106 C193,120 194,128 200,128 C206,128 207,120 206,106", width=FACE)
    svg.path("M187,113 C180,128 176,146 174,160 M213,113 C220,128 224,146 226,160", width=FACE)
    svg.path("M188,134 L212,134 M195,140 L205,140", width=FACE)
    svg.path("M184,156 Q200,167 216,156", width=FACE)
    svg.path("M156,190 Q168,200 182,197 M244,190 Q232,200 218,197", width=FACE * 0.9)
    svg.path("M170,176 Q178,182 186,180 M230,176 Q222,182 214,180", width=FACE * 0.7)


FACE_PEAR = (  # высота к ширине ≈1,12, как в V01 0:12, 0:39 и V02 0:37 (решение владельца 28.10)
             "M154.7,104 C173.6,88 226.4,88 245.3,104 C252.7,116 255.2,128 256.0,139 C263.4,160 270.0,178 270.0,195 "
             "C270.0,214 261.0,230 241.2,238 C228.0,243 214.8,245 200.0,245 C185.2,245 172.0,243 158.8,238 "
             "C139.0,230 130.0,214 130.0,195 C130.0,178 136.6,160 144.0,139 C144.8,128 147.3,116 154.7,104 Z")
BARREL = ("M105,235 C80,250 55,270 45,300 C30,335 25,370 25,400 C25,460 35,520 45,568 "
          "C140,580 260,580 355,568 C365,520 375,460 375,400 C375,370 370,335 355,300 C345,270 320,250 295,235 "
          "C260,226 140,226 105,235 Z")
BACK_BARREL = ("M120,200 C80,215 55,265 45,300 C30,335 25,370 25,400 C25,460 35,520 45,568 "
               "C140,580 260,580 355,568 C365,520 375,460 375,400 C375,370 370,335 355,300 C345,265 320,215 280,200 "
               "C240,192 160,192 120,200 Z")
CAP_FRONT = ("M139.8,170 C136.4,140 139.8,100 143.2,76 C144.1,64 150.1,58 160.4,57 C182.8,53 217.2,53 239.6,57 "
             "C249.9,58 255.9,64 256.8,76 C260.2,100 263.6,140 260.2,170 Z")


def frill_up(svg: Svg, p0: tuple[float, float], p1: tuple[float, float], h: float, n: int) -> None:
    """Белая кромка чепца: ровный нижний край p0→p1, верхний — n фестонов бугорками вверх (V01 0:12, 0:21)."""
    dx, dy = p1[0] - p0[0], p1[1] - p0[1]
    length = math.hypot(dx, dy)
    nx, ny = dy / length, -dx / length  # нормаль «вверх» для ленты слева направо
    if ny > 0:
        nx, ny = -nx, -ny
    top = [(p0[0] + dx * i / n + nx * h, p0[1] + dy * i / n + ny * h) for i in range(n + 1)]
    d = f"M{p0[0]:.1f},{p0[1]:.1f} L{top[0][0]:.1f},{top[0][1]:.1f}"
    for (x0, y0), (x1, y1) in zip(top, top[1:]):
        d += f" Q{(x0 + x1) / 2 + nx * h * 0.7:.1f},{(y0 + y1) / 2 + ny * h * 0.7:.1f} {x1:.1f},{y1:.1f}"
    d += f" L{p1[0]:.1f},{p1[1]:.1f} Z"
    svg.path(d, LACE, INK, FACE)


def babka_hand(svg: Svg, x: float, y: float, side: int, nails: bool = True) -> None:
    """Кисть висит у бока: пухлая ладонь, четыре изогнутых разведённых пальца, кружевная манжета."""
    for k in range(4):
        fx = x - 18 + k * 12
        spread = (k - 1.5) * 3.5
        tip = y + 50 - abs(k - 1.5) * 4
        d = f"M{fx:.1f},{y + 10} Q{fx + spread + side * 4:.1f},{y + 32} {fx + spread * 1.6:.1f},{tip:.1f}"
        svg.path(d, "none", INK, 14)
        svg.path(d, "none", B_SKIN, 14 - LINE * 1.0)
        if nails:
            svg.ellipse(fx + spread * 1.6, tip - 3, 2.6, 3.2, B_SKIN_LO, INK, 1.2)
    svg.ellipse(x, y, 28, 20, B_SKIN, INK, LINE * 0.8)
    svg.ellipse(x, y + 2, 26, 17, B_SKIN, None)
    soft_spot(svg, f"M{x - 28},{y - 20} L{x + 28},{y - 20} L{x + 28},{y + 20} L{x - 28},{y + 20} Z",
              x - side * 9, y - 5, 16, 11, "#FFFFFF", 0.7)
    frill_band(svg, x, y - 20, 26, 3, math.radians(190), math.radians(-10), 6, 10)


def babka_feet(svg: Svg, xs: tuple[float, float] = (165, 235)) -> None:
    for x, s in zip(xs, (-1, 1)):
        svg.path(f"M{x - 15},540 L{x + 15},540 L{x + 15},574 L{x - 15},574 Z", B_STOCK, INK, LINE * 0.6)
        with svg.group(f"rotate({s * 12} {x} 580)"):
            svg.path(f"M{x - 20},572 C{x - 22},588 {x - 12},592 {x},592 C{x + 14},592 {x + 22},588 {x + 20},572 "
                     f"C{x + 8},566 {x - 8},566 {x - 20},572 Z", B_BOOT, INK, LINE * 0.8)
            svg.path(f"M{x - 6},574 L{x + 6},578 M{x + 6},574 L{x - 6},578", width=1.6)


def babka(view: str) -> str:
    svg = Svg()
    if view == "front":
        babka_feet(svg)
        soft_shape(svg, BARREL, B_DRESS, [(200, 385, 105, 75, B_DRESS_LIGHT, 0.6), (40, 420, 50, 160, B_DRESS_DARK),
                                          (360, 420, 50, 160, B_DRESS_DARK)])
        for i in range(12):
            y = 262 + i * 24
            svg.ellipse(200, y, 2.6, 3.2, INK, None)
        svg.path("M70,290 C62,330 60,360 62,385 M330,290 C338,330 340,360 338,385", width=FACE * 1.2)
        babka_hand(svg, 58, 408, -1)
        babka_hand(svg, 342, 408, 1)
        jabot(svg, 200, 200, 266, 84, 13, 9, FACE)  # белого под подбородком ≈0,11 высоты лица (сверка v6)
        with svg.group("rotate(-4 200 120)"):
            soft_shape(svg, CAP_FRONT, B_HAT, [(176, 78, 50, 26, B_HAT_LIGHT)], LINE * 0.7)
        for x, s in ((136, -1), (264, 1)):
            svg.path(f"M{x},136 C{x + 6 * s},136 {x + 6 * s},156 {x},156 Z", B_SKIN, INK, FACE)
        soft_shape(svg, FACE_PEAR, B_SKIN, [(176, 150, 50, 70, "#FFFFFF"), (252, 205, 34, 46, B_SKIN_LO),
                                            (148, 205, 28, 40, B_SKIN_LO)])
        with svg.group("rotate(-4 200 120)"):
            # Кромка чепца — тонкая дуга мелких круглых фестонов по верху лица (сверка v4: «корона» убрана).
            # Одна лента: низ по дуге верха лица, верх — 6 скруглённых фестонов (не отдельные кружки-бусы).
            arc = [(160 + 80 * i / 6, 101 - 10 * math.sin(math.pi * i / 6)) for i in range(7)]
            d = f"M{arc[0][0]:.1f},{arc[0][1] + 4:.1f} L{arc[0][0]:.1f},{arc[0][1] - 3:.1f}"
            for (x0, y0), (x1, y1) in zip(arc, arc[1:]):
                d += f" C{x0 + 1:.1f},{y0 - 13:.1f} {x1 - 1:.1f},{y1 - 13:.1f} {x1:.1f},{y1 - 3:.1f}"
            d += f" L{arc[-1][0]:.1f},{arc[-1][1] + 4:.1f}"
            for x, y in reversed(arc[:-1]):
                d += f" L{x:.1f},{y + 4:.1f}"
            svg.path(d + " Z", LACE, INK, FACE)
        for x in (176, 224):
            svg.path(f"M{x - 6},146 Q{x},142 {x + 6},146 Q{x},150 {x - 6},146 Z", "#FFFFFF", INK, FACE * 0.8)
            svg.ellipse(x + 1.5, 146, 2.0, 2.0, INK, None)
            svg.path(f"M{x - 6},152 Q{x},155 {x + 6},152", width=FACE * 0.7)
        # Бровей нет: в V01 0:12, 0:42 и V02 0:37 их нет, лицо — по роликам (решение владельца 28.10).
        svg.path("M194,137 C193,150 194,154 200,154 C206,154 207,150 206,137", width=FACE)
        svg.path("M190,150 C184,166 180,180 178,194 M210,150 C216,166 220,180 222,194", width=FACE)
        # Открытый рот с рядом верхних зубов, ≈0,23 ширины лица (концепты 02, 10; V01 0:19, 0:40).
        # Тёмный открытый рот, уголки вниз, узкая полоса верхних зубов (концепты 02, 09, 10).
        # Рот — узкая тёмная щель с уголками вниз, как в V01 0:42 и V02 0:37 (лицо по роликам, решение владельца).
        svg.path("M187,160 Q200,157 213,160 L211,165 Q200,163 189,165 Z", INK, INK, FACE * 0.8)
        svg.path("M184,206 Q200,212 216,206", width=FACE)
        svg.path("M152,204 Q164,214 176,208 M248,204 Q236,214 224,208", width=FACE * 0.9)
        svg.path("M180,224 Q200,230 220,224", width=FACE * 0.8)
    elif view == "back":
        babka_feet(svg)
        soft_shape(svg, BACK_BARREL, B_DRESS, [(200, 360, 140, 120, B_DRESS_LIGHT)])
        svg.path("M70,290 C62,330 60,360 62,385 M330,290 C338,330 340,360 338,385", width=FACE * 1.2)
        svg.path("M150,470 Q200,482 250,470", width=FACE * 0.8)
        babka_hand(svg, 58, 408, -1, nails=False)
        babka_hand(svg, 342, 408, 1, nails=False)
        svg.path("M146,166 C146,186 156,202 200,204 C244,202 254,186 254,166 Z", B_NAPE, INK, LINE * 0.8)
        svg.path("M176,194 Q200,200 224,194", width=FACE * 0.7)
        for x, s in ((139, -1), (261, 1)):
            svg.path(f"M{x},150 C{x + 12 * s},150 {x + 12 * s},170 {x},170 Z", B_SKIN, INK, FACE)
        cap = CAP_FRONT.replace(" Z", " C240,178 160,178 130,170 Z")
        soft_shape(svg, cap, B_HAT, [(176, 90, 60, 40, B_HAT_LIGHT)], LINE * 0.7)
    else:  # side, лицом вправо
        svg.path("M200,540 L230,540 L230,574 L200,574 Z", B_STOCK, INK, LINE * 0.6)
        svg.path("M196,572 C194,590 204,592 220,592 L250,592 C262,592 264,580 252,574 C240,568 226,568 220,566 Z",
                 B_BOOT, INK, LINE * 0.8)
        body = ("M150,245 C120,252 98,275 90,310 C82,360 84,460 95,550 C170,562 250,562 315,550 "
                "C322,500 330,450 330,400 C330,340 315,290 290,262 C280,252 268,246 255,245 Z")
        soft_shape(svg, body, B_DRESS, [(270, 400, 80, 110, B_DRESS_LIGHT), (100, 400, 40, 160, B_DRESS_DARK)])
        for i in range(12):
            y = 262 + i * 24
            x = 290 + 36 * math.sin(min(1.0, (y - 262) / 276) * math.pi * 0.95)
            svg.ellipse(x - 4, y, 2.4, 3.0, INK, None)
        svg.path("M200,262 C186,310 186,350 200,385", width=FACE * 1.2)
        babka_hand(svg, 210, 408, 1)
        frill_band(svg, 215, 252, 66, 6, math.radians(186), math.radians(-6), 11, 18, FACE)
        head = ("M140,110 L262,112 C266,128 270,140 272,150 C284,152 292,160 290,170 C289,176 284,178 280,176 "
                "C278,180 274,182 272,183 C278,188 280,195 276,200 C282,208 280,218 272,224 "
                "C268,234 262,242 255,246 L142,246 C138,200 138,150 140,110 Z")
        head = ("M142,110 L262,112 C266,120 267,126 268,132 C276,140 284,148 290,156 C291,160 288,162 284,162 "
                "C280,163 277,164 274,164 C272,170 274,176 272,180 C282,186 288,192 284,202 "
                "C290,212 290,226 282,236 C276,246 266,250 255,250 L134,250 C128,220 130,190 136,170 "
                "C138,150 138,130 142,110 Z")
        soft_shape(svg, head, B_SKIN, [(250, 150, 40, 60, "#FFFFFF"), (165, 210, 36, 50, B_SKIN_LO)])
        svg.path("M252,145 Q258,141 264,145 Q258,148 252,145 Z", "#FFFFFF", INK, FACE * 0.8)
        svg.ellipse(259, 145, 1.8, 1.8, INK, None)
        svg.path("M266,180 L278,182 L268,186 Z", INK, INK, FACE * 0.6)
        svg.path("M190,190 C204,208 222,224 240,235 M258,204 L278,204", width=FACE * 0.9)
        svg.path("M183,155 C171,155 171,175 183,175 Z", B_SKIN, INK, FACE)
        cap = ("M264,114 C258,94 250,80 238,70 C220,58 180,56 156,66 C134,76 122,96 124,118 "
               "C125,135 130,152 140,166 C180,150 225,128 264,114 Z")
        soft_shape(svg, cap, B_HAT, [(196, 82, 54, 30, B_HAT_LIGHT)], LINE * 0.7)
        frill_up(svg, (262, 112), (212, 128), 10, 5)
    return svg.text()


V_SKIN, V_SKIN_LO = "#EBD198", "#D3B67C"  # охристее Бабки (концепт 07)
V_SCARF, V_SCARF_LIGHT = "#8C3B3B", "#A9504C"
V_KNIT, V_KNIT_LIGHT = "#4E3B2D", "#64503E"
V_BLOUSE = "#D9CFB8"
V_NECK = "#C9433A"

V_FACE = ("M166.4,100 C146.2,104 135.0,118 130.6,136 C119.4,162 108.2,190 110.4,214 C112.6,236 144.0,256 200.0,256 "
          "C256.0,256 287.4,236 289.6,214 C291.8,190 280.6,162 269.4,136 C265.0,118 253.8,104 233.6,100 Z")
V_APRON = "#B9B2A0"


def vendor(view: str) -> str:
    """Продавщица по концептам 06–07: по пояс в окне, бордовый платок за лицом спадает на плечи,
    лоб открыт, красная косынка на шее, фартук-нагрудник, крупные руки на прилавке."""
    svg = Svg()
    body = ("M120,262 C88,272 70,296 66,334 C58,420 58,520 60,590 L340,590 C342,520 342,420 334,334 "
            "C330,296 312,272 280,262 Z")
    soft_shape(svg, body, V_KNIT, [(200, 380, 110, 140, V_KNIT_LIGHT)])
    scarf = ("M126,110 C116,58 284,58 274,110 C292,150 302,200 298,252 C262,276 138,276 102,252 "
             "C98,200 108,150 126,110 Z")
    if view == "back":
        soft_shape(svg, scarf.replace("C250,266 150,266 126,246", "C250,290 150,290 126,246"), V_SCARF,
                   [(176, 140, 60, 70, V_SCARF_LIGHT)])
        svg.path("M160,200 Q200,222 240,200", width=FACE)
        return svg.text()
    if view == "front":
        svg.path("M140,302 L260,302 L262,590 L138,590 Z", V_APRON, INK, LINE * 0.7)
        svg.path("M140,302 L128,262 M260,302 L272,262", width=LINE * 0.7)
        svg.path("M100,300 C92,360 90,420 96,470 M300,300 C308,360 310,420 304,470", width=FACE * 1.2)
        for x in (140, 260):
            svg.ellipse(x, 384, 32, 20, V_SKIN, INK, LINE * 0.8)
            for k in range(4):
                svg.path(f"M{x - 18 + k * 12},{392} L{x - 18 + k * 12},{400}", width=1.8)
        soft_shape(svg, scarf, V_SCARF, [(170, 150, 50, 80, V_SCARF_LIGHT)])
        # Косынка на шее: узел-бант с двумя концами (концепт 07).
        svg.path("M200,272 L166,256 L170,288 Z M200,272 L234,256 L230,288 Z", V_NECK, INK, FACE)
        svg.path("M194,276 L180,318 L196,312 Z M206,276 L222,322 L206,314 Z", V_NECK, INK, FACE)
        svg.ellipse(200, 274, 10, 9, V_NECK, INK, FACE)
        soft_shape(svg, V_FACE, V_SKIN, [(178, 140, 44, 60, "#FFFDEB"), (250, 210, 36, 44, V_SKIN_LO)])
        for x in (176, 224):
            svg.path(f"M{x - 10},159 Q{x},152 {x + 10},159 Q{x},165 {x - 10},159 Z", "#FFFFFF", INK, FACE * 0.8)
            svg.ellipse(x + 1, 159.5, 2.6, 2.6, INK, None)
            svg.path(f"M{x - 11},156 Q{x},149 {x + 11},156", width=FACE * 1.2)  # тяжёлое веко
            svg.path(f"M{x - 9},168 Q{x},173 {x + 9},168", width=FACE * 0.7)
        svg.path("M195,156 C194,168 195,174 200,174 C205,174 206,168 205,156", width=FACE)
        svg.path("M183,188 C194,181 206,181 217,188 C212,196 188,196 183,188 Z", INK, INK, FACE * 0.8)
        svg.path("M190,184 L210,184 L209,187 L191,187 Z", "#FFFFFF", None)
        svg.path("M190,172 C184,186 182,198 184,210 M210,172 C216,186 218,198 216,210", width=FACE * 0.9)
        svg.path("M142,222 Q156,230 170,226 M184,224 Q200,230 216,224 M258,222 Q244,230 230,226", width=FACE * 0.9)
    else:
        face = ("M156,96 C151,130 151,190 156,246 L250,246 C266,234 268,220 258,210 C268,200 266,184 258,176 "
                "C260,170 260,164 258,159 L267,153 L257,136 C256,120 256,106 256,96 Z")
        soft_shape(svg, face, V_SKIN, [(236, 150, 36, 60, "#FFFDEB")])
        svg.path("M240,142 Q246,138 252,142 Q246,145 240,142 Z", "#FFFFFF", INK, FACE * 0.8)
        svg.ellipse(247, 142, 1.8, 1.8, INK, None)
        svg.path("M246,166 L258,166 L257,172 L247,172 Z", INK, None)
        svg.path("M236,152 C230,170 230,190 236,200 M226,212 Q242,222 256,214", width=FACE * 0.9)
        svg.path("M258,98 C258,70 236,64 200,64 C162,64 140,80 138,114 C134,170 130,220 140,262 L200,262 "
                 "C190,230 184,180 188,130 C210,118 236,108 258,98 Z", V_SCARF, INK, LINE * 0.8)
        svg.ellipse(150, 330, 26, 16, V_SKIN, INK, LINE * 0.8)
    return svg.text()




# ---------------------------------------------------------------- EXT-01: полицейский и «военком»
# По референсам docs/art/concepts/extension/e01, e03 (дружинника нет — README расширения). Та же манера, что у Бабки:
# тонкий контур, плоская заливка с мягкими пятнами, тонкие черты лица. Форма без реальных эмблем: кокарда и бляха —
# простые диски. Ракурсы front/back/side (стойка), как у Бабки; бок нарисован лицом вправо, второй бок — зеркало.

P_SKIN, P_SKIN_LO, P_SKIN_HI = "#E3C581", "#C9A867", "#F2DCA2"      # широкое охристое лицо с брылями (пипетка e03: #E3C581)
P_COAT, P_COAT_HI, P_COAT_LO = "#232B45", "#34405F", "#161B2C"      # тёмно-синяя шинель до колен
P_HAT, P_HAT_HI = "#1F1E28", "#3C3A46"                              # ушанка (пипетка e03: #1F1E28, ворс #4A474C)
P_BAND, P_BAND_HI = "#2E52A8", "#5578C8"                            # синяя повязка на левом рукаве (e03: #2E4E9B)
P_BOOT, P_PANTS = "#1A1718", "#1D2338"
NOTE_PAPER, PENCIL, BRASS = "#DDD2C0", "#E9B93A", "#C9B35A"          # блокнот серо-бежевый (e03: #C8BAA8)

O_SKIN, O_SKIN_LO, O_SKIN_HI = "#F5A3B0", "#D98593", "#FBC4CC"      # розовое худое лицо без румянца (e03: #F9A4AE)
O_COAT, O_COAT_HI, O_COAT_LO = "#5F4E29", "#76643A", "#46391C"      # буро-оливковая шинель (e03: #5F4E29)
O_CAP, O_CAP_HI, O_CAP_BAND, O_VISOR = "#665A2E", "#7E7140", "#9A2414", "#1E1A12"   # фуражка, красный околыш
O_HAIR, O_HAIR_HI, O_HAIR_LO = "#9A968A", "#C2BEB2", "#5E5A52"      # седина (e03: #8D867D), низ затылка темнее
O_STRAND = "#DCD8CC"                                                # светлые пряди затылка
O_STRAP, O_SHIRT, O_PANTS = "#9A2414", "#3B2E1F", "#3E3A33"         # красные погоны без знаков, рубашка, брюки
CLIP_BOARD, CLIP_PAPER, CLIP_METAL = "#B2925F", "#F2EEE0", "#8E9096"
O_BOOT = "#1A1718"


def tube(svg: Svg, d: str, width: float, fill: str, lo: str | None = None) -> None:
    """Рукав или нога одной толстой линией со скруглёнными концами и контуром по краю."""
    svg.path(d, "none", INK, width)
    svg.path(d, "none", fill, width - LINE * 2.0)
    if lo:
        svg.path(d, "none", lo, (width - LINE * 2.0) * 0.45, extra=' transform="translate(5,6)" opacity="0.55"')


def superellipse(cx: float, cy: float, rx: float, ry: float, p: float, n: int,
                 rot: float = 0.0) -> list[tuple[float, float]]:
    """Точки суперэллипса |x/rx|^p + |y/ry|^p = 1: p=2 — эллипс, p≥4 — скруглённый прямоугольник."""
    a = math.radians(rot)
    pts = []
    for i in range(n):
        t = 2 * math.pi * i / n
        c, s = math.cos(t), math.sin(t)
        x, y = rx * math.copysign(abs(c) ** (2 / p), c), ry * math.copysign(abs(s) ** (2 / p), s)
        pts.append((cx + x * math.cos(a) - y * math.sin(a), cy + x * math.sin(a) + y * math.cos(a)))
    return pts


def fur_d(pts: list[tuple[float, float]], depth: float) -> str:
    """Меховой контур ушанки: между соседними точками — фестон наружу, глубина неровная, как от руки."""
    area = sum(pts[i - 1][0] * pts[i][1] - pts[i][0] * pts[i - 1][1] for i in range(len(pts)))
    sign = 1.0 if area > 0 else -1.0
    d = f"M{pts[0][0]:.1f},{pts[0][1]:.1f}"
    for i in range(len(pts)):
        (x0, y0), (x1, y1) = pts[i], pts[(i + 1) % len(pts)]
        dx, dy = x1 - x0, y1 - y0
        ln = math.hypot(dx, dy) or 1.0
        k = depth * (1.0, 0.6, 0.85)[i % 3]
        d += f" Q{(x0 + x1) / 2 + dy / ln * sign * k:.1f},{(y0 + y1) / 2 - dx / ln * sign * k:.1f} {x1:.1f},{y1:.1f}"
    return d + " Z"


def fur_strokes(svg: Svg, pts: list[tuple[float, float]]) -> None:
    """Короткие светлые штрихи ворса внутри меховой детали."""
    for i, (x, y) in enumerate(pts):
        s = 1 if i % 2 else -1
        svg.path(f"M{x:.1f},{y:.1f} q{3 * s},{-4} {6 * s},{-3}", "none", P_HAT_HI, THIN * 1.4, extra=' opacity="0.9"')


def brush_moustache(svg: Svg, x0: float, x1: float, top: float, bottom: float) -> None:
    """Усы-щётка (e03): тёмный брусок, нижний край — неровный ворс, внутри светлые штрихи щетины."""
    n = max(4, round((x1 - x0) / 4))
    d = f"M{x0},{bottom - 2} C{x0 - 1},{top + 3} {x0 + 3},{top} {x0 + 8},{top} L{x1 - 8},{top} " \
        f"C{x1 - 3},{top} {x1 + 1},{top + 3} {x1},{bottom - 2}"
    for i in range(n, -1, -1):   # ворс справа налево: зубцы разной длины
        x = x0 + (x1 - x0) * i / n
        d += f" L{x:.1f},{bottom + (2.5, 0.5, 3.5, 1.0)[i % 4]:.1f}"
    svg.path(d + " Z", INK, INK, FACE * 0.7)
    for i in range(1, n):
        x = x0 + (x1 - x0) * i / n
        svg.path(f"M{x:.1f},{top + 2.5} L{x + 0.4:.1f},{bottom - 1.5}", "none", "#6B6A72", FACE * 0.55)


# ART-07: полицейский по сетке e03. Координаты форм сняты с кропа e03, приведённого к холсту 400×600 по росту
# (верх ушанки y=20, подошвы y=580); в SVG сетка переносится целиком: P_GRID (рост облика прежний — 0,86 холста,
# height_m 2,05). Композиция e03: ушанка сидит на голове и уже фигуры (корона 125–305, клапаны расходятся вниз
# до 97–316 — «колокол»), лицо широкое и плоское (130–270 × 92–204: выше ширины в 0,73), глаза сразу под
# козырьком, шеи нет; шинель — высокий скруглённый прямоугольник 54–360 × 186–484, рукава выпирают в стороны
# до 4 и 396; блокнот у груди слева от оси, карандаш в правой руке; короткие широкие штаны, крупные ботинки
# носками наружу.
P_GRID_K = 0.932
P_GRID = f"translate(200,590) scale({P_GRID_K}) translate(-200,-580)"
P_AXIS = 205   # ось фигуры по шинели (e03: 54–358)
P_RIM, P_RIM_W, P_RIM_OP = "#B4C4E0", 2.5, 0.7   # иней (ART-07 п2): светлая кайма только сверху — ушанка и плечи, ед. наружу
P_RIM_Y = (205, 245)   # кайма по шинели: полная выше y 205, ослабленная до 245, ниже — нет (на 3 м не «наклейка»)

P_CROWN = superellipse(213, 62, 86, 37, 2.7, 26)                       # корона ушанки 125–305 × 20–100 (с мехом)
P_PANEL = superellipse(206, 72, 56, 23, 4, 22)                         # поднятый передний клапан 148–264 × 47–97
P_FOLD = superellipse(282, 80, 18, 28, 3, 14)                          # правый бок короны (виден в 3/4)
# Клапаны ушанки опущены сплошной массой от тульи до челюсти, обрамляя лицо (e03/e01): внутренний край под лицом.
P_FLAPS = ([(158, 78), (136, 84), (118, 98), (107, 116), (101, 134), (101, 150), (107, 160), (119, 164), (132, 163),
            (148, 150), (156, 118)],
           [(254, 78), (280, 82), (298, 96), (309, 114), (315, 134), (313, 152), (305, 166), (290, 172), (274, 171),
            (258, 152), (252, 118)])
P_BACKFLAP = superellipse(207, 128, 100, 60, 3.0, 28)                  # со спины: затылочный клапан до плеч
P_FACE = [(152, 94), (200, 92), (248, 94), (250, 112), (254, 136), (264, 158), (268, 176), (260, 192), (236, 201),
          (204, 203), (170, 201), (146, 194), (130, 178), (130, 156), (138, 128), (146, 108)]
P_COAT_PTS = [(90, 176), (120, 174), (206, 190), (292, 174), (322, 176), (348, 196), (358, 240), (358, 360), (360, 440),
              (354, 462), (326, 478), (206, 481), (84, 479), (58, 466), (54, 440), (54, 360), (56, 240), (64, 198)]
P_ARM_L = [(88, 180), (54, 198), (22, 232), (6, 276), (10, 316), (36, 334), (62, 342), (96, 334), (128, 308),
           (134, 288), (118, 272), (92, 286), (68, 296), (60, 272), (64, 240), (80, 212)]
P_ARM_R = [(322, 178), (354, 196), (380, 230), (394, 268), (396, 306), (384, 334), (358, 346), (316, 342),
           (276, 332), (244, 324), (236, 304), (252, 292), (288, 300), (330, 302), (344, 286), (342, 254), (330, 222)]
P_BAND_PTS = [(305, 266), (330, 254), (360, 247), (385, 251), (394, 270), (395, 302), (380, 305), (350, 297),
              (320, 291), (306, 289)]
P_PANTS_L = [(88, 470), (172, 470), (172, 494), (168, 517), (146, 529), (112, 529), (96, 519), (90, 495)]
P_LEG_AXIS = 201   # штанины e03 симметричны около x≈201 (90–171 и 230–311)
P_BOOT_L = [(102, 512), (162, 512), (164, 546), (164, 568), (146, 572), (110, 573), (74, 571), (66, 563), (72, 552),
            (100, 544)]
P_BOOT_R = [(240, 512), (298, 512), (302, 546), (330, 560), (338, 572), (334, 580), (296, 581), (252, 580), (240, 570),
            (238, 546)]   # правый ботинок ниже и носком наружу (e03: подошва 251–335 на y 575)
P_NOTE = (184, 296, 62, 70, -10)        # блокнот: центр, ширина, высота, наклон (e03: 150–220 × 262–330)
P_PENCIL = ((101, 232), (138, 297))     # карандаш: ластик вверху слева, грифель к блокноту
P_HANDS = ((112, 276, 24, 21), (222, 312, 27, 23))   # кисти: левая с карандашом, правая держит блокнот


def mirror_pts(pts: list[tuple[float, float]], axis: float = P_AXIS) -> list[tuple[float, float]]:
    return [(2 * axis - x, y) for x, y in pts]


def police_rim(svg: Svg, hat: list[str], body: list[str]) -> None:
    """Иней сверху: светлые штрихи ушанки и верха шинели до заливок — заливки закрывают внутреннюю половину, снаружи
    чернильного контура остаётся кайма P_RIM_W (тёмный на тёмном, LOOK-01). Ушанка — целиком; шинель и рукава —
    только плечи (выше P_RIM_Y[0]), ниже — слабее до P_RIM_Y[1]; ноги и подол без каймы. Группа с общей
    прозрачностью: перекрытия штрихов не светлеют."""
    w = LINE * LINE_K + 2 * P_RIM_W
    y0, y1 = P_RIM_Y
    svg._clip += 1
    ca, cb = f"ra{svg._clip}", f"rb{svg._clip}"
    svg.defs.append(f'<clipPath id="{ca}"><rect x="-100" y="-100" width="600" height="{y0 + 100}"/></clipPath>')
    svg.defs.append(f'<clipPath id="{cb}"><rect x="-100" y="{y0}" width="600" height="{y1 - y0}"/></clipPath>')
    strokes = "".join(f'<path d="{d}" fill="none" stroke="{P_RIM}" stroke-width="{w}" stroke-linejoin="round"/>'
                      for d in body)
    svg.add(f'<g opacity="{P_RIM_OP}">' + "".join(f'<path d="{d}" fill="none" stroke="{P_RIM}" stroke-width="{w}" '
                                                  f'stroke-linejoin="round"/>' for d in hat)
            + f'<g clip-path="url(#{ca})">{strokes}</g></g>')
    svg.add(f'<g opacity="{P_RIM_OP * 0.45:.2f}"><g clip-path="url(#{cb})">{strokes}</g></g>')


def police_boots(svg: Svg, side: bool = False) -> None:
    if side:
        boot = smooth_d([(166, 512), (232, 512), (236, 546), (262, 554), (296, 562), (304, 574), (288, 580),
                         (210, 581), (168, 579), (162, 556)])
        soft_shape(svg, boot, P_BOOT, [(200, 530, 18, 14, "#3A3438")], LINE * 0.9)
        svg.path("M172,548 Q200,553 232,548", width=THIN * 0.8)
        return
    for pts in (P_BOOT_L, P_BOOT_R):
        d = smooth_d(pts)
        x0 = min(x for x, _ in pts[:2]) + 18
        soft_shape(svg, d, P_BOOT, [(x0 + 16, 530, 16, 12, "#3A3438")], LINE * 0.9)
    for x0, x1 in ((102, 162), (240, 298)):
        svg.path(f"M{x0 + 2},548 Q{(x0 + x1) / 2},553 {x1 - 2},548", width=THIN * 0.8)


def police_pants(svg: Svg) -> None:
    for pts in (P_PANTS_L, mirror_pts(P_PANTS_L, P_LEG_AXIS)):
        cx = sum(x for x, _ in pts) / len(pts)
        soft_shape(svg, smooth_d(pts), P_PANTS, [(cx - 14, 488, 26, 16, P_COAT_HI)], LINE * 0.9)
        svg.path(f"M{cx - 30:.0f},512 Q{cx:.0f},518 {cx + 30:.0f},512", width=THIN * 0.7)   # складка над ботинком


def police_hand(svg: Svg, x: float, y: float, rx: float, ry: float, side: int) -> None:
    """Пухлая кисть: ладонь и четыре коротких пальца, загнутых к оси (держат карандаш или блокнот)."""
    svg.ellipse(x, y, rx, ry, P_SKIN, INK, LINE * 0.8)
    for k in range(4):
        fy = y - ry * 0.55 + k * ry * 0.36
        fx0, fx1 = x - side * rx * 0.2, x - side * (rx + 7)
        svg.path(f"M{fx0:.1f},{fy:.1f} L{fx1:.1f},{fy + 2:.1f}", "none", INK, 9)
        svg.path(f"M{fx0:.1f},{fy:.1f} L{fx1:.1f},{fy + 2:.1f}", "none", P_SKIN, 9 - LINE * 1.2)
    svg.ellipse(x, y, rx - 2, ry - 2, P_SKIN, None)
    soft_spot(svg, f"M{x - rx},{y} a{rx},{ry} 0 1,0 {2 * rx},0 a{rx},{ry} 0 1,0 {-2 * rx},0", x - rx * 0.3,
              y - ry * 0.3, rx * 0.6, ry * 0.5, P_SKIN_HI)


def police_note(svg: Svg, cx: float, cy: float, w: float, h: float, tilt: float) -> None:
    with svg.group(f"rotate({tilt} {cx} {cy})"):
        svg.path(f"M{cx - w / 2},{cy - h / 2} L{cx + w / 2},{cy - h / 2} L{cx + w / 2},{cy + h / 2} "
                 f"L{cx - w / 2},{cy + h / 2} Z", NOTE_PAPER, INK, LINE * 0.8)
        for i in range(6):
            svg.ellipse(cx - w / 2 + 7 + i * (w - 14) / 5, cy - h / 2, 2.8, 4.2, "none", INK, THIN * 0.8)
        for k in range(4):
            y = cy - h / 2 + 18 + k * 12
            svg.path(f"M{cx - w / 2 + 7},{y} L{cx + w / 2 - 7},{y}", width=THIN * 0.5, extra=' opacity="0.45"')


def police_pencil(svg: Svg, a: tuple[float, float], b: tuple[float, float]) -> None:
    d = f"M{a[0]},{a[1]} L{b[0]},{b[1]}"
    svg.path(d, "none", INK, 9)
    svg.path(d, "none", PENCIL, 9 - LINE * 1.4)
    svg.ellipse(a[0], a[1], 3.6, 3.6, "#E9A0A0", INK, THIN * 0.7)                      # ластик
    ux, uy = b[0] - a[0], b[1] - a[1]
    ln = math.hypot(ux, uy)
    ux, uy = ux / ln, uy / ln
    tip = (b[0] + ux * 9, b[1] + uy * 9)
    svg.path(f"M{b[0] - uy * 4:.1f},{b[1] + ux * 4:.1f} L{tip[0]:.1f},{tip[1]:.1f} L{b[0] + uy * 4:.1f},{b[1] - ux * 4:.1f} Z",
             "#F6E4B0", INK, THIN * 0.7)


def police_face(svg: Svg) -> None:
    # e03: глаза-щёлки с белками сразу под ушанкой, близко к оси (взгляд чуть влево); брови ровные и тяжёлые, легли
    # на верх глаза — прищур; узкий нос от бровей; усы-щётка, под ними рот скобкой уголками вниз; носогубные складки
    # от крыльев носа к брылям; «гусиные лапки»; три складки по нижнему краю.
    for x, lid in ((181, "M171,118.2 Q181,117.4 190.5,119"), (209, "M198.5,119 Q209,118.4 220,120.6")):
        svg.path(f"M{x - 7},121.6 Q{x},118.6 {x + 7},121.6 Q{x},126.4 {x - 7},121.6 Z", "#FFFFFF", INK, FACE * 0.7)
        svg.ellipse(x - 1.8, 122.4, 2.3, 2.3, INK, None)
        svg.path(lid, "none", INK, FACE * 2.4)                                             # ровная тяжёлая бровь
        svg.path(f"M{x - 5},127.4 Q{x},129.4 {x + 5},127.4", width=FACE * 0.5)              # мешки
    svg.path("M171,125 L178,126.6 M171.5,128.6 L177.5,128.4", width=FACE * 0.55)          # «гусиные лапки»
    svg.path("M213.5,127.6 L220,131 M212.5,130.4 L217.5,134.4", width=FACE * 0.55)
    svg.path("M190.6,120 C189.6,124 188.8,128 188.8,131.4 C190.6,134.4 197.4,134.4 199.2,131.4 "
             "C199.2,128 198.6,124 197.6,120", width=FACE * 0.9)                         # узкий нос от бровей
    brush_moustache(svg, 174.5, 213.5, 135.5, 142.5)   # ART-08: щётка 0,28 ширины лица (39 из 138), e03
    svg.path("M181.5,149.5 Q194,143.5 206.5,149.5", width=FACE * 1.1)                    # рот скобкой, уголки вниз
    svg.path("M181.5,149.5 l-2.2,3.2 M206.5,149.5 l2.2,3.2", width=FACE * 0.8)
    svg.path("M188.5,152.6 Q194,154.2 199.5,152.6", width=FACE * 0.55)                   # нижняя губа
    svg.path("M182,131.5 C175,140 170,149 167.5,159 M204.5,133 C209.5,142 212,152 213,163", width=FACE * 0.9)
    for d in ("M143,168 Q154,175 166,169", "M176,172 Q188,177 200,172", "M214,171 Q227,177 240,169"):
        svg.path(d, width=FACE * 0.8)                                                    # три складки брылей


def police_ushanka(svg: Svg, view: str) -> None:
    if view == "side":
        soft_shape(svg, fur_d(superellipse(150, 136, 34, 44, 2.4, 16, rot=10), 6), P_HAT,
                   [(142, 128, 16, 30, P_HAT_HI)], LINE * 0.8)                         # ухо-клапан у затылка
        fur_strokes(svg, [(140 + 8 * (i % 2), 110 + i * 14) for i in range(5)])
        soft_shape(svg, fur_d(superellipse(206, 60, 88, 40, 3.2, 26), 7), P_HAT, [(186, 44, 56, 16, P_HAT_HI)],
                   LINE * 0.8)
        soft_shape(svg, fur_d(superellipse(270, 72, 30, 27, 3.2, 16), 6), P_HAT, [(262, 66, 16, 12, P_HAT_HI)],
                   LINE * 0.8)                                                          # поднятый передний клапан
        fur_strokes(svg, [(150 + i * 22, 70 + 10 * (i % 3)) for i in range(6)])
        return
    soft_shape(svg, fur_d(P_CROWN, 7), P_HAT, [(196, 40, 70, 16, P_HAT_HI)], LINE * 0.8)
    if view == "back":
        soft_shape(svg, fur_d(P_BACKFLAP, 8), P_HAT, [(226, 110, 70, 36, P_HAT_HI)], LINE * 0.8)
        fur_strokes(svg, [(120 + i * 22, 112 + 22 * (i % 3)) for i in range(9)])
        svg.path("M120,78 Q207,64 296,78", "none", INK, THIN * 0.8)                  # шов: корона и задний клапан
        return
    soft_shape(svg, fur_d(P_FOLD, 6), P_HAT, [(280, 62, 10, 18, P_HAT_HI)], LINE * 0.8)
    soft_shape(svg, fur_d(P_PANEL, 7), P_HAT, [(186, 62, 40, 12, P_HAT_HI)], LINE * 0.8)
    fur_strokes(svg, [(158 + i * 19, 58 + 12 * (i % 3)) for i in range(6)])
    svg.ellipse(200, 68, 6.0, 6.0, BRASS, INK, THIN)   # простой диск вместо кокарды: без реальных эмблем
    svg.ellipse(200, 68, 2.1, 2.1, INK, None)


def police_flap_ds(back: bool = False) -> list[str]:
    """Клапаны ушанки (со спины — зеркально: больший клапан слева)."""
    return [fur_d(mirror_pts(p) if back else p, 7) for p in P_FLAPS]


def police_flaps(svg: Svg, back: bool = False) -> None:
    for pts, s in zip(P_FLAPS, (-1, 1)):
        if back:
            pts, s = mirror_pts(pts), -s
        cx = sum(x for x, _ in pts) / len(pts)
        ox = min(x for x, _ in pts) if s < 0 else max(x for x, _ in pts)   # ворс и блик — у внешнего края
        soft_shape(svg, fur_d(pts, 7), P_HAT, [(ox - 16 * s, 132, 12, 26, P_HAT_HI)], LINE * 0.8)
        fur_strokes(svg, [(ox - (12 + 5 * (i % 2)) * s, 104 + i * 13) for i in range(5)])
        svg.path(f"M{cx + 6 * s:.0f},158 Q{ox - 10 * s:.0f},152 {ox - 4 * s:.0f},138", "none", INK, THIN * 0.7,
                 extra=' opacity="0.7"')                                                   # складка меха у челюсти


def police(view: str) -> str:
    svg = Svg()
    with svg.group(P_GRID):
        police_figure(svg, view)
    return svg.text()


def police_figure(svg: Svg, view: str) -> None:
    if view == "front":
        police_rim(svg, [fur_d(P_CROWN, 7), fur_d(P_FOLD, 6)] + police_flap_ds(),
                   [smooth_d(P_COAT_PTS), smooth_d(P_ARM_L), smooth_d(P_ARM_R)])
        police_boots(svg)
        police_pants(svg)
        soft_shape(svg, smooth_d(P_COAT_PTS), P_COAT, [(150, 300, 80, 90, P_COAT_HI), (70, 420, 40, 120, P_COAT_LO),
                                                   (346, 420, 40, 120, P_COAT_LO)])
        svg.path("M190,262 C186,330 181,410 177,482", width=THIN * 0.9)                 # борт
        svg.path("M60,468 Q206,476 352,468", width=THIN * 0.6, extra=' opacity="0.6"')   # подгиб
        for x, y in ((172, 352), (170, 396), (234, 396), (236, 440)):
            svg.ellipse(x, y, 4.2, 4.2, BRASS, INK, THIN * 0.7)
        for pts in ([(52, 352), (106, 352), (106, 380), (54, 382)], [(272, 368), (352, 366), (352, 394), (274, 396)]):
            svg.path(smooth_d(pts, k=0.04), P_COAT_LO, INK, THIN * 0.9)                # клапаны карманов
        # Воротник: серая рубашка, чёрный галстук, лацканы; погоны с красным кантом.
        svg.path("M166,196 L200,264 L236,196 Z", "#3B3A42", INK, FACE)
        svg.path("M195,204 L207,204 L211,250 L201,264 L191,250 Z", INK, INK, FACE * 0.6)
        for pts in ([(118, 186), (168, 194), (200, 264), (184, 272), (158, 238), (170, 228), (138, 204)],
                    [(294, 186), (236, 194), (204, 264), (222, 272), (250, 236), (240, 228), (272, 204)]):
            soft_shape(svg, smooth_d(pts, k=0.08), P_COAT, [(pts[3][0], 240, 20, 30, P_COAT_HI)], LINE * 0.8)
        for pts in ([(66, 200), (112, 181), (118, 191), (74, 209)], [(298, 181), (344, 200), (336, 209), (292, 191)]):
            svg.path(smooth_d(pts, k=0.04), P_COAT_HI, INK, THIN * 0.9)
            svg.path(f"M{pts[0][0] + 3},{pts[0][1] + 2} L{pts[1][0] - 2},{pts[1][1] + 2}", "none", "#A8322C", 2.2)
        # Рукава: оба согнуты к груди; на левом (справа от зрителя) — синяя повязка.
        soft_shape(svg, smooth_d(P_ARM_L), P_COAT, [(40, 260, 26, 50, P_COAT_HI), (70, 330, 50, 16, P_COAT_LO)])
        svg.path("M60,272 C66,290 80,300 96,300", width=THIN * 0.8)                     # сгиб локтя
        soft_shape(svg, smooth_d(P_ARM_R), P_COAT, [(370, 262, 22, 50, P_COAT_HI), (330, 334, 60, 14, P_COAT_LO)])
        svg.path("M342,290 C330,300 300,304 280,300", width=THIN * 0.8)
        soft_shape(svg, smooth_d(P_BAND_PTS), P_BAND, [(350, 262, 34, 10, P_BAND_HI)], LINE * 0.8)
        # Блокнот у груди слева от оси, правая кисть держит его снизу, левая — карандаш.
        police_note(svg, *P_NOTE)
        police_pencil(svg, *P_PENCIL)
        (lx, ly, lrx, lry), (rx, ry, rrx, rry) = P_HANDS
        police_hand(svg, lx, ly, lrx, lry, -1)
        police_hand(svg, rx, ry, rrx, rry, 1)
        # Голова: клапаны ушанки за широким плоским лицом, корона сидит на лбу.
        police_flaps(svg)
        soft_shape(svg, smooth_d(P_FACE), P_SKIN, [(190, 118, 40, 22, P_SKIN_HI), (258, 166, 22, 30, P_SKIN_LO),
                                                   (142, 166, 18, 26, P_SKIN_LO), (206, 206, 70, 14, P_SKIN_LO),
                                                   (154, 168, 12, 5, P_SKIN_HI), (188, 172, 13, 5, P_SKIN_HI),
                                                   (228, 171, 13, 5, P_SKIN_HI)])
        police_face(svg)
        police_ushanka(svg, "front")
    elif view == "back":
        arm_l, arm_r = mirror_pts(P_ARM_R), mirror_pts(P_ARM_L)   # со спины левая рука с повязкой — слева
        police_rim(svg, [fur_d(P_CROWN, 7), fur_d(P_BACKFLAP, 8)] + police_flap_ds(back=True),
                   [smooth_d(P_COAT_PTS), smooth_d(arm_l), smooth_d(arm_r)])
        police_boots(svg)
        police_pants(svg)
        soft_shape(svg, smooth_d(P_COAT_PTS), P_COAT, [(250, 300, 90, 100, P_COAT_HI), (70, 420, 40, 120, P_COAT_LO)])
        svg.path("M206,200 L206,484", width=THIN * 0.8)                                  # шов и шлица
        svg.path("M60,468 Q206,476 352,468", width=THIN * 0.6, extra=' opacity="0.6"')
        svg.path("M88,330 Q206,342 324,330", width=THIN * 0.7)                           # хлястик-строчка
        for x in (176, 236):
            svg.ellipse(x, 334, 4.2, 4.2, BRASS, INK, THIN * 0.7)
        soft_shape(svg, smooth_d(arm_l), P_COAT, [(40, 262, 22, 50, P_COAT_HI)])
        soft_shape(svg, smooth_d(arm_r), P_COAT, [(370, 262, 26, 50, P_COAT_HI), (330, 330, 50, 16, P_COAT_LO)])
        soft_shape(svg, smooth_d(mirror_pts(P_BAND_PTS)), P_BAND, [(60, 262, 34, 10, P_BAND_HI)], LINE * 0.8)
        for pts in ([(66, 200), (112, 181), (118, 191), (74, 209)], [(298, 181), (344, 200), (336, 209), (292, 191)]):
            svg.path(smooth_d(pts, k=0.04), P_COAT_HI, INK, THIN * 0.9)
        svg.path(smooth_d([(140, 176), (206, 168), (272, 176), (276, 200), (206, 206), (136, 200)]), P_COAT_LO, INK,
                 LINE * 0.8)                                                            # стоячий воротник
        police_flaps(svg, back=True)
        police_ushanka(svg, "back")
    else:  # side, лицом вправо: та же высота форм, шинель в профиль — глубокий скруглённый прямоугольник
        coat = smooth_d([(150, 186), (252, 186), (292, 200), (320, 240), (334, 320), (336, 400), (330, 470),
                         (300, 484), (140, 484), (108, 470), (100, 400), (104, 300), (114, 220)])
        arm = smooth_d([(196, 196), (234, 202), (250, 236), (250, 290), (276, 296), (316, 290), (330, 306),
                        (318, 330), (270, 340), (222, 336), (196, 316), (184, 270), (184, 226)])
        face = smooth_d([(196, 92), (258, 94), (282, 120), (294, 150), (300, 176), (288, 196), (252, 206),
                         (200, 206), (180, 182), (182, 130)])
        police_rim(svg, [fur_d(superellipse(206, 60, 88, 40, 3.2, 26), 7),
                         fur_d(superellipse(150, 136, 34, 44, 2.4, 16, rot=10), 6)], [coat, arm])
        police_boots(svg, side=True)
        soft_shape(svg, smooth_d([(150, 470), (262, 470), (264, 500), (256, 524), (156, 524), (148, 500)]), P_PANTS,
                   [(200, 488, 30, 14, P_COAT_HI)], LINE * 0.9)
        soft_shape(svg, coat, P_COAT, [(250, 300, 70, 100, P_COAT_HI), (120, 420, 30, 120, P_COAT_LO)])
        svg.path("M310,236 C324,320 326,400 318,480", width=THIN * 0.9)                # борт
        for y in (352, 396, 440):
            svg.ellipse(306 - (y - 352) * 0.02, y, 4.2, 4.2, BRASS, INK, THIN * 0.7)
        svg.path("M106,468 Q220,476 330,468", width=THIN * 0.6, extra=' opacity="0.6"')
        svg.path(smooth_d([(200, 180), (262, 184), (280, 206), (232, 212)], k=0.08), P_COAT_LO, INK, LINE * 0.8)
        # Ближняя рука согнута перед грудью: блокнот и карандаш впереди.
        police_note(svg, 318, 278, 22, 66, -6)
        soft_shape(svg, arm, P_COAT, [(214, 250, 20, 40, P_COAT_HI), (280, 330, 40, 10, P_COAT_LO)])
        police_pencil(svg, (300, 236), (322, 290))          # повязка на левой (дальней) руке в профиль не видна
        police_hand(svg, 326, 306, 22, 20, 1)
        # Голова в профиль: ухо-клапан у затылка, широкое лицо с брылями вперёд, нос, усы.
        soft_shape(svg, face, P_SKIN, [(250, 120, 36, 24, P_SKIN_HI), (222, 186, 40, 18, P_SKIN_LO)])
        svg.path("M258,124 Q266,119 274,124 Q266,129 258,124 Z", "#FFFFFF", INK, FACE * 0.8)
        svg.ellipse(270, 124.5, 2.6, 2.6, INK, None)
        svg.path("M252,111 Q264,111 278,118", "none", INK, FACE * 2.3)
        svg.path("M286,124 C298,132 304,142 298,148 C292,152 284,148 284,142", P_SKIN, INK, FACE)   # нос
        brush_moustache(svg, 265, 299, 148, 157)   # ART-08: 0,28 ширины лица в профиль
        svg.path("M272,166 Q284,163 294,168", width=FACE)
        svg.path("M238,148 C246,164 258,174 274,176", width=FACE * 0.9)
        svg.path("M214,190 Q246,198 276,190", width=FACE * 0.8)
        police_ushanka(svg, "side")


# «Военком» (ART-07): по сетке e03 — в 3/4 вправо, как на концепте: сутулый, голова вынесена вперёд на длинной
# наклонной шее, нос-«луковица» торчит за контур лица, фуражка с высокой тульей задрана вверх-вправо, козырёк
# вправо. Левая (от зрителя) рука висит, длинная кисть до середины бедра; правая согнута, папка-планшет у груди.
# Шинель длинная, расширяется книзу вправо, подол скошен; галифе, сапоги носками наружу. Координаты — сетка
# кропа e03 (верх фуражки y=20, подошвы y=580); O_GRID переносит её на холст (рост 0,94 холста, height_m 2,2).
O_GRID = "translate(200,590) scale(1.011) translate(-200,-580)"
O_HEAD_SHIFT = (-2, -2)   # лицо под фуражкой: лучший сдвиг маски лица по наложению на e03
O_SIDE_K = "translate(200,590) scale(0.985) translate(-200,-590)"   # бок и спина: верх фуражки на высоте фаса
O_COAT_PTS = [(158, 146), (182, 140), (198, 146), (206, 166), (222, 161), (234, 176), (241, 194), (245, 214), (246, 260),
              (242, 340), (248, 400), (262, 450), (272, 478), (242, 484), (200, 490), (160, 495), (133, 499),
              (130, 460), (126, 400), (122, 330), (124, 252), (127, 214), (130, 200), (133, 186), (139, 170),
              (146, 159), (153, 150)]   # ворот сзади высокий; плечи — скат «вешалкой» с углом (e03: 153,150 → 132,198)
O_ARM_HANG = [(131, 197), (149, 163), (158, 188), (157, 240), (153, 300), (151, 352), (117, 352), (117, 300),
              (121, 236), (126, 212)]   # рукав от угла плеча, верх — по скату под погоном
O_FACE_PTS = [(197, 72), (249, 68), (253, 86), (250, 102), (244, 122), (240, 138), (236, 150), (222, 155),
              (206, 152), (194, 138), (193, 124), (195, 108), (195, 92)]   # п2: щека ниже уха шире влево (e03)
O_NOSE_PTS = [(230, 90), (241, 96), (251, 100), (259, 109), (265, 119), (266.5, 127), (262, 135), (254, 138),
              (246, 137), (241, 130), (238, 119), (233, 104)]   # «луковица» длиннее вниз: низ кончика на 6 ед. ниже (e03)
O_CROWN_PTS = [(174, 62), (172, 52), (186, 42), (208, 31), (232, 22), (252, 18), (260, 24), (257, 36), (249, 50),
               (246, 58)]   # тулья задрана вверх-вправо (e03: верх 214–257 на y 30)
O_VISOR_PTS = [(200, 73), (226, 67), (252, 63), (266, 65), (268, 71), (250, 76), (222, 77)]
O_TUFT_L = [(198, 78), (182, 78), (170, 84), (166, 94), (174, 96), (168, 106), (180, 108), (188, 114), (196, 104)]
O_TUFT_R = [(252, 78), (257, 80), (260, 88), (256, 95), (252, 92)]
OFFICER_BODY = ("M186,166 C170,168 152,172 142,182 C134,194 132,214 132,240 C130,320 124,420 118,508 "
                "L282,508 C276,420 270,320 268,240 C268,214 266,194 258,182 C248,172 230,168 214,166 Z")
O_TUFT = ("M176,56 C164,56 154,60 147,68 L157,71 C150,77 146,85 145,94 L155,90 C155,97 157,103 161,108 "
          "L167,99 L170,104 L174,90 Z")      # вихры седых волос в стороны из-под околыша
O_EAR = "M174,80 C165,74 157,80 158,91 C159,102 166,107 174,103"
O_STOOP_SIDE = (10, 7)     # в профиль голова вперёд, шея наклонена, спина горбится
O_STOOP_BACK = (0, 7)


def officer_boots(svg: Svg, xs: tuple[float, float] = (160, 218), side: bool = False) -> None:
    """Сапоги e03: голенище до колена, носки врозь (левый влево, правый вправо), галифе над голенищем."""
    if side:
        svg.path(smooth_d([(186, 498), (220, 498), (224, 520), (218, 540), (188, 540), (182, 520)]), O_PANTS, INK,
                 LINE * 0.8)
        boot = smooth_d([(190, 530), (216, 530), (218, 560), (244, 566), (262, 572), (262, 580), (230, 582),
                         (190, 581), (186, 560)])
        soft_shape(svg, boot, O_BOOT, [(204, 546, 8, 12, "#3E3A3A")], LINE * 0.8)
        return
    for x, s in zip(xs, (-1, 1)):
        svg.path(smooth_d([(x - 13, 486), (x + 13, 486), (x + 14, 506), (x + 11, 528), (x - 11, 528), (x - 14, 506)]),
                 O_PANTS, INK, LINE * 0.8)
        # e03: голенища 152–173 и 202–223; левый носок влево до 129, правая стопа вправо-вниз 229–275 на y 575.
        if s < 0:
            pts = [(x - 9, 522), (x + 13, 522), (x + 14, 552), (x + 10, 578), (x - 20, 580), (x - 32, 577),
                   (x - 30, 568), (x - 18, 562), (x - 9, 554)]
        else:
            pts = [(x - 16, 522), (x + 6, 522), (x + 8, 546), (x + 26, 556), (x + 44, 564), (x + 54, 572),
                   (x + 50, 579), (x + 14, 580), (x - 10, 572), (x - 20, 557)]
        soft_shape(svg, smooth_d(pts, k=0.12), O_BOOT, [(x - 4, 540, 6, 12, "#3E3A3A")], LINE * 0.8)


def clipboard(svg: Svg, x: float, y: float, w: float, h: float, tilt: float) -> None:
    with svg.group(f"rotate({tilt} {x} {y})"):
        svg.path(f"M{x - w / 2},{y - h / 2} L{x + w / 2},{y - h / 2} L{x + w / 2},{y + h / 2} L{x - w / 2},{y + h / 2} Z",
                 CLIP_BOARD, INK, LINE * 0.8)
        if w > 24:
            svg.path(f"M{x - w / 2 + 4},{y - h / 2 + 9} L{x + w / 2 - 4},{y - h / 2 + 9} L{x + w / 2 - 4},{y + h / 2 - 4} "
                     f"L{x - w / 2 + 4},{y + h / 2 - 4} Z", CLIP_PAPER, INK, THIN * 0.7)
            for k in range(3):
                svg.path(f"M{x - w / 2 + 9},{y - h / 2 + 22 + k * 11} L{x + w / 2 - 10},{y - h / 2 + 22 + k * 11}",
                         width=THIN * 0.5, extra=' opacity="0.5"')
        cw = min(12, w / 2 - 1)
        svg.path(f"M{x - cw},{y - h / 2 - 5} L{x + cw},{y - h / 2 - 5} L{x + cw},{y - h / 2 + 7} L{x - cw},{y - h / 2 + 7} Z",
                 CLIP_METAL, INK, THIN * 0.8)


def officer_hand_down(svg: Svg, x: float, y: float, k: float = 1.0) -> None:
    """Длинная тонкая кисть висит вниз (e03): ладонь и четыре длинных пальца, большой палец к бедру."""
    for i in range(4):
        fx = x - 7 * k + i * 4.6 * k
        tip = y + (32 + (5 if i in (1, 2) else 0)) * k
        svg.path(f"M{fx:.1f},{y + 6 * k:.1f} L{fx - 0.5 + i * 0.4:.1f},{tip:.1f}", "none", INK, 5.6 * k)
        svg.path(f"M{fx:.1f},{y + 6 * k:.1f} L{fx - 0.5 + i * 0.4:.1f},{tip:.1f}", "none", O_SKIN, 5.6 * k - LINE * 1.2)
    svg.path(f"M{x + 9 * k:.1f},{y:.1f} L{x + 13 * k:.1f},{y + 18 * k:.1f}", "none", INK, 5.6 * k)
    svg.path(f"M{x + 9 * k:.1f},{y:.1f} L{x + 13 * k:.1f},{y + 18 * k:.1f}", "none", O_SKIN, 5.6 * k - LINE * 1.2)
    svg.ellipse(x, y, 10 * k, 13 * k, O_SKIN, INK, LINE * 0.8)
    svg.ellipse(x, y + 1, 8.5 * k, 11 * k, O_SKIN, None)


def officer_cap(svg: Svg, view: str) -> None:
    if view == "side":
        crown = "M172,52 C165,44 165,34 174,28 C188,20 214,14 236,13 C247,14 249,25 243,36 C241,42 239,48 237,52 Z"
        soft_shape(svg, crown, O_CAP, [(206, 30, 28, 12, O_CAP_HI)], LINE * 0.8)
        svg.path("M174,50 L237,50 C239,56 239,60 237,64 L174,64 C172,60 172,56 174,50 Z", O_CAP_BAND, INK, LINE * 0.8)
        svg.path("M230,62 C242,62 254,64 262,68 C264,71 262,74 257,74 C247,72 237,71 228,71 Z", O_VISOR, INK, LINE * 0.8)
        return
    if view == "front":   # 3/4 вправо по сетке e03: тулья задрана вверх-вправо, околыш и козырёк вправо
        soft_shape(svg, smooth_d(O_CROWN_PTS), O_CAP, [(214, 34, 34, 12, O_CAP_HI)], LINE * 0.8)
        svg.path("M178,57 L247,50 C249,56 249,62 248,67 L181,73 C178,68 178,62 178,57 Z", O_CAP_BAND, INK, LINE * 0.8)
        svg.path(smooth_d(O_VISOR_PTS), O_VISOR, INK, LINE * 0.8)
        svg.ellipse(231, 59, 5.0, 5.0, BRASS, INK, THIN)   # простой диск вместо кокарды
        svg.ellipse(231, 59, 1.8, 1.8, INK, None)
        return
    crown = "M160,52 C150,46 149,34 157,28 C170,20 186,15 200,15 C214,15 230,20 243,28 C251,34 250,46 240,52 Z"
    soft_shape(svg, crown, O_CAP, [(184, 30, 30, 12, O_CAP_HI)], LINE * 0.8)
    svg.path("M166,50 L234,50 C236,56 236,60 234,64 L166,64 C164,60 164,56 166,50 Z", O_CAP_BAND, INK, LINE * 0.8)


def officer_face(svg: Svg) -> None:
    """Лицо в 3/4 вправо (e03): глаза под тяжёлыми бровями, нос-«луковица» за контуром, усы-подкова, гримаса."""
    for x, y in ((219, 91), (241, 92)):
        svg.path(f"M{x - 5.5},{y} Q{x},{y - 4} {x + 5.5},{y} Q{x},{y + 3} {x - 5.5},{y} Z", "#FFFFFF", INK, FACE * 0.6)
        svg.ellipse(x + 1.5, y, 1.7, 1.7, INK, None)
        svg.path(f"M{x - 6},{y - 1} Q{x},{y - 5} {x + 6},{y - 1}", width=FACE * 0.8)             # тяжёлое веко
        svg.path(f"M{x - 4},{y + 5} Q{x},{y + 7.5} {x + 4},{y + 5}", width=FACE * 0.45)           # мешки
    svg.path("M211,84 Q218,82 226,87", "none", INK, FACE * 1.5)                                # брови сдвинуты
    svg.path("M235,88 Q242,81 250,83", "none", INK, FACE * 1.5)
    svg.path("M206,98 C204,112 205,126 210,136", width=FACE * 0.8)                              # впалая щека
    svg.path("M200,86 Q203,84 206,87", width=FACE * 0.6)
    # Усы-подкова: от-под носа вниз-влево свисающий конец и короткий правый.
    # Гримаса прямо под усами (e03): оскал — белые зубы под аркой усов, сдвинут вправо; усы ложатся на верх зубов.
    svg.path("M222,129.5 C227,124.5 236,124.5 243.5,130 C237,135 228,135.5 222,129.5 Z", "#FFFFFF", INK, FACE * 0.8)
    svg.path("M229.5,126.5 L230,133.6 M236,126.5 L236.4,134", width=FACE * 0.4, extra=' opacity="0.6"')
    must = smooth_d([(233, 109), (222, 110), (213, 115), (208, 122), (204, 132), (211, 131.5), (218, 130), (224, 127.5),
                     (232, 125.5), (240, 126.5), (247, 131.5), (252, 128), (250, 119), (243, 112)])
    soft_shape(svg, must, O_HAIR, [(224, 115, 12, 5, O_HAIR_HI)], FACE * 0.9)
    for x in (214, 220, 227, 234, 241):
        svg.path(f"M{x},{118 if x > 216 else 121} l{-1.5 if x < 228 else 1.2},6", width=FACE * 0.45)
    svg.path("M226,139 Q231,141 236.5,138.5", width=FACE * 0.6)                                    # нижняя губа
    soft_shape(svg, smooth_d(O_NOSE_PTS), O_SKIN, [(251, 116, 10, 7, O_SKIN_HI), (262, 134, 10, 6, O_SKIN_LO)],
               FACE * 1.0)
    svg.path("M248,136 Q252,133 256,136", width=FACE * 0.6)                                         # ноздря


def officer(view: str) -> str:
    svg = Svg()
    if view == "front":
        with svg.group(O_GRID):
            officer_front(svg)
        return svg.text()
    with svg.group(O_SIDE_K):
        officer_turned(svg, view)
    return svg.text()


def officer_front(svg: Svg) -> None:
    officer_boots(svg)
    soft_shape(svg, smooth_d(O_COAT_PTS), O_COAT, [(170, 240, 30, 80, O_COAT_HI), (130, 440, 18, 70, O_COAT_LO),
                                                    (262, 450, 16, 50, O_COAT_LO)])
    svg.path("M200,226 C205,300 209,400 212,488", width=THIN * 0.9)                           # борт
    svg.path("M128,484 Q200,476 270,466", width=THIN * 0.5, extra=' opacity="0.45"')
    for x, y in ((172, 240), (181, 268), (182, 310), (184, 355), (218, 355)):                 # два ряда пуговиц
        svg.ellipse(x, y, 4.0, 4.0, BRASS, INK, THIN * 0.7)
    svg.path(smooth_d([(124, 300), (150, 298), (150, 310), (125, 312)], k=0.04), O_COAT_LO, INK, THIN * 0.7)
    # Длинная наклонная шея из ворота (e03: 187–227 × 145–205): голова вынесена вперёд-вправо; рубашка — в вырезе
    # под шеей.
    # Стоячий воротник за шеей (e03: верх 157–190 × 137–150).
    svg.path(smooth_d([(154, 152), (160, 143), (184, 135), (204, 136), (222, 146), (226, 160), (206, 166), (184, 164),
                       (162, 168)], k=0.08), O_COAT_LO, INK, LINE * 0.8)
    svg.path("M178,168 L226,166 L200,230 Z", O_SHIRT, INK, LINE * 0.7)
    neck = smooth_d([(192, 136), (232, 140), (224, 160), (216, 184), (211, 212), (190, 214), (187, 190), (189, 160)])
    soft_shape(svg, neck, O_SKIN, [(220, 170, 6, 30, O_SKIN_LO)], LINE * 0.7)
    svg.path("M207,170 C210,166 216,167 217,173", width=FACE * 0.8)                          # кадык
    svg.path("M200,160 L198,206 M212,180 L208,206", width=FACE * 0.45, extra=' opacity="0.6"')
    # Лацканы плоские и ниже ворота: вырез до y≈230, «ступенька» на 198–214 (e03).
    for pts in ([(178, 168), (199, 230), (189, 233), (161, 214), (169, 205), (158, 197), (165, 182)],
                [(224, 166), (236, 182), (239, 198), (230, 202), (236, 210), (204, 234)]):
        svg.path(smooth_d(pts, k=0.04), O_COAT, INK, LINE * 0.8)
    # Левая (от зрителя) рука висит, кисть до середины бедра.
    soft_shape(svg, smooth_d(O_ARM_HANG), O_COAT, [(130, 260, 8, 60, O_COAT_HI)], LINE)
    svg.path("M117,340 L151,341", width=THIN * 0.8)
    officer_hand_down(svg, 134, 366, 1.25)
    # Правая рука согнута: плечо вниз к локтю (внешний край e03 ≈282), предплечье к груди; папка у груди.
    upper = smooth_d([(224, 166), (235, 178), (242, 196), (254, 222), (266, 260), (274, 298), (276, 326), (258, 334),
                      (251, 300), (241, 262), (231, 232), (223, 204)], k=0.1)             # плечо от угла плеча
    soft_shape(svg, upper, O_COAT, [(252, 250, 8, 40, O_COAT_HI), (264, 322, 10, 14, O_COAT_LO)], LINE)
    tube(svg, "M266,320 C258,330 242,318 228,298", 28, O_COAT, O_COAT_LO)
    # Погоны без знаков на скате плеч — поверх рукавов.
    for pts in ([(143, 168), (154, 174), (142, 204), (132, 198)], [(230, 177), (238, 174), (246, 200), (238, 204)]):
        svg.path(smooth_d(pts, k=0.04), O_STRAP, INK, THIN * 0.8)
    clipboard(svg, 239, 272, 64, 86, 8)
    svg.ellipse(216, 282, 13, 17, O_SKIN, INK, LINE * 0.8)
    for k in range(4):   # пальцы обхватывают край папки
        svg.path(f"M216,{272 + k * 7} L232,{270 + k * 7}", "none", INK, 7)
        svg.path(f"M216,{272 + k * 7} L232,{270 + k * 7}", "none", O_SKIN, 7 - LINE * 1.2)
    svg.ellipse(216, 283, 11.5, 15.5, O_SKIN, None)
    # Голова: седые вихры, ухо, узкое лицо в 3/4 (O_HEAD_SHIFT — посадка под фуражкой по наложению на e03), фуражка.
    with svg.group("translate(%d,%d)" % O_HEAD_SHIFT):
        for pts in (O_TUFT_L, O_TUFT_R):
            soft_shape(svg, smooth_d(pts, k=0.12), O_HAIR, [(pts[1][0], 88, 8, 10, O_HAIR_HI)], FACE * 0.9)
        svg.path("M197,100 C189,95 181,100 182,109 C183,118 190,122 198,119", O_SKIN, INK, FACE * 0.9)   # ухо
        svg.path("M194,104 C189,105 188,112 192,115", width=FACE * 0.6)
        soft_shape(svg, smooth_d(O_FACE_PTS), O_SKIN, [(226, 86, 16, 10, O_SKIN_HI), (204, 120, 7, 16, O_SKIN_LO)],
                   LINE * 0.9)
        officer_face(svg)
        # Без подбородка-«улыбки»: низ лица переходит в шею (e03) — контур лица между краями шеи закрыт кожей,
        # левая щека продолжается краем шеи, справа остаётся угол челюсти.
        svg.path("M196.5,140 L232.5,142.5 L229,160 L193.5,160 Z", O_SKIN, None)
        svg.path("M194,134 C193.5,144 192.5,153 191.5,162 M233.5,150.5 C231.5,154 230,157 228.5,161", width=LINE * 0.7)
    officer_cap(svg, "front")


def officer_turned(svg: Svg, view: str) -> None:
    if view == "back":
        officer_boots(svg, (175, 225))
        soft_shape(svg, OFFICER_BODY, O_COAT, [(222, 270, 40, 100, O_COAT_HI), (130, 440, 22, 110, O_COAT_LO)])
        svg.path("M200,178 L200,508", width=THIN * 0.8)                                    # шов и шлица
        svg.path("M200,390 L206,508", width=THIN * 0.6, extra=' opacity="0.6"')
        svg.path("M124,470 Q200,478 276,470", width=THIN * 0.5, extra=' opacity="0.4"')
        # Узкая шея между седым затылком и стоячим воротником.
        soft_shape(svg, "M191,119 C191,136 191,154 190,174 L210,174 C209,154 209,136 209,119 Z", O_SKIN,
                   [(204, 154, 6, 22, O_SKIN_LO)], LINE * 0.7)
        svg.path("M178,164 C190,159 210,159 222,164 L225,180 C212,175 188,175 175,180 Z", O_COAT_LO, INK, LINE * 0.8)
        for d in ("M142,186 L176,170 L180,181 L147,197 Z", mirror_d("M142,186 L176,170 L180,181 L147,197 Z")):
            svg.path(d, O_STRAP, INK, THIN * 0.8)
        # Со спины левая рука с папкой (согнута вперёд) — слева, за локтем виден край папки; правая висит справа.
        clipboard(svg, 115, 296, 10, 64, 10)
        tube(svg, "M148,192 C138,232 134,270 136,300", 30, O_COAT, O_COAT_LO)
        tube(svg, "M252,192 C260,240 264,320 264,402", 30, O_COAT, O_COAT_LO)
        svg.path("M252,396 L276,396", width=THIN * 0.8)
        officer_hand_down(svg, 264, 414)
        # Затылок — седая масса волос: светлые и тёмные пряди, низ темнее; по бокам торчат уши.
        with svg.group("translate(%d,%d)" % O_STOOP_BACK):
            for d in (O_TUFT, mirror_d(O_TUFT)):
                soft_shape(svg, d, O_HAIR, [(160, 76, 8, 12, O_HAIR_HI), (152, 98, 8, 10, O_HAIR_LO)], FACE * 0.9)
            nape = ("M170,60 C164,76 164,96 171,111 C176,120 184,124 190,122 L194,129 L199,122 L204,129 L209,122 "
                    "C217,124 225,119 229,111 C236,96 236,76 230,60 Z")
            soft_shape(svg, nape, O_HAIR, [(190, 78, 16, 16, O_HAIR_HI), (200, 122, 40, 22, O_HAIR_LO, 0.45)],
                       FACE * 1.0)
            for x in (181, 194, 207, 220):   # пряди редкие и мягкие: светлые, без чернил, между ними — тень
                bend = -4 if x < 200 else 4
                y0 = 68 + abs(x - 200) * 0.25
                strand = f"M{x},{y0:.0f} q{bend},16 {bend * 0.4:.1f},{38 - abs(x - 200) * 0.35:.0f}"
                svg.path(strand, "none", O_STRAND, FACE * 1.8, extra=' opacity="0.75"')
            for x in (188, 213):
                svg.path(f"M{x},84 q{-2 if x < 200 else 2},12 0,26", "none", O_HAIR_LO, FACE * 1.2,
                         extra=' opacity="0.55"')
            for d in (O_EAR, mirror_d(O_EAR)):
                svg.path(d, O_SKIN, INK, FACE * 0.9)
            officer_cap(svg, "back")
        return
    # side, лицом вправо
    officer_boots(svg, side=True)
    body = ("M190,168 C170,170 156,184 154,212 C152,300 150,420 146,508 L262,508 C256,420 248,320 240,240 "
            "C237,212 232,186 222,174 C214,168 200,166 190,168 Z")
    soft_shape(svg, body, O_COAT, [(216, 280, 20, 90, O_COAT_HI), (160, 440, 16, 110, O_COAT_LO)])
    svg.path("M232,236 C238,320 246,420 252,508", width=THIN * 0.8)                    # борт
    for y in (262, 302, 342, 382):
        svg.ellipse(230 + (y - 262) * 0.06, y, 3.4, 3.4, BRASS, INK, THIN * 0.7)
        svg.ellipse(214 + (y - 262) * 0.04, y, 3.0, 3.0, BRASS, INK, THIN * 0.6)
    svg.path("M200,390 L196,508", width=THIN * 0.5, extra=' opacity="0.5"')
    # Шея наклонена вперёд, кадык спереди.
    neck = "M205,140 C202,156 196,170 190,182 L218,182 C220,172 224,165 228,160 C230,154 227,149 224,145 Z"
    soft_shape(svg, neck, O_SKIN, [(202, 164, 6, 20, O_SKIN_LO)], LINE * 0.7)
    svg.path("M207,156 L203,178", width=FACE * 0.45, extra=' opacity="0.6"')
    svg.path("M218,170 C224,180 230,196 236,214 L227,218 L232,226 L240,240 C236,214 230,190 222,172 Z",
             O_COAT, INK, LINE * 0.8)                                                    # лацкан
    # Папка — в левой (дальней) руке у груди: перед бортом видны ребро папки и кисть; ближняя правая рука висит.
    clipboard(svg, 251, 272, 12, 76, -6)
    svg.ellipse(246, 290, 8.5, 9, O_SKIN, INK, LINE * 0.8)
    for k in range(3):   # пальцы обхватывают край папки
        svg.path(f"M246,{285 + k * 4} L257,{282 + k * 4}", "none", INK, 5)
        svg.path(f"M246,{285 + k * 4} L257,{282 + k * 4}", "none", O_SKIN, 5 - LINE * 1.2)
    svg.ellipse(246, 291, 7, 7.5, O_SKIN, None)
    tube(svg, "M202,190 C198,250 196,320 196,396", 30, O_COAT, O_COAT_LO)
    svg.path("M182,390 L210,390", width=THIN * 0.8)
    officer_hand_down(svg, 196, 408)
    svg.path("M180,174 L210,171 L212,182 L183,186 Z", O_STRAP, INK, THIN * 0.8)        # погон
    # Голова в профиль: седой затылок, ухо, узкое длинное лицо, «луковица» носа над висячими усами; вынесена вперёд.
    with svg.group("translate(%d,%d)" % O_STOOP_SIDE):
        tuft = ("M182,58 C172,62 166,70 163,80 L171,82 C165,88 163,96 165,105 L173,101 C175,107 179,111 184,113 "
                "L187,98 C189,84 191,72 196,60 Z")
        soft_shape(svg, tuft, O_HAIR, [(176, 80, 8, 14, O_HAIR_HI)], FACE * 0.9)
        head = ("M184,60 C180,74 180,92 184,106 C188,122 194,134 200,142 C206,148 214,151 219,147 "
                "C224,141 225,132 225,122 C227,108 229,92 229,76 C229,68 228,62 226,60 Z")
        soft_shape(svg, head, O_SKIN, [(216, 84, 10, 20, O_SKIN_HI), (206, 116, 8, 16, O_SKIN_LO)], LINE * 0.9)
        svg.path("M199,82 C191,79 186,87 188,95 C190,103 196,105 200,101", O_SKIN, INK, FACE * 0.9)   # ухо
        svg.path("M197,86 C193,88 193,95 196,98", width=FACE * 0.6)
        svg.path("M216,87 Q220,83.5 224,87 Q220,89.5 216,87 Z", "#FFFFFF", INK, FACE * 0.7)
        svg.ellipse(222, 87, 1.6, 1.6, INK, None)
        svg.path("M215,85.5 Q220,81 225,85", width=FACE * 1.1)
        svg.path("M213,79 Q219,75 227,72", "none", INK, FACE * 1.7)                        # бровь «домиком»
        svg.path("M212,98 C209,110 209,120 211,128", width=FACE * 0.8)                     # впалая щека
        svg.path("M219,141 Q223,142.5 227,140", width=FACE * 0.8)                         # рот
        must = ("M230,118 C222,117 214,123 210,133 C208,139 209,145 212,149 C214,143 218,137 224,135 "
                "C229,134 233,132 235,129 Z")
        soft_shape(svg, must, O_HAIR, [(220, 126, 6, 5, O_HAIR_HI)], FACE * 0.9)
        nose = ("M228,79 C233,89 236,97 239,104 C250,108 253,123 246,131 C241,136 233,136 229,131 "
                "C225,126 226,119 229,114 C229,104 229,92 228,79 Z")
        soft_shape(svg, nose, O_SKIN, [(240, 112, 6, 8, O_SKIN_HI), (240, 128, 8, 6, O_SKIN_LO)], FACE * 1.0)
        svg.path("M233,129 Q236,127 239,129", width=FACE * 0.6)
        officer_cap(svg, "side")


# ---------------------------------------------------------------- PEOPLE-01: жители города Н.
# ART-08: росгвардеец (второй пост у киоска, Officer2) по сетке e03 — третья фигура. Координаты форм сняты с кропа e03,
# приведённого к холсту по росту (верх берета y=20, подошвы y=580; ось x=200); G_GRID переносит сетку на холст так же,
# как P_GRID полицейского (рост облика 0,86 холста = 1,77 м при height_m 2,05 — на e03 оба одного роста). Фигура шире
# стандартного холста (e03: −30…430 по сетке), поэтому у его SVG viewBox шире: G_VIEW (текстура 896×1200; высота та же,
# CharacterSprite считает масштаб по высоте). Композиция e03: огромное круглое тело, плечи-горбы, руки толстыми
# дугами висят по бокам, чёрные перчатки у бёдер; бронежилет — плита с тремя рядами подсумков и лямками на плечах,
# боковые подсумки; штаны-шары, короткие голенища ботинок. Голова маленькая на фоне тела, жёлтое широкое лицо с
# брылями и складками у подбородка тонет в высоком вороте; берет сдвинут вправо. Без эмблем и надписей (решение
# владельца: реальные эмблемы не рисуем — кокарды на берете нет); форма серо-синяя.
G_GRID = P_GRID
G_VIEW = (-24, 448)   # x0 и ширина viewBox в единицах холста
G_SKIN, G_SKIN_LO, G_SKIN_HI = "#F0D594", "#D6B874", "#FAE7B8"      # пипетка e03: #F0D594
G_BERET, G_BERET_HI, G_BERET_LO = "#6A1C26", "#8A3440", "#4E141C"   # бордовый берет (e03: #621922)
G_SUIT, G_SUIT_HI, G_SUIT_LO = "#4A4E5C", "#5F6474", "#383B47"      # серо-синяя форма (e03 #434043, синее — по ТЗ)
G_VEST, G_VEST_HI, G_VEST_LO = "#202024", "#36363D", "#141416"      # бронежилет (e03: #1D1C1D)
G_GLOVE, G_BOOT = "#242426", "#171617"

G_BERET_PTS = [(160, 66), (157, 57), (165, 47), (182, 37), (205, 27), (228, 21), (248, 23), (257, 32), (256, 45),
               (247, 55), (224, 59), (192, 63)]
G_FACE_PTS = [(170, 62), (205, 59), (240, 59), (256, 68), (264, 84), (274, 100), (277, 116), (270, 133), (254, 146),
              (230, 153), (205, 155), (180, 151), (162, 141), (152, 125), (150, 105), (157, 88), (166, 74)]
G_COLLAR_PTS = [(146, 92), (160, 86), (166, 112), (178, 140), (205, 152), (240, 150), (262, 134), (272, 108),
                (286, 100), (294, 124), (288, 152), (270, 170), (228, 180), (184, 178), (158, 164), (144, 134)]
G_TORSO_PTS = [(150, 86), (200, 90), (270, 96), (322, 122), (352, 170), (366, 230), (368, 300), (362, 352), (200, 356),
               (72, 352), (70, 300), (76, 230), (88, 168), (112, 118)]
G_ARM_L = [(150, 86), (118, 88), (90, 100), (60, 124), (30, 160), (6, 204), (-16, 250), (-27, 300), (-24, 340),
           (-12, 368), (8, 380), (40, 382), (70, 378), (80, 352), (84, 302), (90, 252), (104, 210), (126, 168), (146, 130)]
G_ARM_R = [(282, 102), (320, 118), (350, 148), (380, 190), (404, 234), (421, 280), (428, 320), (423, 350), (412, 372),
           (394, 378), (366, 374), (357, 350), (355, 300), (351, 252), (339, 210), (318, 170), (298, 138)]
G_PANTS_PTS = [(78, 340), (200, 346), (362, 340), (373, 388), (376, 430), (367, 470), (346, 505), (314, 530), (238, 530),
               (232, 500), (216, 470), (200, 463), (184, 470), (170, 500), (165, 530), (94, 530), (68, 505), (50, 470),
               (45, 430), (51, 388)]
G_VEST_PTS = [(124, 186), (200, 184), (318, 186), (330, 222), (333, 282), (331, 346), (200, 350), (122, 346), (117, 282),
              (118, 222)]
G_POUCH_L = [(82, 268), (126, 268), (126, 346), (86, 346), (79, 306)]
G_STRAP_L = [(106, 94), (128, 88), (150, 90), (154, 190), (120, 190), (110, 150)]
G_STRAP_R = [(282, 104), (304, 108), (320, 116), (322, 190), (286, 190), (284, 150)]
G_ROWS = ((200, 240), (248, 290), (296, 336))          # три ряда подсумков плиты (e03: x 125–310)
G_GLOVE_L = [(2, 378), (30, 371), (62, 373), (75, 390), (73, 414), (62, 432), (36, 438), (12, 431), (1, 410)]
G_GLOVE_R = [(366, 372), (398, 369), (415, 384), (418, 410), (410, 428), (388, 433), (366, 427), (359, 400)]
G_THIGH_L = [(52, 430), (106, 428), (110, 486), (58, 488)]   # набедренные карманы (e03: 52–108 × 428–488)
G_BOOT_L = [(108, 520), (150, 520), (150, 548), (158, 562), (160, 576), (130, 580), (100, 580), (93, 572), (103, 557),
            (106, 540)]


def guard_boots(svg: Svg, back: bool = False) -> None:
    for pts in (G_BOOT_L, mirror_pts(G_BOOT_L, 204)):
        soft_shape(svg, smooth_d(pts, k=0.1), G_BOOT, [(sum(x for x, _ in pts) / len(pts), 540, 14, 10, "#3A3438")],
                   LINE * 0.9)
        x0 = min(x for x, _ in pts[:2])
        if not back:
            for k in range(3):   # шнуровка
                svg.path(f"M{x0 + 14},{530 + k * 8} L{x0 + 34},{532 + k * 8}", width=THIN * 0.6, extra=' opacity="0.7"')
        svg.path(f"M{x0 - 4},{571} L{x0 + 52},{571}", width=THIN * 0.6, extra=' opacity="0.6"')


def guard_pants(svg: Svg, back: bool = False) -> None:
    soft_shape(svg, smooth_d(G_PANTS_PTS), G_SUIT, [(120, 400, 50, 40, G_SUIT_HI), (300, 400, 50, 40, G_SUIT_HI),
                                                    (200, 470, 30, 30, G_SUIT_LO), (360, 470, 30, 50, G_SUIT_LO)])
    for x0, x1 in ((94, 165), (238, 314)):   # манжеты над ботинками
        svg.path(f"M{x0 + 4},518 Q{(x0 + x1) / 2},526 {x1 - 4},518", width=THIN * 0.8)
    svg.path("M200,463 L200,410" if not back else "M200,463 L200,360", width=THIN * 0.8)
    if back:
        svg.path("M120,400 Q160,440 196,446 M204,446 Q240,440 280,400", width=THIN * 0.7, extra=' opacity="0.7"')
    for pts in (G_THIGH_L, mirror_pts(G_THIGH_L, 204)):
        svg.path(smooth_d(pts, k=0.04), G_SUIT_LO, INK, THIN * 0.9)
        y = pts[0][1] + 10
        svg.path(f"M{pts[0][0] + 2},{y} L{pts[1][0] - 2},{y}", width=THIN * 0.6)
    for d in ("M70,480 Q90,500 120,506", "M330,480 Q314,500 286,506", "M150,380 Q170,396 176,420",
              "M250,380 Q232,396 228,420"):
        svg.path(d, width=THIN * 0.7, extra=' opacity="0.7"')   # складки штанов-«шаров»


def guard_arms(svg: Svg, back: bool = False) -> None:
    arm_l, arm_r = (mirror_pts(G_ARM_R, 204), mirror_pts(G_ARM_L, 204)) if back else (G_ARM_L, G_ARM_R)
    soft_shape(svg, smooth_d(arm_l), G_SUIT, [(20, 240, 30, 70, G_SUIT_HI), (60, 330, 30, 40, G_SUIT_LO)])
    soft_shape(svg, smooth_d(arm_r), G_SUIT, [(390, 240, 26, 70, G_SUIT_HI), (360, 330, 26, 40, G_SUIT_LO)])
    for d in ("M-4,236 Q20,250 46,242", "M-14,300 Q16,312 50,302", "M404,236 Q380,250 354,242",
              "M418,300 Q390,312 356,302", "M40,132 Q60,150 86,146", "M362,150 Q342,166 318,160",
              "M-22,272 Q2,280 30,272", "M424,272 Q400,280 372,272"):
        svg.path(d, width=THIN * 0.7, extra=' opacity="0.7"')   # складки рукавов
    for pts in ([(16, 186), (54, 172), (62, 200), (24, 214)], [(386, 186), (348, 172), (340, 200), (378, 214)]):
        svg.path(smooth_d(pts, k=0.04), G_SUIT_LO, INK, THIN * 0.8)   # нарукавные карманы без знаков
    svg.path("M10,362 Q36,372 70,366 M392,362 Q370,372 360,366", width=THIN * 0.8)   # манжеты


def guard_gloves(svg: Svg, back: bool = False) -> None:
    for pts, s in ((G_GLOVE_L, 1), (G_GLOVE_R, -1)):
        if back:
            pts, s = mirror_pts(pts, 204), -s
        cx = sum(x for x, _ in pts) / len(pts)
        soft_shape(svg, smooth_d(pts), G_GLOVE, [(cx - 6 * s, 392, 12, 12, "#3E3E44")], LINE * 0.9)
        for k in range(3):   # пальцы кулака
            y = 404 + k * 9
            svg.path(f"M{cx - 18:.0f},{y} Q{cx:.0f},{y + 3} {cx + 18:.0f},{y}", width=THIN * 0.6, extra=' opacity="0.8"')
        if not back:
            tx = max(x for x, _ in pts) if s > 0 else min(x for x, _ in pts)
            svg.path(f"M{tx - 10 * s},386 Q{tx + 2 * s},396 {tx - 6 * s},412", width=THIN * 0.8)   # большой палец


def guard_vest(svg: Svg, back: bool = False) -> None:
    for pts in (G_POUCH_L, mirror_pts(G_POUCH_L, 204)):
        soft_shape(svg, smooth_d(pts, k=0.06), G_VEST, [(sum(x for x, _ in pts) / len(pts), 290, 14, 20, G_VEST_HI)],
                   LINE * 0.9)
        x0 = min(x for x, _ in pts[:2]); x1 = max(x for x, _ in pts[:2])
        svg.path(f"M{x0 + 3},286 L{x1 - 3},286", width=THIN * 0.6, extra=' opacity="0.7"')
    soft_shape(svg, smooth_d(G_VEST_PTS, k=0.06), G_VEST, [(170, 210, 60, 20, G_VEST_HI), (300, 330, 30, 30, G_VEST_LO)],
               LINE)
    for y0, y1 in G_ROWS if not back else G_ROWS[1:]:
        svg.path(smooth_d([(130, y0), (306, y0), (308, y1), (128, y1)], k=0.03), G_VEST_HI if back else "#2A2A30", INK,
                 THIN * 0.9)
        if not back:
            for x in (184, 250):
                svg.path(f"M{x},{y0 + 2} L{x},{y1 - 2}", width=THIN * 0.5, extra=' opacity="0.6"')
    if back:
        svg.path(smooth_d([(140, 200), (264, 200), (266, 236), (138, 236)], k=0.03), "#2A2A30", INK, THIN * 0.9)
    for pts in (G_STRAP_L, G_STRAP_R) if not back else (mirror_pts(G_STRAP_R, 204), mirror_pts(G_STRAP_L, 204)):
        soft_shape(svg, smooth_d(pts, k=0.06), G_VEST, [(sum(x for x, _ in pts) / len(pts), 120, 10, 20, G_VEST_HI)],
                   LINE * 0.9)
        cx = sum(x for x, _ in pts) / len(pts)
        svg.path(f"M{cx - 10:.0f},150 L{cx + 10:.0f},150 M{cx - 10:.0f},166 L{cx + 10:.0f},166", width=THIN * 0.55,
                 extra=' opacity="0.7"')


def guard_beret(svg: Svg, back: bool = False) -> None:
    pts = mirror_pts(G_BERET_PTS, 210) if back else G_BERET_PTS
    soft_shape(svg, smooth_d(pts), G_BERET, [(220 if not back else 200, 34, 26, 10, G_BERET_HI),
                                            (190 if not back else 230, 58, 34, 6, G_BERET_LO)], LINE * 0.9)
    edge = [(162, 62), (190, 60), (224, 56), (250, 52)]
    if back:
        edge = mirror_pts(edge, 210)
    svg.path(smooth_d(edge, closed=False), width=THIN * 0.8)   # кант берета


def guard_face(svg: Svg) -> None:
    # e03: маленькие злые глаза у оси (брови к переносице вниз), короткий широкий нос, усы-щётка 0,22 ширины лица,
    # приоткрытый рот-скобка, носогубные складки к брылям, три складки подбородка; ухо слева под беретом.
    for x, brow in ((211, "M203,77 Q210,77 218,81.5"), (235, "M228,81.5 Q235,76.5 242,76")):
        svg.path(f"M{x - 6},83 Q{x},79.5 {x + 6},83 Q{x},86.5 {x - 6},83 Z", "#FFFFFF", INK, FACE * 0.7)
        svg.ellipse(x + (1.5 if x < 220 else -1.5), 83.2, 2.0, 2.0, INK, None)
        svg.path(brow, "none", INK, FACE * 2.2)
        svg.path(f"M{x - 4},88 Q{x},89.6 {x + 4},88", width=FACE * 0.45)
    svg.path("M201,86 L196,88 M201,89 L196,92 M245,86 L250,88 M245,89 L250,92", width=FACE * 0.5)   # «лапки»
    svg.path("M219,82 C218,86 216,90 216,93 C219,96 228,96 231,93 C231,90 229,86 228,82", width=FACE * 0.9)   # нос
    brush_moustache(svg, 209, 237, 96, 101.5)
    svg.path("M213,104.5 Q223,102 233,104.5 Q229,109 223,109 Q217,109 213,104.5 Z", "#6A3030", INK, FACE * 0.8)   # рот
    svg.path("M217,107.6 Q223,106.4 229,107.6", "none", "#B86A60", FACE * 0.7)                       # язык
    svg.path("M206,97 C203,106 203,114 206,122 M241,97 C245,106 246,113 245,121", width=FACE * 0.9)
    for d in ("M176,132 Q187,138 198,132", "M212,135 Q222,140 233,135", "M249,131 Q260,136 270,129"):
        svg.path(d, width=FACE * 0.8)   # складки брылей
    svg.path("M171,76 C164,72 159,78 162,86 C164,92 170,93 173,89", G_SKIN, INK, FACE * 0.9)   # ухо
    svg.path("M168,79 C165,81 166,86 169,87", width=FACE * 0.6)


def guard(view: str) -> str:
    svg = Svg(*G_VIEW)
    with svg.group(G_GRID):
        guard_figure(svg, view)
    return svg.text()


def guard_figure(svg: Svg, view: str) -> None:
    if view in ("front", "back"):
        back = view == "back"
        guard_boots(svg, back)
        guard_pants(svg, back)
        guard_arms(svg, back)
        soft_shape(svg, smooth_d(G_TORSO_PTS), G_SUIT, [(200, 140, 70, 40, G_SUIT_HI)])
        guard_vest(svg, back)
        guard_gloves(svg, back)
        if back:
            # Затылок: стриженая голова с ушами, складки шеи над высоким воротом; берет со спины.
            head = smooth_d(mirror_pts(G_FACE_PTS, 210))
            # Стриженый затылок (щетина темнее кожи), без складок-дуг: любая дуга на затылке читается ртом («лицом»).
            soft_shape(svg, head, G_SKIN, [(210, 74, 54, 20, "#C9AA68", 0.5), (210, 140, 50, 14, G_SKIN_LO)], LINE * 0.9)
            for x, s in ((156, -1), (264, 1)):
                svg.path(f"M{x},{74} C{x + 8 * s},70 {x + 12 * s},80 {x + 9 * s},88 C{x + 6 * s},93 {x},92 {x - 2 * s},88",
                         G_SKIN, INK, FACE * 0.9)
            # Со спины ворот сплошной полосой закрывает низ затылка (контур головы снизу не читается подбородком).
            soft_shape(svg, smooth_d([(146, 96), (176, 118), (210, 124), (244, 118), (276, 100), (292, 128), (286, 160),
                                      (260, 176), (214, 182), (166, 176), (142, 160), (140, 128)]), G_SUIT,
                       [(214, 150, 50, 10, G_SUIT_HI)], LINE * 0.9)
            svg.path(smooth_d([(150, 150), (214, 172), (280, 150), (284, 176), (214, 188), (146, 176)]), G_SUIT_LO, INK,
                     LINE * 0.8)
            guard_beret(svg, back=True)
            return
        # Ворот-стойка поднят до щёк: лицо утопает в нём; пуговица ворота под подбородком.
        soft_shape(svg, smooth_d(G_COLLAR_PTS), G_SUIT, [(214, 170, 50, 8, G_SUIT_HI), (150, 120, 8, 30, G_SUIT_LO)],
                   LINE * 0.9)
        svg.ellipse(215, 166, 5.0, 4.0, G_SUIT_LO, INK, THIN * 0.8)
        soft_shape(svg, smooth_d(G_FACE_PTS), G_SKIN, [(212, 80, 40, 18, G_SKIN_HI), (266, 112, 12, 24, G_SKIN_LO),
                                                     (158, 112, 10, 22, G_SKIN_LO), (214, 152, 60, 10, G_SKIN_LO),
                                                     (186, 128, 12, 5, G_SKIN_HI), (222, 131, 12, 5, G_SKIN_HI),
                                                     (260, 126, 10, 5, G_SKIN_HI)], LINE * 0.9)
        guard_face(svg)
        guard_beret(svg)
        return
    # side, лицом вправо: круглое тело в профиль, плита жилета спереди и сзади, рука висит у бока.
    body = smooth_d([(160, 98), (232, 102), (286, 126), (318, 170), (336, 230), (346, 300), (348, 360), (338, 410),
                     (312, 446), (270, 462), (150, 462), (112, 440), (94, 390), (90, 320), (96, 250), (110, 180),
                     (132, 126)])
    legs = smooth_d([(102, 400), (330, 400), (340, 450), (322, 492), (292, 520), (258, 532), (150, 532), (122, 512),
                     (102, 470)])
    back_boot = smooth_d([(138, 522), (200, 522), (204, 548), (230, 560), (238, 574), (228, 580), (140, 580), (134, 556)])
    soft_shape(svg, back_boot, "#0E0D0E", [], LINE * 0.9)
    boot = smooth_d([(156, 522), (238, 522), (242, 548), (276, 556), (298, 568), (292, 580), (200, 581), (154, 579),
                     (150, 556)])
    soft_shape(svg, boot, G_BOOT, [(196, 540, 18, 12, "#3A3438")], LINE * 0.9)
    for k in range(3):
        svg.path(f"M{214 + k * 7},{528 + k * 6} L{232 + k * 7},{526 + k * 6}", width=THIN * 0.6, extra=' opacity="0.7"')
    soft_shape(svg, legs, G_SUIT, [(250, 470, 40, 20, G_SUIT_HI), (140, 500, 20, 20, G_SUIT_LO)], LINE * 0.9)
    svg.path("M150,520 Q200,530 262,520 M214,470 Q224,500 220,530", width=THIN * 0.8)   # манжета, шаг ног
    soft_shape(svg, body, G_SUIT, [(260, 300, 50, 90, G_SUIT_HI), (110, 380, 20, 60, G_SUIT_LO)])
    for pts in ([(290, 182), (326, 204), (342, 268), (348, 340), (338, 362), (306, 358), (304, 280), (294, 222)],
                [(128, 182), (104, 220), (94, 300), (96, 352), (124, 356), (132, 280), (140, 220)]):
        soft_shape(svg, smooth_d(pts, k=0.08), G_VEST, [(pts[2][0], 260, 10, 40, G_VEST_HI)], LINE * 0.9)
    for y0, y1 in G_ROWS:
        svg.path(f"M{308},{y0 + 4} L{336},{y0 + 8} L{340},{y1} L{310},{y1 - 2} Z", "#2A2A30", INK, THIN * 0.8)
    svg.path(smooth_d([(140, 108), (190, 98), (232, 104), (240, 190), (150, 196)], k=0.08), G_VEST, INK, LINE * 0.8)   # лямка
    soft_shape(svg, smooth_d([(128, 262), (178, 262), (180, 346), (132, 346)], k=0.06), G_VEST, [], LINE * 0.9)
    arm = smooth_d([(170, 110), (226, 112), (254, 150), (262, 220), (260, 300), (252, 360), (236, 378), (194, 380),
                    (180, 340), (172, 270), (160, 200), (156, 140)])
    soft_shape(svg, arm, G_SUIT, [(226, 200, 20, 60, G_SUIT_HI), (200, 350, 30, 20, G_SUIT_LO)])
    svg.path("M184,240 Q214,252 252,240 M186,300 Q216,312 256,300", width=THIN * 0.7, extra=' opacity="0.7"')
    svg.path("M186,366 Q214,374 244,366", width=THIN * 0.8)
    soft_shape(svg, smooth_d([(190, 374), (238, 372), (252, 392), (250, 420), (232, 436), (204, 436), (188, 418)]),
               G_GLOVE, [(214, 390, 12, 10, "#3E3E44")], LINE * 0.9)
    svg.path("M200,410 Q220,414 244,408 M202,422 Q220,426 240,420", width=THIN * 0.6, extra=' opacity="0.8"')
    # Голова в профиль: высокий ворот, щёки-брыли вперёд, короткий нос, усы, берет на затылок.
    soft_shape(svg, smooth_d([(148, 100), (176, 92), (186, 130), (230, 156), (262, 150), (278, 128), (292, 140),
                              (284, 172), (240, 186), (186, 182), (150, 160)]), G_SUIT, [(240, 172, 30, 8, G_SUIT_HI)],
               LINE * 0.9)
    face = smooth_d([(176, 64), (226, 58), (252, 70), (262, 86), (272, 100), (280, 116), (276, 134), (258, 148),
                     (226, 156), (194, 150), (176, 130), (168, 100)])
    soft_shape(svg, face, G_SKIN, [(238, 84, 24, 14, G_SKIN_HI), (230, 140, 30, 10, G_SKIN_LO)], LINE * 0.9)
    svg.path("M248,83 Q255,79.5 262,83 Q255,86.5 248,83 Z", "#FFFFFF", INK, FACE * 0.7)
    svg.ellipse(258, 83.2, 2.0, 2.0, INK, None)
    svg.path("M244,77 Q254,77 263,81", "none", INK, FACE * 2.2)
    svg.path("M264,84 C272,88 278,94 274,98 C270,101 265,99 264,96", G_SKIN, INK, FACE)   # нос
    brush_moustache(svg, 256, 278, 99, 104.5)
    svg.path("M260,108 Q268,106 275,110", width=FACE)
    svg.path("M246,98 C250,110 254,120 262,126 M220,138 Q240,146 262,140", width=FACE * 0.8)
    svg.path("M194,80 C186,76 180,84 183,92 C186,99 193,99 196,94", G_SKIN, INK, FACE * 0.9)   # ухо
    soft_shape(svg, smooth_d([(168, 70), (166, 58), (176, 44), (200, 32), (226, 28), (244, 34), (250, 46), (246, 58),
                              (224, 62), (196, 66)]), G_BERET, [(212, 40, 22, 8, G_BERET_HI)], LINE * 0.9)
    svg.path(smooth_d([(170, 66), (200, 63), (230, 60), (248, 56)], closed=False), width=THIN * 0.8)


# Четыре прохожих в манере ART-01: тонкий контур LINE, плоская заливка с мягкими пятнами, мелкие черты лица
# (маленькие глаза с тяжёлым веком, складки щёк). Холст тот же, что у Илюши (height_m 2,0 в игре даёт одинаковый
# масштаб линий): ступни y=590, ось x=200. Рост задан верхом фигуры: мужик y≈50 (≈1,8 м), женщина y≈80,
# Бабка-жительница y≈130, пацан y≈210. Голова (верх убора — подбородок) ≈0,34–0,36 роста у взрослых, ≈0,42 у пацана
# (Бабка-квестодательница 0,36, Илюша 0,47). Лица — груша с брылями, высота к ширине 1,0–1,15, как у принятых.
# Отличия от квестовых: нет S-носа Илюши, нет чепца с кружевом, жабо и лимонного лица Бабки.
# Палитра — глухие зимние; один цветной акцент на силуэт: синий платок, рыжая шапка, бирюзовые санки, красный петушок.

RB_SKIN, RB_SKIN_LO, RB_SKIN_HI, RB_CHEEK = "#EDC6A6", "#D4A988", "#F8DEC8", "#DE8F7E"
RB_SCARF, RB_SCARF_HI, RB_SCARF_LO, RB_DOT = "#4A6FAE", "#6A8CC6", "#37568C", "#C8D3E6"   # акцент: синий платок
RB_COAT, RB_COAT_HI, RB_COAT_LO = "#5A4C43", "#6E5F54", "#45392F"
RB_FUR, RB_FUR_HI = "#3E3530", "#54493F"
RB_FELT, RB_FELT_LO = "#6C6863", "#57534F"                                        # серые валенки
RB_MITT = "#7A6E64"
RB_BAG, RB_BAG_HI = "#47474E", "#5C5C64"                                           # тёмная сумка
RB_CHECK, RB_CHECK_LINE = "#7A6B58", "#5B4E40"                                     # клетчатая сумка

RM_SKIN, RM_SKIN_LO, RM_SKIN_HI, RM_NOSE = "#E7B699", "#CC987C", "#F4D0BB", "#DA8C78"
RM_JACKET, RM_JACKET_HI, RM_JACKET_LO = "#2C2E34", "#41444D", "#1D1E23"            # чёрный пуховик
RM_HAT, RM_HAT_HI, RM_HAT_LO = "#C65F30", "#DE7E4B", "#A04A24"                    # акцент: рыжая вязаная шапка
RM_HAIR, RM_STUBBLE = "#4B3F37", "#8A7264"
RM_JEANS, RM_JEANS_LO = "#3B4457", "#2C3343"
RM_BOOT = "#1E1A1A"

RW_SKIN, RW_SKIN_LO, RW_SKIN_HI, RW_CHEEK = "#F2D4BF", "#DBB79F", "#FBE8DB", "#E79A8E"
RW_PARKA, RW_PARKA_HI, RW_PARKA_LO = "#4E4954", "#625C69", "#3B3741"              # длинная куртка
RW_FUR, RW_FUR_HI = "#A0968A", "#BFB5A8"
RW_HAIR = "#5A3F31"
RW_BOOT, RW_MITT = "#2A2323", "#6A6370"
RW_SLED, RW_SLED_HI, RW_SLED_LO = "#2E8E86", "#4DAEA4", "#22706A"                # акцент: бирюзовые санки
RW_RUNNER, RW_ROPE = "#3A3A40", "#CDBFA0"
RW_SIDE_SHIFT = 44   # профиль: фигура сдвинута вправо, санки за спиной длиной ≈0,64 м

RK_SKIN, RK_SKIN_LO, RK_SKIN_HI, RK_CHEEK = "#F2C6AC", "#DAA88D", "#FBDFCF", "#E5867C"
RK_JACKET, RK_JACKET_HI, RK_JACKET_LO = "#3D4B64", "#506080", "#2C384D"
RK_HAT, RK_HAT_HI, RK_STRIPE = "#C3373A", "#DB5A55", "#ECE5D6"                    # акцент: красный петушок
RK_HAIR = "#6A4A34"
RK_PANTS, RK_BOOT = "#2D2F35", "#2A2424"
RK_BAG, RK_BAG_HI, RK_BAG_LO = "#5C5047", "#706257", "#463C35"
RK_MITT = "#5F6470"


def smooth_d(pts: list[tuple[float, float]], closed: bool = True, k: float = 1 / 6) -> str:
    """Плавный контур через точки (Catmull-Rom -> кубические кривые): рисунок от руки без изломов."""
    n = len(pts)
    d = f"M{pts[0][0]:.1f},{pts[0][1]:.1f}"
    for i in range(n if closed else n - 1):
        p0 = pts[(i - 1) % n] if closed or i > 0 else pts[i]
        p1, p2 = pts[i], pts[(i + 1) % n]
        p3 = pts[(i + 2) % n] if closed or i + 2 < n else p2
        c1 = (p1[0] + (p2[0] - p0[0]) * k, p1[1] + (p2[1] - p0[1]) * k)
        c2 = (p2[0] - (p3[0] - p1[0]) * k, p2[1] - (p3[1] - p1[1]) * k)
        d += f" C{c1[0]:.1f},{c1[1]:.1f} {c2[0]:.1f},{c2[1]:.1f} {p2[0]:.1f},{p2[1]:.1f}"
    return d + (" Z" if closed else "")


def sym(half: list[tuple[float, float]], cx: float = 200) -> list[tuple[float, float]]:
    """Симметричная форма: half — от верхней точки на оси по правому краю до нижней точки на оси."""
    return half + [(2 * cx - x, y) for x, y in reversed(half[1:-1])]


def sym_d(half: list[tuple[float, float]], cx: float = 200) -> str:
    return smooth_d(sym(half, cx))


def mitten(svg: Svg, x: float, y: float, color: str, side: int, r: float = 15) -> None:
    """Варежка: овал ладони и большой палец к оси фигуры."""
    svg.ellipse(x - side * r * 0.75, y - r * 0.2, r * 0.42, r * 0.6, color, INK, LINE * 0.8)
    svg.ellipse(x, y, r * 0.85, r, color, INK, LINE * 0.8)
    svg.path(f"M{x - r * 0.7:.1f},{y - r * 0.55:.1f} Q{x:.1f},{y - r * 0.35:.1f} {x + r * 0.7:.1f},{y - r * 0.55:.1f}",
             width=THIN * 0.7)


def small_eye(svg: Svg, x: float, y: float, w: float = 7, look: float = 0.0, lid: bool = True) -> None:
    """Маленький глаз-миндалина с тяжёлым веком (манера V01/V02)."""
    svg.path(f"M{x - w},{y} Q{x},{y - w * 0.6:.1f} {x + w},{y} Q{x},{y + w * 0.5:.1f} {x - w},{y} Z", "#FFFFFF", INK, FACE * 0.8)
    svg.ellipse(x + look, y, w * 0.3, w * 0.3, INK, None)
    if lid:
        svg.path(f"M{x - w - 1:.1f},{y - 1.5:.1f} Q{x},{y - w * 0.95:.1f} {x + w + 1:.1f},{y - 1.5:.1f}", width=FACE * 1.1)


# ---- Бабка-жительница: платок, пальто, валенки, две сумки

RB_PLATOK = [(200, 124), (242, 128), (274, 148), (290, 190), (294, 240), (286, 284), (264, 308), (230, 320), (200, 322)]
RB_FACE = [(200, 166), (236, 168), (260, 188), (270, 224), (272, 258), (262, 288), (234, 306), (200, 312)]
RB_COAT_HALF = [(200, 286), (250, 288), (284, 304), (300, 346), (312, 428), (324, 506), (330, 546), (296, 556), (200, 558)]
RB_FELT_X = (174, 226)


def rb_felt_boots(svg: Svg, xs: tuple[float, float] = RB_FELT_X) -> None:
    for x, s in zip(xs, (-1, 1)):
        d = smooth_d([(x - 16, 540), (x + 16, 540), (x + 18, 572), (x + 22 * (1 if s > 0 else 0.6), 586),
                      (x + 4 * s, 591), (x - 14, 590), (x - 20, 580)])
        soft_shape(svg, d, RB_FELT, [(x - 6, 556, 8, 14, "#7E7A74")], LINE * 0.9)


def rb_bag(svg: Svg, x: float, top: float, checked: bool, hand_y: float) -> None:
    """Хозяйственная сумка: трапеция со скруглённым низом, ручки к варежке."""
    d = smooth_d([(x - 34, top), (x + 34, top), (x + 40, top + 40), (x + 42, top + 76), (x + 30, top + 86),
                  (x - 30, top + 86), (x - 42, top + 76), (x - 40, top + 40)], k=0.12)
    if checked:
        svg.path(d, RB_CHECK, None)
        svg._clip += 1
        cid = f"k{svg._clip}"
        svg.defs.append(f'<clipPath id="{cid}"><path d="{d}"/></clipPath>')
        lines = "".join(f"M{x - 50 + i * 16},{top - 4} L{x - 50 + i * 16},{top + 92} " for i in range(7))
        lines += "".join(f"M{x - 50},{top + 8 + i * 16} L{x + 50},{top + 8 + i * 16} " for i in range(6))
        svg.add(f'<g clip-path="url(#{cid})"><path d="{lines}" fill="none" stroke="{RB_CHECK_LINE}" stroke-width="4"/></g>')
        svg.path(d, "none", INK, LINE)
    else:
        soft_shape(svg, d, RB_BAG, [(x - 14, top + 30, 18, 30, RB_BAG_HI)])
        svg.path(f"M{x - 30},{top + 10} L{x + 30},{top + 10}", width=THIN * 0.8)        # молния
    for dx in (-18, 18):
        svg.path(f"M{x + dx},{top + 2} C{x + dx * 0.9:.1f},{hand_y - 4} {x + dx * 0.3:.1f},{hand_y - 8} {x},{hand_y}",
                 "none", INK, 5)
        svg.path(f"M{x + dx},{top + 2} C{x + dx * 0.9:.1f},{hand_y - 4} {x + dx * 0.3:.1f},{hand_y - 8} {x},{hand_y}",
                 "none", RB_BAG if not checked else RB_CHECK_LINE, 5 - LINE * 1.2)


def rb_platok_dots(svg: Svg, pts: list[tuple[float, float]]) -> None:
    for x, y in pts:
        svg.ellipse(x, y, 3.4, 3.4, RB_DOT, None)


def resident_babka(view: str) -> str:
    svg = Svg()
    if view in ("front", "back"):
        back = view == "back"
        rb_felt_boots(svg)
        coat = sym_d(RB_COAT_HALF)
        spots = [(200 + (40 if back else -50), 380, 70, 110, RB_COAT_HI), (76, 470, 30, 90, RB_COAT_LO),
                 (324, 470, 30, 90, RB_COAT_LO)]
        soft_shape(svg, coat, RB_COAT, spots)
        svg.path("M84,522 Q200,536 316,522", width=THIN * 0.7, extra=' opacity="0.6"')         # подол
        if back:
            svg.path("M200,330 L200,556", width=THIN * 0.8)
            svg.path("M150,452 Q200,462 250,452", width=THIN * 0.7)                             # хлястик
            svg.ellipse(158, 456, 4, 4, RB_FUR, INK, THIN * 0.6)
            svg.ellipse(242, 456, 4, 4, RB_FUR, INK, THIN * 0.6)
        else:
            svg.path("M200,318 L200,556", width=THIN * 0.8)
            for y in (352, 404, 456):
                svg.ellipse(206, y, 6.5, 6.5, RB_FUR, INK, THIN * 0.8)
            for x0 in (130, 270):                                                             # клапаны карманов
                svg.path(f"M{x0 - 22},450 L{x0 + 22},446", width=THIN * 0.8)
        # Руки в рукавах пальто висят у боков, в варежках ручки сумок; клетчатая — в левой руке.
        left_bag_checked = back
        for s in (-1, 1):
            sx = 200 + s * 72
            hx = 200 + s * 110
            tube(svg, f"M{sx},306 C{sx + s * 30},330 {hx - s * 4},380 {hx},432", 46, RB_COAT, RB_COAT_LO)
            svg.path(f"M{hx - 22},420 Q{hx},428 {hx + 22},420", width=THIN * 0.8)                 # обшлаг
            rb_bag(svg, hx + s * 6, 462, (s < 0) == left_bag_checked, 446)
            mitten(svg, hx, 446, RB_MITT, -s)
        # Меховой воротник под платком.
        svg.path(smooth_d([(140, 296), (200, 286), (260, 296), (262, 316), (200, 326), (138, 316)]),
                 RB_FUR, INK, LINE * 0.9)
        if back:
            # Платок со спины: купол головы и треугольный конец на спине с бахромой.
            tail = "M138,262 C150,300 176,346 200,384 C224,346 250,300 262,262 Z"
            soft_shape(svg, tail, RB_SCARF, [(186, 300, 30, 40, RB_SCARF_HI)])
            for i in range(9):
                t = i / 8
                x0, y0 = 160 + 40 * t, 324 + 60 * t
                x1, y1 = 240 - 40 * t, 324 + 60 * t
                for x, y in ((x0, y0), (x1, y1)):
                    svg.path(f"M{x:.1f},{y:.1f} l{-4 if x < 200 else 4},6", width=THIN * 0.7)
            soft_shape(svg, sym_d(RB_PLATOK), RB_SCARF, [(180, 180, 60, 60, RB_SCARF_HI), (262, 250, 30, 60, RB_SCARF_LO)])
            # Две складки к узлу (V), а не дуга: дуга с парой горошин над ней читалась со спины как «смайлик»
            # (повторная сверка стиля PEOPLE-01, P3). Горошины — без симметричной пары над складками.
            svg.path("M152,262 L196,292", width=THIN * 0.8)
            svg.path("M248,262 L204,292", width=THIN * 0.8)
            svg.path("M200,136 C196,180 196,230 200,280", width=THIN * 0.6, extra=' opacity="0.7"')
            rb_platok_dots(svg, [(166, 172), (232, 150), (200, 206), (156, 228), (244, 226), (190, 248),
                                 (176, 302), (226, 298), (200, 340)])
            return svg.text()
        soft_shape(svg, sym_d(RB_PLATOK), RB_SCARF, [(170, 170, 50, 50, RB_SCARF_HI), (270, 250, 24, 60, RB_SCARF_LO)])
        soft_shape(svg, sym_d(RB_FACE), RB_SKIN, [(178, 222, 38, 42, RB_SKIN_HI), (236, 280, 38, 32, RB_SKIN_LO),
                                                  (163, 264, 19, 14, RB_CHEEK), (237, 264, 19, 14, RB_CHEEK)])
        # Кромка платка поверх лба и щёк: лицо ≈0,25 роста, чтобы читалось с игровой дистанции.
        rim = "M136,288 C120,204 156,162 200,162 C244,162 280,204 264,288"
        svg.path(rim, "none", INK, 16)
        svg.path(rim, "none", RB_SCARF, 16 - LINE * 2)
        rb_platok_dots(svg, [(176, 142), (224, 142), (200, 134), (146, 164), (254, 164), (122, 214), (278, 214),
                             (116, 258), (284, 258)])
        # Лицо: глазки с морщинками, нос пуговкой, запавший рот, складки.
        for x, s in ((179, -1), (221, 1)):
            small_eye(svg, x, 228, 7, 0.9 * s * -1)
            svg.path(f"M{x + 11 * s},223 l{6 * s},-4 M{x + 11 * s},229 l{7 * s},0", width=FACE * 0.6)  # «гусиные лапки»
        svg.path("M196,236 C191,251 194,260 201,260 C209,260 210,251 205,244", RB_SKIN, INK, FACE)
        svg.path("M183,280 Q200,274 217,280", width=FACE)
        for x in (190, 200, 210):
            svg.path(f"M{x},{276 if x != 200 else 275} l0,-5", width=FACE * 0.5)
        svg.path("M175,251 C168,266 170,281 178,291 M225,251 C232,266 230,281 222,291", width=FACE * 0.8)
        svg.path("M188,302 Q200,306 212,302", width=FACE * 0.7)
        # Узел платка под подбородком и два конца.
        svg.path("M194,319 L174,360 L192,356 Z M206,319 L224,362 L208,356 Z", RB_SCARF, INK, FACE)
        svg.ellipse(200, 318, 12, 10, RB_SCARF, INK, FACE)
    else:  # side, лицом вправо: сутулая, голова вынесена вперёд
        x = 206
        d = smooth_d([(x - 16, 540), (x + 14, 540), (x + 18, 568), (x + 42, 578), (x + 44, 590), (x - 16, 591), (x - 20, 576)])
        soft_shape(svg, d, RB_FELT, [(x - 4, 556, 8, 14, "#7E7A74")], LINE * 0.9)
        coat = smooth_d([(206, 290), (248, 296), (268, 326), (276, 390), (288, 470), (296, 546), (250, 556),
                         (150, 556), (112, 548), (116, 470), (122, 392), (134, 334), (160, 300)])
        soft_shape(svg, coat, RB_COAT, [(250, 400, 50, 110, RB_COAT_HI), (124, 450, 24, 100, RB_COAT_LO)])
        svg.path("M118,520 Q200,532 292,520", width=THIN * 0.7, extra=' opacity="0.6"')
        svg.path("M262,326 C270,400 280,480 288,548", width=THIN * 0.8)                          # борт
        for y in (352, 404, 456):
            svg.ellipse(266 + (y - 352) * 0.12, y, 6, 6, RB_FUR, INK, THIN * 0.8)
        svg.path("M150,470 Q130,474 118,480", width=THIN * 0.7)                                  # хлястик сбоку
        # Дальняя сумка выглядывает из-за спины, ближняя висит в руке.
        rb_bag(svg, 168, 470, True, 448)
        tube(svg, "M206,312 C186,350 194,400 206,432", 46, RB_COAT, RB_COAT_LO)
        svg.path("M186,420 Q206,430 228,420", width=THIN * 0.8)
        rb_bag(svg, 214, 462, False, 446)
        mitten(svg, 208, 446, RB_MITT, -1)
        svg.path(smooth_d([(172, 296), (226, 292), (262, 302), (256, 318), (200, 326), (160, 318)]), RB_FUR, INK, LINE * 0.9)
        face = smooth_d([(222, 188), (258, 194), (268, 216), (268, 236), (279, 248), (270, 256), (268, 268),
                         (262, 280), (258, 294), (236, 306), (206, 300), (200, 240)])
        soft_shape(svg, face, RB_SKIN, [(256, 226, 14, 24, RB_SKIN_HI), (252, 262, 12, 9, RB_CHEEK)])
        small_eye(svg, 256, 228, 5, 1.5)
        svg.path("M265,236 C272,240 278,246 274,252 C271,256 266,256 265,252", RB_SKIN, INK, FACE)  # нос пуговкой
        svg.path("M262,276 Q268,276 270,272", width=FACE)
        svg.path("M248,250 C244,262 248,274 256,282", width=FACE * 0.8)
        svg.path("M246,292 Q254,296 260,292", width=FACE * 0.7)
        platok = smooth_d([(214, 134), (252, 142), (272, 166), (270, 190), (244, 196), (226, 228), (222, 274),
                           (232, 306), (214, 318), (186, 322), (152, 316), (136, 292), (138, 236), (152, 176), (178, 146)])
        soft_shape(svg, platok, RB_SCARF, [(220, 170, 40, 30, RB_SCARF_HI), (168, 280, 30, 40, RB_SCARF_LO)])
        svg.path("M266,190 C246,196 232,214 228,240", width=THIN * 0.7)
        rb_platok_dots(svg, [(194, 150), (232, 158), (170, 190), (206, 200), (164, 240), (196, 252),
                             (174, 288), (206, 296)])
        svg.path("M234,302 L254,336 L238,336 Z", RB_SCARF, INK, FACE)                             # конец узла
        svg.ellipse(236, 304, 9, 8, RB_SCARF, INK, FACE)
    return svg.text()


# ---- Мужик: чёрный пуховик, рыжая вязаная шапка, руки в карманах

RM_FACE = [(200, 112), (238, 114), (258, 130), (264, 160), (272, 194), (268, 220), (250, 236), (226, 242), (200, 244)]
RM_BODY_HALF = [(200, 226), (250, 228), (292, 246), (318, 290), (330, 350), (334, 410), (326, 466), (300, 486), (200, 490)]
RM_HAT_HALF = [(200, 48), (238, 52), (264, 70), (276, 100), (278, 134), (200, 136)]


def rm_legs_front(svg: Svg) -> None:
    for x, s in ((160, -1), (240, 1)):
        soft_shape(svg, f"M{x - 38},470 L{x + 38},470 L{x + 34},566 L{x - 34},566 Z", RM_JEANS,
                   [(x + 20 * s, 520, 14, 50, RM_JEANS_LO)], LINE * 0.9)
        with svg.group(f"rotate({s * 6} {x} 580)"):
            d = smooth_d([(x - 36, 566), (x + 36, 566), (x + 42, 584), (x + 30, 592), (x - 30, 592), (x - 42, 584)], k=0.12)
            svg.path(d, RM_BOOT, INK, LINE * 0.9)
            svg.path(f"M{x - 30},{576} L{x + 30},576", "none", "#3A3434", THIN)
    svg.path("M200,476 L200,520", width=THIN * 0.7)


class Clip:
    """Всё, что нарисовано внутри with, обрезается формой d: стёжка и швы не вылезают за контур."""

    def __init__(self, svg: Svg, d: str) -> None:
        self.svg, self.d = svg, d

    def __enter__(self) -> Svg:
        self.svg._clip += 1
        cid = f"q{self.svg._clip}"
        self.svg.defs.append(f'<clipPath id="{cid}"><path d="{self.d}"/></clipPath>')
        self.svg.add(f'<g clip-path="url(#{cid})">')
        return self.svg

    def __exit__(self, *_exc) -> None:
        self.svg.add("</g>")


def puffer_quilt(svg: Svg, ys: tuple[float, ...], x0: float, x1: float, sag: float = 14, clip_d: str | None = None) -> None:
    if clip_d:
        with Clip(svg, clip_d):
            puffer_quilt(svg, ys, x0 - 20, x1 + 20, sag)
        return
    for y in ys:
        svg.path(f"M{x0},{y} Q{(x0 + x1) / 2},{y + sag} {x1},{y}", width=THIN * 0.9)


def rm_hat(svg: Svg, view: str) -> None:
    if view == "side":
        hat = smooth_d([(206, 48), (246, 54), (270, 76), (278, 108), (276, 134), (140, 134), (136, 102),
                        (148, 72), (172, 54)], k=0.15)
        cuff = smooth_d([(134, 106), (278, 106), (282, 136), (132, 138)], k=0.08)
    else:
        hat = sym_d(RM_HAT_HALF, 200)
        cuff = smooth_d([(124, 106), (200, 102), (276, 106), (280, 136), (200, 140), (120, 136)], k=0.1)
    soft_shape(svg, hat, RM_HAT, [(186, 70, 40, 22, RM_HAT_HI)], LINE * 0.9)
    for i in range(7):                                                                   # вязаные рубчики
        x = 150 + i * 17 if view != "side" else 158 + i * 17
        svg.path(f"M{x},{70 + abs(x - 205) * 0.25:.0f} L{x + (x - 205) * 0.06:.1f},104", "none", RM_HAT_LO, THIN * 1.2)
    soft_shape(svg, cuff, RM_HAT, [(180, 116, 50, 10, RM_HAT_HI)], LINE * 0.9)
    for i in range(14):
        x = 130 + i * 11
        svg.path(f"M{x},110 L{x},134", "none", RM_HAT_LO, THIN * 1.1)


def resident_man(view: str) -> str:
    svg = Svg()
    if view in ("front", "back"):
        back = view == "back"
        rm_legs_front(svg)
        body = sym_d(RM_BODY_HALF)
        if back:   # руки в карманах спереди: со спины предплечья уходят за корпус, видны плечо и локоть
            for s in (-1, 1):
                sx, ex = 200 + s * 88, 200 + s * 126
                tube(svg, f"M{sx},258 C{sx + s * 34},290 {ex + s * 4},340 {ex},372 C{ex - s * 4},396 {ex - s * 30},410 {ex - s * 60},420",
                     52, RM_JACKET, RM_JACKET_LO)
        soft_shape(svg, body, RM_JACKET, [(200 + (50 if back else -60), 330, 70, 70, RM_JACKET_HI),
                                          (74, 420, 30, 80, RM_JACKET_LO), (326, 420, 30, 80, RM_JACKET_LO)])
        puffer_quilt(svg, (292, 342, 392, 442), 76, 324, clip_d=body)
        svg.path("M88,474 Q200,494 312,474", width=THIN * 0.8)                               # резинка низа
        if not back:
            svg.path("M200,236 L200,488", width=THIN)                                        # молния
            svg.ellipse(200, 252, 4, 7, "#8C8C94", INK, THIN * 0.7)
        # Руки в карманах: локти в стороны, кисти спрятаны в косые карманы; со спины кисти не видны.
        for s in (-1, 1):
            sx, ex, px = 200 + s * 88, 200 + s * 128, 200 + s * 74
            if back:
                with Clip(svg, body):   # шов проймы
                    svg.path(f"M{200 + s * 100},250 C{200 + s * 118},290 {200 + s * 124},330 {200 + s * 122},360", width=THIN * 0.8)
            else:
                tube(svg, f"M{sx},258 C{sx + s * 34},290 {ex + s * 4},340 {ex},372 C{ex - s * 4},396 {px + s * 18},430 {px},444",
                     52, RM_JACKET, RM_JACKET_LO)
                svg.path(f"M{ex - 22},{352} Q{ex},{364} {ex + 22},{352}", width=THIN * 0.8)  # стёжка рукава
                slot = f"M{px - s * 30},{428} L{px + s * 14},{454} L{px + s * 10},{466} L{px - s * 34},{440} Z"
                svg.path(slot, RM_JACKET_LO, INK, LINE * 0.8)                              # карман поверх кисти
        if back:
            hood = smooth_d([(200, 222), (246, 226), (262, 250), (250, 284), (200, 296), (150, 284), (138, 250), (154, 226)])
            soft_shape(svg, hood, RM_JACKET, [(214, 246, 30, 18, RM_JACKET_HI)], LINE * 0.9)
            svg.path("M162,252 Q200,274 238,252", width=THIN * 0.9)
            nape = sym_d([(200, 108), (250, 112), (266, 140), (268, 180), (258, 210), (236, 226), (200, 230)])
            for x, s in ((132, -1), (268, 1)):                                                # уши торчат
                svg.path(f"M{x - s * 6},146 C{x + s * 14},140 {x + s * 16},178 {x - s * 4},182 Z", RM_SKIN, INK, FACE)
            soft_shape(svg, nape, RM_SKIN, [(220, 190, 30, 30, RM_SKIN_LO)])
            # Стрижка затылка почти до воротника: кожа — узкая полоса шеи, со спины не читается как лицо.
            hair = smooth_d([(136, 126), (200, 122), (264, 126), (268, 168), (262, 194), (246, 204), (222, 206),
                             (200, 204), (178, 206), (154, 204), (138, 194), (132, 168)], k=0.12)
            svg.path(hair, RM_HAIR, INK, FACE)
            for x0, y0 in ((158, 150), (176, 170), (200, 146), (224, 170), (242, 150), (188, 190), (212, 190)):
                svg.path(f"M{x0},{y0} l{(x0 - 200) * 0.04:.1f},9", "none", RM_STUBBLE, THIN * 0.8,
                         extra=' opacity="0.6"')                                              # штрихи машинки
            svg.path("M176,214 Q200,219 224,214", width=FACE * 0.7)                              # складка шеи
            svg.path(smooth_d([(150, 222), (200, 214), (250, 222), (254, 240), (200, 236), (146, 240)]), RM_JACKET,
                     INK, LINE * 0.9)                                                         # воротник-стойка
            rm_hat(svg, "back")
            return svg.text()
        # Воротник-стойка за подбородком.
        svg.path(smooth_d([(140, 236), (200, 222), (260, 236), (266, 262), (200, 256), (134, 262)]), RM_JACKET_LO,
                 INK, LINE * 0.9)
        for x, s in ((130, -1), (270, 1)):
            svg.path(f"M{x - s * 6},146 C{x + s * 14},140 {x + s * 16},178 {x - s * 4},182 Z", RM_SKIN, INK, FACE)
            svg.path(f"M{x + s * 2},154 C{x + s * 8},158 {x + s * 8},168 {x + s * 2},172", width=FACE * 0.6)
        face = sym_d(RM_FACE)
        soft_shape(svg, face, RM_SKIN, [(178, 150, 34, 34, RM_SKIN_HI), (250, 204, 24, 30, RM_SKIN_LO),
                                        (150, 204, 20, 28, RM_SKIN_LO), (168, 186, 12, 9, RM_NOSE), (232, 186, 12, 9, RM_NOSE)])
        # Щетина: точки по низу лица.
        for i in range(26):
            a = math.pi * (0.12 + 0.76 * (i % 13) / 12)
            r = 52 + (i // 13) * 10
            x, y = 200 + r * math.cos(a) * 1.18, 168 + r * math.sin(a) * 1.15
            if y > 196:
                svg.ellipse(x, y, 1.3, 1.3, RM_STUBBLE, None)
        for x, s in ((178, -1), (222, 1)):
            small_eye(svg, x, 164, 7, -0.8 * s)
            svg.path(f"M{x - 7},171 Q{x},175 {x + 7},171", width=FACE * 0.6)                    # мешки
            svg.path(f"M{x - 12 * s * -1:.0f},150 L{x + 10 * s * -1:.0f},152", "none", RM_HAIR, FACE * 3)  # брови щёткой
        nose = ("M194,160 C192,172 185,178 185,188 C185,199 195,203 200,200 C205,203 215,199 215,188 "
                "C215,178 208,172 206,160 Z")
        soft_shape(svg, nose, RM_SKIN, [(204, 192, 10, 8, RM_NOSE), (194, 182, 5, 6, RM_SKIN_HI)], FACE)
        svg.path("M191,196 Q194,193 197,196 M203,196 Q206,193 209,196", width=FACE * 0.6)
        svg.path("M183,218 Q200,213 217,218", width=FACE)
        svg.path("M183,218 l-3,3 M217,218 l3,3", width=FACE * 0.8)
        svg.path("M168,190 C162,204 166,218 176,228 M232,190 C238,204 234,218 224,228", width=FACE * 0.8)
        svg.path("M186,236 Q200,241 214,236", width=FACE * 0.7)
        rm_hat(svg, "front")
    else:  # side, лицом вправо
        soft_shape(svg, "M170,470 L238,470 L234,566 L174,566 Z", RM_JEANS, [(184, 520, 12, 50, RM_JEANS_LO)], LINE * 0.9)
        svg.path(smooth_d([(168, 562), (232, 560), (262, 572), (272, 586), (262, 592), (172, 592), (164, 580)], k=0.12),
                 RM_BOOT, INK, LINE * 0.9)
        body = smooth_d([(200, 226), (244, 232), (276, 262), (300, 320), (312, 390), (306, 450), (290, 484),
                         (200, 492), (128, 488), (106, 450), (104, 380), (114, 300), (138, 252), (168, 230)])
        soft_shape(svg, body, RM_JACKET, [(256, 330, 50, 70, RM_JACKET_HI), (114, 420, 20, 70, RM_JACKET_LO)])
        puffer_quilt(svg, (292, 342, 392, 442), 108, 306, 10, clip_d=body)
        with Clip(svg, body):
            svg.path("M110,476 Q200,494 300,478", width=THIN * 0.8)
            svg.path("M286,262 C304,330 308,400 296,490", width=THIN)                           # молния сбоку
        hood = smooth_d([(150, 224), (184, 226), (186, 262), (164, 290), (134, 286), (126, 250)])
        soft_shape(svg, hood, RM_JACKET, [(156, 248, 16, 16, RM_JACKET_HI)], LINE * 0.9)
        tube(svg, "M196,262 C172,300 166,352 182,390 C192,412 208,426 228,432", 52, RM_JACKET, RM_JACKET_LO)
        svg.path("M162,350 Q182,360 204,350", width=THIN * 0.8)
        svg.path("M220,412 L262,424 L262,440 L218,430 Z", RM_JACKET_LO, INK, LINE * 0.8)       # карман поверх кисти
        svg.path(smooth_d([(178, 232), (236, 228), (266, 240), (262, 262), (226, 256), (180, 258)]), RM_JACKET_LO,
                 INK, LINE * 0.9)
        head = smooth_d([(150, 118), (238, 114), (262, 132), (270, 162), (276, 178), (276, 206), (278, 224),
                         (268, 238), (248, 246), (214, 248), (172, 240), (148, 216), (140, 170)])
        soft_shape(svg, head, RM_SKIN, [(240, 160, 26, 30, RM_SKIN_HI), (180, 220, 30, 24, RM_SKIN_LO),
                                        (246, 196, 12, 9, RM_NOSE)])
        for i in range(14):
            x, y = 214 + (i % 7) * 8, 222 + (i // 7) * 10 - (i % 7) * 1.5
            svg.ellipse(x, y, 1.3, 1.3, RM_STUBBLE, None)
        svg.path(smooth_d([(146, 128), (196, 126), (198, 170), (176, 178), (150, 176), (140, 150)], k=0.12),
                 RM_HAIR, INK, FACE)                                                          # стрижка из-под шапки
        svg.path("M192,150 C178,146 172,168 180,178 C184,184 192,184 196,178 Z", RM_SKIN, INK, FACE)  # ухо
        svg.path("M186,158 C182,162 182,170 186,174", width=FACE * 0.6)
        small_eye(svg, 252, 162, 6, 1.5)
        svg.path("M240,150 L262,151", "none", RM_HAIR, FACE * 3)
        nose = "M266,168 C272,176 286,178 290,190 C294,202 284,210 274,206 C268,204 264,198 266,190 Z"
        soft_shape(svg, nose, RM_SKIN, [(282, 194, 9, 8, RM_NOSE)], FACE)                      # нос-картошка
        svg.path("M276,202 Q280,199 283,202", width=FACE * 0.6)
        svg.path("M258,222 L276,220 l3,3", width=FACE)
        svg.path("M244,180 C240,198 246,212 256,220", width=FACE * 0.8)
        svg.path("M206,240 Q230,248 252,242", width=FACE * 0.7)
        rm_hat(svg, "side")
    return svg.text()


# ---- Женщина: длинная куртка с капюшоном и мехом, тянет бирюзовые санки за верёвку (санки — часть облика)

RW_HOOD_HALF = [(200, 74), (250, 80), (284, 110), (299, 168), (299, 232), (286, 280), (256, 298), (200, 304)]
RW_FACE = [(200, 126), (240, 130), (261, 160), (267, 198), (261, 236), (236, 258), (200, 264)]
RW_PARKA_HALF = [(200, 280), (246, 282), (276, 300), (288, 340), (294, 420), (304, 500), (310, 534), (280, 542), (200, 544)]


def rw_boots(svg: Svg, xs: tuple[float, float] = (174, 226)) -> None:
    for x, s in zip(xs, (-1, 1)):
        d = smooth_d([(x - 16, 532), (x + 16, 532), (x + 18, 574), (x + 20, 588), (x - 20, 589), (x - 18, 574)], k=0.1)
        svg.path(d, RW_BOOT, INK, LINE * 0.9)
        svg.path(f"M{x - 16},548 Q{x},552 {x + 16},548", "none", "#4A4040", THIN)


def sled_front(svg: Svg, x0: float, x1: float, y: float) -> None:
    """Санки, видимые спереди из-за ног: сиденье из реек, стойки и загнутые полозья."""
    for x in (x0 + 8, x1 - 8):
        svg.path(f"M{x},{y + 14} L{x},{y + 40}", "none", INK, 6)
        svg.path(f"M{x},{y + 14} L{x},{y + 40}", "none", RW_RUNNER, 6 - LINE * 1.2)
        svg.path(f"M{x - 8},{y + 46} C{x - 14},{y + 36} {x - 4},{y + 28} {x + 2},{y + 34}", "none", INK, 5)
        svg.path(f"M{x - 8},{y + 46} C{x - 14},{y + 36} {x - 4},{y + 28} {x + 2},{y + 34}", "none", RW_RUNNER, 5 - LINE * 1.2)
    svg.path(f"M{x0 - 4},{y + 46} L{x1 + 4},{y + 46}", "none", INK, 6)
    svg.path(f"M{x0 - 4},{y + 46} L{x1 + 4},{y + 46}", "none", RW_RUNNER, 6 - LINE * 1.2)
    seat = f"M{x0},{y} L{x1},{y} L{x1},{y + 16} L{x0},{y + 16} Z"
    soft_shape(svg, seat, RW_SLED, [((x0 + x1) / 2, y + 4, (x1 - x0) / 2, 6, RW_SLED_HI)], LINE * 0.9)


def sled_back(svg: Svg, cx: float, y: float, half: float) -> None:
    """Санки со стороны спинки (ближе к камере): рейки сиденья в перспективе, спинка, полозья."""
    for s in (-1, 1):
        x = cx + s * (half - 6)
        svg.path(f"M{x},{y + 30} L{x + s * 4},{y + 58}", "none", INK, 7)
        svg.path(f"M{x},{y + 30} L{x + s * 4},{y + 58}", "none", RW_RUNNER, 7 - LINE * 1.2)
    seat = (f"M{cx - half + 14},{y} L{cx + half - 14},{y} L{cx + half},{y + 34} L{cx - half},{y + 34} Z")
    svg.path(seat, RW_SLED_LO, INK, LINE * 0.9)
    for i in range(4):                                                                     # рейки
        y0 = y + 2 + i * 8
        k = (y0 - y) / 34
        xl, xr = cx - half + 14 - 14 * k + 3, cx + half - 14 + 14 * k - 3
        svg.path(f"M{xl:.1f},{y0} L{xr:.1f},{y0} L{xr + 1.6:.1f},{y0 + 5} L{xl - 1.6:.1f},{y0 + 5} Z", RW_SLED, INK, THIN * 0.6)
    back = f"M{cx - half + 2},{y + 18} L{cx + half - 2},{y + 18} L{cx + half - 2},{y + 30} L{cx - half + 2},{y + 30} Z"
    soft_shape(svg, back, RW_SLED, [(cx, y + 20, half, 5, RW_SLED_HI)], LINE * 0.9)       # спинка
    for s in (-1, 1):
        svg.path(f"M{cx + s * (half - 4)},{y + 30} L{cx + s * (half - 4)},{y + 4}", "none", INK, 6)
        svg.path(f"M{cx + s * (half - 4)},{y + 30} L{cx + s * (half - 4)},{y + 4}", "none", RW_RUNNER, 6 - LINE * 1.2)
        svg.path(f"M{cx + s * (half + 2)},{y + 58} L{cx + s * (half - 6)},{y + 58}", "none", INK, 6)


def sled_side(svg: Svg, x0: float, x1: float, y: float) -> None:
    """Санки в профиль: полоз с загнутым передом справа, стойки, сиденье, спинка слева."""
    runner = f"M{x0},{y + 44} L{x1 - 14},{y + 44} C{x1},{y + 44} {x1 + 8},{y + 30} {x1 - 2},{y + 22}"
    svg.path(runner, "none", INK, 7)
    svg.path(runner, "none", RW_RUNNER, 7 - LINE * 1.2)
    for x in (x0 + 14, (x0 + x1) / 2, x1 - 22):
        svg.path(f"M{x},{y + 12} L{x},{y + 42}", "none", INK, 6)
        svg.path(f"M{x},{y + 12} L{x},{y + 42}", "none", RW_RUNNER, 6 - LINE * 1.2)
    seat = f"M{x0 + 2},{y} L{x1 - 10},{y} L{x1 - 12},{y + 14} L{x0 + 4},{y + 14} Z"
    soft_shape(svg, seat, RW_SLED, [((x0 + x1) / 2, y + 3, (x1 - x0) / 2, 5, RW_SLED_HI)], LINE * 0.9)
    for i in range(1, 5):
        x = x0 + 2 + (x1 - x0 - 12) * i / 5
        svg.path(f"M{x:.1f},{y + 1} L{x:.1f},{y + 13}", width=THIN * 0.6)
    svg.path(f"M{x0 + 4},{y} L{x0 - 2},{y - 30} L{x0 + 10},{y - 30} L{x0 + 14},{y} Z", RW_SLED, INK, LINE * 0.8)  # спинка


def rw_head_front(svg: Svg) -> None:
    soft_shape(svg, sym_d(RW_HOOD_HALF), RW_PARKA, [(180, 120, 50, 40, RW_PARKA_HI), (272, 240, 20, 40, RW_PARKA_LO)])
    ring = fur_d(superellipse(200, 196, 85, 94, 2.3, 24), 6)
    soft_shape(svg, ring, RW_FUR, [(180, 146, 46, 44, RW_FUR_HI)], LINE * 0.8)
    soft_shape(svg, sym_d(RW_FACE), RW_SKIN, [(182, 176, 32, 38, RW_SKIN_HI), (238, 234, 22, 24, RW_SKIN_LO),
                                              (166, 222, 15, 11, RW_CHEEK), (234, 222, 15, 11, RW_CHEEK)])
    fringe = smooth_d([(140, 162), (156, 134), (200, 122), (244, 134), (260, 162), (240, 154), (220, 160),
                       (200, 150), (180, 160), (160, 154)], k=0.12)
    svg.path(fringe, RW_HAIR, INK, FACE)                                                     # чёлка из-под капюшона
    # Лицо по паспорту ART-01: маленькие глаза с тяжёлыми веками, без бровей и ресниц, рот тёмной щелью, складки.
    for x, s in ((180, -1), (220, 1)):
        small_eye(svg, x, 190, 7, -0.6 * s)
        svg.path(f"M{x - 7},197 Q{x},201 {x + 7},197", width=FACE * 0.6)                    # мешки
    svg.path("M199,196 C196,210 194,216 199,220 C203,222 207,219 207,216", width=FACE)
    svg.path("M186,238 Q200,233 214,238", width=FACE)
    svg.path("M186,238 l-3,2 M214,238 l3,2", width=FACE * 0.8)
    svg.path("M172,216 C166,232 174,246 186,252 M228,216 C234,232 226,246 214,252", width=FACE * 0.6, extra=' opacity="0.7"')


def resident_woman(view: str) -> str:
    svg = Svg()
    parka = sym_d(RW_PARKA_HALF)
    if view == "front":
        sled_front(svg, 254, 370, 532)
        rw_boots(svg)
        soft_shape(svg, parka, RW_PARKA, [(170, 380, 60, 100, RW_PARKA_HI), (296, 470, 22, 70, RW_PARKA_LO)])
        puffer_quilt(svg, (346, 466), 100, 300, 10, clip_d=parka)
        svg.path("M200,300 L200,540", width=THIN)                                              # молния
        svg.path("M118,404 Q200,416 282,404", width=THIN * 0.9)                                 # кулиска на талии
        svg.ellipse(196, 412, 2.5, 4, RW_FUR, INK, THIN * 0.5)
        svg.ellipse(204, 412, 2.5, 4, RW_FUR, INK, THIN * 0.5)
        for x0 in (140, 260):
            svg.path(f"M{x0 - 22},446 L{x0 + 22},446 L{x0 + 22},458 L{x0 - 22},458 Z", RW_PARKA_LO, INK, THIN * 0.8)
        svg.path("M100,520 Q200,532 300,520", width=THIN * 0.7, extra=' opacity="0.6"')
        tube(svg, "M136,300 C118,340 112,390 114,434", 40, RW_PARKA, RW_PARKA_LO)               # левая рука вдоль тела
        mitten(svg, 114, 446, RW_MITT, 1, 13)
        tube(svg, "M264,300 C286,340 300,390 308,432", 40, RW_PARKA, RW_PARKA_LO)               # правая держит верёвку
        svg.path("M308,452 C320,490 318,520 312,540", "none", INK, 4.4)
        svg.path("M308,452 C320,490 318,520 312,540", "none", RW_ROPE, 4.4 - LINE * 1.2)
        mitten(svg, 308, 446, RW_MITT, -1, 13)
        rw_head_front(svg)
    elif view == "back":
        rw_boots(svg)
        soft_shape(svg, parka, RW_PARKA, [(206, 390, 78, 130, RW_PARKA_HI), (104, 470, 22, 70, RW_PARKA_LO)])
        puffer_quilt(svg, (346, 466), 100, 300, 10, clip_d=parka)
        svg.path("M150,300 Q200,316 250,300", width=THIN * 0.8)                                 # кокетка
        svg.path("M200,300 L200,544", width=THIN * 0.8)                                          # шов спинки
        svg.path("M118,404 Q200,416 282,404", width=THIN * 0.9)
        svg.path("M100,520 Q200,532 300,520", width=THIN * 0.7, extra=' opacity="0.6"')
        tube(svg, "M264,300 C282,340 288,390 286,434", 40, RW_PARKA, RW_PARKA_LO)              # левая рука (справа)
        mitten(svg, 286, 446, RW_MITT, -1, 13)
        tube(svg, "M136,300 C114,340 100,390 92,432", 40, RW_PARKA, RW_PARKA_LO)               # правая с верёвкой
        svg.path("M92,452 C104,490 150,520 182,536", "none", INK, 4.4)
        svg.path("M92,452 C104,490 150,520 182,536", "none", RW_ROPE, 4.4 - LINE * 1.2)
        mitten(svg, 92, 446, RW_MITT, 1, 13)
        # Капюшон со спины: мех выглядывает по краям, по центру шов и складка.
        ring = fur_d(superellipse(200, 188, 100, 110, 2.3, 26), 6)
        soft_shape(svg, ring, RW_FUR, [(200, 120, 60, 40, RW_FUR_HI)], LINE * 0.8)
        hood = sym_d([(200, 76), (248, 82), (280, 112), (292, 168), (290, 230), (278, 274), (252, 296), (200, 304)])
        soft_shape(svg, hood, RW_PARKA, [(206, 170, 70, 90, RW_PARKA_HI), (200, 284, 60, 18, RW_PARKA_LO)])
        svg.path("M200,84 C204,140 204,220 200,296", width=THIN * 0.8)
        svg.path("M150,262 Q200,282 250,262", width=THIN * 0.8)
        sled_back(svg, 200, 530, 74)                                                            # санки ближе к камере
    else:  # side, лицом вправо: идёт вправо, санки тянет за спиной слева
        sled_side(svg, 4, 196, 536)                                                             # ≈0,64 м при height_m 2,0
        with svg.group(f"translate({RW_SIDE_SHIFT},0)"):   # фигура правее оси, чтобы санки поместились на холст
            bx = 240
            for x, fill in ((bx - 6, "#1E1919"), (bx + 10, RW_BOOT)):
                d = smooth_d([(x - 16, 532), (x + 14, 532), (x + 16, 572), (x + 36, 580), (x + 36, 590), (x - 18, 590), (x - 18, 570)], k=0.1)
                svg.path(d, fill, INK, LINE * 0.9)
            body = smooth_d([(232, 280), (268, 288), (288, 316), (296, 380), (306, 460), (316, 532), (272, 544),
                             (196, 544), (160, 536), (168, 460), (176, 380), (182, 316), (200, 290)])
            soft_shape(svg, body, RW_PARKA, [(270, 400, 30, 100, RW_PARKA_HI), (176, 470, 16, 70, RW_PARKA_LO)])
            puffer_quilt(svg, (346, 466), 160, 316, 8, clip_d=body)
            svg.path("M290,330 C296,400 304,470 312,536", width=THIN)                               # молния по борту
            svg.path("M178,404 Q240,414 298,404", width=THIN * 0.9)
            svg.path("M164,520 Q240,532 314,520", width=THIN * 0.7, extra=' opacity="0.6"')
            svg.path("M262,446 L298,446 L298,458 L262,458 Z", RW_PARKA_LO, INK, THIN * 0.8)
            # Ближняя рука отведена назад к санкам, верёвка — от варежки к загнутому полозу.
            tube(svg, "M232,304 C214,340 196,390 178,428", 40, RW_PARKA, RW_PARKA_LO)
            svg.path("M172,450 C162,500 152,540 146,556", "none", INK, 4.4)
            svg.path("M172,450 C162,500 152,540 146,556", "none", RW_ROPE, 4.4 - LINE * 1.2)
            mitten(svg, 174, 442, RW_MITT, 1, 13)
            hood = smooth_d([(232, 82), (266, 92), (284, 122), (282, 148), (252, 160), (240, 210), (250, 270),
                             (250, 296), (210, 302), (172, 292), (158, 250), (160, 180), (176, 120), (200, 92)])
            soft_shape(svg, hood, RW_PARKA, [(206, 150, 30, 50, RW_PARKA_HI), (180, 260, 20, 30, RW_PARKA_LO)])
            face = smooth_d([(252, 140), (282, 150), (290, 176), (292, 194), (302, 210), (294, 216), (292, 232),
                             (286, 250), (270, 264), (244, 264), (236, 200)])
            soft_shape(svg, face, RW_SKIN, [(278, 180, 12, 24, RW_SKIN_HI), (270, 228, 10, 8, RW_CHEEK)])
            svg.path(smooth_d([(250, 140), (282, 146), (290, 166), (274, 162), (256, 170)], k=0.12), RW_HAIR, INK, FACE)
            small_eye(svg, 278, 190, 5, 1.5)
            svg.path("M273,197 Q279,200 284,197", width=FACE * 0.6)                          # мешок
            svg.path("M287,234 Q293,234 297,231", width=FACE)                                  # рот щелью
            # Мех капюшона дугой вокруг лица.
            fur = fur_d(superellipse(244, 204, 16, 80, 2.2, 16, rot=-4), 5)
            soft_shape(svg, fur, RW_FUR, [(242, 180, 8, 30, RW_FUR_HI)], LINE * 0.8)
    return svg.text()


# ---- Пацан: короткая куртка, шапка-петушок с полосами и кисточкой, рюкзак

RK_FACE = [(200, 266), (238, 270), (258, 292), (263, 322), (255, 350), (234, 368), (200, 374)]
RK_BODY_HALF = [(200, 360), (238, 362), (266, 376), (280, 410), (284, 460), (278, 500), (200, 506)]


def rk_hat_front(svg: Svg, back: bool = False) -> None:
    cone = smooth_d([(140, 288), (142, 254), (160, 228), (196, 214), (226, 210), (244, 200), (254, 210),
                     (246, 226), (256, 250), (260, 288)], k=0.16)
    stripes = "M120,236 L280,226 L280,240 L120,250 Z M120,262 L280,254 L280,266 L120,276 Z"
    svg.shape(cone, RK_HAT, lo=RK_STRIPE, lo_d=stripes, width=LINE * 0.9)
    soft_spot(svg, cone, 184 if not back else 220, 236, 30, 16, RK_HAT_HI, 0.6)
    cuff = smooth_d([(134, 276), (200, 270), (266, 276), (268, 302), (200, 306), (132, 302)], k=0.1)
    svg.shape(cuff, RK_HAT, lo=RK_STRIPE, lo_d="M120,286 L280,286 L280,292 L120,292 Z", width=LINE * 0.9)
    pts = [(252 + 11 * math.cos(a), 202 + 11 * math.sin(a)) for a in [i * math.tau / 9 for i in range(9)]]
    svg.path(fur_d(pts, 3), RK_STRIPE, INK, LINE * 0.8)                                     # кисточка-помпон


def rk_legs(svg: Svg) -> None:
    for x, s in ((176, -1), (224, 1)):
        svg.path(f"M{x - 22},500 L{x + 22},500 L{x + 20},568 L{x - 20},568 Z", RK_PANTS, INK, LINE * 0.9)
        with svg.group(f"rotate({s * 6} {x} 582)"):
            svg.path(smooth_d([(x - 22, 566), (x + 22, 566), (x + 28, 584), (x + 18, 591), (x - 18, 591), (x - 28, 584)], k=0.12),
                     RK_BOOT, INK, LINE * 0.9)


def resident_boy(view: str) -> str:
    svg = Svg()
    if view in ("front", "back"):
        back = view == "back"
        rk_legs(svg)
        body = sym_d(RK_BODY_HALF)
        soft_shape(svg, body, RK_JACKET, [(200 + (30 if back else -34), 420, 40, 50, RK_JACKET_HI),
                                          (124, 470, 16, 40, RK_JACKET_LO), (276, 470, 16, 40, RK_JACKET_LO)])
        puffer_quilt(svg, (404, 444), 122, 278, 10, clip_d=body)
        svg.path("M124,490 Q200,504 276,490", width=THIN * 0.8)
        for s in (-1, 1):
            sx, hx = 200 + s * 60, 200 + s * 86
            tube(svg, f"M{sx},382 C{sx + s * 22},400 {hx},430 {hx},474", 34, RK_JACKET, RK_JACKET_LO)
            mitten(svg, hx, 486, RK_MITT, -s, 12)
        if back:
            bag = smooth_d([(146, 384), (254, 384), (262, 400), (262, 484), (250, 496), (150, 496), (138, 484), (138, 400)], k=0.1)
            soft_shape(svg, bag, RK_BAG, [(222, 420, 30, 40, RK_BAG_HI), (146, 470, 12, 30, RK_BAG_LO)], LINE * 0.9)
            flap = smooth_d([(150, 388), (250, 388), (254, 430), (200, 440), (146, 430)], k=0.12)
            soft_shape(svg, flap, RK_BAG, [(220, 404, 26, 14, RK_BAG_HI)], LINE * 0.9)
            svg.path("M196,438 L204,438 L204,452 L196,452 Z", "#B9B4A6", INK, THIN * 0.7)        # застёжка
            svg.path("M152,462 L248,462", width=THIN * 0.7)
            svg.path("M160,476 L240,476 L238,494 L162,494 Z", RK_BAG_LO, INK, THIN * 0.7)        # кармашек
            for x, s in ((136, -1), (264, 1)):                                                  # уши из-под шапки
                svg.path(f"M{x - s * 4},300 C{x + s * 12},296 {x + s * 14},326 {x - s * 2},330 Z", RK_CHEEK, INK, FACE)
            nape = sym_d([(200, 262), (246, 266), (262, 296), (262, 332), (248, 356), (200, 364)])
            soft_shape(svg, nape, RK_SKIN, [(220, 340, 30, 20, RK_SKIN_LO)])
            hair = smooth_d([(140, 296), (200, 290), (260, 296), (258, 330), (244, 342), (232, 334), (220, 346),
                             (206, 336), (194, 346), (180, 336), (166, 344), (154, 334), (142, 330)], k=0.12)
            svg.path(hair, RK_HAIR, INK, FACE)
            svg.path(smooth_d([(150, 356), (200, 350), (250, 356), (252, 372), (200, 368), (148, 372)]), RK_JACKET_LO, INK, LINE * 0.9)
            rk_hat_front(svg, True)
            return svg.text()
        svg.path("M200,372 L200,504", width=THIN)                                               # молния
        for x in (158, 242):                                                                     # лямки рюкзака
            svg.path(f"M{x - 9},366 L{x + 9},366 L{x + 7},446 L{x - 7},446 Z", RK_BAG, INK, LINE * 0.8)
            svg.path(f"M{x - 8},436 L{x + 8},436", width=THIN * 0.7)
        svg.path(smooth_d([(150, 362), (200, 352), (250, 362), (254, 382), (200, 376), (146, 382)]), RK_JACKET_LO, INK, LINE * 0.9)
        for x, s in ((136, -1), (264, 1)):
            svg.path(f"M{x - s * 4},300 C{x + s * 12},296 {x + s * 14},326 {x - s * 2},330 Z", RK_CHEEK, INK, FACE)
        soft_shape(svg, sym_d(RK_FACE), RK_SKIN, [(184, 300, 26, 26, RK_SKIN_HI), (238, 346, 20, 18, RK_SKIN_LO),
                                                  (168, 332, 13, 10, RK_CHEEK), (232, 332, 13, 10, RK_CHEEK)])
        for x, s in ((182, -1), (218, 1)):
            small_eye(svg, x, 314, 6, 0.0, lid=False)
            svg.path(f"M{x - 7},309 Q{x},305 {x + 7},309", width=FACE * 0.9)
            svg.path(f"M{x - 8},300 Q{x},296 {x + 8},300", width=FACE * 0.8)                     # брови
        for x, y in ((174, 326), (180, 330), (220, 330), (226, 326), (186, 324), (214, 324)):  # веснушки
            svg.ellipse(x, y, 1.2, 1.2, "#B97A5E", None)
        svg.path("M197,318 C195,326 197,332 204,331 C208,330 208,326 205,323", RK_SKIN, INK, FACE)  # нос-курносый
        svg.ellipse(199, 330, 1.2, 1.2, INK, None)
        svg.ellipse(205, 330, 1.2, 1.2, INK, None)
        svg.path("M188,346 Q200,354 212,346 Q200,350 188,346 Z", INK, INK, FACE * 0.8)
        svg.path("M190,364 Q200,368 210,364", width=FACE * 0.6)
        rk_hat_front(svg)
    else:  # side, лицом вправо: рюкзак горбом за спиной, кисточка петушка назад
        svg.path("M176,500 L222,500 L220,568 L180,568 Z", RK_PANTS, INK, LINE * 0.9)
        svg.path(smooth_d([(176, 564), (222, 564), (246, 576), (252, 588), (240, 592), (178, 592), (172, 580)], k=0.12),
                 RK_BOOT, INK, LINE * 0.9)
        bag = smooth_d([(130, 380), (160, 378), (166, 400), (166, 480), (156, 494), (122, 492), (112, 470), (112, 400)], k=0.12)
        soft_shape(svg, bag, RK_BAG, [(126, 420, 12, 40, RK_BAG_HI)], LINE * 0.9)
        svg.path("M114,440 L150,440", width=THIN * 0.7)
        body = smooth_d([(200, 360), (232, 364), (254, 384), (266, 424), (266, 470), (256, 502), (200, 508),
                         (156, 504), (146, 470), (148, 420), (158, 384), (178, 364)])
        soft_shape(svg, body, RK_JACKET, [(240, 420, 22, 50, RK_JACKET_HI), (156, 470, 10, 30, RK_JACKET_LO)])
        puffer_quilt(svg, (404, 444), 150, 264, 8, clip_d=body)
        svg.path("M152,490 Q200,504 258,490", width=THIN * 0.8)
        svg.path("M164,372 L176,452", "none", INK, 12)                                          # лямка
        svg.path("M164,372 L176,452", "none", RK_BAG, 12 - LINE * 1.6)
        tube(svg, "M206,382 C212,410 214,440 210,472", 34, RK_JACKET, RK_JACKET_LO)
        mitten(svg, 210, 484, RK_MITT, -1, 12)
        svg.path(smooth_d([(170, 360), (226, 356), (252, 368), (248, 384), (210, 378), (172, 380)]), RK_JACKET_LO, INK, LINE * 0.9)
        head = smooth_d([(160, 270), (234, 268), (254, 288), (262, 314), (270, 324), (272, 334), (262, 338),
                         (260, 352), (244, 368), (210, 374), (172, 366), (154, 340), (150, 300)])
        soft_shape(svg, head, RK_SKIN, [(240, 304, 16, 20, RK_SKIN_HI), (234, 336, 12, 10, RK_CHEEK)])
        svg.path(smooth_d([(150, 296), (196, 290), (198, 332), (180, 340), (164, 338), (150, 326)], k=0.12), RK_HAIR, INK, FACE)
        svg.path("M200,306 C186,302 182,328 194,334 C198,336 202,334 204,330 Z", RK_CHEEK, INK, FACE)  # ухо
        small_eye(svg, 246, 314, 5, 1.2, lid=False)
        svg.path("M240,302 Q248,298 256,302", width=FACE * 0.8)
        svg.path("M262,316 C268,320 274,326 272,332 C270,334 266,334 264,332", RK_SKIN, INK, FACE)  # курносый
        svg.path("M252,350 Q260,354 264,348", width=FACE)
        for x, y in ((236, 330), (242, 334), (230, 334)):
            svg.ellipse(x, y, 1.2, 1.2, "#B97A5E", None)
        cone = smooth_d([(146, 290), (150, 252), (176, 226), (214, 218), (250, 232), (262, 260), (262, 290)], k=0.16)
        svg.shape(cone, RK_HAT, lo=RK_STRIPE, lo_d="M120,244 L280,240 L280,254 L120,258 Z M120,268 L280,266 L280,278 L120,280 Z",
                  width=LINE * 0.9)
        tip = smooth_d([(176, 228), (150, 222), (130, 230), (126, 244), (150, 240), (178, 240)], k=0.14)
        svg.path(tip, RK_HAT, INK, LINE * 0.9)                                                   # гребень петушка назад
        pts = [(122 + 11 * math.cos(a), 238 + 11 * math.sin(a)) for a in [i * math.tau / 9 for i in range(9)]]
        svg.path(fur_d(pts, 3), RK_STRIPE, INK, LINE * 0.8)
        cuff = smooth_d([(142, 280), (264, 280), (266, 304), (140, 306)], k=0.08)
        svg.shape(cuff, RK_HAT, lo=RK_STRIPE, lo_d="M120,289 L280,289 L280,295 L120,295 Z", width=LINE * 0.9)
    return svg.text()


# ---------------------------------------------------------------- PEOPLE-02: прохожие из роликов ШКЯ
# Шесть жителей по стоп-кадрам роликов Евы Морозовой (каталог docs/art/shkya_characters.md, PEOPLE-02 часть B):
# бабка в шубе и бабка в розовом с беретом («Как прожить жизнь так, чтобы на тебя не наорала бабка», 0:50),
# бабка в фиолетовом пальто (там же, 0:38), мужик в ушанке («Моложе я не стал.», 0:05 бок, 0:06 фас, 0:59 спина),
# пацан в вязаной шапке (там же, 0:25), дед-турист с рюкзаком («Случай в лесу», 0:04 фас, 0:00 спина).
# Метод ART-07: фигура из кадра приведена к холсту 400×600 (подошвы y=590, верх — по росту, ось по габариту x≈200),
# с неё сняты формы (убор и его посадка, лицо, одежда, предметы) и цвета пипеткой — ниже они константами.
# Рост при height_m 2,0: шуба 1,60 м (верх y=110), берет 1,70 (80), фиолетовая 1,63 (100), ушанка 1,80 (50),
# турист 1,78 (56), пацан 1,55 (125). Кадры роликов в репозиторий не входят (решение владельца 29.10).
# Зимняя адаптация: кофта бабки в берете — пальто того же цвета и формы; остальное как в роликах.

R_INK_SOFT = 0.8   # доля LINE для внутренних швов и рукавов


def r_shape(svg: Svg, pts: list[tuple[float, float]], fill: str, hi: str | None = None, lo: str | None = None,
            width: float = LINE, k: float = 1 / 6, light: int = -1) -> str:
    """Плавная форма по точкам с мягким светом сверху со стороны light (−1 слева) и тенью с другой стороны."""
    d = smooth_d(pts, k=k)
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
    w, h = x1 - x0, y1 - y0
    spots = []
    if hi:
        cx = x0 + w * (0.3 if light < 0 else 0.7)
        spots.append((round(cx, 1), round(y0 + h * 0.35, 1), round(w * 0.3, 1), round(h * 0.4, 1), hi))
    if lo:
        cx = x0 + w * (0.95 if light < 0 else 0.05)
        spots.append((round(cx, 1), round(y0 + h * 0.7, 1), round(w * 0.28, 1), round(h * 0.5, 1), lo))
    soft_shape(svg, d, fill, spots, width)
    return d


def r_bag(svg: Svg, hx: float, hy: float, w: float, h: float, fill: str, lo: str, dx: float = 0.0) -> None:
    """Пакет-майка в опущенной руке: ручки узлом у кисти (hx, hy), мягкое тело ниже (ширина w, высота h)."""
    cx = hx + dx
    body = [(hx - 7, hy + 4), (hx + 7, hy + 4), (cx + w * 0.42, hy + h * 0.32), (cx + w * 0.5, hy + h * 0.68),
            (cx + w * 0.36, hy + h * 0.96), (cx, hy + h), (cx - w * 0.36, hy + h * 0.96), (cx - w * 0.5, hy + h * 0.68),
            (cx - w * 0.42, hy + h * 0.32)]
    d = r_shape(svg, body, fill, None, lo, LINE * 0.9)
    svg.path(f"M{cx - w * 0.18:.1f},{hy + h * 0.45:.1f} Q{cx - w * 0.1:.1f},{hy + h * 0.7:.1f} {cx - w * 0.2:.1f},{hy + h * 0.9:.1f}",
             width=THIN * 0.7, extra=' opacity="0.7"')
    svg.path(f"M{cx + w * 0.12:.1f},{hy + h * 0.3:.1f} Q{cx + w * 0.24:.1f},{hy + h * 0.55:.1f} {cx + w * 0.16:.1f},{hy + h * 0.78:.1f}",
             width=THIN * 0.7, extra=' opacity="0.7"')
    for s in (-1, 1):   # «уши» пакета над кулаком
        svg.path(f"M{hx + s * 3:.1f},{hy + 2:.1f} C{hx + s * 12:.1f},{hy - 6:.1f} {hx + s * 12:.1f},{hy - 16:.1f} "
                 f"{hx + s * 3:.1f},{hy - 14:.1f} Z", fill, INK, LINE * 0.8)
    del d


def r_hand(svg: Svg, x: float, y: float, r: float, skin: str, side: int = 1) -> None:
    """Кисть-кулак: овал с большим пальцем к оси фигуры (side — сторона кисти от оси)."""
    svg.ellipse(x, y, r * 0.9, r, skin, INK, LINE * 0.8)
    svg.path(f"M{x - side * r * 0.85:.1f},{y - r * 0.2:.1f} q{-side * r * 0.25:.1f},{r * 0.5:.1f} {side * r * 0.25:.1f},{r * 0.7:.1f}",
             width=FACE * 0.7)


def r_boot(svg: Svg, x: float, top: float, w: float, color: str, side: int, toe: float = 10, sole: float = 590) -> None:
    """Сапог/ботинок: голенище от top, носок наружу на side·toe."""
    pts = [(x - w / 2, top), (x + w / 2, top), (x + w / 2 + 2 * (side > 0), sole - 18),
           (x + w / 2 + (toe if side > 0 else 2), sole - 6), (x + w / 2 + (toe if side > 0 else 0) - 4, sole),
           (x - w / 2 - (toe if side < 0 else 0) + 4, sole), (x - w / 2 - (toe if side < 0 else 2), sole - 6),
           (x - w / 2 - 2 * (side < 0), sole - 18)]
    r_shape(svg, pts, color, None, None, LINE * 0.9, k=0.12)
    svg.path(f"M{x - w / 2 + 3:.1f},{sole - 4:.1f} L{x + w / 2 - 3:.1f},{sole - 4:.1f}", width=THIN * 0.6, extra=' opacity="0.6"')


def r_mirror(pts: list[tuple[float, float]], axis: float = 200) -> list[tuple[float, float]]:
    return [(2 * axis - x, y) for x, y in pts]


# ---- Бабка в бордовой шубе с белыми пакетами и голубой «чалмой» (кадр 0:50: x 58–342 × 110–590 на холсте)

RS_TURBAN, RS_TURBAN_HI, RS_TURBAN_LO = "#A6D8E2", "#DDF2F4", "#7DB6C6"
RS_HAIR = "#E2A3C6"                                                                # розовая прядь из-под чалмы
RS_SKIN, RS_SKIN_HI, RS_SKIN_LO = "#E4EAE6", "#F7FAF8", "#BFC9C5"                # бледно-серое лицо
RS_COAT, RS_COAT_HI, RS_COAT_LO = "#9A666B", "#AE7C80", "#7E4F57"                # бордово-коричневая шуба
RS_FUR, RS_FUR_HI, RS_FUR_LO = "#B08C8E", "#C6A6A6", "#967274"                   # меховой воротник-шаль
RS_BOOT = "#463B3D"
RS_BAG, RS_BAG_LO = "#EEF6F4", "#C5DAD8"                                           # белые пакеты-майки
RS_TURBAN_PTS = [(152, 190), (140, 162), (142, 134), (158, 116), (188, 108), (222, 112), (244, 130), (250, 158),
                 (246, 188), (200, 181)]
RS_FACE_PTS = [(178, 181), (224, 181), (234, 198), (243, 220), (253, 240), (255, 255), (243, 265), (223, 263),
               (200, 270), (177, 263), (157, 265), (145, 255), (147, 240), (157, 220), (166, 198)]   # ART-08: груша — узкий лоб, брыли (кадр 0:50)
RS_FUR_PTS = [(126, 226), (166, 210), (238, 210), (272, 230), (288, 268), (284, 300), (244, 322), (200, 330),
              (152, 320), (112, 298), (108, 262)]
RS_COAT_PTS = [(140, 214), (256, 214), (278, 252), (292, 302), (302, 362), (309, 422), (313, 474), (308, 522),
               (200, 528), (92, 524), (70, 512), (67, 442), (71, 372), (83, 320), (100, 270), (120, 232)]
RS_BOOTS = ((136, 48, -1), (253, 52, 1))           # центр, ширина, носок
RS_BAGS = ((102, 452, 94, 94, 16), (306, 452, 56, 64, 9))   # кисть x, y; пакет w, h; сдвиг тела


def rs_turban(svg: Svg, back: bool = False) -> None:
    svg.ellipse(150 if not back else 250, 176, 14, 12, RS_HAIR, INK, LINE * 0.8)
    r_shape(svg, RS_TURBAN_PTS, RS_TURBAN, RS_TURBAN_HI, RS_TURBAN_LO)
    folds = ["M148,170 C166,140 198,122 238,122", "M156,184 C182,152 214,138 248,146", "M176,184 C200,162 226,156 248,170",
             "M160,124 C180,118 204,116 226,122"]
    for f in folds:
        svg.path(f if not back else mirror_d(f), width=THIN * 0.8)


def resident_shuba(view: str) -> str:
    svg = Svg()
    if view in ("front", "back"):
        back = view == "back"
        for x, w, s in RS_BOOTS:
            r_boot(svg, x if not back else 400 - x, 512, w, RS_BOOT, s if not back else -s, 8, 586)
        coat = r_shape(svg, RS_COAT_PTS if not back else r_mirror(RS_COAT_PTS), RS_COAT, RS_COAT_HI, RS_COAT_LO)
        del coat
        f = (lambda p: p) if not back else mirror_d
        svg.path(f("M122,262 C110,330 104,390 110,444"), width=LINE * R_INK_SOFT)      # рукава вдоль тела
        svg.path(f("M280,282 C292,340 298,392 298,440"), width=LINE * R_INK_SOFT)
        svg.path(f("M72,438 Q94,448 116,444"), width=THIN * 0.8)                          # обшлаги
        svg.path(f("M296,440 Q306,436 312,432"), width=THIN * 0.8)
        svg.path(f("M200,330 C202,400 204,470 202,526") if not back else "M200,250 C200,350 200,440 200,526",
                 width=THIN * 0.8)                                                        # борт / шов спинки
        if back:
            svg.path("M150,420 Q200,428 250,420", width=THIN * 0.8)                      # хлястик
            for x in (156, 244):
                svg.ellipse(x, 422, 4, 4, RS_FUR, INK, THIN * 0.6)
        for i, (hx, hy, w, h, dx) in enumerate(RS_BAGS):
            if back:
                hx, dx = 400 - hx, -dx
            r_bag(svg, hx, hy, w, h, RS_BAG, RS_BAG_LO, dx)
            r_hand(svg, hx, hy - 2, 10, RS_SKIN, 1 if hx > 200 else -1)
        if back:
            r_shape(svg, [(126, 222), (166, 192), (238, 192), (272, 222), (282, 262), (240, 284), (200, 288),
                          (160, 284), (114, 262)], RS_FUR, RS_FUR_HI, RS_FUR_LO)          # воротник-шаль со спины
            rs_turban(svg, True)
            svg.path("M170,188 C188,176 214,176 232,188", width=THIN * 0.8)
            return svg.text()
        r_shape(svg, RS_FUR_PTS, RS_FUR, RS_FUR_HI, RS_FUR_LO)
        svg.path("M152,320 C170,300 180,276 182,262 M244,322 C232,300 222,276 220,262", width=THIN * 0.7,
                 extra=' opacity="0.7"')
        svg.ellipse(205, 296, 7, 6, "#D9CFC4", INK, THIN * 0.8)                          # брошь
        r_shape(svg, RS_FACE_PTS, RS_SKIN, RS_SKIN_HI, RS_SKIN_LO)
        rs_turban(svg)
        # Лицо: глаза-щёлки под тяжёлыми веками близко к чалме, короткий нос, поджатый рот уголками вниз, брыли.
        small_eye(svg, 186, 204, 6, 0.6)
        small_eye(svg, 216, 204, 6, -0.4)
        svg.path("M178,194 Q186,190 194,194 M208,194 Q216,190 224,194", width=FACE)
        svg.path("M199,208 C195,220 196,227 202,228 C208,229 211,224 207,218", RS_SKIN, INK, FACE)
        svg.path("M192,242 Q202,236 212,242", width=FACE)
        svg.path("M194,244 Q202,248 210,244", width=FACE * 0.6)
        svg.path("M178,222 C170,236 170,250 178,262 M224,222 C232,236 232,250 224,262", width=FACE * 0.8)   # брыли
        svg.path("M192,258 Q200,262 208,258", width=FACE * 0.6)
    else:  # бок, лицом вправо: шуба колоколом, воротник-шаль, пакет в руке перед собой
        r_boot(svg, 196, 512, 50, RS_BOOT, 1, 12, 586)
        coat = [(162, 222), (226, 218), (250, 250), (264, 320), (276, 400), (288, 470), (294, 522), (200, 528),
                (112, 522), (114, 460), (124, 380), (136, 300), (146, 250)]
        r_shape(svg, coat, RS_COAT, RS_COAT_HI, RS_COAT_LO, light=1)
        svg.path("M252,300 C262,380 276,460 286,520", width=THIN * 0.8)                   # борт
        svg.path("M128,430 Q146,436 160,432", width=THIN * 0.7)
        tube(svg, "M200,250 C212,320 214,390 214,438", 50, RS_COAT, RS_COAT_LO)            # рукав
        svg.path("M190,436 Q214,446 238,436", width=THIN * 0.8)
        r_bag(svg, 216, 452, 80, 90, RS_BAG, RS_BAG_LO, 6)
        r_hand(svg, 216, 450, 10, RS_SKIN)
        r_shape(svg, [(150, 222), (200, 210), (244, 216), (262, 248), (250, 290), (200, 302), (158, 292), (144, 258)],
                RS_FUR, RS_FUR_HI, RS_FUR_LO, light=1)
        face = [(214, 182), (244, 184), (250, 204), (262, 216), (254, 224), (252, 240), (246, 256), (226, 266),
                (200, 262), (196, 220)]
        r_shape(svg, face, RS_SKIN, RS_SKIN_HI, RS_SKIN_LO, light=1, k=0.14)
        small_eye(svg, 238, 204, 5, 1.2)
        svg.path("M231,195 Q238,191 245,195", width=FACE)
        svg.path("M244,238 Q250,238 252,234", width=FACE)
        svg.path("M226,226 C222,240 226,252 232,258", width=FACE * 0.8)
        svg.ellipse(170, 178, 14, 12, RS_HAIR, INK, LINE * 0.8)
        r_shape(svg, [(158, 192), (146, 162), (152, 132), (176, 112), (210, 108), (236, 120), (248, 146), (248, 178),
                      (238, 188), (200, 182)], RS_TURBAN, RS_TURBAN_HI, RS_TURBAN_LO, light=1)
        for fd in ("M156,170 C176,140 206,124 240,128", "M166,186 C190,158 218,148 246,156", "M170,122 C194,114 218,114 236,122"):
            svg.path(fd, width=THIN * 0.8)
    return svg.text()


# ---- Бабка в розовом с голубым беретом и жёлтыми пакетами (кадр 0:50: x 34–366 × 80–590; кофта → пальто)

RP_COAT, RP_COAT_HI, RP_COAT_LO = "#F2BDE8", "#FCD8F7", "#D69CCD"               # розовое пальто (в ролике кофта)
RP_SKIN, RP_SKIN_HI, RP_SKIN_LO = "#C9578A", "#DE7CA6", "#A63F6E"               # малиновое лицо
RP_BERET, RP_BERET_HI, RP_BERET_LO = "#A4DAE6", "#D2EFF5", "#7FBDCC"
RP_BOW = "#E58DB8"
RP_HAIR = "#E2783A"
RP_SKIRT, RP_SKIRT_LO = "#7A3577", "#5C2459"
RP_BOOT = "#55484A"
RP_BAG, RP_BAG_LO = "#F2E7A2", "#D3C272"
RP_BERET_PTS = [(150, 142), (144, 118), (160, 96), (198, 84), (238, 92), (254, 114), (252, 142), (200, 150)]
RP_FACE_PTS = [(160, 140), (242, 140), (250, 172), (254, 210), (246, 240), (200, 252), (154, 240), (146, 210),
               (150, 172)]
RP_COAT_PTS = [(122, 190), (200, 186), (290, 190), (318, 208), (338, 240), (347, 282), (349, 332), (346, 370),
               (334, 386), (300, 390), (200, 394), (100, 390), (64, 386), (52, 362), (46, 302), (48, 252), (64, 214),
               (90, 198)]
RP_SKIRT_PTS = [(128, 380), (300, 380), (305, 460), (301, 540), (200, 546), (130, 540), (123, 462)]
RP_BOOTS = ((154, 48, -1), (262, 54, 1))
RP_BAGS = ((80, 392, 76, 96, 12), (322, 392, 64, 94, 0))


def rp_kerchief(svg: Svg, knot: bool) -> None:
    """Косынка на шее под подбородком: полоса видна по бокам и под лицом, узел с концами — поверх."""
    if not knot:
        band = [(140, 206), (200, 226), (262, 206), (258, 236), (200, 262), (146, 236)]
        r_shape(svg, band, RP_BERET, RP_BERET_HI, RP_BERET_LO, LINE * 0.9)
        return
    svg.path("M192,252 L176,276 L198,266 Z M214,252 L232,274 L210,266 Z", RP_BERET, INK, FACE)
    svg.ellipse(204, 252, 10, 8, RP_BERET, INK, FACE)


def resident_beret(view: str) -> str:
    svg = Svg()
    if view in ("front", "back"):
        back = view == "back"
        for x, w, s in RP_BOOTS:
            r_boot(svg, x if not back else 400 - x, 536, w, RP_BOOT, s if not back else -s, 8, 588)
        r_shape(svg, RP_SKIRT_PTS, RP_SKIRT, None, RP_SKIRT_LO)
        for x in (150, 172, 194, 216, 238, 260, 282):                                    # плиссе
            svg.path(f"M{x},{400} L{x + (x - 214) * 0.08:.1f},{540}", width=THIN * 0.7, extra=' opacity="0.75"')
        f = (lambda p: p) if not back else mirror_d
        r_shape(svg, RP_COAT_PTS, RP_COAT, RP_COAT_HI, RP_COAT_LO)
        svg.path(f("M96,214 C80,270 72,320 72,372"), width=LINE * R_INK_SOFT)              # рукава в массе тела
        svg.path(f("M304,214 C322,270 330,320 330,372"), width=LINE * R_INK_SOFT)
        svg.path("M70,300 Q118,314 168,298 M234,298 Q284,314 334,300", width=THIN * 0.8)    # складки-валики
        svg.path("M60,364 Q76,372 96,368 M306,368 Q326,372 342,364", width=THIN * 0.8)      # манжеты
        if not back:
            for y in (284, 322, 360):
                svg.ellipse(204, y, 5, 5, RP_COAT_LO, INK, THIN * 0.7)
        else:
            svg.path("M200,230 L200,388", width=THIN * 0.8)
        for hx, hy, w, h, dx in RP_BAGS:
            if back:
                hx, dx = 400 - hx, -dx
            r_bag(svg, hx, hy, w, h, RP_BAG, RP_BAG_LO, dx)
            r_hand(svg, hx, hy - 4, 13, RP_SKIN, 1 if hx > 200 else -1)
        if back:
            r_shape(svg, [(152, 140), (248, 140), (252, 176), (238, 198), (200, 204), (162, 198), (148, 176)], RP_HAIR,
                    "#EE965E", "#C2622C", LINE * 0.9)                                     # рыжий затылок под беретом
            for d in ("M176,150 C172,168 176,184 182,196", "M200,152 C198,170 200,186 202,198",
                      "M224,150 C228,168 224,184 218,196"):                               # пряди вниз, без дуги-«рта»
                svg.path(d, width=THIN * 0.7, extra=' opacity="0.7"')
            svg.path("M140,198 Q200,202 260,198 L257,218 Q200,222 143,218 Z", RP_BERET, INK, LINE * 0.9)   # косынка
            for x in (150, 250):
                svg.ellipse(x, 150, 12, 14, RP_HAIR, INK, LINE * 0.8)
            r_shape(svg, RP_BERET_PTS, RP_BERET, RP_BERET_HI, RP_BERET_LO)
            svg.path("M152,140 Q200,144 250,140", width=THIN * 0.8)                       # кант почти прямой (ART-08)
            svg.ellipse(162, 112, 10, 9, RP_BOW, INK, LINE * 0.8)
            return svg.text()
        for x in (148, 252):                                                               # рыжие пряди из-под берета
            svg.ellipse(x, 144, 12, 14, RP_HAIR, INK, LINE * 0.8)
        rp_kerchief(svg, False)
        r_shape(svg, RP_FACE_PTS, RP_SKIN, RP_SKIN_HI, RP_SKIN_LO)
        # Гримаса презрения: узкие глаза под тяжёлыми веками, широкий нос, рот уголками вниз, морщины.
        small_eye(svg, 182, 168, 6, 0.8)
        small_eye(svg, 220, 168, 6, -0.8)
        svg.path("M172,158 L192,162 M210,162 L230,157", width=FACE * 1.2)
        svg.path("M196,176 C188,190 190,200 200,200 C210,200 213,190 205,176", RP_SKIN, INK, FACE)
        svg.path("M190,196 Q186,198 186,202 M210,196 Q214,198 214,202", width=FACE * 0.7)
        svg.path("M184,220 Q200,212 216,220", width=FACE)
        for x in (190, 200, 210):                                                          # зубы-чёрточки
            svg.path(f"M{x},{216 if x == 200 else 217} l0,4", width=FACE * 0.5)
        svg.path("M172,186 C166,206 170,224 180,234 M228,186 C234,206 230,224 220,234", width=FACE * 0.8)
        svg.path("M178,150 Q186,146 194,150 M208,150 Q216,146 224,150", width=FACE * 0.6, extra=' opacity="0.7"')
        rp_kerchief(svg, True)
        r_shape(svg, RP_BERET_PTS, RP_BERET, RP_BERET_HI, RP_BERET_LO)
        svg.path("M152,138 Q200,152 250,138", width=THIN * 0.8)
        svg.ellipse(238, 112, 11, 10, RP_BOW, INK, LINE * 0.8)                            # розочка
        svg.path("M232,110 Q238,104 244,110 M234,116 Q240,120 244,114", width=THIN * 0.6)
    else:  # бок, лицом вправо: корпус-шар, юбка до пят, пакет в ближней руке
        r_boot(svg, 214, 536, 52, RP_BOOT, 1, 12, 588)
        r_shape(svg, [(150, 380), (270, 380), (282, 460), (284, 540), (210, 546), (148, 540), (140, 460)], RP_SKIRT,
                None, RP_SKIRT_LO, light=1)
        for x in (170, 200, 230, 258):
            svg.path(f"M{x},400 L{x + 4},540", width=THIN * 0.7, extra=' opacity="0.75"')
        body = [(150, 196), (230, 190), (270, 210), (296, 250), (306, 300), (302, 350), (288, 384), (210, 394),
                (130, 388), (108, 350), (104, 300), (112, 250), (128, 214)]
        r_shape(svg, body, RP_COAT, RP_COAT_HI, RP_COAT_LO, light=1)
        svg.path("M118,300 Q160,312 200,298", width=THIN * 0.8)
        tube(svg, "M200,222 C216,280 222,330 222,372", 64, RP_COAT, RP_COAT_LO)
        svg.path("M192,368 Q222,378 252,368", width=THIN * 0.8)
        r_bag(svg, 222, 392, 70, 94, RP_BAG, RP_BAG_LO, 4)
        r_hand(svg, 222, 388, 13, RP_SKIN)
        svg.ellipse(170, 150, 14, 16, RP_HAIR, INK, LINE * 0.8)
        svg.path("M160,226 Q206,246 256,232 L254,256 Q206,270 162,250 Z", RP_BERET, INK, LINE * 0.9)   # косынка
        svg.path("M248,250 L266,270 L244,264 Z", RP_BERET, INK, FACE)
        face = [(182, 140), (238, 142), (248, 166), (262, 182), (254, 194), (256, 214), (250, 234), (226, 250),
                (190, 250), (172, 220), (172, 170)]
        r_shape(svg, face, RP_SKIN, RP_SKIN_HI, RP_SKIN_LO, light=1, k=0.14)
        small_eye(svg, 236, 166, 5, 1.2)
        svg.path("M228,157 L244,160", width=FACE * 1.2)
        svg.path("M246,218 Q238,214 232,220", width=FACE)
        svg.path("M220,186 C214,204 218,222 226,232", width=FACE * 0.8)
        r_shape(svg, [(168, 144), (162, 120), (176, 98), (210, 86), (244, 94), (258, 114), (254, 140), (210, 150)],
                RP_BERET, RP_BERET_HI, RP_BERET_LO, light=1)
        svg.path("M170,138 Q210,152 252,138", width=THIN * 0.8)
        svg.ellipse(244, 114, 10, 9, RP_BOW, INK, LINE * 0.8)
    return svg.text()


# ---- Бабка в фиолетовом пальто с рыжим тюрбаном (кадр 0:38: наклон вперёд, руки разведены, пакет в правой)

RV_COAT, RV_COAT_HI, RV_COAT_LO = "#86497A", "#9E6192", "#6A3459"
RV_LAPEL = "#5E2A50"
RV_TURBAN, RV_TURBAN_HI, RV_TURBAN_LO = "#C4532F", "#DE7448", "#97391F"
RV_SCARF, RV_SCARF_HI, RV_SCARF_LO = "#9C8C20", "#B6A63C", "#776A12"           # горчично-оливковый шарф
RV_SKIN, RV_SKIN_HI, RV_SKIN_LO = "#EEE0EA", "#FAF3F8", "#CDB8CB"                # бледно-сиреневое лицо
RV_BOOT = "#3C2D31"
RV_BAG, RV_BAG_LO = "#EDE6AA", "#CFC27A"
RV_TURBAN_PTS = [(124, 172), (116, 146), (126, 118), (150, 103), (182, 100), (212, 110), (232, 132), (238, 158),
                 (232, 176), (180, 180)]
RV_FACE_PTS = [(136, 174), (230, 172), (238, 200), (238, 250), (228, 280), (182, 288), (140, 280), (130, 250),
               (130, 200)]
RV_SCARF_PTS = [(106, 192), (130, 176), (236, 166), (262, 160), (288, 170), (298, 198), (288, 242), (272, 290),
                (250, 318), (204, 334), (160, 346), (124, 344), (110, 312), (104, 252)]
RV_COAT_PTS = [(96, 178), (150, 150), (250, 146), (306, 172), (330, 214), (340, 280), (342, 340), (342, 420),
               (338, 470), (328, 498), (230, 502), (140, 498), (98, 490), (88, 440), (86, 370), (86, 300), (88, 236)]
RV_BOOTS = ((132, 56, -1), (300, 62, 1))


def rv_turban(svg: Svg, pts: list[tuple[float, float]], knot: tuple[float, float] | None) -> None:
    r_shape(svg, pts, RV_TURBAN, RV_TURBAN_HI, RV_TURBAN_LO)
    xs = [p[0] for p in pts]
    x0, x1 = min(xs), max(xs)
    for i, y in enumerate((126, 146, 164)):
        svg.path(f"M{x0 + 8 + i * 2},{y + 6} C{(x0 + x1) / 2 - 20:.1f},{y - 8} {(x0 + x1) / 2 + 20:.1f},{y - 8} {x1 - 8 - i * 2},{y + 4}",
                 width=THIN * 0.8)
    if knot:
        svg.ellipse(knot[0], knot[1], 12, 9, RV_TURBAN_HI, INK, LINE * 0.8)
        svg.ellipse(knot[0], knot[1] + 1, 4, 3, "#E9B23C", INK, THIN * 0.6)              # брошка на узле


def resident_violet(view: str) -> str:
    svg = Svg()
    if view in ("front", "back"):
        back = view == "back"
        m = (lambda p: p) if not back else r_mirror
        f = (lambda p: p) if not back else mirror_d
        for x, w, s in RV_BOOTS:
            r_boot(svg, x if not back else 400 - x, 486, w, RV_BOOT, s if not back else -s, 10, 576)
        # Руки разведены: левая протянута вниз-влево ладонью, правая держит пакет.
        r_shape(svg, m(RV_COAT_PTS), RV_COAT, RV_COAT_HI, RV_COAT_LO)
        # ART-08: руки разведены шире (кадр 0:39) — локти наружу.
        tube(svg, f("M116,204 C72,248 52,300 48,362"), 56, RV_COAT, RV_COAT_LO)      # рукава поверх корпуса
        tube(svg, f("M292,204 C336,244 354,298 360,350"), 52, RV_COAT, RV_COAT_LO)
        svg.path(f("M100,250 C104,320 110,380 104,440"), width=LINE * R_INK_SOFT, extra=' opacity="0.7"')
        r_shape(svg, m([(28, 352), (60, 340), (84, 360), (80, 392), (50, 400), (26, 386)]), RV_LAPEL, None, None, LINE * 0.9)
        r_shape(svg, m([(332, 342), (362, 330), (384, 348), (380, 378), (352, 384), (330, 370)]), RV_LAPEL, None, None,
                LINE * 0.9)
        # Ладонь протянутой руки с растопыренными пальцами.
        palm = m([(30, 392), (56, 398), (60, 420), (48, 440), (22, 440), (10, 424), (14, 404)])
        r_shape(svg, palm, RV_SKIN, None, RV_SKIN_LO, LINE * 0.8)
        for fx, fy in ((14, 440), (24, 448), (36, 450), (48, 446)):
            x0 = fx if not back else 400 - fx
            svg.path(f"M{x0:.1f},{fy - 10} l{(-3 if not back else 3)},{12}", width=LINE * 0.8)
        hx = 364 if not back else 36
        r_bag(svg, hx, 392, 56, 140, RV_BAG, RV_BAG_LO, 0)
        r_hand(svg, hx, 388, 13, RV_SKIN, 1 if not back else -1)
        if back:
            svg.path("M200,260 L200,498", width=THIN * 0.8)
            svg.path("M150,400 Q200,408 250,400", width=THIN * 0.8)                      # хлястик
            svg.add('<g transform="translate(-4,16)">')   # ART-08: голова ниже плеч — наклон вперёд, горб со спины
            r_shape(svg, [(110, 196), (200, 176), (292, 192), (284, 236), (200, 250), (118, 236)], RV_SCARF, RV_SCARF_HI,
                    RV_SCARF_LO)
            svg.path("M126,230 C130,280 128,320 120,350 L146,352 C150,320 150,280 144,236", RV_SCARF, INK, LINE * 0.8)
            rv_turban(svg, r_mirror(RV_TURBAN_PTS), None)
            svg.add("</g>")
            return svg.text()
        r_shape(svg, [(166, 320), (236, 316), (226, 360), (206, 400), (186, 360)], RV_LAPEL, None, None, LINE * 0.8)
        svg.path("M206,400 C208,440 208,470 206,500", width=THIN * 0.8)                    # борт
        for y in (420, 450, 480):
            svg.ellipse(196, y, 4.5, 4.5, RV_LAPEL, INK, THIN * 0.6)
        svg.path("M120,440 L160,436 M250,436 L292,440", width=THIN * 0.8)                  # клапаны карманов
        # ART-08: наклон вперёд (кадр 0:39) — голова с шарфом опущена и вынесена к зрителю, плечи-горб выше неё.
        svg.add('<g transform="translate(4,16) translate(184,240) scale(1.05) translate(-184,-240)">')
        r_shape(svg, RV_SCARF_PTS, RV_SCARF, RV_SCARF_HI, RV_SCARF_LO)
        svg.path("M124,342 C118,300 116,250 126,200 M268,180 C280,220 272,270 250,316", width=THIN * 0.7,
                 extra=' opacity="0.8"')
        r_shape(svg, RV_FACE_PTS, RV_SKIN, RV_SKIN_HI, RV_SKIN_LO)
        # Лицо широкое и плоское; маленькие глаза в складках, нос вниз, открытый рот, брыли.
        small_eye(svg, 160, 208, 6, 0.6)
        small_eye(svg, 202, 206, 6, -0.6)
        svg.path("M150,196 Q160,192 170,197 M192,196 Q202,191 212,195", width=FACE * 1.1)
        svg.path("M180,212 C176,226 176,236 184,238 C192,240 196,232 190,222", RV_SKIN, INK, FACE)
        svg.path("M166,254 Q182,246 198,254 Q182,264 166,254 Z", "#3A2630", INK, FACE)
        svg.path("M148,224 C142,244 146,262 156,272 M214,224 C222,244 218,262 206,272", width=FACE * 0.8)
        for x, y in ((148, 236), (214, 236), (152, 244)):
            svg.ellipse(x, y, 5, 3, RV_SKIN_LO, None)
        svg.ellipse(232, 300, 7, 6, "#F2F4F8", INK, THIN * 0.8)                            # брошь-цветок на шарфе
        svg.ellipse(232, 300, 2.5, 2.5, "#7FA8D8", None)
        rv_turban(svg, RV_TURBAN_PTS, (178, 120))
        svg.add("</g>")
    else:  # бок, лицом вправо: корпус наклонён вперёд, рука с пакетом впереди
        r_boot(svg, 214, 486, 60, RV_BOOT, 1, 12, 586)
        body = [(166, 186), (248, 178), (292, 200), (318, 244), (328, 300), (330, 380), (332, 450), (332, 498),
                (220, 504), (120, 498), (112, 440), (114, 360), (124, 280), (142, 218)]   # ART-08: спина горбом вперёд
        r_shape(svg, body, RV_COAT, RV_COAT_HI, RV_COAT_LO, light=1)
        svg.path("M300,300 C310,380 320,440 326,496", width=THIN * 0.8)
        svg.path("M124,404 Q146,410 168,406", width=THIN * 0.7)
        tube(svg, "M246,214 C270,266 292,318 304,362", 54, RV_COAT, RV_COAT_LO)
        r_shape(svg, [(282, 350), (312, 338), (330, 358), (322, 384), (296, 388)], RV_LAPEL, None, None, LINE * 0.9)
        r_bag(svg, 318, 392, 62, 130, RV_BAG, RV_BAG_LO, 4)
        r_hand(svg, 318, 388, 13, RV_SKIN)
        svg.add('<g transform="translate(24,14)">')   # ART-08: голова вынесена вперёд-вниз
        r_shape(svg, [(150, 196), (230, 170), (292, 176), (304, 206), (292, 250), (262, 300), (222, 328), (176, 330),
                      (150, 300), (140, 240)], RV_SCARF, RV_SCARF_HI, RV_SCARF_LO, light=1)
        face = [(214, 172), (268, 174), (276, 200), (290, 220), (282, 232), (280, 256), (268, 278), (238, 290),
                (210, 282), (200, 230)]
        r_shape(svg, face, RV_SKIN, RV_SKIN_HI, RV_SKIN_LO, light=1, k=0.14)
        small_eye(svg, 262, 206, 5, 1.2)
        svg.path("M254,196 Q262,192 270,197", width=FACE * 1.1)
        svg.path("M276,254 Q266,248 262,258 Q270,264 276,258", "#3A2630", INK, FACE)
        svg.path("M244,226 C238,244 242,262 250,272", width=FACE * 0.8)
        rv_turban(svg, [(178, 176), (166, 146), (178, 116), (206, 102), (240, 106), (264, 126), (272, 156), (266, 178),
                        (220, 182)], (252, 120))
        svg.add("</g>")
    return svg.text()


# ---- Мужик в ушанке из «Моложе я не стал.» (фас 0:06: курит, правая рука в боку; спина 0:59; бок 0:05)

RU_HAT, RU_HAT_HI, RU_HAT_LO = "#6E4C3E", "#8E6C58", "#52372B"                    # коричневая ушанка
RU_SKIN, RU_SKIN_HI, RU_SKIN_LO = "#EDE9E1", "#FBF9F4", "#C9C2B7"                # бледное, почти белое лицо
RU_SCARF, RU_SCARF_HI, RU_SCARF_LO = "#7C2C46", "#974760", "#5C1C33"             # бордовый шарф
RU_JACKET, RU_JACKET_HI, RU_JACKET_LO = "#858868", "#9EA180", "#6A6D50"          # оливковая куртка
RU_PANTS, RU_PANTS_HI, RU_PANTS_LO = "#C4F1EA", "#E2FBF7", "#99D2CA"             # мятные брюки клёш
RU_SHOE = "#C6432F"                                                                # красно-оранжевые ботинки
RU_CROWN_PTS = [(166, 100), (164, 72), (176, 54), (211, 48), (246, 54), (258, 72), (258, 100)]
# ART-08: широкое лицо почти во всю ушанку (кадр 0:08), а не узкое под ней.
RU_FACE_PTS = [(178, 96), (244, 96), (255, 116), (261, 140), (256, 160), (238, 171), (211, 175), (184, 171), (166, 160),
               (161, 140), (167, 116)]
RU_SCARF_PTS = [(142, 150), (200, 146), (272, 150), (300, 172), (290, 196), (212, 202), (134, 196), (124, 172)]
RU_JACKET_PTS = [(136, 170), (210, 166), (290, 168), (312, 196), (310, 254), (300, 300), (210, 308), (144, 304),
                 (134, 254), (126, 196)]
RU_LEG_L = [(148, 300), (206, 300), (206, 400), (200, 470), (202, 520), (204, 540), (156, 540), (154, 500), (152, 440)]   # шаг: левая нога поднята, как в кадре
RU_LEG_R = [(206, 300), (282, 300), (276, 380), (278, 470), (282, 540), (286, 578), (216, 578), (213, 520), (210, 420)]


def ru_hat_front(svg: Svg, back: bool = False) -> None:
    # ART-08: клапаны-уши торчат в стороны и вниз (кадр 0:08), за краями широкого лица.
    for s in (-1, 1):
        pts = [(170, 88), (158, 90), (142, 104), (132, 124), (136, 140), (152, 138), (166, 120), (172, 100)]
        r_shape(svg, pts if s < 0 else r_mirror(pts, 211), RU_HAT, RU_HAT_HI if s < 0 else None,
                RU_HAT_LO if s > 0 else None, LINE * 0.9)
    r_shape(svg, RU_CROWN_PTS + [(210, 104)], RU_HAT, RU_HAT_HI, RU_HAT_LO)
    if not back:
        r_shape(svg, [(166, 84), (211, 78), (258, 84), (258, 102), (211, 104), (166, 102)], RU_HAT_LO, None, None,
                LINE * 0.9)                                                            # поднятый передний клапан
    svg.ellipse(210, 52, 5, 4, RU_HAT_LO, INK, THIN * 0.7)                              # пуговка
    svg.path("M184,62 Q210,56 238,62", width=THIN * 0.7, extra=' opacity="0.7"')


def resident_ushanka(view: str, pose: str = "smoke") -> str:
    """pose "smoke" — курит у подъезда (кадр 0:06): во всех трёх ракурсах локоть в боку и поднятая рука с сигаретой;
    "walk" — для ходьбы: руки опущены вдоль тела, без сигареты, три ракурса согласованы."""
    svg = Svg()
    walk = pose == "walk"
    if view == "front":
        for leg, lo in ((RU_LEG_L, None), (RU_LEG_R, RU_PANTS_LO)):
            r_shape(svg, leg, RU_PANTS, RU_PANTS_HI, lo, k=0.12)
        svg.path("M172,480 L176,516 M244,500 L250,540 M262,430 L264,470", width=THIN * 0.7)  # складки клёша
        svg.path("M158,424 Q180,434 204,424", width=THIN * 0.8)   # ART-08: левая нога согнута назад — колено
        for x0, x1, y in ((152, 208, 552), (216, 288, 590)):
            r_shape(svg, [(x0 + 2, y - 18), (x1 - 2, y - 18), (x1 + (8 if x0 > 200 else 0), y - 6), (x1, y + 1),
                          (x0 - (8 if x0 < 200 else 4), y + 1), (x0 - (8 if x0 < 200 else 4), y - 6)], RU_SHOE, None, None,
                    LINE * 0.9, k=0.12)
        r_shape(svg, [(152, 546), (206, 546), (205, 556), (153, 556)], "#5A2A22", None, None, LINE * 0.8, k=0.1)   # подошва поднятой пятки
        if walk:   # руки опущены вдоль тела, чуть врозь — как со спины
            for s in (-1, 1):
                x = 210 + s * 88
                tube(svg, f"M{210 + s * 70},196 C{x + s * 10},260 {x + s * 16},330 {x + s * 18},392", 40, RU_JACKET,
                     RU_JACKET_LO)
        else:      # правая рука в боку: локоть наружу, кулак на бедре
            tube(svg, "M288,196 L332,236 L296,282", 42, RU_JACKET, RU_JACKET_LO)
        r_shape(svg, RU_JACKET_PTS, RU_JACKET, RU_JACKET_HI, RU_JACKET_LO)
        svg.path("M210,206 L210,304", width=THIN * 0.8)
        for y in (226, 254, 282):
            svg.ellipse(216, y, 4, 4, RU_JACKET_LO, INK, THIN * 0.6)
        svg.path("M160,214 Q186,230 206,212 M214,212 Q238,230 262,214", width=THIN * 0.8)    # отложной воротник
        if walk:
            for s in (-1, 1):
                r_hand(svg, 210 + s * 106, 404, 11, RU_SKIN, s)
        else:
            r_hand(svg, 294, 284, 11, RU_SKIN, -1)
            # Левая рука поднята к груди с сигаретой: плечо вниз к локтю, предплечье вверх к кисти.
            tube(svg, "M148,200 C120,238 92,236 72,196", 48, RU_JACKET, RU_JACKET_LO)
            r_hand(svg, 68, 188, 12, RU_SKIN, -1)
            svg.path("M60,178 L48,162", "none", INK, 4.6)
            svg.path("M60,178 L48,162", "none", "#F4F2EC", 3.0)
        r_shape(svg, RU_SCARF_PTS, RU_SCARF, RU_SCARF_HI, RU_SCARF_LO)
        svg.path("M172,170 Q210,182 262,168", width=THIN * 0.8)
        r_shape(svg, RU_FACE_PTS, RU_SKIN, RU_SKIN_HI, RU_SKIN_LO)
        # Старое злое лицо: глазки под тяжёлыми бровями, широкий приплюснутый нос, рот скобкой вниз, складки.
        small_eye(svg, 198, 118, 5.5, 0.6)
        small_eye(svg, 226, 118, 5.5, -0.6)
        svg.path("M188,108 L206,112 M218,112 L236,107", width=FACE * 1.4)
        svg.path("M206,122 C200,134 200,140 206,142 C210,144 214,144 218,142 C224,140 224,134 218,122", RU_SKIN, INK, FACE)
        svg.ellipse(207, 139, 1.8, 1.4, INK, None)
        svg.ellipse(217, 139, 1.8, 1.4, INK, None)
        svg.path("M200,154 Q212,148 224,154", width=FACE)
        svg.path("M196,128 C190,140 192,152 198,158 M228,128 C234,140 232,152 226,158", width=FACE * 0.8)
        svg.path("M200,166 Q212,170 224,166", width=FACE * 0.6)
        ru_hat_front(svg)
    elif view == "back":
        for leg, lo in ((r_mirror(RU_LEG_R, 210), None), (r_mirror(RU_LEG_L, 210), RU_PANTS_LO)):
            r_shape(svg, leg, RU_PANTS, RU_PANTS_HI, lo, k=0.12)
        svg.path("M176,330 Q194,370 210,340 Q226,370 244,330", width=THIN * 0.8)            # карманы-шов
        for x0, x1 in ((126, 196), (212, 282)):
            r_shape(svg, [(x0 + 2, 574), (x1 - 2, 574), (x1, 591), (x0, 591)], RU_SHOE, None, None, LINE * 0.9, k=0.1)
        if walk:
            for s in (-1, 1):                                                             # руки висят, чуть врозь
                x = 210 + s * 88
                tube(svg, f"M{210 + s * 70},196 C{x + s * 10},260 {x + s * 16},330 {x + s * 18},392", 40, RU_JACKET,
                     RU_JACKET_LO)
                r_hand(svg, x + s * 18, 404, 11, RU_SKIN, s)
        else:   # поза фаса зеркально: локоть в боку — слева, рука с сигаретой поднята — справа
            tube(svg, "M132,196 L88,236 L124,282", 42, RU_JACKET, RU_JACKET_LO)
            tube(svg, "M272,200 C300,238 328,236 348,196", 48, RU_JACKET, RU_JACKET_LO)
        r_shape(svg, [(142, 180), (210, 174), (278, 180), (300, 210), (298, 260), (290, 316), (210, 322), (130, 316),
                      (122, 260), (120, 210)], RU_JACKET, RU_JACKET_HI, RU_JACKET_LO, light=1)
        if not walk:
            r_hand(svg, 352, 188, 12, RU_SKIN, 1)
            svg.path("M360,178 L372,162", "none", INK, 4.6)
            svg.path("M360,178 L372,162", "none", "#F4F2EC", 3.0)
        svg.path("M134,298 Q210,312 286,298", width=THIN * 0.8)                           # резинка куртки
        r_shape(svg, [(150, 170), (210, 160), (270, 170), (276, 190), (210, 200), (144, 190)], RU_SCARF, RU_SCARF_HI,
                RU_SCARF_LO)
        r_shape(svg, [(194, 186), (226, 186), (230, 250), (222, 296), (200, 300), (198, 250)], RU_SCARF, RU_SCARF_HI,
                RU_SCARF_LO, LINE * 0.9)                                                  # конец шарфа по спине
        svg.path("M200,296 l-2,8 M208,298 l0,8 M216,298 l2,8", width=THIN * 0.7)
        r_shape(svg, [(162, 92), (260, 92), (264, 140), (240, 158), (182, 158), (158, 140)], RU_HAT, RU_HAT_HI, RU_HAT_LO)
        svg.path("M170,104 Q210,112 250,104", width=THIN * 0.7)                           # задний клапан ушанки
        ru_hat_front(svg, True)
    else:  # бок, лицом вправо (кадр 0:05): ушанка, шарф с концом за спиной, куртка-бочонок, рука к лицу
        # ART-08: шаг (кадр 0:05) — дальняя нога согнута назад, пятка поднята, носок в снегу; ближняя прямая.
        r_shape(svg, [(168, 300), (212, 300), (214, 380), (206, 440), (188, 486), (164, 526), (150, 548), (126, 540),
                      (140, 506), (160, 462), (170, 410), (166, 350)], RU_PANTS_LO, None, None, k=0.12)
        r_shape(svg, [(124, 532), (154, 540), (172, 576), (174, 591), (150, 591), (120, 552)], RU_SHOE, None, None,
                LINE * 0.9, k=0.1)
        r_shape(svg, [(196, 300), (244, 300), (250, 400), (256, 480), (262, 560), (266, 578), (196, 578), (194, 500),
                      (190, 420)], RU_PANTS, RU_PANTS_HI, RU_PANTS_LO, light=1, k=0.12)
        svg.path("M222,330 C224,420 228,500 232,576", width=THIN * 0.7)
        r_shape(svg, [(196, 572), (262, 572), (290, 580), (292, 591), (194, 591)], RU_SHOE, None, None, LINE * 0.9, k=0.1)
        if not walk:   # дальняя рука в боку: локоть торчит за спиной, как у фаса
            tube(svg, "M184,204 L120,242 L172,284", 40, RU_JACKET, RU_JACKET_LO)
        r_shape(svg, [(166, 176), (232, 172), (262, 196), (272, 240), (262, 290), (236, 312), (176, 314), (148, 290),
                      (140, 240), (146, 200)], RU_JACKET, RU_JACKET_HI, RU_JACKET_LO, light=1)
        svg.path("M148,296 Q200,310 258,294", width=THIN * 0.8)
        r_shape(svg, [(150, 172), (130, 186), (104, 196), (98, 210), (116, 214), (150, 200)], RU_SCARF, None,
                RU_SCARF_LO, LINE * 0.9)                                                  # развевающийся конец шарфа
        r_shape(svg, [(158, 162), (214, 152), (258, 160), (266, 180), (214, 196), (156, 190)], RU_SCARF, RU_SCARF_HI,
                RU_SCARF_LO, light=1)
        if walk:   # рука опущена вдоль бока
            tube(svg, "M206,200 C208,260 212,320 214,384", 40, RU_JACKET, RU_JACKET_LO)
        else:      # рука к лицу
            tube(svg, "M206,200 C230,240 252,252 262,232 L258,184", 40, RU_JACKET, RU_JACKET_LO)
        face = [(212, 98), (246, 100), (252, 118), (266, 134), (258, 142), (256, 156), (246, 168), (220, 170),
                (200, 160), (198, 120)]
        r_shape(svg, face, RU_SKIN, RU_SKIN_HI, RU_SKIN_LO, light=1, k=0.14)
        small_eye(svg, 242, 122, 4.5, 1.0)
        svg.path("M234,112 L250,114", width=FACE * 1.4)
        svg.path("M246,156 Q252,152 256,154", width=FACE)
        svg.path("M230,136 C226,148 230,158 236,164", width=FACE * 0.8)
        if walk:
            r_hand(svg, 216, 396, 11, RU_SKIN)
        else:
            r_hand(svg, 258, 178, 11, RU_SKIN)
            svg.path("M266,170 L280,160", "none", INK, 4.6)
            svg.path("M266,170 L280,160", "none", "#F4F2EC", 3.0)
        r_shape(svg, [(170, 92), (198, 92), (200, 140), (186, 152), (170, 136)], RU_HAT, RU_HAT_HI, None, LINE * 0.9)
        r_shape(svg, [(174, 100), (172, 70), (186, 54), (214, 50), (240, 56), (252, 74), (252, 100), (212, 104)], RU_HAT,
                RU_HAT_HI, RU_HAT_LO, light=1)
        r_shape(svg, [(228, 82), (252, 80), (258, 100), (228, 104)], RU_HAT_LO, None, None, LINE * 0.9)
        svg.ellipse(212, 52, 5, 4, RU_HAT_LO, INK, THIN * 0.7)
    return svg.text()


# ---- Дед-турист с рюкзаком из «Случая в лесу» (фас 0:04, спина 0:00): высокая шапка хаки, пионерская косынка

RT_HAT, RT_HAT_HI, RT_HAT_LO = "#B9B98C", "#D2D2A8", "#97976E"
RT_SKIN, RT_SKIN_HI, RT_SKIN_LO = "#F2E3DD", "#FCF4F0", "#D5BDB6"
RT_JACKET, RT_JACKET_HI, RT_JACKET_LO = "#C3CFAE", "#D9E3C6", "#A3B08E"         # куртка цвета шалфея
RT_STRAP, RT_STRAP_LO = "#A8A47C", "#8A8662"                                       # лямки и ремни рюкзака
RT_PACK, RT_PACK_HI, RT_PACK_LO = "#BFB070", "#D4C78C", "#9C8E52"               # рюкзак-котомка хаки
RT_KERCHIEF, RT_KERCHIEF_LO = "#EBA0BC", "#CC7C9A"                                 # розовая косынка
RT_PANTS, RT_PANTS_HI, RT_PANTS_LO = "#C0A086", "#D2B69E", "#A1836C"
RT_BOOT = "#8C5242"
RT_CAN, RT_CAN_LO = "#F2F2EC", "#CFD2CA"                                           # белый бидончик
RT_HAT_PTS = [(156, 128), (154, 92), (160, 70), (194, 62), (228, 68), (236, 92), (236, 128), (196, 134)]
RT_FACE_PTS = [(162, 116), (230, 116), (240, 148), (244, 176), (230, 196), (196, 204), (162, 198), (150, 176), (152, 146)]
RT_JACKET_PTS = [(150, 186), (246, 186), (280, 204), (298, 240), (304, 300), (308, 362), (296, 384), (200, 374),
                 (104, 384), (94, 362), (96, 300), (104, 240), (120, 206)]
RT_PANTS_PTS = [(118, 356), (282, 356), (280, 440), (276, 520), (272, 574), (206, 576), (204, 500), (196, 462),
                (188, 500), (180, 576), (122, 576), (118, 500), (114, 420)]


def rt_can(svg: Svg, x: float, y: float) -> None:
    """Бидончик в опущенной руке: дужка над кулаком, бочок с крышкой."""
    svg.path(f"M{x - 10},{y + 12} Q{x},{y - 8} {x + 10},{y + 12}", width=LINE * 0.9)
    r_shape(svg, [(x - 12, y + 12), (x + 12, y + 12), (x + 15, y + 30), (x + 14, y + 52), (x - 14, y + 52), (x - 15, y + 30)],
            RT_CAN, None, RT_CAN_LO, LINE * 0.9, k=0.1)
    svg.path(f"M{x - 13},{y + 20} L{x + 13},{y + 20}", width=THIN * 0.7)


def resident_tourist(view: str) -> str:
    svg = Svg()
    if view in ("front", "back"):
        back = view == "back"
        for x, s in ((150, -1), (238, 1)):
            r_boot(svg, x if not back else 400 - x, 556, 58, RT_BOOT, s if not back else -s, 8, 590)
        r_shape(svg, RT_PANTS_PTS, RT_PANTS, RT_PANTS_HI, RT_PANTS_LO, k=0.12)
        svg.path("M196,462 L196,420", width=THIN * 0.8)
        for s in (-1, 1):                                                                 # рукава у боков
            x = 200 + s * 92
            svg.path(f"M{200 + s * 68},214 C{x},270 {x + s * 6},330 {x + s * 4},392", width=LINE * R_INK_SOFT)
        r_shape(svg, RT_JACKET_PTS, RT_JACKET, RT_JACKET_HI, RT_JACKET_LO)
        svg.path("M104,388 Q118,396 134,392 M266,392 Q282,396 296,388", width=THIN * 0.8)  # манжеты
        svg.path("M118,352 Q200,366 284,352", width=THIN * 0.8)                           # низ куртки
        hand_l, hand_r = (114, 404), (288, 404)
        if back:
            r_shape(svg, [(110, 190), (290, 190), (304, 230), (306, 330), (296, 382), (200, 390), (104, 382), (94, 330),
                          (96, 230)], RT_PACK, RT_PACK_HI, RT_PACK_LO)                     # рюкзак во всю спину
            svg.path("M110,300 Q200,316 290,300", width=LINE * R_INK_SOFT)               # клапан кармана
            r_shape(svg, [(150, 300), (250, 300), (252, 360), (200, 368), (148, 360)], RT_PACK, None, RT_PACK_LO,
                    LINE * 0.9)
            svg.ellipse(200, 310, 6, 5, RT_STRAP_LO, INK, THIN * 0.7)
            for x in (150, 250):
                svg.path(f"M{x - 8},{196} C{x - 6},{212} {x + 6},{212} {x + 8},{196}", RT_STRAP, INK, LINE * 0.8)
            r_shape(svg, [(158, 112), (234, 112), (242, 160), (236, 196), (200, 204), (158, 196), (152, 160)], RT_SKIN_LO,
                    None, None, LINE * 0.8)                                                # затылок и шея под шапкой
            svg.path("M162,192 Q200,206 238,192", "none", INK, 8)
            svg.path("M162,192 Q200,206 238,192", "none", RT_KERCHIEF, 8 - LINE * 2)       # косынка сзади
            r_shape(svg, RT_HAT_PTS, RT_HAT, RT_HAT_HI, RT_HAT_LO)
            svg.path("M156,106 Q196,116 236,106", width=THIN * 0.8)
            svg.ellipse(195, 60, 6, 5, RT_HAT_LO, INK, THIN * 0.8)
            r_hand(svg, 400 - hand_l[0], hand_l[1], 11, RT_SKIN, 1)
            rt_can(svg, 400 - hand_l[0], hand_l[1] + 4)
            r_hand(svg, 400 - hand_r[0], hand_r[1], 11, RT_SKIN, -1)
            return svg.text()
        for x in (150, 250):                                                              # лямки рюкзака
            r_shape(svg, [(x - 12, 188), (x + 12, 188), (x + 12 * (1 if x > 200 else -1) * 0.2 + 10, 340),
                          (x - 10, 340)], RT_STRAP, None, RT_STRAP_LO, LINE * 0.9, k=0.08)
        svg.path("M140,298 L260,298", "none", INK, 9)                                    # грудной ремешок с пряжкой
        svg.path("M140,298 L260,298", "none", RT_STRAP, 9 - LINE * 2)
        svg.path("M190,292 L210,292 L210,304 L190,304 Z", RT_STRAP_LO, INK, THIN * 0.8)
        r_hand(svg, *hand_l, 11, RT_SKIN, -1)
        rt_can(svg, hand_l[0], hand_l[1] + 4)
        r_hand(svg, *hand_r, 11, RT_SKIN, 1)
        r_shape(svg, RT_FACE_PTS, RT_SKIN, RT_SKIN_HI, RT_SKIN_LO)
        # Сонные глазки, нос «картошкой» книзу, приоткрытый рот, двойной подбородок.
        small_eye(svg, 180, 140, 5.5, 0.4)
        small_eye(svg, 212, 140, 5.5, -0.4)
        svg.path("M172,130 Q180,126 188,131 M204,131 Q212,126 220,130", width=FACE * 1.1)
        svg.path("M192,144 C188,156 186,166 190,170 C196,176 204,174 206,166 C208,158 202,150 198,144", RT_SKIN, INK, FACE)
        svg.path("M183,179 Q196,173 209,179 Q208,194 196,196 Q184,194 183,179 Z", "#3A2B2B", INK, FACE)   # открытый рот
        svg.path("M186,180 Q196,177 206,180 L205,183 Q196,181 187,183 Z", "#F4EEE4", None)              # верхние зубы
        svg.path("M172,156 C166,170 168,184 176,192 M222,156 C228,170 226,184 218,192", width=FACE * 0.8)
        svg.path("M178,198 Q196,204 214,198", width=FACE * 0.7)
        # Пионерская косынка: обхват шеи и треугольник с узлом.
        svg.path("M160,194 Q196,210 236,194 L232,206 Q196,222 162,206 Z", RT_KERCHIEF, INK, LINE * 0.9)
        svg.path("M190,210 L180,248 L200,226 L216,246 L204,210 Z", RT_KERCHIEF, INK, FACE)
        svg.ellipse(197, 212, 8, 6, RT_KERCHIEF_LO, INK, FACE)
        r_shape(svg, RT_HAT_PTS, RT_HAT, RT_HAT_HI, RT_HAT_LO)
        svg.path("M156,106 Q196,116 236,106", width=THIN * 0.8)                            # отворот шапки
        svg.ellipse(195, 60, 6, 5, RT_HAT_LO, INK, THIN * 0.8)                             # пуговка на макушке
    else:  # бок, лицом вправо: рюкзак горбом за спиной, рука с бидончиком
        r_boot(svg, 214, 556, 60, RT_BOOT, 1, 12, 590)
        r_shape(svg, [(160, 356), (262, 356), (264, 440), (262, 520), (258, 576), (176, 576), (168, 500), (160, 420)],
                RT_PANTS, RT_PANTS_HI, RT_PANTS_LO, light=1, k=0.12)
        r_shape(svg, [(84, 200), (150, 188), (166, 230), (170, 330), (150, 380), (96, 384), (76, 340), (74, 250)],
                RT_PACK, RT_PACK_HI, RT_PACK_LO, light=1)                                  # рюкзак
        svg.path("M80,300 Q120,308 168,300", width=LINE * R_INK_SOFT)
        r_shape(svg, [(158, 186), (232, 184), (262, 206), (278, 250), (284, 320), (276, 376), (200, 380), (150, 372),
                      (146, 300), (148, 230)], RT_JACKET, RT_JACKET_HI, RT_JACKET_LO, light=1)
        r_shape(svg, [(170, 188), (190, 188), (186, 340), (166, 340)], RT_STRAP, None, RT_STRAP_LO, LINE * 0.9, k=0.08)
        svg.path("M150,352 Q214,364 280,352", width=THIN * 0.8)
        tube(svg, "M220,214 C236,280 238,340 236,396", 42, RT_JACKET, RT_JACKET_LO)
        r_hand(svg, 236, 404, 11, RT_SKIN)
        rt_can(svg, 236, 408)
        face = [(204, 116), (240, 118), (248, 140), (262, 160), (254, 170), (252, 182), (240, 198), (210, 204),
                (186, 194), (184, 150)]
        r_shape(svg, face, RT_SKIN, RT_SKIN_HI, RT_SKIN_LO, light=1, k=0.14)
        small_eye(svg, 236, 140, 4.5, 1.0)
        svg.path("M228,131 Q236,127 244,132", width=FACE * 1.1)
        svg.path("M252,176 Q242,173 237,180 Q241,192 252,190 Q249,184 252,176 Z", "#3A2B2B", INK, FACE)   # открытый рот
        svg.path("M222,156 C218,170 222,184 230,192", width=FACE * 0.8)
        svg.path("M186,194 Q220,212 248,198 L246,210 Q220,224 188,206 Z", RT_KERCHIEF, INK, LINE * 0.9)
        svg.path("M240,206 L252,236 L232,214 Z", RT_KERCHIEF, INK, FACE)
        r_shape(svg, [(176, 128), (174, 92), (182, 70), (212, 62), (240, 68), (248, 92), (248, 126), (212, 132)],
                RT_HAT, RT_HAT_HI, RT_HAT_LO, light=1)
        svg.path("M176,106 Q212,116 248,106", width=THIN * 0.8)
        svg.ellipse(212, 60, 6, 5, RT_HAT_LO, INK, THIN * 0.8)
    return svg.text()


# ---- Пацан в вязаной шапке из «Моложе я не стал.» (кадр 0:25, трое у кирпичного дома); палитры — из того же кадра

RKD_SKIN, RKD_SKIN_HI, RKD_SKIN_LO = "#EBD6CC", "#F8EAE3", "#CDB3A7"
RKD_BOOT = "#4A4446"
RKD_PALETTES = (   # 0 — мятная куртка, мятная шапка, розовый шарф, бордовые брюки; 1 — сиреневая куртка, розовая шапка
    {"hat": "#A6EADC", "hat_lo": "#7FCDBE", "jacket": "#C2F5EE", "jacket_hi": "#E0FCF8", "jacket_lo": "#97D6CD",
     "scarf": "#E07CBC", "scarf_lo": "#BC5C9A", "pants": "#93545C", "pants_lo": "#733D45", "glove": "#F0F2F0"},
    {"hat": "#EE7CC6", "hat_lo": "#CC5CA6", "jacket": "#E2D2F2", "jacket_hi": "#F2E8FA", "jacket_lo": "#C2AEDA",
     "scarf": None, "scarf_lo": None, "pants": "#E2A04C", "pants_lo": "#C2823A", "glove": "#EE7CC6"},
)
RKD_HAT_PTS = [(186, 196), (182, 170), (188, 148), (200, 134), (213, 127), (227, 136), (238, 156), (244, 176),
               (244, 196), (214, 200)]
RKD_FACE_PTS = [(190, 188), (240, 188), (253, 202), (259, 222), (253, 240), (235, 252), (215, 256), (195, 252),
                (177, 240), (171, 222), (177, 202)]   # ART-08: круглые щёки (кадр 0:25), а не прямоугольник
RKD_JACKET_PTS = [(168, 224), (214, 232), (260, 224), (278, 244), (286, 290), (290, 340), (287, 388), (214, 394),
                  (116, 390), (112, 340), (116, 290), (130, 250), (150, 232)]
RKD_PANTS_PTS = [(140, 386), (266, 386), (266, 470), (262, 566), (210, 568), (206, 480), (203, 462), (198, 480),
                 (194, 568), (146, 568), (142, 470)]


def rkd_hat(svg: Svg, p: dict, pts: list[tuple[float, float]], band_y: float, x0: float, x1: float) -> None:
    r_shape(svg, pts, p["hat"], None, p["hat_lo"])
    for i in range(6):                                                                    # вязка — вертикальные рубчики
        x = x0 + 10 + i * (x1 - x0 - 20) / 5
        svg.path(f"M{x:.1f},{band_y - 4:.1f} C{x:.1f},{band_y - 30:.1f} {x + (213 - x) * 0.3:.1f},{band_y - 56:.1f} "
                 f"{x + (213 - x) * 0.5:.1f},{band_y - 54:.1f}", width=THIN * 0.6, extra=' opacity="0.55"')
    r_shape(svg, [(x0, band_y - 14), (x1, band_y - 14), (x1 + 2, band_y + 4), (x0 - 2, band_y + 4)], p["hat"], None,
            p["hat_lo"], LINE * 0.9, k=0.1)                                              # отворот


def resident_kid(view: str, palette: int = 0) -> str:
    p = RKD_PALETTES[palette]
    svg = Svg()
    if view in ("front", "back"):
        back = view == "back"
        for x, s in ((170, -1), (238, 1)):
            r_boot(svg, x, 560, 50, RKD_BOOT, s, 8, 590)
        r_shape(svg, RKD_PANTS_PTS, p["pants"], None, p["pants_lo"], k=0.12)
        svg.path("M203,462 L203,420", width=THIN * 0.8)
        r_shape(svg, RKD_JACKET_PTS, p["jacket"], p["jacket_hi"], p["jacket_lo"])
        for s in (-1, 1):                                                                 # рукава в массе куртки
            svg.path(f"M{214 + s * 62},244 C{214 + s * 80},290 {214 + s * 82},340 {214 + s * 80},376", width=LINE * R_INK_SOFT)
        svg.path("M124,300 Q160,310 190,300 M238,300 Q268,310 280,300", width=THIN * 0.7, extra=' opacity="0.8"')
        for x in (124, 284):
            svg.ellipse(x, 388, 13, 15, p["glove"], INK, LINE * 0.8)
        if back:
            svg.path("M214,250 L214,390", width=THIN * 0.7, extra=' opacity="0.6"')
            r_shape(svg, [(186, 196), (244, 196), (250, 226), (214, 236), (180, 226)], RKD_SKIN_LO, None, None, LINE * 0.8)
            if p["scarf"]:
                r_shape(svg, [(170, 232), (214, 222), (262, 232), (262, 250), (214, 254), (168, 250)], p["scarf"], None,
                        p["scarf_lo"], LINE * 0.9)
            rkd_hat(svg, p, RKD_HAT_PTS, 194, 184, 246)
            return svg.text()
        svg.path("M214,262 L214,392", width=THIN * 0.8)                                   # молния
        r_shape(svg, RKD_FACE_PTS, RKD_SKIN, RKD_SKIN_HI, RKD_SKIN_LO)
        small_eye(svg, 202, 208, 4.5, 0.4)
        small_eye(svg, 228, 208, 4.5, -0.4)
        svg.path("M211,212 C207,221 209,226 214,226 C219,226 221,221 217,214", RKD_SKIN, INK, FACE)
        svg.path("M206,236 Q214,233 222,236", width=FACE)
        for x in (186, 242):                                                              # румяные круглые щёки
            svg.ellipse(x, 228, 9, 6, "#EFA0A8", None, extra=' opacity="0.55"')
        svg.path("M178,224 C180,236 188,244 196,247 M250,224 C248,236 240,244 232,247", width=FACE * 0.6,
                 extra=' opacity="0.8"')
        if p["scarf"]:
            r_shape(svg, [(170, 238), (214, 248), (262, 236), (266, 256), (214, 268), (166, 256)], p["scarf"], None,
                    p["scarf_lo"], LINE * 0.9)
            r_shape(svg, [(198, 254), (232, 254), (238, 292), (216, 300), (196, 292)], p["scarf"], None, p["scarf_lo"],
                    LINE * 0.9, k=0.1)
            svg.path("M200,294 l-2,8 M210,298 l0,8 M222,298 l1,8 M232,294 l3,7", width=THIN * 0.7)
        else:
            svg.path("M180,244 Q214,262 250,244", width=LINE * R_INK_SOFT)               # воротник-стойка
        rkd_hat(svg, p, RKD_HAT_PTS, 194, 184, 246)
    else:  # бок, лицом вправо
        r_boot(svg, 214, 560, 52, RKD_BOOT, 1, 12, 590)
        r_shape(svg, [(168, 386), (262, 386), (262, 470), (258, 568), (176, 568), (172, 470)], p["pants"], None,
                p["pants_lo"], light=1, k=0.12)
        r_shape(svg, [(176, 226), (238, 224), (266, 250), (280, 300), (282, 360), (272, 392), (210, 398), (150, 392),
                      (138, 350), (140, 290), (152, 248)], p["jacket"], p["jacket_hi"], p["jacket_lo"], light=1)
        tube(svg, "M212,252 C228,300 232,340 230,372", 44, p["jacket"], p["jacket_lo"])
        svg.ellipse(230, 384, 13, 15, p["glove"], INK, LINE * 0.8)
        face = [(200, 188), (242, 188), (250, 206), (260, 216), (252, 224), (248, 238), (218, 246), (196, 232)]
        r_shape(svg, face, RKD_SKIN, RKD_SKIN_HI, RKD_SKIN_LO, light=1, k=0.14)
        small_eye(svg, 236, 206, 4, 0.8)
        svg.path("M240,234 Q246,232 248,228", width=FACE)
        if p["scarf"]:
            r_shape(svg, [(184, 236), (236, 244), (256, 240), (254, 258), (214, 266), (182, 254)], p["scarf"], None,
                    p["scarf_lo"], LINE * 0.9)
            r_shape(svg, [(242, 254), (262, 256), (264, 290), (246, 292)], p["scarf"], None, p["scarf_lo"], LINE * 0.9, k=0.1)
        rkd_hat(svg, p, [(188, 196), (184, 170), (192, 148), (206, 134), (220, 127), (234, 138), (244, 158), (248, 176),
                         (248, 196), (218, 200)], 194, 188, 250)
    return svg.text()


# ---- PEOPLE-02 c2: остальные бабки ролика «Как прожить жизнь так, чтобы на тебя не наорала бабка» (su-Tl4Gyp7Q).
# Тот же метод: фигура из кадра раскадровки приведена к холсту 400×600, формы и посадка уборов сняты с кадра,
# цвета пипеткой. Рост при height_m 2,0: собачка 1,65 м (верх y=95), колпак 1,70 (80), бант 1,58 (116),
# тюрбан 1,72 (74). Где кадр обрезан (колпак — до колен, бант и тюрбан — по грудь), низ фигуры достроен
# по пропорциям бабок того же ролика (голова с убором ≈ треть роста); кадры роликов в репозиторий не входят.

# ---- Бабка в розовом пальто с собачкой (кадр 0:20, лицо 0:17–0:18): шляпка-«таблетка» с цветком, шарф в обороты,
# жёлтый пакет в левой руке, на поводке маленькая жёлтая собачка. В кадре собачка дальше по тротуару (на уровне
# руки); в игре она стоит на земле у правой ноги — спрайт плоский, иначе «висит» в воздухе.

RG_COAT, RG_COAT_HI, RG_COAT_LO = "#FBBEE9", "#FFD8F5", "#DE9ACB"              # розовое пальто (#FEC0EC)
RG_SCARF, RG_SCARF_HI, RG_SCARF_LO = "#DC97BC", "#EBB0D0", "#BF7CA0"           # шарф темнее пальто (#DB97B6)
RG_HAT, RG_HAT_HI, RG_HAT_LO = "#F9B6E2", "#FFD0F1", "#E197C7"
RG_FLOWER, RG_FLOWER_LO = "#E9819F", "#C4506F"
RG_SKIN, RG_SKIN_HI, RG_SKIN_LO = "#F7F3C8", "#FEFDE2", "#DAD7A4"              # лимонное лицо (#FDF8D0)
RG_BAGS = "#C9C29A"                                                               # зеленоватые мешки под глазами
RG_HAIR = "#D9D0C0"
RG_BOOT = "#746E69"
RG_BAG, RG_BAG_LO = "#F5F6A2", "#D6D57A"
RG_DOG, RG_DOG_HI, RG_DOG_LO = "#F4F5B0", "#FDFDD6", "#D7D89A"
RG_HAT_PTS = [(160, 162), (154, 134), (160, 110), (184, 97), (220, 95), (250, 104), (268, 124), (270, 150), (262, 164),
              (212, 160)]
RG_FACE_PTS = [(168, 152), (244, 152), (253, 180), (255, 220), (247, 250), (224, 264), (190, 264), (166, 250),
               (158, 220), (160, 180)]
RG_SCARF_PTS = [(132, 200), (146, 172), (170, 160), (246, 160), (276, 174), (294, 204), (297, 246), (285, 276),
                (250, 292), (204, 297), (154, 289), (127, 266), (122, 232)]
RG_ROLL_PTS = [(152, 250), (204, 270), (256, 250), (276, 262), (268, 284), (206, 299), (146, 286), (136, 264)]
RG_COAT_PTS = [(150, 180), (250, 180), (296, 196), (322, 220), (340, 256), (350, 300), (354, 350), (356, 400), (354, 440),
               (352, 480), (352, 520), (334, 532), (270, 536), (200, 534), (132, 532), (102, 524), (100, 490),
               (100, 450), (98, 424), (72, 418), (70, 396), (74, 350), (82, 300), (94, 256), (112, 222), (130, 196)]
RG_BOOTS = ((150, 52, -1), (248, 52, 1))


def rg_dog(svg: Svg, x: float, y: float, face: int = -1) -> None:
    """Собачка ростом ≈0,2 м: круглое туловище, острые уши, хвост крючком; x, y — середина низа лап, face — куда морда."""
    for dx in (-18, -8, 8, 18):                                                         # лапки
        svg.path(f"M{x + dx:.1f},{y - 22:.1f} L{x + dx + face * 2:.1f},{y:.1f}", width=LINE * 1.4)
    svg.path(f"M{x - face * 26:.1f},{y - 38:.1f} C{x - face * 40:.1f},{y - 50:.1f} {x - face * 40:.1f},{y - 66:.1f} "
             f"{x - face * 30:.1f},{y - 68:.1f}", "none", INK, 7.5)                    # хвост крючком
    svg.path(f"M{x - face * 26:.1f},{y - 38:.1f} C{x - face * 40:.1f},{y - 50:.1f} {x - face * 40:.1f},{y - 66:.1f} "
             f"{x - face * 30:.1f},{y - 68:.1f}", "none", RG_DOG, 4.0)
    r_shape(svg, [(x - 30, y - 34), (x - 14, y - 48), (x + 14, y - 48), (x + 30, y - 36), (x + 28, y - 20),
                  (x, y - 16), (x - 28, y - 20)], RG_DOG, RG_DOG_HI, RG_DOG_LO, LINE * 0.9, light=face)
    hx, hy = x + face * 30, y - 46
    for ex in (-8, 6):                                                                  # уши торчком
        svg.path(f"M{hx + ex - 5:.1f},{hy - 8:.1f} L{hx + ex + 1:.1f},{hy - 24:.1f} L{hx + ex + 7:.1f},{hy - 9:.1f} Z",
                 RG_DOG, INK, LINE * 0.8)
    svg.ellipse(hx, hy, 15, 13, RG_DOG, INK, LINE * 0.9)
    svg.ellipse(hx + face * 13, hy + 3, 3, 2.5, INK, None)                             # нос
    svg.ellipse(hx + face * 4, hy - 3, 2, 2, INK, None)                                 # глаз
    svg.path(f"M{hx - face * 9:.1f},{hy + 10:.1f} Q{hx:.1f},{hy + 14:.1f} {hx + face * 8:.1f},{hy + 9:.1f}",
             width=THIN * 0.9)                                                            # ошейник


def rg_hat(svg: Svg, pts: list[tuple[float, float]], flower: tuple[float, float] | None) -> None:
    r_shape(svg, pts, RG_HAT, RG_HAT_HI, RG_HAT_LO)
    xs = [p[0] for p in pts]
    x0, x1 = min(xs), max(xs)
    for i, y in enumerate((122, 140)):                                                  # складки «таблетки»
        svg.path(f"M{x0 + 8 + i * 4},{y + 6} C{x0 + 40},{y - 6} {x1 - 40},{y - 8} {x1 - 6 - i * 4},{y}",
                 width=THIN * 0.8, extra=' opacity="0.8"')
    if flower:
        fx, fy = flower
        for a in range(5):
            t = math.radians(a * 72 - 90)
            svg.ellipse(fx + 7 * math.cos(t), fy + 7 * math.sin(t), 6, 6, RG_FLOWER, INK, THIN * 0.7)
        svg.ellipse(fx, fy, 4, 4, RG_FLOWER_LO, INK, THIN * 0.6)


def resident_dog(view: str, dog: bool = True) -> str:
    svg = Svg()
    if view in ("front", "back"):
        back = view == "back"
        m = (lambda p: p) if not back else r_mirror
        f = (lambda p: p) if not back else mirror_d
        mx = (lambda x: x) if not back else (lambda x: 400 - x)
        for x, w, s in RG_BOOTS:
            r_boot(svg, mx(x), 516, w, RG_BOOT, s if not back else -s, 8, 590)
        r_shape(svg, m(RG_COAT_PTS), RG_COAT, RG_COAT_HI, RG_COAT_LO)
        svg.path(f("M112,232 C104,300 100,350 98,394"), width=LINE * R_INK_SOFT)         # рукава вдоль тела
        svg.path(f("M300,232 C312,300 318,350 320,398"), width=LINE * R_INK_SOFT)
        r_shape(svg, m([(68, 392), (98, 394), (100, 420), (70, 418)]), RG_COAT, None, RG_COAT_LO, LINE * 0.9, k=0.1)
        r_shape(svg, m([(318, 398), (356, 398), (356, 420), (318, 420)]), RG_COAT, None, RG_COAT_LO, LINE * 0.9, k=0.1)
        svg.path("M200,300 C200,380 199,460 198,532" if not back else "M200,250 C200,350 200,440 200,532",
                 width=THIN * 0.8)                                                        # борт / шов спинки
        if back:
            svg.path("M156,420 Q200,428 244,420", width=THIN * 0.8)                      # хлястик
        hx = mx(82)
        r_bag(svg, hx, 432, 84, 118, RG_BAG, RG_BAG_LO, -4 if not back else 4)
        r_hand(svg, hx, 428, 12, RG_SKIN, -1 if not back else 1)
        lx, ly = mx(338), 448
        r_hand(svg, lx, ly, 12, RG_SKIN, 1 if not back else -1)
        if dog:
            dx = mx(342)
            svg.path(f"M{lx:.1f},{ly + 10:.1f} C{lx + (dx - lx) * 0.2:.1f},{ly + 50:.1f} {dx - (dx - 200) * 0.06:.1f},{ly + 70:.1f} "
                     f"{dx + (-30 if not back else 30):.1f},{ly + 92:.1f}", width=THIN)   # поводок
            rg_dog(svg, dx, 590, -1 if not back else 1)
        if back:
            r_shape(svg, [(150, 168), (250, 168), (256, 200), (240, 222), (200, 228), (160, 222), (144, 200)], RG_HAIR,
                    None, None, LINE * 0.9)                                               # седой затылок под шляпкой
            r_shape(svg, r_mirror(RG_SCARF_PTS), RG_SCARF, RG_SCARF_HI, RG_SCARF_LO)
            for y in (220, 246, 270):                                                     # обороты шарфа на спине
                svg.path(f"M{134 + (y - 220) * 0.2:.1f},{y} Q200,{y + 18} {266 - (y - 220) * 0.2:.1f},{y}", width=THIN * 0.8)
            rg_hat(svg, r_mirror(RG_HAT_PTS), (400 - 250, 148))
            return svg.text()
        r_shape(svg, RG_SCARF_PTS, RG_SCARF, RG_SCARF_HI, RG_SCARF_LO)
        r_shape(svg, RG_FACE_PTS, RG_SKIN, RG_SKIN_HI, RG_SKIN_LO)
        # Лицо: высокий лоб, глаза низко, в зеленоватых мешках; нос коротким крючком, рот «бантиком», усики-тень.
        for x in (186, 214):
            svg.ellipse(x, 226, 9, 5, RG_BAGS, None)
        small_eye(svg, 186, 218, 6, 0.4)
        small_eye(svg, 214, 218, 6, -0.4)
        svg.path("M178,206 Q186,202 194,206 M206,206 Q214,202 222,206", width=FACE * 0.8)
        svg.path("M200,222 C196,230 197,236 202,236 C207,236 208,232 205,228", RG_SKIN, INK, FACE)
        svg.path("M194,246 Q200,241 206,246 Q200,251 194,246 Z", "#3A2A2E", INK, FACE * 0.8)
        svg.path("M190,241 Q200,238 210,241", width=FACE * 0.6, extra=' opacity="0.45"')    # усики-тень
        svg.path("M172,232 C168,244 172,254 180,260 M228,232 C232,244 228,254 220,260", width=FACE * 0.7)
        r_shape(svg, RG_ROLL_PTS, RG_SCARF, RG_SCARF_HI, RG_SCARF_LO)
        svg.path("M150,268 Q204,288 268,266 M160,282 Q204,296 258,282", width=THIN * 0.8, extra=' opacity="0.8"')
        svg.ellipse(266, 274, 8, 8, RG_SCARF_LO, INK, THIN * 0.8)                          # круглая брошь
        svg.ellipse(266, 274, 3.5, 3.5, RG_FLOWER, None)
        rg_hat(svg, RG_HAT_PTS, (248, 150))
    else:  # бок, лицом вправо: пальто колоколом, шарф кольцом, собачка впереди на поводке, пакет в дальней руке
        r_bag(svg, 136, 436, 70, 106, RG_BAG, RG_BAG_LO, -10)
        r_boot(svg, 196, 516, 52, RG_BOOT, 1, 12, 590)
        coat = [(166, 186), (232, 184), (262, 206), (276, 250), (284, 320), (292, 400), (298, 470), (302, 526), (200, 534),
                (118, 528), (116, 470), (122, 400), (130, 320), (140, 250), (150, 210)]
        r_shape(svg, coat, RG_COAT, RG_COAT_HI, RG_COAT_LO, light=1)
        svg.path("M128,440 Q142,446 156,442", width=THIN * 0.7)
        tube(svg, "M210,236 C224,300 230,360 232,404", 50, RG_COAT, RG_COAT_LO)            # рукав
        r_shape(svg, [(208, 398), (256, 398), (258, 422), (206, 422)], RG_COAT, None, RG_COAT_LO, LINE * 0.9, k=0.1)
        r_hand(svg, 234, 434, 12, RG_SKIN)
        if dog:
            svg.path("M240,442 C262,470 290,500 316,544", width=THIN)                       # поводок к ошейнику
            rg_dog(svg, 344, 590, 1)
        r_shape(svg, [(150, 196), (188, 172), (236, 168), (272, 186), (284, 222), (276, 262), (250, 288), (204, 296),
                      (164, 286), (144, 252), (140, 222)], RG_SCARF, RG_SCARF_HI, RG_SCARF_LO, light=1)
        face = [(204, 154), (252, 156), (262, 184), (272, 206), (264, 214), (262, 234), (252, 254), (226, 262),
                (204, 256), (196, 210)]
        r_shape(svg, face, RG_SKIN, RG_SKIN_HI, RG_SKIN_LO, light=1, k=0.14)
        svg.ellipse(248, 226, 8, 5, RG_BAGS, None)
        small_eye(svg, 248, 218, 5, 1.2)
        svg.path("M240,206 Q248,202 256,206", width=FACE * 0.8)
        svg.path("M258,244 Q252,240 248,245 Q253,249 258,244 Z", "#3A2A2E", INK, FACE * 0.8)
        svg.path("M230,232 C226,244 230,252 236,258", width=FACE * 0.7)
        r_shape(svg, [(196, 250), (236, 262), (268, 244), (282, 256), (270, 282), (230, 296), (190, 290), (182, 268)],
                RG_SCARF, RG_SCARF_HI, RG_SCARF_LO, light=1)                              # оборот шарфа под подбородком
        svg.path("M190,276 Q232,290 272,264", width=THIN * 0.8, extra=' opacity="0.8"')
        rg_hat(svg, [(168, 164), (164, 134), (172, 110), (198, 97), (232, 96), (258, 108), (272, 130), (272, 156),
                     (262, 166), (214, 162)], (176, 146))
    return svg.text()


# ---- Бабка в бордовом пальто, фиолетовом колпаке и тёмных очках (кадры 0:55–0:58, 0:62): колпак завитком
# над рыжими волосами, белёсое лицо, охристый меховой воротник узлом, левая рука протянута к Илюше.

RK2_CAP, RK2_CAP_HI, RK2_CAP_LO = "#834376", "#9C5C8F", "#64305A"               # фиолетовый колпак (#7D487A)
RK2_HAIR, RK2_HAIR_HI, RK2_HAIR_LO = "#DE3A4C", "#EE6070", "#B12838"             # красно-рыжие волосы (#C83556)
RK2_SKIN, RK2_SKIN_HI, RK2_SKIN_LO = "#DCDCE2", "#F1F1F5", "#BDBDC8"             # белёсо-серое лицо (#DCD9DD)
RK2_GLASS = "#1C1719"
RK2_FUR, RK2_FUR_HI, RK2_FUR_LO = "#B0975C", "#C6AE74", "#917840"                # охристый воротник (#AF965A)
RK2_COAT, RK2_COAT_HI, RK2_COAT_LO = "#A24B53", "#B6626B", "#7E3540"             # бордовое пальто (#A24B53)
RK2_HAND, RK2_HAND_LO = "#D6DAD6", "#AEB2AE"
RK2_BOOT = "#3A2C2E"
RK2_CAP_PTS = [(182, 160), (184, 134), (192, 112), (202, 94), (210, 80), (220, 88), (234, 106), (248, 126), (257, 146),
               (258, 162), (220, 168)]
RK2_HAIR_PTS = [(174, 170), (180, 154), (220, 160), (260, 152), (268, 168), (264, 190), (240, 182), (200, 184),
                (178, 192)]
RK2_FACE_PTS = [(192, 182), (248, 182), (262, 206), (270, 240), (266, 266), (246, 284), (214, 290), (186, 282),
                (172, 260), (172, 226), (180, 200)]
RK2_FUR_PTS = [(150, 236), (172, 270), (206, 290), (242, 284), (272, 250), (294, 208), (314, 226), (322, 266),
               (306, 304), (272, 330), (236, 342), (196, 336), (160, 316), (140, 286), (137, 256)]
RK2_COAT_PTS = [(160, 246), (300, 206), (322, 230), (338, 280), (350, 350), (358, 420), (362, 480), (360, 540),
                (340, 562), (280, 570), (200, 572), (130, 570), (88, 560), (82, 520), (90, 470), (102, 420),
                (114, 360), (126, 300), (140, 262)]
RK2_BOOTS = ((156, 52, -1), (258, 56, 1))


def rk2_cap(svg: Svg, pts: list[tuple[float, float]]) -> None:
    """Колпак завитком: мягкий конус, витки — дугами."""
    r_shape(svg, pts, RK2_CAP, RK2_CAP_HI, RK2_CAP_LO)
    xs = [p[0] for p in pts]
    x0, x1 = min(xs), max(xs)
    for y, inset in ((150, 6), (130, 16), (110, 26)):
        svg.path(f"M{x0 + inset:.1f},{y + 6} C{x0 + inset + 14:.1f},{y - 6} {x1 - inset - 10:.1f},{y - 4} {x1 - inset + 4:.1f},{y - 10}",
                 width=THIN * 0.8)


def rk2_palm(svg: Svg, pts: list[tuple[float, float]], tips: list[tuple[float, float, float, float]]) -> None:
    """Растопыренная кисть: ладонь и пальцы чёрточками (6–7 пальцев, как в ШКЯ)."""
    r_shape(svg, pts, RK2_HAND, None, RK2_HAND_LO, LINE * 0.8)
    for x0, y0, dx, dy in tips:
        svg.path(f"M{x0:.1f},{y0:.1f} l{dx:.1f},{dy:.1f}", width=LINE * 0.9)


def resident_kolpak(view: str) -> str:
    svg = Svg()
    if view in ("front", "back"):
        back = view == "back"
        m = (lambda p: p) if not back else r_mirror
        f = (lambda p: p) if not back else mirror_d
        mx = (lambda x: x) if not back else (lambda x: 400 - x)
        for x, w, s in RK2_BOOTS:
            r_boot(svg, mx(x), 548, w, RK2_BOOT, s if not back else -s, 10, 590)
        r_shape(svg, m(RK2_COAT_PTS), RK2_COAT, RK2_COAT_HI, RK2_COAT_LO)
        # Левая рука протянута вбок-вниз ладонью вперёд, правая висит вдоль тела.
        tube(svg, f("M166,270 C142,292 120,312 100,330"), 50, RK2_COAT, RK2_COAT_LO)
        svg.path(f("M318,250 C326,300 314,350 300,398"), width=LINE * R_INK_SOFT)
        svg.path(f("M98,470 C120,476 140,476 160,470"), width=THIN * 0.7, extra=' opacity="0.7"')
        if not back:
            svg.path("M232,346 C230,420 228,490 226,568", width=THIN * 0.8)               # борт
            for y in (392, 440, 488):
                svg.ellipse(220, y, 4.5, 4.5, RK2_COAT_LO, INK, THIN * 0.6)
        else:
            svg.path("M200,250 C200,350 200,460 200,568", width=THIN * 0.8)
            svg.path("M150,452 Q200,460 250,452", width=THIN * 0.8)                      # хлястик
        rk2_palm(svg, m([(98, 322), (110, 338), (100, 356), (78, 362), (62, 350), (66, 330), (84, 320)]),
                 [(mx(x), y, dx if not back else -dx, dy) for x, y, dx, dy in
                  ((66, 336, -12, 2), (64, 344, -12, 2), (64, 352, -10, 6), (70, 358, -7, 10), (80, 361, -3, 11),
                   (92, 358, 1, 11))])
        rk2_palm(svg, m([(276, 404), (300, 402), (306, 424), (302, 444), (282, 450), (268, 432)]),
                 [(mx(x), 446, (dx if not back else -dx), 14) for x, dx in ((272, -3), (280, -1), (288, 0), (296, 1), (303, 3))])
        if back:
            r_shape(svg, r_mirror([(146, 238), (200, 222), (290, 210), (316, 232), (306, 262), (200, 268), (150, 264)]), RK2_FUR,
                    RK2_FUR_HI, RK2_FUR_LO)                                               # воротник со спины
            r_shape(svg, r_mirror([(170, 176), (180, 154), (204, 150), (232, 150), (262, 152), (274, 172), (276, 200),
                                   (268, 226), (250, 244), (226, 250), (200, 248), (178, 236), (166, 210)]), RK2_HAIR,
                    RK2_HAIR_HI, RK2_HAIR_LO)
            for x in (168, 190, 212, 234):                                                # пряди
                svg.path(f"M{x},{170} C{x - 4},{196} {x + 2},{220} {x - 2},{238}", width=THIN * 0.7, extra=' opacity="0.7"')
            rk2_cap(svg, r_mirror(RK2_CAP_PTS))
            return svg.text()
        r_shape(svg, RK2_FUR_PTS, RK2_FUR, RK2_FUR_HI, RK2_FUR_LO)
        svg.path("M226,322 L220,364 L246,344 Z", RK2_FUR, INK, LINE * 0.8)                # концы узла
        svg.path("M246,326 L272,358 L262,330 Z", RK2_FUR, INK, LINE * 0.8)
        svg.path("M158,300 C176,312 196,320 214,322 M288,240 C296,262 290,288 276,306", width=THIN * 0.7,
                 extra=' opacity="0.7"')
        r_shape(svg, RK2_HAIR_PTS, RK2_HAIR, RK2_HAIR_HI, RK2_HAIR_LO)
        r_shape(svg, RK2_FACE_PTS, RK2_SKIN, RK2_SKIN_HI, RK2_SKIN_LO)
        # Лицо: тёмные очки злыми щёлками, нос вниз, рот подковой, брыли и складки у глаз.
        svg.path("M184,200 L212,206 L208,216 L188,212 Z", RK2_GLASS, INK, FACE)
        svg.path("M226,206 L254,198 L252,211 L230,216 Z", RK2_GLASS, INK, FACE)
        svg.path("M211,208 Q219,204 227,208", width=FACE)
        svg.path("M216,220 C212,232 212,240 220,242 C226,243 228,238 224,232", RK2_SKIN, INK, FACE)
        svg.path("M204,258 Q216,248 230,258", width=FACE * 1.1)
        svg.path("M190,234 C184,250 188,266 198,274 M246,232 C252,248 248,264 238,272", width=FACE * 0.8)
        svg.path("M180,222 Q186,226 184,232 M258,222 Q252,226 254,232", width=FACE * 0.6, extra=' opacity="0.7"')
        rk2_cap(svg, RK2_CAP_PTS)
    else:  # бок, лицом вправо: корпус вперёд, рука протянута вперёд-вниз, колпак завитком назад
        r_boot(svg, 214, 548, 58, RK2_BOOT, 1, 12, 590)
        body = [(162, 230), (240, 206), (282, 226), (306, 270), (320, 340), (330, 420), (338, 500), (340, 556),
                (220, 570), (118, 562), (110, 500), (114, 420), (122, 340), (134, 280), (146, 248)]
        r_shape(svg, body, RK2_COAT, RK2_COAT_HI, RK2_COAT_LO, light=1)
        svg.path("M300,330 C312,400 324,470 332,550", width=THIN * 0.8)
        svg.path("M124,470 Q146,476 168,472", width=THIN * 0.7)
        tube(svg, "M236,250 C262,290 290,320 316,344", 50, RK2_COAT, RK2_COAT_LO)
        rk2_palm(svg, [(310, 330), (334, 334), (346, 354), (336, 372), (316, 370), (306, 352)],
                 [(338, 368, 6, 10), (344, 362, 9, 7), (346, 352, 11, 3), (328, 372, 2, 11), (318, 371, -2, 10)])
        r_shape(svg, [(150, 240), (196, 226), (250, 214), (290, 222), (304, 250), (292, 290), (256, 320), (210, 330),
                      (168, 318), (148, 284)], RK2_FUR, RK2_FUR_HI, RK2_FUR_LO, light=1)
        svg.path("M262,312 L270,350 L284,318 Z", RK2_FUR, INK, LINE * 0.8)
        r_shape(svg, [(184, 176), (196, 156), (236, 156), (262, 166), (262, 190), (236, 196), (200, 200), (182, 210)],
                RK2_HAIR, RK2_HAIR_HI, RK2_HAIR_LO, light=1)
        face = [(214, 182), (262, 182), (274, 208), (286, 228), (278, 236), (280, 256), (268, 278), (238, 290),
                (212, 282), (204, 230)]
        r_shape(svg, face, RK2_SKIN, RK2_SKIN_HI, RK2_SKIN_LO, light=1, k=0.14)
        svg.path("M252,204 L276,206 L274,218 L254,216 Z", RK2_GLASS, INK, FACE)
        svg.path("M234,206 L252,208", width=FACE)                                          # дужка
        svg.path("M272,260 Q264,254 256,262", width=FACE * 1.1)
        svg.path("M240,236 C236,252 240,266 248,274", width=FACE * 0.8)
        rk2_cap(svg, [(190, 166), (190, 140), (196, 118), (204, 98), (210, 82), (222, 90), (238, 108), (252, 128),
                      (262, 148), (264, 166), (226, 172)])
    return svg.text()


# ---- Бабка в жёлтой шубе, рыжей шапке и розовой повязке с бантом (кадры 0:29–0:34 в троллейбусе, 0:57–0:58 на улице):
# сиренево-розовое лицо, большой нос, накрашенные губы, рот открыт; круглый отложной воротник, пуговицы.

RB2_HAT, RB2_HAT_HI, RB2_HAT_LO = "#F57E1E", "#FF9E48", "#D2630F"               # рыжая шапка (#FD7D12)
RB2_BAND, RB2_BAND_HI, RB2_BAND_LO = "#E477E0", "#F29CEF", "#C35CC2"             # розовая повязка (#E675E3)
RB2_SKIN, RB2_SKIN_HI, RB2_SKIN_LO = "#F2D9F5", "#FBEEFD", "#D8BADF"             # сиренево-розовое лицо (#F5DEFC)
RB2_CHEEK = "#E8B4DA"
RB2_LIPS, RB2_MOUTH = "#D2485C", "#3A0E14"
RB2_HAIR = "#CFC4C9"
RB2_COAT, RB2_COAT_HI, RB2_COAT_LO = "#D9C78E", "#EADBA6", "#B8A46C"             # жёлтая шуба (#D8C68C)
RB2_BUTTON = "#BBA466"
RB2_BOOT = "#4A3A36"
RB2_HAT_PTS = [(150, 186), (147, 152), (155, 131), (180, 120), (220, 119), (245, 130), (253, 152), (252, 186)]
RB2_BAND_PTS = [(140, 184), (200, 177), (260, 184), (263, 200), (260, 214), (200, 220), (138, 214), (136, 200)]
RB2_FACE_PTS = [(144, 208), (256, 208), (264, 236), (262, 262), (248, 282), (200, 292), (152, 282), (138, 262),
                (136, 236)]
RB2_COAT_PTS = [(132, 262), (268, 262), (300, 282), (310, 320), (314, 370), (326, 420), (338, 470), (342, 520),
                (334, 548), (300, 556), (200, 560), (100, 556), (66, 548), (58, 520), (62, 470), (74, 420), (86, 370),
                (90, 320), (100, 282)]
RB2_COLLAR_L = [(120, 286), (164, 280), (202, 294), (198, 320), (176, 338), (140, 338), (112, 322), (106, 302)]


def rb2_bow(svg: Svg, cx: float, cy: float, s: float = 1.0) -> None:
    """Бант на повязке: две петли и узел."""
    svg.path(f"M{cx:.1f},{cy:.1f} C{cx - 10 * s:.1f},{cy - 18:.1f} {cx - 26 * s:.1f},{cy - 14:.1f} {cx - 24 * s:.1f},{cy:.1f} "
             f"C{cx - 26 * s:.1f},{cy + 14:.1f} {cx - 10 * s:.1f},{cy + 16:.1f} {cx:.1f},{cy:.1f} Z", RB2_BAND, INK, LINE * 0.8)
    svg.path(f"M{cx:.1f},{cy:.1f} C{cx + 10 * s:.1f},{cy - 18:.1f} {cx + 26 * s:.1f},{cy - 14:.1f} {cx + 24 * s:.1f},{cy:.1f} "
             f"C{cx + 26 * s:.1f},{cy + 14:.1f} {cx + 10 * s:.1f},{cy + 16:.1f} {cx:.1f},{cy:.1f} Z", RB2_BAND, INK, LINE * 0.8)
    svg.ellipse(cx, cy, 6, 7, RB2_BAND_LO, INK, LINE * 0.8)
    svg.path(f"M{cx - 18 * s:.1f},{cy - 4:.1f} l{8 * s:.1f},3 M{cx + 18 * s:.1f},{cy - 4:.1f} l{-8 * s:.1f},3",
             width=THIN * 0.6, extra=' opacity="0.7"')


def rb2_fur(svg: Svg, xs: tuple[float, ...], y0: float, y1: float) -> None:
    """Вертикальные штрихи меха на шубе (в кадре — полосы)."""
    for i, x in enumerate(xs):
        svg.path(f"M{x:.1f},{y0 + (i % 3) * 12:.1f} C{x - 3:.1f},{(y0 + y1) / 2:.1f} {x + 3:.1f},{(y0 + y1) / 2 + 30:.1f} "
                 f"{x - 2:.1f},{y1 - (i % 2) * 16:.1f}", RB2_COAT, RB2_COAT_LO, THIN * 1.2, extra=' opacity="0.8"')


def resident_bow(view: str) -> str:
    svg = Svg()
    if view in ("front", "back"):
        back = view == "back"
        for x, w, s in ((162, 50, -1), (240, 50, 1)):
            r_boot(svg, x, 548, w, RB2_BOOT, s, 8, 590)
        r_shape(svg, RB2_COAT_PTS, RB2_COAT, RB2_COAT_HI, RB2_COAT_LO)
        rb2_fur(svg, (100, 124, 150, 250, 276, 300), 370, 540)
        svg.path("M96,320 C82,400 72,450 70,500 M304,320 C318,400 328,450 330,500", width=LINE * R_INK_SOFT)  # рукава
        svg.path("M58,496 Q70,504 84,500 M316,500 Q330,504 342,496", width=THIN * 0.8)                    # обшлаги
        for x in (72, 328):                                                                  # кисти из рукавов
            svg.ellipse(x, 514, 12, 14, RB2_SKIN, INK, LINE * 0.8)
        if back:
            svg.path("M200,300 L200,556", width=THIN * 0.8)
            r_shape(svg, [(122, 272), (200, 262), (278, 272), (290, 296), (200, 308), (110, 296)], RB2_COAT, None,
                    RB2_COAT_LO, LINE * 0.9)                                               # воротник со спины
            r_shape(svg, [(146, 206), (254, 206), (260, 240), (246, 270), (200, 280), (154, 270), (140, 240)], RB2_HAIR,
                    None, None, LINE * 0.9)                                                # седой затылок
            svg.path("M164,236 Q200,250 236,236", width=THIN * 0.7, extra=' opacity="0.6"')
            r_shape(svg, RB2_HAT_PTS, RB2_HAT, RB2_HAT_HI, RB2_HAT_LO)
            r_shape(svg, RB2_BAND_PTS, RB2_BAND, RB2_BAND_HI, RB2_BAND_LO, LINE * 0.9)
            rb2_bow(svg, 158, 198, 0.8)
            return svg.text()
        svg.path("M200,320 C200,400 200,480 200,556", width=THIN * 0.8)                      # борт
        for y in (360, 410, 460):
            svg.ellipse(212, y, 5, 5, RB2_BUTTON, INK, THIN * 0.7)
        for x in (140, 260):                                                                  # уши
            svg.ellipse(x, 244, 8, 12, RB2_SKIN, INK, LINE * 0.8)
        r_shape(svg, RB2_FACE_PTS, RB2_SKIN, RB2_SKIN_HI, RB2_SKIN_LO)
        for x in (166, 234):
            svg.ellipse(x, 252, 13, 8, RB2_CHEEK, None)
        r_shape(svg, RB2_COLLAR_L, RB2_COAT, RB2_COAT_HI, RB2_COAT_LO, LINE * 0.9)
        r_shape(svg, r_mirror(RB2_COLLAR_L), RB2_COAT, RB2_COAT_HI, RB2_COAT_LO, LINE * 0.9)
        # Лицо: веки полуприкрыты, большой нос, накрашенный открытый рот.
        small_eye(svg, 178, 230, 6, 0.4)
        small_eye(svg, 222, 230, 6, -0.4)
        svg.path("M168,222 Q178,217 188,222 M212,222 Q222,217 232,222", width=FACE * 1.1)
        svg.path("M196,226 C188,240 186,252 196,256 C204,259 214,256 212,246 C210,238 206,232 204,226", RB2_SKIN, INK, FACE)
        svg.path("M184,266 Q200,258 216,266 Q214,282 200,284 Q186,282 184,266 Z", RB2_LIPS, INK, FACE)
        svg.path("M189,268 Q200,264 211,268 Q208,278 200,279 Q192,278 189,268 Z", RB2_MOUTH, None)
        svg.path("M158,258 C156,270 162,280 172,284 M242,258 C244,270 238,280 228,284", width=FACE * 0.7)
        r_shape(svg, RB2_HAT_PTS, RB2_HAT, RB2_HAT_HI, RB2_HAT_LO)
        r_shape(svg, RB2_BAND_PTS, RB2_BAND, RB2_BAND_HI, RB2_BAND_LO, LINE * 0.9)
        svg.path("M150,196 Q200,190 222,196", width=THIN * 0.7, extra=' opacity="0.7"')
        rb2_bow(svg, 242, 198)
    else:  # бок, лицом вправо: шуба шаром, шапка, бант спереди на повязке, нос вперёд, рот открыт
        r_boot(svg, 206, 548, 54, RB2_BOOT, 1, 12, 590)
        body = [(150, 272), (240, 270), (284, 292), (306, 336), (316, 400), (318, 470), (312, 530), (284, 552),
                (200, 558), (120, 552), (94, 520), (90, 460), (96, 390), (110, 330), (126, 292)]
        r_shape(svg, body, RB2_COAT, RB2_COAT_HI, RB2_COAT_LO, light=1)
        rb2_fur(svg, (120, 146, 270, 294), 360, 540)
        svg.path("M290,330 C300,400 306,460 304,530", width=THIN * 0.8)
        for y in (370, 420, 470):
            svg.ellipse(298, y, 4.5, 4.5, RB2_BUTTON, INK, THIN * 0.6)
        tube(svg, "M206,300 C216,370 222,430 222,480", 58, RB2_COAT, RB2_COAT_LO)
        svg.path("M194,478 Q222,488 250,478", width=THIN * 0.8)
        svg.ellipse(222, 500, 12, 14, RB2_SKIN, INK, LINE * 0.8)
        r_shape(svg, [(150, 276), (206, 266), (262, 276), (284, 300), (262, 326), (214, 330), (166, 320), (146, 298)],
                RB2_COAT, RB2_COAT_HI, RB2_COAT_LO, LINE * 0.9, light=1)                  # воротник
        r_shape(svg, [(166, 210), (206, 206), (238, 214), (250, 240), (244, 270), (210, 282), (176, 276), (160, 244)],
                RB2_HAIR, None, None, LINE * 0.9)
        face = [(204, 208), (252, 210), (262, 230), (280, 238), (284, 252), (270, 258), (272, 272), (258, 286),
                (226, 292), (202, 280), (196, 240)]
        r_shape(svg, face, RB2_SKIN, RB2_SKIN_HI, RB2_SKIN_LO, light=1, k=0.14)
        svg.ellipse(196, 244, 9, 13, RB2_SKIN, INK, LINE * 0.8)                              # ухо
        svg.ellipse(236, 256, 12, 8, RB2_CHEEK, None)
        small_eye(svg, 250, 228, 5, 1.2)
        svg.path("M242,220 Q250,216 258,221", width=FACE * 1.1)
        svg.path("M258,264 Q268,262 272,268 Q266,280 258,278 Q254,272 258,264 Z", RB2_LIPS, INK, FACE)
        svg.path("M260,268 Q266,267 268,270 Q264,276 260,275 Z", RB2_MOUTH, None)
        r_shape(svg, [(166, 186), (162, 152), (170, 132), (196, 121), (232, 122), (254, 134), (262, 156), (262, 186)],
                RB2_HAT, RB2_HAT_HI, RB2_HAT_LO, light=1)
        r_shape(svg, [(154, 186), (210, 178), (268, 184), (272, 200), (268, 214), (210, 220), (152, 214), (150, 200)],
                RB2_BAND, RB2_BAND_HI, RB2_BAND_LO, LINE * 0.9, light=1)
        rb2_bow(svg, 262, 198, 0.7)
    return svg.text()


# ---- Бабка в голубом пальто, оливковом тюрбане и розовом шарфе (кадры 0:26–0:28 в магазине, 0:58 и 0:62 на улице):
# узкая высокая фигура-столбик, пальто расширяется книзу, шарф обвивает лицо до тюрбана, рот открыт.

RT2_TURBAN, RT2_TURBAN_HI, RT2_TURBAN_LO = "#B4B664", "#CDCF80", "#93954A"     # оливковый тюрбан (#B2B462)
RT2_SKIN, RT2_SKIN_HI, RT2_SKIN_LO = "#FBF8DA", "#FFFFF0", "#DFDAB4"            # кремовое лицо (#FDFCDE)
RT2_SCARF, RT2_SCARF_HI, RT2_SCARF_LO = "#EDB0E3", "#F8CCF6", "#CF8EC4"         # розовый шарф (#F4BEE8, #DBA3CF)
RT2_COAT, RT2_COAT_HI, RT2_COAT_LO = "#BEEEF5", "#DDFBFF", "#96C6D0"            # голубое пальто (#C6FFFF, #99C9D4)
RT2_BROOCH = "#E8E2C0"
RT2_BOOT = "#3E3A3E"
RT2_TURBAN_PTS = [(142, 152), (139, 126), (150, 102), (172, 84), (198, 75), (222, 81), (242, 100), (250, 128),
                  (248, 152), (200, 158)]
RT2_FACE_PTS = [(142, 140), (248, 140), (254, 180), (252, 224), (240, 250), (196, 258), (152, 250), (140, 224),
                (137, 180)]
RT2_SCARF_PTS = [(122, 152), (134, 130), (256, 130), (270, 152), (280, 200), (282, 250), (270, 284), (236, 300),
                 (200, 304), (160, 300), (126, 284), (116, 250), (116, 200)]
RT2_ROLL_PTS = [(138, 246), (196, 262), (254, 246), (272, 266), (252, 294), (200, 305), (148, 296), (128, 268)]
RT2_COAT_PTS = [(120, 138), (200, 132), (280, 138), (296, 170), (304, 220), (312, 300), (320, 380), (328, 460),
                (334, 530), (330, 556), (200, 562), (70, 556), (66, 530), (72, 460), (80, 380), (88, 300), (96, 220),
                (104, 170)]


def rt2_turban(svg: Svg, pts: list[tuple[float, float]], brooch: tuple[float, float] | None) -> None:
    """Тюрбан витками: каждый виток — дуга, выше и уже предыдущего."""
    r_shape(svg, pts, RT2_TURBAN, RT2_TURBAN_HI, RT2_TURBAN_LO)
    xs = [p[0] for p in pts]
    x0, x1 = min(xs), max(xs)
    for i, y in enumerate((140, 120, 100)):
        svg.path(f"M{x0 + 4 + i * 12},{y + 8} C{x0 + 24 + i * 10},{y - 8} {x1 - 30 - i * 8},{y - 10} {x1 - 4 - i * 12},{y + 2}",
                 width=THIN * 0.9)
    if brooch:
        svg.ellipse(brooch[0], brooch[1], 6, 5, RT2_BROOCH, INK, THIN * 0.8)


def resident_turban(view: str) -> str:
    svg = Svg()
    if view in ("front", "back"):
        back = view == "back"
        f = (lambda p: p) if not back else mirror_d
        for x, w, s in ((164, 46, -1), (238, 46, 1)):
            r_boot(svg, x, 548, w, RT2_BOOT, s, 8, 590)
        r_shape(svg, RT2_COAT_PTS, RT2_COAT, RT2_COAT_HI, RT2_COAT_LO)
        svg.path(f("M110,250 C100,330 94,390 92,436 M290,250 C300,330 306,390 308,436"), width=LINE * R_INK_SOFT)  # рукава
        svg.path("M80,432 Q94,440 108,436 M292,436 Q306,440 320,432", width=THIN * 0.8)
        for x in (94, 306):                                                                   # кисти
            svg.ellipse(x, 452, 11, 13, RT2_SKIN, INK, LINE * 0.8)
        if back:
            svg.path("M200,300 L200,560", width=THIN * 0.8)
            r_shape(svg, [(124, 150), (138, 128), (262, 128), (276, 150), (284, 210), (276, 262), (240, 290), (200, 296),
                          (160, 290), (124, 262), (116, 210)], RT2_SCARF, RT2_SCARF_HI, RT2_SCARF_LO)  # шарф-капюшон
            for y in (180, 220, 260):
                svg.path(f"M{128 + (y - 180) * 0.1:.1f},{y} Q200,{y + 16} {272 - (y - 180) * 0.1:.1f},{y}", width=THIN * 0.8)
            rt2_turban(svg, r_mirror(RT2_TURBAN_PTS), None)
            return svg.text()
        svg.path("M200,306 C200,400 200,480 200,560", width=THIN * 0.8)                       # борт
        r_shape(svg, RT2_SCARF_PTS, RT2_SCARF, RT2_SCARF_HI, RT2_SCARF_LO)
        svg.ellipse(256, 204, 8, 12, RT2_SKIN, INK, LINE * 0.8)                               # ухо
        r_shape(svg, RT2_FACE_PTS, RT2_SKIN, RT2_SKIN_HI, RT2_SKIN_LO)
        # Лицо: глаза-точки в морщинах, длинный нос крючком, открытый рот с зубами, складки щёк.
        for x in (172, 216):
            svg.ellipse(x, 196, 4.5, 4.5, "#FFFFFF", INK, FACE * 0.8)
            svg.ellipse(x, 196, 1.8, 1.8, INK, None)
            svg.path(f"M{x - 8},{204} Q{x},{210} {x + 8},{204} M{x - 7},{210} Q{x},{215} {x + 7},{210}", width=FACE * 0.6,
                     extra=' opacity="0.8"')
        svg.path("M196,198 C188,206 186,218 194,224 C198,227 204,226 206,222", width=FACE)
        svg.path("M182,230 Q196,226 210,230 Q206,246 196,247 Q186,246 182,230 Z", "#1E1416", INK, FACE)
        svg.path("M186,232 L208,232 L206,236 L188,236 Z", "#FFFFFF", None)
        svg.path("M158,212 C152,228 156,240 164,246 M232,212 C238,228 234,240 226,246", width=FACE * 0.7)
        svg.path("M154,226 l8,2 M234,228 l8,-2 M156,236 l8,1", width=FACE * 0.6, extra=' opacity="0.7"')
        r_shape(svg, RT2_ROLL_PTS, RT2_SCARF, RT2_SCARF_HI, RT2_SCARF_LO)
        svg.path("M140,270 Q198,292 262,270 M152,286 Q200,300 250,286", width=THIN * 0.8, extra=' opacity="0.8"')
        rt2_turban(svg, RT2_TURBAN_PTS, (240, 140))
    else:  # бок, лицом вправо: столбик пальто, шарф до тюрбана, нос крючком
        r_boot(svg, 206, 548, 50, RT2_BOOT, 1, 12, 590)
        coat = [(150, 140), (230, 134), (256, 160), (266, 220), (276, 300), (288, 380), (298, 460), (306, 530), (302, 558),
                (200, 562), (106, 556), (104, 530), (110, 460), (118, 380), (126, 300), (134, 220), (140, 170)]
        r_shape(svg, coat, RT2_COAT, RT2_COAT_HI, RT2_COAT_LO, light=1)
        svg.path("M270,300 C282,380 294,460 300,556", width=THIN * 0.8)
        svg.path("M196,250 C208,330 214,390 216,436", width=LINE * R_INK_SOFT)
        svg.path("M200,432 Q216,440 232,434", width=THIN * 0.8)
        svg.ellipse(218, 452, 11, 13, RT2_SKIN, INK, LINE * 0.8)
        r_shape(svg, [(150, 150), (164, 128), (240, 128), (262, 150), (270, 200), (270, 250), (258, 284), (226, 302),
                      (184, 302), (150, 284), (138, 240), (138, 190)], RT2_SCARF, RT2_SCARF_HI, RT2_SCARF_LO, light=1)
        face = [(204, 140), (252, 142), (260, 170), (262, 186), (274, 196), (272, 204), (264, 208), (264, 228), (254, 250),
                (226, 258), (204, 250), (196, 200)]
        r_shape(svg, face, RT2_SKIN, RT2_SKIN_HI, RT2_SKIN_LO, light=1, k=0.14)
        svg.ellipse(248, 186, 4, 4, "#FFFFFF", INK, FACE * 0.8)
        svg.ellipse(250, 186, 1.6, 1.6, INK, None)
        svg.path("M240,196 Q248,201 256,196", width=FACE * 0.6, extra=' opacity="0.8"')
        svg.path("M262,222 Q254,218 248,224 Q254,236 262,232 Z", "#1E1416", INK, FACE)
        svg.path("M232,206 C226,220 230,234 238,242", width=FACE * 0.7)
        r_shape(svg, [(170, 244), (226, 262), (264, 246), (276, 266), (258, 292), (210, 304), (166, 294), (156, 268)],
                RT2_SCARF, RT2_SCARF_HI, RT2_SCARF_LO, light=1)
        svg.path("M166,276 Q218,296 266,270", width=THIN * 0.8, extra=' opacity="0.8"')
        rt2_turban(svg, [(160, 154), (156, 128), (166, 104), (188, 86), (214, 77), (238, 84), (256, 104), (262, 130),
                         (260, 154), (210, 160)], (252, 140))
    return svg.text()


RESIDENTS = {"babka": resident_babka, "man": resident_man, "woman": resident_woman, "boy": resident_boy,
             # PEOPLE-02: прохожие из роликов ШКЯ
             "shuba": resident_shuba, "beret": resident_beret, "violet": resident_violet,
             "ushanka": resident_ushanka, "tourist": resident_tourist, "kid": resident_kid,
             "ushanka_walk": lambda view: resident_ushanka(view, "walk"),   # ART-07 п2: идёт, без сигареты
             "kid2": lambda view: resident_kid(view, 1),
             # PEOPLE-02 c2: остальные бабки ролика «…не наорала бабка»
             "dog": resident_dog, "kolpak": resident_kolpak, "bow": resident_bow, "turban": resident_turban}


def main() -> None:
    global LINE_K, OUT
    args = sys.argv[1:]
    if "--line-k" in args:
        LINE_K = float(args[args.index("--line-k") + 1])
    if "--out" in args:
        OUT = Path(args[args.index("--out") + 1]).resolve()
    OUT.mkdir(parents=True, exist_ok=True)
    files: dict[str, str] = {}
    for view in ("front", "back", "side"):
        files[f"ilyusha_{view}_idle.svg"] = ilyusha(view, -1)
        for k in range(4):
            files[f"ilyusha_{view}_walk{k}.svg"] = ilyusha(view, k)
        files[f"babka_{view}_idle.svg"] = babka(view)
        files[f"vendor_{view}_idle.svg"] = vendor(view)
        files[f"police_{view}_idle.svg"] = police(view)   # EXT-01
        files[f"officer_{view}_idle.svg"] = officer(view)
        files[f"guard_{view}_idle.svg"] = guard(view)   # ART-08: второй пост (Officer2)
        for name, draw in RESIDENTS.items():   # PEOPLE-01
            files[f"resident_{name}_{view}_idle.svg"] = draw(view)
    for name, text in files.items():
        (OUT / name).write_text(text, encoding="utf-8")
    print(f"CHARACTERS: {len(files)} files, line k={LINE_K} -> {OUT}")


if __name__ == "__main__":
    main()
