extends Node3D
## One independent 2 km district scene with visible and collision layers.

const DistrictSolids := preload("res://preview/district_solids.gd")
const RoadSidewalkDetailerScript := preload("res://scripts/citywide/road_sidewalk_detailer.gd")
const BuildingFacadeDetailerScript := preload("res://scripts/citywide/building_facade_detailer.gd")
const VegetationPropsDetailerScript := preload("res://scripts/citywide/vegetation_props_detailer.gd")
const VehiclesCommercialDetailerScript := preload("res://scripts/citywide/vehicles_commercial_detailer.gd")

@export var tile_id: String
static var kit_meshes: Dictionary = {}
static var _atlas_tiles_cache: Dictionary = {}
static var _atlas_loaded := false
var _collision_enabled := false
var _native_collision := false
var _prop_placements: Dictionary = {}
var _solids := DistrictSolids.new()
var _collision_root: Node3D
var _surface_shapes: Dictionary = {}
var citywide_stats: Dictionary = {}

func _ready() -> void:
	for layer in ["StreetPaint", "StreetWear", "StreetWires"]:
		var assembly := get_node_or_null(layer)
		if assembly == null:
			continue
		var instances := assembly.find_children("*", "MeshInstance3D", true, false)
		if assembly is MeshInstance3D:
			instances.push_front(assembly)
		for surface: MeshInstance3D in instances:
			surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			surface.visibility_range_end = 500.0 if layer == "StreetWires" else 385.0
			surface.visibility_range_end_margin = 30.0
	_add_street_furniture()
	for layer in ["StreetEdges", "FacadeDetails"]:
		var detail := get_node_or_null(layer)
		if detail:
			for surface: MeshInstance3D in detail.find_children("*", "MeshInstance3D", true, false):
				surface.visibility_range_end = 485.0
				surface.visibility_range_end_margin = 32.0
				surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var path := "res://tiles/%s/instances.json" % tile_id
	if FileAccess.file_exists(path):
		var records: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		for kind: String in records:
			_add_instances(kind, records[kind])
	_apply_citywide_detailers()


static func _get_tile_meta(target_tile_id: String) -> Dictionary:
	if not _atlas_loaded:
		_atlas_loaded = true
		var atlas_path := "res://docs/HARLINGEN_ATLAS.json"
		if FileAccess.file_exists(atlas_path):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(atlas_path))
			if parsed is Dictionary:
				var tiles_val: Variant = parsed.get("tiles", [])
				if tiles_val is Array:
					for entry: Variant in tiles_val:
						if entry is Dictionary and entry.has("id"):
							_atlas_tiles_cache[str(entry["id"])] = entry
				elif tiles_val is Dictionary:
					_atlas_tiles_cache = tiles_val
	var meta: Variant = _atlas_tiles_cache.get(target_tile_id, {})
	return meta if meta is Dictionary else {}


func _apply_citywide_detailers() -> void:
	var tile_meta: Dictionary = _get_tile_meta(tile_id)
	citywide_stats = {
		"roads_sidewalks": RoadSidewalkDetailerScript.apply_to_tile(self, tile_id, tile_meta),
		"building_facades": BuildingFacadeDetailerScript.apply_to_tile(self, tile_id, tile_meta),
		"vegetation_props": VegetationPropsDetailerScript.apply_to_tile(self, tile_id, tile_meta),
		"vehicles_commercial": VehiclesCommercialDetailerScript.apply_to_tile(self, tile_id, tile_meta),
	}

func _add_street_furniture() -> void:
	var path := "res://tiles/%s/StreetFurniture.json" % tile_id
	if not FileAccess.file_exists(path):
		return
	var records: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var furniture := Node3D.new()
	furniture.name = "StreetFurniture"
	add_child(furniture)
	for kind: String in records:
		var resource := "street_realism/" + kind
		if not kit_meshes.has(resource):
			var packed := load("res://assets/%s.glb" % resource) as PackedScene
			var prototype := packed.instantiate()
			kit_meshes[resource] = _mesh_instance(prototype).mesh
			prototype.free()
		var chunks := {}
		for row: Array in records[kind]:
			var cell := Vector2i(floori(row[0] / 256.0), floori(row[2] / 256.0))
			if not chunks.has(cell):
				chunks[cell] = []
			chunks[cell].append(row)
		for cell: Vector2i in chunks:
			var batch: Array = chunks[cell]
			var center := Vector3(cell.x * 256 + 128, 0.0, cell.y * 256 + 128)
			var instance := MultiMeshInstance3D.new()
			instance.position = center
			instance.multimesh = MultiMesh.new()
			instance.multimesh.transform_format = MultiMesh.TRANSFORM_3D
			instance.multimesh.mesh = kit_meshes[resource]
			instance.multimesh.instance_count = batch.size()
			for i in batch.size():
				var row: Array = batch[i]
				var basis := Basis(Vector3.UP, float(row[3]))
				var position := Vector3(row[0], row[1], row[2]) - center
				var placement := Transform3D(basis, position)
				instance.multimesh.set_instance_transform(i, placement)
				placement.origin += center
				_prop_placements.get_or_add(kind, []).append(placement)
			instance.visibility_range_end = 490.0 if kind in ["pole", "light", "signal0", "signal1"] else 300.0
			instance.visibility_range_end_margin = 35.0
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			furniture.add_child(instance)

