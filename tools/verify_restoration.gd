extends SceneTree
## Phase 1 & Phase 2 Visual Restoration Verification for Harlingen.
## Run with:
##   godot --headless --path <project> -s res://tools/verify_restoration.gd
##   godot --headless --path <project> -s res://tools/verify_restoration.gd -- --mesh-ground

var _failures: Array[String] = []
var _world: Node3D = null
var _tri_cache: Dictionary = {} # instance_id -> Array of { "xform": Transform3D, "inv": Transform3D, "tri": TriangleMesh }


func _initialize() -> void:
	call_deferred("_run_all")


func _run_all() -> void:
	var scene := load("res://preview/Harlingen.tscn") as PackedScene
	if not _check(scene != null, "Load Harlingen.tscn"):
		_finish()
		return

	_world = scene.instantiate()
	root.add_child(_world)
	await _frames(20)

	var mode_name := "Terrain3D" if _world.native_terrain else "GLB"
	print("=== VERIFY_RESTORATION START mode=", mode_name, " display=", DisplayServer.get_name(), " ===")

	# Switch to flyover so we can stream arbitrary districts & probe collision cleanly
	_world._set_walking(false, "VerifyRestoration")
	await _frames(5)

	await _verify_district_streaming_and_signage()
	await _verify_jackson_corridor()
	await _verify_ed_carey_corridor()
	await _verify_vehicle_corridor_checkpoints()
	await _measure_performance_diagnostics()

	_finish()


func _finish() -> void:
	var mode_name := "Terrain3D" if (_world and _world.native_terrain) else "GLB"
	if _failures.is_empty():
		print("VERIFY_RESTORATION_PASS mode=", mode_name)
		quit(0)
	else:
		for f in _failures:
			push_error("RESTORATION_FAIL: " + f)
		print("VERIFY_RESTORATION_FAIL mode=", mode_name, " count=", _failures.size())
		quit(1)


func _check(cond: bool, label: String) -> bool:
	if not cond:
		_failures.append(label)
		print("[FAIL] ", label)
	else:
		print("[PASS] ", label)
	return cond


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame


func _stream_at(pos: Vector3, wait_frames := 4) -> void:
	_world.camera.position = Vector3(pos.x, 60.0, pos.z)
	_world._bind_terrain_camera(_world.camera)
	_world._update_tiles(false)
	await _frames(wait_frames)


func _get_layer_tris(tile: Node3D, layer_name: String) -> Array:
	if tile == null:
		return []
	var layer := tile.get_node_or_null(layer_name)
	if layer == null:
		return []
	var key := "%d:%s" % [tile.get_instance_id(), layer_name]
	if _tri_cache.has(key):
		return _tri_cache[key]
	var list: Array = []
	var meshes: Array = layer.find_children("*", "MeshInstance3D", true, false)
	if layer is MeshInstance3D:
		meshes.push_front(layer)
	for node in meshes:
		var mi := node as MeshInstance3D
		if mi and mi.mesh and mi.mesh.get_surface_count() > 0:
			var tmesh := mi.mesh.generate_triangle_mesh()
			if tmesh:
				var xf := mi.global_transform
				list.append({
					"xform": xf,
					"inv": xf.affine_inverse(),
					"tri": tmesh,
					"name": mi.name,
				})
	_tri_cache[key] = list
	return list


func _ray_layer_all(tile: Node3D, layer_name: String, wx: float, wz: float, y_top := 120.0, y_bot := -20.0) -> Array[float]:
	var entries := _get_layer_tris(tile, layer_name)
	var hits: Array[float] = []
	var w_from := Vector3(wx, y_top, wz)
	var w_to := Vector3(wx, y_bot, wz)
	for entry in entries:
		var inv: Transform3D = entry["inv"]
		var xf: Transform3D = entry["xform"]
		var tmesh: TriangleMesh = entry["tri"]
		var cur_from := w_from
		for _step in 8:
			var l_from := inv * cur_from
			var l_to := inv * w_to
			var res := tmesh.intersect_segment(l_from, l_to)
			if res.is_empty():
				break
			var w_hit: Vector3 = xf * (res["position"] as Vector3)
			hits.append(w_hit.y)
			cur_from = Vector3(wx, w_hit.y - 0.03, wz)
			if cur_from.y <= y_bot:
				break
	hits.sort()
	hits.reverse()
	return hits


