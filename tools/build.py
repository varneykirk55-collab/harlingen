"""Build the offline Harlingen scene, tile meshes, collision and asset inventory."""
from collections import Counter, defaultdict
from pathlib import Path
import gzip
import hashlib
from io import BytesIO
import multiprocessing
import json
import math
import random
import re
import shutil
import sys

import mapbox_earcut
import numpy as np
from PIL import Image, ImageDraw
from shapely.geometry import LineString, Point, Polygon, box, shape
from shapely.geometry.polygon import orient
from shapely.ops import unary_union
from shapely.strtree import STRtree

from landmark import BAXTER_ID, BAXTER_NPS, baxter
from vegetation import kit_meshes
from road_grade import is_bridge
from geographic_sites import (attach_sites, corrected_features, district_register, label_position,
                              labels_by_tile, write_tile_sites)
from mesh import Mesh, PALETTE, box as mesh_box, cylinder, facade_atlas, write_glb

ROOT=Path(__file__).resolve().parents[1]
TILE_SIZE=2000
HALF_EXTENT=6000
GAP=.10
ROAD_SPEC = {
    'motorway': (10.8,'highway'), 'trunk': (11,'highway'), 'primary': (10.4,'asphalt'),
    'secondary': (9.4,'asphalt'), 'tertiary': (8.1,'asphalt'), 'unclassified': (7.0,'asphalt'),
    'residential': (6.9,'asphalt'), 'living_street': (6,'asphalt'), 'service': (4.6,'service'),
    'track': (3,'gravel'), 'pedestrian': (3,'walk'), 'footway': (1.5,'walk'),
    'cycleway': (2.5,'walk'), 'path': (1.5,'gravel'), 'steps': (1.5,'walk'), 'crossing': (1.7,'walk')
}
VEHICLE=set(list(ROAD_SPEC)[:9])
TREE_AREAS={'grass','woodland'}


def read_features(filename):
    with gzip.open(ROOT/'source'/filename,'rt') as f:
        return [(shape(row['geometry']),row['properties'],row['id']) for row in json.load(f)['features']]


def parts(geom, kind):
    if geom.is_empty:
        return
    if geom.geom_type==kind:
        yield geom
    elif hasattr(geom,'geoms'):
        for child in geom.geoms:
            yield from parts(child,kind)


def tagged_number(value):
    if value is None:
        return None
    match=re.fullmatch(r'\s*(\d+(?:\.\d+)?)\s*(m|ft|\'|feet)?\s*',str(value))
    if not match:
        return None
    return float(match[1]) * (.3048 if match[2] in ('ft',"'",'feet') else 1)


def seed(value):
    return int.from_bytes(hashlib.blake2b(str(value).encode(),digest_size=8).digest(),'little')


class Elevation:
    def __init__(self, source):
        self.data=np.asarray(Image.open(source),dtype=np.float32)
        if self.data.shape!=(2401,2401) or not np.isfinite(self.data).all():
            raise ValueError('Unexpected 3DEP raster dimensions or voids')
        if self.data.min() < -100 or self.data.max()>300:
            raise ValueError('Unexpected Harlingen elevations')

    def __call__(self,x,z):
        gx=np.clip((np.asarray(x)+HALF_EXTENT)/5,0,2400)
        gz=np.clip((np.asarray(z)+HALF_EXTENT)/5,0,2400)
        ix,iz=gx.astype(int),gz.astype(int)
        jx,jz=np.minimum(ix+1,2400),np.minimum(iz+1,2400)
        xf,zf=gx-ix,gz-iz
        return (1-zf)*((1-xf)*self.data[iz,ix]+xf*self.data[iz,jx])+zf*((1-xf)*self.data[jz,ix]+xf*self.data[jz,jx])


def patch(mesh, geometry, material, ground, dx=0,dz=0,step=0):
    for poly in parts(geometry,'Polygon'):
        if poly.area<.015:
            continue
        if step:
            poly=poly.segmentize(step)
        loops=[np.asarray(r.coords)[:-1] for r in [poly.exterior,*poly.interiors]]
        flat=np.concatenate(loops)
        tri=mapbox_earcut.triangulate_float64(flat,np.cumsum([len(r) for r in loops],dtype=np.uint32))
        if not len(tri):
            continue
        tri=tri.reshape(-1,3)
        vec1,vec2=flat[tri[:,1]]-flat[tri[:,0]],flat[tri[:,2]]-flat[tri[:,0]]
        flip=vec1[:,0]*vec2[:,1]-vec1[:,1]*vec2[:,0]>0
        tri[flip]=tri[flip,::-1]
        x,z=flat.T
        y=ground(x,z)+np.zeros_like(x)
        mesh.add(material,np.column_stack((x-dx,y,z-dz)),tri,normals=[(0,1,0)]*len(x))


