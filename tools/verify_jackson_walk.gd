extends SceneTree
## Phase 4 (Assignment 004C): Continuous walking verification on Jackson Street
## using preview/Harlingen.tscn + PlayerCharacter (PlayerController).

const EXPECTED_WALK_STEP := 3.8 / 60.0
const STALL_THRESHOLD := 0.025
const MAX_STALL_FRAMES := 8

var _world: Node3D
var _player: CharacterBody3D

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	print("=== VERIFY_JACKSON_WALK START ===")
	if not await _load_world():
		quit(1)
		return

	# Run full walking suite (initial load)
	if not await _run_suite("INITIAL"):
		quit(1)
		return

	# 8a. Unload and reload District_p00_p00 via world.gd streaming, then repeat
	print("--- STREAM_RELOAD District_p00_p00 ---")
	if _world.loaded.has("+00_+00"):
		var tile: Node3D = _world.loaded["+00_+00"]
		_world.loaded.erase("+00_+00")
		tile.get_parent().remove_child(tile)
		tile.free()
	_player.respawn()
	await _frames(4)
	_world._update_tiles(false)
	await _frames(32)
	if not _require(_world.loaded.has("+00_+00"), "District_p00_p00 (+00_+00) reloaded via streaming"):
		return
	if not await _run_suite("STREAM_RELOAD"):
		quit(1)
		return

	# 8b. Reload entire Harlingen.tscn scene and repeat
	print("--- SCENE_RELOAD Harlingen.tscn ---")
	_world.get_parent().remove_child(_world)
	_world.free()
	_world = null
	_player = null
	await _frames(4)
	if not await _load_world():
		quit(1)
		return
	if not await _run_suite("SCENE_RELOAD"):
		quit(1)
		return

	print("VERIFY_JACKSON_WALK_PASS all checks passed (initial, stream_reload, scene_reload)")
	quit()

func _load_world() -> bool:
	_world = (load("res://preview/Harlingen.tscn") as PackedScene).instantiate()
	root.add_child(_world)
	_player = _world.player
	await _frames(32)
	if not _require(_world.walking and not _world.legacy_walker_mode, "Gameplay walking mode active"):
		return false
	if not _require(_player.is_on_floor(), "Player starts grounded on Jackson Street"):
		return false
	var sp := _player.global_position
	print("SPAWN: pos=", sp, " on_floor=", _player.is_on_floor())
	return _require(absf(sp.x - 205.0) < 0.1 and absf(sp.z - 320.0) < 0.1 and sp.y > 11.8 and sp.y < 12.5,
		"Spawn on Jackson Street (~205, 12.02, 320), got %s" % str(sp))

func _run_suite(phase_tag: String) -> bool:
	# 1. Spawn on Jackson Street
	_player.respawn()
	await _frames(20)
	if not _require(_player.is_on_floor(), "%s: Player grounded at spawn" % phase_tag):
		return false

	# 2. Step onto center of Jackson St roadway (z~315.8, clear of south-curb props at z~318 and walking west away from HarlingenVehicle at x=223)
	if not await _walk_segment(phase_tag + "_STEP_TO_ROAD", [KEY_S], 65, false):
		return false
	var road_z := _player.global_position.z
	if not _require(road_z > 314.5 and road_z < 317.2, "%s: Stepped onto Jackson St roadway (z=%.2f)" % [phase_tag, road_z]):
		return false

	# 3. Walk continuously >= 100m west (-X) along Jackson St roadway (1650 frames @ 3.8 m/s = 104.5 m)
	var west_start := _player.global_position
	if not await _walk_segment(phase_tag + "_WEST_100M", [KEY_D], 1650, false):
		return false
	var west_dist := Vector2(_player.global_position.x - west_start.x, _player.global_position.z - west_start.z).length()
	print("  %s_WEST_100M dist=%.2fm end=%s" % [phase_tag, west_dist, str(_player.global_position)])
	if not _require(west_dist >= 100.0, "%s: Walked >= 100m along Jackson St (got %.2fm)" % [phase_tag, west_dist]):
		return false

	# 4. Walk backward (+X) along the same route (1650 frames = ~104.5 m)
	var east_start := _player.global_position
	if not await _walk_segment(phase_tag + "_EAST_100M", [KEY_A], 1650, false):
		return false
	var east_dist := Vector2(_player.global_position.x - east_start.x, _player.global_position.z - east_start.z).length()
	print("  %s_EAST_100M dist=%.2fm end=%s" % [phase_tag, east_dist, str(_player.global_position)])
	if not _require(east_dist >= 100.0, "%s: Walked backward >= 100m along Jackson St (got %.2fm)" % [phase_tag, east_dist]):
		return false

	# 5. Walk diagonally across the roadway (W+A then S+D)
	if not await _walk_segment(phase_tag + "_DIAG_WA", [KEY_W, KEY_A], 40, false):
		return false
	if not await _walk_segment(phase_tag + "_DIAG_SD", [KEY_S, KEY_D], 40, false):
		return false

	# 6. Walk from the road onto legitimate sidewalk (+Z back to z~320)
	if not await _walk_segment(phase_tag + "_ROAD_TO_SIDEWALK", [KEY_W], 65, false):
		return false
	if not _require(_player.is_on_floor(), "%s: Grounded after stepping onto sidewalk" % phase_tag):
		return false

	# 7. Jump and resume normal walking
	if not await _walk_segment(phase_tag + "_JUMP_AND_WALK", [KEY_S], 90, true):
		return false
	if not _require(_player.is_on_floor(), "%s: Landed and resumed walking after jump" % phase_tag):
		return false

	return true

