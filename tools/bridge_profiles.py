"""Fit motorway vertical profiles to mapped topology and USGS 3DEP terrain."""
from collections import defaultdict
from dataclasses import dataclass
import heapq
import math

import numpy as np
from shapely.geometry import Point, Polygon
from shapely.strtree import STRtree

from build import VEHICLE, parts, road_spec
from road_grade import ground_grade, is_bridge

DECK_DEPTH = .81
CLEARANCE_TARGET = 4.5
DESIGN_CLEARANCE = 4.68
GRADE_LIMIT = .0775
GRADE_CHANGE_PER_M = .0025
APPROACH_REACH = 112.
STEP = 4.

# Way pairs identified by the first geographic audit, upper then lower.
AUDITED_CROSSINGS = (
    ('97348021', '119748999'), ('97347916', '120600239'),
    ('97347864', '174532927'), ('97347848', '174532916'),
    ('97347916', '120600216'), ('97347880', '119748999'),
    ('97348021', '174532921'), ('97348004', '174532927'),
    ('97347912', '120600239'), ('97347912', '120600216'),
    ('97347880', '174532921'), ('97347952', '174532916'),
    ('97347848', '119748878'), ('1459656357', '143685397'),
    ('97348034', '143685397'), ('119748869', '143685397'),
    ('97347952', '119748878'), ('97347944', '569136402'),
)


@dataclass
class Crossing:
    upper: object
    lower: str
    line: object
    tags: dict
    point: object
    station: float
    lower_station: float
    baseline: float


def crossings(model, source):
    ways = {key:(line,tags) for line,tags,key in source if tags['kind']=='road'
            and line.geom_type=='LineString' and tags['highway'].removesuffix('_link') in VEHICLE}
    routes = {road.key:road for road in model.roads}
    preserved = {(upper,lower) for upper,lower,*_ in model.clearance_checks}
    for upper,lower in sorted(set(AUDITED_CROSSINGS) | preserved):
        road = routes[upper]
        if road.tags['highway'].removesuffix('_link') != 'motorway':
            continue
        line,tags = ways[lower]
        for point in parts(road.line.intersection(line),'Point'):
            station = road.line.project(point)
            lower_station = line.project(point)
            if min(station,road.line.length-station,lower_station,line.length-lower_station)<2.:
                continue
            low = routes[lower].height(lower_station) if lower in routes else ground_grade(model.dem,*point.coords[0])
            yield Crossing(road,lower,line,tags,point,station,lower_station,road.height(station)-low-DECK_DEPTH)


def node_key(point):
    return tuple(np.round(point,3))


def approach_distances(roads):
    graph = defaultdict(list)
    distances = {}
    for road in roads:
        a,b = [node_key(road.line.coords[i]) for i in (0,-1)]
        if is_bridge(road.tags):
            distances[a] = distances[b] = 0.
        else:
            graph[a].append((b,road.line.length))
            graph[b].append((a,road.line.length))
    pending = [(0.,key) for key in distances]
    heapq.heapify(pending)
    while pending:
        distance,key = heapq.heappop(pending)
        if distance != distances[key]:
            continue
        for neighbor,length in graph[key]:
            total = distance+length
            if total<APPROACH_REACH and total<distances.get(neighbor,math.inf):
                distances[neighbor] = total
                heapq.heappush(pending,(total,neighbor))
    return distances


def overlap_samples(model, crossing, lower):
    """Sample both sides of the opening and across the lower roadway width."""
    def ribbon(road, station):
        line = road.line
        sections = []
        for s in np.linspace(max(0.,station-48.),min(line.length,station+48.),49):
            p = road.center(s)
            tangent = model.tangent(road,s,p)
            shift = np.array([-tangent[1],tangent[0]])*road.width/2
            sections.append((p+shift,p-shift))
        return Polygon([a for a,_ in sections]+[b for _,b in reversed(sections)]).buffer(0)

    upper_shape = ribbon(crossing.upper,crossing.station)
    if lower is None:
        low_shape = crossing.line.buffer(road_spec(crossing.tags)[0]/2)
    else:
        low_shape = ribbon(lower,crossing.lower_station)
    area = upper_shape.intersection(low_shape)
    yield crossing.point.coords[0]
    for polygon in parts(area,'Polygon'):
        yield from polygon.exterior.segmentize(1.5).coords
        x0,z0,x1,z1 = polygon.bounds
        for x in np.arange(x0+1,x1,2.):
            for z in np.arange(z0+1,z1,2.):
                if polygon.covers(Point(x,z)):
                    yield x,z


