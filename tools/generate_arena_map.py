#!/usr/bin/env python3
"""Export actual Godot Layout and render its derived navigation map. Requires Pillow."""
import argparse
import base64
import hashlib
import html
import json
import math
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, PngImagePlugin

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ["game/world/layout.gd", "game/world/ambient.gd", "game/world/props.gd",
           "game/world/level_geometry.gd", "game/world/perimeter.gd", "game/vehicles/er2k_train_visual.gd",
           "game/vehicles/vehicle_dimensions.gd", "game/vehicles/lada.gd",
           "game/vehicles/niva_visual.gd", "game/vehicles/samara_visual.gd",
           "game/vehicles/gazelle_visual.gd", "game/vehicles/city_van.gd",
           "tools/export_arena_map.gd", "tools/generate_arena_map.py",
           "tools/godot.sh", "project.godot", "assets/fonts/Pangolin-Regular.ttf"]
FONT = ROOT / "assets/fonts/Pangolin-Regular.ttf"
PAPER, INK, SNOW, ROAD = "#f5f2e9", "#263e49", "#eaf0f1", "#7e8d94"
ORANGE, TEAL, RED = "#d47435", "#387d7b", "#aa514c"
SECTOR_COLUMNS = ("А", "Б", "В", "Г", "Д")
SECTOR_ROWS = 5
SECTOR_LINE = "#1769bc"
SECTOR_LINE_WIDTH = 3.5


def fingerprint():
    digest = hashlib.sha256()
    for name in SOURCES:
        digest.update(name.encode() + b"\0" + (ROOT / name).read_bytes() + b"\0")
    return digest.hexdigest()


class Draw:
    """The same primitives, coordinates and font feed SVG and supersampled Pillow."""
    def __init__(self, width, height):
        self.width, self.height, self.aa = width, height, 2
        self.image = Image.new("RGB", (width * 2, height * 2), PAPER)
        self.pen = ImageDraw.Draw(self.image)
        self.svg = [f'<rect width="{width}" height="{height}" fill="{PAPER}"/>']
        self.fonts = {}

    def font(self, size):
        key = round(size * self.aa)
        if key not in self.fonts:
            self.fonts[key] = ImageFont.truetype(str(FONT), key)
        return self.fonts[key]

    def rect(self, box, fill, stroke=None, width=1, radius=0):
        x, y, w, h = box
        self.pen.rounded_rectangle((round(x*2), round(y*2), round((x+w)*2), round((y+h)*2)),
                                   radius=round(radius*2), fill=fill, outline=stroke, width=max(1, round(width*2)))
        self.svg.append(f'<rect x="{x:.2f}" y="{y:.2f}" width="{w:.2f}" height="{h:.2f}" rx="{radius}" fill="{fill}" stroke="{stroke or "none"}" stroke-width="{width}"/>')

    def line(self, points, fill, width=1, dash=None):
        if len(points) < 2: return
        if dash:
            phase, on = 0.0, True
            for a, b in zip(points, points[1:]):
                distance = math.dist(a, b)
                offset = 0.0
                while offset < distance:
                    take = min(dash - phase, distance - offset)
                    if on:
                        p = tuple(a[j] + (b[j]-a[j])*offset/distance for j in (0, 1))
                        q = tuple(a[j] + (b[j]-a[j])*(offset+take)/distance for j in (0, 1))
                        self.pen.line([tuple(round(v*2) for v in p), tuple(round(v*2) for v in q)], fill=fill, width=max(1, round(width*2)))
                    offset += take; phase += take
                    if phase >= dash - 1e-8: phase, on = 0.0, not on
        else:
            self.pen.line([tuple(round(v*2) for v in p) for p in points], fill=fill, width=max(1, round(width*2)), joint="curve")
        coords = " ".join(f"{x:.2f},{y:.2f}" for x, y in points)
        self.svg.append(f'<polyline points="{coords}" fill="none" stroke="{fill}" stroke-width="{width}" stroke-linejoin="round" stroke-dasharray="{dash or "none"}"/>')

    def circle(self, center, radius, fill, stroke=None, width=1):
        x, y = center
        self.pen.ellipse(((x-radius)*2, (y-radius)*2, (x+radius)*2, (y+radius)*2), fill=fill, outline=stroke, width=max(1, round(width*2)))
        self.svg.append(f'<circle cx="{x:.2f}" cy="{y:.2f}" r="{radius}" fill="{fill}" stroke="{stroke or "none"}" stroke-width="{width}"/>')

    def text(self, at, text, size=22, fill=INK, anchor="middle", angle=0, halo=None):
        x, y = at
        font = self.font(size)
        if angle:
            box = font.getbbox(text)
            tile = Image.new("RGBA", (box[2]-box[0]+24, box[3]-box[1]+24))
            ImageDraw.Draw(tile).text((12-box[0],12-box[1]),text,font=font,fill=fill)
            tile = tile.rotate(-angle, expand=True, resample=Image.Resampling.BICUBIC)
            self.image.paste(tile,(round(x*2-tile.width/2),round(y*2-tile.height/2)),tile)
        else:
            self.pen.text((round(x*2), round(y*2)), text, font=font, fill=fill,
                          anchor={"middle":"mm", "start":"lm", "end":"rm"}[anchor],
                          stroke_width=4 if halo else 0, stroke_fill=halo)
        transform = f' transform="rotate({angle} {x:.2f} {y:.2f})"' if angle else ""
        outline = f' stroke="{halo}" stroke-width="4" paint-order="stroke"' if halo else ""
        self.svg.append(f'<text x="{x:.2f}" y="{y:.2f}" font-size="{size}" text-anchor="{anchor}" dominant-baseline="central" fill="{fill}"{transform}{outline}>{html.escape(text)}</text>')

    def save(self, output, metadata):
        output.mkdir(parents=True, exist_ok=True)
        font64 = base64.b64encode(FONT.read_bytes()).decode()
        meta = html.escape(json.dumps(metadata, ensure_ascii=False, sort_keys=True))
        svg = f'<svg xmlns="http://www.w3.org/2000/svg" width="{self.width}" height="{self.height}" viewBox="0 0 {self.width} {self.height}"><metadata id="arena-map">{meta}</metadata><defs><style>@font-face{{font-family:Pangolin;src:url(data:font/ttf;base64,{font64})}}text{{font-family:Pangolin,sans-serif}}</style></defs>' + "\n".join(self.svg) + '</svg>\n'
        (output / "arena.svg").write_text(svg, encoding="utf-8")
        pnginfo = PngImagePlugin.PngInfo()
        pnginfo.add_text("arena-map", json.dumps(metadata, ensure_ascii=False, sort_keys=True))
        self.image.resize((self.width,self.height),Image.Resampling.LANCZOS).save(output/"arena.png",pnginfo=pnginfo)


