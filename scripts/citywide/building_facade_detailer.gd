class_name BuildingFacadeDetailer
extends RefCounted
## Citywide building facade, roof, trim, and lightweight MultiMesh storefront accent detailer.
## Preserves building footprints, heights, orientation, JacksonArchitecture, landmarks, and BuildingCollision.

const MATERIAL_DIR := "res://materials/citywide/facades/"
const MAX_VISIBILITY_RANGE := 485.0
const ACCENT_VISIBILITY_RANGE := 360.0
const MAX_ACCENTS_PER_TILE := 250

const PROFILE_DOWNTOWN := "downtown_historic"
const PROFILE_MEDICAL := "medical_civic"
const PROFILE_AIRPORT := "airport_industrial"
const PROFILE_INDUSTRIAL := "highway_industrial"
const PROFILE_COMMERCIAL := "commercial_corridor"
const PROFILE_RESIDENTIAL := "residential_suburban"
const PROFILE_RURAL := "rural_outer"

static var _mat_cache: Dictionary = {}
static var _canopy_mesh: BoxMesh = null


static func apply_to_tile(tile_node: Node3D, tile_id: String, tile_meta: Dictionary) -> Dictionary:
	var stats := {
		"tile_id": tile_id,
		"district_profile": "",
		"buildings_surfaces_upgraded": 0,
		"far_surfaces_upgraded": 0,
		"facade_details_configured": 0,
		"accent_multimesh_count": 0,
		"accent_instance_count": 0,
		"already_applied": false,
		"errors": [],
	}

	if tile_node == null or not is_instance_valid(tile_node):
		stats["errors"].append("tile_node is null or invalid")
		return stats

	var profile := _resolve_district_profile(tile_id, tile_meta)
	stats["district_profile"] = profile

	if tile_node.has_meta("_facade_detailer_applied"):
		stats["already_applied"] = true
		return stats

	var tile_variant := absi(tile_id.hash()) % 3
	var surface_map := _build_surface_map(profile, tile_variant)
	var far_map := _build_far_surface_map(profile)

	var buildings_node := tile_node.get_node_or_null("Buildings")
	if buildings_node:
		stats["buildings_surfaces_upgraded"] = _apply_surface_map(buildings_node, surface_map, false)

	var far_node := tile_node.get_node_or_null("BuildingsFar")
	if far_node:
		stats["far_surfaces_upgraded"] = _apply_surface_map(far_node, far_map, false)

	var details_node := tile_node.get_node_or_null("FacadeDetails")
	if details_node:
		var detail_map := _build_detail_surface_map(profile)
		stats["facade_details_configured"] = _apply_surface_map(details_node, detail_map, true)

		if profile in [PROFILE_DOWNTOWN, PROFILE_MEDICAL, PROFILE_COMMERCIAL, PROFILE_INDUSTRIAL]:
			var accent_count := _add_storefront_accents(tile_node, details_node)
			if accent_count > 0:
				stats["accent_multimesh_count"] = 1
				stats["accent_instance_count"] = accent_count

	tile_node.set_meta("_facade_detailer_applied", profile)
	return stats


static func _resolve_district_profile(tile_id: String, tile_meta: Dictionary) -> String:
	var meta_text := ""
	for key in ["district_type", "category", "profile", "zone"]:
		if tile_meta.has(key):
			meta_text += " " + str(tile_meta[key]).to_lower()
	if tile_meta.has("external_scenes"):
		meta_text += " " + str(tile_meta["external_scenes"]).to_lower()
	if tile_meta.has("landmarks"):
		meta_text += " " + str(tile_meta["landmarks"]).to_lower()

	if meta_text.contains("medical") or meta_text.contains("hospital"):
		return PROFILE_MEDICAL
	if meta_text.contains("airport") or meta_text.contains("aviation"):
		return PROFILE_AIRPORT
	if meta_text.contains("industrial") or meta_text.contains("valero") or meta_text.contains("warehouse"):
		return PROFILE_INDUSTRIAL
	if meta_text.contains("downtown") or meta_text.contains("civic") or meta_text.contains("historic"):
		return PROFILE_DOWNTOWN
	if meta_text.contains("commercial") or meta_text.contains("retail"):
		return PROFILE_COMMERCIAL
	if meta_text.contains("residential") or meta_text.contains("suburban"):
		return PROFILE_RESIDENTIAL

	match tile_id:
		"+00_+00":
			return PROFILE_DOWNTOWN
		"+01_+02", "+00_+02", "+01_+01":
			return PROFILE_MEDICAL
		"+01_-02", "+02_-02", "+01_-03", "+02_-03":
			return PROFILE_AIRPORT
		"-02_-02", "-02_+00", "-02_-01", "-01_-01":
			return PROFILE_INDUSTRIAL
		"-01_+00", "+00_-01", "+01_+00", "+00_+01", "+01_-01":
			return PROFILE_COMMERCIAL
		"-03_-01", "-03_+00", "-03_+01", "-02_+01", "-01_+01", "+02_+00", "+02_+01", "+02_+02":
			return PROFILE_RESIDENTIAL
		_:
			return PROFILE_RURAL


