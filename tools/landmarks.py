"""Build three footprint-based landmarks and remove only their superseded shells."""

import json
import math
import struct
import sys
from dataclasses import dataclass
from io import BytesIO
from zipfile import ZipFile

import numpy as np
from PIL import Image, ImageOps
from shapely import intersects_xy
from shapely.geometry import Polygon
from shapely.geometry.polygon import orient

from build import Elevation, ROOT, patch, read_features, walls
from mesh import Mesh, PALETTE, write_glb

OUT = ROOT / 'assets' / 'landmarks'
PALETTE.update({
    'ivory': (.94, .93, .88), 'soffit': (.76, .78, .76),
    'stripes_blue': (.065, .32, .65), 'stripes_deep': (.047, .18, .38),
    'valero_red': (.72, .085, .12), 'valero_dark': (.44, .07, .09),
    'sill': (.25, .29, .29), 'roof_gray': (.43, .46, .45),
    'station_glass': (.25, .46, .52), 'display': (.14, .24, .24),
    'concrete_pad': (.67, .65, .60), 'curb_red': (.66, .16, .13),
    'bollard': (.92, .66, .13), 'rubber': (.09, .10, .10),
    'hospital_brick': (.64, .43, .34), 'hospital_brick_light': (.76, .55, .45),
    'limestone': (.83, .78, .67), 'hospital_glass': (.27, .44, .53),
    'hospital_blue': (.10, .27, .37), 'almond': (.72, .67, .56),
    'forecourt': (.40, .41, .39),
})


@dataclass
class Frame:
    point: np.ndarray
    tangent: np.ndarray
    normal: np.ndarray
    width: float

    @classmethod
    def edge(cls, a, b):
        a, b = np.array(a), np.array(b)
        length = np.linalg.norm(b - a)
        tangent = (b - a) / length
        return cls((a + b) / 2, tangent, np.array([tangent[1], -tangent[0]]), length)

    def xy(self, across, out):
        return self.point + across * self.tangent + out * self.normal

    @property
    def yaw(self):
        return math.atan2(*self.normal)


def edges(poly):
    xy = list(orient(poly).exterior.coords)
    return [Frame.edge(a, b) for a, b in zip(xy, xy[1:])]


def facade(poly, direction):
    faces = edges(poly)
    return max(faces, key=lambda e: e.width * max(0., e.normal @ direction) ** 3)


def rectangle_frame(poly, direction):
    rect = poly.minimum_rotated_rectangle
    front = facade(rect, direction)
    center = np.asarray(rect.centroid.coords[0])
    depth = 2 * np.linalg.norm(front.point - center)
    front.point = center
    return front, depth


def number(x):
    return f'{float(x):.6f}'


def vector(values):
    return ', '.join(map(number, values))


def write_container(path, doc, payload):
    header = json.dumps(doc, separators=(',', ':')).encode()
    header += b' ' * (-len(header) % 4)
    path.write_bytes(struct.pack('<4sII', b'glTF', 2, 28 + len(header) + len(payload)) +
                     struct.pack('<I4s', len(header), b'JSON') + header +
                     struct.pack('<I4s', len(payload), b'BIN\0') + payload)


def read_container(raw):
    length = struct.unpack_from('<I', raw, 12)[0]
    return json.loads(raw[20:20 + length]), bytearray(raw[28 + length:])


