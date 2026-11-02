#!/usr/bin/env python3
"""Rebuild Ilyusha's original skinned mesh with Blender 4.5 LTS.

blender -b -t 2 --python tools/art/build_ilyusha_blender.py -- --render
All coordinates are metres, Z up, character front -Y. The .blend retains
editable quad surfaces; the GLB contains applied subdivision and skin weights.
"""
import argparse
import json
import math
import os
import random
import sys
from pathlib import Path

import bpy
import bmesh
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'assets/models/characters/ilyusha'
CHECK = ROOT / 'builds/checks/IP-01/real-model'
IMAGES = ROOT / 'builds/screenshots/IP-01/real-model'
HEIGHT = 1.765
OBJECTS = []
JOINTS = {
    'root': ((0, 0, 0), (0, 0, .15), None),
    'pelvis': ((0, 0, .88), (0, 0, .98), 'root'),
    'spine_01': ((0, 0, .98), (0, 0, 1.10), 'pelvis'),
    'spine_02': ((0, 0, 1.10), (0, 0, 1.22), 'spine_01'),
    'spine_03': ((0, 0, 1.22), (0, 0, 1.355), 'spine_02'),
    'neck_01': ((0, 0, 1.355), (0, 0, 1.425), 'spine_03'),
    'Head': ((0, 0, 1.425), (0, 0, 1.70), 'neck_01'),
}
for side, sign in [('l', 1), ('r', -1)]:
    def p(x, y, z):
        return (sign * x, y, z)
    JOINTS.update({
        'clavicle_' + side: (p(.055, 0, 1.30), p(.31, 0, 1.315), 'spine_03'),
        'upperarm_' + side: (p(.31, 0, 1.315), p(.435, -.006, 1.035), 'clavicle_' + side),
        'lowerarm_' + side: (p(.435, -.006, 1.035), p(.49, -.02, .785), 'upperarm_' + side),
        'hand_' + side: (p(.49, -.02, .785), p(.51, -.045, .665), 'lowerarm_' + side),
        'thigh_' + side: (p(.155, 0, .88), p(.17, -.025, .46), 'pelvis'),
        'calf_' + side: (p(.17, -.025, .46), p(.17, 0, .14), 'thigh_' + side),
        'foot_' + side: (p(.17, 0, .14), p(.17, -.165, .065), 'calf_' + side),
        'ball_' + side: (p(.17, -.165, .065), p(.17, -.235, .065), 'foot_' + side),
    })


def material(name, color, roughness=.82):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value = (*color, 1)
    bsdf.inputs['Roughness'].default_value = roughness
    bsdf.inputs['Metallic'].default_value = 0
    bsdf.inputs['Specular IOR Level'].default_value = .18
    return mat


def mesh_object(name, vertices, faces, mat, smooth=True, subdivision=0, sleeve_labels=None):
    used=sorted({index for face in faces for index in face})
    if len(used)!=len(vertices):
        remap={old:new for new,old in enumerate(used)}
        vertices=[vertices[index]for index in used]
        faces=[tuple(remap[index]for index in face)for face in faces]
        if sleeve_labels is not None:sleeve_labels=[sleeve_labels[index]for index in used]
    mesh = bpy.data.meshes.new(name + '_quads')
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    mesh.materials.append(mat)
    if sleeve_labels is not None:
        attr=mesh.attributes.new('sleeve_side', 'FLOAT', 'POINT')
        for datum,label in zip(attr.data,sleeve_labels):datum.value=label
    for face in mesh.polygons:
        face.use_smooth = smooth
    if subdivision:
        mod = obj.modifiers.new('Sculpted support-loop surface', 'SUBSURF')
        mod.subdivision_type = 'CATMULL_CLARK'
        mod.levels = subdivision
        mod.render_levels = subdivision
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=mod.name)
    OBJECTS.append(obj)
    return obj


def superellipse(t, power=.45):
    c, s = math.cos(t), math.sin(t)
    return (math.copysign(abs(c) ** power, c),
            math.copysign(abs(s) ** power, s))


def ring_surface(name, rings, n, mat, power=.5, cap=True, subdivision=1):
    vertices, faces = [], []
    for cx, cy, z, rx, ry in rings:
        for j in range(n):
            x, y = superellipse(j * 2 * math.pi / n, power)
            vertices.append((cx + x * rx, cy + y * ry, z))
    for i in range(len(rings) - 1):
        for j in range(n):
            faces.append((i*n+j, i*n+(j+1)%n,
                          (i+1)*n+(j+1)%n, (i+1)*n+j))
    if cap:
        faces.extend([tuple(reversed(range(n))),
                      tuple((len(rings)-1)*n+j for j in range(n))])
    return mesh_object(name, vertices, faces, mat, subdivision=subdivision)


