# Import and coordinate alignment

## Coordinate system

| Field | Value |
| --- | --- |
| Horizontal datum and projection | WGS 84 / UTM zone 14N (EPSG:32614) |
| Common reference origin | Easting 630,000 m, northing 2,898,000 m |
| Godot axes | +X east, +Y up, +Z south |
| Conversion from UTM | X = E − 630000, Z = 2898000 − N |
| Height | USGS 3DEP service output in metres. Terrain render surfaces have a 0.10 m downward offset for surface separation |
| Tile-local origin | Northwest corner. Add the tile's `x` and `z` from `manifest.json` to placement and mesh coordinates |
| Bounds | X and Z each range from −6000 m to +6000 m. Meshes touching the working border may extend across it |
| Terrain3D import padding | −6400 m origin. The outer padded grid uses edge samples to reach a 256-vertex region boundary |

## Godot

- Open a district scene to place it independently. The district root already includes its world-space tile translation.
- The viewer uses Terrain3D for the main terrain and toggles to a textured GLB terrain with **F8**. For portable district-only use, keep `TerrainMesh` or `TerrainFar` visible. For Terrain3D use, hide both mesh terrain layers and keep a single Terrain3D node at world origin.
- `Buildings.glb` contains the architecturally detailed tile layer. `BuildingsFar.glb` has simplified footprint shells. The viewer switches these automatically and keeps landmark meshes separate. Terrain has two independent GLB detail levels. Godot's GLB import settings also generate mesh LODs and baked shadow meshes.
- `tile.gd` creates MultiMesh batches from the JSON placement file, partitioned by asset type within each district. It enables collision shells near the viewer. In a different scene, call `update_detail(use_native_ground, near, detailed_buildings, collisions)` on the district and drive the arguments from your own loader. If a static build uses Terrain3D collision, skip the GLB ground collider.
- For a build exported from Godot, include `manifest.json` and `tiles/*/instances.json` in the export preset's non-resource filter. Include the dynamically loaded tile and prop scenes rather than exporting only direct scene dependencies. The project is supplied as editable source for importing and running from the editor.

## Terrain3D source import

The included regions are ready to load. To rebuild the regions, run this from the project folder after an editor import.

```sh
godot --headless --path . --script tools/import_terrain.gd
```

For manual import, use `terrain/harlingen_height.r16` as little-endian, unsigned R16 with dimensions 2560 × 2560 and range −4 m to 28 m. Use `terrain/surface_color.png` as the color map. Set 5 m vertex spacing, 256 × 256 region size and import position **(−1280, −1280)** in Terrain3D importer's vertex coordinates. Save the regions into `terrain/regions/` or a separate directory for an edited version. The first DEM pixel center is at local (−6000, −6000). Image rows run south.

## Unity or Blender

1. Import the desired tile GLB layers with the application's glTF importer. In Unity, use an installed glTF 2.0 importer. Use 1 m per unit and keep terrain and buildings at the same scale.
2. Parent the tile's meshes beneath a common origin. Place the parent by the manifest's east and south offsets after applying your importer's axis conversion. Confirm orientation with a known point, such as the Baxter Building at local X 206.86 m, Z 348.75 m.
3. Select either high or low terrain and building geometry. Use the supplied collision GLBs as static, non-rendering triangle meshes where useful. In neighborhoods, utility details are typically handled separately from major collision geometry.
4. Instantiate the matching `assets/<key>.glb` for each `instances.json` row. Each row is `[tile_x_m, world_height_m, tile_z_m, yaw_radians, uniform_scale]`. Yaw uses Godot's +Y rotation. Apply the same axis conversion to positions and orientations.
5. Preserve the project attribution from [Accuracy and sources](ACCURACY.md) when publishing.

## Rebuild the GLBs

The supplied GLBs are immediately usable. Rebuilding uses Python 3 with NumPy, Pillow, Shapely 2.2 or newer, pyproj and mapbox-earcut. The included builder uses Linux multiprocessing. PyArrow is needed only when downloading and clipping a new Overture release.

```sh
python -m pip install "shapely>=2.2" numpy pillow pyproj mapbox-earcut
python tools/build.py
python tools/audit.py
godot --headless --path . --script tools/import_terrain.gd
godot --headless --path . --editor --import
```

The provided compressed vector GeoJSON-shaped extracts use documented local metre coordinates, with their second coordinate increasing south. Convert these back to UTM or WGS 84 before importing into a conventional GIS expecting standard GeoJSON longitude and latitude. `source/us_census_harlingen_boundary.geojson` uses ordinary WGS 84 coordinates.
