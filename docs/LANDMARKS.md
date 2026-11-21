# Harlingen landmarks

These scenes are part of the normal streamed world. Each one can also be opened in Godot from `assets/landmarks/`. The scenes use district-local meters. For placement in another project, apply the matching district translation. The GLBs provide the models and PBR materials. The Godot scenes add readable signs and static collision.

| Landmark | Where to find it | Approximate world X/Z (meters) | District |
| --- | --- | --- | --- |
| Stripes | North 7th Street at the North 77 Sunshine Strip | 999 / −1094 | `+00_-01` |
| Valero | North Loop 499 near the North 77 Sunshine Strip | −2041 / −3381 | `-02_-02` |
| Harlingen Medical Center | South expressway campus, 5501 S Expressway 77 | 2397 / 4212 | `+01_+02` |

## Footprints and modeled details

- **Stripes** uses the mapped [convenience-store footprint](https://www.openstreetmap.org/way/542325799) and [fuel-canopy footprint](https://www.openstreetmap.org/way/542325801). The blue and white striped fascia represents the station as requested. It includes two pump islands and a glazed storefront with a covered entry.
- **Valero** uses the mapped [fuel canopy](https://www.openstreetmap.org/way/498135173) and [adjacent store](https://www.openstreetmap.org/way/498135174). The red and white treatment is the requested visual direction. It includes three pump islands and a glazed storefront with a covered entry.
- **Harlingen Medical Center** uses the [main hospital footprint](https://www.openstreetmap.org/way/545113288) and the entrance canopy alignment from Overture Maps feature `1dc76c4b-9b12-43e3-8ea4-a5ff3627d5c1`. The [hospital’s public name and address](https://harlingenmedicalcenter.com/contact-us/) are used on the signs. Four modeled stories, stepped roof lines, brick and limestone bands, blue glazing, and a vehicle drop-off canopy distinguish the building along the expressway.

The source footprints and mapped road locations establish each site's location and scale. Building heights, facade divisions, structural details, fuel branding treatments, and sign positions are modeled approximations. The storefronts and hospital are exterior-only. No third-party logo image or site photography is embedded.

For regeneration, use `python tools/landmarks.py /path/to/pre-landmarks/Harlingen-Godot.zip` from an environment with the project GIS dependencies. The builder reads the original district scenes and building meshes from the prior archive and updates the relevant triangle inventories in `manifest.json`.
