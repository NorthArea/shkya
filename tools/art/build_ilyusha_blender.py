#!/usr/bin/env python3
"""Rebuild Ilyusha's original skinned mesh with Blender 4.5 LTS.

blender -b -t 2 --python tools/art/build_ilyusha_blender.py -- --render
All coordinates are metres, Z up, character front -Y. The .blend retains
editable quad surfaces; the GLB contains applied subdivision and skin weights.
"""
import argparse
import hashlib
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
CHECK = ROOT / 'builds/checks/IP-01/reference-rebuild'
IMAGES = ROOT / 'builds/screenshots/IP-01/reference-rebuild'
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
        'clavicle_' + side: (p(.055, 0, 1.30), p(.31, .025, 1.315), 'spine_03'),
        'upperarm_' + side: (p(.31, .025, 1.315), p(.435, -.006, 1.035), 'clavicle_' + side),
        'lowerarm_' + side: (p(.435, -.006, 1.035), p(.455, -.045, .725), 'upperarm_' + side),
        'hand_' + side: (p(.455, -.045, .725), p(.47, -.080, .580), 'lowerarm_' + side),
        'thigh_' + side: (p(.155, 0, .88), p(.183, -.025, .46), 'pelvis'),
        'calf_' + side: (p(.183, -.025, .46), p(.212, 0, .14), 'thigh_' + side),
        'foot_' + side: (p(.212, 0, .14), p(.238, -.163, .065), 'calf_' + side),
        'ball_' + side: (p(.238, -.163, .065), p(.248, -.232, .065), 'foot_' + side),
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
    if name in ('Graphite_wool', 'Graphite_seams_collar', 'Dark_slate_trousers'):
        # Original, deterministic woven cloth; embedded in the GLB, no borrowed
        # texture or dependency on a Blender-only procedural shader at runtime.
        size=256
        image=bpy.data.images.new(name+'_original_weave',width=size,height=size)
        rng=random.Random(412)
        pixels=[]
        for y in range(size):
            for x in range(size):
                cloud=(math.sin(x*.071+math.sin(y*.054)*2)+math.sin(y*.093+x*.021))*.075
                weave=.018*((x%3==0)-(y%3==0))
                value=max(.65,min(1,.91+cloud+weave+rng.uniform(-.055,.055)))
                linear=[value]*3
                pixels.extend([12.92*c if c<=.0031308 else 1.055*c**(1/2.4)-.055 for c in linear]+[1])
        image.pixels.foreach_set(pixels)
        image.pack()
        texture=mat.node_tree.nodes.new('ShaderNodeTexImage');texture.image=image
        multiply=mat.node_tree.nodes.new('ShaderNodeMix');multiply.data_type='RGBA';multiply.blend_type='MULTIPLY'
        multiply.inputs[0].default_value=1
        first=next(socket for socket in multiply.inputs if socket.identifier=='A_Color')
        second=next(socket for socket in multiply.inputs if socket.identifier=='B_Color')
        second.default_value=(*color,1)
        mat.node_tree.links.new(texture.outputs['Color'],first)
        mat.node_tree.links.new(next(socket for socket in multiply.outputs if socket.type=='RGBA'),bsdf.inputs['Base Color'])
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
    uv=mesh.uv_layers.new(name='Original_cloth_UV')
    for loop in mesh.loops:
        co=mesh.vertices[loop.vertex_index].co
        uv.data[loop.index].uv=(co.x*1.7+co.y*.7+.5,co.z*1.7)
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
    for ring in rings:
        cx,cy,z,rx,ry=ring[:5]
        ring_power=ring[5] if len(ring)>5 else power
        for j in range(n):
            x, y = superellipse(j * 2 * math.pi / n, ring_power)
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


