"""Upgrade mapped Harlingen expressways and the Ramsey crossings as streamed meshes."""
from collections import defaultdict
from dataclasses import dataclass
import heapq
import json
import math
import random
from zipfile import ZipFile

import numpy as np
from shapely.geometry import LineString, Point, Polygon, box
from shapely.ops import unary_union
from shapely.strtree import STRtree

from build import Elevation, ROOT, TILE_SIZE, VEHICLE, parts, patch, read_features, road_spec
from landmarks import Frame, Landmark
from mesh import Mesh, PALETTE, cylinder, write_glb
from vegetation import scrub
from road_grade import ground_grade, is_bridge, smoothstep, surface_grade
from bridge_profiles import DECK_DEPTH, fit_profiles

MAIN = '''
1061023301 119748890 119748783 119749039 1105186743 143948211 97347898
97347971 97347987 97348043 25694477 1158711692 25691779 97347991
97347912 97347916 97347974 97348000 1157923171 97347848 97347952
97347887 118182291 1183883591 97347880 97348021 97347876 97347894
97347864 97348004 97347948 97347955
'''.split()
WEST = '''
97347860 97348008 97348017 97348030 97348038 895045658 895077914
895077916 895077924 895098576 1157858355
97348027 895045659 25838827 97347879 895155548 895045664 895045663
895045665 97347932 1459656357 1459656358 97347856 895077923
28660581 97347944
'''.split()
MAIN_GRADES = [
    (-303,0),(-175,0),(-18,18.65),(117,18.6),(350,18.6),(650,19.10),
    (795,19.20),(1000,18.65),(1400,18.70),(1530,19.10),(1795,19.05),
    (2230,18.6),(2470,19.05),(2560,18.6),(2780,0),(3050,0),
]
WEST_GRADES = [
    (-3530,0),(-3500,0),(-3320,19.8),(-3100,20.15),(-2930,19.25),
    (-2700,18.4),(-2485,19.6),(-2335,20),(-2130,20.2),
]
# Measured station distances along each way, elevations in world meters.
FLYOVERS = {
    '97348013': [(0,20),(138,26.8),(540,27),(700,27),(940,22),(1090,19)],
    '119748869': [(0,18.9),(400,19.85),(690,19.85),(945,20),(977,20)],
    '97347978': [(0,21.5),(65,25.85),(185,26.05),(330,23),(530,20.15)],
    '97348034': [(0,20.08),(210,20.6),(420,20.3),(498,20.8)],
}
# Existing ramps and slip roads retain an at-grade connection at the surface end.
# None means use the source terrain at that endpoint.
CONNECTORS = {
    '20751842': (None,18.9), '119748941': (19,None),
    '28933409': (None,18.6), '119748931': (18.6,None),
    '20754951': (18.67,None), '27567572': (None,18.66),
    '20775588': (19.20,21.5), '97347928': (20.8,18.70),
    '894782355': (18.68,19.20), '894782356': (18.70,18.69),
    '894782357': (18.69,18.68), '895045660': (18.70,18.70),
    '97347872': (19.05,None), '28571061': (None,19.03),
    '119748917': (19.04,None), '28933381': (None,19.05),
    '119748708': (None,18.62), '119748710': (18.64,None),
    '28660561': (None,'west'), '97348009': ('west',None),
}
PARK_ROAD = '567766739'
PARK_WALK = '653171983'
PALETTE.update({
    'flyover_concrete': (.64,.61,.55), 'flyover_girder': (.51,.50,.46),
    'flyover_rail': (.55,.58,.58), 'flyover_walk': (.66,.62,.55),
    'flyover_trail': (.59,.50,.37), 'flyover_wood': (.44,.30,.19),
    'flyover_park_sign': (.20,.31,.22), 'flyover_white': (.92,.90,.82),
    'flyover_yellow': (.93,.71,.20),
    'ramsey_foliage': (.32,.43,.25),
    'ramsey_leaf_tips': (.39,.47,.27),
})
MODE = {'flyover_concrete':'plaza_concrete', 'flyover_girder':'plaza_concrete',
        'highway':'highway_asphalt', 'flyover_rail':'painted_utility_steel',
        'flyover_walk':'sidewalk_concrete'}


def grade(dem, point):
    return float(ground_grade(dem, *point))


def eased(x, keys, ground):
    """Smooth between profile controls, retaining source grade at tie-ins."""
    i = max(0, min(len(keys)-2, int(np.searchsorted([k[0] for k in keys],x))-1))
    x0,y0 = keys[i]
    x1,y1 = keys[i+1]
    t = float(np.clip((x-x0)/(x1-x0),0,1))
    blend = t*t*(3-2*t)
    return (y0 or ground)*(1-blend)+(y1 or ground)*blend


