extends SceneTree
## Exercises the shipped navigation layer and live playable scene.

const WORLD := preload("res://preview/Harlingen.tscn")
const ACTION := &"navigation_map"

var failures := 0
var world: Node3D
var navigation: CanvasLayer

func _initialize() -> void:
	call_deferred("_run")

func _wait(frames: int) -> void:
	for i in frames:
		await process_frame

func _check(ok: bool, label: String) -> void:
	print("[", "PASS" if ok else "FAIL", "] ", label)
	if not ok:
		failures += 1

func _key(code: Key, down := true) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = down
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _tap(code: Key) -> void:
	_key(code)
	_key(code, false)

func _pad(button: JoyButton) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	event = event.duplicate() as InputEventJoypadButton
	event.pressed = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _mouse(button: MouseButton, point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.position = point
	event.global_position = point
	event.pressed = pressed
	root.push_input(event, true)

func _motion(from: Vector2, to: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = to
	event.global_position = to
	event.relative = to - from
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(event, true)

func _world_point(actor: Node3D) -> Vector2:
	return Vector2(actor.global_position.x, actor.global_position.z)

func _run() -> void:
	root.size = Vector2i(1600, 900)
	world = WORLD.instantiate()
	root.add_child(world)
	navigation = world.get_node("Navigation")
	await _wait(65)
	_check(navigation.map_bounds == Rect2(-6000, -6000, 12000, 12000), "Full playable map has correct bounds")
	_check(navigation.mini.visible and not navigation.tracking_vehicle, "Lower-left minimap starts on foot")
	_check(navigation.tracked_position.distance_to(_world_point(world.player)) < 0.03, "On-foot map marker matches the player")
	Input.action_press("move_forward")
	await _wait(22)
	Input.action_release("move_forward")
	await _wait(3)
	var facing: Vector3 = -world.player.visual_root.global_basis.z
	_check(navigation.tracked_position.distance_to(_world_point(world.player)) < 0.20 and
		navigation.tracked_heading.dot(Vector2(facing.x, facing.z).normalized()) > 0.98, "Walking arrow follows movement and orientation")

	var zoom_start: float = navigation.mini.zoom
	_tap(KEY_EQUAL)
	await _wait(3)
	_check(navigation.mini.zoom > zoom_start, "Keyboard can adjust the live minimap zoom")
	_pad(JOY_BUTTON_DPAD_DOWN)
	await _wait(3)
	_check(is_equal_approx(navigation.mini.zoom, zoom_start), "Controller can adjust the live minimap zoom")

	_tap(KEY_M)
	await _wait(5)
	_check(navigation.map_open and paused and navigation.full.is_visible_in_tree() and not navigation.mini.is_visible_in_tree(), "M opens and pauses the full map")
	var full: Control = navigation.full
	var coordinate := Vector2(-2700.2, -1850.7)
	var local: Vector2 = full.map_to_screen(coordinate)
	_check(full.screen_to_map(local).distance_to(coordinate) < 0.005, "Map X/Z projection round-trips at the overview")
	_check(full.get_rect().has_area() and local.x >= 0 and local.y >= 0 and local.x < full.size.x and local.y < full.size.y,
		"Known world position is inside the map canvas")
	var pointer: Vector2 = full.get_global_transform_with_canvas() * local
	_mouse(MOUSE_BUTTON_LEFT, pointer, true)
	_mouse(MOUSE_BUTTON_LEFT, pointer, false)
	await _wait(3)
	_check(navigation.destination_active and navigation.destination.distance_to(coordinate) < 8.0, "Pointer click places a waypoint at the projected world location")
	_mouse(MOUSE_BUTTON_RIGHT, pointer, true)
	_mouse(MOUSE_BUTTON_RIGHT, pointer, false)
	await _wait(2)
	_check(not navigation.destination_active, "Right click clears the waypoint")
	_mouse(MOUSE_BUTTON_WHEEL_UP, pointer, true)
	_mouse(MOUSE_BUTTON_WHEEL_UP, pointer, false)
	await _wait(25)
	_check(full.get("zoom") > 1.2 and full.screen_to_map(local).distance_to(coordinate) < 5.0, "Wheel zoom keeps the point under the pointer")
	var prior_center: Vector2 = full.get("center")
	_mouse(MOUSE_BUTTON_LEFT, pointer, true)
	_motion(pointer, pointer + Vector2(65, 30))
	_mouse(MOUSE_BUTTON_LEFT, pointer + Vector2(65, 30), false)
	await _wait(20)
	_check(prior_center.distance_to(full.get("center")) > 220.0 and not navigation.destination_active, "Dragging pans smoothly without placing a waypoint")
	prior_center = full.get("center")
	Input.action_press("move_right")
	await _wait(18)
	Input.action_release("move_right")
	_check(prior_center.distance_to(full.get("center")) > 220.0, "Movement action pans while the world is paused")
	_pad(JOY_BUTTON_Y)
	await _wait(24)
	_check(navigation.destination_label == "I-2 / US 83", "Controller discovers the first named highway waypoint")
	_pad(JOY_BUTTON_X)
	await _wait(4)
	_check(not navigation.destination_active, "Controller clears the waypoint")
	_pad(JOY_BUTTON_A)
	await _wait(4)
	_check(navigation.destination_active, "Controller places a waypoint under the reticle")
	_pad(JOY_BUTTON_LEFT_STICK)
	await _wait(42)
	_check(Vector2(full.get("center")).distance_to(navigation.tracked_position) < 5.0, "L3 centers the map on the live actor")
	_tap(KEY_M)
	await _wait(4)
	_check(not navigation.map_open and not paused and navigation.mini.visible and navigation.mini.waypoint_active,
		"Closing resumes gameplay and keeps the waypoint on the minimap")

	var initial_binding: int = navigation._map_button
	_pad(initial_binding)
	await _wait(4)
	_pad(JOY_BUTTON_RIGHT_STICK)
	var changed_binding: int = navigation._map_button
	_check(initial_binding != changed_binding, "Controller map binding can be changed from the map")
	_pad(changed_binding)
	await _wait(4)
	_check(not navigation.map_open, "The newly assigned controller button closes the map")
	_pad(changed_binding)
	await _wait(4)
	_pad(JOY_BUTTON_RIGHT_STICK)
	_pad(initial_binding)
	await _wait(4)
	_check(not navigation.map_open, "The controller can reopen the map and restore its original binding")

	world.player.global_position = world.vehicle.global_position + Vector3(-2, 0.1, 0)
	await _wait(6)
	_check(world.vehicle_interaction.try_enter_vehicle(), "Enter the actual playable coupe")
	await _wait(45)
	_check(navigation.tracking_vehicle and navigation.tracked_position.distance_to(_world_point(world.vehicle)) < 0.03, "Marker tracks the vehicle after entry")
	_tap(KEY_M)
	var parked_at := _world_point(world.vehicle)
	Input.action_press("vehicle_accelerate")
	await _wait(18)
	Input.action_release("vehicle_accelerate")
	_check(navigation.tracking_vehicle and parked_at.distance_to(_world_point(world.vehicle)) < 0.01, "Map pauses the car and keeps its marker while driving")
	_tap(KEY_M)
	await _wait(10)
	_check(world.vehicle_interaction.try_exit_vehicle(), "Exit the actual playable coupe")
	await _wait(42)
	_check(not navigation.tracking_vehicle and navigation.tracked_position.distance_to(_world_point(world.player)) < 0.03, "Marker returns to the character after exit")

	# Cross a real streaming boundary using the normal player controller.
	world.player.global_position = Vector3(1998, 14, 293.3)
	world.player.velocity = Vector3.ZERO
	world.player.set_camera_yaw(-PI * 0.5)
	await _wait(45)
	Input.action_press("move_forward")
	await _wait(93)
	Input.action_release("move_forward")
	await _wait(20)
	_check(world.player.global_position.x > 2000.0 and world.loaded.has("+01_+00") and
		navigation.tracked_position.distance_to(_world_point(world.player)) < 0.06 and navigation.mini.waypoint_active,
		"Live player position and waypoint survive crossing into another district")

	# The map index uses real centers of existing audited overpasses. Confirm
	# roadway collision at those exact X/Z points and at their audited deck elevations.
	await _verify_bridge_markers()
	print("VERIFY_NAVIGATION_", "PASS" if failures == 0 else "FAIL", " failures=", failures)
	quit(0 if failures == 0 else 1)

func _verify_bridge_markers() -> void:
	for marker: Dictionary in navigation.markers:
		if marker.category != "highway":
			continue
		var height: float = marker.get("deck_y", 21.0)
		var p := Vector3(marker.x, height, marker.z)
		world.player.global_position = p + Vector3.UP * 4.0
		world.player.velocity = Vector3.ZERO
		await _wait(24)
		var space := root.world_3d.direct_space_state
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * 13, p - Vector3.UP * 12, 1))
		var shape_name := ""
		if not hit.is_empty():
			var body := hit.collider as CollisionObject3D
			if body != null:
				var owner := body.shape_owner_get_owner(body.shape_find_owner(hit.shape))
				if owner != null:
					shape_name = str(owner.name)
		var correct := shape_name == "ElevatedCollision"
		if marker.has("deck_y") and correct:
			correct = absf(hit.position.y - height) < 0.22
		_check(correct, "Highway marker lands on a modeled deck: %s (%s)" % [marker.label, shape_name])
