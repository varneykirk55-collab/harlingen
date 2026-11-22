extends CanvasLayer
## Owns navigation UI, waypoint state, and the full-map modal.

const MapView := preload("res://scenes/ui/navigation/map_view.gd")
const ATLAS := preload("res://assets/navigation/harlingen_map.png")
const CONFIG_PATH := "user://harlingen_navigation.cfg"
const MAP_ACTION := &"navigation_map"
const INK := Color("#e7f2ef")
const MUTED := Color("#9eb9b8")
const GOLD := Color("#edc886")
const MINT := Color("#66e4d3")
const PINK := Color("#f69dcd")

var mini: MapView
var full: MapView
var map_open := false
var destination_active := false
var destination := Vector2.ZERO
var destination_label := ""
var tracked_position := Vector2.ZERO
var tracked_heading := Vector2.UP
var tracking_vehicle := false
var map_bounds: Rect2
var markers: Array

var _world: Node3D
var _mini_hud: Control
var _mini_status: Label
var _mini_hint: Label
var _modal: Control
var _status: Label
var _position: Label
var _binding: Button
var _map_button := JOY_BUTTON_BACK
var _destination_center := Vector2.ZERO
var _destination_zoom := 1.0
var _zoom_anchor := Vector2.ZERO
var _anchor_offset := Vector2.ZERO
var _dragging := false
var _drag_distance := 0.0
var _saved_pause := false
var _saved_mouse := Input.MOUSE_MODE_VISIBLE
var _poi_cursor := -1

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 30
	_world = get_parent() as Node3D
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/navigation/map_index.json"))
	var edges: Array = data.bounds
	map_bounds = Rect2(Vector2(edges[0], edges[1]), Vector2(edges[2] - edges[0], edges[3] - edges[1]))
	markers = data.markers
	_build_interface()
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) == OK:
		_map_button = JOY_BUTTON_START if config.get_value("controls", "map_button", JOY_BUTTON_BACK) == JOY_BUTTON_START else JOY_BUTTON_BACK
	_apply_binding()

func _style(color: Color, stroke: Color = Color.TRANSPARENT, radius := 0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = stroke
	box.set_border_width_all(1)
	box.set_corner_radius_all(radius)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 7
	box.content_margin_bottom = 7
	return box

func _label(parent: Control, text: String, font_size: int, color := INK) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _button(parent: Control, text: String, callback: Callable, tint := INK) -> Button:
	var button := Button.new()
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 15)
	button.add_theme_color_override("font_color", tint)
	button.add_theme_stylebox_override("normal", _style(Color("#1a2c32"), Color("#30494e"), 4))
	button.add_theme_stylebox_override("hover", _style(Color("#2c454c"), Color("#5a8b8c"), 4))
	button.add_theme_stylebox_override("pressed", _style(Color("#38585c"), MINT, 4))
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _map(parent: Control, compact: bool) -> MapView:
	var view := MapView.new()
	view.name = "Minimap" if compact else "CityMap"
	view.atlas = ATLAS
	view.bounds = map_bounds
	view.markers = markers
	view.is_mini = compact
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE if compact else Control.MOUSE_FILTER_STOP
	view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	parent.add_child(view)
	return view

func _build_interface() -> void:
	_mini_hud = PanelContainer.new()
	(_mini_hud as PanelContainer).add_theme_stylebox_override("panel", _style(Color("#0d181deb"), Color("#375257"), 5))
	_mini_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_mini_hud)
	_mini_hud.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_mini_hud.offset_left = 24
	_mini_hud.offset_top = -250
	var mini_stack := VBoxContainer.new()
	mini_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mini_hud.add_child(mini_stack)
	mini = _map(mini_stack, true)
	mini.custom_minimum_size = Vector2(272, 202)
	var mini_bar := HBoxContainer.new()
	mini_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mini_stack.add_child(mini_bar)
	_mini_status = _label(mini_bar, "Harlingen", 14, INK)
	_mini_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mini_hint = _label(mini_bar, "M / View", 13, MUTED)

	_modal = PanelContainer.new()
	(_modal as PanelContainer).add_theme_stylebox_override("panel", _style(Color("#101c20")))
	add_child(_modal)
	_modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 11)
	_modal.add_child(layout)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	layout.add_child(top)
	var heading := VBoxContainer.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(heading)
	_label(heading, "Harlingen", 33)
	_position = _label(heading, "", 14, MUTED)
	_button(top, "−  Zoom out", func(): _request_zoom(1.0 / 1.5))
	_button(top, "+  Zoom in", func(): _request_zoom(1.5))
	_button(top, "Center player", _center_player)
	_button(top, "Close map", func(): set_map_open(false), MINT)

	var content := HBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(content)
	full = _map(content, false)
	full.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	full.size_flags_vertical = Control.SIZE_EXPAND_FILL
	full.gui_input.connect(_map_pointer_input)

	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 316
	side.add_theme_constant_override("separation", 7)
	content.add_child(side)
	_label(side, "Places & highway tests", 21)
	_label(side, "Select a place to mark it on the map.", 14, MUTED)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for marker: Dictionary in markers:
		var tint := GOLD if marker.category == "highway" else (MINT if marker.category == "street" else INK)
		var place := _button(list, marker.label, _select_marker.bind(marker), tint)
		place.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		place.tooltip_text = marker.label + ("
" + marker.detail if not marker.detail.is_empty() else "")

	_status = _label(side, "No waypoint selected", 15, PINK)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.y = 48
	_button(side, "Clear waypoint", clear_waypoint)
	_binding = _button(side, "", _toggle_binding, MUTED)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 20)
	layout.add_child(footer)
	_label(footer, "Drag / WASD / stick to pan   ·   Wheel / + − / LB RB to zoom", 15, MUTED)
	_label(footer, "Click / Enter / A to mark   ·   Right click / X to clear   ·   Tab / Y next place   ·   F / L3 center", 15, MUTED)
	_modal.hide()