static func _load_mat(file_stem: String) -> Material:
	if _mat_cache.has(file_stem):
		return _mat_cache[file_stem]
	var path := MATERIAL_DIR + file_stem + ".tres"
	var mat := load(path) as Material
	if mat != null:
		_mat_cache[file_stem] = mat
	return mat


static func _build_surface_map(profile: String, variant: int) -> Dictionary:
	var m := {}
	match profile:
		PROFILE_DOWNTOWN:
			m = {
				"brick_a": "facade_brick_red_weathered",
				"brick_b": "facade_brick_buff_historic",
				"stucco_a": "facade_stucco_warm_south_tx",
				"stucco_b": "facade_stone_sandstone",
				"house_a": "facade_plaster_sunlit",
				"house_b": "facade_stucco_terracotta",
				"shop": "facade_stone_sandstone" if variant != 2 else "facade_brick_buff_historic",
				"warehouse": "facade_cmu_block_industrial",
				"trim": "trim_cast_stone",
				"equipment": "equipment_weathered_metal",
				"roofs": "roof_membrane_weathered",
				"metalroof": "roof_metal_standing_seam",
				"shingle": "roof_shingle_slate",
			}
		PROFILE_MEDICAL:
			m = {
				"brick_a": "facade_stone_sandstone",
				"brick_b": "facade_concrete_architectural",
				"stucco_a": "facade_plaster_medical_clean",
				"stucco_b": "facade_concrete_architectural",
				"house_a": "facade_plaster_sunlit",
				"house_b": "facade_stucco_warm_south_tx",
				"shop": "facade_plaster_medical_clean" if variant == 0 else "facade_concrete_architectural",
				"warehouse": "facade_metal_panel_modern",
				"trim": "trim_concrete_parapet",
				"equipment": "equipment_weathered_metal",
				"roofs": "roof_membrane_weathered",
				"metalroof": "roof_metal_standing_seam",
				"shingle": "roof_shingle_slate",
			}
		PROFILE_AIRPORT:
			m = {
				"brick_a": "facade_cmu_block_industrial",
				"brick_b": "facade_concrete_weathered",
				"stucco_a": "facade_metal_panel_modern",
				"stucco_b": "facade_concrete_weathered",
				"house_a": "facade_plaster_sunlit",
				"house_b": "facade_stucco_warm_south_tx",
				"shop": "facade_metal_panel_modern",
				"warehouse": "facade_metal_corrugated" if variant != 2 else "facade_metal_panel_modern",
				"trim": "trim_concrete_parapet",
				"equipment": "equipment_weathered_metal",
				"roofs": "roof_membrane_weathered",
				"metalroof": "roof_metal_standing_seam",
				"shingle": "roof_shingle_slate",
			}
		PROFILE_INDUSTRIAL:
			m = {
				"brick_a": "facade_brick_red_weathered",
				"brick_b": "facade_cmu_block_industrial",
				"stucco_a": "facade_concrete_weathered",
				"stucco_b": "facade_stucco_terracotta",
				"house_a": "facade_stucco_warm_south_tx",
				"house_b": "facade_plaster_sunlit",
				"shop": "facade_concrete_architectural" if variant == 0 else "facade_cmu_block_industrial",
				"warehouse": "facade_metal_weathered" if variant == 1 else "facade_metal_corrugated",
				"trim": "trim_concrete_parapet",
				"equipment": "equipment_weathered_metal",
				"roofs": "roof_membrane_weathered",
				"metalroof": "roof_metal_weathered" if variant == 1 else "roof_metal_standing_seam",
				"shingle": "roof_shingle_slate",
			}
		PROFILE_COMMERCIAL:
			m = {
				"brick_a": "facade_brick_buff_historic",
				"brick_b": "facade_brick_red_weathered",
				"stucco_a": "facade_stucco_warm_south_tx" if variant != 1 else "facade_stucco_terracotta",
				"stucco_b": "facade_plaster_sunlit",
				"house_a": "facade_plaster_sunlit",
				"house_b": "facade_brick_tan_residential",
				"shop": "facade_stone_sandstone" if variant == 0 else "facade_concrete_architectural",
				"warehouse": "facade_cmu_block_industrial",
				"trim": "trim_cast_stone" if variant == 0 else "trim_concrete_parapet",
				"equipment": "equipment_weathered_metal",
				"roofs": "roof_membrane_weathered",
				"metalroof": "roof_metal_standing_seam",
				"shingle": "roof_shingle_slate",
			}
		PROFILE_RESIDENTIAL:
			m = {
				"brick_a": "facade_brick_tan_residential",
				"brick_b": "facade_brick_red_weathered",
				"stucco_a": "facade_stucco_warm_south_tx",
				"stucco_b": "facade_stucco_terracotta" if variant == 1 else "facade_plaster_sunlit",
				"house_a": "facade_plaster_sunlit",
				"house_b": "facade_stucco_warm_south_tx" if variant != 2 else "facade_brick_tan_residential",
				"shop": "facade_brick_buff_historic",
				"warehouse": "facade_cmu_block_industrial",
				"trim": "trim_painted_wood",
				"equipment": "equipment_weathered_metal",
				"roofs": "roof_membrane_weathered",
				"metalroof": "roof_metal_standing_seam",
				"shingle": "roof_shingle_slate",
			}
		_: # PROFILE_RURAL
			m = {
				"brick_a": "facade_brick_red_weathered",
				"brick_b": "facade_brick_tan_residential",
				"stucco_a": "facade_plaster_sunlit",
				"stucco_b": "facade_stucco_terracotta",
				"house_a": "facade_stucco_warm_south_tx",
				"house_b": "facade_plaster_sunlit",
				"shop": "facade_concrete_weathered",
				"warehouse": "facade_metal_weathered",
				"trim": "trim_painted_wood",
				"equipment": "equipment_weathered_metal",
				"roofs": "roof_membrane_weathered",
				"metalroof": "roof_metal_weathered",
				"shingle": "roof_shingle_slate",
			}
	return m


