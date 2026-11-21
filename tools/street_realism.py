"""Rebuild the citywide surface-street treatment from the loaded GIS district meshes."""
from collections import Counter, defaultdict
from concurrent.futures import ProcessPoolExecutor
from dataclasses import dataclass
from pathlib import Path
import hashlib
import json
import math
import random
import re
import struct
from zipfile import ZipFile

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from shapely import intersects_xy, points
from shapely.geometry import LineString, Point, Polygon, box
from shapely.ops import unary_union
from shapely.strtree import STRtree

from build import Elevation, ROOT, TILE_SIZE, patch, parts, read_features, road_spec, seed
from landmarks import read_container, write_container
from mesh import Mesh, PALETTE, cylinder, write_glb
from street_detail import Surface, write_detail

MAJOR = {'primary','secondary','tertiary'}
PUBLIC = MAJOR | {'residential','living_street','unclassified'}
VEHICLE_SURFACE = PUBLIC | {'service'}
COLORS = {
    'old_slab': (.63,.62,.59), 'new_slab': (.77,.75,.70), 'ramp_concrete': (.70,.68,.63),
    'warning_mat': (.61,.29,.19), 'fissure': (.28,.27,.24), 'tar': (.195,.187,.17),
    'asphalt_patch': (.30,.285,.263), 'asphalt_fade': (.43,.405,.37),
    'tire': (.255,.245,.228), 'oil': (.185,.171,.145), 'pothole': (.138,.133,.124),
    'hole_edge': (.38,.35,.31), 'street_white': (.91,.90,.83), 'street_yellow': (.86,.66,.19),
    'street_iron': (.27,.277,.269), 'iron_dark': (.13,.145,.136), 'street_grass': (.34,.44,.22),
    'street_post': (.40,.421,.427), 'street_wood': (.40,.30,.22), 'wood_end': (.48,.36,.24),
    'wire': (.145,.16,.158), 'hydrant': (.73,.27,.13), 'hydrant_bonnet': (.78,.62,.24),
    'mail_blue': (.115,.29,.48), 'news_burgundy': (.59,.15,.18), 'news_window': (.23,.34,.39),
    'news_paper': (.81,.80,.69), 'bin_green': (.27,.38,.31), 'signal_box': (.23,.244,.235),
    'signal_visors': (.115,.126,.125), 'signal_amber': (.98,.65,.10),
    'signal_red': (.84,.13,.075), 'signal_green': (.27,.78,.36), 'lens_off': (.28,.29,.25),
    'lamp_lens': (.85,.82,.64), 'speed_face': (1,1,1),
}
PALETTE.update(COLORS)
RES = ROOT/'materials'/'street_realism'
PAINT = {'street_white':'paint_white','street_yellow':'paint_yellow',
         'ramp_concrete':'concrete_ramp','new_slab':'concrete_new','old_slab':'concrete_old'}
CUT_TYPES = {'curb','crosswalk'}
BASE = {}
STREETS = []
CROSSINGS = []
OIL_SITES = []
PROPS = []
CABLES = []


@dataclass
class Street:
    line: LineString
    tags: dict
    ident: str
    width: float

    @property
    def kind(self):
        return self.tags['highway']

    @property
    def speed(self):
        speed = re.match(r'^(25|35|45)\s*mph',self.tags.get('maxspeed',''),re.I)
        return int(speed[1]) if speed else (45 if self.kind=='primary' else 35 if self.kind in MAJOR else 25)

    @property
    def one_way(self):
        return self.tags.get('oneway') in ('yes','1','-1','true')


def uv_frame(line, station, reach=2.0):
    p = np.array(line.interpolate(station).coords[0])
    a = np.array(line.interpolate(max(0,station-reach)).coords[0])
    b = np.array(line.interpolate(min(line.length,station+reach)).coords[0])
    t = b-a
    t /= max(1e-8,np.linalg.norm(t))
    return p,t,np.array([-t[1],t[0]])


def bbox_of(p):
    return tuple((np.floor(np.asarray(p)/TILE_SIZE)*TILE_SIZE).astype(int))


def outline_is_public(tags, ident, hidden):
    name=tags.get('name','').lower()
    return (tags.get('highway') in VEHICLE_SURFACE and ident not in hidden
            and tags.get('bridge','no')=='no' and tags.get('tunnel','no')=='no'
            and not any(name.startswith(n) for n in ('north expressway','south expressway','west expressway','frontage road')))