def clipped_segment(a, b, box):
    low, high = 0.0, 1.0
    for i in (0, 1):
        delta = b[i]-a[i]
        if abs(delta) < 1e-9:
            if not box[i] <= a[i] <= box[i]+box[i+2]: return None
        else:
            u, v = (box[i]-a[i])/delta, (box[i]+box[i+2]-a[i])/delta
            low, high = max(low,min(u,v)), min(high,max(u,v))
    if high <= low: return None
    return [[a[i]+(b[i]-a[i])*t for i in (0,1)] for t in (low,high)]


def sector_grid(bounds):
    """Derive navigation sectors from exported Layout.BOUNDS; +x east, +z south."""
    x_edges = [bounds["x"] + bounds["width"] * i / len(SECTOR_COLUMNS)
               for i in range(len(SECTOR_COLUMNS) + 1)]
    z_edges = [bounds["z"] + bounds["height"] * i / SECTOR_ROWS
               for i in range(SECTOR_ROWS + 1)]
    cells = []
    for row in range(SECTOR_ROWS):
        for column, letter in enumerate(SECTOR_COLUMNS):
            cells.append({"label": f"{letter}{row + 1}", "bounds": {
                "x": x_edges[column], "z": z_edges[row],
                "width": x_edges[column + 1] - x_edges[column],
                "height": z_edges[row + 1] - z_edges[row]}})
    return {"columns": list(SECTOR_COLUMNS), "rows": list(range(1, SECTOR_ROWS + 1)),
            "bounds": dict(bounds), "units": "meters", "axes": {"x": "east", "z": "south"},
            "x_edges": x_edges, "z_edges": z_edges, "cells": cells}


