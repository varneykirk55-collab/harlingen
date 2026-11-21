"""Generate a low-poly memorial proxy scaled to the academy's published dimensions."""
import math

import numpy as np

from mesh import Mesh, PALETTE, box, write_glb

FOOT = .3048
PLINTH = 10*FOOT
ROCK_RISE = 6*FOOT
FIGURE_SCALE = 32*FOOT
POLE_LENGTH = 78*FOOT

PALETTE.update({
    'memorial_granite':(.115,.12,.127), 'memorial_trim':(.19,.19,.19),
    'memorial_rock':(.25,.23,.205), 'memorial_figure':(.32,.27,.19),
    'memorial_uniform':(.34,.29,.205), 'memorial_helmet':(.27,.235,.18),
    'memorial_pole':(.65,.66,.65), 'memorial_flag_red':(.58,.15,.18),
    'memorial_flag_white':(.88,.87,.82), 'memorial_flag_blue':(.12,.19,.38)
})


def tube(mesh, material, a, b, radii, sides=8):
    a,b = np.asarray(a,dtype=float),np.asarray(b,dtype=float)
    axis=(b-a)/np.linalg.norm(b-a)
    cross=np.cross(axis,(0,1,0) if abs(axis[1])<.88 else (1,0,0))
    cross/=np.linalg.norm(cross)
    normal=np.cross(axis,cross)
    directions=[math.cos(i*math.tau/sides)*cross+math.sin(i*math.tau/sides)*normal for i in range(sides)]
    first=[a+radii[0]*v for v in directions]
    last=[b+radii[1]*v for v in directions]
    for i in range(sides):
        j=(i+1)%sides
        mesh.quad(material,[first[i],first[j],last[j],last[i]])
    mesh.add(material,last,[k for i in range(1,sides-1) for k in (0,i,i+1)])
    mesh.add(material,first,[k for i in range(1,sides-1) for k in (0,i+1,i)])


def figure(mesh, position, size, support, pitch):
    feet=np.asarray(position)
    lean=np.array([1.,0.,pitch])
    hip=feet+size*(np.array([0,.47,0])+.10*lean)
    shoulder=feet+size*(np.array([0,.77,0])+.23*lean)
    head=feet+size*(np.array([0,.90,0])+.31*lean)
    side=np.array([-.35*pitch,0,.55])
    tube(mesh,'memorial_uniform',hip,shoulder,(size*.122,size*.175))
    tube(mesh,'memorial_figure',shoulder,head,(size*.082,size*.064))
    tube(mesh,'memorial_figure',head-size*np.array([0,.052,0]),head+size*np.array([0,.023,0]),(size*.072,size*.087))
    tube(mesh,'memorial_helmet',head,head+size*np.array([.019,.10,0]),(size*.095,size*.051))
    for i,sign in enumerate((-1,1)):
        boot=feet+sign*.30*size*side-size*(.16 if i else .035)*lean
        knee=(boot+hip)*.5+size*(.04 if i else -.03)*lean
        tube(mesh,'memorial_uniform',hip+sign*.105*size*side,knee,(size*.085,size*.063))
        tube(mesh,'memorial_figure',knee,boot,(size*.066,size*.039))
        tube(mesh,'memorial_helmet',boot,boot+size*.13*lean,(size*.045,size*.033))
        arm=shoulder+sign*.26*size*side
        hand=support+sign*.15*side
        elbow=(arm+hand)*.5+size*np.array([-.10,-.10,.04*sign])
        tube(mesh,'memorial_uniform',arm,elbow,(size*.065,size*.050))
        tube(mesh,'memorial_figure',elbow,hand,(size*.051,size*.028))


def flag(mesh, pole_end):
    x,y,z=pole_end
    def point(u,v):
        return (x+u*3.8,y-v*2.05-.12*u,z+math.sin(u*math.tau)*.17)
    for row in range(13):
        material='memorial_flag_red' if row%2==0 else 'memorial_flag_white'
        left=.42 if row<7 else 0.
        for a,b in zip(np.linspace(left,1,5),np.linspace(left,1,5)[1:]):
            quad=[point(u,v) for u,v in [(a,row/13),(b,row/13),(b,(row+1)/13),(a,(row+1)/13)]]
            mesh.quad(material,quad)
            mesh.quad(material,quad[::-1])
    quad=[point(u,v) for u,v in [(0,0),(.42,0),(.42,7/13),(0,7/13)]]
    mesh.quad('memorial_flag_blue',quad)
    mesh.quad('memorial_flag_blue',quad[::-1])


def build_memorial(path):
    mesh=Mesh()
    box(mesh,'memorial_granite',0,-.23,0,16.8,PLINTH+.23,11.4)
    box(mesh,'memorial_trim',0,PLINTH-.24,0,17.0,.24,11.6)
    box(mesh,'memorial_trim',0,-.16,0,17.2,.33,11.8)
    bottom=PLINTH
    for x,z,w,d,r in [(-2.1,0,11.,7.6,.64),(-2.7,0,8.8,6.8,.53),(-3.4,.35,6.8,5.4,.40),(-4.,.5,4.6,4.5,.2588)]:
        box(mesh,'memorial_rock',x,bottom,z,w,r,d)
        bottom+=r
    slope=PLINTH+ROCK_RISE
    pole_a=np.array([4.25,PLINTH+.3,-.18])
    direction=np.array([.61,.788,-.083])
    direction/=np.linalg.norm(direction)
    pole_b=pole_a+direction*POLE_LENGTH
    tube(mesh,'memorial_pole',pole_a,pole_b,(.12,.085),10)
    tallest=np.array([-4.65,slope,1.65])
    figure(mesh,tallest,FIGURE_SCALE,(3.05,11.35,-.10),-.19)
    for x,y,z,scale,grip,turn in [
        (-4.5,PLINTH+1.17,-1.7,.87,(1.3,11.4,-.36),.30),
        (-2.65,PLINTH+1.57,.5,.88,(4.65,9.2,.42),-.34),
        (-1.3,PLINTH+1.17,-1.65,.82,(4.75,8.7,-.52),.14),
        (-.08,PLINTH+.64,1.75,.78,(6.65,7.6,.2),-.21),
        (2.65,PLINTH+.15,-.37,.67,(5.30,6.5,-.30),.17),
    ]:
        figure(mesh,(x,y,z),FIGURE_SCALE*scale,grip,turn)
    flag(mesh,pole_b)
    write_glb(path,'IwoJimaMemorial',mesh)
    return mesh.triangles()