func _ray_layer_highest(tile: Node3D, layer_name: String, wx: float, wz: float, y_top := 120.0, y_bot := -20.0) -> float:
	var hits := _ray_layer_all(tile, layer_name, wx, wz, y_top, y_bot)
	return hits[0] if not hits.is_empty() else NAN


func _physics_ray_all(wx: float, wz: float, mask := 1, y_top := 120.0, y_bot := -20.0) -> Array[Dictionary]:
	var space := root.world_3d.direct_space_state
	var exclude: Array[RID] = [_world.player.get_rid(), _world.vehicle.get_rid(), _world.walker.get_rid()]
	var hits: Array[Dictionary] = []
	var cur_y := y_top
	for _step in 10:
		var q := PhysicsRayQueryParameters3D.create(Vector3(wx, cur_y, wz), Vector3(wx, y_bot, wz), mask, exclude)
		var res := space.intersect_ray(q)
		if res.is_empty():
			break
		hits.append(res)
		var hit_y: float = (res["position"] as Vector3).y
		cur_y = hit_y - 0.04
		if cur_y <= y_bot:
			break
	return hits


func _tile_for_xz(wx: float, wz: float) -> Node3D:
	var cx := clampf(wx, -5999.99, 5999.99)
	var cz := clampf(wz, -5999.99, 5999.99)
	var tx := int(floor(cx / 2000.0))
	var tz := int(floor(cz / 2000.0))
	var sx := ("+%02d" % tx) if tx >= 0 else ("-%02d" % abs(tx))
	var sz := ("+%02d" % tz) if tz >= 0 else ("-%02d" % abs(tz))
	var tid := "%s_%s" % [sx, sz]
	return _world.loaded.get(tid, null)


func _verify_district_streaming_and_signage() -> void:
	var targets := [
		{"id": "+00_+00", "pos": Vector3(500, 60, 315), "streetscape": "DowntownStreetscape"},
		{"id": "+01_+00", "pos": Vector3(3300, 60, 1000), "streetscape": "EdCareyStreetscape_01_00"},
		{"id": "+01_+01", "pos": Vector3(2500, 60, 2600), "streetscape": "EdCareyStreetscape_01_01"},
		{"id": "+00_+01", "pos": Vector3(1750, 60, 3850), "streetscape": "EdCareyStreetscape_00_01"},
		{"id": "+00_+02", "pos": Vector3(1200, 60, 5000), "streetscape": "EdCareyStreetscape_00_02"},
	]
	for t in targets:
		await _stream_at(t["pos"], 4)
		var tile: Node3D = _world.loaded.get(t["id"], null)
		if not _check(tile != null, "District streamed: " + t["id"]):
			continue
		var col_body := tile.get_node_or_null("DistrictCollision")
		_check(col_body != null, t["id"] + " DistrictCollision active when near")

		var s_name: String = t["streetscape"]
		var s_node := tile.get_node_or_null(s_name)
		if not _check(s_node != null, t["id"] + " has streetscape node " + s_name):
			continue
		var meshes := s_node.find_children("*", "MeshInstance3D", true, false)
		if s_node is MeshInstance3D:
			meshes.push_front(s_node)
		var quad_count := 0
		var tex_ok := 0
		var tex_bad := 0
		for node in meshes:
			var mi := node as MeshInstance3D
			if mi == null or mi.mesh == null:
				tex_bad += 1
				continue
			var is_quad := mi.mesh is QuadMesh
			if is_quad:
				quad_count += 1
			for s in mi.mesh.get_surface_count():
				var mat := mi.get_active_material(s)
				if mat == null:
					mat = mi.mesh.surface_get_material(s)
				if mat is StandardMaterial3D:
					var sm := mat as StandardMaterial3D
					var needs_tex := is_quad or sm.emission_enabled or sm.albedo_texture != null
					if needs_tex:
						if sm.albedo_texture != null and sm.albedo_texture.get_width() > 0 and sm.albedo_texture.get_height() > 0:
							tex_ok += 1
						else:
							tex_bad += 1
						if sm.emission_enabled:
							if sm.emission_texture == null or sm.emission_texture.get_width() <= 0:
								tex_bad += 1
		print("STREETSCAPE ", t["id"], " node=", s_name, " meshes=", meshes.size(), " quads=", quad_count, " tex_ok=", tex_ok, " tex_bad=", tex_bad)
		_check(meshes.size() > 0 and quad_count > 0 and tex_ok > 0 and tex_bad == 0,
			t["id"] + " " + s_name + " all textures valid (quads=" + str(quad_count) + ", ok=" + str(tex_ok) + ", bad=" + str(tex_bad) + ")")

		if t["id"] == "+00_+02":
			var sw := tile.get_node_or_null("Sidewalks")
			var se := tile.get_node_or_null("StreetEdges")
			var sw_tris := _get_layer_tris(tile, "Sidewalks")
			var se_tris := _get_layer_tris(tile, "StreetEdges")
			print("TILE_+00_+02 Sidewalks=", sw != null, " meshes=", sw_tris.size(), " StreetEdges=", se != null, " meshes=", se_tris.size())
			_check(sw != null and sw_tris.size() > 0, "+00_+02 Sidewalks node & mesh loaded")
			_check(se != null and se_tris.size() > 0, "+00_+02 StreetEdges node & mesh loaded")


