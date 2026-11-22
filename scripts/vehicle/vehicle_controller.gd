extends VehicleBody3D
## Arcade-realistic vehicle controller for the Harlingen sports coupe.

signal driver_state_changed(active: bool)

@export_group("Driving")
@export var max_engine_force := 4400.0
@export var reverse_engine_force := 2600.0
@export var max_brake_force := 85.0
@export var handbrake_force := 140.0
@export var max_forward_speed_mps := 48.0
@export var max_reverse_speed_mps := 14.0
@export var low_speed_steer_rad := 0.42
@export var high_speed_steer_rad := 0.13
@export var steer_speed_reference := 30.0
@export var steer_response := 5.5
@export var downforce_per_mps := 24.0
@export var anti_roll_stiffness := 2200.0

const DRIVER_DOOR_OPEN_EULER := Vector3(-0.67157, -1.14177, 0.01195)
const PASSENGER_DOOR_OPEN_EULER := Vector3(-0.67157, 1.14177, -0.01195)

@export_group("Camera")
@export var pivot_offset := Vector3(0.0, 1.25, 0.15)
@export var mouse_sensitivity := 0.0024
@export var stick_sensitivity := 2.4
@export var stick_deadzone := 0.2
@export var min_pitch_deg := -42.0
@export var max_pitch_deg := 18.0
@export var default_pitch_deg := -12.0
@export var auto_align_delay := 1.2
@export var auto_align_speed := 2.6

@export_group("Interaction")
@export var interaction_radius := 3.5
@export var max_enter_speed_mps := 3.0
@export var max_exit_speed_mps := 2.0

@onready var wheel_fl: VehicleWheel3D = $WheelFL
@onready var wheel_fr: VehicleWheel3D = $WheelFR
@onready var wheel_rl: VehicleWheel3D = $WheelRL
@onready var wheel_rr: VehicleWheel3D = $WheelRR
@onready var camera_pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var chase_camera: Camera3D = $CameraPivot/SpringArm3D/ChaseCamera
@onready var driver_seat: Marker3D = $DriverSeat
@onready var exit_points: Node3D = $ExitPoints
@onready var interaction_area: Area3D = $InteractionArea
@onready var car_model: Node3D = $CarModel

var driver_active := false
var _current_steer := 0.0
var _cam_yaw := 0.0
var _cam_pitch := deg_to_rad(-12.0)
var _manual_cam_timer := 0.0
var _rear_base_slip := 3.4
var _spawn_transform: Transform3D
var _door_l_pivot: Node3D = null
var _door_r_pivot: Node3D = null
var _driver_door_open := false
var _door_tween: Tween = null
var _wheel_meshes: Array = []


func _ready() -> void:
	_spawn_transform = global_transform
	if wheel_rl:
		_rear_base_slip = wheel_rl.wheel_friction_slip
	_apply_clean_material_override()
	_setup_car_model_parts()
	if camera_pivot:
		camera_pivot.top_level = true
		_sync_camera_to_vehicle(true)
	_set_parked_brake()


func _setup_car_model_parts() -> void:
	if not car_model:
		return
	_door_l_pivot = car_model.get_node_or_null("DoorL_Pivot") as Node3D
	if _door_l_pivot == null:
		_door_l_pivot = car_model.find_child("DoorL_Pivot", true, false) as Node3D
	_door_r_pivot = car_model.get_node_or_null("DoorR_Pivot") as Node3D
	if _door_r_pivot == null:
		_door_r_pivot = car_model.find_child("DoorR_Pivot", true, false) as Node3D
	if _door_l_pivot:
		_door_l_pivot.rotation = Vector3.ZERO
	if _door_r_pivot:
		_door_r_pivot.rotation = Vector3.ZERO
	_driver_door_open = false

	_wheel_meshes.clear()
	var wheel_pairs := [
		[wheel_fl, "WheelFL_Mesh"],
		[wheel_fr, "WheelFR_Mesh"],
		[wheel_rl, "WheelRL_Mesh"],
		[wheel_rr, "WheelRR_Mesh"],
	]
	for pair in wheel_pairs:
		var wheel_node := pair[0] as VehicleWheel3D
		var mesh_name: String = pair[1]
		var wheel_mesh := car_model.get_node_or_null(mesh_name) as Node3D
		if wheel_mesh == null:
			wheel_mesh = car_model.find_child(mesh_name, true, false) as Node3D
		if wheel_node and wheel_mesh:
			wheel_mesh.owner = null
			wheel_mesh.reparent(wheel_node, false)
			wheel_mesh.transform = Transform3D.IDENTITY
			_wheel_meshes.append(wheel_mesh)


