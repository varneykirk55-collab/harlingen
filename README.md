# Harlingen, Texas

A 1:1 Godot 4 environment of central Harlingen and surrounding South Texas. The 12 × 12 km working area contains 36 independently loadable 2 × 2 km districts. It covers about 79% of the U.S. Census incorporated-city polygon by area, including the central street grid and Valley International Airport. The square also includes parts of nearby communities and farm country.

## Open the project

1. Extract the entire archive into a local folder, such as `Documents/Harlingen`.
2. In the **Godot 4.7.2** Project Manager, select **Import**, then open `Harlingen/project.godot`.
3. Let Godot finish the first import. On the first launch, press **F5** to open the environment viewer. Compatibility/OpenGL is selected. Terrain3D 1.1.0 and its 100 compiled terrain regions are included for Windows and Linux x86-64.
4. The project opens on foot downtown. Use **WASD** and mouse look, or the left and right gamepad sticks. Use **Space** or gamepad **A** to jump. Press **Esc** to release the mouse and click the viewport to capture it again.
5. Use the **mouse wheel**, **+ / −**, or gamepad **D-pad Up / Down** to adjust first-person speed from **1× to 4×** in 0.25× steps. Base speed is 4 m/s, with a maximum of 16 m/s. **Home** returns you to the downtown spawn.
6. Press **F7** to switch between first person and flyover. **1–4** open the flyover bookmarks. In flyover, hold the right mouse button to look and use **WASD** to fly, **R/F** to rise or descend, **Shift** for a speed boost, and the wheel to change flyover speed. **F8** switches terrain mode and **F9** toggles the overlay.

To edit a district directly, open its `tiles/<id>/district.tscn`. Downtown and the Baxter Building are in `tiles/+00_+00/`. For a permanent build, instance selected district scenes in your own scene and preserve the district origins. `preview/Harlingen.tscn` streams districts around the active first-person or flyover camera.

## Provided files

| Path | Contents |
| --- | --- |
| `project.godot` | Godot project and compatibility renderer settings |
| `terrain/regions/` | Editable Terrain3D height and color regions with dynamic collision in the viewer |
| `terrain/harlingen_height.r16` and `surface_color.png` | Height and color sources for Terrain3D reimport |
| `tiles/<id>/district.tscn` | One independent Godot district with tile translation |
| `tiles/<id>/*.glb` | Standalone buildings, road surfaces, bridges, sidewalks, lane markings, land cover and parking, water, rail/runways and terrain, where present |
| `tiles/<id>/*Collision.glb` | Simplified static ground, building and bridge geometry, where present |
| `tiles/<id>/instances.json` | Tile-local vegetation, lighting, utility and sign placement transforms |
| `assets/` | Reusable GLB prop kit and original façade atlas |
| `manifest.json` | Tile origins, actual mesh files and triangle counts, instance and building totals, mapped place inventory and reference-model source |
| `source/` | Clipped source vector layers with feature identifiers, Census boundary, USGS elevation raster and NAIP orthoimage |
| `tools/` | GIS extraction, reproducible mesh generation, Terrain3D import and validation |
| `docs/` | Integration instructions, source attribution, validation and captured project views |

## Scope and accuracy

The build contains 32,642 building shells, 9,480 instanced vegetation and props, and data for 8,196 road/path centerline features. The OSM vectors include expressways, residential streets, rail, runways, parks, and the Arroyo Colorado and drainage network. Building footprints come from OpenStreetMap and Overture Maps. Height statistics count source height values and two kinds of estimates. A value in the source can itself be estimated.

The Baxter Building is a separate nine-story reference model. Its plan dimensions, narrow form, flat roof, bay counts and horizontal façade divisions follow the National Register documentation. Its total height, current storefront treatment and fine details are approximated. The airport's runway/taxiway alignment and the terminal footprint come from mapped data. Other named places may be represented by mapped land, shells or location records. The full evidence and limitations are in [Accuracy and sources](docs/ACCURACY.md).

[Daylight and materials](docs/ATMOSPHERE.md) · [Street and façade detail](docs/STREET-DETAIL.md) · [Downtown signs and vegetation](docs/STREETSCAPE.md) · [Surface materials and texture credits](docs/MATERIALS.md) · [Godot, Unity and Blender integration](docs/IMPORT.md) · [Validation](docs/VALIDATION.md)