func _toggle_binding() -> void:
	_map_button = JOY_BUTTON_START if _map_button == JOY_BUTTON_BACK else JOY_BUTTON_BACK
	_apply_binding()
	var config := ConfigFile.new()
	config.set_value("controls", "map_button", _map_button)
	var error := config.save(CONFIG_PATH)
	if error != OK:
		push_warning("Navigation binding could not be saved (%s)." % error)

func _apply_binding() -> void:
	# Keep keyboard and any project-defined bindings. Only replace the two
	# built-in controller choices exposed by this menu.
	for event in InputMap.action_get_events(MAP_ACTION):
		if event is InputEventJoypadButton and event.button_index in [JOY_BUTTON_BACK, JOY_BUTTON_START]:
			InputMap.action_erase_event(MAP_ACTION, event)
	var button := InputEventJoypadButton.new()
	button.button_index = _map_button
	InputMap.action_add_event(MAP_ACTION, button)
	_mini_hint.text = "M / View" if _map_button == JOY_BUTTON_BACK else "M / Menu"
	_binding.text = "Map button: %s   ·   Change with R3" % ("View / Select" if _map_button == JOY_BUTTON_BACK else "Menu / Start")

func _track_actor() -> void:
	tracking_vehicle = not _world.legacy_walker_mode and _world.vehicle_interaction.is_driving
	var actor: Node3D = _world.vehicle if tracking_vehicle else (_world.walker if _world.legacy_walker_mode else _world.player)
	var orientation: Node3D = actor
	if not tracking_vehicle:
		orientation = _world.walker.eyes if _world.legacy_walker_mode else _world.player.visual_root
	var actor_position := actor.global_position
	var facing := -orientation.global_basis.z
	tracked_position = Vector2(actor_position.x, actor_position.z)
	var flat := Vector2(facing.x, facing.z)
	if flat.length_squared() > 0.0001:
		tracked_heading = flat.normalized()

func _process(delta: float) -> void:
	_track_actor()
	_mini_hud.visible = not map_open and _world.walking and _world.show_hints
	if _mini_hud.visible:
		mini.center = tracked_position
		_update_view(mini)
		var status := "Harlingen"
		if destination_active:
			status = "Waypoint · " + _distance(tracked_position.distance_to(destination))
		if _mini_status.text != status:
			_mini_status.text = status
	if not map_open:
		return
	_update_full(delta)
	_update_view(full)
	_position.text = "%s   ·   %+.0f E   %+.0f S   ·   %.1f×" % [
		"In vehicle" if tracking_vehicle else "On foot", tracked_position.x, tracked_position.y, full.zoom]

func _update_view(view: MapView) -> void:
	view.actor = tracked_position
	view.heading = tracked_heading
	view.driving = tracking_vehicle
	view.waypoint_active = destination_active
	view.waypoint = destination
	view.queue_redraw()

func _distance(metres: float) -> String:
	return "%.1f km" % (metres / 1000.0) if metres >= 1000.0 else "%d m" % roundi(metres)

func _clamp_world(point: Vector2) -> Vector2:
	return point.clamp(map_bounds.position, map_bounds.end)

func set_map_open(open: bool) -> void:
	if map_open == open:
		return
	map_open = open
	_modal.visible = open
	_dragging = false
	if open:
		_saved_pause = get_tree().paused
		_saved_mouse = Input.mouse_mode
		get_tree().paused = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_track_actor()
		full.zoom = 1.0
		_destination_zoom = 1.0
		full.center = map_bounds.get_center()
		_destination_center = full.center
		_anchor_offset = Vector2.ZERO
		_update_view(full)
	else:
		get_tree().paused = _saved_pause
		Input.mouse_mode = _saved_mouse

func _exit_tree() -> void:
	if map_open:
		get_tree().paused = _saved_pause
		Input.mouse_mode = _saved_mouse

func set_waypoint(point: Vector2, label := "Custom waypoint") -> void:
	destination = _clamp_world(point)
	destination_active = true
	destination_label = label
	_status.text = "%s
%s from you" % [label, _distance(tracked_position.distance_to(destination))]

func clear_waypoint() -> void:
	destination_active = false
	destination_label = ""
	_status.text = "No waypoint selected"

