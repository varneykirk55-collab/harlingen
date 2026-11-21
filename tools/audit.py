"""Validate the delivered GLB buffers, shared terrain borders, and tile inventory."""
from collections import Counter
import json
from pathlib import Path
import struct

import numpy as np

ROOT=Path(__file__).resolve().parents[1]


def inspect(path):
    b=path.read_bytes()
    magic,version,size=struct.unpack_from('<4sII',b)
    assert (magic,version,size)==(b'glTF',2,len(b)),path
    header_size,tag=struct.unpack_from('<I4s',b,12)
    assert tag==b'JSON',path
    doc=json.loads(b[20:20+header_size])
    data_size,tag=struct.unpack_from('<I4s',b,20+header_size)
    bin_pos=28+header_size
    assert tag==b'BIN\0' and bin_pos+data_size==len(b),path
    assert doc['buffers'][0]['byteLength']==data_size,path

    def values(index):
        a=doc['accessors'][index]
        v=doc['bufferViews'][a['bufferView']]
        width={'SCALAR':1,'VEC2':2,'VEC3':3}[a['type']]
        dtype={5125:'<u4',5126:'<f4'}[a['componentType']]
        assert width*4*a['count']==v['byteLength'],path
        assert v['byteOffset']+v['byteLength']<=data_size,path
        return np.frombuffer(b,dtype,count=width*a['count'],offset=bin_pos+v['byteOffset']).reshape(-1,width)

    count=0
    position=None
    for primitive in (p for mesh in doc['meshes'] for p in mesh['primitives']):
        position=values(primitive['attributes']['POSITION'])
        normals=values(primitive['attributes']['NORMAL'])
        triangles=values(primitive['indices'])
        assert np.isfinite(position).all() and np.isfinite(normals).all(),path
        assert len(position)==len(normals) and triangles.max()<len(position),path
        assert len(triangles)%3==0,path
        count+=len(triangles)//3
    return count,position


def main():
    manifest=json.loads((ROOT/'manifest.json').read_text())
    tiles=manifest['tiles']
    assert len(tiles)==36
    assert len(list((ROOT/'terrain'/'regions').glob('*.res')))==100
    grids={}
    counts=Counter()
    for tile in tiles:
        td=ROOT/'tiles'/tile['id']
        assert (td/'district.tscn').exists()
        if tile['instances']:
            props=json.loads((td/'instances.json').read_text())
            assert sum(map(len,props.values()))==tile['instances']
            for kit,rows in props.items():
                assert kit in manifest['prop_kit']
                assert all(len(row)==5 and 0<=row[0]<=2000 and 0<=row[2]<=2000 for row in rows)
        xy=(tile['x'],tile['z'])
        for key,layer in tile['layers'].items():
            triangles,v=inspect(ROOT/layer['file'])
            assert triangles==layer['triangles']
            if key in ('TerrainMesh','TerrainFar','GroundCollision'):
                n=round(len(v)**.5)
                assert n*n==len(v),key
                grids[key,xy]=v[:,1].reshape(n,n)
            counts['tile_glbs']+=1
    for (layer,(x,z)),a in grids.items():
        east=grids.get((layer,(x+2000,z)))
        south=grids.get((layer,(x,z+2000)))
        if east is not None:
            assert np.array_equal(a[:,-1],east[:,0]),(x,z,'east')
            counts['matching_edges']+=1
        if south is not None:
            assert np.array_equal(a[-1,:],south[0,:]),(x,z,'south')
            counts['matching_edges']+=1
    for kit in manifest['prop_kit']:
        inspect(ROOT/'assets'/f'{kit}.glb')
    print(dict(counts), 'asset kit meshes', len(manifest['prop_kit']),'tiles',len(tiles))


if __name__=='__main__':
    main()
