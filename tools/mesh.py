"""Indexed, tiled glTF 2.0 export and procedural facade atlas."""
from collections import defaultdict
from pathlib import Path
import json
import math
import struct

import numpy as np
from PIL import Image, ImageDraw

PALETTE = {
    'baxter_brick': (.69,.59,.44), 'baxter_trim': (.78,.71,.58), 'glass': (.27,.35,.36),
    'ground': (0.45, .52, .30), 'asphalt': (.21,.23,.23), 'highway': (.25,.26,.27),
    'service': (.29,.30,.29), 'gravel': (.47,.43,.36), 'walk': (.62,.59,.51),
    'lot': (.25,.26,.25), 'yellow': (.92,.65,.16), 'white': (.81,.81,.72),
    'water': (.19,.35,.29), 'bank': (.47,.40,.28), 'rail': (.32,.25,.20),
    'steel': (.29,.31,.30), 'signal': (.24,.25,.14), 'signal_glass': (.85,.27,.12),
    'trunk': (.34,.25,.18), 'leaf': (.24,.40,.17), 'leaf_light': (.37,.50,.22),
    'palm': (.33,.49,.19), 'roofs': (.47,.46,.42), 'shingle': (.36,.32,.28),
    'metalroof': (.64,.64,.60), 'trim': (.71,.65,.56), 'equipment': (.60,.62,.58),
    'grass': (.46,.55,.31), 'woodland': (.37,.47,.25), 'field': (.54,.54,.33),
    'baseball': (.66,.48,.32), 'runway': (.26,.27,.28), 'concrete': (.54,.52,.47),
    'sign': (.23,.42,.38), 'bench': (.44,.29,.17),
    'brick_a': (1,1,1), 'brick_b': (1,1,1), 'stucco_a': (1,1,1), 'stucco_b': (1,1,1),
    'house_a': (1,1,1), 'house_b': (1,1,1), 'warehouse': (1,1,1), 'shop': (1,1,1),
}
ATLAS = ['brick_a','brick_b','stucco_a','stucco_b','house_a','house_b','warehouse','shop']


