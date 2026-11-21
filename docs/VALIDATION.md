# Build validation

## Meshes and alignment

- Verified GLB headers, buffer lengths, finite mesh data, indexed triangles and manifest counts for 451 tile GLBs and nine reusable asset GLBs.
- Verified 180 exact shared elevation borders across the high terrain, low terrain and static collision grids.
- The common grid is in projected metres. Alignment against known coordinates comes from source data rather than visual matching alone. The mapped Baxter Building footprint contains the WGS 84 coordinate listed in the National Register.
- Compared the build outline to the Census boundary in EPSG:32614. The projected overlap is 86.54 km² of the 109.06 km² incorporated polygon. [Coverage map](coverage.png)

## Godot

Godot 4.7.2 on Linux x86-64 completed a clean project import from the archive and ran the downtown viewer. The overview initialized all 36 districts and the Terrain3D runtime loaded all 100 regions. The downtown flyover loaded 15 districts based on camera location and radius.

| Collision at the tested world point | Terrain3D mode | GLB mode |
| --- | ---: | ---: |
| Ground at X 205 m, Z 320 m | Y 11.798 m | Y 11.762 m |
| Baxter roof at X 211 m, Z 350 m | Y 46.168 m | Y 46.168 m |

The small ground difference is expected from different mesh sample intervals. Collision coverage here refers to ground, building shells and close bridge decks. Street furniture can use separate colliders in a future game.

The project rendered on Mesa llvmpipe using OpenGL Compatibility at 1280 × 720. A captured downtown frame submitted about 3.15 million primitives in 633 draw calls including render passes. That is a diagnostic from a CPU-only renderer. Frame-rate and streaming budgets remain unverified on a Windows gaming laptop or discrete GPU.

## First-person controller

At 60 physics ticks per second, keyboard movement covered approximately 0.80 m at 1× and 3.20 m at 4× over 12 ticks in both terrain modes. The Baxter Building wall blocked the capsule at full speed. Automated input also verified the wheel and D-pad bounds and retained speed when switching between first person and flyover.

## Project captures

- [Downtown and the Baxter Building](downtown.png)
- [Arroyo Colorado and McKelvey Park area](arroyo-colorado.png)
- [Valley International Airport](valley-international-airport.png)
- [Full extent using the GLB terrain](overview.png)
- [Citywide coverage map](coverage.png)

## Re-run

```sh
python tools/audit.py
godot --headless --path . --editor --import
godot --headless --path . --script tools/check_scene.gd
godot --headless --path . --script tools/check_scene.gd -- --mesh-ground
godot --headless --path . --script tools/check_scene.gd -- --view=4
godot --headless --path . --fixed-fps 60 --script tools/check_walker.gd
godot --headless --path . --fixed-fps 60 --script tools/check_walker.gd -- --mesh-ground
```
