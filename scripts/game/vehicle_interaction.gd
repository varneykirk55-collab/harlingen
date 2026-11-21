extends Node
## Coordinates player <-> vehicle entry/exit, smooth camera transitions, and HUD state.

const GameHUD := preload("res://scenes/ui/game_hud.gd")

signal mode_changed(driving: bool)
signal active_camera_changed(camera: Camera3D)

@export var transition_duration: float = 0.35

var player: Node3D = null
var vehicle: Node3D = null
var hud: GameHUD = null
var transition_camera: Camera3D = null

var is_gameplay_active: bool = false
var is_driving: bool = false
var is_transitioning: bool = false

var _trans_elapsed: float = 0.0
var _trans_start_xform: Transform3D = Transform3D.IDENTITY
var _trans_start_fov: float = 70.0
var _trans_target_driving: bool = false
var _exit_check_timer: float = 0.0
var _exit_blocked_cached: bool = false
var _waiting_ground_unfreeze: bool = false
var _unfreeze_wait_timer: float = 0.0
var _vehicle_paused: bool = false
var _door_close_delay: float = -1.0
var _door_close_duration: float = 0.2


func setup(p_player: Node3D, p_vehicle: Node3D, p_hud: GameHUD, p_transition_camera: Camera3D) -> void:
	player = p_player
	vehicle = p_vehicle
	hud = p_hud
	transition_camera = p_transition_camera

	if player and player.has_signal("rifle_stance_changed"):
		if not player.rifle_stance_changed.is_connected(_on_rifle_stance_changed):
			player.rifle_stance_changed.connect(_on_rifle_stance_changed)
	if vehicle and vehicle.has_signal("driver_state_changed"):
		if not vehicle.driver_state_changed.is_connected(_on_driver_state_changed):
			vehicle.driver_state_changed.connect(_on_driver_state_changed)


func set_gameplay_active(active: bool) -> void:
	is_gameplay_active = active
	if not active:
		cancel_transition()
		_door_close_delay = -1.0
		_waiting_ground_unfreeze = false
		if player and player.has_method("set_active"):
			player.set_active(false)
		if vehicle and vehicle.has_method("set_driver_active"):
			vehicle.set_driver_active(false)
		if vehicle and vehicle.has_method("set_driver_door_open"):
			vehicle.set_driver_door_open(false, 0.0)
		_set_vehicle_paused(true)
		if hud:
			hud.set_prompt("", GameHUD.PromptTone.NONE)
		return

	if _has_ground_under_vehicle():
		_set_vehicle_paused(false)
		_waiting_ground_unfreeze = false
	else:
		_set_vehicle_paused(true)
		_waiting_ground_unfreeze = true
		_unfreeze_wait_timer = 1.5
	if is_driving:
		if player and player.has_method("set_in_vehicle") and not _is_player_in_vehicle():
			player.set_in_vehicle(true, vehicle)
		elif player and player.has_method("set_active"):
			player.set_active(false)
		if vehicle and vehicle.has_method("set_driver_active"):
			vehicle.set_driver_active(true)
	else:
		if vehicle and vehicle.has_method("set_driver_active"):
			vehicle.set_driver_active(false)
		if player and player.has_method("set_active"):
			player.set_active(true)

	_sync_hud_mode()
	active_camera_changed.emit(get_active_camera())


func get_active_camera() -> Camera3D:
	if is_transitioning and transition_camera:
		return transition_camera
	if is_driving and vehicle and vehicle.has_method("get_camera"):
		return vehicle.get_camera()
	if player and player.has_method("get_camera"):
		return player.get_camera()
	return null


func cancel_transition() -> void:
	if not is_transitioning:
		return
	is_transitioning = false
	_trans_elapsed = 0.0


func handle_input(event: InputEvent) -> bool:
	if not is_gameplay_active:
		return false

	if _is_interact_pressed(event):
		if is_driving:
			try_exit_vehicle()
		else:
			try_enter_vehicle()
		return true

	if is_driving:
		if event is InputEventKey and event.pressed and not event.echo:
			if (event as InputEventKey).physical_keycode == KEY_HOME:
				if vehicle and vehicle.has_method("respawn"):
					_door_close_delay = -1.0
					vehicle.respawn()
					return true
	return false


func try_enter_vehicle() -> bool:
	if not is_gameplay_active or is_driving or is_transitioning:
		return false
	if player == null or vehicle == null:
		return false
	if not vehicle.has_method("can_enter") or not vehicle.can_enter():
		return false
	if not vehicle.has_method("is_player_in_range") or not vehicle.is_player_in_range(player.global_position):
		return false

	var start_cam := _get_player_camera()
	var start_xform := start_cam.global_transform if start_cam else player.global_transform
	var start_fov := start_cam.fov if start_cam else 70.0

	if player.has_method("set_in_vehicle"):
		player.set_in_vehicle(true, vehicle)
	player.global_position = vehicle.global_position + Vector3(0.0, 3.5, 0.0)

	is_driving = true
	_exit_blocked_cached = false
	_exit_check_timer = 0.0

	if vehicle.has_method("set_driver_active"):
		vehicle.set_driver_active(true)

	_trigger_door_enter_exit_cycle()
	_begin_camera_transition(start_xform, start_fov, true)
	_sync_hud_mode()
	mode_changed.emit(true)
	return true


