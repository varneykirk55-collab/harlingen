class_name VegetationPropsDetailer
extends RefCounted
## Citywide vegetation and street furniture detailer for Harlingen district tiles.
## Derives sidewalk/curb placement points from StreetFurniture.json and instances.json,
## skips the +00_+00 Jackson Street hero corridor, and batches instances into 256m
## MultiMeshInstance3D chunks with RX 560X-friendly visibility_range_end settings.

const CONTAINER_NAME := "CitywideVegetationProps"
const CHUNK_SIZE := 256.0

# Jackson Street hero corridor in tile +00_+00 (DowntownStreetscape / JacksonStreetProps / JacksonVegetation).
const JACKSON_HERO_MIN := Vector2(70.0, 280.0)
const JACKSON_HERO_MAX := Vector2(900.0, 370.0)

const ASSET_PATHS := {
	"palm": "res://assets/jackson_hero/veg/washingtonia_palm.glb",
	"crape_myrtle": "res://assets/jackson_hero/veg/crape_myrtle.glb",
	"streetlamp": "res://assets/jackson_hero/props/ornamental_streetlamp.glb",
	"bench": "res://assets/bench.glb",
	"planter": "res://assets/jackson_hero/props/street_planter.glb",
	"trash_bin": "res://assets/jackson_hero/props/trash_receptacle.glb",
}

const VISIBILITY_RANGES := {
	"palm": [250.0, 25.0],
	"crape_myrtle": [180.0, 20.0],
	"streetlamp": [160.0, 20.0],
	"bench": [100.0, 15.0],
	"planter": [100.0, 15.0],
	"trash_bin": [90.0, 15.0],
}

const MAT_CAST_IRON_PATH := "res://assets/jackson_hero/props/mat_cast_iron.tres"
const MAT_PLANTER_CONCRETE_PATH := "res://assets/jackson_hero/props/mat_planter_concrete.tres"
const MAT_SHRUB_LEAF_PATH := "res://assets/jackson_hero/props/mat_shrub_leaf.tres"

# Cached per-kind dictionary: { "mesh": Mesh, "local_offset": Vector3 }
static var _mesh_cache: Dictionary = {}
static var _mat_cache: Dictionary = {}