def ground_grid(mesh,x,z,res,dem):
    steps=np.linspace(0,TILE_SIZE,round(TILE_SIZE/res)+1)
    u,v=np.meshgrid(steps,steps)
    y=dem(u+x,v+z)-GAP
    dz,dx=np.gradient(y,steps,steps)
    normals=np.stack((-dx,np.ones_like(y),-dz),axis=-1).reshape(-1,3)
    normals/=np.linalg.norm(normals,axis=1)[:,None]
    n=len(steps)
    a=np.arange(n*n).reshape(n,n)[:-1,:-1].ravel()
    triangles=np.column_stack((a,a+n,a+1,a+1,a+n,a+n+1))
    mesh.add('ground',np.column_stack((u.ravel(),y.ravel(),v.ravel())),triangles,normals=normals)


def road_spec(t):
    name=t['highway'].removesuffix('_link')
    width,mat=ROAD_SPEC.get(name,(5,'service'))
    if t['highway'].endswith('_link'):
        width*=.72
    lanes=tagged_number(t.get('lanes'))
    if lanes and 1<=lanes<=12:
        width=lanes*(3.6 if name in ('motorway','trunk') else 3.2)+(1.35 if name in ('motorway','trunk') else .5)
    if t.get('surface') in ('gravel','unpaved','dirt','ground'):
        mat='gravel'
    explicit=tagged_number(t.get('width'))
    return (explicit if explicit and 0.6<=explicit<50 else width),mat


def land_style(t):
    values=set(t.values())
    if values & {'water','riverbank','basin','reservoir','retention_pond','pond','lake'}:
        return 'water',.02
    if t.get('amenity')=='parking' or t.get('aeroway')=='apron':
        return 'lot',.042
    if (t.get('highway')=='pedestrian' or 'platform' in values):
        return 'concrete',.056
    if t.get('sport') in ('baseball','softball'):
        return 'baseball',.002
    if values & {'wood','forest','scrub','nature_reserve','wetland'}:
        return 'woodland',-.012
    if values & {'farmland','orchard','meadow'}:
        return 'field',-.021
    return 'grass',-.029


def walls(mesh, poly, y0, y1, mat, dx, dz, facade=True):
    for ring in [poly.exterior,*poly.interiors]:
        points=list(ring.coords)
        for (x,z),(a,b) in zip(points,points[1:]):
            count=max(1,round(math.hypot(a-x,b-z)/(7 if mat=='warehouse' else 4.4))) if facade else 1
            rows=max(1,round((y1-y0)/3.6)) if facade else 1
            x,z,a,b=x-dx,z-dz,a-dx,b-dz
            for i in range(count):
                l,r=i/count,(i+1)/count
                x1,z1=x+(a-x)*l,z+(b-z)*l
                x2,z2=x+(a-x)*r,z+(b-z)*r
                for j in range(rows):
                    y_a=y0+(y1-y0)*j/rows
                    y_b=y0+(y1-y0)*(j+1)/rows
                    mesh.quad(mat,[(x2,y_a,z2),(x1,y_a,z1),(x1,y_b,z1),(x2,y_b,z2)],
                              [(1,1),(0,1),(0,0),(1,0)])


def gable(mesh,poly,base,height,dx,dz):
    points=list(poly.exterior.coords)[:-1]
    if len(points)!=4 or poly.interiors:
        return False
    rect=poly.minimum_rotated_rectangle
    if poly.area/rect.area<.96:
        return False
    lens=[math.dist(points[i],points[(i+1)%4]) for i in range(4)]
    if lens[0]<lens[1]:
        points=points[1:]+points[:1]
    a,b,c,d=[np.array([x-dx,base,z-dz]) for x,z in points]
    h=np.array([0,height,0])
    u,v=(a+d)/2+h,(b+c)/2+h
    mesh.quad('shingle',[a,u,v,b])
    mesh.quad('shingle',[d,c,v,u])
    mesh.add('trim',[b,v,c],[0,1,2])
    mesh.add('trim',[a,d,u],[0,1,2])
    return True