@dataclass
class Road:
    key: str
    line: LineString
    tags: dict
    dem: Elevation

    @property
    def width(self):
        return max(2.3, road_spec(self.tags)[0]) if self.key == PARK_WALK else road_spec(self.tags)[0]

    @property
    def lanes(self):
        return int(self.tags.get('lanes', '1'))

    def legacy_height(self, station, p=None):
        if p is None:
            p = self.line.interpolate(station).coords[0]
        g = grade(self.dem,p)
        if self.key in MAIN:
            return eased(p[1], MAIN_GRADES, g)
        if self.key in WEST:
            return eased(p[0], WEST_GRADES, g)
        if self.key in FLYOVERS:
            return eased(station, FLYOVERS[self.key], g)
        if self.key in CONNECTORS:
            a,b = [eased(self.line.coords[i][0],WEST_GRADES,g) if value=='west' else value
                   for value,i in zip(CONNECTORS[self.key],(0,-1))]
            return eased(station,[(0,a),(self.line.length,b)],g)
        step = .124 if self.key==PARK_WALK else 0
        a = grade(self.dem,self.line.coords[0])+step
        b = grade(self.dem,self.line.coords[-1])+step
        middle = 11.75 if self.key == PARK_ROAD else 10.25
        length = self.line.length
        return eased(station,[(0,a),(length*.26,middle),(length*.67,middle),(length,b)],g)

    def height(self, station, p=None):
        if hasattr(self, 'corrected_profile'):
            return float(np.interp(station,*self.corrected_profile))
        if p is None:
            p = self.line.interpolate(station).coords[0]
        if not is_bridge(self.tags):
            base = surface_grade(self.dem, self.line, station, p)
            distances = getattr(self, 'approach_distances', (math.inf, math.inf))
            distance = min(station+distances[0], self.line.length-station+distances[1])
            base = max(base, grade(self.dem,p) + .69*(1-smoothstep(distance/72.)))
            return base
        if hasattr(self, 'bridge_profile'):
            stations, heights = self.bridge_profile
            return float(np.interp(station,stations,heights))
        length = self.line.length
        result = self.legacy_height(station, p)
        joins = getattr(self, 'joins', ())
        for endpoint, target, distance in joins:
            # Interior decks retain their design elevations. Approach ends meet at-grade
            # routes or other bridge pieces at a single shared node elevation.
            normalized = (station if endpoint == 0 else length-station)/distance
            end_point = self.line.coords[0 if endpoint == 0 else -1]
            end = grade(self.dem, end_point) if target is None else target
            if normalized < 1:
                result = end + smoothstep(normalized)*(result-end)
        if joins:
            upper = []
            lower = []
            for endpoint, target, _ in joins:
                distance = station if endpoint==0 else length-station
                upper.append(target + .115*distance)
                lower.append(target - .115*distance)
            result = max(max(lower), min(min(upper), result))
        if joins and station<=.001:
            return next(target for end,target,_ in joins if end==0)
        if joins and length-station<=.001:
            return next(target for end,target,_ in joins if end!=0)
        return result

    def center(self, station):
        return np.asarray(self.line.interpolate(station).coords[0])


def upward(mesh, material, vertices, facing):
    vertices = np.asarray(vertices)
    advance = np.cross(vertices[1]-vertices[0], vertices[2]-vertices[0])
    if np.dot(advance, facing) < 0:
        vertices = vertices[::-1]
    mesh.quad(material, vertices)


def run_key(p):
    return tuple(np.floor(np.asarray(p)/TILE_SIZE).astype(int))