def facade_atlas(path: Path) -> None:
    rng = np.random.default_rng(855)
    colors = [(153,98,76),(184,126,98),(209,192,159),(171,171,152),
              (202,194,168),(194,179,154),(170,175,169),(193,175,147)]
    image = Image.new('RGB', (512,256))
    for i, color in enumerate(colors):
        rows = np.clip(np.array(color) + rng.normal(0, 2.8, (128,128,1)), 0, 255)
        tile = Image.fromarray(rows.astype(np.uint8))
        draw = ImageDraw.Draw(tile)
        if i < 2:
            for y in range(6, 128, 7):
                draw.line((0,y,128,y),fill=(173,145,123))
                for x in range(8*(y%2),128,16):
                    draw.line((x,y-7,x,y),fill=(169,137,116))
        elif i in (4,5,6):
            for y in range(0,128,7):
                draw.line((0,y,128,y),fill=tuple(c-12 for c in color))
        draw.rectangle((0, 115, 127, 127), fill=tuple(c-22 for c in color))
        panes = [(21,37,49,86),(80,37,107,86)]
        if i == 6:
            panes = [(44,50,83,76)]
        if i == 7:
            panes = [(10,44,57,105),(69,44,116,105)]
            draw.rectangle((0,26,127,37), fill=(69,77,74))
        for a,b,c,d in panes:
            draw.rectangle((a-3,b-4,c+3,d+4),fill=(107,99,85))
            draw.rectangle((a,b,c,d),fill=(64,78,80))
            draw.polygon([(a,b),(c,b),(a,b+(d-b)*.65)],fill=(98,122,125))
            draw.line(((a+c)//2,b,(a+c)//2,d),fill=(124,119,106),width=2)
            draw.line((a,d+1,c,d+1),fill=(205,194,162),width=2)
        image.paste(tile, ((i%4)*128,(i//4)*128))
    image.save(path)


def atlas_uv(material, uv):
    if material not in ATLAS:
        return uv
    i = ATLAS.index(material)
    u,v = uv
    return ((128*(i%4)+3+122*u)/512,(128*(i//4)+3+122*v)/256)


class Mesh:
    def __init__(self):
        self.parts = defaultdict(lambda: [[], [], [], []])

    def add(self, material, points, indices, uvs=None, normals=None):
        if not len(indices):
            return
        p,n,t,f = self.parts[material]
        offset = len(p)
        p.extend(points)
        f.extend(np.asarray(indices,dtype=np.uint32).ravel() + offset)
        t.extend([atlas_uv(material, uv) for uv in uvs] if uvs is not None else [(0,0)]*len(points))
        if normals is None:
            a = np.asarray(points)
            tri = np.asarray(indices).reshape(-1,3)
            cross = np.cross(a[tri[:,1]]-a[tri[:,0]], a[tri[:,2]]-a[tri[:,0]])
            accum = np.zeros(a.shape)
            np.add.at(accum,tri.ravel(),np.repeat(cross,3,axis=0))
            lengths = np.linalg.norm(accum,axis=1)
            n.extend(accum/np.maximum(lengths[:,None],1e-6))
        else:
            n.extend(normals)

    def quad(self, material, points, uvs=None):
        self.add(material, points, [0,1,2,0,2,3], uvs)

    def triangles(self):
        return sum(len(v[3])//3 for v in self.parts.values())


def write_glb(path, name, mesh, ground_image=None):
    if not mesh.parts:
        return False
    buffer = bytearray()
    accessors, views, primitives, materials = [], [], [], []

    def push(array, component, typ, target, bounds=False):
        data = np.asarray(array, dtype='<u4' if component==5125 else '<f4')
        raw = data.tobytes()
        view = len(views)
        views.append(dict(buffer=0,byteOffset=len(buffer),byteLength=len(raw),target=target))
        buffer.extend(raw)
        accessor = dict(bufferView=view,componentType=component,count=len(data),type=typ)
        if bounds:
            accessor.update(min=data.min(axis=0).tolist(),max=data.max(axis=0).tolist())
        accessors.append(accessor)
        return len(accessors)-1

    for material,(p,n,t,f) in sorted(mesh.parts.items()):
        base = [c/12.92 if c<=.04045 else ((c+.055)/1.055)**2.4 for c in PALETTE[material]]
        pbr = dict(baseColorFactor=[*base,1],metallicFactor=.16 if material in ('steel','metalroof') else 0,
                   roughnessFactor=.40 if material=='water' else .85)
        attrs = dict(POSITION=push(p,5126,'VEC3',34962,True),NORMAL=push(n,5126,'VEC3',34962))
        if material in ATLAS or material=='ground' and ground_image:
            if material=='ground':
                t=[(v[0]/2000,v[2]/2000) for v in p]
                pbr['baseColorFactor']=[1,1,1,1]
            attrs['TEXCOORD_0'] = push(t,5126,'VEC2',34962)
            pbr['baseColorTexture'] = dict(index=0)
        primitives.append(dict(attributes=attrs,indices=push(f,5125,'SCALAR',34963),material=len(materials)))
        materials.append(dict(name=material,pbrMetallicRoughness=pbr,doubleSided=False))
    doc = dict(asset=dict(version='2.0',generator='Harlingen GIS mesh pipeline'),
               scene=0,scenes=[dict(nodes=[0])],nodes=[dict(mesh=0,name=name)],
               meshes=[dict(name=name,primitives=primitives)],materials=materials,accessors=accessors,
               bufferViews=views,buffers=[dict(byteLength=len(buffer))])
    if ground_image or any(m['name'] in ATLAS for m in materials):
        atlas = Path(__file__).resolve().parents[1] / 'assets' / 'facades.png'
        contents = ground_image if ground_image else atlas.read_bytes()
        view = len(views)
        views.append(dict(buffer=0,byteOffset=len(buffer),byteLength=len(contents)))
        buffer.extend(contents)
        buffer.extend(b'\0'*((-len(buffer))%4))
        doc['buffers'][0]['byteLength']=len(buffer)
        doc.update(images=[dict(bufferView=view,mimeType='image/jpeg' if ground_image else 'image/png')],textures=[dict(source=0)])
    head = json.dumps(doc,separators=(',',':')).encode()
    head += b' '*((-len(head))%4)
    with path.open('wb') as handle:
        handle.write(struct.pack('<4sII',b'glTF',2,28+len(head)+len(buffer)))
        handle.write(struct.pack('<I4s',len(head),b'JSON'))
        handle.write(head)
        handle.write(struct.pack('<I4s',len(buffer),b'BIN\0'))
        handle.write(buffer)
    return True


def cylinder(mesh, material, x, z, y_a, y_b, r_a, r_b, sides=8):
    rings = [[(x+r*math.cos(i*math.tau/sides),y,z+r*math.sin(i*math.tau/sides))
              for i in range(sides)] for y,r in [(y_a,r_a),(y_b,r_b)]]
    for i in range(sides):
        j=(i+1)%sides
        mesh.quad(material,[rings[0][i],rings[1][i],rings[1][j],rings[0][j]])
    mesh.add(material,rings[1],[v for i in range(1,sides-1) for v in (0,i+1,i)])


def box(mesh, material, x, y, z, w, h, d):
    ring=[(x-w/2,z-d/2),(x+w/2,z-d/2),(x+w/2,z+d/2),(x-w/2,z+d/2)]
    for i,(a,b) in enumerate(ring):
        c,e=ring[(i+1)%4]
        mesh.quad(material,[(c,y,e),(a,y,b),(a,y+h,b),(c,y+h,e)])
    mesh.quad(material,[(a,y+h,b) for a,b in reversed(ring)])
