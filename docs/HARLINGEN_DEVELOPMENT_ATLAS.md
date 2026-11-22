# Harlingen Development Atlas

> Auto-generated from `C:\Users\aresg\Projects\harlingen-integration` on `2026-11-22T03:38:48Z` (schema `1.1.0`).

## 1. Project & Coordinate System
- **CRS**: `EPSG:32614` (Origin Easting `630000`, Northing `2898000`)
- **Grid**: `36` tiles (`2000 m` each), local extent `[-6000, -6000, 6000, 6000]`
- **Citywide Totals**: `32,343` buildings | `12,794,440` tile triangles | `9,074` prop instances | `369,161.4 m` curbs | `8,342` crosswalks | `441` signals
- **Coverage**: `23/36` tiles with Sidewalks | `6/36` with ElevatedRoads | `24/36` with legacy `Bridges.glb`

## 2. 36-District Tile Matrix

| Tile | Origin (X, Z) | Bldgs | Tris | MB | Sidewalks | Curbs (m) | Crosswalks | Signals | Legacy Bridge Tris | Elevated Tris | External Scenes |
| --- | --- | ---: | ---: | ---: | :---: | ---: | ---: | ---: | ---: | ---: | --- |
| `-03_-03` | `(-6000, -6000)` | 262 | 125,042 | 5.11 | Yes | 665.9 | 24 | 0 | 0 | 0 | - |
| `-02_-03` | `(-4000, -6000)` | 914 | 237,685 | 11.17 | Yes | 4,478.2 | 181 | 2 | 66 | 0 | - |
| `-01_-03` | `(-2000, -6000)` | 689 | 183,587 | 8.31 | No | 0.0 | 146 | 0 | 26 | 0 | - |
| `+00_-03` | `(0, -6000)` | 312 | 135,356 | 5.64 | No | 0.0 | 38 | 0 | 22 | 0 | - |
| `+01_-03` | `(2000, -6000)` | 85 | 101,265 | 3.58 | No | 0.0 | 19 | 4 | 24 | 0 | - |
| `+02_-03` | `(4000, -6000)` | 85 | 94,520 | 3.24 | No | 0.0 | 8 | 0 | 0 | 0 | - |
| `-03_-02` | `(-6000, -4000)` | 1102 | 241,788 | 11.68 | Yes | 910.3 | 208 | 4 | 0 | 0 | - |
| `-02_-02` | `(-4000, -4000)` | 654 | 212,782 | 9.87 | Yes | 586.0 | 205 | 11 | 467 | 0 | ValeroLoop499.tscn |
| `-01_-02` | `(-2000, -4000)` | 1222 | 300,363 | 14.67 | Yes | 2,544.2 | 293 | 13 | 64 | 0 | - |
| `+00_-02` | `(0, -4000)` | 1605 | 446,747 | 22.96 | Yes | 4,148.5 | 447 | 24 | 16 | 0 | - |
| `+01_-02` | `(2000, -4000)` | 516 | 295,574 | 13.77 | Yes | 12,668.2 | 295 | 29 | 22 | 0 | - |
| `+02_-02` | `(4000, -4000)` | 18 | 96,372 | 3.29 | No | 0.0 | 22 | 0 | 0 | 0 | - |
| `-03_-01` | `(-6000, -2000)` | 1512 | 311,417 | 15.77 | Yes | 15.3 | 429 | 4 | 0 | 0 | - |
| `-02_-01` | `(-4000, -2000)` | 934 | 290,485 | 14.53 | Yes | 1,930.6 | 273 | 0 | 87 | 15,334 | - |
| `-01_-01` | `(-2000, -2000)` | 1603 | 420,804 | 20.76 | Yes | 19,605.7 | 343 | 5 | 0 | 0 | - |
| `+00_-01` | `(0, -2000)` | 2298 | 675,183 | 33.87 | Yes | 52,939.0 | 656 | 33 | 0 | 0 | StripesSunshine.tscn |
| `+01_-01` | `(2000, -2000)` | 1353 | 353,931 | 17.69 | Yes | 7,113.2 | 298 | 33 | 0 | 0 | - |
| `+02_-01` | `(4000, -2000)` | 91 | 113,665 | 4.25 | No | 0.0 | 47 | 0 | 0 | 0 | - |
| `-03_+00` | `(-6000, 0)` | 1093 | 286,928 | 14.1 | Yes | 1,207.5 | 365 | 11 | 126 | 0 | - |
| `-02_+00` | `(-4000, 0)` | 815 | 501,934 | 26.64 | Yes | 7,159.9 | 259 | 17 | 36 | 123,972 | - |
| `-01_+00` | `(-2000, 0)` | 1993 | 869,363 | 45.14 | Yes | 69,873.6 | 580 | 46 | 0 | 122,926 | - |
| `+00_+00` | `(0, 0)` | 2649 | 1,290,612 | 94.42 | Yes | 157,302.5 | 956 | 127 | 111 | 0 | DowntownStreetscape.tscn |
| `+01_+00` | `(2000, 0)` | 1836 | 935,189 | 44.26 | Yes | 5,959.0 | 428 | 9 | 75 | 9,360 | RamseyTrailhead.tscn, EdCareyStreetscape_01_00.tscn |
| `+02_+00` | `(4000, 0)` | 469 | 192,485 | 8.94 | Yes | 1,088.6 | 133 | 0 | 40 | 0 | - |
| `-03_+01` | `(-6000, 2000)` | 885 | 226,710 | 10.91 | Yes | 588.6 | 190 | 2 | 40 | 0 | - |
| `-02_+01` | `(-4000, 2000)` | 734 | 205,618 | 9.6 | No | 0.0 | 180 | 12 | 24 | 0 | - |
| `-01_+01` | `(-2000, 2000)` | 1005 | 300,658 | 15.13 | Yes | 1,737.4 | 185 | 2 | 116 | 38,670 | - |
| `+00_+01` | `(0, 2000)` | 1597 | 721,915 | 32.84 | Yes | 12,393.1 | 211 | 4 | 1,530 | 13,664 | EdCareyStreetscape_00_01.tscn |
| `+01_+01` | `(2000, 2000)` | 795 | 1,066,980 | 49.08 | Yes | 4,246.1 | 230 | 22 | 134 | 0 | EdCareyStreetscape_01_01.tscn |
| `+02_+01` | `(4000, 2000)` | 298 | 167,021 | 7.43 | No | 0.0 | 128 | 9 | 18 | 0 | - |
| `-03_+02` | `(-6000, 4000)` | 326 | 132,595 | 5.52 | No | 0.0 | 37 | 0 | 20 | 0 | - |
| `-02_+02` | `(-4000, 4000)` | 201 | 114,644 | 4.47 | No | 0.0 | 67 | 0 | 24 | 0 | - |
| `-01_+02` | `(-2000, 4000)` | 234 | 127,216 | 5.26 | No | 0.0 | 26 | 4 | 76 | 0 | - |
| `+00_+02` | `(0, 4000)` | 566 | 592,648 | 26.58 | Yes | 0.0 | 144 | 0 | 0 | 0 | EdCareyStreetscape_00_02.tscn |
| `+01_+02` | `(2000, 4000)` | 625 | 184,859 | 8.59 | No | 0.0 | 92 | 3 | 92 | 0 | HarlingenMedicalCenter.tscn |
| `+02_+02` | `(4000, 4000)` | 967 | 240,499 | 11.76 | No | 0.0 | 199 | 11 | 0 | 0 | - |

