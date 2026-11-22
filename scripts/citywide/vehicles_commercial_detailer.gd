class_name VehiclesCommercialDetailer
extends RefCounted

## Citywide parked vehicle & commercial environment detailer.
## Places varied-paint parked vehicles in valid OSM parking lots and safe
## roadside bays via MultiMeshInstance3D (<= 160m visibility, RX 560X budget).

const VEHICLE_GLBS := {
	"sedan": "res://assets/jackson_hero/props/parked_sedan.glb",
	"pickup": "res://assets/jackson_hero/props/parked_pickup.glb",
	"suv": "res://assets/jackson_hero/props/parked_suv.glb",
}

const MAT_CAR_PAINT_INSTANCED := preload("res://assets/citywide/commercial/mat_car_paint_instanced.tres")

const CAR_PAINT_PALETTE: Array[Color] = [
	Color(0.88, 0.87, 0.84, 1.0), # white
	Color(0.88, 0.87, 0.84, 1.0), # white (higher weight for South TX)
	Color(0.68, 0.71, 0.75, 1.0), # silver
	Color(0.68, 0.71, 0.75, 1.0), # silver
	Color(0.18, 0.19, 0.21, 1.0), # charcoal
	Color(0.76, 0.70, 0.58, 1.0), # sand
	Color(0.08, 0.16, 0.34, 1.0), # navy
	Color(0.42, 0.08, 0.11, 1.0), # burgundy
	Color(0.11, 0.26, 0.17, 1.0), # green
	Color(0.64, 0.10, 0.10, 1.0), # red
]

const TILE_SIZE := 2000.0
const MAX_VEHICLES_PER_TILE := 96
const MAX_ROADSIDE_PER_TILE := 24
const MAX_PER_PARKING_LOT := 18
const VISIBILITY_RANGE_END := 155.0
const VISIBILITY_RANGE_MARGIN := 20.0
const WHEEL_GROUND_OFFSET := 0.032

static var _mesh_cache: Dictionary = {}
static var _osm_loaded := false
static var _tile_parking: Dictionary = {}
static var _tile_roads: Dictionary = {}
static var _tile_buildings: Dictionary = {}
static var _tile_rails: Dictionary = {}


static func apply_to_tile(tile_node: Node3D, tile_id: String, tile_meta: Dictionary = {}) -> Dictionary:
	if tile_node == null:
		return {"tile_id": tile_id, "error": "null_tile_node"}

	var existing := tile_node.get_node_or_null("CitywideVehiclesCommercial")
	if existing != null:
		return {
			"tile_id": tile_id,
			"skipped": true,
			"reason": "already_applied",
			"parked_vehicles": int(existing.get_meta("parked_vehicles", 0)),
		}

	_ensure_osm_index()

	var bounds := _parse_tile_bounds(tile_id, tile_meta)
	var container := Node3D.new()
	container.name = "CitywideVehiclesCommercial"
	tile_node.add_child(container)

	var lots: Array = _tile_parking.get(tile_id, [])
	var roads: Array = _tile_roads.get(tile_id, [])
	var buildings: Array = _tile_buildings.get(tile_id, [])
	var rails: Array = _tile_rails.get(tile_id, [])

	var terrain_grid := _build_terrain_grid(tile_node, bounds)

	var rng := RandomNumberGenerator.new()
	rng.seed = hash("vehicles_commercial_" + tile_id)

	var placements := {
		"sedan": [],
		"pickup": [],
		"suv": [],
	}
	var occupied_pts: Array[Vector2] = []
	var lot_vehicle_count := 0
	var lots_populated := 0

	# 1. Populate valid amenity=parking lots
	for lot_idx in range(lots.size()):
		if occupied_pts.size() >= MAX_VEHICLES_PER_TILE:
			break
		var lot: Dictionary = lots[lot_idx]
		var added := _populate_parking_lot(
			lot, bounds, roads, buildings, rails,
			occupied_pts, placements, rng,
			MAX_VEHICLES_PER_TILE - occupied_pts.size()
		)
		if added > 0:
			lots_populated += 1
			lot_vehicle_count += added

	# 2. Populate safe roadside bays (never blocking intersections, driveways, or Jackson hero)
	var bay_vehicle_count := _populate_roadside_bays(
		tile_id, bounds, roads, buildings, rails,
		occupied_pts, placements, rng,
		mini(MAX_ROADSIDE_PER_TILE, MAX_VEHICLES_PER_TILE - occupied_pts.size())
	)

	# 3. Build MultiMeshInstance3D batches (1 draw call per vehicle type)
	var multimesh_count := 0
	var counts_by_kind := {"sedan": 0, "pickup": 0, "suv": 0}
	for kind: String in ["sedan", "pickup", "suv"]:
		var items: Array = placements[kind]
		counts_by_kind[kind] = items.size()
		if items.is_empty():
			continue
		var mm_node := _create_vehicle_multimesh(kind, items, tile_node, terrain_grid, bounds)
		if mm_node != null:
			container.add_child(mm_node)
			multimesh_count += 1

	var total_vehicles := lot_vehicle_count + bay_vehicle_count
	container.set_meta("parked_vehicles", total_vehicles)

	return {
		"tile_id": tile_id,
		"parked_vehicles": total_vehicles,
		"parking_lot_vehicles": lot_vehicle_count,
		"roadside_bay_vehicles": bay_vehicle_count,
		"parking_lots_found": lots.size(),
		"parking_lots_populated": lots_populated,
		"sedans": counts_by_kind["sedan"],
		"pickups": counts_by_kind["pickup"],
		"suvs": counts_by_kind["suv"],
		"multimeshes": multimesh_count,
		"visibility_range_end": VISIBILITY_RANGE_END,
	}


