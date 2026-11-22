extends RefCounted
## Collision proxies are fitted in the source mesh's local metres, then placed
## with the same transform as the visible instance. Foliage and road paint are omitted.

const WORLD := 1
const CELL_SIZE := 128.0
# Round profiles: radius, local bottom and top, and optional X/Z center.
const POSTS := {
	"utility_pole": [0.17, -0.04, 8.6],
	"pole": [0.16, -0.07, 8.05],
	"streetlight": [0.10, -0.03, 6.8],
	"light": [0.10, -0.04, 6.85],
	"traffic_signal": [0.14, -0.04, 5.45],
	"signal0": [0.14, -0.09, 5.45],
	"signal1": [0.14, -0.09, 5.45],
	"stop_sign": [0.04, -0.03, 2.86],
	"street_sign": [0.05, -0.03, 2.97],
	"speed25": [0.034, -0.04, 2.34, 0.0, -0.018],
	"speed35": [0.034, -0.04, 2.34, 0.0, -0.018],
	"speed45": [0.034, -0.04, 2.34, 0.0, -0.018],
	"light_base": [0.16, -0.04, 0.16],
	"hydrant": [0.156, -0.05, 0.93],
	"bin": [0.265, -0.02, 1.0],
	"mailbox_post": [0.052, -0.07, 0.98],
	"jackson_lamp": [0.085, -0.09, 4.15],
	"jackson_lamp_base": [0.20, -0.09, 0.23],
	"jackson_bin": [0.275, -0.04, 1.04],
	"jackson_sign": [0.029, -1.2, 1.2],
}
# Boxes: local center and dimensions, based on the rigid visible parts.
const BOXES := {
	"bench": [Vector3(0, 0.435, 0), Vector3(1.74, 0.87, 0.48)],
	"news": [Vector3(0, 0.57, 0), Vector3(0.55, 1.19, 0.51)],
	"mailbox": [Vector3(0, 1.10, 0), Vector3(0.30, 0.33, 0.51)],
	"jackson_planter": [Vector3(0, 0.304, 0), Vector3(0.91, 0.61, 0.91)],
	"jackson_sedan": [Vector3(0, 0.46, 0.01), Vector3(1.99, 0.63, 4.49)],
	"jackson_sedan_cab": [Vector3(0, 1.05, 0.29), Vector3(1.48, 0.65, 2.12)],
	"jackson_pickup": [Vector3(0, 0.62, 0.02), Vector3(2.04, 0.91, 5.18)],
	"jackson_pickup_cab": [Vector3(0, 1.31, -0.24), Vector3(1.67, 0.75, 1.72)],
	"jackson_suv": [Vector3(0, 0.56, 0), Vector3(2.07, 0.82, 4.59)],
	"jackson_suv_cab": [Vector3(0, 1.28, 0.48), Vector3(1.55, 0.70, 2.79)],
}

var _cells: Dictionary = {}
var _primitive_cache: Dictionary = {}

func populate(tile: Node3D, target: Node3D, batches: Dictionary) -> void:
	_cells.clear()
	for key: String in batches:
		for placement: Transform3D in batches[key]:
			_add_prop(target, key, placement)
	var streetscape := tile.get_node_or_null("DowntownStreetscape") as Node3D
	if streetscape:
		_add_jackson(tile, streetscape, target)

func _body_at(parent: Node3D, position: Vector3) -> StaticBody3D:
	var cell := Vector2i(floori(position.x / CELL_SIZE), floori(position.z / CELL_SIZE))
	if not _cells.has(cell):
		var body := StaticBody3D.new()
		body.name = "Props_%d_%d" % [cell.x, cell.y]
		body.collision_layer = WORLD
		body.collision_mask = 0
		body.position = Vector3(cell.x * CELL_SIZE, 0, cell.y * CELL_SIZE)
		parent.add_child(body)
		_cells[cell] = body
	return _cells[cell]

func _add_prop(target: Node3D, key: String, placement: Transform3D) -> void:
	match key:
		"palm":
			var scale_factor := placement.basis.x.length()
			var id := ["palm", scale_factor]
			if not _primitive_cache.has(id):
				var trunk := ConvexPolygonShape3D.new()
				var points := PackedVector3Array()
				# Tapered, slightly leaning trunk from the instanced palm kit.
				for ring: Vector3 in [Vector3(0, -0.03, .25), Vector3(.01, .56, .16),
						Vector3(.09, 3.8, .133), Vector3(.29, 6.4, .119), Vector3(.35, 7.1, .18)]:
					for i in 7:
						var angle := TAU * i / 7.0
						points.append(Vector3(ring.x + ring.z * cos(angle), ring.y, ring.z * sin(angle)) * scale_factor)
				trunk.points = points
				_primitive_cache[id] = trunk
			_add(target, key, placement, Vector3.ZERO, _primitive_cache[id])
		"light":
			_add_primitive(target, "light", placement)
			_add_primitive(target, "light_base", placement)
		"mailbox":
			_add_primitive(target, "mailbox", placement)
			_add_primitive(target, "mailbox_post", placement)
		_:
			_add_primitive(target, key, placement)

