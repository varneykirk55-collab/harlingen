extends Node3D
## Ground exploration, flyover, and district streaming.

const BOOKMARKS := [
	[Vector3(424, 75, 493), Vector3(220, 19, 341), "Downtown / Jackson Avenue"],
	[Vector3(2586, 137, 1968), Vector3(2238, 12, 1647), "Arroyo Colorado"],
	[Vector3(3800, 350, -2700), Vector3(4460, 12, -3960), "Valley International Airport"],
	[Vector3(-8700, 10900, 7990), Vector3(0, 0, 0), "12 × 12 km overview"]
]
const TILE_SIZE := 2000.0
@onready var camera: Camera3D = $Camera
@onready var walker = $Walker
@onready var terrain: Terrain3D = $Terrain3D
@onready var hint: Label = $Overlay/Hint
var loaded: Dictionary = {}
var tile_rows: Array
var countdown := 0.0
var native_terrain := true
var show_hints := true
var speed := 45.0
var walking := false

func _ready() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://manifest.json"))
	tile_rows = manifest.tiles
	native_terrain = terrain.data.get_regions_active().size() == 100
	if "--mesh-ground" in OS.get_cmdline_user_args():
		native_terrain = false
	_apply_ground_mode()
	walker.speed_changed.connect(_show_walk_controls)
	camera.position = BOOKMARKS[0][0]
	camera.look_at(BOOKMARKS[0][1])
	var starting_view := -1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--view="):
			starting_view = clampi(arg.get_slice("=", 1).to_int(), 1, BOOKMARKS.size()) - 1
		if arg == "--hide-hud":
			show_hints = false
			$Overlay.visible = false
	if starting_view < 0:
		_set_walking(true)
	else:
		_bookmark(starting_view)

func _bookmark(index: int) -> void:
	camera.position = BOOKMARKS[index][0]
	camera.look_at(BOOKMARKS[index][1])
	_set_walking(false, BOOKMARKS[index][2])

func _set_walking(active: bool, fly_label := "Flyover") -> void:
	walking = active
	walker.set_active(active)
	var view: Camera3D = walker.eyes if active else camera
	view.make_current()
	terrain.set_camera(view)
	terrain.set_clipmap_target(view)
	terrain.set_collision_target(view)
	_update_tiles(not active and camera.position.y > 1200)
	if active:
		_show_walk_controls()
	else:
		hint.text = "%s\nWASD fly  ·  R/F rise and descend  ·  Right mouse look  ·  Shift speed\n1–4 views  ·  Wheel speed  ·  F7 walk  ·  F8 terrain  ·  F9 overlay" % fly_label

func _show_walk_controls() -> void:
	hint.text = "Walk   %.2f×\nWASD + mouse or left/right sticks  ·  Space/A jump\nWheel, +/− or D-pad ↑/↓ speed  ·  F7 fly  ·  Home respawn  ·  Esc release mouse\nF8 terrain  ·  F9 overlay" % walker.speed_multiplier

func _apply_ground_mode() -> void:
	terrain.visible = native_terrain
	terrain.collision_mode = 1 if native_terrain else 0

func _update_tiles(overview: bool) -> void:
	var view: Camera3D = walker.eyes if walking else camera
	var position_3d := view.global_position
	var center := Vector2(position_3d.x, position_3d.z)
	$WorldEnvironment.environment.fog_density = lerpf(0.000073, 0.000016, smoothstep(510.0, 4200.0, position_3d.y))
	var radius := clampf(2300.0 + position_3d.y * 12.0,2300.0,6000.0)
	for row: Dictionary in tile_rows:
		var origin := Vector2(row.x, row.z)
		var nearest := center.clamp(origin,origin + Vector2.ONE * TILE_SIZE)
		var distance := nearest.distance_to(center)
		var key: String = row.id
		if overview or distance < radius:
			if not loaded.has(key):
				var scene := load("res://tiles/%s/district.tscn" % key) as PackedScene
				var tile := scene.instantiate()
				$Districts.add_child(tile)
				loaded[key] = tile
			loaded[key].update_detail(native_terrain, distance < 1700 and position_3d.y < 510,
				distance < 520 and position_3d.y < 290, distance < 400 and position_3d.y < 135)
		elif loaded.has(key) and distance > radius+380:
			loaded[key].queue_free()
			loaded.erase(key)

func _process(delta: float) -> void:
	countdown -= delta
	if countdown <= 0:
		countdown = 0.27
		_update_tiles(not walking and camera.position.y > 1200)
	if walking:
		return
	var input := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W): input.z -= 1
	if Input.is_physical_key_pressed(KEY_S): input.z += 1
	if Input.is_physical_key_pressed(KEY_A): input.x -= 1
	if Input.is_physical_key_pressed(KEY_D): input.x += 1
	if Input.is_physical_key_pressed(KEY_R): input.y += 1
	if Input.is_physical_key_pressed(KEY_F): input.y -= 1
	if input != Vector3.ZERO:
		var velocity := camera.basis * Vector3(input.x,0,input.z) + Vector3.UP * input.y
		camera.position += velocity.normalized() * speed * delta * (4 if Input.is_physical_key_pressed(KEY_SHIFT) else 1)
		camera.position.y = clampf(camera.position.y, 2, 11500)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode >= KEY_1 and event.physical_keycode <= KEY_4:
			_bookmark(event.physical_keycode - KEY_1)
		elif event.physical_keycode == KEY_F7:
			_set_walking(not walking)
		elif event.physical_keycode == KEY_F8:
			native_terrain = not native_terrain and terrain.data.get_regions_active().size() == 100
			for tile: Node3D in loaded.values():
				tile.update_detail(native_terrain, false, false, false)
			_apply_ground_mode()
			_update_tiles(not walking and camera.position.y > 1200)
		elif event.physical_keycode == KEY_F9:
			show_hints = not show_hints
			$Overlay.visible = show_hints
	if walking:
		walker.handle_input(event)
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if event.pressed else Input.MOUSE_MODE_VISIBLE
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			speed = minf(speed * 1.34, 1800)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			speed = maxf(speed / 1.34, 5)
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		camera.rotation.y -= event.relative.x * 0.003
		camera.rotation.x = clampf(camera.rotation.x - event.relative.y * 0.003, -1.55, 1.55)
