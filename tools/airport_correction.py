"""Patch runway pavement and centerline markings without rebuilding city tiles."""
import numpy as np
from shapely import intersects_xy
from shapely.geometry import LineString, Point, box
from shapely.ops import unary_union
from shapely.strtree import STRtree

from build import ROOT, TILE_SIZE, parts, patch, tagged_number
from geographic_sites import runway_register
from mesh import Mesh, write_glb
from street_detail import Surface, glb_parts


def runway_strips(line,bounds):
    for station in np.arange(110,line.length-50,62):
        a,b=line.interpolate(station),line.interpolate(station+24)
        yield LineString([a,b]).buffer(.47,cap_style='flat').intersection(bounds)


def patch_airport(manifest,original,corrected,dem):
    register = runway_register()
    refs = set(register['runways'])
    old = {t['ref']:g for g,t,_ in original if t.get('aeroway')=='runway' and t.get('ref') in refs}
    new = {t['ref']:g for g,t,_ in corrected if t.get('aeroway')=='runway' and t.get('ref') in refs}
    if set(old)!=refs or set(new)!=refs:
        raise ValueError('Unexpected runway inventory at HRL')
    transport = [(g,t) for g,t,_ in corrected if t['kind'] in ('airstrip','rail')]
    tree = STRtree([g for g,_ in transport])
    affected=unary_union([line.buffer(24.) for line in (*old.values(),*new.values())])
    exported = {}
    changed=[]
    for tile in manifest['tiles']:
        x,z = tile['x'],tile['z']
        bounds = box(x,z,x+TILE_SIZE,z+TILE_SIZE)
        if not bounds.intersects(affected):
            continue
        folder=ROOT/'tiles'/tile['id']
        new_mesh=Mesh()
        around=bounds.buffer(28,join_style='mitre')
        for j in tree.query(around,predicate='intersects'):
            geom,tags=transport[j]
            is_airstrip=tags['kind']=='airstrip'
            width=tagged_number(tags.get('width')) or (45 if tags.get('aeroway')=='runway' else 19 if is_airstrip else 2.7)
            surface=geom.buffer(width*.5,cap_style='flat').intersection(bounds)
            patch(new_mesh,surface,'runway' if is_airstrip else 'rail',lambda a,b:dem(a,b)+.097,x,z,8)
            if not is_airstrip:
                for side in (-1,1):
                    for line in parts(geom,'LineString'):
                        stripe=line.offset_curve(side*.72).buffer(.045).intersection(bounds)
                        patch(new_mesh,stripe,'steel',lambda a,b:dem(a,b)+.155,x,z,9)
        path=folder/'Transport.glb'
        write_glb(path,'Transport',new_mesh)
        exported[tile['id']]=Surface(path,ignored=('rail','steel'))
        tile['layers']['Transport']['triangles']=new_mesh.triangles()

        previous_stripes=unary_union([poly for line in (*old.values(),*new.values()) for poly in runway_strips(line,bounds)]).buffer(.015)
        markings=Mesh()
        marking_path=folder/'Markings.glb'
        for material,coords,faces in glb_parts(marking_path):
            if material=='white' and not previous_stripes.is_empty:
                middles=coords[faces][:,:,[0,2]].mean(axis=1)+[x,z]
                faces=faces[~intersects_xy(previous_stripes,*middles.T)]
            if faces.size:
                used,indices=np.unique(faces.ravel(),return_inverse=True)
                markings.add(material,coords[used],indices,normals=[(0,1,0)]*len(used))
        for line in new.values():
            for stripe in runway_strips(line,bounds):
                patch(markings,stripe,'white',lambda a,b:dem(a,b)+.14,x,z)
        if write_glb(marking_path,'Markings',markings):
            tile['layers']['Markings']['triangles']=markings.triangles()
        changed.append(tile['id'])

    report={}
    for ref,line in sorted(new.items()):
        before=[]
        after=[]
        for i,point in enumerate(line.coords):
            p=Point(point)
            before.append(round(min(p.distance(Point(v)) for v in (old[ref].coords[0],old[ref].coords[-1])),4))
            ix,iz=np.floor(np.array(point)/TILE_SIZE).astype(int)
            tile=f'{ix:+03d}_{iz:+03d}'
            local=np.asarray(point)-[ix*TILE_SIZE,iz*TILE_SIZE]
            surface=exported[tile]
            near=surface.index.nearest(Point(local))
            distance=surface.polygons[near].distance(Point(local))
            if distance>.012:
                raise ValueError(f'FAA endpoint not covered by exported pavement: {ref} {i} {distance}')
            after.append(round(distance,6))
        report[ref]=dict(before_end_offset_m=before,after_end_offset_to_mesh_m=after,
                         endpoints_local_m=[list(x) for x in line.coords],
                         length_m=round(line.length,3))
    manifest['airport_geography']=dict(source='source/faa_hrl_runway_ends.json',eff_date=register['eff_date'],
                                     affected_tiles=changed,runways=report)
    print('FAA runway ends (before → after)',{r:(v['before_end_offset_m'],v['after_end_offset_to_mesh_m']) for r,v in report.items()})
