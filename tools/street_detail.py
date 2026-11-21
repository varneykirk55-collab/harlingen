"""Generate additive sidewalk, crossing and facade meshes for the existing districts."""
from collections import Counter
from concurrent.futures import ProcessPoolExecutor
import json
import math
import multiprocessing
import struct

import numpy as np
from shapely.geometry import LineString, Point, Polygon, box
from shapely.geometry.polygon import orient
from shapely.ops import polygonize, unary_union
from shapely.strtree import STRtree

from build import City, Elevation, ROOT, VEHICLE, parts, read_features, road_spec, seed, tagged_number
from mesh import Mesh, PALETTE

DETAILS = {
    'curb': ('raised_curb',(.64,.62,.57)),
    'joint': ('slab_joint',(.32,.32,.29)),
    'crosswalk': ('crossing_white',(.91,.89,.82)),
    'portal': ('facade_door_trim',(.51,.43,.33)),
    'door': ('facade_door',(.25,.19,.15)),
    'frame': ('facade_window_frame',(.72,.69,.60)),
    'glass_detail': ('facade_window_glass',(.23,.32,.34)),
    'stoop': ('entrance_stoop',(.58,.54,.48)),
}
PALETTE.update({key:color for key,(_,color) in DETAILS.items()})
DOWNTOWN = box(70,195,735,590)
MAIN = {'primary','secondary','tertiary'}
ATLAS_WINDOWS = {
    'brick_a': [(27,66,102,178),(154,66,230,178)],
    'brick_b': [(27,66,102,178),(154,66,230,178)],
    'stucco_a': [(27,66,102,178),(154,66,230,178)],
    'stucco_b': [(27,66,102,178),(154,66,230,178)],
    'house_a': [(27,66,102,178),(154,66,230,178)],
    'house_b': [(27,66,102,178),(154,66,230,178)],
    'warehouse': [(55,88,200,133)],
    'shop': [(17,85,114,216),(142,85,237,216)],
}


def glb_parts(path):
    if not path.exists():
        return
    b=path.read_bytes()
    length=struct.unpack_from('<I',b,12)[0]
    doc=json.loads(b[20:20+length])
    off=28+length
    def accessor(index,width,dtype):
        entry=doc['accessors'][index]
        view=doc['bufferViews'][entry['bufferView']]
        return np.frombuffer(b,dtype,count=entry['count']*width,offset=off+view['byteOffset']).reshape(-1,width)
    for p in doc['meshes'][0]['primitives']:
        mat=doc['materials'][p['material']]['name']
        yield mat,accessor(p['attributes']['POSITION'],3,'<f4').astype(float),accessor(p['indices'],1,'<u4').reshape(-1,3)


class Surface:
    """Sample the rendered grade instead of interpolating the elevation raster again."""
    def __init__(self, path, ignored=()):
        self.tri=[]
        self.polygons=[]
        self.edges=[]
        for mat,v,tri in glb_parts(path):
            if mat in ignored:
                continue
            faces=v[tri]
            xy=faces[:,:,[0,2]]
            u=xy[:,1]-xy[:,0]
            w=xy[:,2]-xy[:,0]
            mask=np.abs(u[:,0]*w[:,1]-u[:,1]*w[:,0])>1e-8
            self.tri.extend(faces[mask])
            self.polygons.extend(Polygon(p) for p in xy[mask])
            indices=np.sort(np.concatenate((tri[:,[0,1]],tri[:,[1,2]],tri[:,[2,0]])),axis=1)
            unique,counts=np.unique(indices,axis=0,return_counts=True)
            self.edges.extend(v[unique[counts==1]][:,:,[0,2]])
        self.tri=np.array(self.tri)
        self.index=STRtree(self.polygons)

    def heights(self, points):
        points=np.asarray(points)
        if len(points)==0:
            return np.zeros(0)
        from shapely import points as points_2d
        p=points_2d(points)
        left,right=self.index.query(p,predicate='intersects')
        have=set(left)
        missing=np.array([i for i in range(len(points)) if i not in have],dtype=int)
        if len(missing):
            nearest=np.asarray(self.index.nearest(p[missing]))
            left=np.concatenate((left,missing))
            right=np.concatenate((right,nearest))
        tri=self.tri[right]
        xy=tri[:,:,[0,2]]
        a,b=xy[:,1]-xy[:,0],xy[:,2]-xy[:,0]
        p=points[left]-xy[:,0]
        det=a[:,0]*b[:,1]-a[:,1]*b[:,0]
        u=(p[:,0]*b[:,1]-p[:,1]*b[:,0])/det
        v=(a[:,0]*p[:,1]-a[:,1]*p[:,0])/det
        ly=tri[:,0,1]+u*(tri[:,1,1]-tri[:,0,1])+v*(tri[:,2,1]-tri[:,0,1])
        # At exact outline vertices, float32 quantization can put the query just
        # outside a long thin triangle. Never extrapolate beyond that face's grades.
        ly=np.clip(ly,tri[:,:,1].min(axis=1),tri[:,:,1].max(axis=1))
        result=np.full(len(points),-np.inf)
        np.maximum.at(result,left,ly)
        return result

    def outlines(self):
        for polygon in polygonize([LineString(e) for e in self.edges if np.linalg.norm(e[1]-e[0])>1e-7]):
            if polygon.area>.08 and self.index.query(polygon.representative_point(),predicate='intersects').size:
                yield orient(polygon,sign=1)


