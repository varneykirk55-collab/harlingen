# Street and façade detail

The street layer adds rounded concrete curb profiles to the modeled sidewalk outlines, scored slab joints at roughly three-metre intervals, and zebra crossings where major junctions have usable approaches. The new paint follows the existing road elevation. Asphalt uses a darker tint, higher roughness and a subtle aggregate normal map.

The façade layer adds one door surround per modeled footprint. It includes stepped entries and frames on more bays near the Baxter Building and Jackson Avenue. Apertures sit behind raised surrounds to give the façade physical depth. Front-facing entrances are inferred from footprint edges and nearby streets. Business signage remains illustrative.

The two detail layers are packed into 320 m mesh sections and culled independently. Existing road and building mesh files remain the basis of the city. The sidewalk surfaces sit 10 cm higher to meet the new curb profile. The walking controller uses the existing terrain and building collision.

The added asphalt normal map uses ambientCG Asphalt012, under CC0. [Texture license](https://docs.ambientcg.com/license/)