def add_global(source, hidden, dem):
    junctions = defaultdict(list)
    signals = STRtree([g for g,t,_ in source if t.get('highway')=='traffic_signals' and g.geom_type=='Point'])
    raw_streets=[]
    for geom,t,id in source:
        if not outline_is_public(t,id,hidden):
            continue
        for line in parts(geom,'LineString'):
            if line.length < 4:
                continue
            street = Street(line,t,id,road_spec(t)[0])
            STREETS.append(street)
            raw_streets.append(line)
            if street.kind not in PUBLIC:
                continue
            v = np.asarray(line.coords)
            for i,p in enumerate(v):
                for j in (i-1,i+1):
                    if j<0 or j>=len(v):
                        continue
                    delta=v[j]-p
                    length=np.linalg.norm(delta)
                    if length>.08:
                        junctions[tuple(np.round(p,2))].append((delta/length,street))
    road_tree=STRtree(raw_streets)
    all_veh = [(g,road_spec(t)[0]) for g,t,_ in source if t.get('highway','').split('_link')[0]
               in VEHICLE_SURFACE|{'motorway','trunk'} and t.get('bridge','no')=='no']
    veh_buffer = STRtree([g.buffer(w*.5+.22,quad_segs=2) for g,w in all_veh])
    buildings = STRtree([g.buffer(.38,quad_segs=2) for g,t,_ in source if t['kind']=='building'])
    parked = STRtree([g for g,t,_ in source if t['kind']=='land' and t.get('amenity')=='parking'])
    occupied = set()
    sign_grid = defaultdict(list)

    def room(p):
        if not (-5998<p[0]<5998 and -5998<p[1]<5998):
            return False
        q=Point(p)
        return not veh_buffer.query(q,predicate='intersects').size and not buildings.query(q,predicate='intersects').size

    def place(kind,p,t,value=0):
        key=tuple(np.floor(np.asarray(p)/1.45).astype(int))
        if key in occupied or not room(p):
            return False
        if kind=='speed':
            cell=tuple(np.floor(np.asarray(p)/70).astype(int))
            for u in range(cell[0]-1,cell[0]+2):
                for v in range(cell[1]-1,cell[1]+2):
                    if any(np.linalg.norm(p-q)<70 and t@direction>.82 for q,direction in sign_grid[u,v]):
                        return False
            sign_grid[cell].append((p,t))
        occupied.add(key)
        PROPS.append((kind,np.asarray(p),np.asarray(t),value))
        return True

    junction_index = []
    for center,raw in junctions.items():
        arms=[]
        for t,street in raw:
            if all(t@d <.977 for d,_ in arms):
                arms.append((t,street))
        if len(arms)<3 or not any(abs(a@b)<.84 for a,_ in arms for b,_ in arms):
            continue
        p=np.asarray(center)
        if not all(-5986<q<5986 for q in p):
            continue
        junction_index.append(Point(p))
        is_signal = signals.query(Point(p),predicate='dwithin',distance=20).size>0
        is_signal |= len(arms)>=4 and sum(s.kind in MAJOR for _,s in arms)>=3
        arterial=any(s.kind in MAJOR for _,s in arms)
        four = len(arms)>=4
        for j,(t,street) in enumerate(arms):
            n=np.array([-t[1],t[0]])
            crossing=[s.width for d,s in arms if abs(d@t)<.87]
            if not crossing:
                continue
            lead = max(crossing)*.53+1.85
            q=p+t*lead
            # Project the crossing back onto its native approach after the local junction skew.
            s=street.line.project(Point(q))
            q,aligned,native=uv_frame(street.line,s)
            if aligned@t<0:
                aligned=-aligned
                native=-native
            if np.linalg.norm(q-p)<lead*.55:
                continue
            CROSSINGS.append((q,aligned,street.width,street.one_way,p))
            OIL_SITES.append((q+t*4.0,aligned,street.width*.29))
            if is_signal:
                place('signal',q+n*(street.width/2+1.15)-t*.9,aligned, j%2 if four else 0)
            if arterial and j==0:
                place('light',q-n*(street.width/2+1.85),n)
            if j==1 and (arterial or seed(center)%3==0):
                place('hydrant',q-n*(street.width/2+.87)+t*4,t)
    jtree=STRtree(junction_index)
    protected = STRtree([g.buffer(14,quad_segs=2) for g,t,id in source if id in hidden and t['kind']=='road'])
    last_poles=defaultdict(list)
    for street in STREETS:
        line=street.line
        rng=random.Random(seed(street.ident))
        if street.kind not in PUBLIC:
            if parked.query(line,predicate='intersects').size:
                for station in np.arange(8,line.length-3,32):
                    p,t,_ = uv_frame(line,station)
                    OIL_SITES.append((p,t,0.7))
            continue
        def sample(station,side,extra=.70):
            p,t,n=uv_frame(line,station)
            return p+n*side*(street.width/2+extra),t,n
        def clear(p,distance):
            return not jtree.query(Point(p),predicate='dwithin',distance=distance).size
        for station in np.arange(20+rng.uniform(0,24),line.length-10,175 if street.kind in MAJOR else 145):
            for side in ([1] if street.one_way else [-1,1]):
                p,t,n=sample(station,side,1.18)
                if clear(p,17):
                    place('speed',p,-side*t,street.speed)
        for station in np.arange(10+rng.uniform(0,20),line.length-8,90 if street.kind in MAJOR else 138):
            p,t,n=sample(station,1,1.76)
            if street.kind in MAJOR and clear(p,19):
                place('light',p,-n)
            m=p-2*n*(street.width/2+1.3)
            if clear(m,12) and (street.kind in MAJOR or rng.random()<.46):
                place('mailbox' if street.kind not in MAJOR else 'news',m,t)
        # Long uninterrupted local segments get overhead distribution cables and wooden poles.
        if street.kind in {'primary','residential','tertiary','unclassified','secondary'}:
            previous=None
            for station in np.arange(9+rng.uniform(0,7),line.length-8,44+rng.uniform(0,9)):
                p,t,n=sample(station,-1,1.46)
                if not clear(p,8) or protected.query(Point(p),predicate='intersects').size or not place('pole',p,t):
                    previous=None
                    continue
                if previous is not None:
                    before, old_t = previous
                    if t@old_t>.53 and np.linalg.norm(p-before)<60:
                        CABLES.append((before,old_t,p,t))
                previous=p,t
                if street.tags.get('name'):
                    last_poles[street.tags['name']].append((p,t))
    connections={tuple(sorted((tuple(a),tuple(b)))) for a,_,b,_ in CABLES}
    for poles in last_poles.values():
        if len(poles)<2:
            continue
        tree=STRtree([Point(p) for p,_ in poles])
        for i,(p,t) in enumerate(poles):
            for j in tree.query(Point(p),predicate='dwithin',distance=60):
                if i==j:
                    continue
                q,d=poles[j]
                dist=np.linalg.norm(q-p)
                if dist<20 or abs((q-p)@t)<.94*dist or abs(t@d)<.91:
                    continue
                connection=tuple(sorted((tuple(p),tuple(q))))
                if connection not in connections:
                    connections.add(connection)
                    CABLES.append((p,t,q,d if t@d>0 else -d))
    # Public-facing frontage points supply small bins adjacent to commercial entrances.
    for geom,t,id in source:
        if (t['kind']!='building' or geom.area<65 or geom.area>1700 or
            t.get('building') in ('house','garage','shed','hospital','roof') or seed(id)%3!=0):
            continue
        center=geom.representative_point()
        i=road_tree.nearest(center)
        if i is None:
            continue
        street=STREETS[i]
        if street.kind not in MAJOR and not t.get('shop'):
            continue
        p,tangent,n=uv_frame(street.line,street.line.project(center))
        front=geom.boundary.interpolate(geom.boundary.project(Point(p)))
        pos=np.array(front.coords[0])
        direction=p-pos
        distance=np.linalg.norm(direction)
        if not street.width/2+1.7<distance<street.width/2+9:
            continue
        direction/=distance
        q=pos+direction*.68+tangent*.76
        place('bin',q,direction)


def paint_quad(mesh, material, poly, surface, dy=.016):
    xy = np.asarray(poly)
    y = surface.heights(xy)+dy
    mesh.add(material, np.column_stack((xy[:,0],y,xy[:,1])), [0,1,2,0,2,3],
             normals=[(0,1,0)]*4)


