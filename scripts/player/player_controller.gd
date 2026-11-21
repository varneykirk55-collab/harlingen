extends CharacterBody3D
class_name PlayerController
## Third-person player character controller for Harlingen with AnimationTree locomotion & actions.

signal animation_state_changed(state_name: String)
signal rifle_stance_changed(enabled: bool)

const SPAWN := Vector3(205.0, 12.35, 320.0)
const STICK_DEADZONE := 0.2
const LOOPING_ANIMS := [
	&"Idle",
	&"Walking",
	&"FastRun",
	&"Strafing",
	&"WalkWithRifle",
]
const ONESHOT_ANIMS := [
	&"Punching",
	&"Reloading",
]
const ALL_ANIM_STATES := [
	"Idle",
	"Walking",
	"FastRun",
	"Strafing",
	"Punching",
	"WalkWithRifle",
	"Reloading",
]

@export_group("Movement")
@export var walk_speed: float = 3.8
@export var run_speed: float = 7.6
@export var strafe_speed: float = 3.4
@export var rifle_walk_speed: float = 3.2
@export var jump_velocity: float = 4.8
@export var ground_accel: float = 14.0
@export var ground_decel: float = 16.0
@export var air_accel: float = 5.0
@export var turn_speed: float = 12.0
@export var strafe_turn_speed: float = 18.0

@export_group("Animation")
@export var blend_smooth_speed: float = 10.0

@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var visual_root: Node3D = $VisualRoot
@onready var camera_pivot: PlayerCameraRig = $CameraPivot
@onready var animation_tree: AnimationTree = $AnimationTree

var _active: bool = false
var _in_vehicle: bool = false
var _current_vehicle: Node3D = null
var _default_collision_layer: int = 2
var _default_collision_mask: int = 5

var _rifle_stance: bool = false
var _jump_requested: bool = false
var _punch_requested: bool = false
var _reload_requested: bool = false
var _action_state: String = ""
var _action_timer: float = 0.0
var _locomotion_blend: float = 0.0
var _rifle_blend: float = 0.0
var _last_logical_state: String = "Idle"
var _last_handled_event: InputEvent = null
var _suppressed_poll_actions: Dictionary = {}
var _mouse_capture_frame: int = -10

var _anim_player: AnimationPlayer = null
var _state_playback: AnimationNodeStateMachinePlayback = null


func _ready() -> void:
	_default_collision_layer = collision_layer
	_default_collision_mask = collision_mask
	floor_snap_length = 0.4
	floor_max_angle = deg_to_rad(50.0)
	floor_stop_on_slope = true
	floor_constant_speed = true

	if camera_pivot:
		camera_pivot.setup(self)

	_setup_animation_tree()
	set_active(false)
	respawn()


func _setup_animation_tree() -> void:
	_anim_player = _find_animation_player(visual_root)
	if _anim_player:
		for anim_name in LOOPING_ANIMS:
			if _anim_player.has_animation(anim_name):
				_anim_player.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
		for anim_name in ONESHOT_ANIMS:
			if _anim_player.has_animation(anim_name):
				_anim_player.get_animation(anim_name).loop_mode = Animation.LOOP_NONE
	if animation_tree:
		if _anim_player:
			animation_tree.anim_player = animation_tree.get_path_to(_anim_player)
		animation_tree.active = true
		_state_playback = animation_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
		if _state_playback:
			_state_playback.start("Locomotion")
		animation_tree.advance(0.0)


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node == null:
		return null
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found:
			return found
	return null


func respawn() -> void:
	global_position = SPAWN
	velocity = Vector3.ZERO
	_jump_requested = false
	_punch_requested = false
	_reload_requested = false
	_action_state = ""
	_action_timer = 0.0
	_locomotion_blend = 0.0
	_rifle_blend = 0.0
	if visual_root:
		visual_root.rotation.y = PI
	if camera_pivot:
		camera_pivot.reset_orientation(PI, -8.0)
	_reset_animation_to_idle()


func set_active(active: bool) -> void:
	_active = active
	if not active:
		velocity = Vector3.ZERO
		_jump_requested = false
		_punch_requested = false
		_reload_requested = false
		_action_state = ""
		_action_timer = 0.0
	set_physics_process(active and not _in_vehicle)
	set_process(active and not _in_vehicle)
	set_process_unhandled_input(active and not _in_vehicle)
	if camera_pivot:
		camera_pivot.set_active(active and not _in_vehicle)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if (active and not _in_vehicle) else Input.MOUSE_MODE_VISIBLE