func _jackson_center_z(x: float) -> float:
	if x <= 333.04:
		var t := (x - (-324.19)) / (333.04 - (-324.19))
		return lerpf(322.55, 313.35, t)
	elif x <= 442.53:
		var t := (x - 333.04) / (442.53 - 333.04)
		return lerpf(313.35, 312.38, t)
	elif x <= 551.60:
		var t := (x - 442.53) / (551.60 - 442.53)
		return lerpf(312.38, 310.86, t)
	elif x <= 773.16:
		var t := (x - 551.60) / (773.16 - 551.60)
		return lerpf(310.86, 308.71, t)
	elif x <= 880.46:
		var t := (x - 773.16) / (880.46 - 773.16)
		return lerpf(308.71, 307.06, t)
	else:
		var t := (x - 880.46) / (1651.10 - 880.46)
		return lerpf(307.06, 297.82, t)


func _verify_jackson_corridor() -> void:
	await _stream_at(Vector3(150, 60, 315), 5)
	var tile: Node3D = _world.loaded.get("+00_+00", null)
	if not _check(tile != null, "Downtown +00_+00 loaded for Jackson check"):
		return

	var xs: Array[float] = []
	for x in range(40, 901, 20):
		xs.append(float(x))
	xs.append(81.8)
	xs.sort()

	var road_hits := 0
	var road_clips_tm := 0
	var road_clips_col := 0
	var min_road_tm := 999.0
	var min_road_col := 999.0
	var rail_ok := false

	for i in xs.size():
		var x: float = xs[i]
		if absf(x - _world.camera.position.x) > 250.0:
			await _stream_at(Vector3(x, 60, 315), 3)
			tile = _world.loaded.get("+00_+00", null)
		var zc := _jackson_center_z(x)
		var ry := _ray_layer_highest(tile, "Roads", x, zc)
		if is_nan(ry):
			for dz in [-1.5, 1.5, -2.5, 2.5]:
				ry = _ray_layer_highest(tile, "Roads", x, zc + dz)
				if not is_nan(ry):
					break
		var tmy := _ray_layer_highest(tile, "TerrainMesh", x, zc)
		var phits := _physics_ray_all(x, zc, 1)
		var col_y := (phits[0]["position"] as Vector3).y if not phits.is_empty() else NAN
		if not is_nan(ry):
			road_hits += 1
			if not is_nan(tmy):
				var dtm := ry - tmy
				min_road_tm = minf(min_road_tm, dtm)
				if dtm <= 0.0:
					road_clips_tm += 1
			if not is_nan(col_y):
				var dcol := ry - col_y
				min_road_col = minf(min_road_col, dcol)
				if dcol < -0.02:
					road_clips_col += 1
		if absf(x - 81.8) < 0.1:
			rail_ok = (not is_nan(ry)) and (not is_nan(tmy)) and (ry > tmy) and (not is_nan(col_y)) and (ry >= col_y - 0.02)
			print("JACKSON_UP_RAIL (81.8, ", zc, ") road_y=", ry, " tm_y=", tmy, " col_y=", col_y)

	print("JACKSON_ROADS samples=", xs.size(), " hits=", road_hits,
		" clips_tm=", road_clips_tm, " min_road_minus_tm=", min_road_tm,
		" clips_col=", road_clips_col, " min_road_minus_col=", min_road_col)
	_check(road_hits == xs.size(), "Jackson road surface hits at all %d samples" % xs.size())
	_check(road_clips_tm == 0, "Jackson road 0 clips below TerrainMesh (min diff=" + str(min_road_tm) + ")")
	_check(road_clips_col == 0, "Jackson road 0 clips below physics ground (min diff=" + str(min_road_col) + ")")
	_check(rail_ok, "Jackson UP Rail crossing (X=81.8) road & ground collision clean")

	# Continuous bridged sidewalks check (X=145..875): every N/S edge point must be either
	# a restored Sidewalks slab (mid-block) or a paved Roads cross-street/alley/driveway apron (0 bare trench gaps).
	var sw_total_checks := 0
	var sw_slab_hits := 0
	var sw_road_apron_hits := 0
	var sw_bare_gaps := 0
	var sw_clips_tm := 0
	var min_sw_tm := 999.0
	for x in range(145, 876, 10):
		var fx := float(x)
		if absf(fx - _world.camera.position.x) > 250.0:
			await _stream_at(Vector3(fx, 60, 315), 2)
			tile = _world.loaded.get("+00_+00", null)
		var zc := _jackson_center_z(fx)
		for side_sgn: float in [-1.0, 1.0]:
			sw_total_checks += 1
			var sw_hit := NAN
			for off in [5.5, 5.0, 6.0, 6.5, 7.0, 4.6, 7.5]:
				sw_hit = _ray_layer_highest(tile, "Sidewalks", fx, zc + side_sgn * off)
				if not is_nan(sw_hit):
					var tms := _ray_layer_highest(tile, "TerrainMesh", fx, zc + side_sgn * off)
					if not is_nan(tms):
						min_sw_tm = minf(min_sw_tm, sw_hit - tms)
						if sw_hit <= tms:
							sw_clips_tm += 1
					break
			if not is_nan(sw_hit):
				sw_slab_hits += 1
			else:
				var road_apron := _ray_layer_highest(tile, "Roads", fx, zc + side_sgn * 8.0)
				if is_nan(road_apron):
					road_apron = _ray_layer_highest(tile, "Roads", fx, zc + side_sgn * 6.0)
				if not is_nan(road_apron):
					sw_road_apron_hits += 1
				else:
					sw_bare_gaps += 1
					print("[GAP] Jackson bare edge at x=", fx, " side=", ("N" if side_sgn < 0 else "S"))

	print("JACKSON_SIDEWALKS edge_checks=", sw_total_checks, " sidewalk_slabs=", sw_slab_hits,
		" cross_road_aprons=", sw_road_apron_hits, " bare_gaps=", sw_bare_gaps,
		" clips_tm=", sw_clips_tm, " min_sw_minus_tm=", min_sw_tm)
	_check(sw_slab_hits >= 100 and sw_bare_gaps == 0,
		"Jackson continuous bridged sidewalks & paved crossings with 0 bare gaps (slabs=%d, aprons=%d, gaps=%d)" % [sw_slab_hits, sw_road_apron_hits, sw_bare_gaps])
	_check(sw_clips_tm == 0, "Jackson sidewalks 0 clips below TerrainMesh (min diff=" + str(min_sw_tm) + ")")


