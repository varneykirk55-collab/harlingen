"""Reference model for Baxter Building, National Register #100003420."""
import numpy as np
from shapely.geometry import Polygon
from shapely.geometry.polygon import orient

BAXTER_ID='osm:way:690635467'
BAXTER_NPS='https://npgallery.nps.gov/GetAsset/409281b1-6d88-4c2b-acc4-dad2f932a17a'


def baxter(mesh,collision,poly,dem,dx,dz,patch,walls):
    outline=orient(poly,sign=1)
    corners=np.asarray(outline.minimum_rotated_rectangle.exterior.coords)[:4]
    edges=np.roll(corners,-1,axis=0)-corners
    long=edges[np.argmax(np.linalg.norm(edges,axis=1))]
    long/=np.linalg.norm(long)
    short=np.array([long[1],-long[0]])
    if short[0]<0:
        short*=-1
    east,along=corners@short,corners@long
    e,lower=east.max()-.2,along.min()+.4
    dirs=[(e-7.62,lower),(e,lower),(e,lower+42.672),(e-7.62,lower+42.672)]
    tower=orient(Polygon([short*x+long*z for x,z in dirs]),sign=1)
    c=tower.representative_point()
    y=float(dem(c.x,c.y))
    floor_heights=[0,4.6,8.3,11.9,15.5,19.1,22.7,26.3,29.9,33.6]
    top=y+34.25
    remainder=outline.difference(tower.buffer(.03))
    for g in [remainder] if remainder.geom_type=='Polygon' else getattr(remainder,'geoms',[]):
        if g.area>2 and g.geom_type=='Polygon':
            for m in (mesh,collision):
                walls(m,orient(g,sign=1),y-.35,y+5.6,'baxter_brick',dx,dz,False)
                patch(m,g,'roofs',lambda x,z:y+5.6,dx,dz)
    for target in (mesh,collision):
        walls(target,tower,y-.3,top,'baxter_brick',dx,dz,False)
        patch(target,tower,'roofs',lambda x,z:top,dx,dz)
    points=np.asarray(tower.exterior.coords)-[dx,dz]
    for p,q in zip(points,points[1:]):
        length=np.linalg.norm(q-p)
        n=(q-p)/length
        normal=np.array([n[1],-n[0]])
        bays=12 if length>18 else 3
        for j in range(9):
            floor,ceiling=floor_heights[j],floor_heights[j+1]
            for i in range(bays):
                f=(i+.5)/bays
                center=p+(q-p)*f
                full=min(1.8,length/bays*.67)
                for width,bot,height,projection,mat in [
                    (full+.23,floor+.82,(ceiling-floor)*.63+.20,.043,'baxter_trim'),
                    (full,floor+.94,(ceiling-floor)*.63,.058,'glass'),
                    (.07,floor+.94,(ceiling-floor)*.63,.075,'baxter_trim')]:
                    a=center-n*width/2+normal*projection
                    b=center+n*width/2+normal*projection
                    mesh.quad(mat,[(b[0],y+bot,b[1]),(a[0],y+bot,a[1]),
                                   (a[0],y+bot+height,a[1]),(b[0],y+bot+height,b[1])])
        for band in (8.3,29.9,33.6):
            a,b=p+normal*.15,q+normal*.15
            mesh.quad('baxter_trim',[(b[0],y+band-.12,b[1]),(a[0],y+band-.12,a[1]),
                      (a[0],y+band+.10,a[1]),(b[0],y+band+.10,b[1])])
    return 'reference_floors_height_estimated'
