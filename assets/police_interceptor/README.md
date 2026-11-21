# Sunshine City Police Interceptor

The supplied 2020 Ford Police Interceptor Utility GLB is the donor. The four supplied photos specify the livery and equipment. They show an earlier body style, so the 2020 fascia, hatch, dimensions, and panel lines remain identifiable. The livery reproduces the main visual elements from the photos on those panels, including the blue-white-red sweep, oversized POLICE wordmark, front-door badge position, rear motto, unit 781 and emergency 911.

The departmental badge was redrawn in pale gold, muted blue and charcoal with a small sunrise emblem and Sunshine City Police Department text. No Harlingen department graphics were carried over. The straight-on views show the retained Ford marks and the Texas plate treatment. The opposite flank uses the visible side's placement and independent, correctly reading text. The two small rear-window passes are visual approximations because their lettering is illegible in the references.

## Files

- `Sunshine_City_Police_Interceptor.blend` contains the editable vehicle, packed texture atlas, source interior and four studio camera setups. The Studio collection is for Blender review.
- `Sunshine_City_Police_Interceptor.glb` contains the vehicle and PBR textures. Import it in Godot 4.7.2 as a PackedScene or instantiate it in a separate asset review scene.
- `Sunshine_City_Livery.png` is the 2048×2048 decal atlas embedded in both files.
- The four angle-matched renders are in [docs/police-interceptor](../../docs/police-interceptor).

## Pivots

| Assembly | Nodes | Godot local axis |
| --- | --- | --- |
| Front steering | `Steer_FL`, `Steer_FR` | Y |
| Wheel spin | `Wheel_FL_Spin`, `Wheel_FR_Spin`, `Wheel_RL_Spin`, `Wheel_RR_Spin` | X |
| Door hinges | `Door_FL_Hinge`, `Door_FR_Hinge`, `Door_RL_Hinge`, `Door_RR_Hinge` | Y |

The wheel hubs use the donor's axle centers. Brake meshes follow the hubs and steering, with tires and rims on separate spin pivots. All four doors use the donor's existing geometry islands. The door panels, inner trims, side glass and projected decals travel with their hinges. Front mirrors move with the front doors. The donor's jambs and pillars stay fixed, and the rear hatch and hood remain fixed. The hinge locations are modeled pivots rather than measured mechanical hinges. The source's simple interior and jamb detail are visible with the doors open.

Godot uses metres, +Y up and +Z forward. The ground origin is at tire contact and the measured wheelbase is 3.025 m, scaled uniformly from [Ford’s 119.1-inch specification](https://www.ford.com/cmslibs/content/dam/brand_ford/en_us/brand/resources/general/pdf/brochures/2020_PI_Utility_Mini-Brochure2_lr.pdf). The overall asset bounds with mirrors and equipment are approximately 2.29 m wide × 1.86 m high × 5.28 m long. The roof bar, push bumper, front warning modules and rear hardware are static visual meshes.

## Validation and remaining limits

- Blender pivot tests checked child motion and stable pivot origins. Godot 4.7.2 imported the final GLB in a standalone project and exercised the four hinges, four spin nodes, two steering nodes, ground height and scale. It also checked PBR material presence and the embedded decal atlas.
- The exported GLB has approximately 177,000 triangles, after simplifying the densest donor accessories, tread and grille meshes and consolidating rigid parts. It is a close-range asset. Distance LOD meshes for fleet-scale spawning are still outstanding.
- The package contained no author or license metadata. The source is identified here by the supplied archive and `Ford_Police_Interceptor_Utility_2020_lights.glb` filename. Upstream attribution terms remain unverified.