func _verify_ed_carey_corridor() -> void:
	var waypoints := [
		{"name": "Start_+01_+00", "pos": Vector2(3586.9, 500.4)},
		{"name": "Arroyo_Bridge", "pos": Vector2(3250.0, 1278.0)},
		{"name": "Border_01_00_01_01", "pos": Vector2(2833.0, 2000.0)},
		{"name": "Valley_Baptist", "pos": Vector2(2686.0, 2243.0)},
		{"name": "QuickQuack_UPRail", "pos": Vector2(2410.0, 2730.0)},
		{"name": "Border_01_01_00_01", "pos": Vector2(2000.0, 3433.0)},
		{"name": "I69E_Overpass", "pos": Vector2(1745.0, 3875.0)},
		{"name": "Border_00_01_00_02", "pos": Vector2(1677.0, 4000.0)},
		{"name": "HomeDepot_Lamb", "pos": Vector2(1430.0, 4420.0)},
		{"name": "Cottonwood_Creek", "pos": Vector2(1152.0, 5140.0)},
		{"name": "South_End", "pos": Vector2(518.9, 6000.0)},
	]

	var samples: Array[Dictionary] = []
	for i in waypoints.size() - 1:
		var a: Vector2 = waypoints[i]["pos"]
		var b: Vector2 = waypoints[i + 1]["pos"]
		var seg_len := a.distance_to(b)
		var steps := maxi(1, int(ceil(seg_len / 100.0)))
		var dir := (b - a).normalized()
		var perp := Vector2(-dir.y, dir.x)
		for s in steps:
			var t := float(s) / float(steps)
			var p := a.lerp(b, t)
			samples.append({
				"label": waypoints[i]["name"] if s == 0 else ("seg_%d_%d" % [i, s]),
				"pos": p,
				"perp": perp,
				"is_waypoint": s == 0,
			})
	var last_wp: Dictionary = waypoints[waypoints.size() - 1]
	samples.append({
		"label": last_wp["name"],
		"pos": last_wp["pos"],
		"perp": (waypoints[waypoints.size() - 1]["pos"] - waypoints[waypoints.size() - 2]["pos"]).normalized().orthogonal(),
		"is_waypoint": true,
	})

	var total_samples := samples.size()
	var road_or_bridge_hits := 0
	var ground_col_hits := 0
	var terrain_clips := 0
	var blocking_obstacles := 0
	var min_road_tm := 999.0
	var i69e_clearance := -1.0
	var i69e_bridge_y := NAN
	var i69e_road_y := NAN

	for smp in samples:
		var p: Vector2 = smp["pos"]
		var perp: Vector2 = smp["perp"]
		var label: String = smp["label"]
		if Vector2(p.x - _world.camera.position.x, p.y - _world.camera.position.z).length() > 220.0:
			await _stream_at(Vector3(p.x, 60.0, p.y), 3)

		var tile := _tile_for_xz(p.x, p.y)
		if tile == null:
			await _stream_at(Vector3(p.x, 60.0, p.y), 4)
			tile = _tile_for_xz(p.x, p.y)
		if tile == null:
			_check(false, "Tile missing at Ed Carey sample " + label + " " + str(p))
			continue

		# Search Roads, then ElevatedRoads (Arroyo bridge), then Bridges; laterally up to +-120m along gentle curves
		var hit_xz := p
		var surf_y := NAN
		var is_bridge_surface := false
		for cand_dist in range(0, 49):
			var offsets: Array = [0.0] if cand_dist == 0 else [float(cand_dist) * 2.5, -float(cand_dist) * 2.5]
			for off_val: float in offsets:
				var cand: Vector2 = p + perp * off_val
				var cand_tile := _tile_for_xz(cand.x, cand.y)
				if cand_tile == null:
					continue
				var ry := _ray_layer_highest(cand_tile, "Roads", cand.x, cand.y)
				if not is_nan(ry):
					surf_y = ry
					hit_xz = cand
					tile = cand_tile
					break
				var ery := _ray_layer_highest(cand_tile, "ElevatedRoads", cand.x, cand.y)
				if not is_nan(ery):
					surf_y = ery
					hit_xz = cand
					tile = cand_tile
					is_bridge_surface = true
					break
			if not is_nan(surf_y):
				break

		if not is_nan(surf_y):
			road_or_bridge_hits += 1
		else:
			print("[MISS] No road/bridge hit near ", label, " ", p)

		var tmy := _ray_layer_highest(tile, "TerrainMesh", hit_xz.x, hit_xz.y)
		var phits := _physics_ray_all(hit_xz.x, hit_xz.y, 1)
		if not phits.is_empty():
			ground_col_hits += 1
		var lowest_col_y := (phits[phits.size() - 1]["position"] as Vector3).y if not phits.is_empty() else NAN

		if not is_nan(surf_y) and not is_nan(tmy) and not is_bridge_surface:
			var diff := surf_y - tmy
			min_road_tm = minf(min_road_tm, diff)
			if diff <= 0.0:
				terrain_clips += 1
				print("[CLIP] Ed Carey ", label, " at ", hit_xz, " road_y=", surf_y, " tm_y=", tmy)

		# Check for low blocking obstacles on roadway (1.0m to 4.2m above road surface)
		if not is_nan(surf_y):
			var space := root.world_3d.direct_space_state
			var exclude: Array[RID] = [_world.player.get_rid(), _world.vehicle.get_rid(), _world.walker.get_rid()]
			var obs_q := PhysicsRayQueryParameters3D.create(
				Vector3(hit_xz.x, surf_y + 4.2, hit_xz.y),
				Vector3(hit_xz.x, surf_y + 0.55, hit_xz.y),
				1, exclude)
			var obs := space.intersect_ray(obs_q)
			if not obs.is_empty():
				blocking_obstacles += 1
				print("[OBSTACLE] ", label, " hit at ", obs["position"], " collider=", obs["collider"])

		# Special check at I-69E Overpass (1745, 3875): probe both parallel highway decks (Z=3865 NB/WB & Z=3890 SB/EB)
		if label == "I69E_Overpass":
			var span_clearances: Array[float] = []
			for span_z in [3865.0, 3890.0]:
				var s_road := _ray_layer_highest(tile, "Roads", 1745.0, span_z)
				var s_phits := _physics_ray_all(1745.0, span_z, 1)
				var s_bridge_col := NAN
				for h in s_phits:
					var hy: float = (h["position"] as Vector3).y
					if hy > s_road + 3.0:
						s_bridge_col = hy
						break
				var s_bridges := _ray_layer_all(tile, "Bridges", 1745.0, span_z)
				if not is_nan(s_bridge_col) and not is_nan(s_road):
					span_clearances.append(s_bridge_col - s_road)
				print("I69E_SPAN (1745, ", span_z, ") road_y=", s_road, " bridge_col_y=", s_bridge_col,
					" bridges_mesh_ys=", s_bridges, " clearance=", (s_bridge_col - s_road if not is_nan(s_bridge_col) else -1.0))
			if span_clearances.size() == 2:
				i69e_road_y = surf_y
				i69e_bridge_y = surf_y + minf(span_clearances[0], span_clearances[1])
				i69e_clearance = minf(span_clearances[0], span_clearances[1])

		if smp["is_waypoint"]:
			print("ED_CAREY_WP ", label, " xz=", hit_xz, " surf_y=", surf_y, " tm_y=", tmy, " phys_hits=", phits.size())

	print("ED_CAREY_CORRIDOR samples=", total_samples, " road_hits=", road_or_bridge_hits,
		" ground_col_hits=", ground_col_hits, " terrain_clips=", terrain_clips,
		" min_road_minus_tm=", min_road_tm, " blocking_obstacles=", blocking_obstacles)
	_check(road_or_bridge_hits == total_samples, "Ed Carey continuous road/bridge surface (%d/%d samples)" % [road_or_bridge_hits, total_samples])
	_check(ground_col_hits == total_samples, "Ed Carey continuous physics collision (%d/%d samples)" % [ground_col_hits, total_samples])
	_check(terrain_clips == 0, "Ed Carey 0 road clips below TerrainMesh (min diff=" + str(min_road_tm) + ")")
	_check(blocking_obstacles == 0, "Ed Carey 0 blocking obstacles on roadway")
	_check(i69e_clearance >= 5.5, "I-69E overpass clearance >= 5.5m (road=" + str(i69e_road_y) + ", bridge_col=" + str(i69e_bridge_y) + ", clearance=" + str(i69e_clearance) + ")")