def fit_profiles(model, source):
    from scipy.optimize import linprog
    from scipy.sparse import coo_matrix

    roads = [road for road in model.roads if road.tags['highway'].removesuffix('_link')=='motorway']
    routes = {road.key:road for road in roads}
    check = list(crossings(model,source))
    by_pair = {(c.upper.key,c.lower):c for c in check}
    if set(AUDITED_CROSSINGS)-by_pair.keys():
        raise ValueError('The 18 audit crossings no longer match the OSM source')
    nodes = {}
    incidence = defaultdict(list)
    positions = {}
    bounds = []
    objective = []
    preferred = []
    rows,columns,weights,limits = [],[],[],[]

    def variable(low,high,cost=0.):
        index = len(bounds)
        bounds.append((low,high))
        objective.append(cost)
        return index

    def limit(terms, cap):
        for index,value in terms:
            rows.append(len(limits))
            columns.append(index)
            weights.append(value)
        limits.append(cap)

    distances = approach_distances(roads)
    external = [g for g,t,key in source if t['kind']=='road' and key not in routes
                and t['highway'].removesuffix('_link') in VEHICLE]
    external_nodes = STRtree(external)
    for road in roads:
        length = road.line.length
        tagged = is_bridge(road.tags)
        ends = [node_key(road.line.coords[i]) for i in (0,-1)]
        end_distances = [distances.get(key,math.inf) for key in ends]
        stations = np.linspace(0,length,math.ceil(length/STEP)+1)
        handles = []
        for i,s in enumerate(stations):
            point = road.center(s)
            ground = float(ground_grade(model.dem,*point))
            before = road.height(s,point)
            extension_distance = min(s+end_distances[0],length-s+end_distances[1])
            maximum = 36. if tagged or extension_distance < APPROACH_REACH else ground+.78
            minimum = min(ground-.04,before) if tagged else ground-.032
            key = ends[0] if i==0 else ends[-1] if i==len(stations)-1 else None
            if key is not None:
                # Pin merges with roads outside the model to their retained terrain grade.
                p = Point(point)
                if any(external[j].distance(p)<.035 for j in external_nodes.query(p.buffer(.04))):
                    maximum = min(maximum,ground+.18)
                if key in nodes:
                    index = nodes[key]
                    low,high = bounds[index]
                    bounds[index] = max(low,minimum),min(high,maximum)
                else:
                    index = nodes[key] = variable(minimum,maximum)
                side = road.center(min(length,STEP) if i==0 else max(0.,length-STEP))-point
                incidence[key].append((road,i,side/np.linalg.norm(side)))
            else:
                index = variable(minimum,maximum)
            preferred.append((index,before,1. if tagged else 2.6))
            handles.append(index)
        positions[road.key] = stations,handles

    def bend(a,b,c,first,second,rate=GRADE_CHANGE_PER_M):
        terms = [(a,1/first),(b,-1/first-1/second),(c,1/second)]
        permitted = rate*(first+second)/2
        limit(terms,permitted)
        limit([(i,-w) for i,w in terms],permitted)

    for road in roads:
        stations,handles = positions[road.key]
        for i,(left,right) in enumerate(zip(handles,handles[1:])):
            step = stations[i+1]-stations[i]
            limit([(right,1.),(left,-1.)],GRADE_LIMIT*step)
            limit([(left,1.),(right,-1.)],GRADE_LIMIT*step)
        for i in range(1,len(handles)-1):
            end_distances = [distances.get(node_key(road.line.coords[j]),math.inf) for j in (0,-1)]
            near = min(stations[i]+end_distances[0],stations[-1]-stations[i]+end_distances[1])
            rate = GRADE_CHANGE_PER_M if is_bridge(road.tags) or near<95. else .0125
            bend(*handles[i-1:i+2],stations[i]-stations[i-1],stations[i+1]-stations[i],rate)
    for key,neighbors in incidence.items():
        for i,(a,ia,ta) in enumerate(neighbors):
            for b,ib,tb in neighbors[i+1:]:
                if ta@tb>-.85:
                    continue
                sa,ha = positions[a.key]
                sb,hb = positions[b.key]
                bend(ha[1 if ia==0 else -2],nodes[key],hb[1 if ib==0 else -2],sa[1]-sa[0],sb[1]-sb[0])

    def height_terms(road, station, sign):
        stations,handles = positions[road.key]
        i = max(0,min(len(handles)-2,int(np.searchsorted(stations,station))-1))
        t = (station-stations[i])/(stations[i+1]-stations[i])
        return [(handles[i],sign*(1-t)),(handles[i+1],sign*t)]

    deficits = []
    for crossing in check:
        upper = crossing.upper
        lower = routes.get(crossing.lower)
        audited = (upper.key,crossing.lower) in AUDITED_CROSSINGS
        # Account for the lower roadway's transverse raster variation and the actual
        # extent of the overlapping footprints. Existing separated crossings use
        # the same target, with a lower preference than the audited set.
        slack = variable(0.,None,140000. if audited else 30000.)
        deficits.append((crossing,slack))
        for p in overlap_samples(model,crossing,lower):
            point = Point(p)
            upper_s = upper.line.project(point)
            terms = height_terms(upper,upper_s,-1.)
            terms.append((slack,-1.))
            fixed = 0.
            if lower is None:
                fixed = float(ground_grade(model.dem,*p))+.07
            else:
                lower_s = lower.line.project(point)
                if not is_bridge(lower.tags):
                    fixed = max(0.,float(model.dem(*p)-model.dem(*lower.center(lower_s))))
                terms.extend(height_terms(lower,lower_s,1.))
            limit(terms,-DESIGN_CLEARANCE-DECK_DEPTH-fixed)

    for index,before,cost in preferred:
        deviation = variable(0.,None,cost)
        limit([(index,1.),(deviation,-1.)],before)
        limit([(index,-1.),(deviation,-1.)],-before)

    matrix = coo_matrix((weights,(rows,columns)),shape=(len(limits),len(bounds))).tocsr()
    result = linprog(objective,A_ub=matrix,b_ub=limits,bounds=bounds,method='highs')
    if not result.success:
        raise ValueError(f'Cannot fit motorway vertical profiles: {result.message}')
    flat_nodes = {node for node, neighbors in incidence.items()
                  if any(is_bridge(road.tags) for road,_,_ in neighbors)}
    for road in roads:
        road.flat_tie_ends = tuple(node_key(road.line.coords[i]) in flat_nodes for i in (0,-1))
        stations,handles = positions[road.key]
        road.corrected_profile = stations,result.x[handles]
    return check,[(c.upper.key,c.lower,round(result.x[i],3)) for c,i in deficits if result.x[i]>.001]
