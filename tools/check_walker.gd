extends SceneTree
## Exercise real input, speed adjustment and the downtown collider in both terrain modes.

func _initialize() -> void:
	call_deferred("_check")

func _check() -> void:
	var world: Node3D = load("res://preview/Harlingen.tscn").instantiate()
	root.add_child(world)
	var walker: CharacterBody3D = world.walker
	await _frames(32)
	if not _require(world.walking and walker.is_on_floor() and
			root.get_camera_3d() == walker.get_node("Eyes"), "Walker starts grounded with its camera active"):
		return
	var start := walker.position
	_key(KEY_W, true)
	await _frames(12)
	_key(KEY_W, false)
	var normal: float = walker.position.z - start.z
	walker.respawn()
	await _frames(32)
	for i in 18:
		var scroll := InputEventMouseButton.new()
		scroll.button_index = MOUSE_BUTTON_WHEEL_UP
		scroll.pressed = true
		world._unhandled_input(scroll)
	if not _require(is_equal_approx(world.walker.speed_multiplier, 4.0) and
			world.hint.text.contains("4.00×"), "Wheel caps at 4× and updates the HUD"):
		return
	start = walker.position
	_key(KEY_W, true)
	await _frames(12)
	_key(KEY_W, false)
	var fast: float = walker.position.z - start.z
	if not _require(normal > 0.65 and absf(fast / normal - 4.0) < 0.12, "4× actual movement"):
		return
	_key(KEY_W, true)
	await _frames(36)
	_key(KEY_W, false)
	if not _require(walker.position.z < 327.0 and walker.position.z > 324.0,
			"Baxter Building wall stops forward movement"):
		return
	var fly := InputEventKey.new()
	fly.physical_keycode = KEY_F7
	fly.pressed = true
	world._unhandled_input(fly)
	if not _require(not world.walking and root.get_camera_3d() == world.camera, "F7 returns to flyover"):
		return
	world._unhandled_input(fly)
	if not _require(world.walking and is_equal_approx(world.walker.speed_multiplier, 4.0),
			"Walk speed survives a mode switch"):
		return
	for i in 18:
		var slower := InputEventJoypadButton.new()
		slower.button_index = JOY_BUTTON_DPAD_DOWN
		slower.pressed = true
		world._unhandled_input(slower)
	if not _require(is_equal_approx(world.walker.speed_multiplier, 1.0), "D-pad caps at 1×"):
		return
	print("Walk verified in ", "Terrain3D" if world.native_terrain else "GLB",
		": 12 frames at 1× = ", normal, " m, at 4× = ", fast,
		" m, building wall at z=", walker.position.z)
	quit()

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