func set_in_vehicle(in_vehicle: bool, vehicle_node: Node3D = null) -> void:
	_in_vehicle = in_vehicle
	if in_vehicle:
		_current_vehicle = vehicle_node
		_action_state = ""
		_action_timer = 0.0
		velocity = Vector3.ZERO
		visible = false
		collision_layer = 0
		collision_mask = 0
		if collision_shape:
			collision_shape.disabled = true
		set_active(false)
		return

	var prev_vehicle := vehicle_node if vehicle_node != null else _current_vehicle
	_current_vehicle = null
	var exit_transform := global_transform
	if prev_vehicle != null:
		if prev_vehicle.has_method("find_safe_exit_transform"):
			var cap_radius := 0.32
			var cap_height := 1.78
			if collision_shape and collision_shape.shape is CapsuleShape3D:
				var cap := collision_shape.shape as CapsuleShape3D
				cap_radius = cap.radius
				cap_height = cap.height
			exit_transform = prev_vehicle.find_safe_exit_transform(cap_radius, cap_height)
		else:
			exit_transform = Transform3D(
				prev_vehicle.global_transform.basis,
				prev_vehicle.global_position - prev_vehicle.global_transform.basis.x * 2.2 + Vector3(0.0, 0.2, 0.0)
			)

	global_position = exit_transform.origin
	velocity = Vector3.ZERO
	visible = true
	collision_layer = _default_collision_layer
	collision_mask = _default_collision_mask
	if collision_shape:
		collision_shape.disabled = false

	var forward := -exit_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() > 0.0001:
		var yaw := atan2(-forward.x, -forward.z)
		if visual_root:
			visual_root.rotation.y = yaw
		set_camera_yaw(yaw)

	_reset_animation_to_idle()
	set_active(true)


func get_camera() -> Camera3D:
	if camera_pivot:
		return camera_pivot.get_camera()
	return null


func get_camera_global_transform() -> Transform3D:
	if camera_pivot:
		return camera_pivot.get_camera_global_transform()
	return global_transform


func set_camera_yaw(yaw: float) -> void:
	if camera_pivot:
		camera_pivot.set_yaw(yaw)


func get_animation_states() -> Array:
	return ALL_ANIM_STATES.duplicate()


func get_current_animation_state() -> String:
	return _last_logical_state


func get_state_machine_node() -> String:
	if _state_playback:
		return String(_state_playback.get_current_node())
	return ""


func is_rifle_stance() -> bool:
	return _rifle_stance


func is_in_vehicle() -> bool:
	return _in_vehicle


func _physics_process(delta: float) -> void:
	_poll_action_inputs()

	var move_input := _get_move_input()
	var is_strafing_held := _is_strafe_held()
	var wants_sprint := _is_sprint_held() and not is_strafing_held and not _rifle_stance and move_input.length() > 0.1

	# One-shot actions
	if _punch_requested and _action_state == "":
		_start_one_shot_action("Punching")
	elif _reload_requested and _action_state == "":
		_start_one_shot_action("Reloading")
	_punch_requested = false
	_reload_requested = false

	if _action_state != "":
		_action_timer -= delta
		if _action_timer <= 0.0:
			_action_state = ""

	# Camera-relative horizontal movement direction
	var cam_yaw := camera_pivot.get_yaw() if camera_pivot else PI
	var cam_basis := Basis(Vector3.UP, cam_yaw)
	var move_dir := (cam_basis * Vector3(move_input.x, 0.0, move_input.y))
	move_dir.y = 0.0
	if move_dir.length_squared() > 1.0:
		move_dir = move_dir.normalized()

	var target_speed := walk_speed
	if _action_state == "Punching":
		target_speed = 0.0
		move_dir = Vector3.ZERO
	elif _action_state == "Reloading":
		target_speed = rifle_walk_speed if _rifle_stance else walk_speed * 0.75
	elif is_strafing_held:
		target_speed = strafe_speed
	elif _rifle_stance:
		target_speed = rifle_walk_speed
	elif wants_sprint:
		target_speed = run_speed

	var desired_horiz := move_dir * target_speed
	var current_horiz := Vector3(velocity.x, 0.0, velocity.z)
	var accel_rate := ground_accel if move_dir.length_squared() > 0.001 else ground_decel
	if not is_on_floor():
		accel_rate = air_accel
	current_horiz = current_horiz.move_toward(desired_horiz, accel_rate * delta)
	velocity.x = current_horiz.x
	velocity.z = current_horiz.z

	# Gravity & jump
	if not is_on_floor():
		velocity += get_gravity() * delta
	if _jump_requested and is_on_floor() and _action_state != "Punching":
		velocity.y = jump_velocity
	_jump_requested = false

	move_and_slide()

	if global_position.y < -15.0:
		respawn()
		return

	# Character facing rotation
	if visual_root:
		if is_strafing_held:
			visual_root.rotation.y = lerp_angle(visual_root.rotation.y, cam_yaw, 1.0 - exp(-strafe_turn_speed * delta))
		elif current_horiz.length() > 0.2 and _action_state != "Punching":
			var target_yaw := atan2(-current_horiz.x, -current_horiz.z)
			visual_root.rotation.y = lerp_angle(visual_root.rotation.y, target_yaw, 1.0 - exp(-turn_speed * delta))

	_update_animation_state(delta, current_horiz.length(), move_input, is_strafing_held)