static func _populate_parking_lot(
	lot: Dictionary,
	bounds: Rect2,
	roads: Array,
	buildings: Array,
	rails: Array,
	occupied_pts: Array[Vector2],
	placements: Dictionary,
	rng: RandomNumberGenerator,
	budget_left: int
) -> int:
	var pts: PackedVector2Array = lot["pts"]
	if pts.size() < 3:
		return 0
	var area: float = lot["area"]
	if area < 90.0:
		return 0

	var lot_cap := mini(budget_left, mini(MAX_PER_PARKING_LOT, maxi(2, int(area / 180.0))))
	if lot_cap <= 0:
		return 0

	var angle := _dominant_edge_angle(pts)
	var cos_a := cos(-angle)
	var sin_a := sin(-angle)

	var u_min := 1e9
	var u_max := -1e9
	var v_min := 1e9
	var v_max := -1e9
	for p in pts:
		var u := p.x * cos_a - p.y * sin_a
		var v := p.x * sin_a + p.y * cos_a
		u_min = minf(u_min, u)
		u_max = maxf(u_max, u)
		v_min = minf(v_min, v)
		v_max = maxf(v_max, v)

	var cos_w := cos(angle)
	var sin_w := sin(angle)
	var added := 0

	# Scan stall grid: 3.1m stall width, 11.0m aisle-to-aisle row spacing
	var v := v_min + 3.5
	while v <= v_max - 3.5 and added < lot_cap:
		var u := u_min + 2.5
		while u <= u_max - 2.5 and added < lot_cap:
			if rng.randf() < 0.42:
				var wx := u * cos_w - v * sin_w
				var wz := u * sin_w + v * cos_w
				var cand := Vector2(wx, wz)
				var yaw := angle + (PI * 0.5 if rng.randf() < 0.5 else -PI * 0.5)
				if _is_inside_lot_with_clearance(cand, yaw, pts) and _is_safe_spot(cand, bounds, roads, buildings, rails, occupied_pts, true):
					var kind := _pick_vehicle_kind(rng)
					var color: Color = CAR_PAINT_PALETTE[rng.randi() % CAR_PAINT_PALETTE.size()]
					placements[kind].append({"pos": cand, "yaw": yaw, "color": color})
					occupied_pts.append(cand)
					added += 1
			u += 3.1
		v += 11.0

	return added


static func _populate_roadside_bays(
	tile_id: String,
	bounds: Rect2,
	roads: Array,
	buildings: Array,
	rails: Array,
	occupied_pts: Array[Vector2],
	placements: Dictionary,
	rng: RandomNumberGenerator,
	budget: int
) -> int:
	if budget <= 0:
		return 0
	var added := 0
	var jackson_hero := Rect2(50.0, 250.0, 860.0, 150.0)

	for rd: Dictionary in roads:
		if added >= budget:
			break
		var hw: String = rd["highway"]
		if hw not in ["residential", "tertiary", "unclassified"]:
			continue
		var pts: PackedVector2Array = rd["pts"]
		var half_w: float = rd["half_w"]
		for i in range(pts.size() - 1):
			if added >= budget:
				break
			var a := pts[i]
			var b := pts[i + 1]
			var seg_len := a.distance_to(b)
			if seg_len < 34.0:
				continue
			var dir := (b - a) / seg_len
			var right := Vector2(-dir.y, dir.x)
			var yaw := atan2(dir.x, dir.y)

			var d := 14.0
			while d <= seg_len - 14.0 and added < budget:
				if rng.randf() < 0.35:
					var cand := a + dir * d + right * (half_w + 1.35)
					if tile_id == "+00_+00" and jackson_hero.has_point(cand):
						d += 8.0
						continue
					if _is_safe_spot(cand, bounds, roads, buildings, rails, occupied_pts, false, rd):
						var kind := _pick_vehicle_kind(rng)
						var color := CAR_PAINT_PALETTE[rng.randi() % CAR_PAINT_PALETTE.size()]
						placements[kind].append({"pos": cand, "yaw": yaw, "color": color})
						occupied_pts.append(cand)
						added += 1
				d += 8.5

	return added