def bevel_box(name, center, size, mat, bevel=.012, segments=3, rotation=None):
    bpy.ops.mesh.primitive_cube_add(size=1, location=center)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if rotation:
        obj.rotation_euler = rotation
    mod = obj.modifiers.new('Rounded sculpted edges', 'BEVEL')
    mod.width = bevel
    mod.segments = segments
    bpy.ops.object.modifier_apply(modifier=mod.name)
    obj.data.materials.append(mat)
    for face in obj.data.polygons:
        face.use_smooth = True
    normal = obj.modifiers.new('Area weighted planes', 'WEIGHTED_NORMAL')
    normal.keep_sharp = True
    bpy.ops.object.modifier_apply(modifier=normal.name)
    OBJECTS.append(obj)
    return obj


def ellipsoid(name, center, radii, mat):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=20,ring_count=10,location=center)
    obj=bpy.context.object;obj.name=name;obj.scale=radii
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    obj.data.materials.append(mat)
    for face in obj.data.polygons:face.use_smooth=True
    OBJECTS.append(obj)
    return obj


def curve_mesh(name, points, radius, mat, resolution=2):
    curve = bpy.data.curves.new(name, 'CURVE')
    curve.dimensions = '3D'
    curve.resolution_u = resolution
    curve.bevel_depth = radius
    curve.bevel_resolution = 1
    spline = curve.splines.new('POLY')
    spline.points.add(len(points)-1)
    for p, co in zip(spline.points, points):
        p.co = (*co, 1)
    obj = bpy.data.objects.new(name, curve)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.convert(target='MESH')
    obj.select_set(False)
    OBJECTS.append(obj)
    return obj


def jacket(mat):
    n = 32
    levels = [(.710,.310,.169), (.722,.314,.171), (.755,.315,.173),
              (.84,.325,.183), (.96,.338,.192), (1.075,.345,.190),
              (1.150,.347,.186), (1.205,.349,.182), (1.265,.344,.176),
              (1.320,.330,.165), (1.350,.297,.145), (1.375,.240,.126),
              (1.389,.126,.104), (1.398,.120,.101)]
    vertices, faces, sleeve_labels = [], [], []
    for z, rx, ry in levels:
        for j in range(n):
            x, y = superellipse(j*2*math.pi/n, .55)
            # The waist has broad planes; slight lower-front cloth tension.
            front_fold = -.004 * math.sin(z * 35 + abs(x)*2) if y < -.75 else 0
            vertices.append((x*rx, y*ry + front_fold, z))
            sleeve_labels.append(0)
    holes = [(29, 3, 6, 9, 1), (13, 19, 6, 9, -1)]
    for i in range(len(levels)-1):
        for j in range(n):
            skip = any(lo <= i < hi and ((j-start)%n) < ((end-start)%n)
                       for start,end,lo,hi,_ in holes)
            if not skip:
                faces.append((i*n+j, i*n+(j+1)%n,
                              (i+1)*n+(j+1)%n, (i+1)*n+j))
    for start,end,lo,hi,sign in holes:
        span = (end-start)%n
        loop = [lo*n+(start+j)%n for j in range(span+1)]
        loop += [i*n+end for i in range(lo+1, hi+1)]
        loop += [hi*n+(start+j)%n for j in range(span-1,-1,-1)]
        loop += [i*n+start for i in range(hi-1,lo,-1)]
        centerz = (levels[lo][0]+levels[hi][0])/2
        angles = [math.atan2((vertices[k][2]-centerz)/.09,
                            vertices[k][1]/.15) for k in loop]
        previous = loop
        for index in loop:sleeve_labels[index]=sign*.65
        # Elbow has five close rings spanning both bend quadrants.
        sections = [(.360,1.278,.133,.129), (.387,1.219,.132,.124),
                    (.414,1.140,.126,.117), (.429,1.077,.120,.111),
                    (.436,1.038,.118,.109), (.444,.999,.116,.108),
                    (.458,.946,.112,.106), (.479,.853,.101,.099),
                    (.488,.812,.096,.095), (.492,.787,.095,.094),
                    (.494,.775,.094,.093)]
        for cx,z,ry,rr in sections:
            ring = []
            for a in angles:
                # Cross-section basis follows the arm, rather than world Z.
                crease=.006*math.sin(2*a+z*48)*math.exp(-((z-1.04)/.10)**2)
                y = math.cos(a)*(ry+crease)
                transverse = math.sin(a)*(rr+crease)
                ring.append(len(vertices))
                vertices.append((sign*(cx + .925*transverse),
                                 y-.008, z+.380*transverse))
                sleeve_labels.append(sign)
            for j in range(len(loop)):
                faces.append((previous[j],previous[(j+1)%len(loop)],
                              ring[(j+1)%len(loop)],ring[j]))
            previous = ring
        # Inward cuff rim leaves the visible wrist socket open.
        inset = []
        for index in previous:
            x,y,z = vertices[index]
            inset.append(len(vertices))
            vertices.append((sign*.494+(x-sign*.494)*.87,
                             -.008+(y+.008)*.87, z+.003))
            sleeve_labels.append(sign)
        for j in range(len(previous)):
            faces.append((previous[j],previous[(j+1)%len(previous)],
                          inset[(j+1)%len(inset)],inset[j]))
    obj = mesh_object('Jacket_continuous_shoulders_elbows', vertices, faces, mat,
                      subdivision=1, sleeve_labels=sleeve_labels)
    obj['topology'] = 'Connected torso, open neckline and hem, sewn 18-edge armholes; elbow support rings.'
    return obj