def corners(p,t,n,half_along,half_across):
    return np.asarray([p+t*u+n*v for u,v in [(-half_along,-half_across),
                    (-half_along,half_across),(half_along,half_across),(half_along,-half_across)]])


def contains(surface, xy):
    return len(set(surface.index.query(points(np.asarray(xy)),predicate='intersects')[0]))==len(xy)


def strip(mesh,material,a,b,width,surface,dy=.013):
    dif=b-a
    norm=np.linalg.norm(dif)
    if norm<.02:
        return False
    n=np.array([-dif[1],dif[0]])/norm
    polygon=corners((a+b)/2,dif/norm,n,norm/2,width/2)
    if contains(surface,polygon):
        paint_quad(mesh,material,polygon,surface,dy)
        return True
    return False


def crack(mesh, surface, start, tangent, scale, rng, material='tar', height=.014):
    p=np.asarray(start)
    side=np.array([-tangent[1],tangent[0]])
    for i in range(rng.randint(3,6)):
        q=p+rng.uniform(.12,.47)*scale*tangent+rng.uniform(-.19,.23)*scale*side
        strip(mesh,material,p,q,rng.uniform(.013,.038)*min(scale,1.4),surface,height)
        if i==2:
            strip(mesh,material,p,p+tangent*.16+side*.40*scale,.017,surface,height)
        p=q


def disc(mesh,mat,surface,p,ra,rb,rng,dy,irregular=True,edge=None):
    angle=np.arange(10)*math.tau/10
    factor=np.array([rng.uniform(.71,1.25) for _ in angle]) if irregular else 1
    radial=np.column_stack([np.cos(angle)*ra,np.sin(angle)*rb])
    vertices=p+radial*np.broadcast_to(factor,(10,))[:,None]
    if not contains(surface,vertices):
        return False
    yy=surface.heights(np.vstack([p,vertices]))
    verts=np.column_stack((np.r_[p[0],vertices[:,0]],yy+dy,np.r_[p[1],vertices[:,1]]))
    mesh.add(mat,verts,[k for i in range(1,11) for k in (0,1+i%10,i)],normals=[(0,1,0)]*11)
    if edge:
        for i in range(10):
            strip(mesh,edge,vertices[i],vertices[(i+1)%10],.065,surface,dy+.002)
    return True


def center_marks_and_wear(mesh, streets, surface, offset, junctions, stats):
    for street in streets:
        line=street.line
        rng=random.Random(seed(street.ident)+347)
        highway=street.kind in MAJOR
        which_paint = 'street_white' if street.one_way else 'street_yellow'
        span=12 if highway else 15
        for s0 in np.arange(0,line.length,span):
            p,t,n=uv_frame(line,min(s0+2.4,line.length))
            if bbox_of(p)!=tuple(offset) or junctions.query(Point(p),predicate='dwithin',distance=13).size:
                continue
            if highway or street.kind=='unclassified' or (street.kind=='residential' and street.width>=8.75):
                a,_,n0=uv_frame(line,s0)
                b,_,n1=uv_frame(line,min(s0+5,line.length))
                if street.tags.get('lanes') in ('4','5','6') and not street.one_way:
                    for u in (-.12,.12):
                        end=uv_frame(line,min(s0+span,line.length))
                        cut=junctions.query(Point(end[0]),predicate='dwithin',distance=11).size
                        if not cut:
                            if strip(mesh,'street_yellow',a-offset+n0*u,end[0]-offset+end[2]*u,.10,surface,.027):
                                stats['center_or_edge_lines']+=1
                    for u in (-street.width*.225,street.width*.225):
                        strip(mesh,'street_white',a-offset+n0*u,b-offset+n1*u,.10,surface,.027)
                elif strip(mesh,which_paint,a-offset,b-offset,.105,surface,.027):
                    stats['center_or_edge_lines']+=1
                if highway:
                    end=uv_frame(line,min(s0+span,line.length))
                    if not junctions.query(Point(end[0]),predicate='dwithin',distance=12).size:
                        for side in (-1,1):
                            off=side*(street.width/2-.34)
                            strip(mesh,'street_white',a-offset+n0*off,end[0]-offset+end[2]*off,.115,surface,.023)
        for s in np.arange(6+rng.uniform(0,17),line.length-3,27 if highway else 21):
            p,t,n=uv_frame(line,s)
            if bbox_of(p)!=tuple(offset):
                continue
            side=rng.choice((-1,1))
            q=p-offset+n*side*(street.width*.50-.62)
            probability=rng.random()
            if probability<.42:
                crack(mesh,surface,q,t*rng.choice((-1,1)),rng.uniform(.65,1.65),rng)
                stats['road_cracks']+=1
            elif probability<.78:
                size=rng.uniform(.37,1.9)
                a=q-n*side*.43
                poly=corners(a,t,n,size,.45)
                if contains(surface,poly):
                    paint_quad(mesh,rng.choice(('asphalt_patch','asphalt_fade')),poly,surface,.011)
                    stats['patched_areas']+=1
            elif probability<.922:
                a=q-n*side*1.10
                if disc(mesh,'street_iron',surface,a,.32,.32,rng,.022,False,'iron_dark'):
                    stats['manholes']+=1
                    for u in (-.15,0,.15):
                        strip(mesh,'iron_dark',a+t*u-n*.23,a+t*u+n*.23,.024,surface,.024)
                    for u in (-.12,.12):
                        strip(mesh,'iron_dark',a+n*u-t*.23,a+n*u+t*.23,.018,surface,.025)
            elif not highway:
                a=q-n*side*.26
                if disc(mesh,'pothole',surface,a,.23,.36,rng,.019,True,'hole_edge'):
                    stats['potholes']+=1