static func _is_inside_lot_with_clearance(p: Vector2, yaw: float, lot_pts: PackedVector2Array) -> bool:
	if not Geometry2D.is_point_in_polygon(p, lot_pts):
		return false
	var fwd := Vector2(sin(yaw), cos(yaw))
	var right := Vector2(fwd.y, -fwd.x)
	for sx: float in [-1.05, 1.05]:
		for sz: float in [-2.3, 2.3]:
			var corner: Vector2 = p + right * sx + fwd * sz
			if not Geometry2D.is_point_in_polygon(corner, lot_pts):
				return false
	return true


static func _is_safe_spot(
	p: Vector2,
	bounds: Rect2,
	roads: Array,
	buildings: Array,
	rails: Array,
	occupied_pts: Array[Vector2],
	is_lot: bool,
	own_road: Dictionary = {}
) -> bool:
	if not bounds.grow(-6.0).has_point(p):
		return false

	for occ in occupied_pts:
		if p.distance_squared_to(occ) < 11.5: # >= 3.39m spacing
			return false

	for rd: Dictionary in roads:
		if not is_lot and not own_road.is_empty() and rd == own_road:
			continue
		var rbox: Rect2 = rd["bbox"]
		var clearance: float = rd["half_w"] + (2.8 if is_lot else 3.5)
		if not rbox.grow(clearance).has_point(p):
			continue
		if _dist_to_polyline(p, rd["pts"]) < clearance:
			return false

	for b: Dictionary in buildings:
		var bbox: Rect2 = b["bbox"]
		if not bbox.grow(3.2).has_point(p):
			continue
		if Geometry2D.is_point_in_polygon(p, b["pts"]) or _dist_to_polyline(p, b["pts"]) < 3.0:
			return false

	for rl: Dictionary in rails:
		var rbox: Rect2 = rl["bbox"]
		if not rbox.grow(7.0).has_point(p):
			continue
		if _dist_to_polyline(p, rl["pts"]) < 7.0:
			return false

	return true


static func _create_vehicle_multimesh(
	kind: String,
	items: Array,
	tile_node: Node3D,
	terrain_grid: Dictionary,
	bounds: Rect2
) -> MultiMeshInstance3D:
	var mesh := _get_vehicle_mesh(kind)
	if mesh == null:
		return null

	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Parked_%s" % kind.capitalize()
	mmi.visibility_range_end = VISIBILITY_RANGE_END
	mmi.visibility_range_end_margin = VISIBILITY_RANGE_MARGIN
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = items.size()

	for i in range(items.size()):
		var item: Dictionary = items[i]
		var pos2: Vector2 = item["pos"]
		var y := _sample_ground_y(tile_node, pos2.x, pos2.y, terrain_grid, bounds)
		var basis := Basis(Vector3.UP, float(item["yaw"]))
		mm.set_instance_transform(i, Transform3D(basis, Vector3(pos2.x, y + WHEEL_GROUND_OFFSET, pos2.y)))
		mm.set_instance_color(i, item["color"])

	mmi.multimesh = mm
	return mmi


static func _get_vehicle_mesh(kind: String) -> Mesh:
	if _mesh_cache.has(kind):
		return _mesh_cache[kind]
	var path: String = VEHICLE_GLBS.get(kind, "")
	if path == "" or not ResourceLoader.exists(path):
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var root := packed.instantiate()
	var found := root.find_children("*", "MeshInstance3D", true, false)
	var mesh: Mesh = null
	if not found.is_empty():
		var src_mesh: Mesh = (found[0] as MeshInstance3D).mesh
		if src_mesh != null:
			mesh = src_mesh.duplicate()
			for s in range(mesh.get_surface_count()):
				var mat := mesh.surface_get_material(s)
				if mat != null and mat.resource_name == "mat_car_paint":
					mesh.surface_set_material(s, MAT_CAR_PAINT_INSTANCED)
	root.free()
	_mesh_cache[kind] = mesh
	return mesh


