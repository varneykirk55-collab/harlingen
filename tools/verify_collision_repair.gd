extends SceneTree
## Exercise the playable character and coupe against streamed district collision.

const STREETS := [
	["Jackson Street", Vector3(221.5, 12.4, 315.1), Vector3(-1, 0, .02)],
	["East Tyler Avenue westbound", Vector3(470, 12.9, 654.7), Vector3(-1, 0, .01)],
	["East Tyler Avenue eastbound", Vector3(619, 12.9, 660.5), Vector3(1, 0, -.01)],
	["North Ed Carey Drive", Vector3(3025, 12.9, 1668), Vector3(.5, 0, -.866)],
]
const WHEEL_NAMES := ["WheelFL", "WheelFR", "WheelRL", "WheelRR"]

var _failures := 0
var _world: Node3D
var _car: VehicleBody3D
var _player: CharacterBody3D
var _space: PhysicsDirectSpaceState3D

func _initialize() -> void:
	call_deferred("_run")

func _tick(frames: int) -> void:
	for i in frames:
		await physics_frame
		await process_frame

func _check(ok: bool, label: String) -> void:
	print("[", "PASS" if ok else "FAIL", "] ", label)
	if not ok:
		_failures += 1

func _ray(p: Vector3, mask := 1, depth := 8.0) -> Dictionary:
	return _space.intersect_ray(PhysicsRayQueryParameters3D.create(
		p + Vector3.UP * 3.0, p - Vector3.UP * depth, mask, [_car.get_rid(), _player.get_rid()]))

func _shape_name(body: CollisionObject3D, index: int) -> String:
	if not body:
		return ""
	var owner := body.shape_owner_get_owner(body.shape_find_owner(index))
	return str(owner.name) if owner else ""

func _run() -> void:
	_world = (load("res://preview/Harlingen.tscn") as PackedScene).instantiate()
	root.add_child(_world)
	_car = _world.vehicle
	_player = _world.player
	await _tick(45)
	_space = _world.get_world_3d().direct_space_state
	print("COLLISION MODE ", "Terrain3D" if _world.native_terrain else "GLB")
	var downtown: Node3D = _world.loaded["+00_+00"]
	_check(_car.continuous_cd and (_car.collision_mask & 1) != 0 and (_player.collision_mask & 1) != 0,
		"Current coupe has CCD and both playable bodies use world layer 1")
	_check(downtown.has_node("DistrictCollision/BuildingCollision"), "Original building collision shape remains loaded")
	for label: String in ["palm", "pole", "light", "hydrant", "news", "jackson_tree", "jackson_lamp", "jackson_sedan", "jackson_planter", "jackson_bin", "jackson_sign", "jackson_street_sign"]:
		await _test_prop(downtown, label)
	await _test_curb(downtown)
	await _walk_into_planter()
	await _impact_parked_car()
	await _drive_streets()
	print("VERIFY_COLLISION_REPAIR_", "PASS" if _failures == 0 else "FAIL", " failures=", _failures)
	quit(0 if _failures == 0 else 1)

func _test_prop(tile: Node3D, label: String, center := Vector2(205, 315)) -> void:
	var shapes := tile.get_node("DistrictCollision").find_children(label + "*", "CollisionShape3D", true, false)
	var visible_match := false
	var player_blocked := false
	var vehicle_blocked := false
	for collider: CollisionShape3D in shapes:
		var target := collider.global_position
		if Vector2(target.x, target.z).distance_to(center) > 165:
			continue
		# Check from below the top of the object. Use the road/terrain around its
		# footprint to place the actors without standing on the prop itself.
		for direction: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
			var from := target - direction * 3.8
			var base := _ray(from)
			if base.is_empty():
				continue
			var probe := Vector3(target.x, base.position.y + .44, target.z)
			var params := PhysicsRayQueryParameters3D.create(probe - direction * 3.8, probe + direction * 1.8, 1,
				[_car.get_rid(), _player.get_rid()])
			var hit := _space.intersect_ray(params)
			if hit.is_empty() or _shape_name(hit.collider, hit.shape) != str(collider.name):
				continue
			visible_match = true
			var player_origin := Transform3D(Basis.IDENTITY, base.position + Vector3.UP * .03)
			var car_origin := Transform3D(Basis.looking_at(direction), base.position + Vector3.UP * .025)
			var player_hit := KinematicCollision3D.new()
			var car_hit := KinematicCollision3D.new()
			player_blocked = player_blocked or (_player.test_move(player_origin, direction * 4, player_hit, .001)
				and player_hit.get_collider() == hit.collider and player_hit.get_collider_shape_index() == hit.shape)
			vehicle_blocked = vehicle_blocked or (_car.test_move(car_origin, direction * 4, car_hit, .001)
				and car_hit.get_collider() == hit.collider and car_hit.get_collider_shape_index() == hit.shape)
			if player_blocked and vehicle_blocked:
				break
		if player_blocked and vehicle_blocked:
			break
	_check(visible_match and player_blocked and vehicle_blocked, "%s collider blocks both playable body sweeps" % label)