def cross_sections(views,road,walk,offset,dem,markings,ramps,collision,stats):
    cutouts=[]
    accepted=[]
    corner_landings=defaultdict(list)
    for q,t,width,one_way,center in views:
        n=np.array([-t[1],t[0]])
        p=q-offset
        positions=[]
        # Shrink from the mapped shoulder if the rendered edge tapers at a corner.
        for side in (-1,1):
            far=next((dist for dist in np.arange(width*.49,max(.85,width*.31),-.13)
                     if contains(road,np.array([p+n*side*dist+t*dt for dt in (-1.11,0,1.11)]))),None)
            if far is None: break
            positions.append(far)
        if len(positions)!=2:
            continue
        left,right=positions
        rng=random.Random(seed(tuple(center))+int(q[0]*5)+int(q[1]*7))
        for x in np.arange(-left+.23,right-.17,.83):
            u=p+n*x
            poly=corners(u,t,n,1.02,rng.uniform(.228,.26))
            if contains(road,poly):
                paint_quad(markings,'street_white',poly,road,.026)
        stats['crosswalks']+=1
        accepted.append(tuple(center))
        # Traffic approaches toward the intersection, with the stop bar outside the crosswalk.
        stop=p+t*1.77
        upstream_edge=right if one_way else -.12
        if strip(markings,'street_white',stop+n*upstream_edge,stop-n*left,.31,road,.028):
            stats['stop_bars']+=1
        for side,dist in ((-1,left),(1,right)):
            out=n*side
            start=p+out*(dist-.06)
            end=start+out*1.52
            if walk is not None:
                q_end=Point(p+out*(dist+1.30))
                i=walk.index.nearest(q_end)
                poly=walk.polygons[i] if i is not None else None
                if poly is not None and poly.distance(q_end)<1.35:
                    closest=poly.boundary.interpolate(poly.boundary.project(q_end))
                    end=np.asarray(closest.coords[0])
                    direction=end-start
                    if direction@out<.8 or abs(direction@t)>.57 or np.linalg.norm(direction)>3.4:
                        end=start+out*1.52
            a,b = start-t*.76,start+t*.76
            c,d = end+t*.76,end-t*.76
            road_y=road.heights(np.array([a,b]))+.012
            works=walk is not None and contains(walk,[c,d])
            top=walk.heights(np.asarray([c,d]))+.101 if works else dem(*(np.asarray([c,d])+offset).T)+.189
            top=np.clip(top,road_y+.046,road_y+.16)
            coords=np.array([a,b,c,d])
            heights=np.asarray([*road_y,*top])
            if (end-start)@out<.5:
                continue
            faces=[0,1,2,0,2,3] if np.linalg.det(np.asarray(
                [(b-a),(c-a)])) <0 else [0,2,1,0,3,2]
            xyz=np.column_stack((coords[:,0],heights,coords[:,1]))
            for mesh in (ramps,collision):
                mesh.add('ramp_concrete',xyz,faces,normals=[(0,1,0)]*4)
            mark=[a+(d-a)*.20,b+(c-b)*.20,b+(c-b)*.46,a+(d-a)*.46]
            ym=[heights[0]*.8+heights[3]*.2,heights[1]*.8+heights[2]*.2,
                heights[1]*.54+heights[2]*.46,heights[0]*.54+heights[3]*.46]
            ramps.add('warning_mat',np.column_stack((np.asarray(mark)[:,0],np.asarray(ym)+.009,np.asarray(mark)[:,1])),
                      faces,normals=[(0,1,0)]*4)
            if not works:
                # Small landing where the GIS sidewalk inventory omits a curb return.
                far = end+out*.69
                points2=np.array([d,c,far+t*.76,far-t*.76])
                y=np.r_[top,dem(*(points2[2:]+offset).T)+.13]
                corner_landings[tuple(center)].append((far,t))
                for mesh in (ramps,collision):
                    mesh.add('ramp_concrete',np.column_stack((points2[:,0],y,points2[:,1])),faces,
                             normals=[(0,1,0)]*4)
            cutouts.append(LineString([start,end+out*.36]).buffer(.87,cap_style='flat'))
            stats['curb_ramps']+=1
            if side==1:
                pp=start-out*.21+t*3.1
                if contains(road,corners(pp,t,out,.25,.185)):
                    paint_quad(ramps,'street_iron',corners(pp,t,out,.25,.185),road,.020)
                    for j in np.linspace(-.18,.18,5):
                        strip(ramps,'iron_dark',pp+t*j-out*.149,pp+t*j+out*.149,.040,road,.023)
                    stats['storm_drains']+=1
    for landings in corner_landings.values():
        connect_corner_slabs(landings,road,offset,dem,ramps,collision,stats)
    return cutouts,accepted


def connect_corner_slabs(landings, road, origin, dem, visual, collision, stats):
    candidates=[]
    for i,(a,ta) in enumerate(landings):
        for j,(b,tb) in enumerate(landings[:i]):
            gap=np.linalg.norm(b-a)
            if abs(ta@tb)<.86 and 1.1<gap<12:
                candidates.append((gap,i,j))
    joined=set()
    for length,i,j in sorted(candidates):
        if i in joined or j in joined:
            continue
        a,b=landings[i][0],landings[j][0]
        t=(b-a)/length
        n=np.array([-t[1],t[0]])
        mid=(a+b)/2
        footprint=Polygon(corners(mid,t,n,length/2,.54))
        if sum(footprint.intersection(road.polygons[i]).area for i in
               road.index.query(footprint,predicate='intersects'))>.09:
            continue
        joined.update((i,j))
        count=max(1,round(length/1.6))
        for u,v in zip(np.linspace(0,1,count+1),np.linspace(0,1,count+1)[1:]):
            center=a+(b-a)*(u+v)/2
            points2=corners(center,t,n,(v-u)*length/2-.012,.54)
            y=dem(*(points2+origin).T)+.13
            xyz=np.column_stack((points2[:,0],y,points2[:,1]))
            for mesh in (visual,collision):
                mesh.add('ramp_concrete',xyz,[0,1,2,0,2,3],normals=[(0,1,0)]*4)
        stats['corner_walks']+=1


def sidewalk_variation(walk, mesh, collision, stats):
    rng=random.Random(3021)
    for shape in walk.outlines():
        if shape.area<2:
            continue
        line=LineString(shape.exterior.coords)
        for station in np.arange(3.5+rng.uniform(0,12),line.length-1,6.3):
            p,t,n=uv_frame(line,station,.52)
            q=p+n*.39
            if not intersects_xy(shape,*q): continue
            poly=corners(q,t,n,1.34,.31)
            if not all(intersects_xy(shape,*poly.T)): continue
            lifted=rng.random()<.039
            if lifted:
                y=walk.heights(poly)+np.asarray([.104,.106,.146,.132])
                mesh.add('old_slab',np.column_stack((poly[:,0],y,poly[:,1])),[0,1,2,0,2,3],
                         normals=[(0,1,0)]*4)
                collision.add('old_slab',np.column_stack((poly[:,0],y,poly[:,1])),[0,1,2,0,2,3],
                              normals=[(0,1,0)]*4)
                stats['lifted_slabs']+=1
                continue
            paint_quad(mesh,rng.choice(('new_slab','old_slab')),poly,walk,.106)
            stats['varied_slabs']+=1
            if rng.random()<.58:
                crack(mesh,walk,q-t*.68,n,.49,rng,'fissure',.112)
            if rng.random()<.13:
                xy=q+t*1.28
                y=walk.heights([xy])[0]+.101
                for angle in (0,2.1,4.2):
                    dx,dz=.15*np.array([math.cos(angle),math.sin(angle)])
                    x,z=xy
                    pts=[(x-.015,y,z),(x+.012,y,z),(x+dx,y+rng.uniform(.08,.17),z+dz)]
                    mesh.add('street_grass',pts,[0,1,2,2,1,0])
                stats['seam_weeds']+=1