func _add_instances(kind: String, placements: Array) -> void:
	if not kit_meshes.has(kind):
		var kit_scene := load("res://assets/%s.glb" % kind) as PackedScene
		var node := kit_scene.instantiate()
		kit_meshes[kind] = _mesh_instance(node).mesh
		node.free()
	var instance := MultiMeshInstance3D.new()
	instance.name = kind
	instance.multimesh = MultiMesh.new()
	instance.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	instance.multimesh.mesh = kit_meshes[kind]
	instance.multimesh.instance_count = placements.size()
	for i in placements.size():
		var row: Array = placements[i]
		var basis := Basis(Vector3.UP, float(row[3])).scaled(Vector3.ONE * float(row[4]))
		var placement := Transform3D(basis, Vector3(row[0], row[1], row[2]))
		instance.multimesh.set_instance_transform(i, placement)
		_prop_placements.get_or_add(kind, []).append(placement)
	match kind:
		"palm": instance.visibility_range_end = 2050.0
		"scrub": instance.visibility_range_end = 650.0
		"dry_grass": instance.visibility_range_end = 260.0
		_: instance.visibility_range_end = 1400.0
	instance.visibility_range_end_margin = 180.0
	if kind != "palm":
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)

static func _mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	return node.find_children("*", "MeshInstance3D", true, false)[0]

func update_detail(use_native_ground: bool, near: bool, detailed_buildings: bool, collisions: bool) -> void:
	$TerrainMesh.visible = near and not use_native_ground
	$TerrainFar.visible = not near and not use_native_ground
	var buildings := get_node_or_null("Buildings") as Node3D
	if buildings:
		buildings.visible = detailed_buildings
		$BuildingsFar.visible = not detailed_buildings
	for layer in [
		"Markings", "Sidewalks", "StreetEdges", "FacadeDetails",
		"StreetPaint", "StreetWear", "StreetWires", "StreetFurniture",
		"CitywideVegetationProps", "CitywideVehiclesCommercial", "CitywideStorefrontAccents"
	]:
		var node := get_node_or_null(layer) as Node3D
		if node:
			node.visible = near
	if collisions == _collision_enabled and (not collisions or use_native_ground == _native_collision):
		return
	_collision_enabled = collisions
	_native_collision = use_native_ground
	if is_instance_valid(_collision_root):
		remove_child(_collision_root)
		_collision_root.queue_free()
		_collision_root = null
	if not collisions:
		return

	var body := StaticBody3D.new()
	body.name = "DistrictCollision"
	body.collision_layer = DistrictSolids.WORLD
	body.collision_mask = 0
	for layer in ["GroundCollision", "BuildingCollision", "BridgeCollision", "ElevatedCollision", "StreetRampCollision"]:
		if layer == "GroundCollision" and use_native_ground:
			continue
		var path := "res://tiles/%s/%s.glb" % [tile_id, layer]
		if not ResourceLoader.exists(path):
			continue
		var packed := load(path) as PackedScene
		var source := packed.instantiate()
		var surface := _mesh_instance(source)
		_add_shape(body, layer, surface.mesh.create_trimesh_shape(), Transform3D.IDENTITY)
		source.free()
	# Collision uses the same draped asphalt, sidewalk and curb heights as the
	# renderer. Filter out markings, joints and decorative land cover.
	_add_visible_surface(body, "Roads")
	_add_visible_surface(body, "Sidewalks")
	_add_visible_surface(body, "StreetEdges", ["curb", "raised_curb"])
	_add_visible_surface(body, "LandCover", ["lot", "asphalt_lot", "parking_asphalt"])
	_collision_root = body
	_solids.populate(self, body, _prop_placements)
	add_child(body)

func _add_visible_surface(body: StaticBody3D, layer: String, tags: Array = []) -> void:
	var source := get_node_or_null(layer)
	if not source:
		return
	var inverse := global_transform.affine_inverse()
	for surface: MeshInstance3D in DistrictSolids.mesh_instances(source):
		if surface.mesh == null:
			continue
		var mesh_id := surface.mesh.get_instance_id()
		if not _surface_shapes.has(mesh_id):
			_surface_shapes[mesh_id] = surface.mesh.create_trimesh_shape() if tags.is_empty() else DistrictSolids.selected_shape(surface.mesh, tags)
		_add_shape(body, layer, _surface_shapes[mesh_id], inverse * surface.global_transform)

func _add_shape(body: StaticBody3D, label: String, shape: Shape3D, placement: Transform3D) -> void:
	if not shape:
		return
	var collider := CollisionShape3D.new()
	collider.name = label
	collider.shape = shape
	collider.transform = placement
	body.add_child(collider, true)