func try_exit_vehicle() -> bool:
	if not is_gameplay_active or not is_driving or is_transitioning:
		return false
	if player == null or vehicle == null:
		return false
	if not vehicle.has_method("can_exit") or not vehicle.can_exit():
		if hud:
			hud.set_prompt("Stop vehicle to exit", GameHUD.PromptTone.WARNING)
		return false
	if _is_exit_surrounded():
		_exit_blocked_cached = true
		if hud:
			hud.set_prompt("Exit blocked", GameHUD.PromptTone.BLOCKED)
		return false

	var start_cam := _get_vehicle_camera()
	var start_xform := start_cam.global_transform if start_cam else vehicle.global_transform
	var start_fov := start_cam.fov if start_cam else 72.0

	is_driving = false
	if vehicle.has_method("set_driver_active"):
		vehicle.set_driver_active(false)
	if player.has_method("set_in_vehicle"):
		player.set_in_vehicle(false, vehicle)

	_trigger_door_enter_exit_cycle()
	_begin_camera_transition(start_xform, start_fov, false)
	_sync_hud_mode()
	mode_changed.emit(false)
	return true


func _trigger_door_enter_exit_cycle() -> void:
	if vehicle == null or not vehicle.has_method("set_driver_door_open"):
		return
	var open_dur := clampf(transition_duration * 0.5, 0.14, 0.22)
	var close_dur := clampf(transition_duration * 0.55, 0.16, 0.24)
	vehicle.set_driver_door_open(true, open_dur)
	_door_close_delay = open_dur
	_door_close_duration = close_dur


func is_vehicle_paused() -> bool:
	return _vehicle_paused


func _set_vehicle_paused(paused: bool) -> void:
	_vehicle_paused = paused
	if vehicle == null:
		return
	vehicle.set_physics_process(not paused)
	if paused:
		if "engine_force" in vehicle:
			vehicle.engine_force = 0.0
		if "brake" in vehicle:
			vehicle.brake = 0.0
		if "steering" in vehicle:
			vehicle.steering = 0.0
		if "linear_velocity" in vehicle:
			vehicle.linear_velocity = Vector3.ZERO
		if "angular_velocity" in vehicle:
			vehicle.angular_velocity = Vector3.ZERO
		if "gravity_scale" in vehicle:
			vehicle.gravity_scale = 0.0
		if "sleeping" in vehicle:
			vehicle.sleeping = true
	else:
		if "gravity_scale" in vehicle:
			vehicle.gravity_scale = 1.0
		if "sleeping" in vehicle:
			vehicle.sleeping = false


func _physics_process(delta: float) -> void:
	if _waiting_ground_unfreeze and is_gameplay_active:
		_unfreeze_wait_timer -= delta
		if _has_ground_under_vehicle() or _unfreeze_wait_timer <= 0.0:
			_waiting_ground_unfreeze = false
			_set_vehicle_paused(false)


func _process(delta: float) -> void:
	if _door_close_delay > 0.0:
		_door_close_delay -= delta
		if _door_close_delay <= 0.0:
			_door_close_delay = -1.0
			if vehicle and vehicle.has_method("set_driver_door_open"):
				vehicle.set_driver_door_open(false, _door_close_duration)

	if is_driving and player and vehicle:
		player.global_position = vehicle.global_position + Vector3(0.0, 3.5, 0.0)

	if is_driving and vehicle and vehicle.global_position.y < -15.0:
		if vehicle.has_method("respawn"):
			vehicle.respawn()

	if is_transitioning:
		_update_camera_transition(delta)

	if is_gameplay_active:
		_update_hud(delta)


func _begin_camera_transition(start_xform: Transform3D, start_fov: float, to_driving: bool) -> void:
	if transition_camera == null or transition_duration <= 0.01:
		var fallback_cam := _get_vehicle_camera() if to_driving else _get_player_camera()
		if fallback_cam:
			fallback_cam.make_current()
		active_camera_changed.emit(fallback_cam)
		return

	_trans_start_xform = start_xform.orthonormalized()
	_trans_start_fov = start_fov
	_trans_target_driving = to_driving
	_trans_elapsed = 0.0
	is_transitioning = true

	var target_cam := _get_vehicle_camera() if to_driving else _get_player_camera()
	if target_cam:
		transition_camera.near = target_cam.near
		transition_camera.far = target_cam.far
	transition_camera.global_transform = _trans_start_xform
	transition_camera.fov = _trans_start_fov
	transition_camera.make_current()
	active_camera_changed.emit(transition_camera)


