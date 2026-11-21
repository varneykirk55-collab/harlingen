# Elevated highways and Hugh Ramsey Nature Park

The normal Harlingen scene streams the new road structures with the districts. Use `F7` to switch between walking and flying. World coordinates are in meters from the project’s documented GIS origin.

| Area | Approximate world X/Z | In the scene |
| --- | --- | --- |
| I‑2 / I‑69E interchange | −2075 / 780 | Stacked curved flyovers, the elevated highway mainlines, and the mapped frontage roads at ground level |
| Valle Vista Mall corridor | −1740 / 1140 | A continuous elevated I‑69E / US 77 / US 83 spine past the mall |
| West Lincoln Avenue | −1549 / 1523 | Surface street under the expressway deck |
| South M Street | −1125 / 1792 | Surface street under the expressway deck |
| South F Street | −312 / 2275 | Surface street under the expressway deck |
| Hugh Ramsey Nature Park / Loop 499 | 3415 / 1050 | Signed trailhead with seating, a short path connector, and a pedestrian bridge beside the North Ed Carey Drive crossing |

The I‑2 / I‑69E junction follows the mapped directional interchange. [TxDOT’s regional map](https://www.txdot.gov/content/dam/docs/division/trv/city-maps/travel-map-harlingen-rio-grande-valley-combined.pdf) provides regional context. [Texas Parks & Wildlife](https://tpwd.texas.gov/huntwild/wildlife/wildlife-trails/ltc/los-loros-loop) locates Hugh Ramsey Nature Park on Loop 499, east of the expressway interchange. The park treatment uses the existing nature park boundary, the mapped North Ed Carey Drive bridge (OSM way 567766739), and the adjacent mapped pedestrian crossing (OSM way 653171983).

Road centerlines, existing frontage roads, and the relative grade separation follow the source map. The continuous elevated profile, deck heights, column positions, rails, markings, and park entrance are modeled approximations. The short park trail connector is a game-world addition.

The six changed districts have separate `ElevatedRoads.glb` and `ElevatedCollision.glb` layers, and the park entrance is an editable scene in `assets/landmarks/RamseyTrailhead.tscn`. The stripped at-grade previews of the upgraded routes were replaced by the new decks. The road layer still contains the original surface street network. `manifest.json` records the relevant OSM way IDs and per-tile triangle counts. To regenerate, run `python tools/elevated_roads.py /path/to/pre-highway/Harlingen-Godot.zip` with the existing GIS dependencies.