def oil_wear(mesh,surface,sites,offset,stats):
    rng=random.Random(seed(tuple(offset))+31)
    for p,t,w in sites:
        q=p-offset
        n=np.array([-t[1],t[0]])
        q+=n*w*.54
        if not contains(surface,[q]): continue
        if rng.random()<.62 and disc(mesh,'oil',surface,q,rng.uniform(.10,.30),rng.uniform(.14,.51),rng,.018):
            for _ in range(2):
                disc(mesh,'tire',surface,q+t*rng.uniform(-.52,.83)+n*rng.uniform(-.32,.38),.08,.14,rng,.019)
            stats['oil_spots']+=1
        if rng.random()<.35:
            for lane in (-.48,.48):
                a=q+n*lane
                strip(mesh,'tire',a-t*1.1,a+t*rng.uniform(.24,1.65),.095,surface,.015)
            stats['tire_tracks']+=1


class Furniture:
    def __init__(self, mesh, point, front, height):
        self.mesh = mesh
        self.point = point
        self.front = front
        self.side = np.array([-front[1],front[0]])
        self.height = height

    def xy(self, x, z):
        return self.point+x*self.side+z*self.front

    def prism(self,mat,x,z,y,w,d,h):
        pts = [self.xy(x+a,z+b) for a,b in
               [(-w/2,-d/2),(w/2,-d/2),(w/2,d/2),(-w/2,d/2)]]
        y+=self.height
        self.mesh.quad(mat,[(a,y+h,b) for a,b in pts])
        self.mesh.quad(mat,[(a,y,b) for a,b in reversed(pts)])
        for i,p in enumerate(pts):
            a,b=p
            c,d=pts[(i+1)%len(pts)]
            self.mesh.quad(mat,[(a,y,b),(c,y,d),(c,y+h,d),(a,y+h,b)])

    def circle(self,mat,x,z,start,end,r1,r2,sides=8):
        a,b=self.xy(x,z)
        cylinder(self.mesh,mat,a,b,self.height+start,self.height+end,r1,r2,sides)

    def panel(self,mat,x,z,y,w,h,uv=None):
        pts=[self.xy(a,z) for a in (x+w/2,x-w/2)]
        p,q=pts
        y+=self.height
        self.mesh.quad(mat,[(p[0],y,p[1]),(q[0],y,q[1]),(q[0],y+h,q[1]),(p[0],y+h,p[1])],uv)


def model_furniture(mesh, kind, p, t, h, value):
    f=Furniture(mesh,p,t,h)
    block=f.prism
    shape=f.circle
    if kind=='speed':
        block('street_post',0,-.029,0,.061,.047,2.33)
        block('street_post',0,0,1.66,.54,.035,.68)
        index = {25:0,35:1,45:2}[value]
        a,b=(index+.022)/3,(index+.978)/3
        f.panel('speed_face',0,.021,1.66,.536,.676,[(a,.982),(b,.982),(b,.018),(a,.018)])
    elif kind=='pole':
        shape('street_wood',0,0,-.07,8.25,.165,.095)
        shape('wood_end',0,0,8.24,8.3,.095,.09)
        block('street_wood',0,0,7.90,1.87,.15,.13)
        for x in (-.78,0,.78):
            shape('street_post',x,0,8.02,8.16,.045,.039,6)
            shape('iron_dark',x,0,8.16,8.23,.048,.033,6)
    elif kind=='hydrant':
        shape('hydrant',0,0,-.05,.068,.183,.182)
        shape('hydrant',0,0,.064,.71,.131,.124)
        shape('hydrant_bonnet',0,0,.70,.87,.154,.081)
        shape('street_iron',0,0,.87,.93,.055,.046,6)
        block('hydrant',0,0,.30,.47,.158,.135)
        block('hydrant',0,.15,.28,.112,.14,.185)
        block('hydrant_bonnet',0,.223,.32,.10,.025,.13)
    elif kind=='mailbox':
        block('street_wood',0,0,-.07,.105,.105,1.07)
        block('mail_blue',0,0,.94,.30,.49,.27)
        block('mail_blue',0,-.012,1.21,.223,.465,.064)
        block('street_post',0,.250,.98,.24,.016,.185)
        block('hydrant',.16,-.04,1.13,.026,.042,.14)
    elif kind=='news':
        block('news_burgundy',0,0,-.025,.51,.48,1.11)
        block('news_burgundy',0,.011,1.085,.55,.51,.08)
        block('news_window',0,.25,.71,.37,.025,.25)
        block('news_paper',0,.267,.729,.31,.012,.13)
        block('street_post',0,.259,.655,.228,.040,.044)
    elif kind=='bin':
        shape('bin_green',0,0,-.02,.92,.227,.263)
        shape('iron_dark',0,0,.916,1.01,.271,.204)
        block('iron_dark',0,.202,.84,.29,.076,.112)
        for x in (-.15,.15):
            shape('street_iron',x,0,.025,.117,.071,.071,6)
    elif kind=='light':
        shape('street_iron',0,0,-.04,.16,.16,.135)
        shape('street_post',0,0,.16,7.1,.096,.048)
        block('street_post',0,.71,6.99,.072,1.48,.077)
        block('signal_box',0,1.47,6.93,.27,.53,.129)
        block('lamp_lens',0,1.50,6.915,.21,.32,.027)
    elif kind=='signal':
        shape('street_post',0,0,-.09,5.65,.145,.09)
        block('street_post',-1.97,0,5.56,4.09,.13,.14)
        for x in (-2.25,-3.83):
            block('signal_box',x,0,4.62,.34,.235,.92)
            block('signal_amber',x,.124,4.66,.294,.036,.82)
            for i,color in enumerate(('signal_green','signal_amber','signal_red')):
                y=4.74+.25*i
                block('signal_visors',x,.21,y,.245,.18,.21)
                block(color if (color==('signal_green' if value else 'signal_red')) else 'lens_off',
                      x,.317,y+.019,.169,.042,.164)
        block('street_post',0,-.15,.52,.37,.28,.55)