func _process(delta: float) -> void:
	if camera_pivot:
		var is_strafing := _is_strafe_held()
		var horiz_speed := Vector2(velocity.x, velocity.z).length()
		var is_sprinting := _is_sprint_held() and not is_strafing and not _rifle_stance and horiz_speed > walk_speed + 0.5
		camera_pivot.update_camera(delta, is_strafing, is_sprinting)


func _unhandled_input(event: InputEvent) -> void:
	_process_input_event(event)


func handle_input(event: InputEvent) -> void:
	_process_input_event(event)


func _process_input_event(event: InputEvent) -> void:
	if not _active or _in_vehicle:
		return
	if event == _last_handled_event:
		return
	_last_handled_event = event

	if camera_pivot and camera_pivot.handle_input(event):
		return

	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
			if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
				_mouse_capture_frame = Engine.get_physics_frames()
				return

	if event is InputEventKey and event.pressed and not event.echo:
		var key_ev := event as InputEventKey
		match key_ev.physical_keycode:
			KEY_ESCAPE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				return
			KEY_HOME:
				respawn()
				return

	if _event_matches_action(event, "jump", KEY_SPACE, JOY_BUTTON_A):
		_jump_requested = true
		_suppressed_poll_actions["jump"] = true
	if _event_matches_action(event, "action_punch", KEY_F, JOY_BUTTON_X):
		_punch_requested = true
		_suppressed_poll_actions["action_punch"] = true
	if _event_matches_action(event, "action_reload", KEY_R, JOY_BUTTON_DPAD_LEFT):
		_reload_requested = true
		_suppressed_poll_actions["action_reload"] = true
	if _event_matches_action(event, "action_rifle_stance", KEY_Q, JOY_BUTTON_DPAD_RIGHT):
		_toggle_rifle_stance()
		_suppressed_poll_actions["action_rifle_stance"] = true


func _poll_action_inputs() -> void:
	for action_name in _suppressed_poll_actions.keys():
		if not InputMap.has_action(action_name) or not Input.is_action_pressed(action_name):
			_suppressed_poll_actions.erase(action_name)

	if not _suppressed_poll_actions.has("jump") and InputMap.has_action("jump") and Input.is_action_just_pressed("jump"):
		_jump_requested = true
	if (
		not _suppressed_poll_actions.has("action_punch")
		and InputMap.has_action("action_punch")
		and Input.is_action_just_pressed("action_punch")
		and Engine.get_physics_frames() - _mouse_capture_frame > 1
	):
		_punch_requested = true
	if not _suppressed_poll_actions.has("action_reload") and InputMap.has_action("action_reload") and Input.is_action_just_pressed("action_reload"):
		_reload_requested = true
	if not _suppressed_poll_actions.has("action_rifle_stance") and InputMap.has_action("action_rifle_stance") and Input.is_action_just_pressed("action_rifle_stance"):
		_toggle_rifle_stance()


func _toggle_rifle_stance() -> void:
	_rifle_stance = not _rifle_stance
	rifle_stance_changed.emit(_rifle_stance)


func _start_one_shot_action(state_name: String) -> void:
	_action_state = state_name
	var anim_len := 1.0
	if _anim_player and _anim_player.has_animation(state_name):
		anim_len = _anim_player.get_animation(state_name).length
	_action_timer = maxf(anim_len - 0.18, 0.2)
	if _state_playback:
		_state_playback.travel(state_name)
	_set_logical_state(state_name)


func _reset_animation_to_idle() -> void:
	_locomotion_blend = 0.0
	_rifle_blend = 0.0
	if animation_tree:
		animation_tree.set("parameters/Locomotion/blend_position", 0.0)
		animation_tree.set("parameters/RifleLocomotion/blend_position", 0.0)
		if _state_playback:
			_state_playback.start("RifleLocomotion" if _rifle_stance else "Locomotion")
		animation_tree.advance(0.0)
	_set_logical_state("Idle")