def add_masonry(doc, data):
    """Embed a repeatable neutral brick map for the two hospital masonry tints."""
    texture = ROOT/'materials'/'textures'/'brick_albedo.jpg'
    with Image.open(texture) as original:
        gray = ImageOps.autocontrast(ImageOps.grayscale(original).resize((256, 256)), cutoff=3)
        gray = gray.point(lambda value: round(188 + value * .26))
    encoded = BytesIO()
    gray.convert('RGB').save(encoded, 'JPEG', quality=88)

    def append(raw, **fields):
        view = len(doc['bufferViews'])
        doc['bufferViews'].append(dict(buffer=0, byteOffset=len(data), byteLength=len(raw), **fields))
        data.extend(raw)
        data.extend(b'\0' * (-len(data) % 4))
        return view

    doc['images'] = [dict(bufferView=append(encoded.getvalue()), mimeType='image/jpeg')]
    doc['textures'] = [dict(source=0)]
    for primitive in doc['meshes'][0]['primitives']:
        material = doc['materials'][primitive['material']]
        if not material['name'].startswith('hospital_brick'):
            continue
        material['pbrMetallicRoughness']['baseColorTexture'] = dict(index=0)
        attrs = primitive['attributes']
        position, normal = (doc['accessors'][attrs[key]] for key in ('POSITION', 'NORMAL'))
        coordinates = np.frombuffer(data, '<f4', count=position['count']*3,
                                    offset=doc['bufferViews'][position['bufferView']]['byteOffset']).reshape(-1, 3)
        vectors = np.frombuffer(data, '<f4', count=normal['count']*3,
                                offset=doc['bufferViews'][normal['bufferView']]['byteOffset']).reshape(-1, 3)
        uv = np.column_stack((coordinates[:,0]*vectors[:,2] - coordinates[:,2]*vectors[:,0],
                              -coordinates[:,1])) * .42
        del coordinates, vectors
        view = append(uv.astype('<f4').tobytes(), target=34962)
        attrs['TEXCOORD_0'] = len(doc['accessors'])
        doc['accessors'].append(dict(bufferView=view, componentType=5126, count=len(uv), type='VEC2'))
    doc['buffers'][0]['byteLength'] = len(data)


def replace_shells(path, baseline, origin, polygons):
    doc, data = read_container(baseline)
    removed = 0
    remaining = 0
    tolerance = {'BuildingsFar': .65, 'FacadeDetails': .38}.get(path.stem, .04)
    areas = [polygon.buffer(tolerance) for polygon in polygons]

    def accessor(index, dtype, width):
        spec = doc['accessors'][index]
        view = doc['bufferViews'][spec['bufferView']]
        start = view.get('byteOffset', 0) + spec.get('byteOffset', 0)
        return np.frombuffer(data, dtype, count=spec['count'] * width, offset=start).reshape(-1, width), spec, view

    for node in doc['nodes']:
        if 'mesh' not in node:
            continue
        tx, _, tz = node.get('translation', (0, 0, 0))
        shift = origin + np.array([tx, tz])
        mesh = doc['meshes'][node['mesh']]
        kept = []
        for primitive in mesh['primitives']:
            indexes, spec, view = accessor(primitive['indices'], '<u4', 1)
            coords, _, _ = accessor(primitive['attributes']['POSITION'], '<f4', 3)
            world = coords[:, [0, 2]] + shift
            triangles = indexes.reshape(-1, 3)
            cut = np.zeros(len(triangles), dtype=bool)
            for area in areas:
                contains = intersects_xy(area, *world.T)
                cut |= contains[triangles].all(axis=1)
            still = triangles[~cut].ravel()
            removed += np.count_nonzero(cut)
            remaining += len(still) // 3
            if len(still):
                indexes[:len(still), 0] = still
                spec['count'] = len(still)
                view['byteLength'] = still.nbytes
                kept.append(primitive)
        if kept:
            mesh['primitives'] = kept
        else:
            del node['mesh']
    if removed:
        unused = {i for i, m in enumerate(doc['meshes'])} - {n['mesh'] for n in doc['nodes'] if 'mesh' in n}
        remap = {old: new for new, old in enumerate(i for i in range(len(doc['meshes'])) if i not in unused)}
        doc['meshes'] = [m for i, m in enumerate(doc['meshes']) if i not in unused]
        for node in doc['nodes']:
            if 'mesh' in node:
                node['mesh'] = remap[node['mesh']]
        write_container(path, doc, data)
    return int(removed), remaining