func set_driver_door_open(open: bool, duration: float = 0.35) -> void:
	_driver_door_open = open
	if _door_tween and _door_tween.is_valid():
		_door_tween.kill()
		_door_tween = null
	if _door_l_pivot == null:
		return
	var target_quat := Quaternion.from_euler(DRIVER_DOOR_OPEN_EULER) if open else Quaternion.IDENTITY
	if duration <= 0.001 or not is_inside_tree():
		_door_l_pivot.quaternion = target_quat
		if not open:
			_door_l_pivot.rotation = Vector3.ZERO
		return
	_door_tween = create_tween()
	_door_tween.set_trans(Tween.TRANS_CUBIC)
	_door_tween.set_ease(Tween.EASE_OUT if open else Tween.EASE_IN_OUT)
	var start_quat := _door_l_pivot.quaternion
	_door_tween.tween_method(
		func(t: float) -> void:
			if is_instance_valid(_door_l_pivot):
				_door_l_pivot.quaternion = start_quat.slerp(target_quat, t),
		0.0,
		1.0,
		duration
	)
	if not open:
		_door_tween.tween_callback(func() -> void:
			if is_instance_valid(_door_l_pivot) and not _driver_door_open:
				_door_l_pivot.rotation = Vector3.ZERO
		)


func is_driver_door_open() -> bool:
	return _driver_door_open


func get_driver_door_pivot() -> Node3D:
	return _door_l_pivot


func get_wheel_meshes() -> Array:
	return _wheel_meshes.duplicate()


func _apply_clean_material_override() -> void:
	if not car_model:
		return
	var meshes := car_model.find_children("*", "MeshInstance3D", true, false)
	for node in meshes:
		var mi := node as MeshInstance3D
		if not mi or not mi.mesh:
			continue
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s)
			if mat is BaseMaterial3D:
				var bm := mat as BaseMaterial3D
				if bm.metallic_specular > 1.0:
					var dup := bm.duplicate() as BaseMaterial3D
					dup.metallic_specular = 0.5
					mi.set_surface_override_material(s, dup)


func set_spawn_transform(xform: Transform3D) -> void:
	_spawn_transform = xform
	global_transform = xform
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_sync_camera_to_vehicle(true)


func respawn() -> void:
	global_transform = _spawn_transform
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_current_steer = 0.0
	engine_force = 0.0
	brake = 0.0
	steering = 0.0
	set_driver_door_open(false, 0.0)
	_sync_camera_to_vehicle(true)


func set_driver_active(active: bool) -> void:
	if driver_active == active:
		if active and chase_camera:
			chase_camera.make_current()
		return
	driver_active = active
	if active:
		_cam_pitch = deg_to_rad(default_pitch_deg)
		_manual_cam_timer = 0.0
		_sync_camera_to_vehicle(true)
		if chase_camera:
			chase_camera.make_current()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		_set_parked_brake()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	driver_state_changed.emit(driver_active)


func get_camera() -> Camera3D:
	return chase_camera


func get_camera_global_transform() -> Transform3D:
	if chase_camera:
		return chase_camera.global_transform
	return global_transform


func get_speed_mps() -> float:
	return linear_velocity.length()


func get_forward_speed_mps() -> float:
	return linear_velocity.dot(-global_basis.z)


func can_enter() -> bool:
	return not driver_active and global_basis.y.y > 0.4 and get_speed_mps() < max_enter_speed_mps


func can_exit() -> bool:
	return driver_active and get_speed_mps() < max_exit_speed_mps


func is_player_in_range(player_pos: Vector3) -> bool:
	return global_position.distance_to(player_pos) <= interaction_radius


func get_driver_seat_transform() -> Transform3D:
	if driver_seat:
		return driver_seat.global_transform
	return global_transform