static func apply_to_tile(tile_node: Node3D, tile_id: String, tile_meta: Dictionary = {}) -> Dictionary:
	var stats := {
		"tile_id": tile_id,
		"palms_added": 0,
		"crape_myrtles_added": 0,
		"streetlamps_added": 0,
		"benches_added": 0,
		"planters_added": 0,
		"trash_bins_added": 0,
		"total_props_added": 0,
		"multimesh_chunks": 0,
		"skipped_jackson": 0,
		"already_applied": false,
	}
	if tile_node == null or not is_instance_valid(tile_node):
		return stats

	if tile_node.get_node_or_null(CONTAINER_NAME) != null:
		stats["already_applied"] = true
		return stats

	var sf_data := _load_json_dict("res://tiles/%s/StreetFurniture.json" % tile_id)
	var inst_data := _load_json_dict("res://tiles/%s/instances.json" % tile_id)
	if sf_data.is_empty() and inst_data.is_empty():
		return stats

	var lights: Array = sf_data.get("light", [])
	if lights.is_empty():
		return stats

	# Build spatial hash of existing obstacles/anchors so we never overlap furniture or intersections.
	var obstacle_grid := {}
	var intersection_pts: Array[Vector2] = []
	for key in sf_data.keys():
		var rows: Array = sf_data[key]
		for row in rows:
			if row.size() < 3:
				continue
			var p2 := Vector2(float(row[0]), float(row[2]))
			_grid_insert(obstacle_grid, p2, 8.0)
			if key == "signal0" or key == "signal1":
				intersection_pts.append(p2)

	for key in inst_data.keys():
		var rows: Array = inst_data[key]
		for row in rows:
			if row.size() < 3:
				continue
			var p2 := Vector2(float(row[0]), float(row[2]))
			_grid_insert(obstacle_grid, p2, 8.0)
			if key == "stop_sign" or key == "traffic_signal":
				intersection_pts.append(p2)

	# Determine district density tier from StreetFurniture + tile_meta.
	var light_count := lights.size()
	var is_urban := light_count >= 90 or str(tile_meta.get("tier", "")) == "urban"
	var is_suburban := not is_urban and light_count >= 25

	var rng := RandomNumberGenerator.new()
	rng.seed = hash(tile_id)

	var placements := {
		"palm": [],
		"crape_myrtle": [],
		"streetlamp": [],
		"bench": [],
		"planter": [],
		"trash_bin": [],
	}

	# Track our own newly placed props to enforce minimum spacing.
	var placed_veg_grid := {}
	var placed_prop_grid := {}

	# 1. Derive valid sidewalk/curb segments from pairs of neighboring streetlights (16m..55m apart).
	#    Midpoints and quarter-points along consecutive curb lights stay on the sidewalk line.
	var light_grid := {}
	for i in lights.size():
		var r: Array = lights[i]
		if r.size() >= 4:
			_grid_insert_idx(light_grid, Vector2(float(r[0]), float(r[2])), i, 60.0)

	var used_pairs := {}
	var max_veg := 220 if is_urban else (140 if is_suburban else 60)
	var max_furniture := 160 if is_urban else (70 if is_suburban else 20)
	var veg_count := 0
	var furn_count := 0

	for i in lights.size():
		var r1: Array = lights[i]
		if r1.size() < 4:
			continue
		var p1 := Vector3(float(r1[0]), float(r1[1]), float(r1[2]))
		var yaw1 := float(r1[3])

		var neighbors := _grid_query_idx(light_grid, Vector2(p1.x, p1.z), 60.0)
		var best_j := -1
		var best_dist := 55.0
		for j in neighbors:
			if j <= i:
				continue
			var r2: Array = lights[j]
			var p2 := Vector3(float(r2[0]), float(r2[1]), float(r2[2]))
			var d := Vector2(p1.x, p1.z).distance_to(Vector2(p2.x, p2.z))
			if d >= 16.0 and d < best_dist:
				best_dist = d
				best_j = j

		if best_j < 0:
			continue

		var pair_key := "%d_%d" % [i, best_j]
		if used_pairs.has(pair_key):
			continue
		used_pairs[pair_key] = true

		var r2: Array = lights[best_j]
		var p2 := Vector3(float(r2[0]), float(r2[1]), float(r2[2]))
		var seg_dir := Vector2(p2.x - p1.x, p2.z - p1.z).normalized()
		var seg_yaw := atan2(seg_dir.x, seg_dir.y)

		# Midpoint: vegetation (Washingtonia palm or Crape Myrtle).
		if veg_count < max_veg:
			var mid := p1.lerp(p2, 0.5)
			var mid2 := Vector2(mid.x, mid.z)
			if _is_jackson_hero(tile_id, mid2):
				stats["skipped_jackson"] += 1
			elif not _near_any(mid2, intersection_pts, 12.0) \
					and not _grid_has_near(obstacle_grid, mid2, 2.4, 8.0) \
					and not _grid_has_near(placed_veg_grid, mid2, 13.0, 16.0):
				var kind := "palm" if rng.randf() < 0.45 else "crape_myrtle"
				var scale := rng.randf_range(0.86, 1.06) if kind == "palm" else rng.randf_range(0.88, 1.05)
				var yaw := rng.randf_range(0.0, TAU)
				placements[kind].append([mid.x, mid.y, mid.z, yaw, scale])
				_grid_insert(placed_veg_grid, mid2, 16.0)
				veg_count += 1

		# Quarter-points: urban/suburban street furniture (planter, bench, trash_bin, ornamental streetlamp).
		if furn_count < max_furniture and best_dist >= 22.0:
			var q_t := 0.28 if (i % 2 == 0) else 0.72
			var qp := p1.lerp(p2, q_t)
			var qp2 := Vector2(qp.x, qp.z)
			if _is_jackson_hero(tile_id, qp2):
				stats["skipped_jackson"] += 1
			elif not _near_any(qp2, intersection_pts, 12.0) \
					and not _grid_has_near(obstacle_grid, qp2, 2.2, 8.0) \
					and not _grid_has_near(placed_veg_grid, qp2, 3.0, 16.0) \
					and not _grid_has_near(placed_prop_grid, qp2, 9.0, 12.0):
				var roll := rng.randf()
				var fkind := "planter"
				if is_urban:
					if roll < 0.34:
						fkind = "planter"
					elif roll < 0.60:
						fkind = "trash_bin"
					elif roll < 0.84:
						fkind = "bench"
					else:
						fkind = "streetlamp"
				elif is_suburban:
					if roll < 0.45:
						fkind = "planter"
					elif roll < 0.75:
						fkind = "bench"
					else:
						fkind = "trash_bin"
				else:
					fkind = "bench" if roll < 0.5 else "planter"

				var fyaw := seg_yaw if fkind != "streetlamp" else yaw1
				placements[fkind].append([qp.x, qp.y, qp.z, fyaw, 1.0])
				_grid_insert(placed_prop_grid, qp2, 12.0)
				furn_count += 1

	# 2. Add pedestrian trash_bin / bench companions near existing news/mailbox sidewalk anchors in urban tiles.
	if is_urban and furn_count < max_furniture + 40:
		for anchor_key in ["news", "mailbox"]:
			var anchors: Array = sf_data.get(anchor_key, [])
			for idx in anchors.size():
				if idx % 3 != 0:
					continue
				var ar: Array = anchors[idx]
				if ar.size() < 4:
					continue
				var ap := Vector3(float(ar[0]), float(ar[1]), float(ar[2]))
				var ayaw := float(ar[3])
				# Offset 1.4m along the sidewalk tangent (perpendicular to facing yaw).
				var tangent := Vector3(cos(ayaw), 0.0, -sin(ayaw))
				var cand := ap + tangent * 1.4
				var cand2 := Vector2(cand.x, cand.z)
				if _is_jackson_hero(tile_id, cand2):
					stats["skipped_jackson"] += 1
					continue
				if _near_any(cand2, intersection_pts, 10.0):
					continue
				if _grid_has_near(obstacle_grid, cand2, 1.2, 8.0) or _grid_has_near(placed_prop_grid, cand2, 6.0, 12.0):
					continue
				var pkind := "trash_bin" if (idx % 2 == 0) else "planter"
				placements[pkind].append([cand.x, cand.y, cand.z, ayaw, 1.0])
				_grid_insert(placed_prop_grid, cand2, 12.0)
				furn_count += 1

	# 3. Build 256m chunked MultiMeshInstance3D nodes under CitywideVegetationProps.
	var container := Node3D.new()
	container.name = CONTAINER_NAME
	tile_node.add_child(container)

	var chunks_created := 0
	for kind in placements.keys():
		var rows: Array = placements[kind]
		if rows.is_empty():
			continue
		var mesh_info := _get_mesh_info(kind)
		if mesh_info.is_empty():
			continue
		var mesh: Mesh = mesh_info["mesh"]
		var local_offset: Vector3 = mesh_info["local_offset"]
		var vis_cfg: Array = VISIBILITY_RANGES[kind]

		var chunks := {}
		for row in rows:
			var cell := Vector2i(floori(float(row[0]) / CHUNK_SIZE), floori(float(row[2]) / CHUNK_SIZE))
			if not chunks.has(cell):
				chunks[cell] = []
			chunks[cell].append(row)

		for cell in chunks.keys():
			var batch: Array = chunks[cell]
			var center := Vector3(cell.x * CHUNK_SIZE + CHUNK_SIZE * 0.5, 0.0, cell.y * CHUNK_SIZE + CHUNK_SIZE * 0.5)
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "%s_%d_%d" % [kind, cell.x, cell.y]
			mmi.position = center
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.visibility_range_end = float(vis_cfg[0])
			mmi.visibility_range_end_margin = float(vis_cfg[1])

			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = mesh
			mm.instance_count = batch.size()
			for i in batch.size():
				var row: Array = batch[i]
				var basis := Basis(Vector3.UP, float(row[3])).scaled(Vector3.ONE * float(row[4]))
				var pos := Vector3(float(row[0]), float(row[1]), float(row[2])) - center + (basis * local_offset)
				mm.set_instance_transform(i, Transform3D(basis, pos))
			mmi.multimesh = mm
			container.add_child(mmi)
			chunks_created += 1

	stats["palms_added"] = placements["palm"].size()
	stats["crape_myrtles_added"] = placements["crape_myrtle"].size()
	stats["streetlamps_added"] = placements["streetlamp"].size()
	stats["benches_added"] = placements["bench"].size()
	stats["planters_added"] = placements["planter"].size()
	stats["trash_bins_added"] = placements["trash_bin"].size()
	stats["total_props_added"] = (
		stats["palms_added"]
		+ stats["crape_myrtles_added"]
		+ stats["streetlamps_added"]
		+ stats["benches_added"]
		+ stats["planters_added"]
		+ stats["trash_bins_added"]
	)
	stats["multimesh_chunks"] = chunks_created
	return stats


