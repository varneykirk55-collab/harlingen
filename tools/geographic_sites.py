"""Authoritative locations, municipal boundaries and FAA pavement endpoints."""
from collections import defaultdict
import gzip
import json
import math
from pathlib import Path

from shapely.geometry import LineString, shape

from extract import project

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT/'source'
SITE_AMENITIES = frozenset({'hospital','school','college','university'})


def site_rows():
    path = SOURCE/'geographic_sites.geojson'
    if not path.exists():
        return []
    document = json.loads(path.read_text())
    return [(shape(f['geometry']),f['properties'],f['id']) for f in document['features']]


def runway_register():
    path = SOURCE/'faa_hrl_runway_ends.json'
    return json.loads(path.read_text()) if path.exists() else {'runways':{}}


def corrected_features(rows):
    runways = runway_register()['runways']
    authoritative = site_rows()
    identities = {identity for _,_,identity in authoritative}
    found = set()
    corrected = []
    for geom,tags,identity in rows:
        if identity in identities:
            continue
        ref = tags.get('ref')
        if tags.get('aeroway')=='runway' and ref in runways:
            ends = runways[ref]
            geom = LineString([project(end['lon'],end['lat']) for end in ends])
            tags = {**tags,'width':'45.72'}
            found.add(ref)
        corrected.append((geom,tags,identity))
    if found != set(runways):
        raise ValueError(f'FAA runway matches are incomplete: {set(runways)-found}')
    return corrected+authoritative


def district_register():
    path = SOURCE/'geographic_districts.geojson.gz'
    if not path.exists():
        return {}
    with gzip.open(path,'rt') as stream:
        data = json.load(stream)
    rows = data['features']
    metro = next(row for row in rows if row['id']=='downtown-overlay')
    polygon = shape(metro['geometry'])
    return dict(file='source/'+path.name, municipality='City of Harlingen, January 2025',
                planning_zones=sum(row['properties']['kind']=='zoning_district' for row in rows),
                source_zoning_features=data['source_total_polygons'],
                downtown_overlay={
                    'id':metro['id'],'name':metro['properties']['name'],
                    'source':metro['properties']['source'],'bounds_m':list(polygon.bounds),
                    'area_m2':round(polygon.area,2),'vertices':len(polygon.exterior.coords)-1})


def label_position(geom,tags):
    if 'label' in tags:
        x,z = tags['label']
    else:
        p = geom.representative_point()
        x,z = p.x,p.y
    return x,z


def landmark_index(rows):
    entries = []
    for geom,tags,ident in rows:
        if tags.get('kind') not in ('site','poi') or not tags.get('name'):
            continue
        if tags.get('kind')=='poi' and ident!='thc:iwo-jima' and tags.get('historic') not in ('monument','memorial'):
            continue
        x,z = label_position(geom,tags)
        entries.append(dict(name=tags['name'],layer=tags['kind'],source=ident,x=round(x,4),z=round(z,4),
                            easting=round(630000+x,4),northing=round(2898000-z,4)))
    return entries


def labels_by_tile(rows):
    tiles = defaultdict(list)
    for geom,tags,identity in rows:
        x,z = label_position(geom,tags)
        ix,iz = math.floor(x/2000),math.floor(z/2000)
        tiles[f'{ix:+03d}_{iz:+03d}'].append((x,z,tags['name'],identity))
    return tiles


def write_tile_sites(folder, records, dem):
    if not records:
        return
    tile = folder.name
    ix,iz = (int(part) for part in tile.split('_'))
    has_memorial = any(row[3]=='thc:iwo-jima' for row in records)
    result = ['[gd_scene format=3]','']
    if has_memorial:
        result.extend(['[ext_resource type="PackedScene" path="res://assets/landmarks/IwoJimaMemorial.glb" id="1"]',''])
    result.append('[node name="GeographicSites" type="Node3D"]')
    for index,(x,z,name,identity) in enumerate(records):
        lx,lz = x-ix*2000,z-iz*2000
        y = float(dem(x,z))
        result.extend(['',f'[node name="Site{index}" type="Node3D" parent="."]',
                       f'position = Vector3({lx:.6f}, {y:.6f}, {lz:.6f})',
                       f'metadata/geographic_source = {json.dumps(identity)}',
                       '',f'[node name="MapLabel" type="Label3D" parent="Site{index}"]',
                       'position = Vector3(0, 16, 0)' if identity!='thc:iwo-jima' else 'position = Vector3(0, 14.8, 0)',
                       'billboard = 1','visibility_range_end = 690.0','pixel_size = 0.028','font_size = 46',
                       'outline_size = 10',f'text = {json.dumps(name,ensure_ascii=False)}'])
        if identity=='thc:iwo-jima':
            result.extend(['',f'[node name="IwoJimaMemorial" parent="Site{index}" instance=ExtResource("1")]',
                           '',f'[node name="PedestalCollision" type="StaticBody3D" parent="Site{index}"]'])
    # A primitive plinth collider keeps the campus traversable.
    if has_memorial:
        result[2:2]=['[sub_resource type="BoxShape3D" id="Box_plinth"]','size = Vector3(16.8, 3.28, 11.4)','']
        # Godot requires external resources before sub-resources.
        external = next(i for i,line in enumerate(result) if line.startswith('[ext_resource'))
        result.insert(2,result.pop(external))
        index = next(index for index,row in enumerate(records) if row[3]=='thc:iwo-jima')
        result.extend(['',f'[node name="Shape" type="CollisionShape3D" parent="Site{index}/PedestalCollision"]',
                       'position = Vector3(0, 1.41, 0)','shape = SubResource("Box_plinth")'])
    (folder/'GeographicSites.tscn').write_text('\n'.join(result)+'\n')


def attach_sites(folder):
    scene = folder/'district.tscn'
    old = scene.read_text()
    if 'GeographicSites.tscn' in old:
        return
    at = old.index('[node')
    resource = f'[ext_resource type="PackedScene" path="res://tiles/{folder.name}/GeographicSites.tscn" id="geographic_sites"]'
    node = '[node name="GeographicSites" parent="." instance=ExtResource("geographic_sites")]'
    scene.write_text(old[:at]+resource+'\n\n'+old[at:].rstrip()+'\n\n'+node+'\n')