def cables(mesh, origin, runs, walk, dem, stats):
    for a,ta,b,tb in runs:
        n1,n2=[np.array([-t[1],t[0]]) for t in (ta,tb)]
        y1,y2 = float(dem(*a))+8.19,float(dem(*b))+8.19
        if walk is not None:
            for p in [a,b]:
                if contains(walk,[p-origin]):
                    py=walk.heights([p-origin])[0]+.101+8.19
                    if np.all(a==p):
                        y1=py
                    else:
                        y2=py
        for j in (-.78,0,.78):
            aa,bb = a+n1*j-origin,b+n2*j-origin
            distance=np.linalg.norm(bb-aa)
            if not 3<distance<65:
                continue
            path=np.array([(p[0],y1*(1-u)+y2*u-(.70+distance*.009)*4*u*(1-u),p[1])
                           for u in np.linspace(0,1,6) for p in [aa*(1-u)+bb*u]])
            for p,q in zip(path,path[1:]):
                for r in ([0,.0105,0],):
                    v=np.asarray(r)
                    mesh.add('wire',[p-v,q-v,q+v,p+v],[0,1,2,0,2,3,0,2,1,0,3,2])
        stats['cable_spans']+=1


def atlas():
    path=RES/'speed_signs.png'
    img=Image.new('RGB',(384,160),(214,216,207))
    draw=ImageDraw.Draw(img)
    font='/usr/share/fonts/truetype/liberation2/LiberationSans-Bold.ttf'
    if not Path(font).is_file():
        font='/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'
    for i,value in enumerate([25,35,45]):
        x=i*128
        draw.rounded_rectangle((x+4,4,x+123,155),radius=10,outline=(30,32,32),width=4)
        for word,y,size in [('SPEED',30,24),('LIMIT',57,24),(str(value),108,68)]:
            draw.text((x+64,y),word,font=ImageFont.truetype(font,size),anchor='mm',fill=(18,20,22))
    img.save(path)
    return path


def inject_sign_uv(path, mesh):
    doc,data=read_container(path.read_bytes())
    if 'speed_face' not in mesh.parts:
        return
    index=next(i for i,m in enumerate(doc['materials']) if m['name']=='speed_face')
    primitive=next(p for p in doc['meshes'][0]['primitives'] if p['material']==index)
    uv=np.asarray(mesh.parts['speed_face'][2],dtype='<f4')
    view=len(doc['bufferViews'])
    doc['bufferViews'].append(dict(buffer=0,byteOffset=len(data),byteLength=uv.nbytes,target=34962))
    data.extend(uv.tobytes())
    primitive['attributes']['TEXCOORD_0']=len(doc['accessors'])
    doc['accessors'].append(dict(bufferView=view,componentType=5126,count=len(uv),type='VEC2'))
    doc['buffers'][0]['byteLength']=len(data)
    write_container(path,doc,data)


def trim_layer(path, original, road_filter=None, ramps=None):
    doc,data=read_container(original)
    cut_geom=unary_union(ramps) if ramps else None
    triangles_kept=0

    def accessor(index, dtype, width):
        spec=doc['accessors'][index]
        view=doc['bufferViews'][spec['bufferView']]
        return (np.frombuffer(data,dtype,count=spec['count']*width,
                              offset=view.get('byteOffset',0)+spec.get('byteOffset',0)).reshape(-1,width),spec,view)

    for node in doc['nodes']:
        if 'mesh' not in node:
            continue
        mesh=doc['meshes'][node['mesh']]
        offset=np.array(node.get('translation',[0,0,0]))[[0,2]]
        primitives=[]
        for primitive in mesh['primitives']:
            name=doc['materials'][primitive['material']]['name']
            idx,spec,view=accessor(primitive['indices'],'<u4',1)
            idx=idx.reshape(-1,3)
            keep=np.ones(len(idx),dtype=bool)
            if ramps is not None and name=='crosswalk':
                keep[:]=False
            if road_filter is not None or (cut_geom is not None and name=='curb'):
                coords,_,_=accessor(primitive['attributes']['POSITION'],'<f4',3)
                tri=coords[idx][:,:,[0,2]]+offset
                middles=tri.mean(axis=1)
                if road_filter is not None:
                    # Repaint local street centers; leave airfield and highway paint intact.
                    keep &= ~intersects_xy(road_filter,*middles.T)
                else:
                    keep &= ~intersects_xy(cut_geom,*middles.T)
            result=idx[keep].ravel()
            if len(result):
                idx.ravel()[:len(result)]=result
                spec['count']=len(result)
                view['byteLength']=result.nbytes
                triangles_kept+=len(result)//3
                primitives.append(primitive)
        if primitives:
            mesh['primitives']=primitives
        else:
            del node['mesh']
    used={n['mesh'] for n in doc['nodes'] if 'mesh' in n}
    translate={old:new for new,old in enumerate(sorted(used))}
    doc['meshes']=[v for i,v in enumerate(doc['meshes']) if i in used]
    for node in doc['nodes']:
        if 'mesh' in node:
            node['mesh']=translate[node['mesh']]
    if triangles_kept:
        write_container(path,doc,data)
    else:
        path.unlink(missing_ok=True)
    return triangles_kept


def configure_import(path, materials):
    file=path.with_suffix('.glb.import')
    if file.exists():
        source=file.read_text()
    else:
        sample=ROOT/'tiles'/'+00_+00'/'Markings.glb.import'
        source=sample.read_text()
        old='res://tiles/+00_+00/Markings.glb'
        new='res://'+path.relative_to(ROOT).as_posix()
        source=re.sub(r'^uid=.*\n','',source,flags=re.M)
        source=source.replace(old,new).replace(
            'Markings.glb-'+hashlib.md5(old.encode()).hexdigest(),
            path.name+'-'+hashlib.md5(new.encode()).hexdigest())
    m=re.search(r'_subresources=(\{.*?\})\s*\ngltf/',source,re.S)
    data=json.loads(m.group(1))
    entries=data.setdefault('materials',{})
    for key,resource in materials.items():
        entries[key]={'use_external/enabled':True,'use_external/path':resource,'use_external/fallback_path':resource}
    source=source[:m.start(1)]+json.dumps(data,indent=0)+source[m.end(1):]
    file.write_text(source)


