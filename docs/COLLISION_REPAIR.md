# Playable collision repair

The repair starts from playable integration commit `6ab1472`, including the Jackson Street visual pass. It applies to the existing `HarlingenVehicle` coupe.

- Districts build solid prop collision from their existing instance transforms. Palms use a tapered trunk, poles use fitted cylinders, and rigid furniture uses fitted boxes or cylinders. Jackson's added trees use their visible trunk surfaces. Its benches, signs, lamps, bins, planters and parked cars have collision. Low vegetation and decorative road markings remain traversable.
- Curbs, sidewalks, roads and parking surfaces use the existing geometry. The original building, bridge and curb-ramp colliders stay loaded on world layer 1. The player and vehicle retain their original collision masks.
- The coupe now uses continuous collision detection, tire radii fitted to the wheel meshes, and more suspension droop through corrected hardpoints, rest length and spring tuning. Wheel visuals follow the loaded tire contact plane. Throttle, braking, steering and camera settings are unchanged.

## Godot 4.7.2 verification

| Test | Result |
| --- | --- |
| Jackson Street, East Tyler in both directions, and North Ed Carey Drive | In both terrain modes, four parked wheels contacted the road. Estimated parked visual tire clearance was within 2 mm at the sampled positions, compared with 19–20 cm of penetration at the baseline Jackson position. All four drive runs per terrain mode maintained at least three contacting wheels during all 80 sampled acceleration frames. |
| Prop contact | Both playable-body sweeps blocked against tested trees, utility poles, lamps, signs and furniture. The player stopped at a Jackson planter. The coupe struck a parked sedan at 16 m/s without passing through it. |
| Curbs, buildings, bridges | Jackson curb contact and the Baxter building regression passed. All 18 existing bridge collision checks passed. |
| General validation | The pre-existing Godot integration suite passed in Terrain3D and GLB modes. The asset audit checked 36 tiles, 659 tile GLBs, and 180 matching terrain edges. |

The tested Tyler travel lanes passed. A steep seam in the existing East Tyler road mesh near world X=470, Z=659 still causes a local tire-height variation if the coupe straddles it. Collision follows the existing pavement there. A full manual drive of every district remains outstanding.

To rerun, import the project in Godot 4.7.2 and run:

```sh
godot --headless --path . -s tools/verify_collision_repair.gd
godot --headless --path . -s tools/verify_collision_repair.gd -- --mesh-ground
godot --headless --path . -s tools/verify_integration.gd
godot --headless --path . -s tools/verify_integration.gd -- --mesh-ground
godot --headless --path . -s tools/verify_bridge_clearance.gd
python tools/audit.py
```
