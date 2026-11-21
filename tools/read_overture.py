"""Clip a STAC-selected Overture building parquet file before projecting."""
import json
from pathlib import Path
import sys

import pyarrow.dataset as ds
from shapely import from_wkb, get_coordinates
from shapely.geometry import mapping

WEST,SOUTH,EAST,NORTH=-97.765,26.140,-97.630,26.253

if __name__=='__main__':
    dataset=ds.dataset(sys.argv[1])
    intersects=(ds.field(('bbox','xmin'))<EAST)&(ds.field(('bbox','xmax'))>WEST)&(
        ds.field(('bbox','ymin'))<NORTH)&(ds.field(('bbox','ymax'))>SOUTH)
    cols=['id','geometry','sources','subtype','class','height','num_floors','roof_shape','names','is_underground']
    values=dataset.to_table(columns=cols,filter=intersects).to_pylist()
    with Path(sys.argv[2]).open('w') as output:
        for row in values:
            if row.pop('is_underground',False):
                continue
            geometry=from_wkb(row.pop('geometry'))
            if geometry is None or geometry.is_empty:
                continue
            ident=row.pop('id')
            row['name']=(row.pop('names') or {}).get('primary')
            output.write(json.dumps({'type':'Feature','id':ident,'geometry':mapping(geometry),'properties':row})+'\n')
    print(len(values))
