"""Apply targeted geometry/data updates to an existing Harlingen project."""
import json

from build import Elevation, ROOT, read_features
from elevated_roads import Road, RouteModel
from mesh import write_glb
from road_grade import is_bridge
from bridge_validation import validate


def correct_highways(manifest, source, dem):
    info = manifest['elevated_highway']
    selected = set(info['upgraded_osm_ways'])
    roads = [Road(i,g,t,dem) for g,t,i in source if t['kind']=='road' and i in selected]
    if {r.key for r in roads} != selected:
        raise ValueError('Highway inventory no longer matches the OSM source')
    model = RouteModel(roads, source, dem)

    checks,deficits = model.fit_motorway(source)
    motorway = [road for road in roads if hasattr(road,'corrected_profile')]
    bridge_count = sum(is_bridge(road.tags) for road in roads)
    ground_count = len(roads)-bridge_count
    if (ground_count,bridge_count) != (57,27):
        raise ValueError(f'Expected 57 ground roads and 27 bridges, found {ground_count} and {bridge_count}')
    for road in motorway:
        model.model(road)

    tiles = {r['id']:r for r in manifest['tiles']}
    highway_tiles = []
    for (ix,iz), geometry in sorted(model.tiles.items()):
        tile = f'{ix:+03d}_{iz:+03d}'
        highway_tiles.append(tile)
        for name,mesh in geometry.items():
            path = ROOT/'tiles'/tile/f'{name}.glb'
            if not write_glb(path,name,mesh):
                raise ValueError(f'Expected populated highway asset {path}')
            layers[name]['triangles'] = mesh.triangles()

    info['bridge_clearance'] = validate(highway_tiles,roads,checks,dem)
    report = info['bridge_clearance']
    report['modeled_clearance_shortfalls'] = [
        {'upper_way':upper,'lower_way':lower,'deficit_to_design_m':gap}
        for upper,lower,gap in deficits
    ]
    report['exported_tiles'] = highway_tiles
    report['motorway_pier_columns'] = model.support_count
    print(f'{ground_count} non-bridge ways, {bridge_count} tagged bridges retained. '
          f'Exported minimum clearance {report["minimum_mesh_clearance_m"]:.3f} m. '
          f'Exported maximum motorway grade {report["maximum_exported_motorway_grade_percent"]:.3f}%. '
          f'Crossings below target: {len(report["below_target"])}.')


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