def pants(mat):
    # Front/back half grids make a single connected crotch, without overlapping
    # capped leg primitives. Outer leg rings continue directly into the pelvis.
    n = 24
    vertices, faces = [], []
    loops = {}
    sections = [(.230,.119,.111),(.242,.122,.115),(.270,.111,.106),
                (.315,.120,.112),(.402,.127,.119),(.435,.129,.122),
                (.460,.130,.124),(.485,.132,.126),(.520,.135,.129),
                (.590,.142,.134),(.655,.147,.139)]
    for sign in (1,-1):
        last = None
        for z,rx,ry in sections:
            loop = []
            centerx = sign*(.17 if z<.49 else .164)
            centery = -.008 - .013*math.exp(-((z-.46)/.10)**2)
            for j in range(n):
                sx,sy=superellipse(2*math.pi*j/n,.65)
                fold = .008*math.sin(j*1.15+z*48)*math.exp(-((z-.47)/.12)**2)
                fold += .005*math.sin(j*.9+z*40)*math.exp(-((z-.27)/.05)**2)
                loop.append(len(vertices))
                vertices.append((centerx+rx*sx,centery+(ry+fold)*sy,z))
            if last:
                for j in range(n):
                    faces.append((last[j],last[(j+1)%n],loop[(j+1)%n],loop[j]))
            last=loop
        loops[sign]=last
    # Each leg top is cut at the inside half and joined into a common hip loop.
    # The bridge is a four-column arched crotch saddle with no closed caps.
    left,right=loops[1],loops[-1]
    # Boundary of the hip is the outer half of each leg ring plus front/back bridges.
    outer_l=[left[j%n] for j in range(-6,7)]
    outer_r=[right[j%n] for j in range(6,19)]
    # Inner half leg loops are joined across the crotch. Ends are front/back center.
    inner_l=[left[j%n] for j in range(6,19)]
    inner_r=[right[j%n] for j in range(6,-7,-1)]
    saddle=[]
    for k in range(13):
        li,ri=inner_l[k],inner_r[k]
        midpoint=(Vector(vertices[li])+Vector(vertices[ri]))*.5
        midpoint.z=.655+.045*abs((k-6)/6)**1.4
        saddle.append(len(vertices))
        vertices.append(tuple(midpoint))
    for k in range(12):
        faces.append((inner_l[k],inner_l[k+1],saddle[k+1],saddle[k]))
        faces.append((saddle[k],saddle[k+1],inner_r[k+1],inner_r[k]))
    boundary=outer_l+[saddle[0]]+outer_r+[saddle[-1]]
    previous=boundary
    # Ring correspondence follows the actual perimeter; upper hip has a flat waist.
    for z,width,depth in [(.725,.307,.150),(.790,.307,.155),
                          (.865,.301,.156),(.940,.290,.150),(.958,.287,.148)]:
        ring=[]
        for index in boundary:
            x,y,_=vertices[index]
            angle=math.atan2(y/.14,x/.31)
            sx,sy=superellipse(angle,.65)
            ring.append(len(vertices))
            vertices.append((width*sx,depth*sy-.008,z))
        for k in range(len(ring)):
            faces.append((previous[k],previous[(k+1)%len(ring)],
                          ring[(k+1)%len(ring)],ring[k]))
        previous=ring
    obj=mesh_object('Trousers_connected_crotch_knee_loops',vertices,faces,mat,subdivision=1)
    obj['topology']='One connected crotch saddle, continuous thighs; rings .402/.435/.460/.485/.520 support knee flexion.'
    return obj