static func _build_far_surface_map(profile: String) -> Dictionary:
	var brick_mat := "far_commercial_mixed"
	var trim_mat := "trim_concrete_parapet"
	var metal_roof := "roof_metal_standing_seam"
	match profile:
		PROFILE_DOWNTOWN:
			brick_mat = "far_brick_historic"
			trim_mat = "trim_cast_stone"
		PROFILE_MEDICAL:
			brick_mat = "far_concrete_medical"
			trim_mat = "trim_concrete_parapet"
		PROFILE_AIRPORT:
			brick_mat = "far_metal_industrial"
			trim_mat = "trim_concrete_parapet"
		PROFILE_INDUSTRIAL:
			brick_mat = "far_metal_industrial"
			metal_roof = "roof_metal_weathered"
		PROFILE_COMMERCIAL:
			brick_mat = "far_commercial_mixed"
			trim_mat = "trim_cast_stone"
		PROFILE_RESIDENTIAL, PROFILE_RURAL:
			brick_mat = "far_stucco_residential"
			trim_mat = "trim_painted_wood"

	return {
		"baxter_brick": brick_mat,
		"trim": trim_mat,
		"equipment": "equipment_weathered_metal",
		"roofs": "roof_membrane_weathered",
		"metalroof": metal_roof,
		"shingle": "roof_shingle_slate",
	}


static func _build_detail_surface_map(profile: String) -> Dictionary:
	var frame_mat := "accent_window_frame_bronze"
	var portal_mat := "trim_concrete_parapet"
	match profile:
		PROFILE_DOWNTOWN, PROFILE_COMMERCIAL:
			frame_mat = "accent_window_frame_bronze"
			portal_mat = "trim_cast_stone"
		PROFILE_RESIDENTIAL, PROFILE_RURAL:
			frame_mat = "trim_painted_wood"
			portal_mat = "trim_painted_wood"
		_:
			frame_mat = "accent_window_frame_bronze"
			portal_mat = "trim_concrete_parapet"
	return {
		"frame": frame_mat,
		"portal": portal_mat,
		"glass_detail": "accent_storefront_glass",
	}