class RouteModel:
    def __init__(self, roads, source, dem):
        self.roads = roads
        self.dem = dem
        self.tiles = defaultdict(lambda: defaultdict(Mesh))
        self.route_shapes = [r.line.buffer(r.width/2+.38) for r in roads]
        self.route_index = STRtree(self.route_shapes)
        self.obstacles = []
        route_ids = {r.key for r in roads}
        for geom,t,key in source:
            if t['kind']=='road' and key not in route_ids and t.get('highway') in VEHICLE:
                self.obstacles.append(geom.buffer(road_spec(t)[0]/2+1.1))
            if t['kind']=='building' or t['kind']=='channel':
                self.obstacles.append(geom.buffer(1.6))
        self.obstacle_index = STRtree(self.obstacles)
        self.endpoint_dirs = defaultdict(list)
        for r in roads:
            v = np.asarray(r.line.coords)
            for q, v0 in [(v[0],v[1]-v[0]),(v[-1],v[-2]-v[-1])]:
                self.endpoint_dirs[tuple(q)].append(v0/np.linalg.norm(v0))
        self.configure_joins()
        self.protect_crossing_clearance(source)
        self.support_count = 0

    def configure_joins(self):
        nodes = defaultdict(list)
        graph = defaultdict(list)
        ground_graph = defaultdict(list)
        for road in self.roads:
            road.joins = []
            road.approach_distances = (math.inf, math.inf)
            ends = [tuple(np.round(position, 3)) for position in (road.line.coords[0],road.line.coords[-1])]
            for end, key in enumerate(ends):
                nodes[key].append((road,end))
            a,b = ends
            if is_bridge(road.tags):
                graph[a].append((b,road.line.length*.115))
                graph[b].append((a,road.line.length*.115))
            else:
                ground_graph[a].append((b,road.line.length))
                ground_graph[b].append((a,road.line.length))

        targets = {}
        fixed_approaches = set()
        for key in graph:
            refs = nodes[key]
            bridges = [(road,end) for road,end in refs if is_bridge(road.tags)]
            approaches = [(road,end) for road,end in refs if not is_bridge(road.tags)]
            if approaches:
                fixed_approaches.add(key)
                targets[key] = grade(self.dem,key)+.69

            elif len(bridges)==1:
                targets[key] = grade(self.dem,key)
            else:
                targets[key] = sum(road.legacy_height(end*road.line.length)
                                   for road,end in bridges)/len(bridges)

        ground_distances = {key:0. for key in fixed_approaches}
        pending = [(0.,key) for key in fixed_approaches]
        heapq.heapify(pending)
        while pending:
            distance,key = heapq.heappop(pending)
            if distance != ground_distances[key]:
                continue
            for neighbor,length in ground_graph[key]:
                total = distance+length
                if total<72. and total<ground_distances.get(neighbor, math.inf):
                    ground_distances[neighbor] = total
                    heapq.heappush(pending,(total,neighbor))
        for road in self.roads:
            if not is_bridge(road.tags):
                road.approach_distances = tuple(ground_distances.get(tuple(np.round(p,3)),math.inf)
                                                for p in (road.line.coords[0],road.line.coords[-1]))

        # Limit adjacent bridge ends as a connected system, including very short
        # pieces that would otherwise create an abrupt ramp at a shared node.
        pending = [(height,key) for key,height in targets.items()]
        heapq.heapify(pending)
        while pending:
            height,key = heapq.heappop(pending)
            if height != targets[key]:
                continue
            for neighbor,rise in graph[key]:
                if neighbor not in fixed_approaches and height+rise < targets[neighbor]:
                    targets[neighbor] = height+rise
                    heapq.heappush(pending,(height+rise,neighbor))
        for key,target in targets.items():
            for road,end in nodes[key]:
                if not is_bridge(road.tags):
                    continue
                rise = abs(road.legacy_height(end*road.line.length)-target)
                distance = max(.3,min(145.,max(18.,rise*13.),road.line.length*.49))
                road.joins.append((end,target,distance))

        for road in self.roads:
            if not is_bridge(road.tags):
                continue
            stations = np.linspace(0,road.line.length,math.ceil(road.line.length/2)+1)
            heights = [road.height(station) for station in stations]
            allowance = .115*(stations[1]-stations[0])
            for sequence in (range(1,len(heights)), range(len(heights)-2,-1,-1)):
                previous = 0 if sequence.step>0 else len(heights)-1
                for current in sequence:
                    heights[current] = min(heights[current],heights[previous]+allowance)
                    previous = current
            road.bridge_profile = (stations,heights)

    def protect_crossing_clearance(self, source):
        """Keep existing driveable openings at actual intersecting centerlines."""
        ways = [(g,t,key) for g,t,key in source if t['kind']=='road' and
                t['highway'].removesuffix('_link') in VEHICLE]
        tree = STRtree([g for g,_,_ in ways])
        routes = {r.key:r for r in self.roads}
        bridges = sorted((r for r in self.roads if is_bridge(r.tags)),
                         key=lambda r:int(r.tags.get('layer','1')))
        self.clearance_checks = []
        for road in bridges:
            if road.key==PARK_WALK:
                continue
            stations, baseline = road.bridge_profile
            heights = np.array(baseline)
            for i in tree.query(road.line,predicate='intersects'):
                other,tags,key = ways[i]
                if key==road.key or other.geom_type!='LineString':
                    continue
                if tags['highway'].endswith('_link') and not tags.get('name'):
                    continue
                if is_bridge(tags) and int(tags.get('layer','1')) >= int(road.tags.get('layer','1')):
                    continue
                for point in parts(road.line.intersection(other),'Point'):
                    station = road.line.project(point)
                    other_station = other.project(point)
                    if min(station,road.line.length-station,other_station,other.length-other_station)<2.:
                        continue
                    low = routes[key].height(other_station) if key in routes else grade(self.dem,point.coords[0])
                    original_clear = road.legacy_height(station)-low-.81
                    if original_clear<2.15:
                        continue
                    required = low+.81+min(2.60,original_clear)
                    # Fit a smooth correction to the checked crossing without changing either approach end.
                    # Gate it over the closest available distance on short spans.
                    pad = min(4.,station*.38,(road.line.length-station)*.38)
                    delta = max(0.,required-min(float(np.interp(x,stations,heights))
                                                for x in (station-pad,station,station+pad)))
                    if delta:
                        west=min(station-pad, max(26.,delta*15.))
                        east=min(road.line.length-station-pad,max(26.,delta*15.))
                        strength=[smoothstep((s-(station-pad-west))/west)*smoothstep((station+pad+east-s)/east)
                                  for s in stations]
                        heights += delta*np.asarray(strength)
                    self.clearance_checks.append((road.key,key,station,low,required-.81-low))
            road.bridge_profile = (stations,heights)

    def tangent(self, road, s, p):
        length = road.line.length
        t = road.center(min(length,s+1.25))-road.center(max(0,s-1.25))
        t /= np.linalg.norm(t)
        if s < 1e-6 or s > length-1e-6:
            opposite = -1 if s < 1e-6 else 1
            for v in self.endpoint_dirs[tuple(p)]:
                if (v*opposite) @ t > .87:
                    t += v*opposite
            t /= np.linalg.norm(t)
        return t

    def cross_section(self, road, s):
        p = road.center(s)
        t = self.tangent(road,s,p)
        return p, np.array([-t[1],t[0]]), road.height(s,p)

    def shared_edge(self, road, p, height):
        point = Point(p)
        for i in self.route_index.query(point,predicate='intersects'):
            neighbor = self.roads[i]
            if neighbor is not road and abs(neighbor.height(neighbor.line.project(point))-height) < 1.25:
                return True
        return False

    def support(self, road, s):
        p, n, y = self.cross_section(road,s)
        h = y-grade(self.dem,p)
        if h<2.15:
            return
        corrected = hasattr(road,'corrected_profile')
        if corrected:
            t = np.array([n[1],-n[0]])
            beam = Polygon([p+n*w+t*d for w,d in
                            [(-road.width/2,-1.45),(road.width/2,-1.45),
                             (road.width/2,1.45),(-road.width/2,1.45)]])
            if self.openings.query(beam,predicate='intersects').size:
                return
        candidates = [p]
        if road.width>6 and road.key!=PARK_WALK:
            candidates = [p + n*d for d in (-road.width*.24,road.width*.24)]
        dx,dz = np.array(run_key(p))*TILE_SIZE
        mesh = self.tiles[run_key(p)]['ElevatedRoads']
        collision = self.tiles[run_key(p)]['ElevatedCollision']
        placed = 0
        for q in candidates:
            post = Point(q)
            if self.obstacle_index.query(post,predicate='intersects').size:
                continue
            blocked = False
            for i in self.route_index.query(post,predicate='intersects'):
                r = self.roads[i]
                if r is not road:
                    other = r.height(r.line.project(post))
                    if grade(self.dem,q)+.6 < other < y+1.5:
                        blocked = True
            if blocked:
                continue
            x,z = q-[dx,dz]
            floor = grade(self.dem,q)-.38
            radius = .50 if road.width<8 else .71
            cylinder(mesh,'flyover_concrete',x,z,floor,y-.85,radius+.13,radius,10)
            cylinder(collision,'flyover_concrete',x,z,floor,y-.85,radius+.13,radius,6)
            placed += 1
            self.support_count += 1
        if placed:
            cap_w = min(road.width-.25,road.width*.76)
            t = np.array([n[1],-n[0]])
            ring = [p + n*w + t*d - [dx,dz] for w,d in
                    [(-cap_w/2,-.66),(cap_w/2,-.66),(cap_w/2,.66),(-cap_w/2,.66)]]
            for target in (mesh,collision) if corrected else (mesh,):
                for k,(x,z) in enumerate(ring):
                    a,b = ring[(k+1)%4]
                    upward(target,'flyover_girder',[(x,y-1.09,z),(a,y-1.09,b),(a,y-.46,b),(x,y-.46,z)],
                           [(x+a)/2-p[0]+dx,0,(z+b)/2-p[1]+dz])
                upward(target,'flyover_girder',[(x,y-1.09,z) for x,z in ring],[0,-1,0])

    def fit_motorway(self,source):
        checks,deficits = fit_profiles(self,source)
        self.openings = STRtree([c.line.buffer(road_spec(c.tags)[0]/2)
                                .intersection(c.point.buffer(45.)) for c in checks])
        return checks,deficits

    def model(self,road):
        length = road.line.length
        coords = np.asarray(road.line.coords)
        vertices = np.r_[0,np.cumsum(np.linalg.norm(np.diff(coords,axis=0),axis=1))]
        # Break at real centerline corners and at lane stripe endpoints.
        samples = np.sort(np.r_[np.arange(0,length,5 if is_bridge(road.tags) else 2.5),np.arange(4.6,length,15),
                                np.arange(15,length,15),vertices,length])
        stations = list(np.r_[samples[0], samples[1:][np.diff(samples)>.008]])
        stations[-1] = length
        corrected = hasattr(road, 'corrected_profile')
        if corrected:
            samples = np.sort(np.r_[samples,road.corrected_profile[0]])
            stations = list(np.r_[samples[0],samples[1:][np.diff(samples)>.00001]])
            stations[-1] = length
        width = road.width
        tagged_bridge = is_bridge(road.tags)
        ped = road.key == PARK_WALK
        w=width/2
        for s0,s1 in zip(stations,stations[1:]):
            a,na,ya = self.cross_section(road,s0)
            b,nb,yb = self.cross_section(road,s1)
            mid = (a+b)/2
            axis = na+nb
            axis /= np.linalg.norm(axis)
            tile = run_key(mid)
            mesh = self.tiles[tile]['ElevatedRoads']
            collision = self.tiles[tile]['ElevatedCollision']
            origin = np.array(tile)*TILE_SIZE
            a -= origin
            b -= origin

            def face(l0,l1,r0,r1):
                return [(p[0],y,p[1]) for p,y in (
                    (a+na*l0[0],ya+l0[1]),(b+nb*l1[0],yb+l1[1]),
                    (b+nb*r1[0],yb+r1[1]),(a+na*r0[0],ya+r0[1]))]

            def strip(mat, off1, h1, off2, h2, facing, solid=False):
                quad = face((off1,h1),(off1,h1),(off2,h2),(off2,h2))
                upward(mesh,mat,quad,facing)
                if solid:
                    upward(collision,mat,quad,facing)

            if tagged_bridge:
                material = 'flyover_walk' if ped else 'highway'
                bands = (-w,0.,w) if corrected else (-w,w)
                for left,right in zip(bands,bands[1:]):
                    strip(material,left,0,right,0,(0,1,0),True)
            else:
                def drape(p, n, h, lateral, s):
                    if corrected:
                        world = p + origin
                        raster = float(self.dem(*world))
                        shoulder = float(self.dem(*(world+n*lateral)))
                        # Flatten the crossfall gradually over a bridge tie-in.
                        ends = getattr(road,'flat_tie_ends', (False,False))
                        remaining = min(s if ends[0] else math.inf,length-s if ends[1] else math.inf)
                        blend = min(smoothstep(remaining/14.),1-smoothstep((h-raster-.22)/.64))
                        return h+(shoulder-raster)*blend
                    world = p + origin
                    grade_here = float(self.dem(*world))
                    return max(.026, min(.92, h-grade_here)) + float(self.dem(*(world+n*lateral)))
                # Lane paint follows the same cross-section as the pavement.
                base_face = face
                def face(l0,l1,r0,r1):
                    quad = base_face(l0,l1,r0,r1)
                    return [ (q[0], drape(p,n,h,off,s)+dy, q[2]) for q,p,n,h,s,(off,dy) in zip(
                        quad,(a,b,b,a),(na,nb,nb,na),(ya,yb,yb,ya),(s0,s1,s1,s0),(l0,l1,r1,r0)) ]
                half_bands = math.ceil(w/3)
                count = 2*half_bands+1 if corrected else max(3,math.ceil(width/3)+1)
                bands = np.linspace(-w,w,count)
                for left,right in zip(bands,bands[1:]):
                    strip('highway',left,0,right,0,(0,1,0),True)
            rise = (ya+yb)/2-grade(self.dem,mid)
            if (tagged_bridge or corrected) and rise>.55:
                bands = (-w,0.,w) if corrected else (-w,w)
                for left,right in zip(bands,bands[1:]):
                    strip('flyover_girder',left,-DECK_DEPTH,right,-DECK_DEPTH,(0,-1,0),corrected)
                for sgn in (-1,1):
                    out = (axis[0]*sgn,0,axis[1]*sgn)
                    strip('flyover_concrete',w*sgn,0,w*sgn,-DECK_DEPTH,out,corrected)
                    if rise<.95 or self.shared_edge(road,mid+axis*(w-.06)*sgn,(ya+yb)/2):
                        continue
                    rail_top = .23 if ped else .55
                    strip('flyover_concrete',w*sgn,0,w*sgn,rail_top,out)
                    inner = (w-(.105 if ped else .29))*sgn
                    strip('flyover_concrete',inner,0,inner,rail_top,tuple(-c for c in out),True)
                    strip('flyover_concrete',inner,rail_top,w*sgn,rail_top,(0,1,0),True)
                    if ped:
                        top = 1.14
                        rail = w*sgn
                        strip('flyover_rail',rail,top-.08,rail,top,out,True)
                        strip('flyover_rail',rail-.06*sgn,top,rail,top,(0,1,0))
                        strip('flyover_rail',rail,top-.08,rail-.06*sgn,top-.08,(0,-1,0))
                        if int(s0/3.5)!=int(s1/3.5):
                            self.rail_post(mesh,mid-origin,axis,rail, (ya+yb)/2+rail_top,top-rail_top)
                    else:
                        rail = (w-.105)*sgn
                        strip('flyover_rail',rail,rail_top,rail,rail_top+.26,tuple(-c for c in out),True)
                        strip('flyover_rail',rail,rail_top+.26,w*sgn,rail_top+.26,(0,1,0))
                        strip('flyover_rail',w*sgn,rail_top+.26,w*sgn,rail_top,out)
            if ped:
                continue
            one_way = road.key != PARK_ROAD
            for sgn in (-1,1):
                x = (w-(.49 if rise>.90 else .30))*sgn
                marking = 'flyover_yellow' if one_way and sgn<0 else 'flyover_white'
                strip(marking,x-.065,.018,x+.065,.018,(0,1,0))
            for lane in range(1,road.lanes):
                x = (lane-road.lanes/2)*min(3.55,(width-1.20)/road.lanes)
                if not one_way and lane==road.lanes//2:
                    for offset in (-.095,.095):
                        strip('flyover_yellow',offset-.055,.019,offset+.055,.019,(0,1,0))
                elif ((s0+s1)*.5)%15<4.6:
                    strip('flyover_white',x-.057,.018,x+.057,.018,(0,1,0))
        if tagged_bridge or corrected:
            for s in np.arange(min(18,length*.45),length-5,25 if ped else 26):
                self.support(road,s)

    @staticmethod
    def rail_post(mesh,p,n,rail,y,h):
        x,z = p + n*rail
        cylinder(mesh,'flyover_rail',x,z,y,y+h,.043,.037,6)