def head(skin, hair, hair_light, brow, eye, pupil, crease):
    sculpt=ring_surface('Head_neck_cheek_jaw_sculpt',[
        (0,.007,1.293,.083,.077),(0,.007,1.320,.087,.081),
        (0,.004,1.361,.091,.087),(0,-.001,1.378,.130,.112),
        (0,-.017,1.389,.159,.140),(0,-.022,1.414,.178,.158),
        (0,-.018,1.448,.182,.153),(0,-.003,1.491,.183,.147),
        (0,.002,1.540,.181,.143),(0,.003,1.590,.175,.138),
        (0,.005,1.646,.171,.134),(0,.009,1.694,.168,.130),
        (0,.012,1.721,.149,.112),(0,.012,1.734,.115,.086),
        (0,.012,1.739,.055,.049)],32,skin,power=.43,subdivision=1)
    for vertex in sculpt.data.vertices:
        x,y,z=vertex.co
        if y<-.075:
            orbital=.026*math.exp(-((abs(x)-.086)/.038)**4)*math.exp(-((z-1.591)/.028)**2)
            cheek=.010*math.exp(-((abs(x)-.104)/.045)**2)*math.exp(-((z-1.502)/.044)**2)
            vertex.co.y+=orbital-cheek
    sculpt.data.update()
    # Nose side planes narrow toward the bridge, with a substantial blunt tip.
    verts=[(-.019,-.133,1.612),(.019,-.133,1.612),
           (-.027,-.181,1.599),(.027,-.181,1.599),
           (-.038,-.222,1.541),(.038,-.222,1.541),
           (-.037,-.221,1.520),(.037,-.221,1.520),
           (-.034,-.138,1.518),(.034,-.138,1.518)]
    nose=mesh_object('Nose_blunt_rectangular_planes',verts,
        [(0,1,3,2),(2,3,5,4),(4,5,7,6),(6,7,9,8),
         (0,2,4,6,8),(1,9,7,5,3),(0,8,9,1)],skin)
    mod=nose.modifiers.new('Soft nose corners','BEVEL'); mod.width=.005; mod.segments=3
    bpy.context.view_layer.objects.active=nose; bpy.ops.object.modifier_apply(modifier=mod.name)
    for sign in (-1,1):
        # Almond geometry is mostly covered by skin lids, giving a deadpan gaze.
        ellipsoid('Sclera_'+str(sign),(sign*.088,-.126,1.590),(.035,.008,.013),eye)
        ellipsoid('Pupil_'+str(sign),(sign*.086,-.134,1.586),(.006,.003,.008),pupil)
        curve_mesh('Upper_lid_'+str(sign),[(sign*.088+dx,-.139+.008*abs(dx)/.035,1.599)
                    for dx in(-.036,-.020,0,.020,.036)],.008,skin)
        curve_mesh('Lower_lid_'+str(sign),[(sign*.088+dx,-.132+.005*abs(dx)/.035,
                    1.580+.006*abs(dx)/.035)for dx in(-.035,-.02,0,.02,.035)],.0035,skin)
        bevel_box('Heavy_brow_'+str(sign),(sign*.092,-.150,1.628),(.112,.028,.028),brow,.005,2,
                  (0,sign*.018,sign*.010))
        # Auricle has a continuous turned outer rim and recessed concha.
        n=16; verts=[];faces=[]
        for i,(rx,rz,offset) in enumerate([(.043,.070,.004),(.039,.066,.035),(.025,.048,.040),(.014,.031,.017)]):
            for j in range(n):
                a=2*math.pi*j/n
                verts.append((sign*(.177+offset*(.55+.45*abs(math.cos(a)))), .002+rx*math.cos(a),
                              1.539+rz*math.sin(a)))
        for i in range(3):
            for j in range(n):
                faces.append((i*n+j,i*n+(j+1)%n,(i+1)*n+(j+1)%n,(i+1)*n+j))
        faces.append(tuple(3*n+j for j in range(n)))
        mesh_object('Ear_sculpt_'+str(sign),verts,faces,skin,subdivision=1)
    curve_mesh('Mouth_restrained_horizontal',[
        (-.067,-.165,1.466),(-.040,-.171,1.471),(0,-.173,1.472),
        (.040,-.171,1.471),(.067,-.165,1.466)],.0020,crease)
    hair_sculpt(hair,hair_light)