static func _is_jackson_hero(tile_id: String, p2: Vector2) -> bool:
	if tile_id != "+00_+00":
		return false
	return p2.x >= JACKSON_HERO_MIN.x and p2.x <= JACKSON_HERO_MAX.x \
		and p2.y >= JACKSON_HERO_MIN.y and p2.y <= JACKSON_HERO_MAX.y


static func _load_json_dict(res_path: String) -> Dictionary:
	if not FileAccess.file_exists(res_path):
		return {}
	var text := FileAccess.get_file_as_string(res_path)
	var parsed = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	return {}


static func _get_mesh_info(kind: String) -> Dictionary:
	if _mesh_cache.has(kind):
		return _mesh_cache[kind]
	var path: String = ASSET_PATHS.get(kind, "")
	if path.is_empty() or not ResourceLoader.exists(path):
		return {}
	var packed := load(path) as PackedScene
	if packed == null:
		return {}
	var root := packed.instantiate()
	var mi := _find_mesh_instance(root)
	if mi == null or mi.mesh == null:
		root.free()
		return {}
	var mesh_copy := mi.mesh.duplicate() as Mesh
	var local_offset := mi.position
	root.free()

	_apply_shared_prop_materials(mesh_copy)
	var info := {
		"mesh": mesh_copy,
		"local_offset": local_offset,
	}
	_mesh_cache[kind] = info
	return info


