#!/usr/bin/env python3
"""Рисунки персонажей ART-01: Илюша, Бабка, продавщица; EXT-01: полицейский, «военком»; PEOPLE-01: жители — SVG собственной работы.

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

P_SKIN, P_SKIN_LO, P_SKIN_HI = "#EFDB93", "#D4BC74", "#FBF1C4"      # крупное бледно-жёлтое лицо с брылями (e01, e03)
P_COAT, P_COAT_HI, P_COAT_LO = "#232B45", "#34405F", "#161B2C"      # тёмно-синяя шинель до колен
P_HAT, P_HAT_HI = "#1B2136", "#2C3450"                              # ушанка
P_BAND, P_BAND_HI = "#2F63D8", "#5A8BEE"                            # синяя повязка на левом рукаве
P_BOOT, P_PANTS = "#1A1718", "#1D2338"
NOTE_PAPER, PENCIL, BRASS = "#F3F1E6", "#E9B93A", "#C9B35A"

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


def police_boots(svg: Svg, xs: tuple[float, float] = (158, 242)) -> None:
    for x, s in zip(xs, (-1, 1)):
        svg.path(f"M{x - 20},496 L{x + 20},496 L{x + 20},552 L{x - 20},552 Z", P_PANTS, INK, LINE * 0.7)
        with svg.group(f"rotate({s * 8} {x} 580)"):
            svg.path(f"M{x - 24},548 C{x - 28},576 {x - 16},592 {x + 2},592 C{x + 22},592 {x + 34},584 {x + 30},566 "
                     f"C{x + 26},554 {x + 20},548 {x + 22},540 L{x - 22},540 Z", P_BOOT, INK, LINE * 0.8)
            svg.path(f"M{x - 18},548 Q{x},554 {x + 18},548", width=THIN * 0.7)


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


def police_face(svg: Svg) -> None:
    # Маленькие глаза близко к центру под сердитыми бровями-«галочкой», усики щёткой, рот прямой чертой,
    # носогубные складки к брылям, три складки по нижнему краю (e01, e03).
    for x, s in ((182, -1), (218, 1)):
        svg.path(f"M{x - 8},183 Q{x},178 {x + 8},183 Q{x},188 {x - 8},183 Z", "#FFFFFF", INK, FACE * 0.8)
        svg.ellipse(x - 1.5 * s, 183.5, 2.6, 2.6, INK, None)
        # Бровь: внешний конец выше, внутренний опущен к переносице.
        svg.path(f"M{x + 15 * s},169 Q{x + 4 * s},170 {x - 9 * s},177", "none", INK, FACE * 2.2)
        svg.path(f"M{x - 7},191 Q{x},194 {x + 7},191", width=FACE * 0.6)
    svg.path("M193,174 L196,178 M207,174 L204,178", width=FACE * 0.7)                 # морщинки хмурого лба
    svg.path("M200,180 C196,190 194,199 199,203 C204,205 207,200 205,195", width=FACE)
    brush_moustache(svg, 183, 217, 205, 215)
    svg.path("M189,231 Q200,228.5 211,231", width=FACE)                              # рот прямой чертой
    svg.path("M180,200 C170,214 166,232 170,248 M220,200 C230,214 234,232 230,248", width=FACE * 0.9)
    for d in ("M138,248 Q156,262 176,254", "M184,258 Q200,267 216,258", "M224,254 Q244,262 262,248"):
        svg.path(d, width=FACE * 0.9)                                                  # три складки брылей


# Ушанка (e01, e03, e05): плоский верх, меховой фестончатый край, ≈0,37 роста, шире лица в ≈1,4 раза по брылям;
# передний клапан поднят над бровями, уши-клапаны висят снаружи узкого верха лица, брыли ложатся поверх их низа.
U_CROWN = superellipse(200, 106, 108, 34, 4, 24)
U_BAND = superellipse(200, 130, 116, 28, 5, 28)
U_FLAPS = [superellipse(200 + 88 * s, 208, 28, 52, 2.4, 16, rot=-8 * s) for s in (-1, 1)]
U_BACK = superellipse(200, 170, 116, 66, 3.2, 28)       # задний клапан со спины: закрывает затылок до шеи


def ushanka_flaps(svg: Svg) -> None:
    for pts, s in zip(U_FLAPS, (-1, 1)):
        soft_shape(svg, fur_d(pts, 7), P_HAT, [(200 + 96 * s, 200, 13, 34, P_HAT_HI)], LINE * 0.8)
        fur_strokes(svg, [(200 + (90 + 8 * (i % 2)) * s, 178 + i * 16) for i in range(5)])


def ushanka_front(svg: Svg, back: bool = False) -> None:
    soft_shape(svg, fur_d(U_CROWN, 7), P_HAT, [(178, 90, 62, 18, P_HAT_HI)], LINE * 0.8)
    if back:
        soft_shape(svg, fur_d(U_BACK, 8), P_HAT, [(218, 150, 80, 40, P_HAT_HI)], LINE * 0.8)
        fur_strokes(svg, [(108 + i * 23, 150 + 22 * (i % 3)) for i in range(9)])
        svg.path("M98,116 Q200,102 302,116", "none", INK, THIN * 0.8)       # шов: верх ушанки и задний клапан
        return
    soft_shape(svg, fur_d(U_BAND, 8), P_HAT, [(170, 120, 70, 16, P_HAT_HI)], LINE * 0.8)
    fur_strokes(svg, [(98 + i * 21, 120 + 12 * (i % 3)) for i in range(11)])
    svg.ellipse(200, 129, 6.5, 6.5, BRASS, INK, THIN)   # простой диск вместо кокарды: без реальных эмблем
    svg.ellipse(200, 129, 2.3, 2.3, INK, None)


def ushanka_side(svg: Svg) -> None:
    """Ушанка в профиль (лицом вправо): спереди поднятый клапан, сзади ухо-клапан и затылочный клапан вместе."""
    soft_shape(svg, fur_d(superellipse(150, 186, 48, 64, 2.6, 18, rot=12), 5), P_HAT,
               [(140, 176, 22, 36, P_HAT_HI)], LINE * 0.8)
    fur_strokes(svg, [(126 + 10 * (i % 2), 160 + i * 16) for i in range(5)])
    soft_shape(svg, fur_d(superellipse(196, 106, 99, 34, 4, 22), 5), P_HAT, [(174, 90, 56, 18, P_HAT_HI)], LINE * 0.8)
    soft_shape(svg, fur_d(superellipse(196, 136, 96, 18, 5, 22), 5), P_HAT, [(166, 132, 54, 9, P_HAT_HI)], LINE * 0.8)
    soft_shape(svg, fur_d(superellipse(262, 126, 36, 32, 3, 16), 5), P_HAT, [(253, 119, 20, 16, P_HAT_HI)], LINE * 0.8)
    fur_strokes(svg, [(246 + 9 * (i % 2), 112 + i * 11) for i in range(4)])


POLICE_HEAD = ("M200,146 C226,146 246,152 256,164 C266,178 272,196 278,214 C286,234 291,252 285,264 "
               "C280,273 270,279 258,277 C250,276 242,273 236,268 C228,274 214,276 200,275 "
               "C186,276 172,274 164,268 C158,273 150,276 142,277 C130,279 120,273 115,264 "
               "C109,252 114,234 122,214 C128,196 134,178 144,164 C154,152 174,146 200,146 Z")
POLICE_BODY = ("M126,262 C76,276 46,330 40,400 C36,452 42,486 50,504 L350,504 C358,486 364,452 360,400 "
               "C354,330 324,276 274,262 C250,254 150,254 126,262 Z")
P_FIGURE_K = 1.1   # вся фигура вокруг ступней: рост облика прежний при height_m 2,05, хотя голова стала меньше
P_HEAD_K = 0.74    # лицо-«груша» ≈0,18 роста, низ к лбу ≈1,55, ушанка ≈0,37 (сверка 28.10: e01/e03 0,33–0,38)


def police(view: str) -> str:
    svg = Svg()
    with svg.group(f"translate(200,590) scale({P_FIGURE_K}) translate(-200,-590)"):
        police_figure(svg, view)
    return svg.text()


def police_figure(svg: Svg, view: str) -> None:
    head_k = f"translate(200,270) scale({P_HEAD_K}) translate(-200,-270)"
    if view == "front":
        police_boots(svg)
        soft_shape(svg, POLICE_BODY, P_COAT, [(150, 350, 90, 90, P_COAT_HI), (52, 420, 48, 150, P_COAT_LO),
                                              (352, 430, 44, 140, P_COAT_LO)])
        svg.path("M200,290 L200,500", width=THIN * 0.8)
        for x in (176, 224):
            for y in (338, 384, 430, 476):
                svg.ellipse(x, y, 4, 4, BRASS, INK, THIN * 0.7)
        # Воротник и галстук.
        svg.path("M160,262 C176,282 190,296 200,306 C210,296 224,282 240,262 Z", P_COAT_LO, INK, LINE * 0.8)
        svg.path("M186,262 L200,286 L214,262 Z", "#F2EEE4", INK, FACE)
        svg.path("M196,270 L204,270 L206,300 L200,308 L194,300 Z", INK, INK, FACE * 0.6)
        # Рукава: оба согнуты вперёд, кисти сходятся у блокнота. Правый рукав (его левая рука) — с повязкой.
        tube(svg, "M118,292 C78,318 62,362 82,396 C100,418 136,420 164,408", 60, P_COAT, P_COAT_LO)
        tube(svg, "M282,292 C322,318 338,362 318,396 C300,418 264,420 236,408", 60, P_COAT, P_COAT_LO)
        svg.path("M294,318 C312,328 324,342 330,356 L352,344 C346,326 332,308 312,296 Z", P_BAND, INK, LINE * 0.8)
        svg.path("M304,310 C318,320 328,334 334,346", "none", P_BAND_HI, 4, extra=' opacity="0.8"')
        # Блокнот на пружине и карандаш.
        svg.path("M190,352 L254,352 L254,432 L190,432 Z", NOTE_PAPER, INK, LINE * 0.8)
        for x in range(198, 250, 10):
            svg.ellipse(x, 352, 3.2, 4, "none", INK, THIN * 0.7)
        for y in (378, 392, 406, 420):
            svg.path(f"M198,{y} L246,{y}", width=THIN * 0.5, extra=' opacity="0.5"')
        svg.path("M166,390 L204,348", "none", INK, 9)
        svg.path("M166,390 L204,348", "none", PENCIL, 9 - LINE * 1.4)
        svg.path("M198,354 L208,344 L204,342 Z", "#F6E4B0", INK, THIN * 0.6)
        # Кисти: пухлые, четыре коротких пальца.
        for x, y, s in ((162, 406, -1), (244, 410, 1)):
            svg.ellipse(x, y, 22, 18, P_SKIN, INK, LINE * 0.8)
            for k in range(4):
                fx = x - 12 + k * 8
                svg.path(f"M{fx},{y + 8} L{fx + s},{y + 24}", "none", INK, 8)
                svg.path(f"M{fx},{y + 8} L{fx + s},{y + 24}", "none", P_SKIN, 8 - LINE * 1.2)
            svg.ellipse(x, y, 20, 15, P_SKIN, None)
        # Голова-груша с брылями между опущенными ушами ушанки, сверху плоская меховая ушанка.
        with svg.group(head_k):
            ushanka_flaps(svg)
            soft_shape(svg, POLICE_HEAD, P_SKIN, [(184, 176, 40, 30, P_SKIN_HI), (258, 238, 34, 34, P_SKIN_LO),
                                                  (142, 240, 30, 30, P_SKIN_LO), (200, 284, 96, 16, P_SKIN_LO),
                                                  (156, 247, 14, 5, P_SKIN_HI), (200, 253, 13, 5, P_SKIN_HI),
                                                  (244, 247, 14, 5, P_SKIN_HI)])
            police_face(svg)
            ushanka_front(svg)
    elif view == "back":
        police_boots(svg)
        soft_shape(svg, POLICE_BODY, P_COAT, [(230, 360, 110, 110, P_COAT_HI), (50, 420, 44, 150, P_COAT_LO)])
        svg.path("M200,276 L200,500", width=THIN * 0.8)
        svg.path("M60,460 Q200,470 340,460", width=THIN * 0.7)                 # шлица-строчка
        tube(svg, "M112,296 C72,330 56,380 66,420", 60, P_COAT, P_COAT_LO)
        tube(svg, "M288,296 C328,330 344,380 334,420", 60, P_COAT, P_COAT_LO)
        svg.path("M76,330 C92,344 100,360 106,374 L84,386 C78,370 68,354 58,344 Z", P_BAND, INK, LINE * 0.8)   # левая рука — слева от зрителя
        for x, y in ((66, 424), (334, 424)):
            svg.ellipse(x, y, 20, 17, P_SKIN, INK, LINE * 0.8)
        # Со спины видна только узкая полоса шеи между задним клапаном ушанки и воротником.
        with svg.group(head_k):
            soft_shape(svg, "M150,222 C150,252 166,270 200,272 C234,270 250,252 250,222 Z", P_SKIN,
                       [(186, 246, 30, 14, P_SKIN_HI), (240, 256, 20, 14, P_SKIN_LO)])
            svg.path("M162,256 Q200,264 238,256", width=FACE * 0.8)        # складка затылка
        svg.path("M146,258 C150,282 250,282 254,258 L256,272 C246,294 154,294 144,272 Z", P_COAT_LO, INK, LINE * 0.8)   # воротник
        with svg.group(head_k):
            ushanka_flaps(svg)
            ushanka_front(svg, back=True)
    else:  # side, лицом вправо
        svg.path("M172,496 L236,496 L236,552 L172,552 Z", P_PANTS, INK, LINE * 0.7)
        svg.path("M170,548 C166,574 178,592 200,592 L270,592 C290,592 294,572 276,562 C258,554 244,548 240,540 L174,540 Z",
                 P_BOOT, INK, LINE * 0.8)
        body = ("M118,274 C84,300 72,380 80,504 L298,504 C318,440 326,340 304,284 C292,262 240,252 200,252 "
                "C170,252 136,258 118,274 Z")
        soft_shape(svg, body, P_COAT, [(240, 360, 90, 110, P_COAT_HI), (92, 420, 40, 140, P_COAT_LO)])
        svg.path("M286,296 C300,360 296,440 282,504", width=THIN * 0.8)        # борт шинели
        for y in (340, 386, 432, 478):
            svg.ellipse(276 - (y - 340) * 0.05, y, 4, 4, BRASS, INK, THIN * 0.7)
        svg.path("M248,262 C258,278 266,290 272,300", P_COAT_LO, INK, LINE * 0.8)
        # Рука (ближняя, правая) согнута перед собой: блокнот, карандаш.
        tube(svg, "M200,296 C172,326 164,372 186,396 C204,414 232,414 252,404", 58, P_COAT, P_COAT_LO)
        svg.path("M240,350 L292,340 L302,422 L250,432 Z", NOTE_PAPER, INK, LINE * 0.8)
        for i in range(5):
            svg.ellipse(250 + i * 10, 348 - i * 2, 3.2, 4, "none", INK, THIN * 0.7)
        svg.path("M246,392 L276,336", "none", INK, 9)
        svg.path("M246,392 L276,336", "none", PENCIL, 9 - LINE * 1.4)
        svg.ellipse(254, 404, 22, 18, P_SKIN, INK, LINE * 0.8)
        for k in range(4):
            fx = 244 + k * 8
            svg.path(f"M{fx},410 L{fx + 1},428", "none", INK, 8)
            svg.path(f"M{fx},410 L{fx + 1},428", "none", P_SKIN, 8 - LINE * 1.2)
        svg.ellipse(254, 404, 20, 15, P_SKIN, None)
        # Голова в профиль: круглое лицо, брыль, нос, усы; клапан ушанки — у уха и затылка, не на щеке.
        with svg.group(f"translate(206,270) scale({P_HEAD_K}) translate(-206,-270)"):
            head = ("M138,110 C170,92 232,94 258,120 C276,140 282,166 290,190 C300,218 292,250 262,264 "
                    "C232,274 160,272 138,256 C116,238 114,180 122,150 C126,132 130,118 138,110 Z")
            soft_shape(svg, head, P_SKIN, [(240, 170, 50, 60, P_SKIN_HI), (176, 236, 40, 30, P_SKIN_LO)])
            svg.path("M246,182 Q254,176 262,182 Q254,188 246,182 Z", "#FFFFFF", INK, FACE * 0.8)
            svg.ellipse(257, 182, 2.6, 2.6, INK, None)
            svg.path("M238,168 Q252,169 266,176", "none", INK, FACE * 2.2)
            svg.path("M276,186 C290,194 298,206 292,214 C286,218 278,214 276,208", P_SKIN, INK, FACE)   # нос
            brush_moustache(svg, 262, 290, 212, 222)                                          # усы-щётка
            svg.path("M262,238 Q276,234 286,240", width=FACE)
            svg.path("M206,214 C214,236 230,248 248,246", width=FACE * 0.9)
            svg.path("M190,256 Q224,266 258,256", width=FACE * 0.8)
            ushanka_side(svg)


# «Военком» (e03): высокий и худой; голова ≈0,22 роста, лицо узкое и длинное ≈0,10 роста, длинная тонкая шея
# с кадыком, фуражка с высокой тульей и красным околышем; двубортная буро-оливковая шинель без ремня, красные
# погоны без знаков, папка-планшет у груди. Холст: верх тульи y=16, подбородок y=147, ступни y=590.
# Сутулость (e03): голова на шее вынесена вперёд и опущена — сдвиг O_STOOP_* всей головы с фуражкой.
OFFICER_FACE = ("M172,62 C170,80 170,98 172,112 C174,128 184,146 200,147 C216,146 226,128 228,112 "
                "C230,98 230,80 228,62 Z")
OFFICER_BODY = ("M186,166 C170,168 152,172 142,182 C134,194 132,214 132,240 C130,320 124,420 118,508 "
                "L282,508 C276,420 270,320 268,240 C268,214 266,194 258,182 C248,172 230,168 214,166 Z")
O_TUFT = ("M176,56 C164,56 154,60 147,68 L157,71 C150,77 146,85 145,94 L155,90 C155,97 157,103 161,108 "
          "L167,99 L170,104 L174,90 Z")      # вихры седых волос в стороны из-под околыша
O_EAR = "M174,80 C165,74 157,80 158,91 C159,102 166,107 174,103"
O_STOOP_FRONT = (3, 7)     # в фас голова ниже и чуть в сторону взгляда
O_STOOP_SIDE = (10, 7)     # в профиль голова вперёд, шея наклонена, спина горбится
O_STOOP_BACK = (0, 7)


def officer_cap(svg: Svg, view: str) -> None:
    if view == "side":
        crown = "M172,52 C165,44 165,34 174,28 C188,20 214,14 236,13 C247,14 249,25 243,36 C241,42 239,48 237,52 Z"
        soft_shape(svg, crown, O_CAP, [(206, 30, 28, 12, O_CAP_HI)], LINE * 0.8)
        svg.path("M174,50 L237,50 C239,56 239,60 237,64 L174,64 C172,60 172,56 174,50 Z", O_CAP_BAND, INK, LINE * 0.8)
        svg.path("M230,62 C242,62 254,64 262,68 C264,71 262,74 257,74 C247,72 237,71 228,71 Z", O_VISOR, INK, LINE * 0.8)
        return
    # Высокая тулья с поднятым передом: верх выше всего над серединой, по бокам ниже.
    crown = "M160,52 C150,46 149,34 157,28 C170,20 186,15 200,15 C214,15 230,20 243,28 C251,34 250,46 240,52 Z"
    soft_shape(svg, crown, O_CAP, [(184, 30, 30, 12, O_CAP_HI)], LINE * 0.8)
    svg.path("M166,50 L234,50 C236,56 236,60 234,64 L166,64 C164,60 164,56 166,50 Z", O_CAP_BAND, INK, LINE * 0.8)
    if view == "front":
        svg.path("M164,63 C180,70 220,70 236,63 L240,68 C222,81 178,81 160,68 Z", O_VISOR, INK, LINE * 0.8)
        svg.ellipse(200, 57, 4.5, 4.5, BRASS, INK, THIN)   # простой диск вместо кокарды
        svg.ellipse(200, 57, 1.6, 1.6, INK, None)


def officer_face(svg: Svg) -> None:
    for x, s in ((189, -1), (211, 1)):
        svg.path(f"M{x - 5},87 Q{x},83 {x + 5},87 Q{x},90 {x - 5},87 Z", "#FFFFFF", INK, FACE * 0.7)
        svg.ellipse(x - 0.8 * s, 87, 1.7, 1.7, INK, None)
        svg.path(f"M{x - 6},85.5 Q{x},81 {x + 6},85.5", width=FACE * 1.1)                  # тяжёлое веко
        svg.path(f"M{x - 5},93 Q{x},96 {x + 5},93", width=FACE * 0.55)                     # мешки
        svg.path(f"M{x + 9 * s},79 Q{x + 2 * s},75 {x - 5 * s},71.5", "none", INK, FACE * 1.7)   # бровь «домиком»
    svg.path("M177,98 C178,110 181,120 184,128 M223,98 C222,110 219,120 216,128", width=FACE * 0.8)   # впалые щёки
    svg.path("M175,96 Q179,94 183,97 M225,96 Q221,94 217,97", width=FACE * 0.6)                   # скулы
    # Рот — кривая гримаса между концами усов (без зубов), уголки вниз, складка подбородка.
    svg.path("M191,139.5 C195,136.8 201,136.6 209,139 C204,140.6 196,141 191,139.5 Z", INK, INK, FACE * 0.7)
    svg.path("M191,139.5 L188.5,143 M209,139 L211.5,142.5", width=FACE * 0.8)
    svg.path("M194,144.5 Q200,146.5 206,144.5", width=FACE * 0.6)
    # Пышные седые усы-подкова шире носа: концы свисают вниз мимо рта.
    must = ("M200,119 C190,116 178,118 173,126 C169,133 170,141 174,146 C177,140 181,135 188,133 "
            "C194,132 198,132 200,133 C202,132 206,132 212,133 C219,135 223,140 226,146 C230,141 231,133 227,126 "
            "C222,118 210,116 200,119 Z")
    soft_shape(svg, must, O_HAIR, [(190, 124, 16, 6, O_HAIR_HI)], FACE * 0.9)
    for x in (180, 186, 192, 208, 214, 220):
        svg.path(f"M{x},{126 if abs(x - 200) < 12 else 129} l{-1.5 if x < 200 else 1.5},7", width=FACE * 0.45)
    # Нос — мясистая «луковица»: узкая переносица, низ ниже верхней губы.
    nose = ("M196,82 C195,92 193,100 190,106 C183,114 182,127 192,132 C196,134 204,134 208,132 "
            "C218,127 217,114 210,106 C207,100 205,92 204,82 Z")
    soft_shape(svg, nose, O_SKIN, [(194, 112, 7, 9, O_SKIN_HI), (210, 126, 10, 8, O_SKIN_LO)], FACE * 1.0)
    svg.path("M193,128 Q196,125.5 199,128 M201,128 Q204,125.5 207,128", width=FACE * 0.6)


def officer_boots(svg: Svg, xs: tuple[float, float] = (182, 218)) -> None:
    for x, s in zip(xs, (-1, 1)):
        svg.path(f"M{x - 9},506 L{x + 9},506 L{x + 9},552 L{x - 9},552 Z", O_PANTS, INK, LINE * 0.7)
        with svg.group(f"rotate({s * 10} {x} 580)"):
            svg.path(f"M{x - 15},546 C{x - 19},574 {x - 10},592 {x + 4},592 C{x + 20},592 {x + 27},584 {x + 22},568 "
                     f"C{x + 18},556 {x + 13},550 {x + 13},540 L{x - 13},540 Z", O_BOOT, INK, LINE * 0.8)


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


def officer_hand_down(svg: Svg, x: float, y: float) -> None:
    """Длинная тонкая кисть висит вниз (e03): ладонь и четыре длинных пальца."""
    for k in range(4):
        fx = x - 6 + k * 4
        svg.path(f"M{fx},{y + 6} L{fx - 0.5 + k * 0.4},{y + 26 + (3 if k in (1, 2) else 0)}", "none", INK, 5.2)
        svg.path(f"M{fx},{y + 6} L{fx - 0.5 + k * 0.4},{y + 26 + (3 if k in (1, 2) else 0)}", "none", O_SKIN, 5.2 - LINE * 1.2)
    svg.ellipse(x, y, 9, 12, O_SKIN, INK, LINE * 0.8)
    svg.ellipse(x, y + 1, 7.5, 10, O_SKIN, None)


def officer(view: str) -> str:
    svg = Svg()
    if view == "front":
        officer_boots(svg)
        soft_shape(svg, OFFICER_BODY, O_COAT, [(176, 260, 40, 90, O_COAT_HI), (130, 440, 22, 110, O_COAT_LO),
                                               (272, 440, 22, 110, O_COAT_LO)])
        svg.path("M188,168 L200,238 L212,168 Z", O_SHIRT, INK, LINE * 0.7)                  # тёмная рубашка в вырезе
        svg.path("M214,240 C214,320 214,420 214,508", width=THIN * 0.9)                    # запах правой полы
        for y in (262, 302, 342, 382):                                                      # два ряда пуговиц
            for x in (182, 222):
                svg.ellipse(x, y, 3.6, 3.6, BRASS, INK, THIN * 0.7)
        for x0, x1 in ((140, 172), (228, 260)):                                             # клапаны карманов
            svg.path(f"M{x0},{402} L{x1},{400} L{x1},{411} L{x0 + 1},{413} Z", O_COAT_LO, INK, THIN * 0.7)
        svg.path("M124,470 Q200,478 276,470", width=THIN * 0.5, extra=' opacity="0.4"')
        # Длинная тонкая шея с кадыком и жилами.
        neck = "M195,139 C194,156 192,174 189,200 L211,200 C210,176 210,156 211,139 Z"
        soft_shape(svg, neck, O_SKIN, [(207, 172, 6, 30, O_SKIN_LO)], LINE * 0.7)
        svg.path("M197,170 C198,164 204,164 205,170", width=FACE * 0.8)                     # кадык
        svg.path("M197,156 L198,192 M208,156 L204,192", width=FACE * 0.45, extra=' opacity="0.6"')
        # Лацканы с вырезом-«нотчем».
        lapel = "M187,166 C178,170 168,178 163,190 L175,197 L169,205 L200,242 C196,214 192,190 189,168 Z"
        for d in (lapel, mirror_d(lapel)):
            soft_shape(svg, d, O_COAT, [(178, 196, 10, 20, O_COAT_HI)], LINE * 0.8)
        for d in ("M142,186 L176,170 L180,181 L147,197 Z", mirror_d("M142,186 L176,170 L180,181 L147,197 Z")):
            svg.path(d, O_STRAP, INK, THIN * 0.8)                                            # погоны без знаков
        # Левая (от зрителя) рука висит до колена; правая согнута и прижимает папку к груди.
        tube(svg, "M148,192 C140,240 136,320 136,402", 30, O_COAT, O_COAT_LO)
        svg.path("M124,396 L148,396", width=THIN * 0.8)
        officer_hand_down(svg, 136, 414)
        tube(svg, "M252,192 C262,232 266,270 262,300", 30, O_COAT, O_COAT_LO)
        clipboard(svg, 242, 282, 46, 76, -8)
        tube(svg, "M262,300 C252,312 238,316 224,312", 28, O_COAT, O_COAT_LO)
        svg.ellipse(220, 306, 9, 10, O_SKIN, INK, LINE * 0.8)
        for k in range(3):   # пальцы обхватывают край папки
            svg.path(f"M{222},{300 + k * 5} L{235},{296 + k * 5}", "none", INK, 5)
            svg.path(f"M{222},{300 + k * 5} L{235},{296 + k * 5}", "none", O_SKIN, 5 - LINE * 1.2)
        svg.ellipse(220, 307, 7.5, 8.5, O_SKIN, None)
        # Голова: вихры, торчащие уши, узкое длинное лицо, фуражка; опущена и вынесена вперёд (сутулость).
        with svg.group("translate(%d,%d)" % O_STOOP_FRONT):
            for d in (O_TUFT, mirror_d(O_TUFT)):
                soft_shape(svg, d, O_HAIR, [(160, 76, 8, 12, O_HAIR_HI)], FACE * 0.9)
            for d in (O_EAR, mirror_d(O_EAR)):
                svg.path(d, O_SKIN, INK, FACE * 0.9)
            svg.path("M171,84 C166,86 165,94 169,98 M229,84 C234,86 235,94 231,98", width=FACE * 0.6)
            soft_shape(svg, OFFICER_FACE, O_SKIN, [(186, 82, 16, 22, O_SKIN_HI), (180, 118, 9, 16, O_SKIN_LO),
                                                   (220, 118, 9, 16, O_SKIN_LO)], LINE * 0.9)
            officer_face(svg)
            officer_cap(svg, "front")
    elif view == "back":
        officer_boots(svg)
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
        tube(svg, "M148,192 C140,240 136,320 136,402", 30, O_COAT, O_COAT_LO)
        svg.path("M124,396 L148,396", width=THIN * 0.8)
        officer_hand_down(svg, 136, 414)
        tube(svg, "M252,192 C262,232 266,270 264,300", 30, O_COAT, O_COAT_LO)            # правая согнута вперёд
        # Затылок — седая масса волос: светлые и тёмные пряди, низ темнее; по бокам торчат уши.
        with svg.group("translate(%d,%d)" % O_STOOP_BACK):
            for d in (O_TUFT, mirror_d(O_TUFT)):
                soft_shape(svg, d, O_HAIR, [(160, 76, 8, 12, O_HAIR_HI), (152, 98, 8, 10, O_HAIR_LO)], FACE * 0.9)
            nape = ("M170,60 C164,76 164,96 171,111 C176,120 184,124 190,122 L194,129 L199,122 L204,129 L209,122 "
                    "C217,124 225,119 229,111 C236,96 236,76 230,60 Z")
            soft_shape(svg, nape, O_HAIR, [(190, 78, 16, 16, O_HAIR_HI), (200, 122, 40, 22, O_HAIR_LO, 0.45)],
                       FACE * 1.0)
            for i, x in enumerate((176, 184, 192, 200, 208, 216, 224)):
                bend = -3 if x < 200 else 3 if x > 200 else 0
                y0 = 66 + abs(x - 200) * 0.25
                strand = f"M{x},{y0:.0f} q{bend},14 {bend * 0.3:.1f},{40 - abs(x - 200) * 0.35:.0f}"
                if i % 2:
                    svg.path(strand, "none", INK, FACE * 1.1)                              # тёмная прядь
                else:
                    svg.path(strand, "none", O_STRAND, FACE * 2.0)                        # светлая прядь
            for d in (O_EAR, mirror_d(O_EAR)):
                svg.path(d, O_SKIN, INK, FACE * 0.9)
            officer_cap(svg, "back")
    else:  # side, лицом вправо
        svg.path("M192,506 L212,506 L212,552 L192,552 Z", O_PANTS, INK, LINE * 0.7)
        svg.path("M188,548 C184,574 194,592 212,592 L250,592 C266,592 268,576 254,566 C242,558 232,552 228,540 L192,540 Z",
                 O_BOOT, INK, LINE * 0.8)
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
        svg.path("M180,174 L210,171 L212,182 L183,186 Z", O_STRAP, INK, THIN * 0.8)        # погон
        # Ближняя рука согнута, папка у груди.
        tube(svg, "M200,188 C192,226 188,262 194,292", 30, O_COAT, O_COAT_LO)
        clipboard(svg, 246, 272, 12, 76, -6)
        tube(svg, "M194,292 C206,300 222,300 236,292", 28, O_COAT, O_COAT_LO)
        svg.ellipse(240, 288, 9, 9, O_SKIN, INK, LINE * 0.8)
        for k in range(3):   # пальцы обхватывают край папки
            svg.path(f"M240,{283 + k * 4} L251,{280 + k * 4}", "none", INK, 5)
            svg.path(f"M240,{283 + k * 4} L251,{280 + k * 4}", "none", O_SKIN, 5 - LINE * 1.2)
        svg.ellipse(240, 289, 7.5, 7.5, O_SKIN, None)
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
    return svg.text()


# ---------------------------------------------------------------- PEOPLE-01: жители города Н.
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
            svg.path("M150,268 Q200,300 250,268", width=THIN * 0.8)                              # складка у узла
            svg.path("M200,136 C196,180 196,230 200,280", width=THIN * 0.6, extra=' opacity="0.7"')
            rb_platok_dots(svg, [(172, 160), (226, 158), (200, 200), (160, 222), (240, 222), (200, 252),
                                 (176, 300), (224, 300), (200, 340)])
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


RESIDENTS = {"babka": resident_babka, "man": resident_man, "woman": resident_woman, "boy": resident_boy}


def main() -> None:
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
        for name, draw in RESIDENTS.items():   # PEOPLE-01
            files[f"resident_{name}_{view}_idle.svg"] = draw(view)
    for name, text in files.items():
        (OUT / name).write_text(text, encoding="utf-8")
    print(f"CHARACTERS: {len(files)} files -> {OUT}")


if __name__ == "__main__":
    main()