def hair_sculpt(hair,hair_light):
    # Directional roof columns form a broad left sweep, an inset side part,
    # and the smaller opposing right mass. The front edge has deliberate breaks.
    xs=[[-.157,-.105,-.025,.070,.105,.157],
        [-.181,-.117,-.040,.050,.100,.181],
        [-.181,-.125,-.050,.035,.100,.181],
        [-.174,-.117,-.050,.030,.100,.174],
        [-.150,-.100,-.035,.045,.105,.150]]
    zs=[[1.690,1.720,1.704,1.710,1.717,1.692],
        [1.708,1.747,1.743,1.746,1.752,1.705],
        [1.714,HEIGHT,1.756,1.745,1.755,1.710],
        [1.710,1.752,1.748,1.743,1.749,1.704],
        [1.694,1.724,1.731,1.714,1.722,1.692]]
    ys=[[-.115,-.143,-.148,-.145,-.138,-.115],
        [-.066]*6,[.009]*6,[.085]*6,[.115,.142,.146,.143,.137,.115]]
    verts=[(xs[i][j],ys[i][j],zs[i][j])for i in range(5)for j in range(6)]
    faces=[]
    for i in range(4):
        for j in range(5):faces.append((i*6+j,i*6+j+1,(i+1)*6+j+1,(i+1)*6+j))
    boundary=list(range(6))+[11,17,23,29]+[28,27,26,25,24]+[18,12,6]
    hairline=[1.634,1.677,1.660,1.685,1.690,1.657,
              1.582,1.600,1.604,1.611,1.611,1.611,1.611,1.611,1.611,
              1.604,1.587,1.579]
    lower=[]
    for index,z in zip(boundary,hairline):
        x,y,_=verts[index];lower.append(len(verts));verts.append((x*.987,y*.98,z))
    for j in range(len(boundary)):
        nxt=(j+1)%len(boundary)
        faces.append((boundary[j],boundary[nxt],lower[nxt],lower[j]))
    obj=mesh_object('Hair_asymmetric_angular_cap',verts,faces,hair,smooth=False)
    obj.data.materials.append(hair_light)
    for f in obj.data.polygons:
        if f.center.x<-.03:f.material_index=1


