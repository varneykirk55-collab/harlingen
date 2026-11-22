class_name RoadSidewalkDetailer
extends RefCounted
## Upgrades Roads, Sidewalks, Markings, StreetEdges, StreetPaint, and StreetWear
## surfaces with shared Poly Haven PBR materials and subtle per-tile variation.

const MATERIAL_BASE := "res://materials/citywide/roads/"
const TARGET_LAYERS := [
	"Roads",
	"Sidewalks",
	"Markings",
	"StreetEdges",
	"StreetPaint",
	"StreetWear",
]

const MATERIAL_FILES := {
	"asphalt_arterial": "asphalt_arterial.tres",
	"asphalt_highway": "asphalt_highway.tres",
	"asphalt_local": "asphalt_local.tres",
	"asphalt_service": "asphalt_service.tres",
	"road_gravel": "road_gravel.tres",
	"sidewalk_concrete": "sidewalk_concrete.tres",
	"curb_concrete": "curb_concrete.tres",
	"slab_joint": "slab_joint.tres",
	"concrete_new": "concrete_new.tres",
	"concrete_old": "concrete_old.tres",
	"concrete_ramp": "concrete_ramp.tres",
	"marking_white": "marking_white.tres",
	"marking_yellow": "marking_yellow.tres",
	"crosswalk_white": "crosswalk_white.tres",
}

static var _material_cache: Dictionary = {}


static func clear_cache() -> void:
	_material_cache.clear()


static func apply_to_tile(tile_node: Node3D, tile_id: String, tile_meta: Dictionary = {}) -> Dictionary:
	var stats := {
		"tile_id": tile_id,
		"layers_processed": 0,
		"meshes_upgraded": 0,
		"surfaces_upgraded": 0,
		"by_layer": {},
		"materials_used": [],
		"tile_tint": Color.WHITE,
		"tile_wear": 0.0,
	}
	if tile_node == null or not is_instance_valid(tile_node):
		return stats

	var variation := _compute_tile_variation(tile_id, tile_meta)
	stats["tile_tint"] = variation["asphalt_tint"]
	stats["tile_wear"] = variation["wear"]

	var used_keys := {}
	var is_rural := int(tile_meta.get("buildings", 1000)) < 350 and not bool(tile_meta.get("has_sidewalks", true))

	for layer_name: String in TARGET_LAYERS:
		var layer_node := tile_node.get_node_or_null(layer_name)
		if layer_node == null:
			continue

		var mesh_instances := _collect_mesh_instances(layer_node)
		if mesh_instances.is_empty():
			continue

		stats["layers_processed"] += 1
		var layer_surface_count := 0

		for mesh_inst: MeshInstance3D in mesh_instances:
			if mesh_inst.mesh == null:
				continue
			var surface_count := mesh_inst.mesh.get_surface_count()
			if surface_count <= 0:
				continue

			var upgraded_any := false
			for s_idx in surface_count:
				var mat_key := _resolve_material_key(layer_name, mesh_inst, s_idx, is_rural)
				var mat := _get_material(mat_key)
				if mat == null:
					continue
				mesh_inst.set_surface_override_material(s_idx, mat)
				used_keys[mat_key] = true
				layer_surface_count += 1
				upgraded_any = true

			if upgraded_any:
				stats["meshes_upgraded"] += 1
				var tint := _tint_for_layer(layer_name, variation)
				mesh_inst.set_instance_shader_parameter("tile_tint", Vector3(tint.r, tint.g, tint.b))
				mesh_inst.set_instance_shader_parameter("tile_wear", float(variation["wear"]))

		stats["by_layer"][layer_name] = layer_surface_count
		stats["surfaces_upgraded"] += layer_surface_count

	var used_list: Array[String] = []
	for k: String in used_keys:
		used_list.append(k)
	used_list.sort()
	stats["materials_used"] = used_list
	return stats


static func _collect_mesh_instances(root: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		result.append(root)
	for child in root.find_children("*", "MeshInstance3D", true, false):
		if child is MeshInstance3D:
			result.append(child)
	return result


static func _resolve_material_key(
	layer_name: String,
	mesh_inst: MeshInstance3D,
	surface_idx: int,
	is_rural: bool
) -> String:
	var existing := mesh_inst.get_surface_override_material(surface_idx)
	if existing == null:
		existing = mesh_inst.mesh.surface_get_material(surface_idx)

	var hint: String = str(mesh_inst.mesh.surface_get_name(surface_idx)).to_lower()
	if existing != null:
		hint += " " + existing.resource_name.to_lower() + " " + existing.resource_path.get_file().to_lower()

	match layer_name:
		"Roads":
			if "gravel" in hint:
				return "road_gravel"
			if "highway" in hint:
				return "asphalt_highway"
			if "service" in hint:
				return "asphalt_service"
			if "local" in hint or is_rural:
				return "asphalt_local"
			return "asphalt_arterial"
		"Sidewalks":
			return "sidewalk_concrete"
		"Markings":
			if "yellow" in hint:
				return "marking_yellow"
			return "marking_white"
		"StreetEdges":
			if "joint" in hint:
				return "slab_joint"
			if "crosswalk" in hint or "crossing" in hint or "white" in hint:
				return "crosswalk_white"
			return "curb_concrete"
		"StreetPaint":
			if "yellow" in hint:
				return "marking_yellow"
			return "marking_white"
		"StreetWear":
			if "new_slab" in hint or "concrete_new" in hint:
				return "concrete_new"
			if "ramp" in hint:
				return "concrete_ramp"
			if "yellow" in hint:
				return "marking_yellow"
			if "white" in hint:
				return "marking_white"
			if "asphalt" in hint:
				return "asphalt_local"
			return "concrete_old"
	return "asphalt_arterial"


static func _get_material(mat_key: String) -> Material:
	if _material_cache.has(mat_key):
		return _material_cache[mat_key]
	if not MATERIAL_FILES.has(mat_key):
		return null
	var path: String = MATERIAL_BASE + MATERIAL_FILES[mat_key]
	var loaded := load(path) as Material
	if loaded != null:
		_material_cache[mat_key] = loaded
	return loaded


static func _compute_tile_variation(tile_id: String, tile_meta: Dictionary) -> Dictionary:
	var h1 := _hash_unit(tile_id + "_a")
	var h2 := _hash_unit(tile_id + "_b")
	var density_bias := clampf(float(tile_meta.get("buildings", 1000)) / 3000.0, 0.0, 1.0)
	var wear := clampf(h2 * 0.15 + (density_bias - 0.5) * 0.12, -0.22, 0.22)
	return {
		"asphalt_tint": Color(1.0 + h1 * 0.042, 1.0 + h1 * 0.038, 1.0 + h1 * 0.032, 1.0),
		"concrete_tint": Color(1.0 + h2 * 0.034, 1.0 + h2 * 0.030, 1.0 + h2 * 0.024, 1.0),
		"paint_tint": Color(1.0 + h1 * 0.024, 1.0 + h1 * 0.024, 1.0 + h1 * 0.018, 1.0),
		"wear": wear,
	}


static func _tint_for_layer(layer_name: String, variation: Dictionary) -> Color:
	match layer_name:
		"Roads":
			return variation["asphalt_tint"]
		"Markings", "StreetPaint":
			return variation["paint_tint"]
		_:
			return variation["concrete_tint"]


static func _hash_unit(key: String) -> float:
	var h := key.hash()
	var norm := float(posmod(h, 10007)) / 10006.0
	return norm * 2.0 - 1.0