def build_building(mesh,collision,far,poly,t,ident,dem,dx,dz,center):
    poly=orient(poly,sign=1)
    rng=random.Random(seed(ident))
    c=poly.representative_point()
    values=set(map(str,t.values()))
    kind=t.get('building',t.get('subtype','yes'))
    area=poly.area
    residential=kind in ('house','detached','residential','semidetached_house','bungalow','apartments') or (area<205 and kind=='yes')
    util=kind in ('garage','shed','carport','garages','roof','service') or area<23
    industrial=bool(values & {'industrial','warehouse','manufacture','hangar','storage'}) or area>3000
    retail=bool(values & {'retail','commercial','supermarket','restaurant','fast_food','shop'}) or 'shop' in t
    historic=(center and 70<area<1800 and not residential and not industrial) or kind in ('civic','church','public')
    num=tagged_number(t.get('height'))
    floors=tagged_number(t.get('building:levels',t.get('num_floors')))
    height=num if num and 1.8<=num<=95 else None
    basis='tagged_height' if height else 'estimated'
    if height is None and floors and 1<=floors<=24:
        height=floors*(3.20 if residential else 3.85)
        basis='tagged_floors_height_estimated'
    if height is None:
        base=2.7 if util else 4.4 if residential else 8.7 if industrial else 7.4 if historic else 5.6
        height=base*rng.uniform(.84,1.17)
    corner=np.asarray(poly.exterior.coords)
    y=np.min(dem(corner[:,0],corner[:,1]))-.18
    top=float(dem(c.x,c.y))+height
    mat=('trim' if util else 'warehouse' if industrial else rng.choice(['house_a','house_b','stucco_a']) if residential
         else rng.choice(['brick_a','brick_b','shop','stucco_a']) if historic else 'shop' if retail
         else rng.choice(['stucco_a','stucco_b','brick_b']))
    walls(mesh,poly,y,top,mat,dx,dz,not util)
    roof='metalroof' if industrial or util else 'roofs'
    use_gable=residential and t.get('roof:shape',t.get('roof_shape','gabled'))=='gabled' and basis!='tagged_height'
    if not use_gable or not gable(mesh,poly,top,min(2.3,math.sqrt(area)*.115),dx,dz):
        patch(mesh,poly,roof,lambda x,z:top,dx,dz)
        if (retail or historic or industrial) and area>105:
            sz=min(2.6,math.sqrt(area)*.09)
            mesh_box(mesh,'equipment',c.x-dx,top,c.y-dz,sz,.52 if not industrial else .8,sz*.71)
    walls(collision,poly,y,top,roof,dx,dz,False)
    if not use_gable or not gable(collision,poly,top,min(2.3,math.sqrt(area)*.115),dx,dz):
        patch(collision,poly,roof,lambda x,z:top,dx,dz)
    low=orient(poly.simplify(.62,preserve_topology=True),sign=1)
    low_mat='baxter_brick' if mat.startswith('brick') else 'trim' if residential else 'equipment'
    walls(far,low,y,top,low_mat,dx,dz,False)
    if not use_gable or not gable(far,low,top,min(2.3,math.sqrt(area)*.115),dx,dz):
        patch(far,low,roof,lambda x,z:top,dx,dz)
    return basis


def create_kit():
    definitions=kit_meshes()
    pole=Mesh()
    cylinder(pole,'trunk',0,0,0,9,.18,.12,7)
    mesh_box(pole,'trunk',0,8.45,0,2.1,.14,.18)
    for x in [-.8,0,.8]:
        mesh_box(pole,'trim',x,8.6,0,.12,.17,.13)
    definitions['utility_pole']=pole
    lamp=Mesh()
    cylinder(lamp,'steel',0,0,0,7,.11,.056,7)
    mesh_box(lamp,'steel',0,6.89,.65,.10,.1,1.4)
    mesh_box(lamp,'trim',0,6.78,1.29,.29,.12,.53)
    definitions['streetlight']=lamp
    signal=Mesh()
    cylinder(signal,'steel',0,0,0,5.85,.15,.10,7)
    mesh_box(signal,'steel',0,5.72,1.92,.13,.13,3.9)
    mesh_box(signal,'signal',0,4.70,3.57,.33,1,.29)
    for y in [4.88,5.14,5.4]:
        mesh_box(signal,'signal_glass' if y>5.3 else 'steel',.185,y,3.57,.04,.13,.14)
    definitions['traffic_signal']=signal
    sign=Mesh()
    cylinder(sign,'steel',0,0,0,3,.05,.049,6)
    mesh_box(sign,'sign',0,2.7,0,1,.24,.07)
    definitions['street_sign']=sign
    bench=Mesh()
    for x in [-.7,.7]:
        mesh_box(bench,'steel',x,0,0,.10,.44,.35)
        mesh_box(bench,'steel',x,.36,-.18,.10,.51,.08)
    mesh_box(bench,'bench',0,.42,0,1.75,.08,.48)
    mesh_box(bench,'bench',0,.65,-.21,1.75,.21,.065)
    definitions['bench']=bench
    stop=Mesh()
    cylinder(stop,'steel',0,0,0,2.85,.047,.047,6)
    ring=[(.36*math.cos((i+.5)*math.tau/8),2.53+.36*math.sin((i+.5)*math.tau/8),.018) for i in range(8)]
    stop.add('signal_glass',ring,[v for i in range(1,7) for v in (0,i,i+1)])
    stop.add('steel',[(x,y,z-.035) for x,y,z in ring],[v for i in range(1,7) for v in (0,i+1,i)])
    definitions['stop_sign']=stop
    for name,mesh in definitions.items():
        write_glb(ROOT/'assets'/f'{name}.glb',name,mesh)
    return list(definitions)