static func _apply_surface_map(root_node: Node, surface_map: Dictionary, clamp_visibility: bool) -> int:
	var upgraded := 0
	var meshes: Array = root_node.find_children("*", "MeshInstance3D", true, false)
	if root_node is MeshInstance3D:
		meshes.push_front(root_node)

	for node in meshes:
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		if clamp_visibility:
			if mi.visibility_range_end <= 0.0 or mi.visibility_range_end > MAX_VISIBILITY_RANGE:
				mi.visibility_range_end = MAX_VISIBILITY_RANGE
			mi.visibility_range_end_margin = 32.0
		var surf_count := mi.mesh.get_surface_count()
		for s in surf_count:
			var surf_name: String = mi.mesh.surface_get_name(s)
			if not surface_map.has(surf_name):
				continue
			var mat := _load_mat(surface_map[surf_name])
			if mat != null:
				mi.set_surface_override_material(s, mat)
				upgraded += 1
	return upgraded


static func _add_storefront_accents(tile_node: Node3D, details_node: Node) -> int:
	var portals := _extract_portal_placements(details_node)
	if portals.is_empty():
		return 0

	if _canopy_mesh == null:
		_canopy_mesh = BoxMesh.new()
		_canopy_mesh.size = Vector3(1.0, 0.14, 0.40)
		_canopy_mesh.material = _load_mat("accent_storefront_canopy")

	var mmi := MultiMeshInstance3D.new()
	mmi.name = "CitywideStorefrontAccents"
	mmi.visibility_range_end = ACCENT_VISIBILITY_RANGE
	mmi.visibility_range_end_margin = 30.0
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _canopy_mesh
	mm.instance_count = portals.size()

	for i in portals.size():
		var p: Dictionary = portals[i]
		var n: Vector3 = p["normal"]
		var pos: Vector3 = p["pos"] + n * 0.21 + Vector3(0.0, 0.06, 0.0)
		var w: float = p["width"] + 0.16
		var right := Vector3.UP.cross(n)
		if right.length_squared() < 0.001:
			right = Vector3.RIGHT
		right = right.normalized()
		var basis := Basis(right * w, Vector3.UP, n)
		mm.set_instance_transform(i, Transform3D(basis, pos))

	mmi.multimesh = mm
	tile_node.add_child(mmi)
	return portals.size()


static func _extract_portal_placements(details_node: Node) -> Array[Dictionary]:
	var placements: Array[Dictionary] = []
	var meshes: Array = details_node.find_children("*", "MeshInstance3D", true, false)
	if details_node is MeshInstance3D:
		meshes.push_front(details_node)

	for node in meshes:
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var portal_surf := -1
		for s in mi.mesh.get_surface_count():
			if mi.mesh.surface_get_name(s) == "portal":
				portal_surf = s
				break
		if portal_surf < 0:
			continue

		var arrays := mi.mesh.surface_get_arrays(portal_surf)
		if arrays.is_empty():
			continue
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if verts.is_empty() or indices.is_empty():
			continue

		# Cluster portal triangles into individual door/storefront portals by quantized XZ cell (~2m)
		var clusters: Dictionary = {}
		var offset := mi.position
		for t in range(0, indices.size(), 3):
			var i0 := indices[t]
			var i1 := indices[t + 1]
			var i2 := indices[t + 2]
			var v0 := verts[i0] + offset
			var v1 := verts[i1] + offset
			var v2 := verts[i2] + offset
			var center := (v0 + v1 + v2) / 3.0
			var cell := Vector2i(roundi(center.x * 0.5), roundi(center.z * 0.5))
			if not clusters.has(cell):
				clusters[cell] = {
					"min": v0,
					"max": v0,
					"norm_sum": Vector3.ZERO,
				}
			var c: Dictionary = clusters[cell]
			for v in [v0, v1, v2]:
				c["min"] = c["min"].min(v)
				c["max"] = c["max"].max(v)
			if i0 < normals.size():
				var n := normals[i0]
				if absf(n.y) < 0.35:
					c["norm_sum"] += Vector3(n.x, 0.0, n.z)

		for cell in clusters:
			if placements.size() >= MAX_ACCENTS_PER_TILE:
				return placements
			var c: Dictionary = clusters[cell]
			var bmin: Vector3 = c["min"]
			var bmax: Vector3 = c["max"]
			var size := bmax - bmin
			var horiz_width := Vector2(size.x, size.z).length()
			if horiz_width < 1.35 or horiz_width > 3.5 or size.y < 1.55 or size.y > 4.5:
				continue
			var n_sum: Vector3 = c["norm_sum"]
			if n_sum.length_squared() < 0.01:
				continue
			var normal := n_sum.normalized()
			var top_center := Vector3((bmin.x + bmax.x) * 0.5, bmax.y, (bmin.z + bmax.z) * 0.5)
			placements.append({
				"pos": top_center,
				"width": horiz_width,
				"normal": normal,
			})
	return placements