def ribbons(mesh, positions, heights, mat, invert=False):
    count=len(positions)
    bands=positions.shape[1]
    idx=[]
    for i in range(count-1):
        for j in range(bands-1):
            a=i*bands+j
            q=(a,a+bands,a+bands+1,a,a+bands+1,a+1)
            idx.extend(q if not invert else (q[2],q[1],q[0],q[5],q[4],q[3]))
    points=np.column_stack((positions[:,:,0].ravel(),heights.ravel(),positions[:,:,1].ravel()))
    mesh.add(mat,points,idx)


def sidewalk_detail(mesh,surface):
    lengths=0.
    joints=0
    for poly in surface.outlines():
        for ring in [poly.exterior,*poly.interiors]:
            path=LineString(ring.coords)
            xy=np.asarray(path.simplify(.026).segmentize(6.).coords)[:-1]
            if len(xy)<3:
                continue
            segment=np.roll(xy,-1,axis=0)-xy
            size=np.linalg.norm(segment,axis=1)
            # Repeated vertices can come from touching paths at a tile edge.
            if np.any(size<1e-8):
                continue
            tangent=segment/size[:,None]
            inward=np.column_stack((-tangent[:,1],tangent[:,0]))
            previous=np.roll(inward,1,axis=0)
            miter=(inward+previous)/np.maximum(.43,1+(inward*previous).sum(axis=1))[:,None]
            px=np.concatenate((xy,xy[:1]))
            miter=np.concatenate((miter,miter[:1]))
            heights=surface.heights(px)
            # The profile follows the original outer edge, with a three-facet bullnose.
            offsets=np.array([0.0,0.0,.029,.085,.15])
            elevations=np.array([-.25,.018,.080,.112,.112])
            curb_xy=px[:,None,:]+offsets[None,:,None]*miter[:,None,:]
            curb_y=heights[:,None]+elevations[None,:]
            ribbons(mesh,curb_xy,curb_y,'curb',invert=True)
            lengths+=path.length
        # Score seams from the perimeter toward the inside. Opposite sides share one joint.
        if poly.area<1.:
            continue
        from shapely import intersects_xy
        accepted=set()
        for ring in [poly.exterior,*poly.interiors]:
            path=LineString(ring.coords)
            count=min(4000,round(path.length/3.15))
            for d in (np.arange(count)+.50)*path.length/max(1,count):
                p=np.array(path.interpolate(d).coords[0])
                a=np.array(path.interpolate(max(0,d-.09)).coords[0])
                b=np.array(path.interpolate(min(path.length,d+.09)).coords[0])
                tangent=b-a
                if np.linalg.norm(tangent)<.015:
                    continue
                tangent/=np.linalg.norm(tangent)
                n=np.array([-tangent[1],tangent[0]])
                q=p+.035*n
                if not intersects_xy(poly,*q):
                    continue
                ray=LineString([q,q+n*5.0])
                lines=list(parts(poly.intersection(ray),'LineString'))
                match=next((g for g in lines if g.distance(Point(q))<.012),None)
                if match is None or not .35<match.length<4.6:
                    continue
                e=np.asarray(match.coords)[-1]
                middle=(q+e)/2
                bucket=tuple(np.floor(middle/.85).astype(int))
                if any((bucket[0]+u,bucket[1]+v) in accepted for u in (-1,0,1) for v in (-1,0,1)):
                    continue
                accepted.add(bucket)
                p=q+n*.095
                e=e-n*.132
                corners=np.array([p-tangent*.016,e-tangent*.016,e+tangent*.016,p+tangent*.016])
                h=surface.heights(corners)+.106
                mesh.add('joint',np.column_stack((corners[:,0],h,corners[:,1])),[0,1,2,0,2,3],
                         normals=[(0,1,0)]*4)
                joints+=1
    return round(lengths,1),joints