static func _pick_vehicle_kind(rng: RandomNumberGenerator) -> String:
	var r := rng.randf()
	if r < 0.45:
		return "sedan"
	elif r < 0.78:
		return "pickup"
	return "suv"


static func _dominant_edge_angle(pts: PackedVector2Array) -> float:
	var best_len := -1.0
	var best_angle := 0.0
	for i in range(pts.size()):
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		var d := a.distance_squared_to(b)
		if d > best_len:
			best_len = d
			best_angle = atan2(b.y - a.y, b.x - a.x)
	return best_angle


static func _dist_to_polyline(p: Vector2, pts: PackedVector2Array) -> float:
	var best := 1e9
	for i in range(pts.size() - 1):
		var closest := Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1])
		var d := p.distance_to(closest)
		if d < best:
			best = d
	return best


static func _parse_tile_bounds(tile_id: String, tile_meta: Dictionary) -> Rect2:
	if tile_meta.has("x") and tile_meta.has("z"):
		return Rect2(float(tile_meta["x"]), float(tile_meta["z"]), TILE_SIZE, TILE_SIZE)
	var parts := tile_id.split("_")
	if parts.size() == 2:
		var ix := parts[0].to_int()
		var iz := parts[1].to_int()
		return Rect2(float(ix) * TILE_SIZE, float(iz) * TILE_SIZE, TILE_SIZE, TILE_SIZE)
	return Rect2(0.0, 0.0, TILE_SIZE, TILE_SIZE)


static func _build_terrain_grid(tile_node: Node3D, bounds: Rect2) -> Dictionary:
	var cell_size := 25.0
	var cols := int(ceil(TILE_SIZE / cell_size)) + 1
	var grid := {}
	var tm := tile_node.get_node_or_null("TerrainMesh")
	if tm == null:
		return {"cell_size": cell_size, "cols": cols, "cells": grid, "default_y": 11.5}

	var mis := tm.find_children("*", "MeshInstance3D", true, false)
	if tm is MeshInstance3D:
		mis.push_front(tm)

	var sum_y := 0.0
	var cnt_y := 0
	for mi_node in mis:
		var mi := mi_node as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in range(mi.mesh.get_surface_count()):
			var arrays := mi.mesh.surface_get_arrays(s)
			if arrays.is_empty():
				continue
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for v in verts:
				var cx := clampi(int((v.x - bounds.position.x) / cell_size), 0, cols - 1)
				var cz := clampi(int((v.z - bounds.position.y) / cell_size), 0, cols - 1)
				var key := cz * cols + cx
				if not grid.has(key):
					grid[key] = [v.y, 1]
				else:
					grid[key][0] += v.y
					grid[key][1] += 1
				sum_y += v.y
				cnt_y += 1

	var default_y := (sum_y / float(cnt_y)) if cnt_y > 0 else 11.5
	return {"cell_size": cell_size, "cols": cols, "cells": grid, "default_y": default_y}


static func _sample_ground_y(tile_node: Node3D, x: float, z: float, terrain_grid: Dictionary, bounds: Rect2) -> float:
	if tile_node.is_inside_tree() and tile_node.get_world_3d() != null:
		var space := tile_node.get_world_3d().direct_space_state
		if space != null:
			var query := PhysicsRayQueryParameters3D.create(Vector3(x, 120.0, z), Vector3(x, -40.0, z))
			var hit := space.intersect_ray(query)
			if not hit.is_empty():
				return float((hit["position"] as Vector3).y)

	var cell_size: float = terrain_grid.get("cell_size", 25.0)
	var cols: int = terrain_grid.get("cols", 81)
	var cells: Dictionary = terrain_grid.get("cells", {})
	var cx := clampi(int((x - bounds.position.x) / cell_size), 0, cols - 1)
	var cz := clampi(int((z - bounds.position.y) / cell_size), 0, cols - 1)
	for r in range(0, 3):
		var total := 0.0
		var count := 0
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var key := (cz + dz) * cols + (cx + dx)
				if cells.has(key):
					total += float(cells[key][0])
					count += int(cells[key][1])
		if count > 0:
			return total / float(count)
	return float(terrain_grid.get("default_y", 11.5))