func find_safe_exit_transform(player_radius: float = 0.32, player_height: float = 1.78) -> Transform3D:
	var space := get_world_3d().direct_space_state if get_world_3d() else null
	var candidates: Array[Vector3] = []
	if exit_points:
		for child in exit_points.get_children():
			if child is Marker3D:
				candidates.append((child as Marker3D).global_position)
	if candidates.is_empty():
		candidates = [
			global_transform * Vector3(-1.7, 0.05, 0.15),
			global_transform * Vector3(1.7, 0.05, 0.15),
			global_transform * Vector3(0.0, 0.05, 3.0),
		]
	# Add diagonal / forward radial fallbacks around the vehicle
	for local_pt in [
		Vector3(-2.1, 0.05, -0.6),
		Vector3(2.1, 0.05, -0.6),
		Vector3(-2.1, 0.05, 1.2),
		Vector3(2.1, 0.05, 1.2),
		Vector3(0.0, 0.05, -2.9),
	]:
		candidates.append(global_transform * local_pt)

	var car_origin := global_position + global_basis.y * 0.85
	var capsule := CapsuleShape3D.new()
	capsule.radius = player_radius
	capsule.height = player_height
	var exclude_rids: Array[RID] = [get_rid()]

	var forward := -global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.001:
		forward = Vector3.FORWARD
	else:
		forward = forward.normalized()
	var exit_basis := Basis.looking_at(forward, Vector3.UP)

	if space == null:
		return Transform3D(exit_basis, candidates[0])

	for pt in candidates:
		# 1. Horizontal path check from car center to exit XY so player does not pass through a wall
		var path_end := Vector3(pt.x, car_origin.y, pt.z)
		var path_query := PhysicsRayQueryParameters3D.create(car_origin, path_end, 1, exclude_rids)
		if not space.intersect_ray(path_query).is_empty():
			continue

		# 2. Ground raycast straight down at the candidate spot
		var ray_top := Vector3(pt.x, global_position.y + 2.5, pt.z)
		var ray_bot := Vector3(pt.x, global_position.y - 4.0, pt.z)
		var ground_query := PhysicsRayQueryParameters3D.create(ray_top, ray_bot, 1, exclude_rids)
		var ground_hit := space.intersect_ray(ground_query)
		if ground_hit.is_empty():
			continue
		var ground_pos: Vector3 = ground_hit.position
		if absf(ground_pos.y - global_position.y) > 2.0:
			continue

		# 3. Capsule overlap test against world (layer 1) and vehicle (layer 4)
		var shape_center := ground_pos + Vector3.UP * (player_height * 0.5 + 0.06)
		var shape_params := PhysicsShapeQueryParameters3D.new()
		shape_params.shape = capsule
		shape_params.collision_mask = 1 | 4
		shape_params.exclude = exclude_rids
		shape_params.transform = Transform3D(Basis.IDENTITY, shape_center)
		if space.intersect_shape(shape_params, 2).is_empty():
			return Transform3D(exit_basis, ground_pos + Vector3.UP * 0.04)

	# Fallback above roof if completely boxed in on all sides
	var roof_pos := global_position + Vector3.UP * 1.95
	return Transform3D(exit_basis, roof_pos)


func handle_input(event: InputEvent) -> void:
	if not driver_active:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var rel: Vector2 = event.screen_relative
		if rel.length_squared() < 0.0001:
			rel = event.relative
		_rotate_camera(rel * mouse_sensitivity)


func _unhandled_input(event: InputEvent) -> void:
	if driver_active:
		handle_input(event)


func _process(delta: float) -> void:
	if not driver_active:
		return
	var cam_delta := _read_camera_stick_and_actions()
	if cam_delta.length_squared() > 0.0001:
		_rotate_camera(cam_delta * stick_sensitivity * delta)
	else:
		_manual_cam_timer = maxf(0.0, _manual_cam_timer - delta)
		if _manual_cam_timer <= 0.0:
			_auto_align_camera(delta)
	_update_camera_pivot(delta)