def crossing_candidates(city):
    """Find mapped at-grade junctions. Feature endpoints at shared XY identify approaches."""
    junctions={}
    for geo,tags,ident in city.groups['road']:
        cls=tags.get('highway')
        if cls not in VEHICLE or cls in ('motorway','trunk') or tags.get('tunnel') or tags.get('bridge'):
            continue
        for line in parts(geo,'LineString'):
            if line.length<5:
                continue
            coords=np.asarray(line.coords)
            w=road_spec(tags)[0]
            for i,point in enumerate(coords):
                key=tuple(np.round(point,2))
                for k in (i-1,i+1):
                    if not 0<=k<len(coords):
                        continue
                    direction=coords[k]-point
                    dist=np.linalg.norm(direction)
                    if dist>.05:
                        junctions.setdefault(key,[]).append((direction/dist,tags,w))
    signals=STRtree([g for g,t,_ in city.groups['prop'] if t.get('highway')=='traffic_signals'])
    output={}
    for p,raw_arms in junctions.items():
        arms=[]
        for arm in raw_arms:
            if all(np.dot(arm[0],other[0])<.98 for other in arms):
                arms.append(arm)
        if len(arms)<3:
            continue
        x,z=p
        central=70<x<760 and 190<z<600
        arterial=sum(t.get('highway') in MAIN for _,t,_ in arms)
        nearby_signal=signals.query(Point(p),predicate='dwithin',distance=18).size
        if not (central or (arterial>=2 and nearby_signal)):
            continue
        if not any(abs(np.dot(a[0],b[0]))<.77 for a in arms for b in arms):
            continue
        ix,iz=math.floor(x/2000),math.floor(z/2000)
        if not (-3<=ix<=2 and -3<=iz<=2):
            continue
        for d,t,w in arms:
            if t.get('highway')=='service' or (not central and t.get('highway') not in MAIN):
                continue
            others=[width for other,_,width in arms if abs(np.dot(d,other))<.82]
            if not others:
                continue
            lead=max(others)*.53+2.1
            output.setdefault((ix,iz),[]).append((np.array(p)+d*lead,d,w,central))
    return output


def crosswalks(mesh,road,existing,sidewalk,candidates,offset):
    count=0
    for center,along,width,priority in candidates:
        center=center-offset
        across=np.array([-along[1],along[0]])
        if not priority:
            if sidewalk is None:
                continue
            # Only add a crossing where it has an existing pedestrian approach nearby.
            approaches=[Point(center+across*width*.51),Point(center-across*width*.51)]
            if all(closest_distance(sidewalk,p)>4.5 for p in approaches):
                continue
        if existing:
            region=Polygon([center+across*u+along*v for u,v in
                            [(-width/2,-2.1),(width/2,-2.1),(width/2,2.1),(-width/2,2.1)]])
            cover=existing.index.query(region,predicate='intersects')
            # Existing lane dashes are narrow; an existing zebra pattern occupies a substantially larger area.
            if sum(region.intersection(existing.polygons[i]).area for i in cover)>2.0:
                continue
        centers=np.arange(-width*.42,width*.43,.91)
        vertices=[]
        for side in centers:
            p=center+across*side
            vertices.extend([p+across*u+along*v for u,v in [(-.25,-1.32),(.25,-1.32),(.25,1.32),(-.25,1.32)]])
        vertices=np.array(vertices)
        if not len(vertices):
            continue
        # Require actual asphalt beneath every tip. Don't paint onto terrain or over tile borders.
        from shapely import points as points_2d
        covered=road.index.query(points_2d(vertices),predicate='intersects')[0]
        if len(set(covered))!=len(vertices):
            continue
        yy=road.heights(vertices)+.017
        for k in range(0,len(vertices),4):
            xy=vertices[k:k+4]
            points=np.column_stack((xy[:,0],yy[k:k+4],xy[:,1]))
            d1=np.cross(points[1]-points[0],points[2]-points[0])[1]
            mesh.add('crosswalk',points,[0,1,2,0,2,3] if d1>0 else [0,2,1,0,3,2],normals=[(0,1,0)]*4)
        count+=1
    return count