def details(mats):
    jacketmat,trim,zipmat,ochre,skin,boot,sole,lace=mats
    # Collar follows an open elliptical band, leaving room at the center zip.
    verts=[];faces=[];n=32
    for i in range(5):
        for j in range(n):
            a=-math.pi/2+.004+(2*math.pi-.008)*j/(n-1)
            sx,sy=superellipse(a,.6)
            if i==0:rx,ry,z=.193,.164,1.339
            elif i==1:rx,ry,z=.202,.172,1.351
            elif i==2:rx,ry,z=.190,.162,1.428
            elif i==3:rx,ry,z=.174,.146,1.429
            else:rx,ry,z=.178,.150,1.351
            verts.append((sx*rx,sy*ry,z-.010*max(0,-sy)))
    for i in range(4):
        for j in range(n-1):faces.append((i*n+j,i*n+j+1,(i+1)*n+j+1,(i+1)*n+j))
    faces.extend([(0,n,2*n,3*n,4*n),tuple((i+1)*n-1 for i in reversed(range(5)))])
    mesh_object('Collar_standing_open_band',verts,faces,trim,subdivision=1)
    ring_surface('Jacket_hem_turned_seam',[(0,0,.709,.318,.182),
        (0,0,.718,.322,.185),(0,0,.742,.322,.185),(0,0,.747,.320,.183)],
        32,trim,power=.55,cap=False,subdivision=1)
    # Center zipper and inset pockets sit just above the actual cloth surface.
    points=[]
    for z in [.724,.78,.90,1.04,1.17,1.29,1.35,1.385]:
        depth=.171 if z<.78 else (.190 if z<1.18 else .172 if z<1.31 else .128)
        points.append((0,-depth-.005,z))
    curve_mesh('Zipper_tape',points,.0065,trim)
    curve_mesh('Zipper_teeth',[(x,y-.002,z)for x,y,z in points],.002,zipmat)
    bevel_box('Ochre_zip_pull',(0,-.187,1.292),(.025,.011,.051),ochre,.003,2)
    for sign in (-1,1):
        pocket=bevel_box('Pocket_welt_'+str(sign),(sign*.245,-.190,.882),(.023,.012,.145),trim,.005,2,
                         (0,sign*.12,0))
        # A single stitched hem line, without decorative texture noise.
        curve_mesh('Shoulder_seam_'+str(sign),[(sign*.18,-.133,1.351),
            (sign*.27,-.141,1.331),(sign*.327,-.137,1.286),(sign*.352,-.128,1.236)],.0018,trim)
        # Broad relaxed palm with four rounded finger columns and a thick thumb.
        palm=bevel_box('Palm_'+str(sign),(sign*.505,-.025,.720),(.135,.091,.135),skin,.028,3,
                       (0,sign*-.10,0))
        for k in range(4):
            x=sign*(.458+k*.031)
            z=.650+(.009 if k in(0,3) else 0)
            finger=bevel_box('Finger_%s_%s'%(sign,k),(x,-.038,z),(.032,.073,.087),skin,.014,3,
                             (math.radians(-12),sign*-.1,0))
        bevel_box('Thumb_'+str(sign),(sign*.442,-.059,.712),(.047,.069,.090),skin,.019,4,
                  (math.radians(-16),sign*-.32,sign*.12))
        # Practical boots: rolled ankle, broad toe box, thick grooved sole.
        cx=sign*.17
        ring_surface('Boot_upper_'+str(sign),[
            (cx,-.070,.054,.120,.198),(cx,-.070,.071,.122,.200),
            (cx,-.070,.112,.117,.195),(cx,-.042,.151,.109,.153),
            (cx,.006,.176,.095,.106),(cx,.008,.228,.091,.099),
            (cx,.008,.241,.090,.098)],24,boot,power=.4,subdivision=1)
        bevel_box('Boot_sole_'+str(sign),(cx,-.072,.036),(.251,.412,.072),sole,.012,3)
        bevel_box('Boot_toecap_'+str(sign),(cx,-.213,.099),(.221,.125,.070),boot,.018,3)
        for k in range(6):
            y=-.237+k*.070
            for side in(-1,1):
                bevel_box('Sole_tread_%s_%s_%s'%(sign,k,side),
                    (cx+side*.118,y,.018),(.023,.037,.035),sole,.004,1)
        for k in range(4):
            z=.136+k*.020;y=-.159+k*.017
            curve_mesh('Boot_lace_%s_%s'%(sign,k),[(cx-.056,y,z),(cx+.056,y-.003,z+.003)],.003,lace)


def smoothstep(a,b,x):
    t=max(0,min(1,(x-a)/(b-a)))
    return t*t*(3-2*t)


def weights_for(obj,co,sleeve_label=0):
    x,y,z=co
    side='l' if x>=0 else 'r'
    name=obj.name
    if name.startswith(('Head','Nose','Sclera','Pupil','Upper_lid','Lower_lid','Heavy_brow','Ear','Mouth','Hair')):
        if z<1.385:
            h=smoothstep(1.34,1.405,z)
            return {'neck_01':1-h,'Head':h}
        return {'Head':1}
    if name.startswith(('Palm','Finger','Thumb')):return {'hand_'+side:1}
    if name.startswith(('Boot','Sole')):return {'foot_'+side:1}
    if name.startswith('Trousers'):
        knee=smoothstep(.405,.515,z)
        lateral=smoothstep(-.06,.06,x)
        upper={'thigh_l':knee*lateral,'thigh_r':knee*(1-lateral),
               'calf_l':(1-knee)*lateral,'calf_r':(1-knee)*(1-lateral)}
        pelvis=smoothstep(.775,.885,z)
        upper={k:v*(1-pelvis) for k,v in upper.items()}
        upper['pelvis']=pelvis
        return upper
    if sleeve_label:
        elbow=smoothstep(.975,1.105,z)
        w={'upperarm_'+side:elbow,'lowerarm_'+side:1-elbow}
        blend=min(1,abs(sleeve_label))
        if blend<1:
            w={k:v*blend for k,v in w.items()};w['spine_03']=1-blend
        return w
    if z>1.35:return {'neck_01':.35,'spine_03':.65}
    if z>1.20:return {'spine_03':1}
    if z>1.07:
        t=smoothstep(1.07,1.20,z);return {'spine_02':1-t,'spine_03':t}
    if z>.96:
        t=smoothstep(.96,1.07,z);return {'spine_01':1-t,'spine_02':t}
    if z>.84:
        t=smoothstep(.84,.96,z);return {'pelvis':1-t,'spine_01':t}
    thigh=(1-smoothstep(.775,.885,z))*(1 if y<-.06 else .35)
    lateral=smoothstep(-.06,.06,x)
    return {'pelvis':1-thigh,'thigh_l':thigh*lateral,'thigh_r':thigh*(1-lateral)}