func _update_animation_state(delta: float, horiz_speed: float, move_input: Vector2, is_strafing_held: bool) -> void:
	if not animation_tree or not _state_playback:
		return

	var smooth_t := 1.0 - exp(-blend_smooth_speed * delta)

	# Compute target locomotion blend values
	var target_loco := 0.0
	if horiz_speed > 0.15:
		if horiz_speed <= walk_speed + 0.35:
			target_loco = clampf(horiz_speed / walk_speed, 0.0, 1.0)
		else:
			target_loco = 1.0 + clampf((horiz_speed - walk_speed) / maxf(run_speed - walk_speed, 0.1), 0.0, 1.0)
	_locomotion_blend = lerpf(_locomotion_blend, target_loco, smooth_t)
	animation_tree.set("parameters/Locomotion/blend_position", _locomotion_blend)

	var target_rifle := clampf(horiz_speed / maxf(rifle_walk_speed, 0.1), 0.0, 1.0) if horiz_speed > 0.15 else 0.0
	_rifle_blend = lerpf(_rifle_blend, target_rifle, smooth_t)
	animation_tree.set("parameters/RifleLocomotion/blend_position", _rifle_blend)

	if _action_state != "":
		_set_logical_state(_action_state)
		return

	var lateral_strafing := is_strafing_held and horiz_speed > 0.25 and absf(move_input.x) > 0.15
	if lateral_strafing:
		if _state_playback.get_current_node() != "Strafing":
			_state_playback.travel("Strafing")
		_set_logical_state("Strafing")
	elif _rifle_stance:
		if _state_playback.get_current_node() != "RifleLocomotion":
			_state_playback.travel("RifleLocomotion")
		_set_logical_state("WalkWithRifle" if horiz_speed > 0.35 else "Idle")
	else:
		if _state_playback.get_current_node() != "Locomotion":
			_state_playback.travel("Locomotion")
		if horiz_speed <= 0.35:
			_set_logical_state("Idle")
		elif horiz_speed <= walk_speed + 1.1:
			_set_logical_state("Walking")
		else:
			_set_logical_state("FastRun")


func _set_logical_state(state_name: String) -> void:
	if state_name != _last_logical_state:
		_last_logical_state = state_name
		animation_state_changed.emit(state_name)


func _get_move_input() -> Vector2:
	if (
		InputMap.has_action("move_left")
		and InputMap.has_action("move_right")
		and InputMap.has_action("move_forward")
		and InputMap.has_action("move_back")
	):
		var vec := Input.get_vector("move_left", "move_right", "move_forward", "move_back", STICK_DEADZONE)
		return vec.limit_length(1.0)

	var move := Vector2(
		float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT))
		- float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),
		float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN))
		- float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP))
	)
	var pads := Input.get_connected_joypads()
	if not pads.is_empty():
		var axes := Vector2(
			Input.get_joy_axis(pads[0], JOY_AXIS_LEFT_X),
			Input.get_joy_axis(pads[0], JOY_AXIS_LEFT_Y)
		)
		var len_val := axes.length()
		if len_val > STICK_DEADZONE:
			var strength := inverse_lerp(STICK_DEADZONE, 1.0, clampf(len_val, STICK_DEADZONE, 1.0))
			move += axes.normalized() * strength
	return move.limit_length(1.0)


func _is_sprint_held() -> bool:
	if InputMap.has_action("sprint"):
		return Input.is_action_pressed("sprint")
	if Input.is_physical_key_pressed(KEY_SHIFT):
		return true
	var pads := Input.get_connected_joypads()
	if not pads.is_empty() and Input.is_joy_button_pressed(pads[0], JOY_BUTTON_LEFT_STICK):
		return true
	return false


func _is_strafe_held() -> bool:
	if InputMap.has_action("action_strafe"):
		return Input.is_action_pressed("action_strafe")
	if Input.is_physical_key_pressed(KEY_C):
		return true
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		return true
	var pads := Input.get_connected_joypads()
	if not pads.is_empty() and Input.is_joy_button_pressed(pads[0], JOY_BUTTON_LEFT_SHOULDER):
		return true
	return false


func _event_matches_action(event: InputEvent, action: StringName, fallback_key: Key, fallback_joy_button: JoyButton) -> bool:
	if InputMap.has_action(action):
		return event.is_action_pressed(action, false)
	if event is InputEventKey and event.pressed and not event.echo:
		return (event as InputEventKey).physical_keycode == fallback_key
	if event is InputEventJoypadButton and event.pressed and fallback_joy_button != JOY_BUTTON_INVALID:
		return (event as InputEventJoypadButton).button_index == fallback_joy_button
	return false
