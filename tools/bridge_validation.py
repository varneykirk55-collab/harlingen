"""Measure bridge openings and grade on the exported pavement and collision meshes."""
from collections import defaultdict
import math

import numpy as np
from shapely.geometry import Point, Polygon
from shapely.strtree import STRtree

from bridge_profiles import AUDITED_CROSSINGS, CLEARANCE_TARGET, DECK_DEPTH
from build import ROOT, TILE_SIZE, parts, road_spec
from road_grade import is_bridge
from street_detail import glb_parts


class Pavement:
    def __init__(self, tiles, layers):
        self.polygons = []
        self.planes = []
        self.triangles = []
        for tile in tiles:
            x,z = (int(x)*TILE_SIZE for x in tile.split('_'))
            for layer,materials in layers.items():
                for material,vertices,indices in glb_parts(ROOT/'tiles'/tile/(layer+'.glb')):
                    if material not in materials:
                        continue
                    tri = vertices[indices]+[x,0,z]
                    axis = (tri[:,1]-tri[:,0])[:,[0,2]]
                    cross = (tri[:,2]-tri[:,0])[:,[0,2]]
                    keep = np.abs(axis[:,0]*cross[:,1]-axis[:,1]*cross[:,0])>1.e-7
                    tri = tri[keep]
                    basis = np.concatenate((tri[:,:,[0,2]],np.ones((*tri.shape[:2],1))),axis=2)
                    self.planes.extend(np.linalg.solve(basis,tri[:,:,1,None])[:,:,0])
                    self.polygons.extend(Polygon(t[:,[0,2]]) for t in tri)
                    self.triangles.extend(tri)
        self.index = STRtree(self.polygons)
        self.planes = np.asarray(self.planes)
        self.vertices = np.concatenate(self.triangles)

    def at(self, points, expected):
        from shapely import points as mapped_points
        points = np.asarray(points)
        pids,triangles = self.index.query(mapped_points(points[:,[0,2]]),predicate='intersects')
        heights = np.einsum('ij,ij->i',self.planes[triangles],points[pids][:,[0,2,1]]*[1,1,0]+[0,0,1])
        differences = np.abs(heights-expected[pids])
        order = np.lexsort((differences,pids))
        firsts = np.unique(pids[order],return_index=True)[1]
        found = np.full(len(points),np.nan)
        found[pids[order[firsts]]] = heights[order[firsts]]
        return found


def opening(crossing, surfaces, routes, dem):
    road = crossing.upper
    lower = routes.get(crossing.lower)
    under = surfaces['soffit']
    paving = surfaces['road' if lower is None else 'top']
    extent = crossing.point.buffer(55.).intersection(crossing.line.buffer(road_spec(crossing.tags)[0]/2))
    minimum = (math.inf,None)
    overlap = 0.
    for i in under.index.query(extent,predicate='intersects'):
        triangle = under.polygons[i]
        centroid = triangle.centroid
        station = road.line.project(centroid)
        if (centroid.distance(road.line)>road.width/2+.35 or
            abs(road.height(station)-DECK_DEPTH-under.planes[i]@[centroid.x,centroid.y,1.])>.35):
            continue
        covered = triangle.intersection(extent)
        for j in paving.index.query(covered,predicate='intersects'):
            low = paving.polygons[j]
            common = covered.intersection(low)
            if common.area<1.e-8:
                continue
            cp = common.centroid
            y = float(paving.planes[j]@[cp.x,cp.y,1.])
            target = lower.height(lower.line.project(cp)) if lower else float(dem(cp.x,cp.y))+.078
            if abs(y-target)>.42:
                continue
            overlap += common.area
            gradient = under.planes[i]-paving.planes[j]
            for polygon in parts(common,'Polygon'):
                xz = np.asarray(polygon.exterior.coords)
                clearance = xz@gradient[:2]+gradient[2]
                at = int(np.argmin(clearance))
                if clearance[at]<minimum[0]:
                    x,z = xz[at]
                    minimum = float(clearance[at]),[x,float(paving.planes[j]@[x,z,1.]),z]
    if not np.isfinite(minimum[0]):
        raise ValueError(f'Could not measure exported opening {road.key} / {crossing.lower}')
    x,z = crossing.point.coords[0]
    center = lower.height(crossing.lower_station) if lower else float(dem(x,z))+.078
    # The physics test uses the most restrictive XY position plus the slip-road
    # centerline through the opening, with headings taken from OSM.
    length = crossing.line.length
    lower_points = []
    for station in np.arange(max(.5,crossing.lower_station-22.),min(length-.5,crossing.lower_station+22.),1.):
        p = crossing.line.interpolate(station)
        before = crossing.line.interpolate(station-.45)
        after = crossing.line.interpolate(station+.45)
        lower_points.append([p.x,p.y,after.x-before.x,after.y-before.y])
    return dict(upper_way=road.key,lower_way=crossing.lower,
                before_center_clearance_m=round(crossing.baseline,3),
                center_clearance_m=round(road.height(crossing.station)-DECK_DEPTH-center,3),
                minimum_mesh_clearance_m=round(minimum[0],4),
                minimum_position=[round(float(n),5) for n in minimum[1]],
                measured_overlap_m2=round(overlap,2),
                center=[round(x,5),round(center,5),round(z,5),round(road.height(crossing.station),5)],
                slip_path=[[round(n,5) for n in row] for row in lower_points])