def armature():
    bpy.ops.object.select_all(action='DESELECT')
    data=bpy.data.armatures.new('Ilyusha_Humanoid')
    rig=bpy.data.objects.new('Ilyusha_Rig',data)
    bpy.context.collection.objects.link(rig)
    bpy.context.view_layer.objects.active=rig
    rig.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    for name,(head,tail,parent) in JOINTS.items():
        bone=data.edit_bones.new(name)
        bone.head=head;bone.tail=tail
        if parent:bone.parent=data.edit_bones[parent]
        bone.use_deform=name!='root'
    bpy.ops.object.mode_set(mode='OBJECT')
    for obj in OBJECTS:
        for name in JOINTS:
            if name!='root':obj.vertex_groups.new(name=name)
        for v in obj.data.vertices:
            co=obj.matrix_world@v.co
            attr=obj.data.attributes.get('sleeve_side')
            label=attr.data[v.index].value if attr else 0
            w=weights_for(obj,co,label)
            total=sum(w.values())
            for bone,value in w.items():
                if value>1e-7:obj.vertex_groups[bone].add([v.index],value/total,'REPLACE')
        mod=obj.modifiers.new('Humanoid linear skin','ARMATURE')
        mod.object=rig
        mod.use_deform_preserve_volume=False
        obj.parent=rig
    rig['height_metres']=HEIGHT
    rig['rest_pose']='A pose, front -Y, Z up. Animation rotations require source-rest correction.'
    rig['joint_contract']='Quaternius UAL names; original geometry and analytical normalized weights.'
    return rig


def camera_at(name, location, target, scale=2.12):
    data=bpy.data.cameras.new(name);obj=bpy.data.objects.new(name,data)
    bpy.context.collection.objects.link(obj)
    obj.location=location;obj.rotation_euler=(Vector(target)-obj.location).to_track_quat('-Z','Y').to_euler()
    data.type='ORTHO';data.ortho_scale=scale
    bpy.context.scene.camera=obj
    return obj


def studio():
    scene=bpy.context.scene
    scene.render.engine='CYCLES'
    scene.cycles.device='CPU'
    scene.cycles.samples=32
    scene.cycles.use_denoising=True
    scene.render.threads_mode='FIXED';scene.render.threads=2
    scene.render.resolution_x=700;scene.render.resolution_y=900
    scene.render.resolution_percentage=100
    scene.world.color=(.28,.28,.28)
    scene.view_settings.view_transform='AgX'
    floor=material('Studio_warm_neutral',(.43,.41,.38))
    bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.006))
    bpy.context.object.name='Studio_floor';bpy.context.object.data.materials.append(floor)
    for name,location,power,size in [('Key',(-3,-4,5),450,4),('Fill',(3,-2,3),220,3),('Rim',(1,3,4),380,3)]:
        light=bpy.data.lights.new(name,'AREA');light.energy=power;light.shape='DISK';light.size=size
        obj=bpy.data.objects.new(name,light);bpy.context.collection.objects.link(obj);obj.location=location
        obj.rotation_euler=(Vector((0,0,.9))-obj.location).to_track_quat('-Z','Y').to_euler()
    print('RENDER_DEVICE CPU; threads=2; no GUI; no audio')