## 3. Poly Haven Library Summary
- **PBR Texture Sets**: `23` sets
- **Terrain3D Packed Slots**: `9` files
- **HDRIs**: `1` (`kloofendal_48d_partly_cloudy_puresky_2k`)

| Texture ID | Res | Maps | Path |
| --- | :---: | ---: | --- |
| `asphalt_01` | 2K | 4 | `materials/polyhaven/asphalt_01/` |
| `asphalt_02` | 2K | 4 | `materials/polyhaven/asphalt_02/` |
| `asphalt_04` | 2K | 4 | `materials/polyhaven/asphalt_04/` |
| `asphalt_06` | 1K | 4 | `materials/polyhaven/asphalt_06/` |
| `bark_brown_02` | 1K | 4 | `materials/polyhaven/bark_brown_02/` |
| `beige_wall_001` | 2K | 4 | `materials/polyhaven/beige_wall_001/` |
| `brick_wall_006` | 2K | 4 | `materials/polyhaven/brick_wall_006/` |
| `brown_mud_dry` | 2K | 4 | `materials/polyhaven/brown_mud_dry/` |
| `concrete_floor_worn_001` | 2K | 4 | `materials/polyhaven/concrete_floor_worn_001/` |
| `concrete_pavement` | 2K | 4 | `materials/polyhaven/concrete_pavement/` |
| `concrete_wall_007` | 1K | 4 | `materials/polyhaven/concrete_wall_007/` |
| `corrugated_iron` | 1K | 4 | `materials/polyhaven/corrugated_iron/` |
| `gravel_road` | 2K | 4 | `materials/polyhaven/gravel_road/` |
| `grey_roof_01` | 1K | 4 | `materials/polyhaven/grey_roof_01/` |
| `leafy_grass` | 2K | 4 | `materials/polyhaven/leafy_grass/` |
| `metal_plate_02` | 1K | 4 | `materials/polyhaven/metal_plate_02/` |
| `painted_plaster_wall` | 1K | 4 | `materials/polyhaven/painted_plaster_wall/` |
| `red_brick_03` | 2K | 4 | `materials/polyhaven/red_brick_03/` |
| `rough_block_wall` | 1K | 4 | `materials/polyhaven/rough_block_wall/` |
| `rough_wood` | 1K | 4 | `materials/polyhaven/rough_wood/` |
| `rusty_metal_02` | 1K | 4 | `materials/polyhaven/rusty_metal_02/` |
| `sandstone_blocks_05` | 2K | 4 | `materials/polyhaven/sandstone_blocks_05/` |
| `withered_grass` | 2K | 4 | `materials/polyhaven/withered_grass/` |