def terrain3d_import_data(dem, features):
    # Terrain3D regions start at exact multiples of 256 vertices. Pad to region boundaries.
    padded=np.pad(dem.data,((80,79),(80,79)), mode='edge')
    rng=np.random.default_rng(64593)
    n=np.array(Image.fromarray(np.uint8(rng.uniform(85,170,(32,32)))).resize((2560,2560),Image.Resampling.BICUBIC)).astype(np.float32)-120
    color=Image.new('RGB',(2560,2560),tuple(round(c*255) for c in PALETTE['ground']))
    dc=ImageDraw.Draw(color)
    for geom,t,_ in sorted(features,key=lambda a:land_style(a[1])[1]):
        style,_=land_style(t)
        if style not in ('field','grass','woodland','baseball'):
            continue
        fill=tuple(round(c*255) for c in PALETTE[style])
        for poly in parts(geom,'Polygon'):
            dc.polygon([((x+6400)/5,(z+6400)/5) for x,z in poly.exterior.coords],fill=fill)
    a=np.asarray(color,dtype=np.float32)+n[:,:,None]*.48
    ortho_path=ROOT/'source'/'usgs_naip.jpg'
    if ortho_path.exists():
        ortho=np.asarray(Image.open(ortho_path).convert('RGB'),dtype=np.float32)
        if ortho.shape!=(2401,2401,3):
            raise ValueError('Unexpected NAIP imagery dimensions')
        ortho=np.pad(ortho,((80,79),(80,79),(0,0)),mode='edge')
        # Preserve texture and parcel variation while making the color layer less
        # contrasty than the original ortho mosaic at street elevation.
        a=a*.16+np.clip(ortho*.89+3,0,255)*.84
    surface=Image.fromarray(np.uint8(np.clip(a,0,255)))
    surface.save(ROOT/'terrain'/'surface_color.png')
    lo,hi=-4,28
    raw=np.clip(np.rint((padded-GAP-lo)*65535/(hi-lo)),0,65535).astype('<u2')
    (ROOT/'terrain'/'harlingen_height.r16').write_bytes(raw.tobytes())
    return surface
    


