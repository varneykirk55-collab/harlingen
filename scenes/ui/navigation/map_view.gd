extends Control
## North-up map view. World X goes right and world Z goes down.

const INK := Color("#e7f2ef")
const MUTED := Color("#9eb9b8")
const GOLD := Color("#edc886")
const MINT := Color("#66e4d3")
const PINK := Color("#f69dcd")
const BORDER := Color("#4a686c")
const BACKGROUND := Color("#101c20")

var atlas: Texture2D
var bounds: Rect2
var markers: Array
var center := Vector2.ZERO
var zoom := 1.0
var is_mini := false
var actor := Vector2.ZERO
var heading := Vector2.UP
var driving := false
var waypoint_active := false
var waypoint := Vector2.ZERO

func pixels_per_meter() -> float:
	var screen_span := minf(size.x, size.y)
	return maxf(1.0, screen_span) * zoom / (365.0 if is_mini else maxf(bounds.size.x, bounds.size.y) * 1.055)

func map_to_screen(point: Vector2) -> Vector2:
	return size * 0.5 + (point - center) * pixels_per_meter()

func screen_to_map(point: Vector2) -> Vector2:
	return center + (point - size * 0.5) / pixels_per_meter()

func marker_at(point: Vector2) -> Dictionary:
	var best := 14.0
	var result: Dictionary = {}
	for marker: Dictionary in markers:
		if not shows_marker(marker):
			continue
		var distance := map_to_screen(Vector2(marker.x, marker.z)).distance_to(point)
		if distance < best:
			best = distance
			result = marker
	return result

func shows_marker(marker: Dictionary) -> bool:
	return is_mini or zoom > 2.25 or marker.category == "landmark" or marker.id in ["i2", "i69", "big-split", "ed-carey", "jackson"]

func _draw() -> void:
	if atlas == null or minf(size.x, size.y) < 40.0:
		return
	var viewport := Rect2(Vector2.ZERO, size)
	draw_rect(viewport, BACKGROUND)
	var whole := Rect2(map_to_screen(bounds.position), bounds.size * pixels_per_meter())
	var visible_map := whole.intersection(viewport)
	if visible_map.has_area():
		var ratio := atlas.get_size() / whole.size
		draw_texture_rect_region(atlas, visible_map, Rect2(
			(visible_map.position - whole.position) * ratio, visible_map.size * ratio))
	_draw_markers(viewport.grow(-14))
	if waypoint_active:
		_draw_waypoint(viewport.grow(-17))
	_draw_actor(viewport.grow(-15))
	if not is_mini:
		var reticle := size * 0.5
		for direction: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.RIGHT, Vector2.LEFT]:
			draw_line(reticle + direction * 5, reticle + direction * 13, MUTED, 1.2, true)
		draw_circle(reticle, 1.3, INK)
	_draw_scale()
	draw_rect(viewport.grow(-0.5), BORDER, false, 1.0)
	draw_string(ThemeDB.fallback_font, Vector2(size.x - 26, 22), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, INK)
	draw_line(Vector2(size.x - 21, 30), Vector2(size.x - 21, 40), MUTED, 1.4, true)
	draw_colored_polygon(PackedVector2Array([Vector2(size.x - 21, 26), Vector2(size.x - 25, 34), Vector2(size.x - 17, 34)]), MINT)

func _draw_markers(area: Rect2) -> void:
	var labels: Array[Rect2] = []
	var font := ThemeDB.fallback_font
	for marker: Dictionary in markers:
		if not shows_marker(marker):
			continue
		var p := map_to_screen(Vector2(marker.x, marker.z))
		if not area.has_point(p):
			continue
		var tint := GOLD if marker.category == "highway" else (MINT if marker.category == "street" else INK)
		var radius := 3.3 if is_mini else 4.8
		draw_circle(p, radius + 2.2, BACKGROUND, true, -1, true)
		draw_circle(p, radius, tint, true, -1, true)
		if is_mini or (zoom < 1.85 and marker.id not in ["i2", "i69", "big-split", "ed-carey", "jackson"] and marker.category != "landmark"):
			continue
		var label: String = marker.label
		var dimensions := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
		var origin := p + Vector2(10, -10)
		if origin.x + dimensions.x + 8 > area.end.x:
			origin.x = p.x - dimensions.x - 14
		var box := Rect2(origin - Vector2(3, 1), dimensions + Vector2(8, 3))
		if not area.encloses(box) or labels.any(func(other: Rect2) -> bool: return other.intersects(box)):
			continue
		labels.append(box)
		draw_rect(box, Color("#152326ee"))
		draw_string(font, origin + Vector2(0, font.get_ascent(14)), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, tint)

func _edge_point(point: Vector2, area: Rect2) -> Vector2:
	var middle := area.get_center()
	var delta := point - middle
	var x_factor := area.size.x * 0.5 / maxf(0.01, absf(delta.x))
	var y_factor := area.size.y * 0.5 / maxf(0.01, absf(delta.y))
	return middle + delta * minf(1.0, minf(x_factor, y_factor))

func _draw_waypoint(area: Rect2) -> void:
	var point := map_to_screen(waypoint)
	if not area.has_point(point):
		if not is_mini:
			return
		var edge := _edge_point(point, area)
		_arrow(edge, (point - edge).normalized(), 7, PINK)
		return
	draw_circle(point, 9, BACKGROUND, true, -1, true)
	draw_colored_polygon(PackedVector2Array([
		point + Vector2.UP * 7, point + Vector2.RIGHT * 6,
		point + Vector2.DOWN * 7, point + Vector2.LEFT * 6]), PINK)

func _draw_actor(area: Rect2) -> void:
	var point := map_to_screen(actor)
	if not area.has_point(point):
		if not is_mini:
			var edge := _edge_point(point, area)
			_arrow(edge, (point - edge).normalized(), 8, MINT)
		return
	draw_circle(point, 14 if driving else 12, Color("#101d22ed"), true, -1, true)
	_arrow(point, heading, 10 if driving else 9, MINT if driving else INK)

func _arrow(at: Vector2, direction: Vector2, length: float, color: Color) -> void:
	var side := direction.orthogonal()
	var points := PackedVector2Array([
		at + direction * length, at - direction * length * 0.58 + side * length * 0.58,
		at - direction * length * 0.25, at - direction * length * 0.58 - side * length * 0.58])
	draw_colored_polygon(points, color)
	points.append(points[0])
	draw_polyline(points, BACKGROUND, 1.6, true)

func _draw_scale() -> void:
	var scale := pixels_per_meter()
	var distance := 25.0
	for candidate: float in [25.0, 50.0, 100.0, 200.0, 500.0, 1000.0, 2000.0, 5000.0]:
		if candidate * scale <= 96.0:
			distance = candidate
	var length := distance * scale
	var left := Vector2(14, size.y - 13)
	draw_rect(Rect2(left - Vector2(5, 21), Vector2(maxf(length + 11, 62), 29)), Color("#0b171cdd"))
	draw_line(left, left + Vector2(length, 0), INK, 1.5, true)
	draw_line(left - Vector2(0, 4), left, INK, 1.5, true)
	draw_line(left + Vector2(length, -4), left + Vector2(length, 0), INK, 1.5, true)
	var text := "%d km" % int(distance / 1000) if distance >= 1000 else "%d m" % int(distance)
	draw_string(ThemeDB.fallback_font, left - Vector2(0, 7), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, INK)