func _test_curb(tile: Node3D) -> void:
	var count := 0
	var curb_found := false
	for node: Node in tile.get_node("DistrictCollision").get_children():
		var collider := node as CollisionShape3D
		if not collider or not str(collider.name).begins_with("StreetEdges"):
			continue
		count += 1
		if curb_found:
			continue
		var faces := (collider.shape as ConcavePolygonShape3D).get_faces()
		for i in range(0, faces.size(), 3):
			var p := collider.global_transform * ((faces[i] + faces[i + 1] + faces[i + 2]) / 3)
			if p.distance_to(Vector3(206,12,316)) > 30:
				continue
			var hit := _ray(p)
			if not hit.is_empty() and _shape_name(hit.collider, hit.shape).begins_with("StreetEdges"):
				curb_found = true
				break
	_check(curb_found and count > 1, "Jackson curb surface is physical and retains separate mesh chunks")

func _walk_into_planter() -> void:
	var floor := _ray(Vector3(211.5, 12.5, 325.2))
	if floor.is_empty():
		_check(false, "Jackson planter test has a sidewalk surface")
		return
	_player.global_position = floor.position + Vector3.UP * 0.05
	_player.velocity = Vector3.ZERO
	_player.set_camera_yaw(0.0)
	await _tick(15)
	Input.action_press("move_forward")
	var planter_hit := false
	for i in 75:
		await _tick(1)
		for j in _player.get_slide_collision_count():
			var hit := _player.get_slide_collision(j)
			planter_hit = planter_hit or _shape_name(hit.get_collider(), hit.get_collider_shape_index()).begins_with("jackson_planter")
	Input.action_release("move_forward")
	_check(planter_hit and _player.global_position.z > 322.5, "Playable character walks into a Jackson planter and is stopped")

func _impact_parked_car() -> void:
	# The south Jackson sedan is centered at X=196.5 and ends near X=198.8.
	_car.set_driver_active(false)
	_car.contact_monitor = true
	_car.max_contacts_reported = 8
	var start := _ray(Vector3(207, 12.5, 318.8))
	if start.is_empty():
		_check(false, "Jackson impact test has a road surface")
		return
	_car.global_transform = Transform3D(Basis.looking_at(Vector3.LEFT), start.position + Vector3.UP * 0.045)
	_car.angular_velocity = Vector3.ZERO
	_car.linear_velocity = Vector3.LEFT * 16.0
	var prop_contact := false
	var stayed_outside := true
	for i in 52:
		await _tick(1)
		for item: Node3D in _car.get_colliding_bodies():
			prop_contact = prop_contact or str(item.name).begins_with("Props_")
		stayed_outside = stayed_outside and _car.global_position.x > 199.9
	_check(prop_contact and stayed_outside, "Playable coupe does not pass through a parked Jackson sedan at 16 m/s")

func _drive_streets() -> void:
	for street: Array in STREETS:
		var position: Vector3 = street[1]
		var direction: Vector3 = street[2].normalized()
		_player.global_position = position + Vector3(0, 1, 9)
		_car.set_driver_active(false)
		_world._update_tiles(false)
		await _tick(5)
		if street[0] == "North Ed Carey Drive":
			var district: Node3D = _world.loaded["+01_+00"]
			await _test_prop(district, "utility_pole", Vector2(position.x, position.z))
			await _test_prop(district, "light", Vector2(position.x, position.z))
		var floor_hit := _ray(position)
		if floor_hit.is_empty():
			_check(false, "%s road collision available" % street[0])
			continue
		_car.set_spawn_transform(Transform3D(Basis.looking_at(direction),
			floor_hit.position + Vector3.UP * .08))
		await _tick(42)
		var ground_ok := true
		var min_clearance := INF
		var max_clearance := -INF
		var parked_contacts := 0
		for wheel_name: String in WHEEL_NAMES:
			var wheel := _car.get_node(wheel_name) as VehicleWheel3D
			if wheel.is_in_contact():
				parked_contacts += 1
			var point: Vector3 = wheel.get_child(0).global_position
			var ground := _ray(point, 1)
			if ground.is_empty():
				continue
			var gap: float = point.y - wheel.wheel_radius - ground.position.y
			min_clearance = minf(min_clearance, gap)
			max_clearance = maxf(max_clearance, gap)
			ground_ok = ground_ok and absf(gap) <= .023
		print(street[0], " PARKED ", parked_contacts, "/4, tire-to-road range ", min_clearance, " to ", max_clearance, " m")
		_check(parked_contacts == 4 and ground_ok and min_clearance != INF, "%s parked wheel contact and ride height" % street[0])

		_car.set_driver_active(true)
		_world._update_tiles(false)
		Input.action_press("vehicle_accelerate")
		var grounded_frames := 0
		var start := _car.global_position
		for f in 80:
			await _tick(1)
			var contacts := 0
			for key: String in WHEEL_NAMES:
				if (_car.get_node(key) as VehicleWheel3D).is_in_contact():
					contacts += 1
			if contacts >= 3:
				grounded_frames += 1
		Input.action_release("vehicle_accelerate")
		_car.set_driver_active(false)
		var distance := (_car.global_position - start).dot(direction)
		_check(distance > 5.0 and grounded_frames > 73 and _car.global_basis.y.y > .96,
				"%s driving (%.2f m, %d/80 frames with 3+ grounded wheels)" % [street[0], distance, grounded_frames])
