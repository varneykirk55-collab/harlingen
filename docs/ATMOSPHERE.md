# Gulf Coast daylight and materials

Main roads and the commercial corridor have city-specific finishes. Asphalt uses 0.72 roughness and fine aggregate normals. Road-edge masks derive from the existing road and sidewalk outlines and shade the asphalt at curb joins. Paint and crosswalks still render on their separate meshes.

Sidewalks use warm concrete albedo, light normal detail, and a roughness map. Fine relief and mottling help the projected material read across the existing slabs and their scored joints. Façade finishes vary subtly by location and preserve the distinct brick, stucco, painted siding, and metal-panel textures. Roof variation comes from material color, exposure, and corrugation.

Existing separate window surfaces use cool dielectric glass at 0.19 roughness. A matching glazing mask gives the atlas window panes physically based sky reflections while keeping the surrounding wall and mullions matte. Two static reflection probes capture the immediate surroundings along Jackson Avenue. Sky radiance provides reflections throughout the map.

The scene uses a clear procedural midday sky with a deep blue zenith and a few thin cirrus wisps. A high sun casts short, sharp shadows and the warm ambient fill keeps shade from going gray. Light horizon haze gives distant blocks some depth. The default Compatibility renderer remains in use.

This pass is limited to surfaces and atmosphere as requested. Building heights, roof profiles, and window positions are defined by the existing meshes. Small differences between sidewalk slabs are suggested through shading.

## Sources

- Concrete and asphalt maps derive from CC0 ambientCG materials already used by the city kit. [ambientCG license](https://docs.ambientcg.com/license/)