def existing_layers(bounds, road_tree, records, others, selected, dem):
    """Use the existing district recipe for roads left at their original elevations."""
    dx,dz = bounds.bounds[:2]
    layers = {name:Mesh() for name in ('Roads','Markings','Bridges','BridgeCollision')}
    paving = defaultdict(list)
    around = bounds.buffer(28,join_style='mitre')
    nearby_roads = [records[i] for i in road_tree.query(around,predicate='intersects')]
    for geom,t,key in nearby_roads:
        if key in selected or t.get('tunnel') not in (None,'no','building_passage'):
            continue
        width,material = road_spec(t)
        bridge = is_bridge(t)
        for line in parts(geom,'LineString'):
            if line.length<.45:
                continue
            surface = line.buffer(width/2,quad_segs=3,cap_style='round',join_style='round').intersection(bounds)
            if surface.is_empty:
                continue
            if bridge:
                def bridge_ground(x,z):
                    distances = np.array([line.project(Point(a,b)) for a,b in zip(x,z)])
                    ramp = min(15.,line.length*.30)
                    return dem(x,z)+.091+np.minimum(1,np.minimum(distances,line.length-distances)/max(.1,ramp))*3.15
                for name in ('Bridges','BridgeCollision'):
                    patch(layers[name],surface,material,bridge_ground,dx,dz,5)
                continue
            name = t['highway'].removesuffix('_link')
            if material!='walk' or name in VEHICLE:
                paving[material].append(surface)
            if (name in ('primary','secondary','tertiary','trunk','motorway')
                    and t.get('name',t.get('ref',' ')) and line.length>25):
                for d in np.arange(11,line.length-9,16):
                    a,b = line.interpolate(d),line.interpolate(d+4.5)
                    stripe = LineString([(a.x,a.y),(b.x,b.y)]).buffer(.076,cap_style='flat').intersection(bounds)
                    paint = 'white' if t.get('oneway') in ('yes','1','-1') or name=='motorway' else 'yellow'
                    patch(layers['Markings'],stripe,paint,lambda x,z:dem(x,z)+.118,dx,dz)
    higher = []
    for material in ('highway','asphalt','service','gravel'):
        grouped = unary_union(paving[material])
        patch(layers['Roads'],grouped.difference(unary_union(higher)),material,lambda x,z:dem(x,z)+.078,dx,dz,6)
        higher.extend(paving[material])
    paved = unary_union([g for kind in paving.values() for g in kind]).buffer(.15)
    for geom,t,_ in others:
        if t['kind']=='airstrip' and t.get('aeroway')=='runway' and geom.intersects(around):
            for line in parts(geom,'LineString'):
                for step in np.arange(110,line.length-50,62):
                    a,b=line.interpolate(step),line.interpolate(step+24)
                    stripe=LineString([(a.x,a.y),(b.x,b.y)]).buffer(.47,cap_style='flat').intersection(bounds)
                    patch(layers['Markings'],stripe,'white',lambda x,z:dem(x,z)+.14,dx,dz)
        if (t['kind']!='prop' or t.get('highway')!='crossing' or geom.geom_type!='Point'
                or not geom.intersects(bounds) or not paved.contains(geom)):
            continue
        nearby = [(g,t) for g,t,k in nearby_roads if k not in selected and t['highway'] in VEHICLE and g.distance(geom)<6]
        if not nearby:
            continue
        road,tags = min(nearby,key=lambda item:item[0].distance(geom))
        if road.geom_type!='LineString':
            continue
        s = road.project(geom)
        a,b = [np.array(road.interpolate(s+d).coords[0]) for d in (-min(s,1),min(road.length-s,1))]
        tangent = (b-a)/np.linalg.norm(b-a)
        normal = np.array([-tangent[1],tangent[0]])
        width = road_spec(tags)[0]
        for offset in np.arange(-width*.41,width*.42,1.05):
            p = np.asarray(geom.coords[0])+normal*offset
            stripe = Polygon([p+tangent*u+normal*v for u,v in [(-1.3,-.25),(1.3,-.25),(1.3,.25),(-1.3,.25)]])
            patch(layers['Markings'],stripe.intersection(bounds),'white',lambda x,z:dem(x,z)+.132,dx,dz)
    return layers


