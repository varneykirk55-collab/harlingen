"""Clip the public source data to the Harlingen working extent."""
import collections
import gzip
import json
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

import numpy as np
from pyproj import Transformer
from shapely import force_2d, make_valid
from shapely.geometry import LineString, Point, Polygon, box, mapping, shape
from shapely.ops import polygonize, transform, unary_union

ROOT = Path(__file__).resolve().parents[1]
ORIGIN = (630000,2898000)
WORLD = box(-6000,-6000,6000,6000)
PROJECT = Transformer.from_crs(4326,32614,always_xy=True)
AREAS = {'parking','park','garden','golf_course','pitch','recreation_ground','sports_centre',
         'playground','nature_reserve','cemetery','forest','farmland','farmland','orchard','grass',
         'meadow','grassland','wood','scrub','water','wetland','basin','reservoir','retention_pond',
         'aerodrome','apron','pedestrian','platform'}
ROADS = {'motorway','trunk','primary','secondary','tertiary','unclassified','residential',
         'living_street','service','track','pedestrian','path','footway','cycleway',
         'motorway_link','trunk_link','primary_link','secondary_link','tertiary_link','steps','crossing'}
TAGS = {'highway','building','material','building:material','building:levels','roof:shape','height',
        'name','sidewalk','lanes','surface','oneway','width','bridge','tunnel','layer','natural',
        'leaf_type','waterway','water','leisure','landuse','amenity','aeroway','railway','power',
        'man_made','tourism','historic','shop','area','sport','parking','crossing','location','ref'}


def project(x,y,z=None):
    e,n = PROJECT.transform(x,y)
    return np.asarray(e)-ORIGIN[0],ORIGIN[1]-np.asarray(n)


def category(tags, area):
    if area:
        if tags.get('building','no') != 'no':
            return 'building'
        if any(v in AREAS for k,v in tags.items() if k in ('natural','landuse','leisure','amenity','aeroway','water','highway','railway')):
            return 'land'
        if tags.get('waterway') == 'riverbank':
            return 'land'
    elif tags.get('highway') in ROADS and tags.get('area') != 'yes':
        return 'road'
    elif tags.get('waterway') in ('river','stream','canal','ditch','drain') and tags.get('tunnel') not in ('yes','culvert'):
        return 'channel'
    elif tags.get('aeroway') in ('runway','taxiway'):
        return 'airstrip'
    elif tags.get('railway') in ('rail','light_rail') and tags.get('tunnel') != 'yes':
        return 'rail'
    return None


def load_osm(work):
    nodes, ways, relations, tagged = {}, {}, {}, {}
    paths = sorted(work.glob('osm_*.xml'))
    if len(paths) != 36:
        raise ValueError(f'Expected 36 overlapping OSM source requests, have {len(paths)}')
    for file in paths:
        for elem in ET.parse(file).getroot():
            if elem.tag not in ('node','way','relation'):
                continue
            ident=int(elem.get('id'))
            tags={e.get('k'):e.get('v') for e in elem.findall('tag') if e.get('k') in TAGS or e.get('k')=='type'}
            if elem.tag=='node':
                nodes[ident]=(float(elem.get('lon')),float(elem.get('lat')))
                if tags:
                    tagged[ident]=tags
            elif elem.tag=='way':
                ways[ident]=([int(e.get('ref')) for e in elem.findall('nd')],tags)
            else:
                relations[ident]=([(int(e.get('ref')),e.get('role')) for e in elem.findall('member') if e.get('type')=='way'],tags)
    coords=np.array(list(nodes.values()))
    x,z=project(coords[:,0],coords[:,1])
    nodes=dict(zip(nodes,zip(x,z)))
    rows=[]
    def save(geom, source_id, tags, kind):
        if kind and geom is not None and not geom.is_empty and geom.intersects(WORLD):
            # Keep whole building footprints so tile ownership never cuts a building in two.
            clipped = geom if kind=='building' else geom.intersection(WORLD)
            if not clipped.is_empty:
                rows.append(dict(type='Feature',id=source_id,geometry=mapping(clipped),
                                 properties={'kind':kind,**tags}))
    def way_coords(ident):
        refs=ways.get(ident, ([],{}))[0]
        return [nodes[n] for n in refs] if all(n in nodes for n in refs) else []
    consumed=set()
    for ident,(members,tags) in relations.items():
        kind=category(tags,True)
        if not kind or tags.get('type')!='multipolygon':
            continue
        loops=collections.defaultdict(list)
        for wid,role in members:
            coords=way_coords(wid)
            if role in ('outer','inner','') and len(coords)>1:
                loops[role or 'outer'].append(LineString(coords))
        outer=unary_union(list(polygonize(loops['outer'])))
        if not outer.is_empty:
            inner=unary_union(list(polygonize(loops['inner'])))
            save(outer.difference(inner),f'osm:relation:{ident}',tags,kind)
            consumed.update(wid for wid,role in members if role!='inner')
    for ident,(refs,tags) in ways.items():
        if len(refs)<2 or not tags:
            continue
        loop=len(refs)>3 and refs[0]==refs[-1]
        area_kind=category(tags,True) if loop and ident not in consumed else None
        kind=area_kind or category(tags,False)
        if not kind:
            continue
        coords=way_coords(ident)
        if coords:
            geom=make_valid(Polygon(coords)) if area_kind else LineString(coords)
            save(geom,f'osm:way:{ident}',tags,kind)
    for ident,tags in tagged.items():
        useful=(tags.get('highway') in ('traffic_signals','crossing','street_lamp','stop') or
                tags.get('power') in ('pole','tower') or tags.get('natural')=='tree' or
                tags.get('amenity')=='bench')
        poi=tags.get('name') and (tags.get('tourism') in ('museum','attraction','artwork') or
            tags.get('historic') or tags.get('amenity') in ('townhall','library','community_centre','theatre','arts_centre'))
        if useful or poi:
            save(Point(nodes[ident]),f'osm:node:{ident}',tags,'prop' if useful else 'poi')
    return rows


def main(work):
    rows=load_osm(work)
    path=ROOT/'source'/'osm_local.geojson.gz'
    with gzip.open(path,'wt') as f:
        json.dump({'type':'FeatureCollection','name':'Harlingen local metres X east, Z south',
                   'features':rows},f,separators=(',',':'))
    print('OSM',collections.Counter(f['properties']['kind'] for f in rows))
    print('Named references:',[(f['properties']['kind'],f['properties']['name']) for f in rows
        if 'name' in f['properties'] and (f['properties']['kind']=='poi' or
        f['properties'].get('leisure')=='park' or f['properties'].get('aeroway')=='aerodrome')])
    footprint_file=work/'overture.geojsonseq'
    if not footprint_file.exists():
        return
    buildings=[]
    for line in footprint_file.open():
        f=json.loads(line.strip().lstrip('\x1e'))
        p=f['properties']
        geom=make_valid(transform(project,force_2d(shape(f['geometry']))))
        if geom.intersects(WORLD):
            tags={k:p[k] for k in ('height','subtype','class','num_floors','sources','roof_shape','name') if p.get(k) is not None}
            buildings.append(dict(type='Feature',id=f.get('id') or p['id'],properties=tags,geometry=mapping(geom)))
    if buildings:
        with gzip.open(ROOT/'source'/'overture_local.geojson.gz','wt') as f:
            json.dump(dict(type='FeatureCollection',features=buildings),f,separators=(',',':'))
    print('Overture footprints',len(buildings))


if __name__=='__main__':
    main(Path(sys.argv[1]))