def configure_ground(folder):
    asphalt={'asphalt':'asphalt_street','service':'asphalt_local'}
    for filename,variants in [('Roads.glb',asphalt),('Sidewalks.glb',{'walk':'concrete_walk'}),
                              ('LandCover.glb',{'lot':'asphalt_lot'})]:
        file=folder/filename
        if not file.exists():
            continue
        imported=file.with_suffix('.glb.import')
        old=imported.read_text()
        replacements={}
        for key,value in variants.items():
            if not re.search(r'"'+key+r'"\s*:',old):
                continue
            if filename=='Roads.glb' and re.search(r'"'+key+r'":\s*{[^}]*road_edges/',old):
                # The tuned curb-edge distance remains active on its original tiles.
                continue
            replacements[key]='res://materials/street_realism/'+value+'.tres'
        if replacements:
            configure_import(file,replacements)


def connect_scene(path, visible, removed):
    src=path.read_text().rstrip()
    tile=path.parent.name
    for name in removed:
        res=next(r for r in src.splitlines() if f'/{name}.glb"' in r)
        idx=re.search(r'id="([^"]+)"',res)[1]
        src=src.replace(res+'\n','').replace(f'[node name="{name}" parent="." instance=ExtResource("{idx}")]', '')
    resources='\n'.join(f'[ext_resource type="PackedScene" path="res://tiles/{tile}/{name}.glb" id="streets_{i}"]'
                        for i,name in enumerate(visible))
    nodes='\n\n'.join(f'[node name="{name}" parent="." instance=ExtResource("streets_{i}")]'
                          for i,name in enumerate(visible))
    if visible:
        src=src.replace('\n[node name=', '\n'+resources+'\n\n[node name=',1)+'\n\n'+nodes
    path.write_text(src+'\n')


def regularize_downtown_road(path, dem):
    """Break up long diagonal grade interpolation on the original downtown pavement."""
    doc,data=read_container(path.read_bytes())
    plate=box(183,285,605,465)

    def read(index,width,dtype):
        entry=doc['accessors'][index]
        view=doc['bufferViews'][entry['bufferView']]
        return np.frombuffer(data,dtype,offset=view.get('byteOffset',0)+entry.get('byteOffset',0),
                             count=entry['count']*width).reshape(-1,width).copy()

    def append(values,code,kind,target):
        view=len(doc['bufferViews'])
        attrs=dict(bufferView=view,count=len(values),componentType=code,type=kind)
        if kind=='VEC3' and code==5126 and target==34962:
            attrs.update(min=values.min(axis=0).tolist(),max=values.max(axis=0).tolist())
        doc['bufferViews'].append(dict(buffer=0,byteOffset=len(data),byteLength=values.nbytes,target=target))
        data.extend(values.tobytes())
        doc['accessors'].append(attrs)
        return len(doc['accessors'])-1

    def conform(tris):
        pending=[]
        for tri in tris:
            footprint=Polygon(tri[:,[0,2]])
            if plate.intersects(footprint) and footprint.area>.001:
                pending.append(tri.astype(float))
            else:
                yield tri
        for depth in range(3):
            working=pending
            pending=[]
            for xyz in working:
                for_coords=xyz[:,[0,2]]
                mid=(xyz+np.roll(xyz,-1,axis=0))/2
                mids=mid[:,[0,2]]
                goal=dem(*mids.T)+.086
                delta=abs(goal-mid[:,1])
                segment=np.linalg.norm(for_coords-np.roll(for_coords,-1,axis=0),axis=1)
                split=(delta>.052)&(segment>4.7)
                center=xyz.mean(axis=0)
                cy=float(dem(center[0],center[2]))+.086
                if not split.any() and (abs(cy-center[1])<.074 or segment.max()<4.7):
                    yield xyz
                    continue
                mid[:,1]=goal
                center[1]=cy
                rim=[]
                for k in range(3):
                    rim.append(xyz[k])
                    if split[k]:
                        rim.append(mid[k])
                for a,b in zip(rim,rim[1:]+rim[:1]):
                    tri=np.asarray([center,a,b])
                    if depth<2:
                        pending.append(tri)
                    else:
                        yield tri

    count=0
    fixed=0
    for chunk in doc['meshes']:
        for item in chunk['primitives']:
            indices=read(item['indices'],1,'<u4').reshape(-1,3)
            material=doc['materials'][item['material']]['name']
            if material not in ('asphalt','service'):
                count+=len(indices)
                continue
            positions=read(item['attributes']['POSITION'],3,'<f4')
            initial=len(indices)
            triangles=np.asarray(list(conform(positions[indices])),dtype='<f4')
            count+=len(triangles)
            fixed+=len(triangles)-initial
            verts,indices=np.unique(triangles.reshape(-1,3),axis=0,return_inverse=True)
            directions=np.tile(np.array([0,1,0],dtype='<f4'),(len(verts),1))
            item['attributes']={'POSITION':append(verts,5126,'VEC3',34962),
                                'NORMAL':append(directions,5126,'VEC3',34962)}
            item['indices']=append(indices.astype('<u4'),5125,'SCALAR',34963)
    doc['buffers'][0]['byteLength']=len(data)
    write_container(path,doc,data)
    return count,fixed