static func _apply_shared_prop_materials(mesh: Mesh) -> void:
	for s in mesh.get_surface_count():
		var mat := mesh.surface_get_material(s)
		if mat == null:
			continue
		var mname := mat.resource_name
		if mname in ["mat_cast_iron", "mat_trash_metal"]:
			var m := _get_material(MAT_CAST_IRON_PATH)
			if m:
				mesh.surface_set_material(s, m)
		elif mname == "mat_planter_concrete":
			var m := _get_material(MAT_PLANTER_CONCRETE_PATH)
			if m:
				mesh.surface_set_material(s, m)
		elif mname == "mat_shrub_leaf":
			var m := _get_material(MAT_SHRUB_LEAF_PATH)
			if m:
				mesh.surface_set_material(s, m)


static func _get_material(path: String) -> Material:
	if _mat_cache.has(path):
		return _mat_cache[path]
	if not ResourceLoader.exists(path):
		return null
	var mat := load(path) as Material
	_mat_cache[path] = mat
	return mat


static func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	var found := node.find_children("*", "MeshInstance3D", true, false)
	if found.is_empty():
		return null
	return found[0] as MeshInstance3D


static func _near_any(p: Vector2, pts: Array[Vector2], radius: float) -> bool:
	var r2 := radius * radius
	for q in pts:
		if p.distance_squared_to(q) <= r2:
			return true
	return false


static func _grid_insert(grid: Dictionary, p: Vector2, cell_size: float) -> void:
	var key := Vector2i(floori(p.x / cell_size), floori(p.y / cell_size))
	if not grid.has(key):
		grid[key] = []
	grid[key].append(p)


static func _grid_has_near(grid: Dictionary, p: Vector2, radius: float, cell_size: float) -> bool:
	var r2 := radius * radius
	var cx := floori(p.x / cell_size)
	var cy := floori(p.y / cell_size)
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var key := Vector2i(cx + dx, cy + dy)
			if not grid.has(key):
				continue
			for q: Vector2 in grid[key]:
				if p.distance_squared_to(q) <= r2:
					return true
	return false


static func _grid_insert_idx(grid: Dictionary, p: Vector2, idx: int, cell_size: float) -> void:
	var key := Vector2i(floori(p.x / cell_size), floori(p.y / cell_size))
	if not grid.has(key):
		grid[key] = []
	grid[key].append([p, idx])


static func _grid_query_idx(grid: Dictionary, p: Vector2, cell_size: float) -> Array[int]:
	var out: Array[int] = []
	var cx := floori(p.x / cell_size)
	var cy := floori(p.y / cell_size)
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var key := Vector2i(cx + dx, cy + dy)
			if not grid.has(key):
				continue
			for entry in grid[key]:
				out.append(int(entry[1]))
	return out