func _select_marker(marker: Dictionary) -> void:
	_poi_cursor = markers.find(marker)
	var point := Vector2(marker.x, marker.z)
	set_waypoint(point, marker.label)
	_status.text = marker.label + ("
" + marker.detail if not marker.detail.is_empty() else "
" + _distance(tracked_position.distance_to(point)) + " from you")
	_focus(point, 4.0)

func _next_place() -> void:
	_select_marker(markers[(_poi_cursor + 1) % markers.size()])

func _focus(point: Vector2, scale: float) -> void:
	_anchor_offset = Vector2.ZERO
	_destination_zoom = maxf(scale, _destination_zoom)
	_destination_center = _clamp_world(point)

func _center_player() -> void:
	_focus(tracked_position, 3.0)

func _request_zoom(multiplier: float, screen_anchor := Vector2.INF) -> void:
	_destination_zoom = clampf(_destination_zoom * multiplier, 1.0, 30.0)
	_anchor_offset = Vector2.ZERO if screen_anchor == Vector2.INF else screen_anchor - full.size * 0.5
	_zoom_anchor = full.center + _anchor_offset / full.pixels_per_meter()
	_destination_center = full.center

func _update_full(delta: float) -> void:
	var pan := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if Input.is_physical_key_pressed(KEY_LEFT): pan.x -= 1.0
	if Input.is_physical_key_pressed(KEY_RIGHT): pan.x += 1.0
	if Input.is_physical_key_pressed(KEY_UP): pan.y -= 1.0
	if Input.is_physical_key_pressed(KEY_DOWN): pan.y += 1.0
	if pan.length_squared() > 0.01:
		_anchor_offset = Vector2.ZERO
		_destination_center = _clamp_world(_destination_center + pan.limit_length() * 730.0 * delta / full.pixels_per_meter())
	var weight := 1.0 - exp(-14.0 * delta)
	full.zoom = lerpf(full.zoom, _destination_zoom, weight)
	if not _anchor_offset.is_zero_approx():
		full.center = _clamp_world(_zoom_anchor - _anchor_offset / full.pixels_per_meter())
		_destination_center = full.center
	else:
		full.center = full.center.lerp(_destination_center, weight)

func _mark_screen_point(point: Vector2) -> void:
	var poi := full.marker_at(point)
	if not poi.is_empty():
		_select_marker(poi)
	else:
		var projected := full.screen_to_map(point)
		if map_bounds.grow(0.01).has_point(projected):
			set_waypoint(projected)

func _map_pointer_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				if event.pressed:
					_dragging = true
					_drag_distance = 0.0
					full.grab_click_focus()
				elif _dragging:
					_dragging = false
					if _drag_distance < 5.0:
						_mark_screen_point(event.position)
			MOUSE_BUTTON_RIGHT:
				if event.pressed:
					clear_waypoint()
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					_request_zoom(1.35 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.35, event.position)
		full.accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_drag_distance += event.relative.length()
		if _drag_distance >= 5.0:
			_anchor_offset = Vector2.ZERO
			_destination_center = _clamp_world(_destination_center - event.relative / full.pixels_per_meter())
		full.accept_event()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed(MAP_ACTION):
		set_map_open(not map_open)
		get_viewport().set_input_as_handled()
		return
	if not event.is_pressed() or event.is_echo():
		return
	if event is InputEventKey:
		match event.physical_keycode:
			KEY_MINUS, KEY_KP_SUBTRACT: _change_zoom(1.0 / 1.4)
			KEY_EQUAL, KEY_KP_ADD: _change_zoom(1.4)
			KEY_ESCAPE:
				if not map_open: return
				set_map_open(false)
			KEY_ENTER, KEY_KP_ENTER:
				if not map_open: return
				_mark_screen_point(full.size * 0.5)
			KEY_TAB:
				if not map_open: return
				_next_place()
			KEY_DELETE:
				if not map_open: return
				clear_waypoint()
			KEY_F:
				if not map_open: return
				_center_player()
			_: return
	elif event is InputEventJoypadButton:
		if not map_open:
			if _world.legacy_walker_mode: return
			if event.button_index == JOY_BUTTON_DPAD_UP:
				_change_zoom(1.4)
			elif event.button_index == JOY_BUTTON_DPAD_DOWN:
				_change_zoom(1.0 / 1.4)
			else:
				return
		else:
			match event.button_index:
				JOY_BUTTON_LEFT_SHOULDER: _request_zoom(1.0 / 1.4)
				JOY_BUTTON_RIGHT_SHOULDER: _request_zoom(1.4)
				JOY_BUTTON_A: _mark_screen_point(full.size * 0.5)
				JOY_BUTTON_X: clear_waypoint()
				JOY_BUTTON_B: set_map_open(false)
				JOY_BUTTON_Y: _next_place()
				JOY_BUTTON_LEFT_STICK: _center_player()
				JOY_BUTTON_RIGHT_STICK: _toggle_binding()
				_: return
	else:
		return
	get_viewport().set_input_as_handled()

func _change_zoom(factor: float) -> void:
	if map_open:
		_request_zoom(factor)
	elif not _world.legacy_walker_mode:
		mini.zoom = clampf(mini.zoom * factor, 0.55, 2.3)
