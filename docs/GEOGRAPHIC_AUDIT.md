# Harlingen geographic audit corrections

Baseline is main at 2e0e6c073ff88e1acf2645930689a47441445bc9. The branch uses EPSG:32614, origin easting 630000 m and northing 2898000 m, and preserves the 36 streaming tiles and the 12 km square extent. The Terrain3D height raster SHA-256 is e54d19c90d0b06b4c2316644a76c2fdf2ee384cdea6de5d9fb97567fe17da1b3 before and after.

| Check | Before | After |
|---|---|---|
| Audited highway ways | 57 of 57 with legacy centerline profiles more than 1 m off 3DEP. Worst sampled error 8.023 m | 0 of 57 outside 1 m. Worst deviation on exported ground-way collision samples 0.771 m |
| Tagged bridge ways | 27 | All 27 retain bridge geometry. 65 shared route nodes checked with a maximum analytic centerline join gap below 1 mm |
| Airport 13/31 | Physical ends 75.439 m and 26.817 m from FAA source | Both exported ends within 1 cm of source |
| Airport 18L/36R | Physical ends 22.063 m and 62.575 m from FAA source | Both exported ends within 1 cm of source. The 190 ft displaced threshold is separately recorded |
| Airport 18R/36L | Physical ends 3.591 m and 1.677 m from FAA source | Both exported ends within 1 cm of source |
| Sites | The six requested labels and model were absent from the site inventory | Six labels verified in Godot and all five campus boundaries validated. The monument includes a dedicated mesh and plinth collider |
| Planning districts | Rectangular downtown approximation in prior scene tooling | City's 19-vertex Downtown District Overlay and 15 zoning district geometries, independent of streaming |
| tools/audit.py | PASS, 657 tile GLBs and 180 matching terrain edges | PASS, 657 tile GLBs and 180 matching terrain edges |
| Godot | Existing project was the baseline | Headless import and scene launch passed. Geographic label and full Terrain3D player and vehicle integration checks passed |

Highway tests compare against the project's unchanged USGS 3DEP raster. The after measurement samples the exported collision at approximately 2.5 m intervals. At overlapping decks it selects the height matching the ground road. This measures the game mesh against its input raster, with no claim of survey-grade roadway elevation. Per-way results and the old and new runway endpoint measurements are in the manifest.

## Sources and interpretation

- OpenStreetMap bridge and layer tags distinguish the 57 ground ways from the 27 bridge ways. At-grade approaches blend against USGS ground heights, and bridge spans retain separate visual and collision geometry.
- Valley Baptist and Harlingen High School South use OSM campus outlines. The other school and campus grounds use the 2024 parcel layer in the city's January 2025 map, checked against the district directory and campus maps. TSTC uses a parcel-derived campus footprint, including mapped campus land on city-owned airport parcels. The six labels use the same projected sources. [City GIS](https://www.arcgis.com/home/item.html?id=9524f7af7fca43428d8fce2b1558ccde) · [HCISD directory](https://www.choosehcisd.org/directory?level=high) · [TSTC campus map](https://www.tstc.edu/wp-content/uploads/2025/12/Harlingen_Campus_11-25.pdf)
- The Iwo Jima model is a low-poly sculptural proxy using 32 ft figure scale, a 10 ft base, and a 78 ft flagpole. The footprint and poses are approximations. The site is on the Marine Military Academy campus. [Academy monument dimensions](https://www.mma-tx.org/about-us/iwo-jima-monument/) · [Texas Historical Commission](https://thc.texas.gov/historic-sites/iwo-jima-museum-and-monument)
- The Downtown District Overlay follows the vector outline embedded in the city's georeferenced 2025 PDF. The zoning layer retains municipal zone codes and uses clipped geometry dissolved by zone. Of 25,440 source polygons, 22,913 intersect the game's extent. [City overlay map](https://cms3.revize.com/revize/harlingen/Downtown%20District%20Overlay%20Boundary%20Map%202025.pdf) · [January 2025 zoning map](https://www.arcgis.com/home/item.html?id=9524f7af7fca43428d8fce2b1558ccde)
- FAA NASR runway-end positions were read from the USDOT BTS Runway Ends Table effective 2026-10-29, and runway widths were checked against the FAA airport listing. Physical pavement ends are used for geometry. [FAA NASR source metadata](https://www.arcgis.com/sharing/rest/content/items/77db9c3ab3bd4a02bd85e575992bbd3e/info/metadata/metadata.xml?format=default&output=html) · [FAA chart supplement](https://aeronav.faa.gov/afd/14MAY2026/sc_348_14MAY2026.pdf)

## Open roadway issue

The corrected profile retains the named through-road crossings. At 18 modeled crossings with unnamed slip roads, estimated underside clearance remains below 2.74 m, with a minimum of 0.51 m in the centerline check. These estimates subtract the modeled 0.81 m deck thickness. Several short tagged bridge approaches still reach simulated grades up to 27.2%. Holding all 57 adjacent OSM ways within 1 m leaves little or no grade transition distance at those slips. Further bridge work needs a decision about lengthening the modeled approach spans beyond the tagged bridge ends or revising the slip-road geometry from better elevation evidence. Keep this branch unmerged until those locations are reviewed.

The branch avoids changes to terrain assets, materials, textures, facade meshes, and gameplay code. Coordinate review and visual merge review should focus on the changed highway and airport GLBs and the shared manifest. No separate Argon branch was visible on the remote at the time of the check.

## Regeneration

The targeted entry point is python tools/apply_geographic_audit.py. It rebuilds the audited highway ribbons, clips and updates the airport pavement and paint, and adds scene labels and the monument without running a citywide rebuild. tools/extract.py retains institutional areas and memorials on refreshed OSM extracts. The existing tools/build.py full-build entry point consumes the curated site and runway sources for future regeneration.

Run python tools/audit.py and godot --headless -s tools/verify_geographic_audit.gd after import. The existing tools/verify_integration.gd exercises the player, vehicle and terrain mode switching.