def plant_grove(site, source, connector):
    """Add a limited grove inside the park near the path that leads to the bridge."""
    park = next(g for g,t,_ in source if t.get('name')=='Hugh Ramsey Nature Park')
    paths = unary_union([g for g,t,_ in source
                         if t.get('highway') in ('footway','path','cycleway','service')
                         and park.intersects(g)] + [connector])
    paved = unary_union([g.buffer(road_spec(t)[0]/2)
                         for g,t,_ in source if t.get('highway') in VEHICLE and park.intersects(g)])
    region = park.intersection(box(3369,995,3505,1190)).difference(paved.buffer(5.8))
    region = region.difference(paths.buffer(3.6))
    x0,z0,x1,z1 = region.bounds
    rng = random.Random(809)
    shrubs = scrub()
    for x in np.arange(x0,x1,7.2):
        for z in np.arange(z0,z1,7.2):
            p = np.array([x+rng.uniform(-2,2),z+rng.uniform(-2,2)])
            if not region.contains(Point(p)) or rng.random()<.64:
                continue
            terrain = site.grade(p)
            xx,zz = p-site.origin
            height = rng.uniform(2.2,4.1)
            if rng.random()<.46:
                for material,(coords,_,_,faces) in shrubs.parts.items():
                    a = np.asarray(coords)*rng.uniform(.9,1.75)+[xx,terrain,zz]
                    site.visual.add(material,a,faces)
                continue
            cylinder(site.visual,'trunk',xx,zz,terrain-.09,terrain+height*.68,.13,.07,6)
            cylinder(site.collision,'trunk',xx,zz,terrain-.09,terrain+height*.52,.15,.10,5)
            for _ in range(3):
                tx,tz = [rng.uniform(-height*.24,height*.24) for _ in range(2)]
                for material,(coords,_,_,faces) in shrubs.parts.items():
                    coords = np.asarray(coords)
                    a = coords*[height*1.45,height*.90,height*1.45]+[xx+tx,terrain+height*.57,zz+tz]
                    site.visual.add('ramsey_foliage' if material=='leaf' else 'ramsey_leaf_tips',a,faces)