func _update_camera_transition(delta: float) -> void:
	_trans_elapsed += delta
	var raw_t := clampf(_trans_elapsed / maxf(transition_duration, 0.001), 0.0, 1.0)
	var t := raw_t * raw_t * (3.0 - 2.0 * raw_t)

	var target_cam := _get_vehicle_camera() if _trans_target_driving else _get_player_camera()
	var target_xform := target_cam.global_transform.orthonormalized() if target_cam else _trans_start_xform
	var target_fov := target_cam.fov if target_cam else _trans_start_fov

	transition_camera.global_transform = _trans_start_xform.interpolate_with(target_xform, t)
	transition_camera.fov = lerpf(_trans_start_fov, target_fov, t)

	if raw_t >= 1.0:
		is_transitioning = false
		if target_cam and is_gameplay_active:
			target_cam.make_current()
			active_camera_changed.emit(target_cam)


func _update_hud(delta: float) -> void:
	if hud == null or player == null or vehicle == null:
		return

	if is_driving:
		var speed_mps: float = vehicle.get_speed_mps() if vehicle.has_method("get_speed_mps") else 0.0
		var fwd_mps: float = vehicle.get_forward_speed_mps() if vehicle.has_method("get_forward_speed_mps") else 0.0
		hud.set_speed_mps(speed_mps, fwd_mps)

		if vehicle.has_method("can_exit") and not vehicle.can_exit():
			_exit_blocked_cached = false
			hud.set_prompt("Stop vehicle to exit", GameHUD.PromptTone.WARNING)
		else:
			_exit_check_timer -= delta
			if _exit_check_timer <= 0.0:
				_exit_check_timer = 0.15
				_exit_blocked_cached = _is_exit_surrounded()
			if _exit_blocked_cached:
				hud.set_prompt("Exit blocked", GameHUD.PromptTone.BLOCKED)
			else:
				hud.set_prompt("[E / Y] Exit Vehicle", GameHUD.PromptTone.NORMAL)
	else:
		if vehicle.has_method("is_player_in_range") and vehicle.is_player_in_range(player.global_position):
			if vehicle.has_method("can_enter") and vehicle.can_enter():
				hud.set_prompt("[E / Y] Enter Vehicle", GameHUD.PromptTone.NORMAL)
			else:
				hud.set_prompt("", GameHUD.PromptTone.NONE)
		else:
			hud.set_prompt("", GameHUD.PromptTone.NONE)


func _sync_hud_mode() -> void:
	if hud == null:
		return
	if not is_gameplay_active:
		return
	if is_driving:
		hud.set_mode(GameHUD.HudMode.DRIVING)
	else:
		hud.set_mode(GameHUD.HudMode.ON_FOOT)
		if player and player.has_method("is_rifle_stance"):
			hud.set_rifle_stance(player.is_rifle_stance())


func _has_ground_under_vehicle() -> bool:
	if vehicle == null or not vehicle.is_inside_tree():
		return true
	var world_3d := vehicle.get_world_3d()
	if world_3d == null:
		return true
	var space := world_3d.direct_space_state
	var start := vehicle.global_position + Vector3.UP * 2.5
	var end := vehicle.global_position - Vector3.UP * 4.5
	var query := PhysicsRayQueryParameters3D.create(start, end, 1, [vehicle.get_rid()])
	return not space.intersect_ray(query).is_empty()


func _is_exit_surrounded() -> bool:
	if vehicle == null or not vehicle.has_method("find_safe_exit_transform"):
		return false
	var exit_xform: Transform3D = vehicle.find_safe_exit_transform()
	var roof_fallback: Vector3 = vehicle.global_position + Vector3.UP * 1.95
	return exit_xform.origin.distance_squared_to(roof_fallback) < 0.0001


func _is_player_in_vehicle() -> bool:
	return player != null and player.has_method("is_in_vehicle") and player.is_in_vehicle()


func _get_player_camera() -> Camera3D:
	if player and player.has_method("get_camera"):
		return player.get_camera()
	return null


func _get_vehicle_camera() -> Camera3D:
	if vehicle and vehicle.has_method("get_camera"):
		return vehicle.get_camera()
	return null


func _is_interact_pressed(event: InputEvent) -> bool:
	if InputMap.has_action(&"interact"):
		return event.is_action_pressed(&"interact", false)
	if event is InputEventKey and event.pressed and not event.echo:
		return (event as InputEventKey).physical_keycode == KEY_E
	if event is InputEventJoypadButton and event.pressed:
		return (event as InputEventJoypadButton).button_index == JOY_BUTTON_Y
	return false


func _on_rifle_stance_changed(enabled: bool) -> void:
	if hud:
		hud.set_rifle_stance(enabled)


func _on_driver_state_changed(_active: bool) -> void:
	_sync_hud_mode()