def closest_distance(surface,point):
    nearest=surface.index.nearest(point)
    return surface.polygons[nearest].distance(point) if nearest is not None else math.inf


def wall_quad(mesh,mat,origin,tangent,outward,left,bottom,right,top,projection):
    a=origin+tangent*left+outward*projection
    b=origin+tangent*right+outward*projection
    mesh.quad(mat,[(b[0],bottom,b[1]),(a[0],bottom,a[1]),(a[0],top,a[1]),(b[0],top,b[1])])


def fixture(mesh,origin,u,n,left,bot,right,top,trim,leaf,projection=.08,edge=.062):
    """A shallow opening with a panel behind a beveled perimeter."""
    outer=[(right,bot),(left,bot),(left,top),(right,top)]
    inner=[(right-edge,bot+edge),(left+edge,bot+edge),(left+edge,top-edge),(right-edge,top-edge)]
    verts=[]
    for uv,depth in [(outer,projection),(inner,.025)]:
        for x,y in uv:
            p=origin+u*x+n*depth
            verts.append((p[0],y,p[1]))
    mesh.add(trim,verts,[q for i in range(4) for q in (i,(i+1)%4,(i+1)%4+4,i,(i+1)%4+4,i+4)])
    wall_quad(mesh,leaf,origin,u,n,left+edge,bot+edge,right-edge,top-edge,.027)


def step(mesh,p,u,n,left,right,y):
    # Small landing with a dark riser and a dressed concrete cap.
    world=[p+t*u+d*n for t,d in [(left,.013),(right,.013),(right,.32),(left,.32)]]
    mesh.quad('stoop',[(x,y+.11,z) for x,z in world])
    for a,b in [(0,1),(1,2),(2,3),(3,0)]:
        x,z=world[a]; q,r=world[b]
        mesh.quad('stoop',[(x,y-.105,z),(q,y-.105,r),(q,y+.11,r),(x,y+.11,z)])


def building_specs(poly,t,ident,dem):
    """Match the dimensions and facade selection in the source tile builder."""
    from random import Random
    rng=Random(seed(ident))
    c=poly.representative_point()
    values=set(map(str,t.values()))
    kind=t.get('building',t.get('subtype','yes'))
    area=poly.area
    home=kind in ('house','detached','residential','semidetached_house','bungalow','apartments') or (area<205 and kind=='yes')
    utility=kind in ('garage','shed','carport','garages','roof','service') or area<23
    industrial=bool(values & {'industrial','warehouse','manufacture','hangar','storage'}) or area>3000
    retail=bool(values & {'retail','commercial','supermarket','restaurant','fast_food','shop'}) or 'shop' in t
    historic=(abs(poly.centroid.x-310)<620 and abs(poly.centroid.y-455)<560 and 70<area<1800 and not home and not industrial) or kind in ('civic','church','public')
    height=tagged_number(t.get('height'))
    if height is None or not 1.8<=height<=95:
        floors=tagged_number(t.get('building:levels',t.get('num_floors')))
        if floors and 1<=floors<=24:
            height=floors*(3.2 if home else 3.85)
        else:
            h=2.7 if utility else 4.4 if home else 8.7 if industrial else 7.4 if historic else 5.6
            height=h*rng.uniform(.84,1.17)
    mat=('trim' if utility else 'warehouse' if industrial else rng.choice(['house_a','house_b','stucco_a']) if home
         else rng.choice(['brick_a','brick_b','shop','stucco_a']) if historic else 'shop' if retail
         else rng.choice(['stucco_a','stucco_b','brick_b']))
    coord=np.asarray(poly.exterior.coords)
    floor=float(np.min(dem(coord[:,0],coord[:,1])))-.18
    roof=float(dem(c.x,c.y))+height
    return floor,roof,mat,industrial or (retail and area>260)