def trailhead(model, source):
    origin = np.array([2000,0])
    site = Landmark('RamseyTrailhead','+01_+00',origin,model.dem)
    # The entrance feature sits between the trail and the park side of Loop 499.
    f = Frame.edge((3410.4,1057.7),(3418.6,1042.0))
    x,z = f.point
    y = grade(model.dem,(x,z))
    c = site.cuboid
    c(f,'flyover_concrete',0,y-.30,0,4.10,.78,.53,solid=True)
    c(f,'flyover_park_sign',0,y+.43,0,4.0,1.05,.23)
    c(f,'flyover_wood',0,y+1.47,0,4.13,.11,.36)
    site.label(f,'HUGH RAMSEY',0,y+1.17,.127,.34)
    site.label(f,'NATURE PARK',0,y+.79,.127,.26)
    for x in (-3.2,3.2):
        p = f.xy(x,-1.9)
        h = grade(model.dem,p)
        for d in (-.66,.66):
            c(f,'flyover_concrete',x+d,h-.07,-1.9,.21,.52,.53,solid=True)
        c(f,'flyover_wood',x,h+.42,-1.92,1.86,.09,.48)
        c(f,'flyover_wood',x,h+.68,-2.12,1.86,.26,.073)
    # Short game connector linking the western trail loop to the bridge approach.
    # The durable path follows existing terrain inside the park boundary.
    connector = LineString([(3379.3,1096.3),(3369.5,1106.7),(3363.6,1121.2),(3364.1,1132.2),
                            (3372.4,1139.7),(3384.6,1141.8),(3390.5,1145.6)])
    plant_grove(site,source,connector)
    site.save()
    mesh = model.tiles[(1,0)]['ElevatedRoads']
    patch(mesh,connector.buffer(.83,quad_segs=3),'flyover_trail',
          lambda a,b:model.dem(a,b)+.12,*origin,3)
    return connector.length