def jacket(mat,trim):
    n = 32
    levels = [(.687,.330,.169), (.700,.332,.171), (.733,.333,.173),
              (.84,.337,.183), (.96,.344,.192), (1.075,.350,.190),
              (1.150,.347,.186), (1.205,.349,.182), (1.265,.344,.176),
              (1.320,.330,.165), (1.350,.297,.145), (1.375,.240,.126),
              (1.389,.126,.104), (1.398,.120,.101)]
    vertices, faces, sleeve_labels = [], [], []
    for z, rx, ry in levels:
        for j in range(n):
            x, y = superellipse(j*2*math.pi/n, .55)
            # The waist has broad planes; slight lower-front cloth tension.
            front_fold = -.003 * math.sin(z * 35 + abs(x)*2) if y < -.75 else 0
            neckline_drop = .095 * max(0, -y)**8 * smoothstep(1.32, 1.389, z)
            vertices.append((x*rx, y*ry + front_fold, z-neckline_drop))
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
        sections = [(.328,1.278,.128,.108), (.351,1.219,.130,.112),
                    (.385,1.140,.127,.113), (.411,1.077,.124,.114),
                    (.427,1.038,.122,.113), (.436,.992,.124,.114),
                    (.443,.930,.118,.111), (.451,.844,.107,.103),
                    (.455,.760,.099,.098), (.456,.733,.098,.097),
                    (.456,.719,.096,.096)]
        for cx,z,ry,rr in sections:
            ring = []
            for a in angles:
                # Cross-section basis follows the arm, rather than world Z.
                crease=.014*math.sin(2*a+z*48)*math.exp(-((z-1.00)/.10)**2)
                crease+=.005*math.sin(3*a-z*61)*math.exp(-((z-.79)/.08)**2)
                y = math.cos(a)*(ry+crease)
                transverse = math.sin(a)*(rr+crease)
                ring.append(len(vertices))
                tangent=.08+.30*smoothstep(.80,1.25,z)
                transverse_x=math.sqrt(1-tangent*tangent)
                vertices.append((sign*(cx + transverse_x*transverse),
                                 y+.025*smoothstep(1.0,1.28,z)-.040*(1-smoothstep(.73,1.02,z)), z+tangent*transverse))
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
            vertices.append((sign*.456+(x-sign*.456)*.87,
                             -.040+(y+.040)*.87, z+.003))
            sleeve_labels.append(sign)
        for j in range(len(previous)):
            faces.append((previous[j],previous[(j+1)%len(previous)],
                          inset[(j+1)%len(inset)],inset[j]))
    obj = mesh_object('Jacket_continuous_shoulders_elbows', vertices, faces, mat,
                      subdivision=1, sleeve_labels=sleeve_labels)
    obj.data.materials.append(trim)
    labels=obj.data.attributes['sleeve_side']
    for polygon in obj.data.polygons:
        if polygon.center.z<.745 and all(abs(labels.data[index].value)>.95 for index in polygon.vertices):polygon.material_index=1
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
                (.550,.142,.134),(.590,.147,.139)]
    for sign in (1,-1):
        last = None
        for z,rx,ry in sections:
            loop = []
            centerx = sign*(.202-(z-.23)*.08 if z<.49 else .180-(z-.49)*.10)
            centery = -.008 - .013*math.exp(-((z-.46)/.10)**2)
            for j in range(n):
                sx,sy=superellipse(2*math.pi*j/n,.65)
                fold = .017*math.sin(j*1.15+z*48+sign*.7)*math.exp(-((z-.47)/.12)**2)
                fold += .012*math.sin(j*.9+z*40-sign*.6)*math.exp(-((z-.27)/.05)**2)
                loop.append(len(vertices))
                hem_wave=.006*math.sin(j*.8+sign)*math.exp(-((z-.25)/.035)**2)
                vertices.append((centerx+(rx+fold*.55)*sx,centery+(ry+fold)*sy,z+hem_wave))
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
        midpoint.z=.590+.045*abs((k-6)/6)**1.4
        saddle.append(len(vertices))
        vertices.append(tuple(midpoint))
    for k in range(12):
        faces.append((inner_l[k],inner_l[k+1],saddle[k+1],saddle[k]))
        faces.append((saddle[k],saddle[k+1],inner_r[k+1],inner_r[k]))
    boundary=outer_l+[saddle[0]]+outer_r+[saddle[-1]]
    previous=boundary
    # Ring correspondence follows the actual perimeter; upper hip has a flat waist.
    for z,width,depth in [(.655,.307,.150),(.735,.307,.155),
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
    # Front-view proportions are measured on the owner's selected 04 turnaround:
    # broad planar jaw, narrower temples, heavy upper lids, a short blunt nose.
    sculpt=ring_surface('Head_neck_cheek_jaw_sculpt',[
        (0,.015,1.288,.080,.074),(0,.015,1.320,.084,.078),
        (0,.012,1.361,.087,.082),(0,-.006,1.381,.112,.103),
        (0,-.019,1.391,.137,.121,.4),(0,-.022,1.411,.157,.134,.4),
        (0,-.015,1.443,.164,.137,.36),(0,-.004,1.478,.159,.134,.45),
        (0,.001,1.514,.157,.128,.48),(0,.006,1.550,.157,.128,.48),
        (0,.008,1.586,.149,.118),(0,.011,1.619,.148,.117),
        (0,.012,1.657,.147,.115),(0,.014,1.684,.140,.110),
        (0,.015,1.703,.120,.096),(0,.015,1.714,.086,.068),
        (0,.015,1.720,.043,.039)],40,skin,power=.60,subdivision=1)
    for vertex in sculpt.data.vertices:
        x,y,z=vertex.co
        if y<-.070:
            # Recess the orbit, raise cheek bones and make a distinct muzzle/chin.
            orbital=.019*math.exp(-((abs(x)-.074)/.034)**4)*math.exp(-((z-1.588)/.028)**2)
            cheek=.023*math.exp(-((abs(x)-.107)/.039)**2)*math.exp(-((z-1.534)/.035)**2)
            muzzle=.006*math.exp(-(x/.073)**4)*math.exp(-((z-1.467)/.031)**2)
            chin=.006*math.exp(-(x/.072)**4)*math.exp(-((z-1.419)/.018)**2)
            vertex.co.y+=orbital-cheek-muzzle-chin
    sculpt.data.update()
    verts=[(-.021,-.111,1.620),(.021,-.111,1.620),
           (-.027,-.156,1.600),(.027,-.156,1.600),
           (-.043,-.188,1.554),(.043,-.188,1.554),
           (-.042,-.190,1.532),(.042,-.190,1.532),
           (-.035,-.135,1.527),(.035,-.135,1.527)]
    nose_skin=material('Warm_nose_skin',(.54,.19,.075))
    ear_skin=material('Warm_ear_skin',(.64,.31,.18))
    nose=mesh_object('Nose_blunt_rectangular_planes',verts,
        [(0,1,3,2),(2,3,5,4),(4,5,7,6),(6,7,9,8),
         (0,2,4,6,8),(1,9,7,5,3),(0,8,9,1)],nose_skin,smooth=False)
    mod=nose.modifiers.new('Soft nose corners','BEVEL');mod.width=.006;mod.segments=3
    bpy.context.view_layer.objects.active=nose;bpy.ops.object.modifier_apply(modifier=mod.name)
    for sign in (-1,1):
        # The iris meets the upper eyelid rather than floating in the eye white.
        ellipsoid('Sclera_'+str(sign),(sign*.074,-.117,1.591),(.032,.010,.017),eye)
        ellipsoid('Pupil_'+str(sign),(sign*.071,-.127,1.587),(.007,.0035,.009),pupil)
        curve_mesh('Upper_lid_'+str(sign),[(sign*.074+dx,-.129+.010*abs(dx)/.033,
                    1.601-.001*abs(dx)/.033)for dx in(-.034,-.023,0,.023,.034)],.0085,skin)
        curve_mesh('Lower_lid_'+str(sign),[(sign*.074+dx,-.124+.008*abs(dx)/.033,
                    1.578+.012*abs(dx)/.033)for dx in(-.033,-.022,0,.022,.033)],.0038,skin)
        bevel_box('Heavy_brow_'+str(sign),(sign*.075,-.132,1.627),(.094,.032,.029),brow,.004,2,
                  (0,sign*-.025,sign*.020))
        n=20;verts=[];faces=[]
        for rx,rz,offset in [(.035,.058,.001),(.033,.055,.030),(.022,.040,.036),(.012,.025,.016)]:
            for j in range(n):
                a=2*math.pi*j/n
                verts.append((sign*(.151+offset*(.65+.35*abs(math.cos(a)))),
                              .008+rx*math.cos(a),1.536+rz*math.sin(a)))
        for i in range(3):
            for j in range(n):
                faces.append((i*n+j,i*n+(j+1)%n,(i+1)*n+(j+1)%n,(i+1)*n+j))
        faces.append(tuple(3*n+j for j in range(n)))
        mesh_object('Ear_sculpt_'+str(sign),verts,faces,ear_skin,subdivision=1)
        # Small nostril planes and a soft fold beneath each alar wing.
        ellipsoid('Nose_nostril_'+str(sign),(sign*.028,-.183,1.531),(.008,.003,.003),crease)
    mouth=[]
    for x,z in[(-.070,1.492),(-.044,1.502),(0,1.504),(.044,1.502),(.070,1.492)]:
        found,point,normal,face=sculpt.ray_cast(Vector((x,-1,z)),Vector((0,1,0)))
        assert found,'Mouth contour must lie on the real facial surface'
        mouth.append((x,point.y-.0012,z))
    curve_mesh('Mouth_restrained_horizontal',mouth,.0018,crease)
    curve_mesh('Mouth_chin_cleft',[(0,-.158,1.408),(0,-.161,1.426),(0,-.159,1.442)],.0008,crease)
    hair_sculpt(hair,hair_light)


def hair_sculpt(hair,hair_light):
    # Three swept polygon rings close over a low cranial surface. The back is a
    # full dark nape; the front rises into a side-swept, irregular angular fringe.
    n=24;verts=[];faces=[]
    for ring in range(3):
        for j in range(n):
            a=2*math.pi*j/n
            sx,sy=superellipse(a,.65)
            if ring==0:
                sx,sy=superellipse(a,.48)
                front=smoothstep(.20,.82,-sy)
                back=smoothstep(.10,.80,sy)
                x=(.157-.006*back)*sx;y=(.143-.013*back)*sy+.010
                z=1.580-.045*back+.100*front+.018*sx*front
                # A short temple rather than a tall straight side wall.
                if abs(sx)>.88 and sy<0:z-=.012*(1-front)
            elif ring==1:
                x=.165*sx;y=.145*sy+.006
                z=1.711-.015*sx+.005*math.sin(j*1.9)
            else:
                x=.120*sx-.012;y=.100*sy+.002
                z=1.744-.015*sx+.004*math.sin(j*2.4)
                if sy<-.3 and .055<x<.105:z-=.008
                if sy<-.7 and sx<0:y-=.010
            verts.append((x,y,z))
    for ring in range(2):
        for j in range(n):
            nxt=(j+1)%n;a=ring*n+j;b=ring*n+nxt;c=(ring+1)*n+j;d=(ring+1)*n+nxt
            faces.extend([(a,b,d),(a,d,c)])
    verts.append((-.041,-.012,HEIGHT))
    for j in range(n):faces.append((2*n+j,2*n+(j+1)%n,3*n))
    obj=mesh_object('Hair_asymmetric_angular_cap',verts,faces,hair,smooth=False)
    obj.data.materials.append(hair_light)
    for polygon in obj.data.polygons:
        polygon.material_index=1 if polygon.index%9 in(1,4) else 0


def flesh_tube(name, points, radii, skin):
    vertices=[];faces=[];n=12
    centers=[Vector(point)for point in points]
    for index,center in enumerate(centers):
        tangent=(centers[min(index+1,len(centers)-1)]-centers[max(0,index-1)]).normalized()
        width=Vector((1,0,0));width=(width-tangent*width.dot(tangent)).normalized()
        depth=tangent.cross(width).normalized()
        for j in range(n):
            a=2*math.pi*j/n
            vertex=center+width*(math.cos(a)*radii[index][0])+depth*(math.sin(a)*radii[index][1])
            vertices.append(tuple(vertex))
    for index in range(len(centers)-1):
        for j in range(n):faces.append((index*n+j,index*n+(j+1)%n,(index+1)*n+(j+1)%n,(index+1)*n+j))
    faces.extend([tuple(reversed(range(n))),tuple((len(centers)-1)*n+j for j in range(n))])
    return mesh_object(name,vertices,faces,skin,subdivision=1)


def relaxed_hand(sign, skin):
    before=len(OBJECTS);cx=sign*.466
    bevel_box('Palm_build',(cx,-.020,.641),(.131,.086,.143),skin,.030,4,
              (math.radians(-6),sign*-.09,0))
    ellipsoid('Palm_back_volume',(cx,.003,.640),(.071,.048,.075),skin)
    for k,length in enumerate([.110,.129,.123,.096]):
        x=sign*(.416+k*.0345);z=.596+(.006 if k in(0,3)else 0)
        scale=length/.129
        # Proximal fingers descend, middle joints curl forwards, distal pads
        # turn back up: a real C-shaped relaxed fist, not parallel vertical bars.
        points=[(x,-.014,z),(x-sign*.001,-.015,z-.033*scale),
                (x-sign*.005,-.032,z-.070*scale),
                (x-sign*.011,-.057,z-.092*scale),
                (x-sign*.016,-.080,z-.088*scale),
                (x-sign*.018,-.086,z-.065*scale)]
        flesh_tube('Finger_build',points,[(.018,.021),(.017,.021),(.0165,.020),
            (.015,.019),(.0145,.017),(.007,.010)],skin)
    flesh_tube('Thumb_build',[(sign*.413,-.032,.687),(sign*.395,-.052,.665),
        (sign*.384,-.080,.638),(sign*.390,-.099,.617),(sign*.407,-.105,.612)],
        [(.026,.028),(.025,.027),(.023,.025),(.019,.022),(.010,.013)],skin)
    parts=OBJECTS[before:]
    bpy.ops.object.select_all(action='DESELECT')
    for obj in parts:obj.select_set(True)
    bpy.context.view_layer.objects.active=parts[0]
    bpy.ops.object.join();obj=bpy.context.object;obj.name='Palm_relaxed_connected_'+str(sign)
    remesh=obj.modifiers.new('Continuous finger webs','REMESH');remesh.mode='VOXEL';remesh.voxel_size=.0035
    bpy.ops.object.modifier_apply(modifier=remesh.name)
    smooth=obj.modifiers.new('Soft hand planes','SMOOTH');smooth.factor=.55;smooth.iterations=2
    bpy.ops.object.modifier_apply(modifier=smooth.name)
    decimate=obj.modifiers.new('Hand surface budget','DECIMATE');decimate.ratio=.24
    bpy.ops.object.modifier_apply(modifier=decimate.name)
    inverse=obj.matrix_world.inverted()
    angle=-sign*.60;cosine=math.cos(angle);sine=math.sin(angle)
    for vertex in obj.data.vertices:
        co=obj.matrix_world@vertex.co;co.y-=.035
        dx=co.x-sign*.455;dy=co.y+.045
        co.x=sign*.455+dx*cosine-dy*sine;co.y=-.045+dx*sine+dy*cosine
        vertex.co=inverse@co
    for polygon in obj.data.polygons:polygon.use_smooth=True
    OBJECTS[before:]=[obj]


def details(mats):
    jacketmat,trim,zipmat,ochre,skin,boot,sole,lace=mats
    boot_panel=material('Boot_leather_quarters',(.025,.023,.020))
    inner_shirt=material('Inner_knitted_shirt',(.012,.012,.011),.90)
    verts=[];faces=[];n=32
    sections=[(.235,.180,1.340),(.236,.181,1.345),
              (.211,.160,1.425),(.210,.159,1.432),
              (.190,.143,1.433),(.190,.143,1.425),
              (.216,.163,1.345),(.217,.164,1.340)]
    for rx,ry,z in sections:
        for j in range(n):
            a=-math.pi/2+.065+(2*math.pi-.130)*j/(n-1)
            sx,sy=superellipse(a,.48)
            band_height=max(0,min(1,(z-1.340)/.093))
            nape=(.092*(1-band_height)+.068*band_height)*max(0,sy)**2
            front_drop=(.045*(1-band_height)+.090*band_height)*max(0,-sy)**6
            verts.append((sx*rx,sy*ry,z-front_drop+nape))
    for i in range(len(sections)):
        following=(i+1)%len(sections)
        for j in range(n-1):faces.append((i*n+j,i*n+j+1,following*n+j+1,following*n+j))
    faces.extend([tuple(i*n for i in reversed(range(len(sections)))),
                  tuple((i+1)*n-1 for i in range(len(sections)))])
    mesh_object('Collar_standing_open_band',verts,faces,trim,subdivision=1)
    # Dark knitted inner layer is visible in the low front collar opening.
    ring_surface('Collar_inner_knit',[(0,.008,1.291,.112,.098),
        (0,.008,1.322,.111,.098),(0,.008,1.382,.092,.085)],32,inner_shirt,power=.65,cap=False)
    ring_surface('Jacket_hem_turned_seam',[(0,0,.685,.332,.177),
        (0,0,.694,.336,.181),(0,0,.716,.336,.181),(0,0,.723,.334,.179)],
        40,trim,power=.55,cap=False,subdivision=1)
    points=[]
    for z in [.699,.75,.84,.96,1.075,1.15,1.205,1.265,1.292,1.320,1.343]:
        depth=.171 if z<.78 else (.190 if z<1.18 else .179 if z<1.24 else .168 if z<1.31 else .157)
        points.append((0,-depth-.006,z))
    curve_mesh('Zipper_tape',points,.0050,trim)
    curve_mesh('Zipper_teeth',[(x,y-.002,z)for x,y,z in points],.0018,zipmat)
    for z in [i*.008+.72 for i in range(70)]:
        depth=.171 if z<.78 else (.190 if z<1.18 else .179 if z<1.24 else .168)
        bevel_box('Zipper_tooth',(0,-depth-.009,z),(.006,.002,.002),zipmat,.0004,1)
    bevel_box('Ochre_zip_pull',(0,-.181,1.246),(.025,.010,.053),ochre,.003,2)
    # Pockets sit in the cloth, with a dark slit and a wide, softly rolled welt.
    for sign in (-1,1):
        bevel_box('Pocket_welt_'+str(sign),(sign*.252,-.187,.883),(.028,.004,.191),trim,.005,2,
                  (0,sign*.12,0))
        curve_mesh('Pocket_opening_'+str(sign),[(sign*.259,-.195,.974),
            (sign*.245,-.198,.801)],.0018,lace)
        curve_mesh('Shoulder_seam_'+str(sign),[(sign*.183,-.139,1.348),
            (sign*.267,-.147,1.329),(sign*.323,-.146,1.283),
            (sign*.352,-.137,1.226)],.0018,trim)
        curve_mesh('Rear_yoke_'+str(sign),[(0,.190,1.202),
            (sign*.17,.184,1.208),(sign*.282,.160,1.202),
            (sign*.338,.122,1.184)],.0019,trim)
        relaxed_hand(sign,skin)
        boot_start=len(OBJECTS)
        cx=sign*.212
        # Layered toe cap, raised ankle, stitched quarters and broad rubber tread.
        ring_surface('Boot_upper_'+str(sign),[
            (cx,-.068,.050,.134,.197),(cx,-.068,.068,.137,.199),
            (cx,-.068,.109,.132,.194),(cx,-.038,.151,.120,.153),
            (cx,.010,.180,.100,.106),(cx,.011,.221,.096,.100),
            (cx,.011,.235,.095,.099)],28,boot,power=.43,subdivision=1)
        outline=[(-.106,.136),(-.126,.105),(-.127,.022),(-.139,-.081),
                 (-.145,-.194),(-.132,-.250),(-.108,-.278)]
        outline += [(x,-.283)for x in(-.094,-.076,-.060,-.042,-.026,-.008,.008,.026,.042,.060,.076,.094)]
        outline +=[(.108,-.278),(.132,-.250),(.145,-.194),(.139,-.081),
                  (.127,.022),(.126,.105),(.106,.136)]
        sole_vertices=[];sole_faces=[];count=len(outline)
        for ring,(z,factor)in enumerate([(.000,1),(.025,1),(.055,.985),(.064,.955)]):
            for j,(x,y)in enumerate(outline):
                notch=.011 if ring==0 and (7<=j<=18) and ((j-7)//2)%2==0 else 0
                arch=.010 if ring==0 and -.035<y<.080 else 0
                sole_vertices.append((cx+x*factor,y*factor,z+notch+arch))
        for ring in range(3):
            for j in range(count):
                sole_faces.append((ring*count+j,ring*count+(j+1)%count,
                                   (ring+1)*count+(j+1)%count,(ring+1)*count+j))
        sole_faces.extend([tuple(reversed(range(count))),tuple(3*count+j for j in range(count))])
        sole_obj=mesh_object('Boot_sole_'+str(sign),sole_vertices,sole_faces,sole,smooth=False)
        edge=sole_obj.modifiers.new('Rubber edge softness','BEVEL');edge.width=.002;edge.segments=1
        bpy.context.view_layer.objects.active=sole_obj;bpy.ops.object.modifier_apply(modifier=edge.name)
        toe=[]
        outline=[(-.112,-.147),(-.133,-.171),(-.133,-.252),(-.108,-.273),
                 (.108,-.273),(.133,-.252),(.133,-.171),(.112,-.147)]
        for top in (False,True):
            for x,y in outline:
                z=.071 if not top else .110+.035*(y+.273)/.126
                toe.append((cx+x,y,z))
        toe.append((cx,-.208,.142))
        faces=[tuple(reversed(range(8)))]+[(8+j,8+(j+1)%8,16)for j in range(8)]
        for j in range(8):faces.append((j,(j+1)%8,(j+1)%8+8,j+8))
        toe_obj=mesh_object('Boot_toecap_'+str(sign),toe,faces,boot)
        edge=toe_obj.modifiers.new('Rolled toe stitching','BEVEL');edge.width=.006;edge.segments=2
        bpy.context.view_layer.objects.active=toe_obj;bpy.ops.object.modifier_apply(modifier=edge.name)
        tongue=[]
        for z,y in[(.128,-.221),(.145,-.205),(.170,-.173),(.195,-.137),(.221,-.108),(.238,-.096)]:
            for x in(-.057,0,.057):tongue.append((cx+x,y-(.004 if x==0 else 0),z))
        tongue_faces=[]
        for row in range(5):
            for col in range(2):tongue_faces.append((row*3+col,row*3+col+1,(row+1)*3+col+1,(row+1)*3+col))
        tongue_obj=mesh_object('Boot_padded_tongue_'+str(sign),tongue,tongue_faces,boot_panel)
        solid=tongue_obj.modifiers.new('Tongue leather thickness','SOLIDIFY');solid.thickness=.005
        bpy.context.view_layer.objects.active=tongue_obj;bpy.ops.object.modifier_apply(modifier=solid.name)
        for edge_side in(-1,1):
            profile=[(.050,.134,.197,-.068),(.068,.137,.199,-.068),
                     (.109,.132,.194,-.068),(.151,.120,.153,-.038),
                     (.180,.100,.106,.010),(.221,.096,.100,.011),(.235,.095,.099,.011)]
            panel=[]
            for y,z in[(.090,.075),(-.100,.075),(-.108,.132),(-.040,.185),
                       (-.012,.215),(.064,.216),(.085,.160)]:
                lo,hi=next((low,high)for low,high in zip(profile,profile[1:])if low[0]<=z<=high[0])
                t=(z-lo[0])/(hi[0]-lo[0])
                rx,ry,cy=[lo[index]*(1-t)+hi[index]*t for index in(1,2,3)]
                cross=max(0,1-min(.999,abs((y-cy)/ry))**(2/.43))**(.43/2)
                panel.append((cx+edge_side*(rx*cross*.985-.0005),y,z))
            panel_obj=mesh_object('Boot_shaped_quarter_%s_%s'%(sign,edge_side),panel,[tuple(range(7))],boot_panel)
            solid=panel_obj.modifiers.new('Quarter leather thickness','SOLIDIFY');solid.thickness=.002;solid.offset=0
            bpy.context.view_layer.objects.active=panel_obj;bpy.ops.object.modifier_apply(modifier=solid.name)
            curve_mesh('Boot_quarter_stitch_%s_%s'%(sign,edge_side),
                [(x+edge_side*.001,y,z)for x,y,z in panel[1:]],.0008,lace)
        for k in range(6):
            y=-.247+k*.069
            for side in(-1,1):
                bevel_box('Sole_tread_%s_%s_%s'%(sign,k,side),
                    (cx+side*(.119 if y>.01 else .130),y,.014),(.014,.025,.028),sole,.003,1)
        curve_mesh('Boot_stitched_quarter_'+str(sign),[(cx-.095,.075,.162),
            (cx-.103,-.033,.147),(cx-.099,-.105,.115),(cx+.099,-.105,.115),
            (cx+.103,-.033,.147),(cx+.095,.075,.162)],.0018,lace)
        for k in range(5):
            z=.136+k*.022;y=-.210+k*.024
            curve_mesh('Boot_lace_%s_%s'%(sign,k),[(cx-.050,y,z),
                (cx+.048,y-.004,z+.007)],.0027,lace)
            curve_mesh('Boot_lace_cross_%s_%s'%(sign,k),[(cx+.050,y,z),
                (cx-.048,y+.020,z+.018)],.0027,lace)
            for edge in(-1,1):
                bevel_box('Boot_eyelet_%s_%s_%s'%(sign,k,edge),(cx+edge*.054,y+.001,z+.001),(.008,.006,.008),zipmat,.002,2)
        angle=sign*.16;cosine=math.cos(angle);sine=math.sin(angle)
        for obj in OBJECTS[boot_start:]:
            for vertex in obj.data.vertices:
                world=obj.matrix_world@vertex.co
                dx=world.x-cx;dy=world.y
                world.x=cx+dx*cosine-dy*sine;world.y=dx*sine+dy*cosine
                world.z=max(0,world.z)
                vertex.co=obj.matrix_world.inverted()@world


def smoothstep(a,b,x):
    t=max(0,min(1,(x-a)/(b-a)))
    return t*t*(3-2*t)


def reference_garment_profile():
    # The side turnaround has a substantial padded coat, with chest and scapula
    # volume beyond the head. Keep the fixed height and physics rig untouched.
    for obj in OBJECTS:
        name=obj.name
        is_jacket=name.startswith('Jacket_continuous')
        body_detail=name.startswith(('Jacket_hem','Zipper','Ochre','Pocket','Shoulder_seam','Rear_yoke'))
        collar=name.startswith('Collar_standing')
        cuff=name.startswith('Cuff')
        if not(is_jacket or body_detail or collar or cuff):continue
        attr=obj.data.attributes.get('sleeve_side')
        inverse=obj.matrix_world.inverted()
        for vertex in obj.data.vertices:
            co=obj.matrix_world@vertex.co
            sleeve=abs(attr.data[vertex.index].value) if attr else float(cuff)
            body_factor=1.45-.28*smoothstep(1.20,1.40,co.z)
            arm_factor=1.05+.25*smoothstep(.76,1.15,co.z)
            factor=(body_factor*(1-sleeve)+arm_factor*sleeve) if is_jacket else arm_factor if cuff else 1.10 if collar else body_factor
            co.y*=factor
            if not(collar or cuff):co.y+=.010*(1-min(1,sleeve))
            if is_jacket and co.y<0 and sleeve<.1:
                co.y-=.005*math.sin(co.z*31+abs(co.x)*14)*math.exp(-((abs(co.x)-.25)/.075)**2)
            if is_jacket and co.y>0 and sleeve<.1:
                co.z+=.082*smoothstep(1.28,1.35,co.z)*min(1,co.y/.18)**4
            vertex.co=inverse@co
        obj.data.update()


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
    if name.startswith('Cuff'):return {'lowerarm_'+side:1}
    if name.startswith(('Trousers','Trouser_seam')):
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
    scene.world.use_nodes=True
    scene.world.node_tree.nodes['Background'].inputs['Color'].default_value=(.52,.48,.43,1)
    scene.world.node_tree.nodes['Background'].inputs['Strength'].default_value=.65
    scene.view_settings.view_transform='AgX'
    floor=material('Studio_warm_neutral',(.52,.49,.45))
    bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.006))
    bpy.context.object.name='Studio_floor';bpy.context.object.data.materials.append(floor)
    for name,location,power,size in [('Key',(-3,-4,5),450,4),('Fill',(3,-2,3),220,3),('Rim',(1,3,4),380,3)]:
        light=bpy.data.lights.new(name,'AREA');light.energy=power;light.shape='DISK';light.size=size
        obj=bpy.data.objects.new(name,light);bpy.context.collection.objects.link(obj);obj.location=location
        obj.rotation_euler=(Vector((0,0,.9))-obj.location).to_track_quat('-Z','Y').to_euler()
    print('RENDER_DEVICE CPU; threads=2; no GUI; no audio')


