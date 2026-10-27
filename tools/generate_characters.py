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


# ---------------------------------------------------------------- Бабка и продавщица
# Пропорции — по независимой сверке с V01/V02 (ART-01, раздел «Сверка по роликам»): голова ≈0,32 роста,
# лицо — высокая груша с брылями (рот на 0,43 высоты лица), низкий мягкий чепец, шеи нет,
# тело-бочонок в 2,4–3 ширины лица, руки входят в массу тела, свет — мягкие пятна.

FACE = 3.0  # тонкие черты лица у старших персонажей

B_SKIN, B_SKIN_LO = "#FFFDE2", "#F1EECB"
B_NAPE = "#EBDC9E"
B_HAT, B_HAT_LIGHT = "#A9AD6E", "#C4C68C"
B_DRESS, B_DRESS_LIGHT, B_DRESS_DARK = "#B6BA78", "#CDCF92", "#9A9E66"
B_STOCK, B_BOOT = "#C2BF96", "#8A7E60"


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


def jabot(svg: Svg, cx: float, top: float, bottom: float, half: float, n: int, depth: float) -> None:
    """Воротник-жабо одной лентой: боковины поднимаются за брылями, наружный край — фестоны."""
    outer = []
    for i in range(n + 1):
        t = math.pi - math.pi * i / n
        outer.append((cx + half * math.cos(t), top + (bottom - top) * math.sin(t)))
    d = f"M{outer[0][0]:.1f},{outer[0][1]:.1f}"
    for (x0, y0), (x1, y1) in zip(outer, outer[1:]):
        mx, my = (x0 + x1) / 2, (y0 + y1) / 2
        nx, ny = mx - cx, my - top
        k = depth / max(1.0, math.hypot(nx, ny))
        d += f" Q{mx + nx * k:.1f},{my + ny * k:.1f} {x1:.1f},{y1:.1f}"
    inner = half - depth * 1.2
    d += f" C{cx + inner:.1f},{bottom - 8:.1f} {cx - inner:.1f},{bottom - 8:.1f} {outer[0][0]:.1f},{outer[0][1]:.1f} Z"
    svg.path(d, LACE, INK, LINE * 0.7)


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


FACE_PEAR = ("M145,100 C170,92 230,92 255,100 C266,112 272,126 274,139 C279,158 283,176 283,193 "
             "C283,222 250,240 200,240 C150,240 117,222 117,193 C117,176 121,158 126,139 C128,126 134,112 145,100 Z")
BARREL = ("M105,235 C80,250 55,270 45,300 C30,335 25,370 25,400 C25,460 35,520 45,568 "
          "C140,580 260,580 355,568 C365,520 375,460 375,400 C375,370 370,335 355,300 C345,270 320,250 295,235 "
          "C260,226 140,226 105,235 Z")
BACK_BARREL = ("M120,200 C80,215 55,265 45,300 C30,335 25,370 25,400 C25,460 35,520 45,568 "
               "C140,580 260,580 355,568 C365,520 375,460 375,400 C375,370 370,335 355,300 C345,265 320,215 280,200 "
               "C240,192 160,192 120,200 Z")