static func _ensure_osm_index() -> void:
	if _osm_loaded:
		return
	_osm_loaded = true
	var path := "res://source/osm_local.geojson.gz"
	if not FileAccess.file_exists(path):
		push_warning("VehiclesCommercialDetailer: missing " + path)
		return

	var raw := FileAccess.get_file_as_bytes(path)
	if raw.is_empty():
		return
	var decompressed := raw.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
	var parsed = JSON.parse_string(decompressed.get_string_from_utf8())
	if not (parsed is Dictionary):
		return

	var features: Array = (parsed as Dictionary).get("features", [])
	for f: Dictionary in features:
		var props: Dictionary = f.get("properties", {})
		var geom: Dictionary = f.get("geometry", {})
		var gtype := str(geom.get("type", ""))
		var amenity := str(props.get("amenity", ""))
		var kind := str(props.get("kind", ""))
		var railway := str(props.get("railway", ""))

		if amenity == "parking" and (gtype == "Polygon" or gtype == "MultiPolygon"):
			var ring: Array = geom["coordinates"][0] if gtype == "Polygon" else geom["coordinates"][0][0]
			var pts := _to_vec2_array(ring)
			if pts.size() >= 3:
				var area := _poly_area(pts)
				var bbox := _vec2_bbox(pts)
				var entry := {"pts": pts, "bbox": bbox, "area": area, "name": str(props.get("name", ""))}
				for tid in _tiles_for_bbox(bbox, 0.0):
					if not _tile_parking.has(tid):
						_tile_parking[tid] = []
					_tile_parking[tid].append(entry)

		elif kind == "road" and gtype == "LineString":
			if str(props.get("bridge", "")) == "yes" or str(props.get("tunnel", "")) == "yes":
				continue
			var pts := _to_vec2_array(geom["coordinates"])
			if pts.size() >= 2:
				var hw := str(props.get("highway", "residential"))
				var lanes := maxi(1, str(props.get("lanes", "2")).to_int())
				var half_w := maxf(3.2, float(lanes) * 1.85)
				var bbox := _vec2_bbox(pts)
				var entry := {"pts": pts, "bbox": bbox, "half_w": half_w, "highway": hw}
				for tid in _tiles_for_bbox(bbox, 16.0):
					if not _tile_roads.has(tid):
						_tile_roads[tid] = []
					_tile_roads[tid].append(entry)

		elif kind == "building" and (gtype == "Polygon" or gtype == "MultiPolygon"):
			var ring: Array = geom["coordinates"][0] if gtype == "Polygon" else geom["coordinates"][0][0]
			var pts := _to_vec2_array(ring)
			if pts.size() >= 3:
				var bbox := _vec2_bbox(pts)
				var entry := {"pts": pts, "bbox": bbox}
				for tid in _tiles_for_bbox(bbox, 8.0):
					if not _tile_buildings.has(tid):
						_tile_buildings[tid] = []
					_tile_buildings[tid].append(entry)

		elif railway == "rail" and gtype == "LineString":
			var pts := _to_vec2_array(geom["coordinates"])
			if pts.size() >= 2:
				var bbox := _vec2_bbox(pts)
				var entry := {"pts": pts, "bbox": bbox}
				for tid in _tiles_for_bbox(bbox, 12.0):
					if not _tile_rails.has(tid):
						_tile_rails[tid] = []
					_tile_rails[tid].append(entry)


static func clear_cache() -> void:
	_mesh_cache.clear()
	_osm_loaded = false
	_tile_parking.clear()
	_tile_roads.clear()
	_tile_buildings.clear()
	_tile_rails.clear()


static func _to_vec2_array(coords: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(coords.size())
	for i in range(coords.size()):
		var c: Array = coords[i]
		out[i] = Vector2(float(c[0]), float(c[1]))
	return out


static func _vec2_bbox(pts: PackedVector2Array) -> Rect2:
	var minx := 1e9
	var miny := 1e9
	var maxx := -1e9
	var maxy := -1e9
	for p in pts:
		minx = minf(minx, p.x)
		miny = minf(miny, p.y)
		maxx = maxf(maxx, p.x)
		maxy = maxf(maxy, p.y)
	return Rect2(minx, miny, maxx - minx, maxy - miny)


static func _poly_area(pts: PackedVector2Array) -> float:
	var sum := 0.0
	for i in range(pts.size()):
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		sum += a.x * b.y - b.x * a.y
	return absf(sum) * 0.5


static func _tiles_for_bbox(bbox: Rect2, margin: float) -> Array[String]:
	var x0 := floori((bbox.position.x - margin) / TILE_SIZE)
	var x1 := floori((bbox.position.x + bbox.size.x + margin) / TILE_SIZE)
	var z0 := floori((bbox.position.y - margin) / TILE_SIZE)
	var z1 := floori((bbox.position.y + bbox.size.y + margin) / TILE_SIZE)
	var out: Array[String] = []
	for ix in range(x0, x1 + 1):
		for iz in range(z0, z1 + 1):
			out.append("%s_%s" % [("%+03d" % ix), ("%+03d" % iz)])
	return out