def render(data, output, digest):
    d = Draw(2060, 1810)
    bounds = data["bounds"]
    sectors = sector_grid(bounds)
    scale = min(1180 / bounds["width"], 1460 / bounds["height"])
    left, top = 105, 220
    mw, mh = bounds["width"]*scale, bounds["height"]*scale
    def point(p): return left+(p[0]-bounds["x"])*scale, top+(p[1]-bounds["z"])*scale
    def rect(center, size):
        x,y=point((center[0]-size[0]/2,center[1]-size[1]/2))
        return x,y,size[0]*scale,size[1]*scale
    d.text((105,58),"ШКЯ • НИЧЕГО НЕОБЫЧНОГО",22,RED,"start")
    d.text((105,116),"Арена города Н.",56,INK,"start")
    d.text((105,166),"Зимний квартал • навигационная карта • вид сверху",25,TEAL,"start")
    d.rect((left,top,mw,mh),SNOW,"#b6c6cb",2)
    for surface in data["surfaces"]:
        d.rect(rect(surface["center"],surface["size"]), ROAD if surface["kind"]=="road" else "#d6e0e0" if surface["kind"]=="sidewalk" else "#dee7e5")
    # Above ground surfaces, below buildings, paths, routes and labels.
    for x in sectors["x_edges"][1:-1]:
        d.line([point((x,bounds["z"])),point((x,bounds["z"]+bounds["height"]))],SECTOR_LINE,SECTOR_LINE_WIDTH,dash=9)
    for z in sectors["z_edges"][1:-1]:
        d.line([point((bounds["x"],z)),point((bounds["x"]+bounds["width"],z))],SECTOR_LINE,SECTOR_LINE_WIDTH,dash=9)
    for i, letter in enumerate(sectors["columns"]):
        x=(sectors["x_edges"][i]+sectors["x_edges"][i+1])/2
        d.text((point((x,bounds["z"]))[0],top-27),letter,34,SECTOR_LINE)
    for i, number in enumerate(sectors["rows"]):
        z=(sectors["z_edges"][i]+sectors["z_edges"][i+1])/2
        d.text((left-32,point((bounds["x"],z))[1]),str(number),34,SECTOR_LINE)
    for surface in data["surfaces"]:
        if surface["kind"]=="yard_road":
            c=surface["center"]; size=surface["size"]
            d.text(point((c[0]+size[0]*.24,c[1])),"Двор у Бабки",28,"#96aaa3")
    for edge in data["paths"]:
        d.line([point(edge["from"]),point(edge["to"])],"#a1bdb4",2)
    for item in data["solids"]:
        kind=item["kind"]; size=item["size"]; box=rect(item["center"],[size[0],size[2]])
        if kind in ("snow","snow_bank"):
            d.rect(box,"#fdfefe","#b7cbd4",1)
        elif kind.startswith("perimeter_"):
            fill = "#38715b" if kind in ("perimeter_train", "perimeter_gangway") else "#42668c" if kind=="perimeter_police" else "#7c8783"
            x0, y0 = max(left, box[0]), max(top, box[1])
            x1, y1 = min(left+mw, box[0]+box[2]), min(top+mh, box[1]+box[3])
            if x1 > x0 and y1 > y0:
                d.rect((x0,y0,x1-x0,y1-y0),fill)
        elif kind in ("panel","panel_low","garage","kiosk","shop24","pavilion","parked_car","props","fence"):
            fill = "#4b626b" if kind in ("panel","panel_low") else "#b6a995" if kind=="garage" else "#ad957a" if kind=="parked_car" else "#9ea9a6"
            if kind=="kiosk": fill=ORANGE
            d.rect(box,fill,"#71868a",1,2)
            if kind in ("panel","panel_low"):
                label="Дом Бабки" if item["id"]=="H1_South" else "Жилой дом"
                d.text((box[0]+box[2]/2,box[1]+box[3]/2),label,20,"#f3f3e9",angle=-90 if box[3]>box[2]*1.5 else 0)
            elif kind=="garage":
                d.text((box[0]+box[2]/2,box[1]+box[3]/2),"Гаражи",18,INK,angle=-90 if box[3]>box[2] else 0)
        elif kind in ("tree","poplar"):
            d.circle(point(item["center"]),9 if kind=="poplar" else 6,"#c2d0c5","#99b4a3",1)
    for item in data["breakables"]:
        if item["kind"] in ("fence","barrier","domino","slide","swing","sandpit","fort","stall"):
            size=item["size"]; d.rect(rect(item["center"],[size[0],size[2]]),"#bda988","#9d8d74",1)
    roads=[s for s in data["surfaces"] if s["kind"]=="road"]
    for edge in data["crossings"]:
        for road in roads:
            c,s=road["center"],road["size"]
            clipped=clipped_segment(edge["from"],edge["to"],[c[0]-s[0]/2,c[1]-s[1]/2,*s])
            if not clipped: continue
            a,b=clipped; length=math.dist(a,b); n=max(1,int(length))
            dx,dz=(b[0]-a[0])/length,(b[1]-a[1])/length
            for i in range(n):
                p=[a[j]+(b[j]-a[j])*(i+.5)/n for j in (0,1)]
                d.line([point((p[0]-dz*1.4,p[1]+dx*1.4)),point((p[0]+dz*1.4,p[1]-dx*1.4))],"#f9f7ef",3)
    for door in data["doors"]: d.circle(point(door["point"]),3.5,"#d8af66",PAPER,1)
    d.line([point(p) for p in data["routes"]["car"]],PAPER,8)
    d.line([point(p) for p in data["routes"]["car"]],ORANGE,5,dash=9)
    walk=data["routes"]["walk"]; end=data["routes"]["car"][-1]
    start=min(range(len(walk)),key=lambda i:math.dist(end,walk[i]))
    foot=[end]+walk[start:]
    d.line([point(p) for p in foot],PAPER,7)
    d.line([point(p) for p in foot],TEAL,3.5,dash=5)
    for road in roads:
        c=list(road["center"]); size=road["size"]
        if size[0]>size[1]: c[0] -= size[0]*.18 if road["id"]=="Street_A" else 0
        else:
            c[0]-=size[0]*.25 if road["id"]=="Street_B" else 0
            c[1]+=size[1]*(.08 if road["id"]=="Street_B" else .23)
        name=road["label"].replace("УЛ. ","ул. ").title().replace("Ул.","ул.")
        d.text(point(c),name,24,"#fdf8ea",angle=-90 if size[1]>size[0] else 0,halo=ROAD)
    # Landmark labels are displaced only in screen space; their leader lines retain the real source positions.
    occupied=[(point(p["point"])[0]-13,point(p["point"])[1]-13,point(p["point"])[0]+13,point(p["point"])[1]+13) for p in data["landmarks"]]
    important={"bread","start","car","babka","dog","officer","guard","shop24","stop_a","stop_b","dig"}
    labels=sorted(data["landmarks"],key=lambda x:(x["id"] not in important,x["id"]))
    for item in labels:
        px,py=point(item["point"]); kind=item["kind"]
        color=RED if kind=="post" else ORANGE if kind in ("bread","car","start") else TEAL
        symbol={"bread":"Х","home":"Б","car":"Л","start":"И","post":"!","stop":"Т","dog":"С"}.get(kind,"")
        radius=10 if symbol else 4
        d.circle((px,py),radius,color,PAPER,1.5)
        if symbol: d.text((px,py),symbol,15,PAPER)
        text=item["label"]; fs=21 if item["id"] in important else 19
        width=d.font(fs).getlength(text)/2+16; height=fs+12
        best=None
        for ox,oy in [(18,-20),(18,22),(-width-18,-20),(-width-18,22),(18,-47),(-width-18,48),(18,50),(-width-18,-50)]:
            x=max(left+3,min(px+ox,left+mw-width-3)); y=max(top+8,min(py+oy,top+mh-height))
            box=(x,y-height/2,x+width,y+height/2)
            overlap=sum(max(0,min(box[2],q[2])-max(box[0],q[0]))*max(0,min(box[3],q[3])-max(box[1],q[1])) for q in occupied)
            score=overlap+abs(ox)*.03+abs(oy)*.05
            if best is None or score<best[0]: best=(score,x,y,box)
        _,x,y,box=best; occupied.append(box)
        d.line([(px,py),(x if x>px else x+width,y)],color,1)
        d.rect((x,y-height/2,width,height),PAPER,None,radius=4)
        d.text((x+8,y),text,fs,color,"start")
    sx=1390
    d.text((sx,245),"СЕВЕР",20,TEAL,"start")
    d.line([(sx+150,280),(sx+150,225)],INK,3)
    d.line([(sx+140,240),(sx+150,225),(sx+160,240)],INK,3)
    d.text((sx,330),"Как читать карту",34,INK,"start")
    legend=[("#4b626b","Дома"),("#b6a995","Гаражи"),(ROAD,"Проезжая часть"),("#b7cbd4","Снежные валы; разрывы — проходы"),(TEAL,"Тропинки и пешая связность"),(RED,"Посты у киоска")]
    for i,(color,text) in enumerate(legend):
        y=395+i*60; d.rect((sx,y-10,32,20),color,None,radius=3); d.text((sx+50,y),text,22,INK,"start")
    d.line([(sx,755),(sx+32,755)],SECTOR_LINE,SECTOR_LINE_WIDTH,dash=9)
    d.text((sx+50,755),"Сектора: буква сверху, номер слева.",22,INK,"start")
    d.text((sx+50,789),"Например, В3 — центр карты.",22,INK,"start")
    d.rect((sx-20,820,550,290),"#e8e4d8",None,radius=18)
    d.text((sx,865),"За хлебом",32,INK,"start")
    d.line([(sx,924),(sx+68,924)],ORANGE,5,dash=9);d.text((sx+87,924),"На машине до парковки",23,INK,"start")
    d.line([(sx,979),(sx+68,979)],TEAL,4,dash=5);d.text((sx+87,979),"Дальше к киоску пешком",23,INK,"start")
    d.text((sx,1056),"Старт, «Лада» и Бабка — внизу карты.",21,INK,"start")
    d.text((sx,1190),"Кусочек зимнего города",30,INK,"start")
    for i,text in enumerate(["Карта сохраняет размеры и проходы игры.","Зебры следуют настоящим пешим переходам.","Маленькие золотые точки — входы в дома.","Люди и транспорт здесь не зафиксированы:","они перемещаются во время игры."]):
        d.text((sx,1245+i*39),text,22,INK,"start")
    bar=50*scale; y=top+mh+46
    d.line([(left,y),(left+bar,y)],INK,5)
    for x in [left,left+bar/2,left+bar]: d.line([(x,y-7),(x,y+7)],INK,2)
    for x,text in [(left,"0"),(left+bar/2,"25"),(left+bar,"50 м")]:d.text((x,y+25),text,19,INK)
    d.text((left+mw,y+18),"Размер арены: %g × %g м"%(bounds["width"],bounds["height"]),21,INK,"end")
    metadata={"schema":1,"source_fingerprint":digest,"sources":SOURCES,"coverage":data["coverage"],
              "sector_grid":sectors}
    d.save(output,metadata)