def scene_edit(old_text, directory, layers, add_park):
    source = old_text.strip()
    for layer,mesh in layers.items():
        if mesh.parts:
            continue
        # A former coarse bridge layer can be empty after the audited replacements.
        old_res = next((r for r in source.splitlines() if f'/{layer}.glb"' in r),None)
        if old_res:
            ident = old_res.split('id="')[-1].split('"')[0]
            node = f'[node name="{layer}" parent="." instance=ExtResource("{ident}")]'
            source = source.replace(old_res+'\n','').replace(node+'\n','').replace(node,'')
    defs = [f'[ext_resource type="PackedScene" path="res://tiles/{directory}/ElevatedRoads.glb" id="flyover"]']
    nodes = ['[node name="ElevatedRoads" parent="." instance=ExtResource("flyover")]']
    if add_park:
        defs.append('[ext_resource type="PackedScene" path="res://assets/landmarks/RamseyTrailhead.tscn" id="ramsey"]')
        nodes.append('[node name="RamseyTrailhead" parent="." instance=ExtResource("ramsey")]')
    return source.replace('\n[node name=', '\n'+'\n'.join(defs)+'\n\n[node name=',1)+'\n\n'+'\n\n'.join(nodes)+'\n'


def material_import(folder, mesh):
    path = folder/'ElevatedRoads.glb.import'
    base = (ROOT/'tiles'/'-02_+00'/'Bridges.glb.import').read_text()
    rel = folder.relative_to(ROOT).as_posix()+'/ElevatedRoads.glb'
    bindings = {key:{'use_external/enabled':True,
                     'use_external/fallback_path':f'res://materials/{material}.tres',
                     'use_external/path':f'res://materials/{material}.tres'}
                for key,material in MODE.items() if key in mesh.parts}
    import re
    import hashlib
    # Engine-equivalent destination hash keeps the sidecar usable on first import.
    old_res = 'res://tiles/-02_+00/Bridges.glb'
    new_res = f'res://{rel}'
    old_hash = hashlib.md5(old_res.encode()).hexdigest()
    new_hash = hashlib.md5(new_res.encode()).hexdigest()
    base = re.sub('^uid=.*\n','',base,flags=re.M)
    base = base.replace(old_res,new_res).replace('Bridges.glb-'+old_hash,'ElevatedRoads.glb-'+new_hash)
    base = re.sub(r'_subresources=\{.*?\}\s*(?=gltf/)', '_subresources='+json.dumps({'materials':bindings},indent=0)+'\n',base,flags=re.S)
    path.write_text(base)


