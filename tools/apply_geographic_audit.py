"""Apply targeted geometry/data updates to an existing Harlingen project."""
import json

import numpy as np
from shapely.geometry import Point

from build import Elevation, ROOT, TILE_SIZE, read_features
from elevated_roads import PARK_ROAD, PARK_WALK, Road, RouteModel
from mesh import write_glb
from road_grade import is_bridge
from street_detail import Surface, glb_parts


def correct_highways(manifest, source, dem):
    info = manifest['elevated_highway']
    selected = set(info['upgraded_osm_ways'])
    roads = [Road(i,g,t,dem) for g,t,i in source if t['kind']=='road' and i in selected]
    if {r.key for r in roads} != selected:
        raise ValueError('Highway inventory no longer matches the OSM source')
    model = RouteModel(roads, source, dem)

    report = {}
    for road in roads:
        points = np.linspace(0., road.line.length, max(2,int(road.line.length/2.5)+1))
        base = np.asarray([dem(*road.center(s)) for s in points])
        legacy = np.asarray([road.legacy_height(s) for s in points])
        fixed = np.asarray([road.height(s) for s in points])
        report[road.key] = dict(bridge=is_bridge(road.tags),layer=road.tags.get('layer'),
            profile_before_m=round(float(np.max(abs(legacy-base))),4),
            profile_after_m=round(float(np.max(abs(fixed-base))),4),
            maximum_sampled_grade_percent=round(float(100*np.max(abs(np.diff(fixed)/np.diff(points)))),1))
        model.model(road)
    ground = [i for i,r in report.items() if not r['bridge']]
    if len(ground) != 57:
        raise ValueError(f'Expected the audited 57 non-bridge ways, found {len(ground)}')
    info['pier_columns'] = model.support_count
    info['audit_at_grade_ways'] = ground
    info['audit_way_profiles'] = report

    tiles = {r['id']:r for r in manifest['tiles']}
    for (ix,iz), geometry in sorted(model.tiles.items()):
        tile = f'{ix:+03d}_{iz:+03d}'
        folder = ROOT/'tiles'/tile
        for name,mesh in geometry.items():
            path = folder/f'{name}.glb'
            # The Ramsey path is part of the existing visual layer. Transfer it
            # intact without touching the park scene or its asset.
            if tile == '+01_+00' and name=='ElevatedRoads':
                for mat,coords,indices in glb_parts(path):
                    if mat == 'flyover_trail':
                        mesh.add(mat,coords,indices.ravel(),normals=[(0,1,0)]*len(coords))
            if not write_glb(path,name,mesh):
                raise ValueError(f'Expected populated highway asset {path}')
            tiles[tile]['layers'][name]['triangles'] = mesh.triangles()
    del model

    rendered = {}
    for tile in info['tiles']:
        rendered[tile] = Surface(ROOT/'tiles'/tile/'ElevatedCollision.glb',
                                  ignored=('flyover_concrete','flyover_rail','flyover_walk'))
    for road in roads:
        if is_bridge(road.tags):
            continue
        maximum = 0.
        for s in np.linspace(0.08,road.line.length-.08,max(2,int(road.line.length/2.5)+1)):
            x,z = road.center(s)
            ix,iz = np.floor(np.array([x,z])/TILE_SIZE).astype(int)
            found = []
            for tx,tz in ((ix,iz),(ix-1,iz),(ix+1,iz),(ix,iz-1),(ix,iz+1)):
                surface = rendered.get(f'{tx:+03d}_{tz:+03d}')
                if surface is None:
                    continue
                p = np.array([x-tx*TILE_SIZE,z-tz*TILE_SIZE])
                ids = surface.index.query(Point(p),predicate='intersects')
                if len(ids):
                    # Where decks overlap, measure the height closest to this way's
                    # local profile rather than attributing a separate bridge to it.
                    for verts in surface.tri[ids]:
                        v = verts[:,[0,2]]
                        basis = np.column_stack((v[1]-v[0],v[2]-v[0]))
                        u,w = np.linalg.solve(basis, p-v[0])
                        found.append(verts[0,1]+u*(verts[1,1]-verts[0,1])+w*(verts[2,1]-verts[0,1]))
                if len(found):
                    break
            if not found:
                raise ValueError(f'No exported road collision for {road.key} at {x,z}')
            base = float(dem(x,z))
            maximum = max(maximum, min(abs(y-base) for y in found))
        report[road.key]['collision_after_m'] = round(maximum,4)
        if maximum > 1.0:
            raise ValueError(f'{road.key} exceeds the one metre tolerance ({maximum:.3f})')
    print(f'{len(ground)} corrected ways, {len(roads)-len(ground)} tagged bridges retained; '
          f'maximum exported at-grade deviation {max(report[i]["collision_after_m"] for i in ground):.3f} m')


def main():
    path = ROOT/'manifest.json'
    manifest = json.loads(path.read_text())
    from argparse import ArgumentParser

    parser=ArgumentParser(description=__doc__)
    parser.add_argument('--highway-only',action='store_true')
    parser.add_argument('--sites-and-airport-only',action='store_true')
    options=parser.parse_args()
    original=read_features('osm_local.geojson.gz')
    source=[(g,t,i.split(':')[-1]) for g,t,i in original]
    dem=Elevation(ROOT/'source'/'3dep_float.tif')
    if not options.sites_and_airport_only:
        correct_highways(manifest,source,dem)
    if not options.highway_only:
        from airport_correction import patch_airport
        from geographic_sites import (attach_sites, corrected_features, district_register,
                                      landmark_index, labels_by_tile, site_rows, write_tile_sites)
        from iwo_jima import build_memorial

        sites=site_rows()
        if not sites:
            raise ValueError('Geographic landmark sources are required')
        build_memorial(ROOT/'assets'/'landmarks'/'IwoJimaMemorial.glb')
        entries=landmark_index(sites)
        keys={row['source'] for row in entries}
        manifest['landmarks']=[r for r in manifest['landmarks'] if r['source'] not in keys]+entries
        manifest['geographic_districts']=district_register()
        manifest['geographic_sites']='source/geographic_sites.geojson'
        for tile,locations in labels_by_tile(sites).items():
            folder=ROOT/'tiles'/tile
            write_tile_sites(folder,locations,dem)
            attach_sites(folder)
        patch_airport(manifest,original,corrected_features(original),dem)
    path.write_text(json.dumps(manifest,indent=2)+'\n')


if __name__=='__main__':
    main()