def process_tile(row):
    folder=ROOT/'tiles'/row['id']
    origin=np.array([row['x'],row['z']])
    key=tuple(origin)
    stats=Counter()
    marks=Mesh()
    detail=Mesh()
    ramp_collision=Mesh()
    wires=Mesh()
    furniture=defaultdict(list)
    walk=Surface(folder/'Sidewalks.glb') if (folder/'Sidewalks.glb').exists() else None
    updated={}
    if row['id']=='+00_+00':
        updated['Roads'],stats['grade_refinement_triangles']=regularize_downtown_road(folder/'Roads.glb',BASE['dem'])
    selected=BASE['street_tiles'].get(key,[])
    crossing=BASE['cross_tiles'].get(key,[])
    cutouts=[]
    if selected and (folder/'Roads.glb').exists():
        surface=Surface(folder/'Roads.glb',ignored=('highway','gravel'))
        if surface.polygons:
            junctions=STRtree([Point(c[-1]) for c in crossing])
            center_marks_and_wear(marks,selected,surface,origin,junctions,stats)
            cutouts,accepted=cross_sections(crossing,surface,walk,origin,BASE['dem'],marks,detail,ramp_collision,stats)
            stats['intersections_reached']=len(set(accepted))
            oil_wear(detail,surface,BASE['oil_tiles'].get(key,[]),origin,stats)
    if walk is not None:
        sidewalk_variation(walk,detail,ramp_collision,stats)
    for name,p,t,value in BASE['prop_tiles'].get(key,[]):
        xy=p-origin
        h=float(BASE['dem'](*p))
        if walk is not None and contains(walk,[xy]):
            h=walk.heights([xy])[0]+.100
        tag=name+str(value) if name in ('speed','signal') else name
        yaw=math.atan2(t[0],t[1])
        furniture[tag].append([round(float(x),3) for x in (xy[0],h,xy[1],yaw,1)])
        stats[name]+=1
        if name=='speed':
            stats[f'speed_{value}']+=1
    cables(wires,origin,BASE['cable_tiles'].get(key,[]),walk,BASE['dem'],stats)
    (folder/'StreetFurniture.json').write_text(json.dumps(furniture,separators=(',',':')))
    old_path=folder/'instances.json'
    if old_path.exists():
        old=json.loads(old_path.read_text())
        previous=json.dumps(old)
        for former,kind,radius in [('streetlight','light',20),('traffic_signal','signal',23),
                                   ('utility_pole','pole',13)]:
            if former not in old or kind not in furniture and kind!='signal':
                continue
            rows=[q for k,batch in furniture.items() if k.startswith(kind) for q in batch]
            new=STRtree([Point(q[0],q[2]) for q in rows])
            old[former]=[r for r in old[former] if not new.query(Point(r[0],r[2]),predicate='dwithin',distance=radius).size]
        if json.dumps(old)!=previous:
            old_path.write_text(json.dumps(old,separators=(',',':')))
    visible=[]
    pairs=[('StreetPaint',marks),('StreetWear',detail),('StreetWires',wires),('StreetRampCollision',ramp_collision)]
    for name,mesh in pairs:
        path=folder/(name+'.glb')
        writer=write_glb if name=='StreetRampCollision' else write_detail
        if not writer(path,name,mesh):
            continue
        updated[name]=mesh.triangles()
        if name!='StreetRampCollision':
            visible.append(name)
            bindings={mat:'res://materials/street_realism/'+res+'.tres' for mat,res in PAINT.items() if mat in mesh.parts}
            if bindings:
                configure_import(path,bindings)
    mask = unary_union([s.line.intersection(box(*(origin-20),*(origin+2020))).buffer(
                         s.width*.41,quad_segs=2) for s in selected if s.kind in MAJOR])
    from shapely.affinity import translate
    mask=translate(mask,xoff=-origin[0],yoff=-origin[1])
    removed=[]
    edges=folder/'StreetEdges.glb'
    marks_path=folder/'Markings.glb'
    if edges.exists():
        updated['StreetEdges']=trim_layer(edges,edges.read_bytes(),ramps=cutouts)
    if marks_path.exists() and not mask.is_empty:
        updated['Markings']=trim_layer(marks_path,marks_path.read_bytes(),road_filter=mask)
    for name in ('StreetEdges','Markings'):
        if name in updated and not updated[name]:
            removed.append(name)
            (folder/(name+'.glb.import')).unlink(missing_ok=True)
    connect_scene(folder/'district.tscn',visible,removed)
    configure_ground(folder)
    return row['id'],updated,stats


def group_assets(rows,key):
    result=defaultdict(list)
    for row in rows:
        result[bbox_of(key(row))].append(row)
    return result


def generate_kit():
    output=ROOT/'assets'/'street_realism'
    output.mkdir(exist_ok=True)
    variants=[('speed',v) for v in (25,35,45)]+[('signal',v) for v in (0,1)]
    variants += [(name,0) for name in ('hydrant','mailbox','news','bin','light','pole')]
    for kind,value in variants:
        ident=kind+str(value) if kind in ('speed','signal') else kind
        mesh=Mesh()
        model_furniture(mesh,kind,np.zeros(2),np.array([0,1]),0,value)
        path=output/(ident+'.glb')
        write_glb(path,ident,mesh)
        if kind=='speed':
            inject_sign_uv(path,mesh)
            configure_import(path,{'speed_face':'res://materials/street_realism/speed_sign.tres'})


def main():
    RES.mkdir(parents=True,exist_ok=True)
    atlas()
    generate_kit()
    root=ROOT/'manifest.json'
    manifest=json.loads(root.read_text())
    source=read_features('osm_local.geojson.gz')
    rows=manifest['tiles']
    hidden={f'osm:way:{i}' for i in manifest['elevated_highway']['upgraded_osm_ways']}
    dem=Elevation(ROOT/'source'/'3dep_float.tif')
    add_global(source,hidden,dem)
    print('Street plan',len(STREETS),len(CROSSINGS),len(PROPS),len(CABLES),flush=True)
    tree=STRtree([s.line for s in STREETS])
    streets_by_tile={}
    for row in rows:
        x,z=row['x'],row['z']
        streets_by_tile[x,z]=[STREETS[i] for i in tree.query(box(x-10,z-10,x+2010,z+2010),predicate='intersects')]
    BASE.update(dem=dem,street_tiles=streets_by_tile,
                cross_tiles=group_assets(CROSSINGS,lambda r:r[0]),oil_tiles=group_assets(OIL_SITES,lambda r:r[0]),
                prop_tiles=group_assets(PROPS,lambda r:r[1]),cable_tiles=group_assets(CABLES,lambda r:(r[0]+r[2])/2))
    by_id={row['id']:row for row in rows}
    reports={}
    with ProcessPoolExecutor(max_workers=5) as pool:
        for tile,updated,stats in pool.map(process_tile,rows):
            row=by_id[tile]
            for name,count in updated.items():
                if not count:
                    row['layers'].pop(name,None)
                else:
                    row['layers'][name]=dict(file=f'tiles/{tile}/{name}.glb',triangles=count)
            old=ROOT/'tiles'/tile/'instances.json'
            if old.exists():
                row['instances']=sum(map(len,json.loads(old.read_text()).values()))
            reports[tile]=dict(stats)
            print(tile, dict(stats),flush=True)
    manifest['street_realism']=dict(scope='public at-grade streets and sidewalks', districts=reports,
                                  features_planned=len(CROSSINGS),
                                  mapped_junctions=len({tuple(c[-1]) for c in CROSSINGS}), totals=dict(sum((Counter(stats) for stats in reports.values()),Counter())))
    root.write_text(json.dumps(manifest,indent=2)+'\n')


if __name__=='__main__':
    main()