func _add_primitive(target: Node3D, key: String, placement: Transform3D) -> void:
	var scale_factor := placement.basis.get_scale()
	var id := [key, scale_factor]
	var center: Vector3
	if POSTS.has(key):
		var profile: Array = POSTS[key]
		center = Vector3(profile[3] if profile.size() > 3 else 0.0,
			(profile[1] + profile[2]) * 0.5, profile[4] if profile.size() > 4 else 0.0)
		if not _primitive_cache.has(id):
			var cylinder := CylinderShape3D.new()
			cylinder.radius = profile[0] * maxf(scale_factor.x, scale_factor.z)
			cylinder.height = (profile[2] - profile[1]) * scale_factor.y
			_primitive_cache[id] = cylinder
	elif BOXES.has(key):
		center = BOXES[key][0]
		if not _primitive_cache.has(id):
			var box := BoxShape3D.new()
			box.size = BOXES[key][1] * scale_factor
			_primitive_cache[id] = box
	else:
		return
	_add(target, key, placement, center, _primitive_cache[id])

func _add(target: Node3D, label: String, placement: Transform3D, center: Vector3, shape: Shape3D) -> void:
	var body := _body_at(target, placement.origin)
	var node := CollisionShape3D.new()
	node.name = label
	node.shape = shape
	node.transform = Transform3D(placement.basis.orthonormalized(), placement * center - body.position)
	body.add_child(node, true)

func _add_jackson(tile: Node3D, scene: Node3D, target: Node3D) -> void:
	var inverse := tile.global_transform.affine_inverse()
	var furniture := scene.get_node("JacksonStreetProps")
	for group: Node in furniture.get_children():
		if group.name == "RoadDetails":
			continue
		for prop: Node3D in group.get_children():
			var mesh := mesh_instances(prop)[0] as MeshInstance3D
			var placement := inverse * mesh.global_transform
			match str(group.name):
				"ParkedVehicles":
					var kind := "jackson_sedan"
					if "Pickup" in prop.name:
						kind = "jackson_pickup"
					elif "SUV" in prop.name:
						kind = "jackson_suv"
					_add_primitive(target, kind, placement)
					_add_primitive(target, kind + "_cab", placement)
				"Streetlamps":
					_add_primitive(target, "jackson_lamp", placement)
					_add_primitive(target, "jackson_lamp_base", placement)
				"Benches": _add_primitive(target, "bench", placement)
				"TrashBins": _add_primitive(target, "jackson_bin", placement)
				"Planters": _add_primitive(target, "jackson_planter", placement)
				"ParkingSigns": _add_primitive(target, "jackson_sign", placement)
	var vegetation := scene.get_node("JacksonVegetation")
	for tree: Node3D in vegetation.get_children():
		for mesh: MeshInstance3D in mesh_instances(tree):
			var placement := inverse * mesh.global_transform
			var trunk := selected_shape(mesh.mesh, ["PalmTrunk", "CrapeMyrtleBark"], placement.basis.get_scale())
			if trunk:
				_add(target, "jackson_tree", placement, Vector3.ZERO, trunk)
	for prop: Node in scene.get_children():
		var pole := prop.get_node_or_null("Post") as MeshInstance3D
		if pole and pole.mesh is CylinderMesh:
			var pole_mesh := pole.mesh as CylinderMesh
			var placement := inverse * pole.global_transform
			var shape := CylinderShape3D.new()
			shape.radius = pole_mesh.bottom_radius * placement.basis.x.length()
			shape.height = pole_mesh.height * placement.basis.y.length()
			_add(target, "jackson_street_sign", placement, Vector3.ZERO, shape)

static func mesh_instances(node: Node) -> Array[Node]:
	var result := node.find_children("*", "MeshInstance3D", true, false)
	if node is MeshInstance3D:
		result.push_front(node)
	return result

static func selected_shape(mesh: Mesh, tags: Array, scale_factor := Vector3.ONE) -> ConcavePolygonShape3D:
	var faces := PackedVector3Array()
	for i in mesh.get_surface_count():
		var material := mesh.surface_get_material(i)
		if material == null:
			continue
		var alias := material.resource_path.get_file().get_basename()
		if not tags.has(alias) and not tags.has(material.resource_name):
			continue
		var arrays := mesh.surface_get_arrays(i)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if indices.is_empty():
			for vertex in vertices:
				faces.append(vertex * scale_factor)
		else:
			for index in indices:
				faces.append(vertices[index] * scale_factor)
	if faces.is_empty():
		return null
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	return shape
