# Poly Haven PBR Assets & HDRI Inventory

All assets listed below are sourced from [Poly Haven](https://polyhaven.com/) (CC0 1.0 Public Domain license) and stored locally under `materials/polyhaven/`.

Each texture set includes 4 JPG maps:
- `diff` — Diffuse / Albedo
- `nor_gl` — OpenGL Normal Map
- `rough` — Roughness Map
- `ao` — Ambient Occlusion Map

---

## PBR Texture Sets (23 Sets, 92 Files)

| Category | Texture ID | Resolution | Local Path | Maps | Source URL |
| :--- | :--- | :--- | :--- | :--- | :--- |
| Asphalt & Weathered Road Surfaces | `asphalt_02` | 2K | `materials/polyhaven/asphalt_02/` | `diff`, `nor_gl`, `rough`, `ao` | https://polyhaven.com/a/asphalt_02 |
| Asphalt & Weathered Road Surfaces | `asphalt_04` | 2K | `materials/polyhaven/asphalt_04/` | `diff`, `nor_gl`, `rough`, `ao` | https://polyhaven.com/a/asphalt_04 |
| Asphalt & Weathered Road Surfaces | `asphalt_01` | 2K | `materials/polyhaven/asphalt_01/` | `diff`, `nor_gl`, `rough`, `ao` | https://polyhaven.com/a/asphalt_01 |
| Concrete Sidewalks, Curbs & Parking Lots | `concrete_pavement` | 2K | `materials/polyhaven/concrete_pavement/` | `diff`, `nor_gl`, `rough`, `ao` | https://polyhaven.com/a/concrete_pavement |
| Concrete Sidewalks, Curbs & Parking Lots | `concrete_floor_worn_001` | 2K | `materials/polyhaven/concrete_floor_worn_001/` | `diff`, `nor_gl`, `rough`, `ao` | https://polyhaven.com/a/concrete_floor_worn_001 |
| Brick & Stucco Building Facades | `red_brick_03` | 2K | `materials/polyhaven/red_brick_03/` | `diff`, `nor_gl`, `rough`, `ao` | https://polyhaven.com/a/red_brick_03 |
| Brick & Stucco Building Facades | `brick_wall_006` | 2K | `materials/polyhaven/brick_wall_006/` | `diff`, `nor_gl`, `rough`, `ao` | https://polyhaven.com/a/brick_wall_006 |
| Brick & Stucco Building Facades | `sandstone_blocks_05` | 2K | `materials/polyhaven/sandstone_blocks_05/` | `diff`, `nor_gl`, `rough`, `ao` | https://polyhaven.com/a/sandstone_blocks_05 |
| Brick & Stucco Building Facades | `beige_wall_001` | 2K | `materials/polyhaven/beige_wall_001/` | `diff`, `nor_gl`, `rough`, `ao` | https://polyhaven.com/a/beige_wall_001 |
| Brick & Stucco Building Facades | `painted_plaster_wall` | 1K | `materials/polyhaven/painted_plaster_wall/` | `diff`, `nor_gl`, `rough`, `ao` | https://polyhaven.com/a/painted_plaster_wall |
| Painted Concrete & Masonry | `concrete_wall_007` | 1K | `materials/polyhaven/concrete_wall_007/` | `diff`, `nor_gl`, `rough`, `ao` | https://polyhaven.com/a/concrete_wall_007 |
| Painted Concrete & Masonry | `rough_block_wall` | 1K | `materials/polyhaven/rough_block_wall/` | `diff`, `nor_gl`, `rough`, `ao` | https://polyhaven.com/a/rough_block_wall |
| Roofing Materials | `asphalt_06` | 1K | `materials/polyhaven/asphalt_06/` | `diff`, `nor_gl`, `rough`, `ao` | https://polyhaven.com/a/asphalt_06 |
| Roofing Materials | `grey_roof_01` | 1K | `materials/polyhaven/grey_roof_01/` | `diff`, `nor_gl`, `rough`, `ao` | https://polyhaven.com/a/grey_roof_01 |
| Roofing Materials | `corrugated_iron` | 1K | `materials/polyhaven/corrugated_iron/` | `diff`, `nor_gl`, `rough`, `ao` | https://polyhaven.com/a/corrugated_iron |
| Metal Surfaces & Architectural Details | `metal_plate_02` | 1K | `materials/polyhaven/metal_plate_02/` | `diff`, `nor_gl`, `rough`, `ao` | https://polyhaven.com/a/metal_plate_02 |
| Metal Surfaces & Architectural Details | `rusty_metal_02` | 1K | `materials/polyhaven/rusty_metal_02/` | `diff`, `nor_gl`, `rough`, `ao` | https://polyhaven.com/a/rusty_metal_02 |
| Metal Surfaces & Architectural Details | `rough_wood` | 1K | `materials/polyhaven/rough_wood/` | `diff`, `nor_gl`, `rough`, `ao` | https://polyhaven.com/a/rough_wood |
| Ground Surfaces & Environmental Details | `withered_grass` | 2K | `materials/polyhaven/withered_grass/` | `diff`, `nor_gl`, `rough`, `ao` | https://polyhaven.com/a/withered_grass |
| Ground Surfaces & Environmental Details | `leafy_grass` | 2K | `materials/polyhaven/leafy_grass/` | `diff`, `nor_gl`, `rough`, `ao` | https://polyhaven.com/a/leafy_grass |
| Ground Surfaces & Environmental Details | `brown_mud_dry` | 2K | `materials/polyhaven/brown_mud_dry/` | `diff`, `nor_gl`, `rough`, `ao` | https://polyhaven.com/a/brown_mud_dry |
| Ground Surfaces & Environmental Details | `gravel_road` | 2K | `materials/polyhaven/gravel_road/` | `diff`, `nor_gl`, `rough`, `ao` | https://polyhaven.com/a/gravel_road |
| Ground Surfaces & Environmental Details | `bark_brown_02` | 1K | `materials/polyhaven/bark_brown_02/` | `diff`, `nor_gl`, `rough`, `ao` | https://polyhaven.com/a/bark_brown_02 |

---

## HDRI Sky Environments

| HDRI ID | Resolution | Local Path | Format | Source URL |
| :--- | :--- | :--- | :--- | :--- |
| `kloofendal_48d_partly_cloudy_puresky` | 2K | `materials/polyhaven/hdri/kloofendal_48d_partly_cloudy_puresky_2k.hdr` | HDR | https://polyhaven.com/a/kloofendal_48d_partly_cloudy_puresky |

---

## Terrain3D Surface Textures

Packed 2K RGBA PNG texture pairs under `materials/polyhaven/terrain/` for `Terrain3D` v1.1.0 (`TerrainAssets` in `preview/Harlingen.tscn`), plus a 256×256 tileable macro noise texture (`macro_noise.png`) for `TerrainMat`:

- **`*_albedo_height.png`**: `RGB` = Poly Haven `diff_2k` (sRGB), `A` = height/AO proxy (`ao_2k`)
- **`*_normal_roughness.png`**: `RGB` = Poly Haven `nor_gl_2k` (OpenGL normal), `A` = `rough_2k`

| Slot | Name | Source Asset | Resolution | Packed Files | Source URL |
| :--- | :--- | :--- | :--- | :--- | :--- |
| 0 | Dry South Texas Grass | `withered_grass` | 2K (2048×2048) | `withered_grass_albedo_height.png`, `withered_grass_normal_roughness.png` | https://polyhaven.com/a/withered_grass |
| 1 | Park / Hospital Lawn Grass | `leafy_grass` | 2K (2048×2048) | `leafy_grass_albedo_height.png`, `leafy_grass_normal_roughness.png` | https://polyhaven.com/a/leafy_grass |
| 2 | Dry South Texas Soil | `brown_mud_dry` | 2K (2048×2048) | `brown_mud_dry_albedo_height.png`, `brown_mud_dry_normal_roughness.png` | https://polyhaven.com/a/brown_mud_dry |
| 3 | Gravel Shoulders & Lots | `gravel_road` | 2K (2048×2048) | `gravel_road_albedo_height.png`, `gravel_road_normal_roughness.png` | https://polyhaven.com/a/gravel_road |