func _physics_process(delta: float) -> void:
	if not driver_active:
		_set_parked_brake()
		_apply_stabilization()
		return

	var throttle := _get_throttle_input()
	var brake_in := _get_brake_input()
	var steer_in := _get_steer_input()
	var handbrake := _get_handbrake_input()

	var speed := linear_velocity.length()
	var forward_speed := linear_velocity.dot(-global_basis.z)

	# Speed-sensitive steering
	var speed_t := clampf(speed / steer_speed_reference, 0.0, 1.0)
	var max_steer := lerpf(low_speed_steer_rad, high_speed_steer_rad, speed_t)
	var target_steer := steer_in * max_steer
	_current_steer = move_toward(_current_steer, target_steer, steer_response * delta)
	steering = _current_steer

	# Acceleration, braking, and smooth reversing
	var target_engine := 0.0
	var target_brake := 0.0

	if handbrake:
		target_engine = 0.0
		target_brake = handbrake_force
		_set_rear_slip(_rear_base_slip * 0.55)
	else:
		_set_rear_slip(_rear_base_slip)
		if brake_in > 0.05:
			if forward_speed > 1.0:
				# Moving forward -> brake cleanly
				target_brake = brake_in * max_brake_force
				target_engine = 0.0
			else:
				# Speed near 0 or moving backward -> shift smoothly into reverse
				if -forward_speed < max_reverse_speed_mps:
					target_engine = -brake_in * reverse_engine_force
				target_brake = 0.0
		elif throttle > 0.05:
			if forward_speed < -1.0:
				# Reversing and pressing forward -> brake to a stop first
				target_brake = throttle * max_brake_force
				target_engine = 0.0
			else:
				if forward_speed < max_forward_speed_mps:
					var speed_factor := 1.0 - clampf(forward_speed / (max_forward_speed_mps * 1.15), 0.0, 0.75)
					target_engine = throttle * max_engine_force * speed_factor
				target_brake = 0.0
		else:
			# Gentle engine braking when coasting
			if speed > 0.5:
				target_brake = 4.0

	# Note: Godot VehicleBody3D applies positive engine_force along +Z, while our car faces -Z.
	engine_force = -target_engine
	brake = target_brake

	_apply_stabilization()


func _apply_stabilization() -> void:
	var speed := linear_velocity.length()
	var grounded_wheels := 0
	for w in [wheel_fl, wheel_fr, wheel_rl, wheel_rr]:
		if w and w.is_in_contact():
			grounded_wheels += 1

	# Speed-proportional aerodynamic downforce when wheels are near/on ground
	if grounded_wheels >= 2 and speed > 1.0:
		apply_central_force(-global_basis.y * downforce_per_mps * speed)

	# Gentle anti-roll torque based on left vs right suspension compression / chassis roll
	if grounded_wheels >= 2:
		var up := global_basis.y
		var roll_error := up.cross(Vector3.UP)
		# Keep pitch natural on hills, primarily resist excessive lateral roll
		var local_roll_axis := global_basis.z
		var roll_amount := roll_error.dot(local_roll_axis)
		apply_torque(local_roll_axis * (roll_amount * anti_roll_stiffness))


func _set_rear_slip(slip: float) -> void:
	if wheel_rl:
		wheel_rl.wheel_friction_slip = slip
	if wheel_rr:
		wheel_rr.wheel_friction_slip = slip


func _set_parked_brake() -> void:
	engine_force = 0.0
	brake = 24.0
	_current_steer = 0.0
	steering = 0.0


func _rotate_camera(angle: Vector2) -> void:
	_cam_yaw = wrapf(_cam_yaw - angle.x, -PI, PI)
	_cam_pitch = clampf(_cam_pitch - angle.y, deg_to_rad(min_pitch_deg), deg_to_rad(max_pitch_deg))
	_manual_cam_timer = auto_align_delay


func _auto_align_camera(delta: float) -> void:
	var forward_speed := get_forward_speed_mps()
	if forward_speed < 1.8:
		return
	var vel_horiz := Vector3(linear_velocity.x, 0.0, linear_velocity.z)
	if vel_horiz.length_squared() < 1.0:
		return
	var dir := vel_horiz.normalized()
	var target_yaw := atan2(-dir.x, -dir.z)
	_cam_yaw = lerp_angle(_cam_yaw, target_yaw, 1.0 - exp(-auto_align_speed * delta))


func _sync_camera_to_vehicle(reset_yaw: bool) -> void:
	if reset_yaw:
		var fwd := -global_basis.z
		fwd.y = 0.0
		if fwd.length_squared() > 0.001:
			fwd = fwd.normalized()
			_cam_yaw = atan2(-fwd.x, -fwd.z)
		else:
			_cam_yaw = global_rotation.y
	if camera_pivot:
		camera_pivot.global_position = global_position + global_basis * pivot_offset
		camera_pivot.global_rotation = Vector3(_cam_pitch, _cam_yaw, 0.0)


