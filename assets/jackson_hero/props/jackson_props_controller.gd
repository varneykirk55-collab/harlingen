@tool
extends Node3D

const MAT_CAST_IRON := preload("res://assets/jackson_hero/props/mat_cast_iron.tres")
const MAT_MANHOLE_IRON := preload("res://assets/jackson_hero/props/mat_manhole_iron.tres")
const MAT_PLANTER_CONCRETE := preload("res://assets/jackson_hero/props/mat_planter_concrete.tres")
const MAT_SHRUB_LEAF := preload("res://assets/jackson_hero/props/mat_shrub_leaf.tres")
const MAT_ASPHALT_PATCH := preload("res://assets/jackson_hero/props/mat_asphalt_patch.tres")

const GROUP_VIS_RANGE := {
	"ParkedVehicles": 160.0,
	"Streetlamps": 160.0,
	"Benches": 100.0,
	"TrashBins": 90.0,
	"Planters": 100.0,
	"ParkingSigns": 90.0,
	"RoadDetails": 75.0,
}

const CAR_PAINTS := {
	"silver": Color(0.68, 0.71, 0.75, 1.0),
	"navy": Color(0.08, 0.16, 0.34, 1.0),
	"white": Color(0.88, 0.87, 0.84, 1.0),
	"charcoal": Color(0.18, 0.19, 0.21, 1.0),
	"burgundy": Color(0.42, 0.08, 0.11, 1.0),
	"green": Color(0.11, 0.26, 0.17, 1.0),
}

var _paint_cache: Dictionary = {}


func _ready() -> void:
	_apply_props_setup()


func _apply_props_setup() -> void:
	for group_node in get_children():
		var vis_end: float = GROUP_VIS_RANGE.get(group_node.name, 120.0)
		for prop in group_node.get_children():
			var paint_mat: Material = null
			if prop.has_meta("paint_key"):
				paint_mat = _get_car_paint(str(prop.get_meta("paint_key")))
			_configure_subtree(prop, vis_end, paint_mat)


func _configure_subtree(node: Node, vis_end: float, paint_mat: Material) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		mi.visibility_range_end = vis_end
		if mi.mesh:
			for s in range(mi.mesh.get_surface_count()):
				var mat := mi.mesh.surface_get_material(s)
				if mat == null:
					continue
				var mname := mat.resource_name
				if paint_mat != null and mname == "mat_car_paint":
					mi.set_surface_override_material(s, paint_mat)
				elif mname in ["mat_cast_iron", "mat_trash_metal"]:
					mi.set_surface_override_material(s, MAT_CAST_IRON)
				elif mname in ["mat_manhole_iron", "mat_storm_grate"]:
					mi.set_surface_override_material(s, MAT_MANHOLE_IRON)
				elif mname == "mat_planter_concrete":
					mi.set_surface_override_material(s, MAT_PLANTER_CONCRETE)
				elif mname == "mat_shrub_leaf":
					mi.set_surface_override_material(s, MAT_SHRUB_LEAF)
				elif mname == "mat_asphalt_patch":
					mi.set_surface_override_material(s, MAT_ASPHALT_PATCH)
	for child in node.get_children():
		_configure_subtree(child, vis_end, paint_mat)


func _get_car_paint(key: String) -> Material:
	if _paint_cache.has(key):
		return _paint_cache[key]
	var col: Color = CAR_PAINTS.get(key, Color(0.55, 0.58, 0.62, 1.0))
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.metallic = 0.72
	mat.metallic_specular = 0.65
	mat.roughness = 0.22
	_paint_cache[key] = mat
	return mat