def current(output, digest):
    try:
        meta=ET.parse(output/"arena.svg").getroot().find("{http://www.w3.org/2000/svg}metadata")
        svg=json.loads(meta.text)
        with Image.open(output/"arena.png") as image: png=json.loads(image.info["arena-map"])
        return svg==png and svg["source_fingerprint"]==digest
    except (OSError, ValueError, KeyError, AttributeError, ET.ParseError): return False


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check",action="store_true",help="Check both map artifacts against their actual source files, without launching Godot")
    parser.add_argument("--force",action="store_true",help="Export and regenerate even if the map is current")
    parser.add_argument("--output-dir",type=Path,default=ROOT/"docs/maps")
    args=parser.parse_args(); digest=fingerprint()
    if args.check:
        if not current(args.output_dir,digest):
            print("MAP01: map missing or stale; run python3 tools/generate_arena_map.py",file=sys.stderr);return 1
        print("MAP01: current SVG and PNG");return 0
    if not args.force and current(args.output_dir,digest):
        print("MAP01: current SVG and PNG");return 0
    evidence=ROOT/"builds/checks/MAP-01"; evidence.mkdir(parents=True,exist_ok=True)
    export=evidence/"arena.json"
    command=[str(ROOT/"tools/godot.sh"),"--path",str(ROOT),"--headless","--log-file",str(evidence/"export-runtime.log"),"--script",str(ROOT/"tools/export_arena_map.gd"),"--",str(export)]
    with (evidence/"export.log").open("w") as log:
        result=subprocess.run(command,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,check=False)
    log=(evidence/"export.log").read_text()
    if result.returncode or "MAP01_EXPORT:" not in log or "SCRIPT ERROR" in log:
        print(log,file=sys.stderr);return 1
    if fingerprint()!=digest:
        print("MAP01: sources changed during export; rerun the generator",file=sys.stderr);return 1
    data=json.loads(export.read_text())
    if data.get("schema")!=1 or data.get("units")!="meters":
        raise ValueError("Unsupported native map export")
    for collection, count in [("solids","solids"),("surfaces","surfaces"),("paths","pedestrian_edges"),("crossings","crossings")]:
        if len(data[collection])!=data["coverage"][count]:
            raise ValueError("Incomplete native export: " + collection)
    data["source_fingerprint"]=digest
    data["generator_sources"]=SOURCES
    export.write_text(json.dumps(data,ensure_ascii=False,sort_keys=True,indent=2)+"\n",encoding="utf-8")
    render(data,args.output_dir,digest)
    print("MAP01:",args.output_dir/"arena.png")
    print("MAP01:",args.output_dir/"arena.svg")
    return 0


if __name__=="__main__":
    sys.exit(main())
