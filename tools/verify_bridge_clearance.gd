extends SceneTree
## Check the shipped district collision at each audited slip-road opening.

const TILE_SIZE := 2000.0
const COLLISION_MASK := 1
const TARGET := 4.5

var _tiles := {}
var _failures := 0

func _initialize() -> void:
	call_deferred("_verify")

func _load_tile(ix: int, iz: int) -> void:
	var key := "%+03d_%+03d" % [ix, iz]
	if _tiles.has(key):
		return
	var path := "res://tiles/%s/district.tscn" % key
	var scene := load(path) as PackedScene
	if scene == null:
		_fail("Cannot load district " + key)
		return
	var district := scene.instantiate() as Node3D
	root.add_child(district)
	district.update_detail(false, true, true, true)
	_tiles[key] = district

func _fail(message: String) -> void:
	_failures += 1
	push_error(message)

func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, COLLISION_MASK)
	query.hit_back_faces = false
	return root.world_3d.direct_space_state.intersect_ray(query)

func _verify() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://manifest.json"))
	var data: Dictionary = manifest.elevated_highway.bridge_clearance
	if data.crossings.size() != 18:
		_fail("Expected all 18 audit crossings")
	for row: Dictionary in data.crossings:
		var x: float = row.center[0]
		var z: float = row.center[2]
		_load_tile(floori((x - 50.0) / TILE_SIZE), floori((z - 50.0) / TILE_SIZE))
		_load_tile(floori((x + 50.0) / TILE_SIZE), floori((z - 50.0) / TILE_SIZE))
		_load_tile(floori((x - 50.0) / TILE_SIZE), floori((z + 50.0) / TILE_SIZE))
		_load_tile(floori((x + 50.0) / TILE_SIZE), floori((z + 50.0) / TILE_SIZE))
	await physics_frame
	await physics_frame

	var envelope := BoxShape3D.new()
	# Check a 2.02 m wide vehicle envelope along each slip road. The diagnostic
	# height includes the full clearance target, with a small ground tolerance.
	envelope.size = Vector3(2.02, 4.20, 0.65)
	var minimum := INF
	for row: Dictionary in data.crossings:
		var tag := "%s / %s" % [row.upper_way, row.lower_way]
		var p := Vector3(row.center[0], row.center[1], row.center[2])
		var predicted_deck: float = row.center[3]
		var road := _ray(p + Vector3.UP * 0.7, p - Vector3.UP * 4.0)
		var deck := _ray(Vector3(p.x, predicted_deck + 0.25, p.z),
			Vector3(p.x, predicted_deck - 0.4, p.z))
		var underside := _ray(p + Vector3.UP * 0.7, Vector3(p.x, predicted_deck - 0.05, p.z))
		if road.is_empty() or deck.is_empty() or underside.is_empty():
			_fail("Missing road, deck or soffit collision at " + tag)
			continue
		var clearance: float = underside.position.y - road.position.y
		minimum = minf(minimum, clearance)
		if clearance < TARGET or absf(deck.position.y - predicted_deck) > 0.15:
			_fail("Clearance or deck collision outside tolerance at " + tag + ": " + str(clearance))

		for sample: Array in row.slip_path:
			var path_point := Vector3(sample[0], p.y, sample[1])
			var floor_hit := _ray(path_point + Vector3.UP * 1.5, path_point - Vector3.UP * 3.0)
			if floor_hit.is_empty():
				_fail("Missing slip-road floor along " + tag)
				break
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = envelope
			query.collision_mask = COLLISION_MASK
			var heading := Vector3(sample[2], 0, sample[3]).normalized()
			query.transform = Transform3D(Basis.looking_at(heading), floor_hit.position + Vector3.UP * 2.28)
			var hits := root.world_3d.direct_space_state.intersect_shape(query, 12)
			if not hits.is_empty():
				for hit: Dictionary in hits:
					var body: CollisionObject3D = hit.collider
					var shape := body.shape_owner_get_owner(body.shape_find_owner(hit.shape))
					print("BLOCKING_SHAPE ", body.get_path(), "/", shape.name)
				_fail("Vehicle envelope obstructed along %s at %s" % [tag, floor_hit.position])
				break
		print("BRIDGE_COLLISION ", tag, " center_clearance_m=", clearance)

	if _failures == 0:
		print("VERIFY_BRIDGE_CLEARANCE_PASS crossings=18 minimum_center_collision_clearance_m=", minimum)
		quit(0)
	else:
		print("VERIFY_BRIDGE_CLEARANCE_FAIL count=", _failures)
		quit(1)
