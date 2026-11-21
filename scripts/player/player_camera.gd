extends Node3D
class_name PlayerCameraRig
## Third-person follow camera rig (CameraPivot -> SpringArm3D -> PlayerCamera).

@export var pivot_height: float = 1.55
@export var default_spring_length: float = 3.2
@export var strafe_spring_length: float = 2.4
@export var strafe_shoulder_offset: float = 0.42
@export var min_pitch_deg: float = -65.0
@export var max_pitch_deg: float = 70.0
@export var mouse_sensitivity: float = 0.0024
@export var stick_sensitivity: float = 2.8
@export var stick_deadzone: float = 0.2
@export var default_fov: float = 70.0
@export var sprint_fov: float = 76.0
@export var strafe_fov: float = 62.0
@export var follow_lerp_speed: float = 12.0

@onready var spring_arm: SpringArm3D = $SpringArm3D
@onready var camera: Camera3D = $SpringArm3D/PlayerCamera

var _active: bool = false
var _pitch: float = deg_to_rad(-8.0)
var _yaw: float = PI


func _ready() -> void:
	position = Vector3(0.0, pivot_height, 0.0)
	if spring_arm:
		spring_arm.spring_length = default_spring_length
		spring_arm.rotation.x = _pitch
	if camera:
		camera.fov = default_fov
	rotation.y = _yaw


func setup(owner_body: PhysicsBody3D) -> void:
	if spring_arm and owner_body:
		spring_arm.add_excluded_object(owner_body.get_rid())


func set_active(active: bool) -> void:
	_active = active
	if active and camera:
		camera.make_current()


func set_yaw(yaw: float) -> void:
	_yaw = wrapf(yaw, -PI, PI)
	rotation.y = _yaw


func get_yaw() -> float:
	return _yaw


func set_pitch(pitch_rad: float) -> void:
	_pitch = clampf(pitch_rad, deg_to_rad(min_pitch_deg), deg_to_rad(max_pitch_deg))
	if spring_arm:
		spring_arm.rotation.x = _pitch


func reset_orientation(yaw: float = PI, pitch_deg: float = -8.0) -> void:
	set_yaw(yaw)
	set_pitch(deg_to_rad(pitch_deg))
	position = Vector3(0.0, pivot_height, 0.0)
	if spring_arm:
		spring_arm.spring_length = default_spring_length
	if camera:
		camera.fov = default_fov


func update_camera(delta: float, is_strafing: bool, is_sprinting: bool) -> void:
	if not _active:
		return

	var look_input := _get_look_stick_input()
	if look_input != Vector2.ZERO:
		_apply_look(look_input * stick_sensitivity * delta)

	var t := 1.0 - exp(-follow_lerp_speed * delta)
	var target_shoulder_x := strafe_shoulder_offset if is_strafing else 0.0
	position.x = lerpf(position.x, target_shoulder_x, t)
	position.y = lerpf(position.y, pivot_height, t)

	if spring_arm:
		var target_length := strafe_spring_length if is_strafing else default_spring_length
		spring_arm.spring_length = lerpf(spring_arm.spring_length, target_length, t)

	if camera:
		var target_fov := default_fov
		if is_strafing:
			target_fov = strafe_fov
		elif is_sprinting:
			target_fov = sprint_fov
		camera.fov = lerpf(camera.fov, target_fov, t)


func handle_input(event: InputEvent) -> bool:
	if not _active:
		return false
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		var rel := motion.screen_relative if motion.screen_relative != Vector2.ZERO else motion.relative
		_apply_look(rel * mouse_sensitivity)
		return true
	return false


func get_camera() -> Camera3D:
	return camera


func get_camera_global_transform() -> Transform3D:
	if camera:
		return camera.global_transform
	return global_transform


func _apply_look(angle: Vector2) -> void:
	_yaw = wrapf(_yaw - angle.x, -PI, PI)
	rotation.y = _yaw
	_pitch = clampf(_pitch - angle.y, deg_to_rad(min_pitch_deg), deg_to_rad(max_pitch_deg))
	if spring_arm:
		spring_arm.rotation.x = _pitch


func _get_look_stick_input() -> Vector2:
	if (
		InputMap.has_action("cam_left")
		and InputMap.has_action("cam_right")
		and InputMap.has_action("cam_up")
		and InputMap.has_action("cam_down")
	):
		var vec := Input.get_vector("cam_left", "cam_right", "cam_up", "cam_down", stick_deadzone)
		if vec != Vector2.ZERO:
			return vec

	var pads := Input.get_connected_joypads()
	if pads.is_empty():
		return Vector2.ZERO
	var axes := Vector2(
		Input.get_joy_axis(pads[0], JOY_AXIS_RIGHT_X),
		Input.get_joy_axis(pads[0], JOY_AXIS_RIGHT_Y)
	)
	var len_val := axes.length()
	if len_val <= stick_deadzone:
		return Vector2.ZERO
	var strength := inverse_lerp(stick_deadzone, 1.0, clampf(len_val, stick_deadzone, 1.0))
	return axes.normalized() * strength