class Landmark:
    def __init__(self, name, tile, origin, dem):
        self.name = name
        self.tile = tile
        self.origin = origin
        self.dem = dem
        self.visual = Mesh()
        self.collision = Mesh()
        self.labels = []

    def grade(self, p):
        return float(self.dem(*p))

    def cuboid(self, frame, mat, x, y, z, width, height, depth, *, solid=False):
        footprint = Polygon([frame.xy(x + a, z + b)
                             for a, b in ((-width/2, -depth/2), (width/2, -depth/2),
                                          (width/2, depth/2), (-width/2, depth/2))])
        self.shell(footprint, y, y + height, mat, mat, solid=solid, underside=True)

    def shell(self, poly, bottom, top, wall, roof, *, solid=False, underside=False):
        poly = orient(poly)
        dx, dz = self.origin
        for mesh in [self.visual, self.collision] if solid else [self.visual]:
            walls(mesh, poly, bottom, top, wall, dx, dz, False)
            patch(mesh, poly, roof, lambda _x, _z: top, dx, dz)
        if underside:
            p = np.asarray(poly.exterior.coords)[:-1] - self.origin
            self.visual.quad(roof, [(x, bottom, z) for x, z in p])

    def label(self, frame, words, x, y, z, size, color=(1, 1, 1)):
        gx, gz = frame.xy(x, z) - self.origin
        self.labels.append((words, (gx, y, gz), frame.yaw, size, color))

    def surface(self, poly, mat, offset=.065):
        patch(self.visual, poly, mat, lambda x, z: self.dem(x, z) + offset, *self.origin, 4)

    def window(self, f, x, y, width, height, glass='station_glass', trim='sill', out=0):
        self.cuboid(f, trim, x, y-.065, out+.055, width+.16, height+.13, .15)
        self.cuboid(f, glass, x, y, out+.14, width, height, .04)
        self.cuboid(f, trim, x, y, out+.169, .065, height, .04)

    def save(self):
        path = OUT / f'{self.name}.glb'
        write_glb(path, self.name, self.visual)
        doc, data = read_container(path.read_bytes())
        for material in doc['materials']:
            name = material['name']
            pbr = material['pbrMetallicRoughness']
            if name.endswith('glass') or name == 'display':
                pbr.update(roughnessFactor=.22, metallicFactor=.13)
            elif name in ('sill', 'roof_gray', 'hospital_blue', 'stripes_blue', 'valero_red'):
                pbr['roughnessFactor'] = .48
        if self.name == 'HarlingenMedicalCenter':
            add_masonry(doc, data)
        write_container(path, doc, data)
        points = []
        for positions, _, _, indices in self.collision.parts.values():
            # Godot's ConcavePolygonShape3D face winding is clockwise.
            for a, b, c in np.asarray(indices).reshape(-1, 3):
                points.extend((positions[a], positions[c], positions[b]))
        string = [
            '[gd_scene format=3]',
            f'[ext_resource type="PackedScene" path="res://assets/landmarks/{self.name}.glb" id="model"]',
            '[sub_resource type="ConcavePolygonShape3D" id="structure"]',
            'backface_collision = true',
            f'data = PackedVector3Array({vector(x for p in points for x in p)})',
            f'[node name="{self.name}" type="Node3D"]',
            '[node name="Model" parent="." instance=ExtResource("model")]',
            '[node name="Structure" type="StaticBody3D" parent="."]',
            '[node name="Colliders" type="CollisionShape3D" parent="Structure"]',
            'shape = SubResource("structure")',
        ]
        for i, (words, pos, yaw, size, color) in enumerate(self.labels):
            string.extend([
                f'[node name="Sign{i+1:02d}" type="Label3D" parent="."]',
                f'position = Vector3({vector(pos)})', f'rotation = Vector3(0, {number(yaw)}, 0)',
                f'text = {json.dumps(words)}', 'font_size = 96', 'outline_size = 0',
                f'pixel_size = {number(size/96)}', f'modulate = Color({vector((*color,1))})',
                'double_sided = false', 'visibility_range_end = 350.0',
            ])
        (OUT / f'{self.name}.tscn').write_text('\n\n'.join(string[:6]) + '\n\n' + '\n'.join(string[6:]) + '\n')
        return self.visual.triangles(), len(points) // 3