class City:
    def __init__(self, dem, rows):
        self.dem=dem
        groups=defaultdict(list)
        for geom,t,i in rows:
            groups[t['kind']].append((geom,t,i))
        self.groups=groups
        self.landmarks=[]
        for kind in ('building','land','poi','road','channel','airstrip','site'):
            for geom,t,ident in groups[kind]:
                if not t.get('name') or kind=='road' and t['name'] not in ('West Jackson Avenue','East Jackson Avenue','West Jackson Street','East Jackson Street','Jackson Street','Jackson Avenue'):
                    continue
                if kind=='land' and not (t.get('leisure')=='park' or t.get('aeroway')=='aerodrome' or t.get('tourism')):
                    continue
                px,pz=label_position(geom,t)
                self.landmarks.append(dict(name=t['name'],layer=kind,source=ident,x=round(px,2),z=round(pz,2),
                                           northing=round(2898000-pz,2),easting=round(630000+px,2)))
        self.by_tile=defaultdict(list)
        self.assign_buildings()
        self.indices={k:STRtree([r[0] for r in items]) for k,items in groups.items() if k not in ('building','poi')}

    def assign_buildings(self):
        entries=self.groups['building']
        supplement=ROOT/'source'/'overture_local.geojson.gz'
        if supplement.exists():
            osm_geoms=[r[0] for r in entries]
            tree=STRtree(osm_geoms)
            for poly,t,i in read_features(supplement.name):
                if poly.area<8 or poly.is_empty:
                    continue
                near=tree.query(poly,predicate='intersects')
                if any(poly.intersection(osm_geoms[j]).area/min(poly.area,osm_geoms[j].area)>.40 for j in near):
                    continue
                entries.append((poly,t,f'overture:{i}'))
        for geom,t,ident in entries:
            for poly in parts(geom,'Polygon'):
                if poly.area<5:
                    continue
                point=poly.representative_point()
                ix,iz=math.floor(point.x/TILE_SIZE),math.floor(point.y/TILE_SIZE)
                if -3<=ix<3 and -3<=iz<3:
                    self.by_tile[ix,iz].append((poly,t,ident))

    def query(self,k,ext):
        return [self.groups[k][int(i)] for i in self.indices[k].query(ext,predicate='intersects')]

    def tile(self,ix,iz):
        dx,dz=ix*TILE_SIZE,iz*TILE_SIZE
        bounds=box(dx,dz,dx+TILE_SIZE,dz+TILE_SIZE)
        around=bounds.buffer(28,join_style='mitre')
        folder=ROOT/'tiles'/f'{ix:+03d}_{iz:+03d}'
        folder.mkdir(parents=True,exist_ok=True)
        meshes=defaultdict(Mesh)
        stats=Counter()
        ground_grid(meshes['TerrainMesh'],dx,dz,12.5,self.dem)
        ground_grid(meshes['TerrainFar'],dx,dz,50,self.dem)
        roads,walks,water_areas=[],[],[]
        lots=defaultdict(list)
        prop_rows=defaultdict(list)
        road_features=self.query('road',around)
        building_parts=self.by_tile[ix,iz]
        building_tree=STRtree([b[0] for b in building_parts])

        def instance(kind,x,z,s=1.0,a=0):
            if dx<=x<dx+TILE_SIZE and dz<=z<dz+TILE_SIZE:
                prop_rows[kind].append([round(float(q),3) for q in (x-dx,self.dem(x,z),z-dz,a,s)])

        def plants(geom,ident,dense):
            rng=random.Random(seed(ident))
            x0,z0,x1,z1=geom.bounds
            area=geom.area
            if not area or x1==x0 or z1==z0:
                return
            for _ in range(min(260,int(area/(205 if dense else 620)))):
                x,z=rng.uniform(x0,x1),rng.uniform(z0,z1)
                point=Point(x,z)
                if geom.contains(point) and not building_tree.query(point,predicate='intersects').size:
                    shrub=dense and rng.random()<.41
                    instance('scrub' if shrub else 'palm',x,z,rng.uniform(.58,1.35),rng.random()*math.tau)

        for geom,t,i in self.query('land',bounds):
            g=geom.intersection(bounds)
            style,h=land_style(t)
            if style=='water':
                for p in parts(g,'Polygon'):
                    c=p.representative_point()
                    high=np.quantile(self.dem(*np.asarray(p.exterior.coords).T),.16)+.14
                    patch(meshes['Water'],p,style,lambda x,z:np.maximum(high,self.dem(x,z)+.018),dx,dz,8)
                    water_areas.append(p)
            elif style=='lot':
                patch(meshes['LandCover'],g,'lot',lambda x,z:self.dem(x,z)+h,dx,dz,8)
            else:
                lots[(style,h)].append(g)
                if style in TREE_AREAS and t.get('leisure')!='pitch' and t.get('landuse') not in ('grass',):
                    plants(g,(i,ix,iz),style=='woodland')
        for (style,h),pieces in sorted(lots.items(),key=lambda e:e[0][1]):
            patch(meshes['LandCover'],unary_union(pieces),style,lambda x,z:self.dem(x,z)+h,dx,dz,20)

        lake_surfaces=unary_union(water_areas)
        for geom,t,i in self.query('channel',around):
            width=tagged_number(t.get('width')) or {'river':15,'canal':6,'stream':3,'drain':2.6,'ditch':1.7}[t['waterway']]
            for p in parts(geom.intersection(around),'LineString'):
                # Channel ribbon follows the bare-earth bed and is excluded from mapped lake surfaces.
                b=p.buffer(width/2,quad_segs=2).intersection(bounds)
                if water_areas:
                    b=b.difference(lake_surfaces)
                patch(meshes['Water'],b,'water',lambda x,z:self.dem(x,z)+.027,dx,dz,5)

        for feat,t,i in road_features:
            if t.get('tunnel') not in (None,'no','building_passage'):
                continue
            width,mat=road_spec(t)
            bridge=is_bridge(t)
            for line in parts(feat,'LineString'):
                if line.length<.45:
                    continue
                surface=line.buffer(width/2,quad_segs=3,cap_style='round',join_style='round').intersection(bounds)
                if surface.is_empty:
                    continue
                class_name=t['highway'].removesuffix('_link')
                if bridge:
                    # Estimated rise with zero offset at the mapped deck join.
                    def bridge_ground(x,z):
                        distances=np.array([line.project(Point(a,b)) for a,b in zip(x,z)])
                        ramp=min(15.,line.length*.30)
                        return self.dem(x,z)+.091+np.minimum(1,np.minimum(distances,line.length-distances)/max(.1,ramp))*3.15
                    patch(meshes['Bridges'],surface,mat,bridge_ground,dx,dz,5)
                    patch(meshes['BridgeCollision'],surface,mat,bridge_ground,dx,dz,5)
                    continue
                if class_name in VEHICLE:
                    roads.append((surface,mat))
                elif mat=='walk':
                    walks.append(surface)
                else:
                    roads.append((surface,mat))

                explicit=t.get('sidewalk')
                is_central=abs(line.centroid.x-310)<1050 and abs(line.centroid.y-455)<1050
                if explicit in ('both','yes','left','right') or explicit is None and is_central and class_name in ('residential','primary','secondary','tertiary'):
                    sides=[1,-1] if explicit not in ('left','right') else [1 if explicit=='left' else -1]
                    for side in sides:
                        offset=line.offset_curve(side*(width/2+1.06),quad_segs=3)
                        walks.append(offset.buffer(.79,quad_segs=2,cap_style='flat').intersection(bounds))

                if (class_name in ('primary','secondary','tertiary','trunk','motorway') and len(t.get('name',t.get('ref',' '))) and line.length>25):
                    for d in np.arange(11, line.length-9, 16):
                        p,q=line.interpolate(d),line.interpolate(d+4.5)
                        stripe=LineString([(p.x,p.y),(q.x,q.y)]).buffer(.076,cap_style='flat').intersection(bounds)
                        material='white' if t.get('oneway') in ('yes','1','-1') or class_name=='motorway' else 'yellow'
                        patch(meshes['Markings'],stripe,material,lambda x,z:self.dem(x,z)+.118,dx,dz)
                if is_central and class_name in ('primary','secondary','tertiary','residential'):
                    for d in np.arange(32+(seed(i)%19),line.length-12,49):
                        p, q=line.interpolate(d),line.interpolate(d+1)
                        a=math.atan2(q.y-p.y,q.x-p.x)
                        side=1 if int(d)%2 else -1
                        off=width/2+2.15
                        x,z=p.x-math.sin(a)*off*side,p.y+math.cos(a)*off*side
                        if not building_tree.query(Point(x,z),predicate='intersects').size:
                            instance('streetlight',x,z,1,math.atan2(p.x-x,p.y-z))
                            if (int(d)//49)%2==0:
                                instance('palm',x+(q.x-p.x)*9,z+(q.y-p.y)*9,.84,0)
        paved=unary_union([g for g,_ in roads])
        for mat in ('highway','asphalt','service','gravel'):
            grouped=unary_union([g for g,m in roads if m==mat])
            if not grouped.is_empty:
                if mat!='highway':
                    grouped=grouped.difference(unary_union([g for g,m in roads if ('highway','asphalt','service','gravel').index(m)<('highway','asphalt','service','gravel').index(mat)]))
                patch(meshes['Roads'],grouped,mat,lambda x,z:self.dem(x,z)+.078,dx,dz,6)
        walk=unary_union(walks).difference(paved.buffer(.045))
        patch(meshes['Sidewalks'],walk,'walk',lambda x,z:self.dem(x,z)+.102,dx,dz,6)
        # At-grade collision is a seam-aligned coarse version of the underlying bare-earth terrain.
        ground_grid(meshes['GroundCollision'],dx,dz,20,self.dem)

        for kind in ('airstrip','rail'):
            for geom,t,i in self.query(kind,around):
                width=tagged_number(t.get('width')) or (45 if t.get('aeroway')=='runway' else 19 if kind=='airstrip' else 2.7)
                m='runway' if kind=='airstrip' else 'rail'
                surface=geom.buffer(width*.5,cap_style='flat').intersection(bounds)
                patch(meshes['Transport'],surface,m,lambda x,z:self.dem(x,z)+.097,dx,dz,8)
                if t.get('aeroway')=='runway':
                    for line in parts(geom,'LineString'):
                        for step in np.arange(110,line.length-50,62):
                            a,b=line.interpolate(step),line.interpolate(step+24)
                            stripe=LineString([(a.x,a.y),(b.x,b.y)]).buffer(.47,cap_style='flat').intersection(bounds)
                            patch(meshes['Markings'],stripe,'white',lambda x,z:self.dem(x,z)+.14,dx,dz)
                elif kind=='rail':
                    for side in (-1,1):
                        for l in parts(geom,'LineString'):
                            stripe=l.offset_curve(side*.72).buffer(.045).intersection(bounds)
                            patch(meshes['Transport'],stripe,'steel',lambda x,z:self.dem(x,z)+.155,dx,dz,9)

        for geom,t,i in self.query('prop',bounds):
            if geom.geom_type!='Point':
                continue
            h=t.get('highway')
            if h=='crossing':
                if not paved.buffer(.15).contains(geom):
                    continue
                nearby=[row for row in road_features if row[1]['highway'] in VEHICLE and row[0].distance(geom)<6]
                if not nearby:
                    continue
                road,rt,_=min(nearby,key=lambda r:r[0].distance(geom))
                if road.geom_type!='LineString':
                    continue
                d=road.project(geom)
                a,b=road.interpolate(max(0,d-1)),road.interpolate(min(road.length,d+1))
                angle=math.atan2(b.y-a.y,b.x-a.x)
                tangent=np.array([math.cos(angle),math.sin(angle)])
                normal=np.array([-tangent[1],tangent[0]])
                cp=np.array([geom.x,geom.y])
                width,_=road_spec(rt)
                for offset in np.arange(-width*.41,width*.42,1.05):
                    s=cp+normal*offset
                    p=Polygon([s-tangent*1.3-normal*.25,s+tangent*1.3-normal*.25,s+tangent*1.3+normal*.25,s-tangent*1.3+normal*.25])
                    patch(meshes['Markings'],p.intersection(bounds),'white',lambda x,z:self.dem(x,z)+.132,dx,dz)
                continue
            kit=('traffic_signal' if h=='traffic_signals' else 'streetlight' if h=='street_lamp' else
                 'stop_sign' if h=='stop' else 'utility_pole' if 'power' in t else 'bench' if t.get('amenity')=='bench' else 'palm')
            px,pz=geom.x,geom.y
            yaw=0.
            if h in ('traffic_signals','stop') and paved.contains(geom):
                # Source nodes commonly mark a road center rather than a surveyed pole.
                side=paved.boundary.interpolate(paved.boundary.project(geom)) if paved.boundary.geom_type=='LineString' else None
                if side is None:
                    from shapely.ops import nearest_points
                    side=nearest_points(paved.boundary,geom)[0]
                vx,vz=geom.x-side.x,geom.y-side.y
                dist=max(.001,math.hypot(vx,vz))
                px,pz=side.x-vx/dist*.9,side.y-vz/dist*.9
                yaw=math.atan2(vx,vz)
            instance(kit,px,pz,1 if kit!='palm' else .70+random.Random(seed(i)).random()*.43,yaw)
            if kit=='traffic_signal':
                instance('street_sign',px+1.35,pz+.75,.84,yaw)

        for poly,t,i in building_parts:
            center=abs(poly.centroid.x-310)<620 and abs(poly.centroid.y-455)<560
            if i==BAXTER_ID:
                basis=baxter(meshes['Landmarks'],meshes['BuildingCollision'],poly,self.dem,dx,dz,patch,walls)
            else:
                basis=build_building(meshes['Buildings'],meshes['BuildingCollision'],meshes['BuildingsFar'],poly,t,i,self.dem,dx,dz,center)
            stats[basis]+=1
            stats['osm_buildings' if i.startswith('osm:') else 'overture_buildings']+=1
        metadata=dict(id=folder.name,x=dx,z=dz,layers={},counts=dict(stats),
                      instances=sum(map(len,prop_rows.values())))
        sub=BytesIO()
        u,v=(dx+6400)//5,(dz+6400)//5
        self.surface.crop((u,v,u+401,v+401)).save(sub,format='JPEG',quality=82)
        for layer,mesh in sorted(meshes.items()):
            tex=sub.getvalue() if layer in ('TerrainMesh','TerrainFar') else None
            if write_glb(folder/f'{layer}.glb',layer,mesh,tex):
                metadata['layers'][layer]=dict(triangles=mesh.triangles(),file=f'tiles/{folder.name}/{layer}.glb')
        if prop_rows:
            (folder/'instances.json').write_text(json.dumps(prop_rows,separators=(',',':')))
        scene(folder,metadata)
        return metadata


def scene(folder,meta):
    visible=[k for k in meta['layers'] if not k.endswith('Collision')]
    lines=['[gd_scene format=3]', '', '[ext_resource type="Script" path="res://preview/tile.gd" id="1"]']
    for i,k in enumerate(visible,2):
        lines.append(f'[ext_resource type="PackedScene" path="res://tiles/{meta["id"]}/{k}.glb" id="{i}"]')
    downtown = meta['id'] == '+00_+00' and (ROOT/'assets'/'signage'/'DowntownStreetscape.tscn').exists()
    if downtown:
        lines.append('[ext_resource type="PackedScene" path="res://assets/signage/DowntownStreetscape.tscn" id="streetscape"]')
    lines+=['',f'[node name="District_{meta["id"].replace("+","p").replace("-","n")}" type="Node3D"]',
            f'position = Vector3({meta["x"]}, 0, {meta["z"]})','script = ExtResource("1")',
            f'tile_id = "{meta["id"]}"']
    for i,k in enumerate(visible,2):
        lines+=['',f'[node name="{k}" parent="." instance=ExtResource("{i}")]']
        if k in ('TerrainFar','BuildingsFar'):
            lines.append('visible = false')
    if downtown:
        lines+=['', '[node name="DowntownStreetscape" parent="." instance=ExtResource("streetscape")]']
    (folder/'district.tscn').write_text('\n'.join(lines)+'\n')


def main(work):
    (ROOT/'assets').mkdir(exist_ok=True)
    facade_atlas(ROOT/'assets'/'facades.png')
    kit=create_kit()
    if (work/'harlingen_dem.tif').exists():
        dem=Elevation(work/'harlingen_dem.tif')
    else:
        dem=Elevation(ROOT/'source'/'3dep_float.tif')
    rows=corrected_features(read_features('osm_local.geojson.gz'))
    global SHARED_CITY
    city=City(dem,rows)
    city.surface=terrain3d_import_data(dem,city.groups['land'])
    SHARED_CITY=city
    manifest=dict(origin_epsg=32614,origin_easting=630000,origin_northing=2898000,
                  vertical='USGS 3DEP service elevations, metres',tile_size=TILE_SIZE,
                  local_extent=[-6000,-6000,6000,6000],prop_kit=kit,
                  landmarks=city.landmarks,
                  reference_models={BAXTER_ID:{"name":"Baxter Building","source":BAXTER_NPS}},tiles=[])
    manifest['geographic_districts']=district_register()
    import os
    from concurrent.futures import ProcessPoolExecutor
    with ProcessPoolExecutor(max_workers=min(6,os.cpu_count() or 1),
                             mp_context=multiprocessing.get_context('fork')) as pool:
        jobs=[pool.submit(make_tile,ix,iz) for iz in range(-3,3) for ix in range(-3,3)]
        for job in jobs:
            meta=job.result()
            manifest['tiles'].append(meta)
            print(meta['id'],meta['counts'],meta['instances'],flush=True)
    label_rows=[(g,t,i) for g,t,i in rows if t.get('name') and
                (t.get('kind')=='site' or i=='thc:iwo-jima')]
    if any(i=='thc:iwo-jima' for _,_,i in label_rows):
        from iwo_jima import build_memorial
        memorial=ROOT/'assets'/'landmarks'/'IwoJimaMemorial.glb'
        memorial.parent.mkdir(exist_ok=True)
        build_memorial(memorial)
    for tile,sites in labels_by_tile(label_rows).items():
        folder=ROOT/'tiles'/tile
        write_tile_sites(folder,sites,dem)
        attach_sites(folder)
    (ROOT/'manifest.json').write_text(json.dumps(manifest,indent=2))

# Fork workers share the parsed, read-only GIS scene and DEM.
def make_tile(ix,iz):
    return SHARED_CITY.tile(ix,iz)


if __name__=='__main__':
    # The build uses fork on Linux. The generated Godot project is portable.
    main(Path(sys.argv[1]) if len(sys.argv)>1 else ROOT/'source')
