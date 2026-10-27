#!/usr/bin/env python3
"""Рисунки персонажей ART-01: Илюша, Бабка, продавщица — SVG собственной работы.

Запуск: uv run tools/generate_characters.py
Пишет assets/art/characters/<имя>_<ракурс>_<кадр>.svg.

Манера по паспорту ART-01 (V01, V02 и кадры 01–10): чёрный контур от руки, плоская заливка
с одной светлой полосой, мелкие тонкие линии лица. Холст 400×600 условных единиц,
ноги стоят на y=590, ось персонажа x=200. Ракурсы: front (лицом к камере), back, side
(смотрит вправо; левый бок — зеркало в игре). Только стандартная библиотека Python.
"""

from __future__ import annotations

import math
import re
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "assets" / "art" / "characters"
W, H = 400, 600
SCALE = 2  # пиксели текстуры на единицу холста

INK = "#141213"
LINE = 9.0   # внешний контур: «жирный чёрный контур» канона (раздел 2) приоритетнее паспорта
THIN = 4.0   # детали лица и складки

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
    def __init__(self) -> None:
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
        return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{W * SCALE}" height="{H * SCALE}" '
                f'viewBox="0 0 {W} {H}">{defs}{"".join(self.parts)}</svg>\n')


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
               depth: float = 12.0) -> None:
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
    svg.path(d, LACE, INK, LINE * 0.7)


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


# ---------------------------------------------------------------- Бабка