def station(site, store, canopy, brand, road):
    stripes = brand == 'Stripes'
    accent, dark = ('stripes_blue', 'stripes_deep') if stripes else ('valero_red', 'valero_dark')
    roof, depth = rectangle_frame(canopy, road)
    grade = site.grade(roof.point)
    width = roof.width
    c = site.cuboid
    # Concrete under the pumps is graded to the mapped terrain; service roads retain their meshes.
    paved = canopy.union(store).convex_hull.buffer(3.15, quad_segs=2)
    concrete = canopy.minimum_rotated_rectangle.buffer(.38, quad_segs=2)
    site.surface(paved.difference(concrete), 'forecourt', .035)
    site.surface(concrete, 'concrete_pad')
    c(roof, 'soffit', 0, grade+4.48, 0, width, .19, depth, solid=True)
    c(roof, 'ivory', 0, grade+4.67, 0, width+.10, .55, depth+.10)
    for f in edges(canopy.minimum_rotated_rectangle):
        c(f, accent, 0, grade+4.69, .07, f.width+.06, .46, .06)
        c(f, dark, 0, grade+4.68, .10, f.width+.08, .075, .05)
        if stripes:
            for offset in np.arange(-f.width/2+.38, f.width/2-.2, .74):
                if abs(offset) > 2.3 or f.width < 5:
                    c(f, 'ivory', offset, grade+4.77, .11, .12, .35, .045)
        if f.width > 6:
            c(f, dark if stripes else accent, 0, grade+4.755, .125, 4.25, .405, .10)
            site.label(f, brand.upper(), 0, grade+4.963, .193, .52)
    rows = 3 if width >= 30 else 2
    for x in np.linspace(-width/2+3.15, width/2-3.15, rows):
        y = site.grade(roof.xy(x,0))
        c(roof, 'concrete_pad', x, y-.08, 0, 3.7, .25, 1.35, solid=True)
        c(roof, 'ivory', x+.99, y-.12, 0, .52, grade+4.56-y, .52, solid=True)
        c(roof, 'sill', x+.99, y+.15, 0, .63, .70, .63)
        c(roof, 'ivory', x-.48, y+.17, 0, 1.03, 1.58, .56, solid=True)
        c(roof, accent, x-.48, y+1.44, 0, 1.08, .36, .64)
        for sign in (-1, 1):
            c(roof, 'display', x-.48, y+.92, .299*sign, .68, .38, .05)
            c(roof, 'rubber', x-.93, y+.37, .29*sign, .045, .91, .05)
            c(roof, 'rubber', x-.85, y+.36, .29*sign, .21, .055, .05)
            c(roof, 'bollard', x+1.54*sign, y+.15, .36*sign, .13, .83, .13)
        for z in (-depth*.31, depth*.31):
            c(roof, 'ivory', x, grade+4.44, z, 1.35, .045, .38)

    center = np.asarray(store.centroid.coords[0])
    f = facade(store, roof.point-center)
    base = site.grade(center)
    foot = np.asarray(store.exterior.coords)
    bottom = min(site.dem(*foot.T))-.26
    site.shell(store, bottom, base+4.05, 'ivory', 'roof_gray', solid=True)
    site.shell(store.buffer(.15, join_style='mitre'), base+3.84, base+4.12, dark, 'roof_gray')
    for side in edges(store):
        if side.width > 2.8:
            c(side, 'almond', 0, base-.04, .045, side.width-.2, .47, .10)
    c(f, 'ivory', 0, base+2.85, .89, f.width-.4, .20, 1.9, solid=True)
    c(f, accent, 0, base+3.00, 1.84, f.width-.35, .35, .12)
    c(f, 'concrete_pad', 0, base-.11, .85, f.width-.24, .22, 1.78, solid=True)
    usable = f.width - 2.2
    count = max(3, round(usable/2.4))
    for i in range(count):
        x = (i-(count-1)/2)*usable/count
        site.window(f, x, base + (.14 if i == count//2 else .49), usable/count-.21,
                    2.20 if i == count//2 else 1.82)
    site.label(f, 'STRIPES' if stripes else 'CONVENIENCE STORE', 0, base+3.53, .075, .69 if stripes else .52,
               PALETTE[dark])

    # The sign is on the end of the pump island, within the mapped fuel parcel.
    pylon = Frame(roof.xy(-width/2+1.15, depth/2+1.98), roof.tangent, roof.normal, 2.85)
    ground = site.grade(pylon.point)
    c(pylon, 'ivory', 0, ground-.10, 0, .33, 5.52, .38, solid=True)
    c(pylon, dark, 0, ground+4.51, 0, 3.05, 1.48, .42)
    c(pylon, accent, 0, ground+5.64, 0, 3.10, .31, .48)
    c(pylon, 'ivory', 0, ground+4.64, .232, 2.81, .065, .035)
    site.label(pylon, brand.upper(), 0, ground+5.20, .227, .55)
    site.label(pylon, 'FUEL  /  MARKET', 0, ground+4.83, .229, .24)
    reverse = Frame(pylon.point, -pylon.tangent, -pylon.normal, pylon.width)
    site.label(reverse, brand.upper(), 0, ground+5.20, .227, .55)


def hospital(site, footprint, canopy):
    center = np.asarray(footprint.centroid.coords[0])
    ground = site.grade(center)
    bottom = min(site.dem(*np.asarray(footprint.exterior.coords).T))-.42
    entry = np.asarray(canopy.centroid.coords[0])
    main = min((f for f in edges(footprint) if f.width > 35 and (entry-f.point) @ f.normal > 0),
               key=lambda f: np.linalg.norm(f.point-entry))
    offsets = np.asarray(canopy.exterior.coords) - main.point
    across = offsets @ main.tangent
    width = across.max() - across.min()
    projection = (offsets @ main.normal).max()
    shift = (across.max()+across.min())/2
    front = Frame(main.xy(shift,0), main.tangent, main.normal, main.width)
    upper = footprint.buffer(-1.22, join_style='mitre')
    c = site.cuboid
    site.shell(footprint, bottom, ground+8.16, 'hospital_brick', 'roof_gray', solid=True)
    site.shell(upper, ground+8.12, ground+16.12, 'hospital_brick_light', 'roof_gray', solid=True)
    for poly, floors, height in [(footprint,(1.1,4.77),7.82), (upper,(8.92,12.52),15.77)]:
        for f in edges(poly):
            if f.width < .75:
                continue
            c(f, 'limestone', 0, ground+height, .09, f.width+.05, .34, .33)
            if f.width < 4.5:
                continue
            divisions = max(1, round((f.width-1.1)/3.14))
            step = (f.width-.95)/divisions
            for j in range(divisions):
                x = (j-(divisions-1)/2)*step
                for floor in floors:
                    if np.allclose(f.point, main.point) and floor < 2 and abs(x-shift) < 12:
                        continue
                    site.window(f, x, ground+floor, min(step-.46, 2.53), 1.81,
                                'hospital_glass','almond')
            c(f, 'limestone', 0, ground+floors[0]-.20, .075, f.width-.08, .11, .18)

    # Covered drop-off follows the mapped canopy axis. The widening at the
    # street end and the column positions are modeled.
    main = front
    y = site.grade(main.xy(0,6.7))
    c(main, 'soffit', 0, y+4.55, projection/2, width, .25, projection+.26, solid=True)
    c(main, 'hospital_blue', 0, y+4.80, projection/2, width+.35, .82, projection+.35)
    c(main, 'limestone', 0, y+5.62, projection/2, width+.65, .19, projection+.60)
    c(main, 'limestone', 0, y+4.73, projection+.17, width+.43, .12, .14)
    for x in (-width/2+1.45, -width*.31, width*.31, width/2-1.45):
        g = site.grade(main.xy(x, projection-1.07))
        c(main, 'limestone', x, g-.23, projection-1.07, .83, y+4.92-g, .83, solid=True)
        c(main, 'almond', x, g-.06, projection-1.07, 1.06, .54, 1.06)
    for x in (-8.9,-5.4,0,5.4,8.9):
        site.window(main, x, ground+.14, 2.9 if x else 3.48, 3.44, 'hospital_glass','hospital_blue')
    c(main, 'concrete_pad', 0, y-.23, 1.46, 23.5, .31, 2.95, solid=True)
    c(main, 'curb_red', 0, y-.085, 2.97, 23.5, .17, .13)
    site.label(main, 'HARLINGEN MEDICAL CENTER', 0, y+5.25, projection+.202, .93)
    site.label(main, 'MAIN ENTRANCE', 0, ground+4.05, .072, .54, PALETTE['hospital_blue'])

    # Site sign faces the main expressway at the campus approach.
    f = min((f for f in edges(footprint) if f.width > 30), key=lambda f: f.point[0])
    c(f, 'hospital_blue', 0, ground+6.92, .10, min(f.width-.9, 26), .75, .15)
    site.label(f, 'HARLINGEN MEDICAL CENTER', 0, ground+7.31, .195, .90)
    way = np.array([2293.0, 4229.0])
    sign = Frame(way, np.array([.54,.842]), np.array([-.842,.54]), 7.6)
    y = site.grade(way)
    c(sign, 'hospital_brick', 0, y-.21, 0, 7.65, 2.18, 1.0, solid=True)
    c(sign, 'limestone', 0, y+1.94, 0, 8.0, .21, 1.18)
    c(sign, 'hospital_blue', 0, y+.15, .53, 7.12, 1.55, .12)
    site.label(sign, 'HARLINGEN\nMEDICAL CENTER', 0, y+.97, .61, .66)


def attach(district, name, baseline):
    scene = baseline.decode()
    resource = f'[ext_resource type="PackedScene" path="res://assets/landmarks/{name}.tscn" id="local_landmark"]'
    scene = scene.replace('\n[node name=', '\n'+resource+'\n\n[node name=', 1)
    scene += f'\n[node name="{name}" parent="." instance=ExtResource("local_landmark")]\n'
    district.write_text(scene)


def main(archive):
    OUT.mkdir(exist_ok=True)
    dem = Elevation(ROOT/'source'/'3dep_float.tif')
    features = {i.split(':')[-1]: g for g,t,i in read_features('osm_local.geojson.gz') if t['kind']=='building'}
    over = {i:g for g,_,i in read_features('overture_local.geojson.gz')}
    layout = [
        ('StripesSunshine', '+00_-01', (0,-2000), '542325799', '542325801', 'Stripes', (-.57,.82)),
        ('ValeroLoop499', '-02_-02', (-4000,-4000), '498135174', '498135173', 'Valero', (0,-1)),
        ('HarlingenMedicalCenter', '+01_+02', (2000,4000), '545113288',
         '1dc76c4b-9b12-43e3-8ea4-a5ff3627d5c1', None, None),
    ]
    with ZipFile(archive) as original:
        manifest = json.loads(original.read('Harlingen/manifest.json'))
        tiles = {t['id']: t for t in manifest['tiles']}
        catalog = []
        for name, tile, origin, store, roof, brand, heading in layout:
            district = ROOT/'tiles'/tile
            origin = np.array(origin)
            site = Landmark(name, tile, origin, dem)
            polygons = [features[store], features[roof] if brand else over[roof]]
            if brand:
                station(site, *polygons, brand, np.array(heading))
            else:
                hospital(site, *polygons)
            triangles, collision_faces = site.save()
            name_path = f'assets/landmarks/{name}'
            catalog.append(dict(name=name, tile=tile, source_footprints=[store,roof],
                                scene=name_path+'.tscn', mesh=name_path+'.glb',
                                triangles=triangles, collision_faces=collision_faces))
            for layer in ('Buildings','BuildingCollision','BuildingsFar','FacadeDetails'):
                path = district/(layer+'.glb')
                raw = original.read('Harlingen/'+path.relative_to(ROOT).as_posix())
                removed, remaining = replace_shells(path, raw, origin, polygons)
                if layer != 'FacadeDetails':
                    assert removed, (tile, layer)
                if removed:
                    tiles[tile]['layers'][layer]['triangles'] = remaining
                print(tile, layer, 'removed', removed, 'kept', remaining)
            path = district/'district.tscn'
            attach(path, name, original.read('Harlingen/'+path.relative_to(ROOT).as_posix()))
            print(name, triangles, 'visual triangles;', collision_faces, 'collision faces')
        manifest['site_landmarks'] = catalog
        (ROOT/'manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')


if __name__ == '__main__':
    main(sys.argv[1])