CAP_FRONT = ("M130,170 C126,140 130,100 134,76 C135,64 142,58 154,57 C180,53 220,53 246,57 "
             "C258,58 265,64 266,76 C270,100 274,140 270,170 Z")


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
        svg.path(d, "none", B_SKIN, 14 - LINE * 0.6)
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
        jabot(svg, 200, 200, 252, 99, 14, 10)
        scallops(svg, [(103, 200), (297, 200)], 9, LACE)
        with svg.group("rotate(-4 200 120)"):
            soft_shape(svg, CAP_FRONT, B_HAT, [(176, 78, 50, 26, B_HAT_LIGHT)], LINE * 0.7)
            frill_up(svg, (148, 100), (252, 100), 20, 9)
        for x, s in ((122, -1), (278, 1)):
            svg.path(f"M{x},132 C{x + 13 * s},132 {x + 13 * s},152 {x},152 Z", B_SKIN, INK, FACE)
        soft_shape(svg, FACE_PEAR, B_SKIN, [(172, 150, 60, 70, "#FFFFFF"), (262, 205, 40, 46, B_SKIN_LO),
                                            (138, 205, 34, 40, B_SKIN_LO)])
        for x in (176, 224):
            svg.path(f"M{x - 6},139 Q{x},135 {x + 6},139 Q{x},143 {x - 6},139 Z", "#FFFFFF", INK, FACE * 0.8)
            svg.ellipse(x + 1.5, 139, 2.0, 2.0, INK, None)
            svg.path(f"M{x - 6},145 Q{x},148 {x + 6},145", width=FACE * 0.7)
        svg.path("M194,138 C193,152 194,158 200,158 C206,158 207,152 206,138", width=FACE)
        svg.path("M188,150 C182,164 178,176 176,188 M212,150 C218,164 222,176 224,188", width=FACE)
        svg.path("M188,165 Q200,161 212,165 M196,170 L204,170", width=FACE)
        svg.path("M184,200 Q200,206 216,200", width=FACE)
        svg.path("M142,198 Q156,208 170,202 M258,198 Q244,208 230,202", width=FACE * 0.9)
        svg.path("M180,224 Q200,230 220,224", width=FACE * 0.8)
    elif view == "back":
        babka_feet(svg)
        soft_shape(svg, BACK_BARREL, B_DRESS, [(200, 360, 140, 120, B_DRESS_LIGHT)])
        svg.path("M70,290 C62,330 60,360 62,385 M330,290 C338,330 340,360 338,385", width=FACE * 1.2)
        svg.path("M150,470 Q200,482 250,470", width=FACE * 0.8)
        babka_hand(svg, 58, 408, -1, nails=False)
        babka_hand(svg, 342, 408, 1, nails=False)
        svg.path("M138,166 C138,186 150,202 200,204 C250,202 262,186 262,166 Z", B_NAPE, INK, LINE * 0.8)
        svg.path("M176,194 Q200,200 224,194", width=FACE * 0.7)
        for x, s in ((130, -1), (270, 1)):
            svg.path(f"M{x},150 C{x + 13 * s},150 {x + 13 * s},170 {x},170 Z", B_SKIN, INK, FACE)
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
        frill_band(svg, 215, 256, 66, 6, math.radians(186), math.radians(-6), 11, 10)
        head = ("M140,110 L262,112 C266,128 270,140 272,150 C284,152 292,160 290,170 C289,176 284,178 280,176 "
                "C278,180 274,182 272,183 C278,188 280,195 276,200 C282,208 280,218 272,224 "
                "C268,234 262,242 255,246 L142,246 C138,200 138,150 140,110 Z")
        head = ("M142,110 L262,112 C266,120 267,126 268,130 C276,140 286,152 290,163 C288,167 282,166 277,162 "
                "C276,166 273,168 270,168 C272,172 274,174 272,178 C282,184 288,192 284,202 "
                "C290,212 290,226 282,236 C276,246 266,250 255,250 L134,250 C128,220 130,190 136,170 "
                "C138,150 138,130 142,110 Z")
        soft_shape(svg, head, B_SKIN, [(250, 150, 40, 60, "#FFFFFF"), (165, 210, 36, 50, B_SKIN_LO)])
        svg.path("M252,145 Q258,141 264,145 Q258,148 252,145 Z", "#FFFFFF", INK, FACE * 0.8)
        svg.ellipse(259, 145, 1.8, 1.8, INK, None)
        svg.path("M264,172 L272,172", width=FACE)
        svg.path("M190,190 C204,208 222,224 240,235 M258,204 L278,204", width=FACE * 0.9)
        svg.path("M183,155 C171,155 171,175 183,175 Z", B_SKIN, INK, FACE)
        cap = ("M264,114 C258,94 250,80 238,70 C220,58 180,56 156,66 C134,76 122,96 124,118 "
               "C125,135 130,152 140,166 C180,150 225,128 264,114 Z")
        soft_shape(svg, cap, B_HAT, [(196, 82, 54, 30, B_HAT_LIGHT)], LINE * 0.7)
        frill_up(svg, (262, 112), (212, 128), 10, 5)
    return svg.text()


V_SKIN, V_SKIN_LO = "#F5EBBB", "#E2D59C"
V_SCARF, V_SCARF_LIGHT = "#8C3B3B", "#A9504C"
V_KNIT, V_KNIT_LIGHT = "#4E3B2D", "#64503E"
V_BLOUSE = "#D9CFB8"
V_NECK = "#C9433A"

V_FACE = ("M150,98 C138,112 132,126 132,140 C124,166 118,194 120,216 C122,244 158,256 200,256 "
          "C242,256 278,244 280,216 C282,194 276,166 268,140 C268,126 262,112 250,98 Z")
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
        svg.path("M168,262 L200,292 L232,262 L222,256 L200,276 L178,256 Z", V_NECK, INK, FACE)
        soft_shape(svg, V_FACE, V_SKIN, [(178, 140, 44, 60, "#FFFDEB"), (250, 210, 36, 44, V_SKIN_LO)])
        svg.path("M176,108 Q200,104 224,108 M172,117 Q200,113 228,117", width=FACE * 0.8)
        for x in (178, 222):
            svg.path(f"M{x - 7},159 Q{x},153 {x + 7},159 Q{x},163 {x - 7},159 Z", "#FFFFFF", INK, FACE * 0.8)
            svg.ellipse(x, 159, 2.2, 2.2, INK, None)
            svg.path(f"M{x - 8},167 Q{x},172 {x + 8},167", width=FACE * 0.7)
        svg.path("M195,156 C194,168 195,174 200,174 C205,174 206,168 205,156", width=FACE)
        svg.path("M184,186 C196,182 204,182 216,186 L214,194 L186,194 Z", INK, None)
        svg.path("M192,186 L192,193 M200,185 L200,193 M208,186 L208,193", stroke="#FFFFFF", width=1.8)
        svg.path("M184,162 C174,184 172,206 176,222 M216,162 C226,184 228,206 224,222", width=FACE * 0.9)
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