func _verify_vehicle_corridor_checkpoints() -> void:
	# Stream Downtown +00_+00 first so ground collision is active before entering gameplay
	await _stream_at(Vector3(215, 60, 318), 8)
	var car: VehicleBody3D = _world.vehicle
	var player: CharacterBody3D = _world.player
	var vi = _world.vehicle_interaction
	car.respawn()
	player.respawn()
	_world._set_walking(true)
	await _frames(25)

	# Enter vehicle
	player.global_position = car.global_position + Vector3(-1.8, 0.05, 0.0)
	await _frames(8)
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_E
	ev.pressed = true
	Input.parse_input_event(ev)
	Input.flush_buffered_events()
	await _frames(5)
	ev.pressed = false
	Input.parse_input_event(ev)
	Input.flush_buffered_events()
	await _frames(25)
	_check(vi.is_driving, "Entered HarlingenVehicle for Ed Carey checkpoint driving test")

	# Test driving through BOTH I-69E spans (Z=3865 & Z=3890) heading SW toward (1677, 4000)
	var start_xz := Vector2(1768.0, 3835.0)
	var target_xz := Vector2(1715.0, 3927.0)
	var dir_2d := (target_xz - start_xz).normalized()
	var yaw := atan2(-dir_2d.x, -dir_2d.y)
	var basis := Basis(Vector3.UP, yaw)

	# Move car near start_xz so active chase_camera streams +00_+01 & Terrain3D collision
	car.global_transform = Transform3D(basis, Vector3(start_xz.x, 14.0, start_xz.y))
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	_world._bind_terrain_camera(car.chase_camera)
	_world._update_tiles(false)
	await _frames(10)

	var phits := _physics_ray_all(start_xz.x, start_xz.y, 1)
	var gy := (phits[phits.size() - 1]["position"] as Vector3).y if not phits.is_empty() else 13.0
	car.global_transform = Transform3D(basis, Vector3(start_xz.x, gy + 0.35, start_xz.y))
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	await _frames(20)
	var contacts_before := [car.wheel_fl.is_in_contact(), car.wheel_fr.is_in_contact(), car.wheel_rl.is_in_contact(), car.wheel_rr.is_in_contact()]

	var w := InputEventKey.new()
	w.physical_keycode = KEY_W
	w.pressed = true
	Input.parse_input_event(w)
	Input.flush_buffered_events()
	await _frames(210) # ~3.5s drive completely through both I-69E overpass spans!
	w.pressed = false
	Input.parse_input_event(w)
	Input.flush_buffered_events()
	await _frames(5)

	var end_xz := Vector2(car.global_position.x, car.global_position.z)
	var traveled := end_xz.distance_to(start_xz)
	var speed := car.linear_velocity.length()
	print("I69E_DRIVE start=", start_xz, " end=", end_xz, " traveled=", traveled, "m speed=", speed, "m/s wheels=", contacts_before, " up_y=", car.global_basis.y.y)
	_check(contacts_before[0] and contacts_before[1] and contacts_before[2] and contacts_before[3],
		"Vehicle 4 wheels grounded before I-69E underpass")
	_check(traveled > 18.0 and car.global_basis.y.y > 0.98,
		"Vehicle drives unobstructed under I-69E overpass (traveled=" + str(traveled) + " m)")

	# Return to flyover and restore spawn
	if vi.is_driving:
		car.linear_velocity = Vector3.ZERO
		vi.try_exit_vehicle()
		await _frames(25)
	car.respawn()
	player.respawn()
	_world._set_walking(false, "VerifyRestoration")
	await _frames(5)


