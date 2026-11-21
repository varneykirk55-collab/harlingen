# Harlingen bridge clearance and approaches

Baseline commit: `a603a08`. The repair preserves the OpenStreetMap centerlines, the project origin, the USGS 3DEP raster, and all 27 audited tagged bridges. It refits 25 motorway bridges and 57 connected ground ways. The two Loop 499 and Ramsey bridges remain in their existing district assets.

| Measurement | Result |
| --- | --- |
| Audited openings | 18 of 18 at or above 4.5 m |
| Minimum clearance across exported overlapping surfaces | 4.5928 m at upper OSM way 1459656357 over way 143685397 |
| Minimum centerline clearance on Godot collision | 4.6938 m |
| Maximum sampled grade on exported motorway collision | 7.7515%, measured at intervals of approximately 0.8 m |
| Shared motorway joins | 65 checked, with equal profile heights at each shared endpoint |
| Ground elevation exceptions | 35 of 57 ways contain an interval above the 1 m tolerance. The other 22 peak at 0.9762 m. |
| Largest documented ground offset | 5.6743 m on 1183883591, a short approach joining bridge 97348021 |

The fit uses common endpoint elevations and limits the longitudinal grade and its change between stations. An approach can depart from the terrain envelope only within 112 m of a tagged bridge along the modeled road network. Approach station intervals where the exported road differs from 3DEP by more than 1 m are listed by OSM way in `manifest.json` under `elevated_highway.bridge_clearance.profiles_by_osm_way`. Stations are measured from the start of each stored OSM line. Bridges, elevated approaches, rails, underside collision, and supports use the same road profiles. Support caps are kept clear of the checked openings.

Clearance is measured between the lower road mesh and the underside of the exported deck across their intersecting footprints. The Godot test independently checks ground, deck, and underside collision at all 18 crossing centers and runs a 2.02 m wide by 4.20 m high collision envelope along every slip-road centerline near those crossings. The orphaned coarse bridge meshes in district `-01_+00` were removed because the district had already replaced their visual layer, but the collision loader still discovered the obsolete collider by path.

## Source and test scope

- The project uses OSM bridge and layer tags for topology and the existing USGS 3DEP bare-earth DEM for ground and tie-ins. The vertical deck profiles are modeled from those inputs. Deck survey elevations were unavailable. [USGS DEM specification](https://www.usgs.gov/ngp-standards-and-specifications/lidar-base-specification-digital-elevation-model-surface)
- The 4.5 m target is for this game build. TxDOT's design manual provides a reference for checking the full width and both sides of an opening. [TxDOT vertical clearance](https://www.txdot.gov/manuals/des/rdw/chapter-4--basic-design-criteria/4-8-vertical-alignment/4-8-6-vertical-clearance.html)
- No audited crossing remains below target. The collision checks cover the audited slip roads, and the existing integration tests exercise the stock vehicle in both terrain modes. A manual end-to-end drive of every ramp has yet to be run.

## Reproduce

With the project's Python GIS dependencies and SciPy installed, run `python tools/apply_geographic_audit.py --highway-only`, then `python tools/audit.py`. Reimport in Godot before running `godot --headless -s tools/verify_bridge_clearance.gd` and `godot --headless -s tools/verify_integration.gd`. Append `-- --mesh-ground` to the integration test to check the GLB terrain mode.
