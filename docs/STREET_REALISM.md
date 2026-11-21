# Street and sidewalk pass

The weathering, pavement paint, curb ramps, fittings and overhead lines cover the 36 existing districts. Open the normal Harlingen viewer and walk or fly to any district.

- Shared OSM street vertices identify 2,582 mapped public, at-grade junctions with crossings. Approach geometry is checked against the road mesh before paint is accepted. Access-controlled highways, bridges, tunnels, and private service aisles are outside the public crossing pass.
- The asphalt finish varies by block and road class. Local cracks, repair patches, tire scuffs, oil spots, visual potholes, utility covers, and grates sit over the pavement. Downtown asphalt is locally refit to the original elevation samples where long pavement triangles caused visible grade artifacts.
- Lane paint includes white edge and lane lines, yellow centerlines where appropriate, stop bars, and worn zebra stripes. Speed signs show 25, 35, or 45 mph using matching source tags when available and otherwise the road class. The numbers and placements are scenery estimates.
- Sidewalks use individual color accents, existing expansion joints, fissures, weeds, and isolated lifted slab corners. New ramps and corner links have physical walk surfaces. Small landings and connected corner walk sections cover gaps in the source sidewalk inventory where there is room.
- Furniture includes hydrants, mailboxes, newspaper and trash boxes, streetlights, and mast-arm traffic signals at major intersections. Wooden utility poles carry three sagging cables. Signal colors and lighting fixtures are static scenery.

## Editing and streaming

| Layer | Contents |
| --- | --- |
| StreetPaint.glb | Lane paint, stop bars, and zebra stripes |
| StreetWear.glb | Curb ramps, corner slabs, pavement wear, grates and other close-up details |
| StreetRampCollision.glb | Collision for ramp and sidewalk geometry |
| StreetWires.glb | Wires grouped into spatial cells |
| StreetFurniture.json | Instance transforms for the shared kit in assets/street_realism |

Keep StreetFurniture.json alongside the district scene. Include *.json in non-resource file filters when making a Godot export. The visual layers use spatial cells and a distance limit to cut down draw calls. The existing building, landmark, highway and sky assets are retained. For regeneration, run tools/street_realism.py against a fresh copy of the pre-street-pass project with the same Python GIS dependencies as the original district generator.