func _walk_segment(label: String, keys: Array, frames: int, do_jump: bool) -> bool:
	for k in keys:
		_key(k, true)
	if do_jump:
		_key(KEY_SPACE, true)

	var consecutive_stalls := 0
	for f in frames:
		if do_jump and f == 2:
			_key(KEY_SPACE, false)
		var pre := _player.global_position
		await physics_frame
		var post := _player.global_position
		var horiz := Vector2(post.x - pre.x, post.z - pre.z).length()

		# Skip acceleration / reversal ramp-up and airborne jump arc
		if f >= 36 and _player.is_on_floor():
			if horiz < STALL_THRESHOLD:
				var legit_block := false
				var col_info := ""
				for c in _player.get_slide_collision_count():
					var col := _player.get_slide_collision(c)
					var obj := col.get_collider()
					var cname := str((obj as Node).name) if obj is Node else str(obj)
					var shape_name := ""
					if obj is CollisionObject3D:
						var co := obj as CollisionObject3D
						var owner_obj := co.shape_owner_get_owner(co.shape_find_owner(col.get_collider_shape_index()))
						if owner_obj is Node:
							shape_name = str((owner_obj as Node).name)
					col_info += "[%s/%s n=%s pos=%s] " % [cname, shape_name, str(col.get_normal()), str(col.get_position())]
					if cname.begins_with("Props_") or cname == "HarlingenVehicle" or shape_name in ["BuildingCollision", "HarlingenVehicle", "BodyCollider"]:
						legit_block = true
				if not legit_block:
					consecutive_stalls += 1
					print("  STALL_TRACE %s f=%d pos=%s horiz=%.4f vel=%s cols=%s" % [
						label, f, str(post), horiz, str(_player.velocity), col_info
					])
					if consecutive_stalls >= MAX_STALL_FRAMES:
						for k in keys:
							_key(k, false)
						_key(KEY_SPACE, false)
						push_error("%s: Unexpected movement stall at frame %d pos=%s horiz=%.4f cols=%s" % [
							label, f, str(post), horiz, col_info
						])
						return false
				else:
					consecutive_stalls = 0
			else:
				consecutive_stalls = 0

	for k in keys:
		_key(k, false)
	_key(KEY_SPACE, false)
	return true

func _frames(count: int) -> void:
	for i in count:
		await physics_frame

func _key(code: Key, pressed: bool) -> void:
	var input := InputEventKey.new()
	input.physical_keycode = code
	input.pressed = pressed
	Input.parse_input_event(input)
	Input.flush_buffered_events()

func _require(condition: bool, description: String) -> bool:
	if not condition:
		push_error(description)
		quit(1)
	return condition
