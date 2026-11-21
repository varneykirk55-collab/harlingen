"""Create the small, instanced vegetation kit used by Harlingen."""
from pathlib import Path
import math
import random

from mesh import Mesh, PALETTE, cylinder, write_glb

PALETTE['dry_grass'] = (.63, .49, .29)
PALETTE['palm_young'] = (.42, .53, .25)
PALETTE['palm_fiber'] = (.41, .32, .22)


def palm():
    mesh = Mesh()
    # A wide foot and narrowing, slightly curved trunk. Seven faces per ring.
    stations = [(0., 0., .25), (.56, .01, .16), (3.8, .09, .133),
                (6.4, .29, .119), (7.1, .35, .18)]
    rings = []
    for height, lean, radius in stations:
        rings.append([(lean + radius * math.cos(i * math.tau / 7), height,
                       radius * math.sin(i * math.tau / 7)) for i in range(7)])
    for ring_low, ring_high in zip(rings, rings[1:]):
        for i in range(7):
            j = (i + 1) % 7
            mesh.quad('trunk', [ring_low[i], ring_high[i], ring_high[j], ring_low[j]])
    cylinder(mesh, 'palm_fiber', .36, 0, 6.76, 7.21, .25, .23, 7)
    # Folded blades give each frond a ridge and an arc, with tips in distinct directions.
    for i in range(11):
        heading = i * 2.399963 + .19
        reach = [2.43, 1.87, 2.61, 2.12, 2.32][i % 5]
        young = i >= 8
        crown_height = 7.1 + (.14 if young else 0)
        if young:
            reach *= .62
        c, s = math.cos(heading), math.sin(heading)
        blade = [(0, 0, 0), (.34, .55, 0), (.34, .44, .20), (.34, .44, -.20),
                 (.70, .46, 0), (.69, .36, .14), (.69, .36, -.14),
                 (1, .12 if young else -.5 - .13 * (i % 3), 0)]
        points = [(.35 + c * reach * d - s * w, crown_height + h + (.23 * d if young else 0),
                   s * reach * d + c * w) for d, h, w in blade]
        mesh.add('palm_young' if young else 'palm', points,
                 [0, 1, 2, 0, 3, 1, 1, 4, 5, 1, 5, 2, 1, 3, 6, 1, 6, 4,
                  4, 7, 5, 4, 6, 7])
    return mesh


def scrub():
    mesh = Mesh()
    rng = random.Random(7)
    # Low rounded foliage clumps with uneven profiles and broad shoulders.
    for cx, cz, wide, tall in [(-.24, .03, .30, .42), (.23, -.07, .34, .47),
                                (.04, .20, .28, .34)]:
        count = 7
        rings = []
        for y, width in [(.10, .72), (.24, 1.0), (tall, .51)]:
            rings.append([(cx + wide * width * math.cos(i * math.tau / count) * rng.uniform(.91, 1.08),
                        y + rng.uniform(-.038, .038), cz + wide * width * math.sin(i * math.tau / count))
                        for i in range(count)])
        for band in range(2):
            for i in range(count):
                j = (i + 1) % count
                mesh.quad('leaf_light' if band else 'leaf',
                          [rings[band][i], rings[band+1][i], rings[band+1][j], rings[band][j]])
        mesh.add('leaf_light', rings[-1], [idx for i in range(1,count-1) for idx in (0,i+1,i)])
    return mesh


def dry_grass():
    mesh = Mesh()
    rng = random.Random(91)
    for i in range(11):
        theta = i * math.tau / 11
        c, s = math.cos(theta), math.sin(theta)
        height = rng.uniform(.22,.53)
        reach = rng.uniform(.17,.33)
        points = [(c*.04-s*.023, 0, s*.04+c*.023), (c*.04+s*.023,0,s*.04-c*.023),
                  (c*reach*.41+s*.016,height*.7,s*reach*.41-c*.016),
                  (c*reach*.41-s*.016,height*.7,s*reach*.41+c*.016),
                  (c*reach,height,s*reach)]
        mesh.add('dry_grass', points, [0,1,2,0,2,3,3,2,4])
    return mesh


def kit_meshes():
    return {'palm': palm(), 'scrub': scrub(), 'dry_grass': dry_grass()}


if __name__ == '__main__':
    assets = Path(__file__).resolve().parents[1] / 'assets'
    for name, mesh in kit_meshes().items():
        write_glb(assets / f'{name}.glb', name, mesh)
        print(name, mesh.triangles())