def babka(view: str) -> str:
    svg = Svg()
    if view in ("front", "back"):
        back = view == "back"
        for xc in (165, 235):
            svg.shape(f"M{xc - 30},566 C{xc - 34},588 {xc + 34},588 {xc + 30},566 Z", B_SHOE)
        dress = ("M200,236 C130,236 92,262 86,320 C78,400 60,500 52,566 C120,580 280,580 348,566 "
                 "C340,500 322,400 314,320 C308,262 270,236 200,236 Z")
        svg.shape(dress, B_DRESS, hi=B_DRESS_HI, hi_d="M120,250 C96,330 86,460 82,580 L40,580 L40,240 Z",
                  lo=B_DRESS_LO, lo_d="M290,250 C318,330 324,460 330,580 L360,580 L360,240 Z")
        svg.path("M120,470 Q200,486 280,470", width=THIN * 0.8)
        if not back:
            for i in range(11):
                svg.ellipse(200, 300 + i * 24, 3.4, 4.2, INK, None)
        else:
            svg.path("M200,280 L200,560", width=THIN * 0.8)
        for side in (-1, 1):
            d = "M110,262 C84,280 78,360 84,452 C88,470 120,472 126,456 C126,380 130,320 138,280 Z"
            if side > 0:
                d = mirror_d(d)
            svg.shape(d, B_DRESS, lo=B_DRESS_LO, lo_d="M0,420 L400,420 L400,480 L0,480 Z")
            x = 104 if side < 0 else 296
            scallops(svg, arc_points(x, 458, 22, 6, math.radians(180), math.radians(0), 5), 9, LACE)
            hand = f"M{x - 18},466 C{x - 22},494 {x - 12},516 {x},516 C{x + 12},516 {x + 22},494 {x + 18},466 Z"
            svg.shape(hand, B_SKIN, lo=B_SKIN_LO, lo_d=f"M{x + 4},460 L{x + 30},460 L{x + 30},520 L{x + 4},520 Z")
            if not back:
                for k in (-8, -2, 4, 10):
                    svg.path(f"M{x + k},{500} L{x + k * 1.1},{512}", width=THIN * 0.6)
        head = ("M200,84 C268,84 300,134 302,186 C304,240 274,278 200,280 C126,278 96,240 98,186 "
                "C100,134 132,84 200,84 Z")
        svg.shape(head, B_SKIN, hi=B_SKIN_HI, hi_d="M130,110 C116,160 118,230 150,272 L100,280 L100,100 Z",
                  lo=B_SKIN_LO, lo_d="M272,130 C292,190 286,250 240,280 L300,280 L300,120 Z")
        if not back:
            for x in (172, 228):
                svg.ellipse(x, 176, 10, 5, "#FFFFFF", INK, THIN * 0.8)
                svg.ellipse(x, 177, 3, 3, INK, None)
                svg.path(f"M{x - 13},170 Q{x},164 {x + 13},170", width=THIN)
                svg.path(f"M{x - 12},186 Q{x},192 {x + 12},186", width=THIN * 0.7)
            svg.path("M190,170 C188,198 182,214 184,224 C188,234 212,234 216,224 C218,214 212,198 210,170", width=THIN)
            svg.path("M184,222 C176,236 176,252 186,262 M216,222 C224,236 224,252 214,262", width=THIN * 0.8)
            svg.path("M184,246 C192,242 208,242 216,246 C210,254 190,254 184,246 Z", INK, None)
            svg.path("M190,246 L193,250 M200,244 L200,249 M208,246 L206,250", stroke="#FFFFFF", width=2.2)
            svg.path("M150,236 C156,256 172,268 200,268 C228,268 244,256 250,236", width=THIN * 0.8)
            svg.path("M176,262 Q200,276 224,262", width=THIN * 0.8)
        else:
            svg.path("M150,240 Q200,262 250,240", width=THIN * 0.8)
        for x, s in ((98, -1), (302, 1)):
            svg.path(f"M{x},176 C{x + 16 * s},178 {x + 16 * s},206 {x},208", B_SKIN, INK, THIN)
        hat = "M122,128 C112,80 126,22 200,18 C274,22 288,80 278,128 C240,112 160,112 122,128 Z"
        svg.shape(hat, B_HAT, hi="#BFBB74", hi_d="M140,50 C126,80 126,110 134,136 L110,136 L110,40 Z",
                  lo=B_HAT_LO, lo_d="M250,46 C276,80 278,110 268,140 L300,140 L300,40 Z")
        svg.path("M150,60 Q200,48 250,60", width=THIN * 0.7)
        if not back:
            frill_band(svg, 200, 136, 80, 10, math.radians(196), math.radians(-16), 10, 13)
        scallops(svg, arc_points(200, 258, 86, 20, math.radians(170), math.radians(10), 13), 15, LACE)
    else:
        svg.shape("M180,566 C176,588 260,588 252,566 Z", B_SHOE)
        dress = ("M190,236 C130,240 104,272 102,330 C98,410 90,500 92,568 C160,580 280,580 318,566 "
                 "C320,480 318,400 300,330 C290,270 250,236 190,236 Z")
        svg.shape(dress, B_DRESS, hi=B_DRESS_HI, hi_d="M260,250 C298,320 312,460 312,580 L360,580 L360,240 Z",
                  lo=B_DRESS_LO, lo_d="M96,250 L150,250 C120,330 116,460 118,580 L80,580 Z")
        svg.path("M110,470 Q200,486 300,470", width=THIN * 0.8)
        for i in range(10):
            svg.ellipse(292 - abs(i - 4) * 1.5, 310 + i * 24, 3.2, 4.0, INK, None)
        head = ("M160,96 C212,84 262,110 272,150 C280,180 284,214 276,236 C266,266 230,278 196,276 "
                "C150,274 122,250 118,206 C116,160 126,106 160,96 Z")
        svg.shape(head, B_SKIN, hi=B_SKIN_HI, hi_d="M240,100 C274,150 284,220 266,276 L300,276 L300,96 Z",
                  lo=B_SKIN_LO, lo_d="M100,120 L150,120 C130,170 136,240 170,280 L100,280 Z")
        svg.path("M166,176 C150,178 150,206 166,208", B_SKIN, INK, THIN)
        svg.ellipse(246, 172, 7, 4.5, "#FFFFFF", INK, THIN * 0.8)
        svg.ellipse(249, 173, 2.6, 2.6, INK, None)
        svg.path("M236,166 Q246,160 256,166", width=THIN)
        nose = "M262,164 C280,186 302,210 298,222 C294,230 276,228 268,220"
        svg.path(nose, B_SKIN, INK, THIN * 1.2)
        svg.path("M262,234 C270,232 278,234 282,236 C278,242 266,242 262,234 Z", INK, None)
        svg.path("M238,214 C230,236 232,252 244,262 M210,262 Q240,282 270,256", width=THIN * 0.8)
        hat = "M134,140 C124,90 140,42 196,38 C254,40 274,86 268,140 C230,126 170,126 134,140 Z"
        svg.shape(hat, B_HAT, hi="#BFBB74", hi_d="M236,44 C266,80 272,110 266,140 L300,140 L300,40 Z",
                  lo=B_HAT_LO, lo_d="M100,40 L150,40 C134,80 134,110 140,140 L100,140 Z")
        frill_band(svg, 200, 128, 70, 12, math.radians(250), math.radians(345), 6, 12)
        scallops(svg, arc_points(205, 262, 80, 18, math.radians(175), math.radians(5), 12), 14, LACE)
        sleeve = "M176,270 C150,284 146,370 150,452 C154,470 196,472 200,456 C204,380 206,310 204,276 Z"
        svg.shape(sleeve, B_DRESS, hi=B_DRESS_HI, hi_d="M190,276 C204,330 204,400 200,460 L230,460 L230,270 Z",
                  lo=B_DRESS_LO, lo_d="M140,420 L220,420 L220,480 L140,480 Z")
        scallops(svg, arc_points(175, 460, 26, 6, math.radians(180), math.radians(0), 5), 9, LACE)
        svg.shape("M158,466 C152,494 164,516 178,516 C192,516 200,494 196,466 Z", B_SKIN,
                  lo=B_SKIN_LO, lo_d="M140,460 L168,460 L168,520 L140,520 Z")
    return svg.text()