def baxter_outline(outline):
    corners=np.asarray(outline.minimum_rotated_rectangle.exterior.coords)[:4]
    edges=np.roll(corners,-1,axis=0)-corners
    long=edges[np.argmax(np.linalg.norm(edges,axis=1))]
    long/=np.linalg.norm(long)
    short=np.array([long[1],-long[0]])
    if short[0]<0:
        short*=-1
    e,lower=(corners@short).max()-.2,(corners@long).min()+.4
    return orient(Polygon([short*x+long*z for x,z in [(e-7.62,lower),(e,lower),(e,lower+42.672),(e-7.62,lower+42.672)]]),sign=1)


def frontage(poly,streets,tree):
    coords=np.asarray(poly.exterior.coords)
    result=[]
    for idx,(p,q) in enumerate(zip(coords,coords[1:])):
        v=q-p
        length=np.linalg.norm(v)
        if length<.7:
            continue
        u=v/length
        n=np.array([u[1],-u[0]])
        mid=(p+q)/2
        pt=Point(mid)
        road=streets[tree.nearest(pt)]
        near=road.interpolate(road.project(pt))
        toward=np.array(near.coords[0])-mid
        alignment=np.dot(toward,n)/max(np.linalg.norm(toward),.01)
        score=4.5*alignment+math.log(length)*1.7-.028*toward.dot(toward)**.5
        result.append((score,idx,p,u,n,length))
    if not result:
        return None
    return max(result,key=lambda a:a[0])