func _update_camera_pivot(delta: float) -> void:
	if not camera_pivot:
		return
	var target_pos := global_position + global_basis * pivot_offset
	var follow_t := 1.0 - exp(-22.0 * delta)
	camera_pivot.global_position = camera_pivot.global_position.lerp(target_pos, follow_t)
	camera_pivot.global_rotation = Vector3(_cam_pitch, _cam_yaw, 0.0)


func _get_throttle_input() -> float:
	if InputMap.has_action(&"vehicle_accelerate"):
		return Input.get_action_strength(&"vehicle_accelerate")
	var val := float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP))
	var pads := Input.get_connected_joypads()
	if not pads.is_empty():
		val = maxf(val, clampf(Input.get_joy_axis(pads[0], JOY_AXIS_TRIGGER_RIGHT), 0.0, 1.0))
	return clampf(val, 0.0, 1.0)


func _get_brake_input() -> float:
	if InputMap.has_action(&"vehicle_brake"):
		return Input.get_action_strength(&"vehicle_brake")
	var val := float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN))
	var pads := Input.get_connected_joypads()
	if not pads.is_empty():
		val = maxf(val, clampf(Input.get_joy_axis(pads[0], JOY_AXIS_TRIGGER_LEFT), 0.0, 1.0))
	return clampf(val, 0.0, 1.0)


func _get_steer_input() -> float:
	var steer := 0.0
	if InputMap.has_action(&"vehicle_steer_left") and InputMap.has_action(&"vehicle_steer_right"):
		steer = Input.get_action_strength(&"vehicle_steer_left") - Input.get_action_strength(&"vehicle_steer_right")
	else:
		var left := float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT))
		var right := float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT))
		steer = left - right
		var pads := Input.get_connected_joypads()
		if not pads.is_empty():
			var stick_x := _stick_axis(pads[0], JOY_AXIS_LEFT_X)
			steer -= stick_x
	return clampf(steer, -1.0, 1.0)


func _get_handbrake_input() -> bool:
	if InputMap.has_action(&"vehicle_handbrake"):
		return Input.is_action_pressed(&"vehicle_handbrake")
	if Input.is_physical_key_pressed(KEY_SPACE):
		return true
	var pads := Input.get_connected_joypads()
	if not pads.is_empty():
		return Input.is_joy_button_pressed(pads[0], JOY_BUTTON_B)
	return false


func _read_camera_stick_and_actions() -> Vector2:
	var has_x := InputMap.has_action(&"cam_right") and InputMap.has_action(&"cam_left")
	var has_y := InputMap.has_action(&"cam_down") and InputMap.has_action(&"cam_up")
	if has_x and has_y:
		return Vector2(
			Input.get_action_strength(&"cam_right") - Input.get_action_strength(&"cam_left"),
			Input.get_action_strength(&"cam_down") - Input.get_action_strength(&"cam_up")
		)
	var delta := Vector2.ZERO
	var pads := Input.get_connected_joypads()
	var pad_vec := _stick_vec(pads[0], JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y) if not pads.is_empty() else Vector2.ZERO
	delta.x = (Input.get_action_strength(&"cam_right") - Input.get_action_strength(&"cam_left")) if has_x else pad_vec.x
	delta.y = (Input.get_action_strength(&"cam_down") - Input.get_action_strength(&"cam_up")) if has_y else pad_vec.y
	return delta


func _stick_axis(device: int, axis: JoyAxis) -> float:
	var raw := Input.get_joy_axis(device, axis)
	if absf(raw) < stick_deadzone:
		return 0.0
	return signf(raw) * inverse_lerp(stick_deadzone, 1.0, clampf(absf(raw), stick_deadzone, 1.0))


func _stick_vec(device: int, x_axis: JoyAxis, y_axis: JoyAxis) -> Vector2:
	var v := Vector2(Input.get_joy_axis(device, x_axis), Input.get_joy_axis(device, y_axis))
	var len_v := v.length()
	if len_v < stick_deadzone:
		return Vector2.ZERO
	var strength := inverse_lerp(stick_deadzone, 1.0, clampf(len_v, stick_deadzone, 1.0))
	return v.normalized() * strength