def export(rig,render):
    OUT.mkdir(parents=True,exist_ok=True);CHECK.mkdir(parents=True,exist_ok=True);IMAGES.mkdir(parents=True,exist_ok=True)
    source=OUT/'source';source.mkdir(exist_ok=True)
    (source/'.gdignore').write_text('')
    bpy.context.preferences.filepaths.save_version=0
    bpy.ops.wm.save_as_mainfile(filepath=str(source/'ilyusha.blend'))
    # Runtime has one skinned mesh with material primitives; source keeps all
    # editable anatomical surfaces and accessories as named objects.
    bpy.ops.object.select_all(action='DESELECT')
    copies=[]
    for obj in OBJECTS:
        copy=obj.copy();copy.data=obj.data.copy()
        bpy.context.collection.objects.link(copy);copy.select_set(True);copies.append(copy)
    bpy.context.view_layer.objects.active=copies[0]
    bpy.ops.object.join();runtime=bpy.context.object;runtime.name='Ilyusha_Surface'
    rig.select_set(True)
    bpy.ops.export_scene.gltf(filepath=str(OUT/'ilyusha.glb'),export_format='GLB',
        use_selection=True,export_apply=True,export_animations=False,
        export_yup=True,export_skins=True,export_all_influences=False)
    bpy.data.objects.remove(runtime,do_unlink=True)
    triangles=sum(len(p.vertices)-2 for obj in OBJECTS for p in obj.data.polygons)
    metrics={'height_metres':HEIGHT,'triangles':triangles,'vertices':sum(len(o.data.vertices) for o in OBJECTS),
             'objects':len(OBJECTS),'bones':len(JOINTS),
             'anatomical_joint_z':{'hip':.88,'knee':.46,'ankle':.14},
             'coat_hem_z':.71,'linear_skin':True,'render_device':'CPU',
             'source_reference':'docs/art/explorations/ilyusha/2026-11-02-independent-3d/04.png',
             'status':'development geometry, requires independent visual comparison and game integration'}
    (CHECK/'geometry_metrics.json').write_text(json.dumps(metrics,indent=2)+'\n')
    (OUT/'rig_contract.json').write_text(json.dumps({'coordinates':'Blender Z-up front -Y; glTF Y-up front +Z',
        'height_metres':HEIGHT,'rest':'A pose','joints':JOINTS},indent=2)+'\n')
    print(json.dumps(metrics))
    if render:
        studio()
        for name,location in [('front',(0,-6,.91)),('left',(-6,0,.91)),
                              ('back',(0,6,.91)),('three_quarter',(3,-6,2.5))]:
            camera_at(name,location,(0,0,.88),2.07)
            bpy.context.scene.render.filepath=str(IMAGES/(name+'.png'))
            bpy.ops.render.render(write_still=True)
        # A genuine deformation probe uses the exported linear-skin armature.
        rig.pose.bones['thigh_l'].rotation_mode='XYZ'
        rig.pose.bones['calf_l'].rotation_mode='XYZ'
        for angle in (45,90):
            rig.pose.bones['thigh_l'].rotation_euler.x=math.radians(-35)
            rig.pose.bones['calf_l'].rotation_euler.x=math.radians(angle)
            camera_at('knee_'+str(angle),(3,-6,2.0),(0,0,.88),2.07)
            bpy.context.scene.render.filepath=str(IMAGES/('knee_%s.png'%angle))
            bpy.ops.render.render(write_still=True)


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--render',action='store_true')
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    mats={
        'jacket':material('Graphite_wool',(.105,.111,.116)),
        'trim':material('Graphite_seams_collar',(.071,.077,.081)),
        'zip':material('Zipper_dull_gray',(.21,.215,.21)),
        'ochre':material('Muted_ochre_pull',(.42,.36,.075)),
        'pants':material('Dark_slate_trousers',(.046,.053,.065)),
        'skin':material('Warm_pale_skin',(.60,.344,.222)),
        'hair':material('Dark_brown_hair',(.040,.025,.018)),
        'hair_light':material('Hair_facet_variation',(.055,.035,.024)),
        'brow':material('Heavy_dark_brows',(.027,.019,.014)),
        'eye':material('Warm_eye_white',(.76,.74,.66)),
        'pupil':material('Pupil',(.014,.012,.010)),
        'crease':material('Skin_mouth_crease',(.29,.135,.080)),
        'boot':material('Matte_winter_boot',(.028,.026,.023)),
        'sole':material('Rubber_soles',(.017,.018,.017)),
        'lace':material('Boot_laces',(.060,.054,.044)),
    }
    jacket(mats['jacket']);pants(mats['pants'])
    head(*(mats[k] for k in ['skin','hair','hair_light','brow','eye','pupil','crease']))
    details([mats[k] for k in ['jacket','trim','zip','ochre','skin','boot','sole','lace']])
    rig=armature();export(rig,args.render)


if __name__=='__main__':main()