def validate(tiles, roads, checks, dem):
    routes = {r.key:r for r in roads}
    assets = {
        'top': Pavement(tiles,{'ElevatedCollision':{'highway'}}),
        'visual': Pavement(tiles,{'ElevatedRoads':{'highway'}}),
        'soffit': Pavement(tiles,{'ElevatedCollision':{'flyover_girder'}}),
        'soffit_visual': Pavement(tiles,{'ElevatedRoads':{'flyover_girder'}}),
        'road': Pavement(tiles,{'Roads':{'highway','asphalt','service','gravel'}}),
    }
    # Compare each top and soffit as triangle vertex arrays in file order.
    for a,b in (('top','visual'),('soffit','soffit_visual')):
        if not np.array_equal(assets[a].vertices,assets[b].vertices):
            raise ValueError(f'Collision does not match rendered mesh for {a}')
    checks_by_pair = {(c.upper.key,c.lower):c for c in checks}
    clearances = [opening(checks_by_pair[pair],assets,routes,dem) for pair in AUDITED_CROSSINGS]

    profiles = {}
    joins = defaultdict(list)
    for road in roads:
        if not hasattr(road,'corrected_profile'):
            continue
        length = road.line.length
        samples = np.linspace(.06,length-.06,math.ceil(length/.8)+1)
        xyz = np.array([(x,1.,z) for x,z in map(road.center,samples)])
        expected = np.array([road.height(s) for s in samples])
        pavement = assets['top'].at(xyz,expected)
        drift = abs(pavement-expected)
        if not np.isfinite(pavement).all() or max(drift)>.25:
            raise ValueError(f'Exported pavement is missing or misaligned for {road.key}: {max(drift):.3f} m')
        ground = dem(xyz[:,0],xyz[:,2])
        offset = abs(pavement-ground)
        runs = []
        for indices in np.split(np.arange(len(samples)),np.flatnonzero(np.diff(offset>1.))+1):
            if offset[indices[0]]>1.:
                runs.append([round(float(samples[indices[0]]),2),round(float(samples[indices[-1]]),2)])
        for a,b in zip((0.,length),road.corrected_profile[1][[0,-1]]):
            joins[tuple(np.round(road.center(a),3))].append(b)
        bridge = is_bridge(road.tags)
        profiles[road.key] = dict(
            bridge=bridge, maximum_exported_grade_percent=round(float(100*np.max(abs(np.diff(pavement)/np.diff(samples)))),4),
            maximum_exported_ground_offset_m=round(float(np.max(offset)),4),
            maximum_centerline_mesh_error_m=round(float(max(drift)),4),
            approach_extension_station_intervals_m=runs if not bridge else [],
        )
    return dict(
        crossings=clearances,
        minimum_mesh_clearance_m=min(c['minimum_mesh_clearance_m'] for c in clearances),
        below_target=[{'upper_way':c['upper_way'],'lower_way':c['lower_way']}
                      for c in clearances if c['minimum_mesh_clearance_m']<CLEARANCE_TARGET],
        profiles_by_osm_way=profiles,
        maximum_exported_motorway_grade_percent=max(r['maximum_exported_grade_percent'] for r in profiles.values()),
        maximum_shared_node_gap_m=round(max(max(ys)-min(ys) for ys in joins.values()),6),
        shared_nodes_checked=sum(len(ys)>1 for ys in joins.values()),
    )