def main(previous):
    source = [(g,t,i.split(':')[-1]) for g,t,i in read_features('osm_local.geojson.gz')]
    records = [(g,t,i) for g,t,i in source if t['kind']=='road']
    others = [(g,t,i) for g,t,i in source if t['kind'] in ('airstrip','prop')]
    road_tree = STRtree([g for g,_,_ in records])
    selected = set(MAIN+WEST+list(FLYOVERS)+list(CONNECTORS)+[PARK_ROAD,PARK_WALK])
    dem = Elevation(ROOT/'source'/'3dep_float.tif')
    roads = [Road(i,g,t,dem) for g,t,i in records if i in selected]
    assert {r.key for r in roads}==selected
    model = RouteModel(roads,source,dem)
    model.fit_motorway(source)
    for road in roads:
        assert road.line.geom_type=='LineString'
        model.model(road)
    path_length = trailhead(model, source)
    affected = []
    with ZipFile(previous) as original:
        manifest = json.loads(original.read('Harlingen/manifest.json'))
        tiles = {t['id']:t for t in manifest['tiles']}
        for (ix,iz), geometry in sorted(model.tiles.items()):
            tile = f'{ix:+03d}_{iz:+03d}'
            folder = ROOT/'tiles'/tile
            row = tiles[tile]
            bounds = box(ix*TILE_SIZE,iz*TILE_SIZE,(ix+1)*TILE_SIZE,(iz+1)*TILE_SIZE)
            layers = existing_layers(bounds,road_tree,records,others,selected,dem)
            manifest_layers = row['layers']
            for name,mesh in (layers | geometry).items():
                path = folder/(name+'.glb')
                if write_glb(path,name,mesh):
                    manifest_layers[name] = dict(file=path.relative_to(ROOT).as_posix(), triangles=mesh.triangles())
                else:
                    path.unlink(missing_ok=True)
                    path.with_suffix('.glb.import').unlink(missing_ok=True)
                    manifest_layers.pop(name,None)
            scene = original.read(f'Harlingen/tiles/{tile}/district.tscn').decode()
            (folder/'district.tscn').write_text(scene_edit(scene,tile,layers,tile=='+01_+00'))
            material_import(folder,geometry['ElevatedRoads'])
            affected.append(tile)
            print(tile, {name:mesh.triangles() for name,mesh in geometry.items()})

        # Existing buildings, street detail, terrain and their collision remain site-for-site intact.
        manifest['elevated_highway'] = dict(tiles=affected, upgraded_osm_ways=sorted(selected),
            pier_columns=model.support_count, ramsey_walk_bridge_m=round(next(r.line.length for r in roads if r.key==PARK_WALK),1),
            added_trail_m=round(path_length,1))
        (ROOT/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print(len(roads),'mapped ways;',model.support_count,'columns;',len(affected),'districts')


if __name__=='__main__':
    import sys
    main(sys.argv[1])