def export(rig,render,deformation=False,images=IMAGES):
    OUT.mkdir(parents=True,exist_ok=True);CHECK.mkdir(parents=True,exist_ok=True);images.mkdir(parents=True,exist_ok=True)
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
    def bounds(objects):
        points=[obj.matrix_world@vertex.co for obj in objects for vertex in obj.data.vertices]
        low=[min(point[axis]for point in points)for axis in range(3)]
        high=[max(point[axis]for point in points)for axis in range(3)]
        assert all(math.isfinite(value)for point in points for value in point)
        return {'min':low,'max':high,'size':[high[axis]-low[axis]for axis in range(3)]}
    metrics={'height_metres':HEIGHT,'triangles':triangles,'vertices':sum(len(o.data.vertices) for o in OBJECTS),
             'objects':len(OBJECTS),'bones':len(JOINTS),
             'anatomical_joint_z':{'hip':.88,'knee':.46,'ankle':.14},
             'coat_hem_z':.685,'linear_skin':True,'render_device':'CPU',
             'source_reference':'docs/art/explorations/ilyusha/2026-11-02-independent-3d/04.png',
             'neutral_bounds_metres':bounds(OBJECTS),
             'coat_bounds_metres':bounds([obj for obj in OBJECTS if obj.name.startswith('Jacket')]),
             'head_bounds_metres':bounds([obj for obj in OBJECTS if obj.name.startswith(('Head','Ear','Hair','Nose'))]),
             'input_hashes':{str(path.relative_to(ROOT)):hashlib.sha256(path.read_bytes()).hexdigest()
                 for path in[Path(__file__),OUT/'ilyusha.glb',source/'ilyusha.blend',
                    ROOT/'docs/art/explorations/ilyusha/2026-11-02-independent-3d/04.png']},
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
            bpy.context.scene.render.filepath=str(images/(name+'.png'))
            bpy.ops.render.render(write_still=True)
        (images/'manifest.json').write_text(json.dumps({
            'scope':'Authored neutral mesh/skin only; gameplay appearance and animation NOT_RUN',
            'input_hashes':metrics['input_hashes'],
            'camera':'Orthographic scale 2.07m; front/left/back target (0,0,.88), 3/4 elevated',
            'renderer':'Cycles CPU, 2 threads, 32 samples; 700x900',
            'renders':{name+'.png':hashlib.sha256((images/(name+'.png')).read_bytes()).hexdigest()
                for name in['front','left','back','three_quarter']}},indent=2)+'\n')
    if deformation:
        if not render:studio()
        # A genuine deformation probe uses the exported linear-skin armature.
        rig.pose.bones['thigh_l'].rotation_mode='XYZ'
        rig.pose.bones['calf_l'].rotation_mode='XYZ'
        for angle in (45,90):
            rig.pose.bones['thigh_l'].rotation_euler.x=math.radians(-35)
            rig.pose.bones['calf_l'].rotation_euler.x=math.radians(angle)
            camera_at('knee_'+str(angle),(3,-6,2.0),(0,0,.88),2.07)
            bpy.context.scene.render.filepath=str(images/('knee_%s.png'%angle))
            bpy.ops.render.render(write_still=True)


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--render',action='store_true')
    parser.add_argument('--deformation',action='store_true')
    parser.add_argument('--render-dir',type=Path,default=IMAGES)
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    mats={
        'jacket':material('Graphite_wool',(.048,.049,.050)),
        'trim':material('Graphite_seams_collar',(.038,.039,.040)),
        'zip':material('Zipper_dull_gray',(.12,.125,.12)),
        'ochre':material('Muted_ochre_pull',(.42,.36,.075)),
        'pants':material('Dark_slate_trousers',(.028,.031,.038)),
        'skin':material('Warm_pale_skin',(.62,.32,.17)),
        'hair':material('Dark_brown_hair',(.022,.011,.006)),
        'hair_light':material('Hair_facet_variation',(.039,.019,.010)),
        'brow':material('Heavy_dark_brows',(.027,.019,.014)),
        'eye':material('Warm_eye_white',(.76,.74,.66)),
        'pupil':material('Pupil',(.014,.012,.010)),
        'crease':material('Skin_mouth_crease',(.28,.12,.06)),
        'boot':material('Matte_winter_boot',(.028,.026,.023)),
        'sole':material('Rubber_soles',(.017,.018,.017)),
        'lace':material('Boot_laces',(.060,.054,.044)),
    }
    jacket(mats['jacket'],mats['trim']);pants(mats['pants'])
    head(*(mats[k] for k in ['skin','hair','hair_light','brow','eye','pupil','crease']))
    details([mats[k] for k in ['jacket','trim','zip','ochre','skin','boot','sole','lace']])
    reference_garment_profile()
    rig=armature();export(rig,args.render,args.deformation,args.render_dir)


if __name__=='__main__':main()