def facades(mesh,tile,city,offset,streets,tree):
    doors=0
    windows=0
    from landmark import BAXTER_ID
    for poly,t,ident in city.by_tile[(int(tile['x']//2000),int(tile['z']//2000))]:
        poly=orient(poly,sign=1)
        is_landmark=ident==BAXTER_ID
        if is_landmark:
            poly=baxter_outline(poly)
        coords=np.asarray(poly.exterior.coords)
        priority=poly.intersects(DOWNTOWN)
        spec=building_specs(poly,t,ident,city.dem)
        floor,roof,mat,double=spec
        front=frontage(poly,streets,tree)
        if front is None:
            continue
        _,selected,start,u,n,length=front
        middle=start+u*.5*length
        y=max(floor+.05,float(city.dem(*middle))+.045)
        # Compact sheds receive a narrow opening, larger storefronts a wider one.
        wide=min(length*.66,1.72 if double else 1.12)
        head=min(roof-.07,y+(2.48 if double else 2.18))
        if head<y+.75:
            y=max(floor+.022,head-1.30)
        door_left,door_right=length*.5-wide*.5,length*.5+wide*.5
        fixture(mesh,start-offset,u,n,door_left,y,door_right,head,'portal',
                'glass_detail' if double else 'door',.108 if priority else .074,.072 if wide>.72 else .042)
        doors+=1
        if priority:
            step(mesh,start-offset,u,n,door_left-.08,door_right+.08,y-.05)
            wall_quad(mesh,'frame',start-offset,u,n,length/2+wide*.21,y+.88,length/2+wide*.32,y+.935,.095)
        if is_landmark:
            # The landmark already ships with individually modeled window trim and glazing.
            continue
        if mat not in ATLAS_WINDOWS:
            if length>2.7 and head-y>1.2:
                fixture(mesh,start-offset,u,n,.24,y+.65,.76,min(roof-.14,y+1.23),'frame','glass_detail',.067,.047)
                windows+=1
            continue
        for ix,(a,b) in enumerate(zip(coords,coords[1:])):
            if not priority and ix!=selected:
                continue
            tangent=b-a
            ll=np.linalg.norm(tangent)
            if ll<.75:
                continue
            uu=tangent/ll
            nn=np.array([uu[1],-uu[0]])
            bays=max(1,round(ll/(7 if mat=='warehouse' else 4.4)))
            rows=max(1,round((roof-floor)/3.6))
            bay_width=ll/bays
            level=(roof-floor)/rows
            if priority:
                use_bays=range(bays)
            else:
                use_bays=[0 if bays>1 else bays//2]
            for bay in use_bays:
                for l,hi,r,lo in ATLAS_WINDOWS[mat]:
                    left=bay_width*(bay+(l-6)/244)
                    right=bay_width*(bay+(r-6)/244)
                    if not priority and right-left<.35:
                        continue
                    for row in range(min(rows,2 if priority else 1)):
                        bottom=floor+level*(row+1-(lo-6)/244)
                        top=floor+level*(row+1-(hi-6)/244)
                        if top<bottom+.15 or right-left<.22:
                            continue
                        if ix==selected and right>door_left-.11 and left<door_right+.11 and bottom<head+.06 and top>y:
                            continue
                        fixture(mesh,a-offset,uu,nn,left,bottom,right,top,'frame','glass_detail',
                                .078 if priority else .057,.063 if priority else .044)
                        windows+=1
    return doors,windows



def write_detail(path,name,mesh):
    """Pack 320 m cells into one GLB so the renderer can cull each separately."""
    if not mesh.parts:
        return False
    buffers=bytearray()
    materials,accessors,views,meshes,nodes=[],[],[],[],[]
    cells={}
    for material,(points,normals,_,indices) in sorted(mesh.parts.items()):
        p=np.asarray(points,dtype=np.float32)
        n=np.asarray(normals,dtype=np.float32)
        triangles=np.asarray(indices,dtype=np.uint32).reshape(-1,3)
        keys=np.floor(p[triangles][:,:,[0,2]].mean(axis=1)/320).astype(int)
        groups,groups_idx=np.unique(keys,axis=0,return_inverse=True)
        col=PALETTE[material]
        linear=[c/12.92 if c<=.04045 else ((c+.055)/1.055)**2.4 for c in col]
        mat=len(materials)
        materials.append(dict(name=material,pbrMetallicRoughness=dict(baseColorFactor=[*linear,1],
                              metallicFactor=0,roughnessFactor=.78)))
        for i,cell in enumerate(groups):
            used,faces=np.unique(triangles[groups_idx==i].ravel(),return_inverse=True)
            key=tuple(map(int,cell))
            translate=np.array([key[0]*320+160,0,key[1]*320+160],dtype=np.float32)
            positions=p[used]-translate
            attrs={}
            for label,values,target,typ,ctype in [
                ('POSITION',positions,34962,'VEC3',5126), ('NORMAL',n[used],34962,'VEC3',5126),
                ('indices',faces.astype('<u4'),34963,'SCALAR',5125)]:
                data=values.tobytes()
                views.append(dict(buffer=0,byteOffset=len(buffers),byteLength=len(data),target=target))
                buffers.extend(data)
                entry=dict(bufferView=len(views)-1,componentType=ctype,count=len(values),type=typ)
                if label=='POSITION':
                    entry.update(min=values.min(axis=0).tolist(),max=values.max(axis=0).tolist())
                attrs[label]=len(accessors)
                accessors.append(entry)
            index=attrs.pop('indices')
            cells.setdefault(key,[]).append(dict(attributes=attrs,indices=index,material=mat))
    for (x,z),primitives in sorted(cells.items()):
        label=f'{name}_{x}_{z}'
        nodes.append(dict(name=label,mesh=len(meshes),translation=[x*320+160,0,z*320+160]))
        meshes.append(dict(name=label,primitives=primitives))
    doc=dict(asset=dict(version='2.0',generator='Harlingen street detail'),
             scene=0,scenes=[dict(nodes=list(range(len(nodes))))],nodes=nodes,meshes=meshes,
             materials=materials,accessors=accessors,bufferViews=views,buffers=[dict(byteLength=len(buffers))])
    header=json.dumps(doc,separators=(',',':')).encode()
    header+=b' '*((-len(header))%4)
    with path.open('wb') as f:
        f.write(struct.pack('<4sII',b'glTF',2,28+len(header)+len(buffers)))
        f.write(struct.pack('<I4s',len(header),b'JSON'))
        f.write(header)
        f.write(struct.pack('<I4s',len(buffers),b'BIN\0'))
        f.write(buffers)
    return True


def build_tile(tile):
    folder=ROOT/'tiles'/tile['id']
    offset=np.array([tile['x'],tile['z']])
    ix,iz=(offset//2000).astype(int)
    new={}
    sidewalk=Surface(folder/'Sidewalks.glb') if (folder/'Sidewalks.glb').exists() else None
    ground=Mesh()
    curb_length,joints=sidewalk_detail(ground,sidewalk) if sidewalk else (0,0)
    candidates=CONNECTIONS.get((ix,iz),[])
    number=0
    if candidates and (folder/'Roads.glb').exists():
        road=Surface(folder/'Roads.glb',ignored=('gravel',))
        paint=Surface(folder/'Markings.glb',ignored=('yellow',)) if (folder/'Markings.glb').exists() else None
        if road.polygons:
            number=crosswalks(ground,road,paint,sidewalk,candidates,offset)
    facade=Mesh()
    doors,windows=facades(facade,tile,CITY,offset,STREETS,ROAD_TREE)
    for name,mesh in [('StreetEdges',ground),('FacadeDetails',facade)]:
        if write_detail(folder/f'{name}.glb',name,mesh):
            new[name]={'triangles':mesh.triangles(),'file':f'tiles/{tile["id"]}/{name}.glb'}
    print(tile['id'],int(curb_length),joints,number,doors,windows,flush=True)
    return tile['id'],new,dict(curb_metres=curb_length,slab_joints=joints,new_crosswalks=number,entrances=doors,window_frames=windows)


def apply_tile(filename,layers):
    text=filename.read_text()
    for layer in ('StreetEdges','FacadeDetails'):
        id_=layer.lower()
        old=f'[ext_resource type="PackedScene" path="res://tiles/{filename.parent.name}/{layer}.glb" id="{id_}"]\n'
        node=f'\n[node name="{layer}" parent="." instance=ExtResource("{id_}")]\n'
        text=text.replace(old,'').replace(node,'')
        if layer in layers:
            split=text.index('\n[node')
            text=text[:split]+old+text[split:]+node
    # The new lip is approximately flush with a slightly raised visual slab.
    before='[node name="Sidewalks"'
    if before in text:
        lines=text.splitlines()
        i=next(i for i,l in enumerate(lines) if l.startswith(before))
        if not lines[i+1].startswith('position = '):
            lines.insert(i+1,'position = Vector3(0, 0.10, 0)')
        text='\n'.join(lines)+'\n'
    filename.write_text(text)


if __name__=='__main__':
    document=ROOT/'manifest.json'
    manifest=json.loads(document.read_text())
    CITY=City(Elevation(ROOT/'source'/'3dep_float.tif'),read_features('osm_local.geojson.gz'))
    STREETS=[g for g,t,_ in CITY.groups['road'] if t.get('highway') in VEHICLE and not g.is_empty]
    ROAD_TREE=STRtree(STREETS)
    CONNECTIONS=crossing_candidates(CITY)
    with ProcessPoolExecutor(max_workers=6,mp_context=multiprocessing.get_context('fork')) as pool:
        data={name:(layers,stats) for name,layers,stats in pool.map(build_tile,manifest['tiles'])}
    totals=Counter()
    for tile in manifest['tiles']:
        layers,stats=data[tile['id']]
        for name in ('StreetEdges','FacadeDetails'):
            tile['layers'].pop(name,None)
        tile['layers'].update(layers)
        tile['street_details']=stats
        apply_tile(ROOT/'tiles'/tile['id']/'district.tscn',layers)
        totals.update(stats)
    manifest['street_details']=dict(totals)
    document.write_text(json.dumps(manifest,indent=2)+'\n')
    print(dict(totals))
