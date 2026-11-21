# Harlingen surface materials

Harlingen's visible tile meshes and instanced props use `StandardMaterial3D`. Godot's GLB import settings assign shared, editable resources from `res://materials/`. Mesh data, UVs, transforms, collision and district boundaries use the original project files. Reimport a GLB to apply its stored surface assignments if it was already open in Godot.

## Surface treatment

| Surface | Treatment |
| --- | --- |
| Lakefront and Jackson Avenue | Dedicated façade atlas, weathered street asphalt and concrete sidewalk. Applies to the Lake Harlingen and Jackson Avenue tiles |
| Commercial and civic | Red and buff brick, masonry storefront or stucco with window and frame details |
| Residential | Muted painted wood siding and composition shingles |
| Warehouse and service buildings | Corrugated metal siding and coated roof panels |
| Paving and infrastructure | Asphalt, poured concrete, gravel, painted road markings, and coated utility fixtures |
| Parks and lake | Textured turf and soil, diffuse and subtle normal detail on the existing water surface |
| Terrain | Existing Terrain3D and aerial-textured fallback materials |

Most surfaces use roughness in the 0.40–0.90 range. The source meshes have sign hardware as the only surfaces assigned nonzero metalness. The brick and concrete resources use normal maps. Façade atlases include texture-based ambient occlusion along panel edges, beneath eaves, and around recessed windows. Those cues work with the existing Compatibility renderer. Surface roles follow the project's existing building classifications and material slots.

Existing UVs are used for the façade atlas. World-projected textures provide material continuity on pavements, roofs, and other geometry without built-in UVs. Shared textures use mipmaps.

## Texture sources

- Selected albedo and surface detail were derived from CC0 ambientCG assets Asphalt012, Asphalt019, Concrete034, Concrete049, Bricks034, Bricks059, Bricks097, Planks040, Grass001, and Gravel023. [ambientCG license](https://docs.ambientcg.com/license/)
- The coated roofing and corrugated siding use the CC0 Corrugated Iron 02 texture. [Poly Haven asset](https://polyhaven.com/a/corrugated_iron_02)
- The façade compositing, eave and reveal masks, and lake surface maps were made for this project.

## Verification

The material audit loaded 1,107 visible imported surfaces in Godot 4.7.2. Of those, 1,035 referenced the new external materials and 72 used the existing textured terrain materials. The audit found 270 normal-map bindings, 247 AO bindings, and two metallic sign surfaces. The first-person movement and collision checks still passed in both terrain modes.
