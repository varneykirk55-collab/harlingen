extends CharacterBody3D
## First-person exploration on Harlingen's streamed collision geometry.

signal speed_changed

const WALK_SPEED := 4.0
const SPEED_STEP := 0.25
const SPAWN := Vector3(205.0, 12.35, 320.0)
const STICK_DEAD_ZONE := 0.2

@onready var eyes: Camera3D = $Eyes

var speed_multiplier := 1.0
var _jump_requested := false

func _ready() -> void:
	floor_snap_length = 0.4
	floor_max_angle = deg_to_rad(50.0)
	floor_stop_on_slope = true
	floor_constant_speed = true
	set_physics_process(false)
	respawn()

func respawn() -> void:
	global_position = SPAWN
	rotation.y = PI
	eyes.rotation.x = 0.0
	velocity = Vector3.ZERO
	_jump_requested = false

func set_active(active: bool) -> void:
	velocity = Vector3.ZERO
	_jump_requested = false
	set_physics_process(active)
	if active:
		eyes.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if active else Input.MOUSE_MODE_VISIBLE

func adjust_speed(steps: int) -> void:
	var next_speed := clampf(speed_multiplier + SPEED_STEP * steps, 1.0, 4.0)
	if next_speed != speed_multiplier:
		speed_multiplier = next_speed
		speed_changed.emit()

func _physics_process(delta: float) -> void:
	var move := Vector2(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))
	)
	var pads := Input.get_connected_joypads()
	if not pads.is_empty():
		move += _stick(pads[0], JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y)

	var direction := move.limit_length()
	var horizontal := basis * Vector3(direction.x, 0.0, direction.y) * WALK_SPEED * speed_multiplier
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if not is_on_floor():
		velocity += get_gravity() * delta
	if _jump_requested and is_on_floor():
		velocity.y = 4.5
	_jump_requested = false
	move_and_slide()
	if global_position.y < -15.0:
		respawn()

func _process(delta: float) -> void:
	if not is_physics_processing():
		return
	var pads := Input.get_connected_joypads()
	if not pads.is_empty():
		_look(_stick(pads[0], JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y) * 2.75 * delta)

func handle_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_ESCAPE: Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			KEY_EQUAL, KEY_KP_ADD: adjust_speed(1)
			KEY_MINUS, KEY_KP_SUBTRACT: adjust_speed(-1)
			KEY_SPACE: _jump_requested = true
			KEY_HOME: respawn()
	elif event is InputEventJoypadButton and event.pressed:
		match event.button_index:
			JOY_BUTTON_A: _jump_requested = true
			JOY_BUTTON_DPAD_UP: adjust_speed(1)
			JOY_BUTTON_DPAD_DOWN: adjust_speed(-1)
	elif event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT: Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			MOUSE_BUTTON_WHEEL_UP: adjust_speed(1)
			MOUSE_BUTTON_WHEEL_DOWN: adjust_speed(-1)
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_look(event.screen_relative * 0.0024)

func _look(angle: Vector2) -> void:
	rotation.y = wrapf(rotation.y - angle.x, -PI, PI)
	eyes.rotation.x = clampf(eyes.rotation.x - angle.y, deg_to_rad(-88.0), deg_to_rad(88.0))

func _stick(device: int, x: JoyAxis, y: JoyAxis) -> Vector2:
	var axes := Vector2(Input.get_joy_axis(device, x), Input.get_joy_axis(device, y))
	var strength := inverse_lerp(STICK_DEAD_ZONE, 1.0, clampf(axes.length(), STICK_DEAD_ZONE, 1.0))
	return axes.normalized() * strength