# ---------------------------------------------------------------- Продавщица

def vendor(view: str) -> str:
    svg = Svg()
    side = view == "side"
    back = view == "back"
    body = ("M200,250 C130,250 98,282 94,340 C88,430 84,520 86,590 L314,590 C316,520 312,430 306,340 "
            "C302,282 270,250 200,250 Z")
    svg.shape(body, V_KNIT, lo=V_KNIT_LO, lo_d="M280,260 C312,340 314,480 312,600 L340,600 L340,250 Z")
    if not back and not side:
        svg.path("M200,300 L200,590", width=THIN * 0.8)
        for i in range(6):
            svg.ellipse(212, 330 + i * 40, 4, 4, "#2A211A", None)
        svg.path("M150,270 L200,312 L250,270 L236,262 L200,292 L164,262 Z", V_NECK, INK, THIN)
    if side:
        head = ("M160,104 C212,92 262,118 270,158 C278,190 280,220 272,240 C262,266 228,278 196,276 "
                "C150,274 124,250 120,208 C118,162 128,112 160,104 Z")
    else:
        head = ("M200,100 C258,100 284,142 286,188 C288,236 264,270 200,272 C136,270 112,236 114,188 "
                "C116,142 142,100 200,100 Z")
    svg.shape(head, V_SKIN, hi=V_SKIN_HI, hi_d="M130,110 C116,160 120,230 150,272 L100,280 L100,100 Z",
              lo=V_SKIN_LO, lo_d="M272,130 C292,190 286,250 240,280 L300,280 L300,120 Z")
    if view == "front":
        for x in (174, 226):
            svg.ellipse(x, 186, 9, 5, "#FFFFFF", INK, THIN * 0.8)
            svg.ellipse(x, 187, 3, 3, INK, None)
            svg.path(f"M{x - 12},180 Q{x},174 {x + 12},180", width=THIN)
        svg.path("M192,186 C190,204 186,212 188,218 C192,224 208,224 212,218 C214,212 210,204 208,186", width=THIN)
        svg.path("M184,238 L216,238 L214,248 L186,248 Z", INK, None)
        svg.path("M192,239 L192,247 M200,239 L200,247 M208,239 L208,247", stroke="#FFFFFF", width=2.0)
        svg.path("M156,232 C160,256 176,266 200,266 C224,266 240,256 244,232", width=THIN * 0.8)
    elif side:
        svg.ellipse(246, 182, 7, 4.5, "#FFFFFF", INK, THIN * 0.8)
        svg.ellipse(249, 183, 2.6, 2.6, INK, None)
        svg.path("M262,182 C276,198 284,212 280,220 C276,224 266,222 262,218", V_SKIN, INK, THIN * 1.2)
        svg.path("M260,240 L280,240 L278,248 L262,248 Z", INK, None)
    scarf = ("M118,196 C108,120 140,82 200,80 C260,82 292,120 282,196 C276,166 262,128 200,124 "
             "C138,128 124,166 118,196 Z") if not side else (
             "M122,206 C112,128 142,86 196,84 C252,86 278,124 270,170 C252,132 220,124 190,126 "
             "C150,130 130,170 122,206 Z")
    if back:
        scarf = "M112,210 C100,120 140,80 200,78 C260,80 300,120 288,210 C280,250 250,272 200,276 C150,272 120,250 112,210 Z"
    svg.shape(scarf, V_SCARF, lo=V_SCARF_LO, lo_d="M250,90 C290,130 296,190 284,240 L320,240 L320,80 Z")
    return svg.text()


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    files: dict[str, str] = {}
    for view in ("front", "back", "side"):
        files[f"ilyusha_{view}_idle.svg"] = ilyusha(view, -1)
        for k in range(4):
            files[f"ilyusha_{view}_walk{k}.svg"] = ilyusha(view, k)
        files[f"babka_{view}_idle.svg"] = babka(view)
        files[f"vendor_{view}_idle.svg"] = vendor(view)
    for name, text in files.items():
        (OUT / name).write_text(text, encoding="utf-8")
    print(f"CHARACTERS: {len(files)} files -> {OUT}")


if __name__ == "__main__":
    main()