func _measure_performance_diagnostics() -> void:
	var views := [
		{"name": "Downtown_Jackson", "pos": Vector3(424, 75, 493), "look": Vector3(220, 19, 341)},
		{"name": "EdCarey_ValleyBaptist", "pos": Vector3(2760, 55, 2180), "look": Vector3(2686, 15, 2243)},
		{"name": "EdCarey_I69E", "pos": Vector3(1830, 55, 3810), "look": Vector3(1745, 15, 3875)},
	]
	for v in views:
		_world.camera.position = v["pos"]
		_world.camera.look_at(v["look"])
		_world._bind_terrain_camera(_world.camera)
		_world._update_tiles(false)
		await _frames(10)

		var t0 := Time.get_ticks_usec()
		for _f in 30:
			await process_frame
		var mean_ms := (Time.get_ticks_usec() - t0) / 30000.0
		var draw_calls := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		var prims := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
		var objs := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
		var vis_meshes := 0
		for tile: Node3D in _world.loaded.values():
			for mi in tile.find_children("*", "MeshInstance3D", true, false):
				if (mi as MeshInstance3D).is_visible_in_tree():
					vis_meshes += 1
		print("PERF ", v["name"], " loaded_tiles=", _world.loaded.size(), " visible_meshes=", vis_meshes,
			" mean_frame_ms=", mean_ms, " draw_calls=", draw_calls, " primitives=", prims, " objects=", objs,
			" note=", ("headless_dummy_renderer" if DisplayServer.get_name() == "headless" else "gpu_renderer"))
