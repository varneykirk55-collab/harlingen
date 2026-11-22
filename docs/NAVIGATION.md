# Harlingen navigation

The navigation branch starts from playable integration commit `8e516f8`, with the collision repair and the existing playable coupe.

## Controls

| Action | Keyboard and mouse | Controller |
| --- | --- | --- |
| Open or close city map | M. Esc also closes. | View / Select by default. B also closes. |
| Adjust minimap zoom | = / − (numpad + / − also work) | D-pad up / down |
| Pan city map | Drag, WASD, or arrows | Left stick |
| Zoom city map | Wheel, = / −, or the on-screen zoom buttons | LB / RB |
| Set waypoint | Click the map, press Enter at the center reticle, or select a place from the list | A at the reticle |
| Clear waypoint | Right click, Delete, or Clear waypoint | X |
| Select next named place | Tab | Y |
| Center on player | F or Center player | L3 |
| Change map button | Click Map button in the sidebar | Press R3 on the map. Switches between View / Select and Menu / Start. |

The city map pauses gameplay while open and restores the previous pause and mouse state on close. A waypoint remains active while walking, driving, or crossing streamed districts. The minimap points toward offscreen waypoints and shows straight-line distance in metres or kilometres. Waypoints are session-only and have no turn-by-turn routing or teleport. Highway pins are mapped deck locations. When roads are stacked, the 2D map shows the shared ground-plane position, and the place description identifies the intended deck.

## Data and validation

The single 4K 2D atlas is generated from the existing OpenStreetMap street centerlines, land and water, and audited FAA runway endpoints. Landmark coordinates come from the project manifest. Eight freeway and overpass pins use modeled bridge ways or audited deck locations. The extent matches all 36 playable tiles. The map uses game X and Z directly, with north up, and does not load a second city scene.

To regenerate, run `python tools/build_navigation.py` with Pillow and Shapely installed. To test after a Godot 4.7.2 import, run:

```sh
godot --headless --fixed-fps 60 --path . -s tools/verify_navigation.gd
godot --headless --fixed-fps 60 --path . -s tools/verify_navigation.gd -- --mesh-ground
```

The checks cover open/close, projection, keyboard and controller inputs, drag, pointer-anchored zoom, waypoint placement and clearing, actual coupe entry/exit, a walked district crossing, and collision at all eight highway pins.