## 4. Target Harlingen Landmarks & Geographic Sites

| Category | Matches | Sample Tiles / Notes |
| --- | ---: | --- |
| `church` | 65 | +00_+00, +00_-01, +00_-02, +01_+01, +01_-01, -01_+00, -01_-01, -02_-02, -02_-03 |
| `heart_clinic` | 2 | -01_+00 |
| `heb` | 12 | +00_+00, +01_-01, -01_+00 |
| `iwo_jima` | 8 | +01_-02 |
| `mckelvey` | 1 | +01_+00 |
| `police` | 4 | +02_+02, -01_-01 |
| `walmart` | 2 | -01_+00 |
| `whataburger` | 6 | +00_+00, +01_+01, -01_+00 |

## 5. Citywide Detailing Systems & Worker Ownership

| Role / Module | Agent | Script / Class | Owned Paths |
| --- | --- | --- | --- |
| `integration_owner` | `atlas-inventor` | `-` | `preview/tile.gd`, `tools/generate_atlas.py`, `docs/HARLINGEN_ATLAS.json`, `docs/HARLINGEN_DEVELOPMENT_ATLAS.md` |
| `worker_b_roads_sidewalks` | `roads-sidewalks` | `scripts/citywide/road_sidewalk_detailer.gd` | `materials/citywide/roads/`, `scripts/citywide/road_sidewalk_detailer.gd` |
| `worker_c_building_facades` | `building-facades` | `scripts/citywide/building_facade_detailer.gd` | `materials/citywide/facades/`, `scripts/citywide/building_facade_detailer.gd` |
| `worker_d_vegetation_props` | `vegetation-props` | `scripts/citywide/vegetation_props_detailer.gd` | `assets/citywide/props/`, `scripts/citywide/vegetation_props_detailer.gd` |
| `worker_e_vehicles_commercial` | `vehicles-commercial` | `scripts/citywide/vehicles_commercial_detailer.gd` | `assets/citywide/commercial/`, `docs/HARLINGEN_LANDMARKS.json`, `scripts/citywide/vehicles_commercial_detailer.gd` |
