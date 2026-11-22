extends SceneTree
## Independent Phase 7 end-to-end integration verification for Harlingen.
## Run with:
##   godot --headless --path <project> -s tools/verify_integration.gd
##   godot --headless --path <project> -s tools/verify_integration.gd -- --mesh-ground

var _failures: Array[String] = []
var _world: Node3D = null


func _initialize() -> void:
	call_deferred("_run_all")


func _run_all() -> void:
	_verify_input_map()

	var scene: PackedScene = load("res://preview/Harlingen.tscn") as PackedScene
	if not _check(scene != null, "Load Harlingen.tscn"):
		_finish()
		return

	_world = scene.instantiate()
	root.add_child(_world)
	await _frames(45)

	var mode_name := "Terrain3D" if _world.native_terrain else "GLB"
	print("=== VERIFY START mode=", mode_name, " ===")

	_verify_ground_ray_diagnostic()
	await _verify_player_spawn_and_pose()
	await _verify_animations_and_locomotion()
	await _verify_building_collision()
	await _verify_vehicle_spawn_and_driving()
	await _verify_enter_drive_exit_cycle()
	await _verify_obstacle_blocked_exit()
	await _verify_camera_spring_arms()
	await _verify_joypad_action_inputs()
	await _verify_flyover_toggles()

	_finish()


func _finish() -> void:
	if _failures.is_empty():
		print("VERIFY_INTEGRATION_PASS mode=", ("Terrain3D" if _world and _world.native_terrain else "GLB"))
		quit(0)
	else:
		for f in _failures:
			push_error("VERIFY_FAIL: " + f)
		print("VERIFY_INTEGRATION_FAIL count=", _failures.size())
		quit(1)


func _check(cond: bool, label: String) -> bool:
	if not cond:
		_failures.append(label)
		print("[FAIL] ", label)
	else:
		print("[PASS] ", label)
	return cond


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame


func _key_ev(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _joy_btn_ev(btn: JoyButton, pressed: bool) -> void:
	var ev := InputEventJoypadButton.new()
	ev.device = 0
	ev.button_index = btn
	ev.pressed = pressed
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _joy_axis_ev(axis: JoyAxis, val: float) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.device = 0
	ev.axis = axis
	ev.axis_value = val
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _verify_input_map() -> void:
	var expected_actions := [
		"move_forward", "move_back", "move_left", "move_right",
		"cam_up", "cam_down", "cam_left", "cam_right",
		"sprint", "jump", "interact",
		"action_punch", "action_strafe", "action_reload", "action_rifle_stance",
		"vehicle_accelerate", "vehicle_brake", "vehicle_steer_left", "vehicle_steer_right", "vehicle_handbrake"
	]
	for act in expected_actions:
		_check(InputMap.has_action(act), "InputMap has action: " + act)

	# Verify JoyButton constants & axis mappings
	var sprint_events := InputMap.action_get_events("sprint")
	var has_l3 := false
	for ev in sprint_events:
		if ev is InputEventJoypadButton and (ev as InputEventJoypadButton).button_index == JOY_BUTTON_LEFT_STICK:
			has_l3 = true
	_check(has_l3, "InputMap sprint bound to JOY_BUTTON_LEFT_STICK (L3=" + str(JOY_BUTTON_LEFT_STICK) + ")")

	var accel_events := InputMap.action_get_events("vehicle_accelerate")
	var has_rt := false
	for ev in accel_events:
		if ev is InputEventJoypadMotion and (ev as InputEventJoypadMotion).axis == JOY_AXIS_TRIGGER_RIGHT and (ev as InputEventJoypadMotion).axis_value > 0.0:
			has_rt = true
	_check(has_rt, "InputMap vehicle_accelerate bound to JOY_AXIS_TRIGGER_RIGHT (+)")

	var brake_events := InputMap.action_get_events("vehicle_brake")
	var has_lt := false
	for ev in brake_events:
		if ev is InputEventJoypadMotion and (ev as InputEventJoypadMotion).axis == JOY_AXIS_TRIGGER_LEFT and (ev as InputEventJoypadMotion).axis_value > 0.0:
			has_lt = true
	_check(has_lt, "InputMap vehicle_brake bound to JOY_AXIS_TRIGGER_LEFT (+)")

	var hb_events := InputMap.action_get_events("vehicle_handbrake")
	var has_b := false
	for ev in hb_events:
		if ev is InputEventJoypadButton and (ev as InputEventJoypadButton).button_index == JOY_BUTTON_B:
			has_b = true
	_check(has_b, "InputMap vehicle_handbrake bound to JOY_BUTTON_B")


func _verify_ground_ray_diagnostic() -> void:
	var space := root.world_3d.direct_space_state
	var all_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(205, 74, 320), Vector3(205, -5, 320)))
	var mask1_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(205, 74, 320), Vector3(205, -5, 320), 1))
	var player: CharacterBody3D = _world.player
	print("DIAGNOSTIC ray_all_hit=", all_hit.get("position"), " collider=", all_hit.get("collider"),
		" ray_mask1_hit=", mask1_hit.get("position"), " player_pos=", player.global_position)
	_check(not mask1_hit.is_empty() and mask1_hit.position.y > 11.5 and mask1_hit.position.y < 12.1,
		"World ground collision (mask=1) at spawn ~11.8m: " + str(mask1_hit.get("position")))
	_check(all_hit.get("collider") == player,
		"Confirm check_scene.gd ray hits PlayerCharacter capsule (layer 2) when mask is default")


func _verify_player_spawn_and_pose() -> void:
	var player: CharacterBody3D = _world.player
	var vi = _world.vehicle_interaction
	var hud = _world.hud

	_check(_world.walking and not _world.legacy_walker_mode, "World starts in gameplay mode (non-legacy)")
	_check(not vi.is_driving, "Starts on foot")
	_check(root.get_camera_3d() == player.get_camera(), "PlayerCamera is active on startup")
	_check(player.is_on_floor(), "PlayerCharacter spawns grounded (is_on_floor=true)")

	var space := root.world_3d.direct_space_state
	var ground_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(
		player.global_position + Vector3(0, 1.0, 0),
		player.global_position - Vector3(0, 2.0, 0),
		1
	))
	var ground_y: float = ground_hit.position.y if not ground_hit.is_empty() else -999.0
	var foot_offset: float = player.global_position.y - ground_y
	_check(absf(foot_offset) < 0.08, "Player feet grounded cleanly (offset=" + str(foot_offset) + " m)")

	var vr: Node3D = player.visual_root
	var fwd: Vector3 = -vr.global_basis.z
	_check(absf(vr.rotation.y - PI) < 0.05, "Player visual_root facing +Z toward street/Baxter (rot_y=" + str(vr.rotation.y) + ", fwd=" + str(fwd) + ")")

	var skel: Skeleton3D = player.find_child("Skeleton3D", true, false) as Skeleton3D
	_check(skel != null, "Skeleton3D found under PlayerCharacter")
	if skel:
		var l_hand_idx := skel.find_bone("mixamorig_LeftHand")
		var r_hand_idx := skel.find_bone("mixamorig_RightHand")
		var l_sh_idx := skel.find_bone("mixamorig_LeftShoulder")
		_check(l_hand_idx >= 0 and r_hand_idx >= 0 and l_sh_idx >= 0, "Mixamo hand/shoulder bones present")
		if l_hand_idx >= 0 and r_hand_idx >= 0 and l_sh_idx >= 0:
			var lh_y := skel.get_bone_global_pose(l_hand_idx).origin.y
			var rh_y := skel.get_bone_global_pose(r_hand_idx).origin.y
			var ls_y := skel.get_bone_global_pose(l_sh_idx).origin.y
			print("POSE idle bone_y: LHand=", lh_y, " RHand=", rh_y, " LShoulder=", ls_y)
			_check(lh_y < ls_y - 0.15 and rh_y < ls_y - 0.15, "Character is in relaxed Idle pose, NOT T-pose")

	_check(hud.mode_label.text == "ON FOOT", "HUD mode badge shows ON FOOT")
	_check(hud.stance_label.text == "STANCE: UNARMED", "HUD stance shows UNARMED")


func _verify_animations_and_locomotion() -> void:
	var player: CharacterBody3D = _world.player
	var hud = _world.hud
	var anim_tree: AnimationTree = player.animation_tree
	var anim_player: AnimationPlayer = player.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var skel: Skeleton3D = player.find_child("Skeleton3D", true, false) as Skeleton3D

	_check(anim_tree != null and anim_tree.active, "AnimationTree present and active")
	_check(anim_player != null, "AnimationPlayer found")

	var expected_anims := ["Idle", "Walking", "FastRun", "Strafing", "Punching", "WalkWithRifle", "Reloading"]
	for a in expected_anims:
		_check(anim_player.has_animation(a), "Animation exists: " + a)

	for a in ["Idle", "Walking", "FastRun", "Strafing", "WalkWithRifle"]:
		_check(anim_player.get_animation(a).loop_mode == Animation.LOOP_LINEAR, "Looping anim LOOP_LINEAR: " + a)
	for a in ["Punching", "Reloading"]:
		_check(anim_player.get_animation(a).loop_mode == Animation.LOOP_NONE, "One-shot anim LOOP_NONE: " + a)

	_check(player.get_current_animation_state() == "Idle", "Initial logical animation state is Idle")

	# 1. Walk forward (-Z in camera space, which at yaw=PI is +Z world) -> verify Walking & bone motion
	var pose_before := skel.get_bone_global_pose(skel.find_bone("mixamorig_LeftFoot")).origin
	_key_ev(KEY_W, true)
	await _frames(25)
	var walk_speed := Vector2(player.velocity.x, player.velocity.z).length()
	var walk_blend: float = anim_tree.get("parameters/Locomotion/blend_position")
	var pose_walk := skel.get_bone_global_pose(skel.find_bone("mixamorig_LeftFoot")).origin
	print("WALK speed=", walk_speed, " state=", player.get_current_animation_state(), " blend=", walk_blend)
	_check(walk_speed > 3.2 and walk_speed < 4.3, "Walking speed ~3.8 m/s (got " + str(walk_speed) + ")")
	_check(player.get_current_animation_state() == "Walking", "State transitions to Walking")
	_check(walk_blend > 0.7 and walk_blend < 1.3, "Locomotion blend_position ~1.0 (got " + str(walk_blend) + ")")
	_check(pose_before.distance_to(pose_walk) > 0.01, "Skeleton bone pose animates during Walking")

	# 2. Hold Shift to Sprint -> FastRun
	_key_ev(KEY_SHIFT, true)
	await _frames(35)
	var run_speed := Vector2(player.velocity.x, player.velocity.z).length()
	var run_blend: float = anim_tree.get("parameters/Locomotion/blend_position")
	print("RUN speed=", run_speed, " state=", player.get_current_animation_state(), " blend=", run_blend)
	_check(run_speed > 6.5 and run_speed < 8.2, "Sprint speed ~7.6 m/s (got " + str(run_speed) + ")")
	_check(player.get_current_animation_state() == "FastRun", "State transitions to FastRun")
	_check(run_blend > 1.6, "Locomotion blend_position approaches 2.0 (got " + str(run_blend) + ")")

	# 3. Release W + Shift -> smooth deceleration (not instant 0 on frame 1) back to Idle
	_key_ev(KEY_W, false)
	_key_ev(KEY_SHIFT, false)
	await _frames(2)
	var decel_mid := Vector2(player.velocity.x, player.velocity.z).length()
	await _frames(40)
	var decel_end := Vector2(player.velocity.x, player.velocity.z).length()
	print("DECEL mid=", decel_mid, " end=", decel_end, " state=", player.get_current_animation_state())
	_check(decel_mid > 1.0 and decel_end < 0.1, "Smooth deceleration (mid=" + str(decel_mid) + ", end=" + str(decel_end) + ")")
	_check(player.get_current_animation_state() == "Idle", "Returns to Idle after stopping")

	# 4. Strafe (C + D)
	player.respawn()
	await _frames(15)
	_key_ev(KEY_C, true)
	_key_ev(KEY_D, true)
	await _frames(22)
	var strafe_speed := Vector2(player.velocity.x, player.velocity.z).length()
	print("STRAFE speed=", strafe_speed, " state=", player.get_current_animation_state(), " node=", player.get_state_machine_node())
	_check(strafe_speed > 2.8, "Strafing moves character laterally (speed=" + str(strafe_speed) + ")")
	_check(player.get_current_animation_state() == "Strafing" and player.get_state_machine_node() == "Strafing",
		"StateMachine enters Strafing")
	_key_ev(KEY_D, false)
	_key_ev(KEY_C, false)
	await _frames(25)
	_check(player.get_current_animation_state() == "Idle" and player.get_state_machine_node() == "Locomotion",
		"Strafing exits cleanly back to Locomotion/Idle")

	# 5. Punching one-shot (F)
	_key_ev(KEY_F, true)
	await _frames(4)
	_key_ev(KEY_F, false)
	_check(player.get_current_animation_state() == "Punching" and player.get_state_machine_node() == "Punching",
		"Punching one-shot triggers on F")
	await _frames(85) # ~1.4s > 1.27s punch length
	_check(player.get_current_animation_state() == "Idle", "Punching returns smoothly to Idle after completion")

	# 6. Rifle stance (Q) + WalkWithRifle + Reloading (R)
	_key_ev(KEY_Q, true)
	await _frames(3)
	_key_ev(KEY_Q, false)
	_check(player.is_rifle_stance() and hud.stance_label.text == "STANCE: RIFLE", "Q toggles Rifle Stance & HUD updates")
	_key_ev(KEY_W, true)
	await _frames(25)
	var rifle_speed := Vector2(player.velocity.x, player.velocity.z).length()
	var rifle_blend: float = anim_tree.get("parameters/RifleLocomotion/blend_position")
	print("RIFLE walk speed=", rifle_speed, " state=", player.get_current_animation_state(), " node=", player.get_state_machine_node(), " blend=", rifle_blend)
	_check(rifle_speed > 2.6 and rifle_speed < 3.7, "WalkWithRifle speed ~3.2 m/s (got " + str(rifle_speed) + ")")
	_check(player.get_current_animation_state() == "WalkWithRifle" and player.get_state_machine_node() == "RifleLocomotion",
		"State transitions to WalkWithRifle in RifleLocomotion")
	_key_ev(KEY_W, false)
	await _frames(25)
	_check(player.get_current_animation_state() == "Idle", "Rifle stance blends back to Idle when stopped")

	_key_ev(KEY_R, true)
	await _frames(4)
	_key_ev(KEY_R, false)
	_check(player.get_current_animation_state() == "Reloading" and player.get_state_machine_node() == "Reloading",
		"Reloading triggers on R")
	await _frames(230) # ~3.8s > 3.67s reload length
	_check(player.get_current_animation_state() == "Idle" and player.get_state_machine_node() == "RifleLocomotion",
		"Reloading returns to RifleLocomotion/Idle")

	# Toggle back to unarmed
	_key_ev(KEY_Q, true)
	await _frames(3)
	_key_ev(KEY_Q, false)
	_check(not player.is_rifle_stance() and hud.stance_label.text == "STANCE: UNARMED", "Q toggles back to UNARMED")

	# 7. Jump (Space)
	player.respawn()
	for i in 45:
		await _frames(1)
		if player.is_on_floor():
			break
	var ground_y := player.global_position.y
	_key_ev(KEY_SPACE, true)
	await _frames(4)
	_key_ev(KEY_SPACE, false)
	var peak_y := player.global_position.y
	for i in 16:
		await _frames(1)
		peak_y = maxf(peak_y, player.global_position.y)
	await _frames(50)
	print("JUMP ground_y=", ground_y, " peak_y=", peak_y, " landed_y=", player.global_position.y)
	_check(peak_y > ground_y + 0.5 and player.is_on_floor(), "Jump lifts character and lands grounded")


func _verify_building_collision() -> void:
	var player: CharacterBody3D = _world.player
	player.respawn()
	await _frames(20)
	# Player starts at (205, ~11.8, 320) facing +Z toward Baxter Building (~z=326.66)
	_key_ev(KEY_W, true)
	await _frames(120)
	_key_ev(KEY_W, false)
	print("BUILDING_COLLISION player_pos=", player.global_position)
	_check(player.global_position.z > 325.0 and player.global_position.z < 327.0,
		"Player collides with Baxter Building wall without clipping (z=" + str(player.global_position.z) + ")")


func _wheel_steer_yaw(wheel: VehicleWheel3D) -> float:
	if wheel == null:
		return 0.0
	var x_axis := wheel.transform.basis.x
	return atan2(-x_axis.z, x_axis.x)


func _get_door_pivots(car: VehicleBody3D) -> Array[Node3D]:
	var car_model := car.get_node_or_null("CarModel") as Node3D
	var door_l := car_model.find_child("DoorL_Pivot", true, false) as Node3D if car_model else null
	var door_r := car_model.find_child("DoorR_Pivot", true, false) as Node3D if car_model else null
	return [door_l, door_r]


func _door_angle(pivot: Node3D) -> float:
	if pivot == null:
		return -1.0
	return pivot.quaternion.angle_to(Quaternion.IDENTITY)


func _verify_vehicle_spawn_and_driving() -> void:
	var car: VehicleBody3D = _world.vehicle
	var vi = _world.vehicle_interaction
	_check(not vi.is_vehicle_paused() and not car.freeze, "Vehicle is active/unpaused in gameplay mode")
	_check(car.global_basis.y.y > 0.99, "Vehicle upright (up.y=" + str(car.global_basis.y.y) + ")")

	# Verify koenigsegg.glb structure & CarModel 1:1 scale
	var glb := load("res://assets/vehicle/koenigsegg/koenigsegg.glb") as PackedScene
	_check(glb != null, "Load koenigsegg.glb PackedScene")
	if glb:
		var glb_inst := glb.instantiate()
		var glb_body := glb_inst.find_child("CarBody", true, false)
		var glb_dl := glb_inst.find_child("DoorL_Pivot", true, false)
		var glb_dl_mesh := glb_dl.find_child("DoorL_Mesh", true, false) if glb_dl else null
		var glb_dr := glb_inst.find_child("DoorR_Pivot", true, false)
		var glb_dr_mesh := glb_dr.find_child("DoorR_Mesh", true, false) if glb_dr else null
		_check(glb_body != null and glb_dl != null and glb_dl_mesh != null and glb_dr != null and glb_dr_mesh != null,
			"koenigsegg.glb has CarBody, DoorL_Pivot(DoorL_Mesh), DoorR_Pivot(DoorR_Mesh)")
		glb_inst.free()

	var car_model := car.get_node_or_null("CarModel") as Node3D
	_check(car_model != null and car_model.scale.is_equal_approx(Vector3.ONE),
		"CarModel scale is (1, 1, 1) (got " + str(car_model.scale if car_model else Vector3.ZERO) + ")")
	if car_model:
		var body_node := car_model.find_child("CarBody", true, false)
		var dl_pivot := car_model.find_child("DoorL_Pivot", true, false) as Node3D
		var dl_mesh := dl_pivot.find_child("DoorL_Mesh", true, false) if dl_pivot else null
		var dr_pivot := car_model.find_child("DoorR_Pivot", true, false) as Node3D
		var dr_mesh := dr_pivot.find_child("DoorR_Mesh", true, false) if dr_pivot else null
		_check(body_node != null and dl_pivot != null and dl_mesh != null and dr_pivot != null and dr_mesh != null,
			"CarModel runtime hierarchy has CarBody, DoorL_Pivot(DoorL_Mesh), DoorR_Pivot(DoorR_Mesh)")
		var dl_ang := _door_angle(dl_pivot)
		var dr_ang := _door_angle(dr_pivot)
		print("DOOR_SPAWN doorL_angle=", dl_ang, " doorR_angle=", dr_ang)
		_check(dl_ang >= 0.0 and dl_ang < 0.01 and dr_ang >= 0.0 and dr_ang < 0.01,
			"Both DoorL_Pivot and DoorR_Pivot start flush closed at spawn (L=" + str(dl_ang) + ", R=" + str(dr_ang) + ")")

	# Verify all 4 wheel meshes are parented under VehicleWheel3D at local (0, 0, 0)
	var wheel_pairs := [
		[car.wheel_fl, "WheelFL_Mesh"],
		[car.wheel_fr, "WheelFR_Mesh"],
		[car.wheel_rl, "WheelRL_Mesh"],
		[car.wheel_rr, "WheelRR_Mesh"],
	]
	for pair in wheel_pairs:
		var w_node := pair[0] as VehicleWheel3D
		var m_name: String = pair[1]
		var w_mesh := w_node.get_node_or_null(m_name) as Node3D if w_node else null
		var local_ok := w_mesh != null and w_mesh.position.length() < 0.001 and w_mesh.rotation.length() < 0.001 and w_mesh.scale.is_equal_approx(Vector3.ONE)
		_check(local_ok, m_name + " parented under " + (w_node.name if w_node else "null") + " at local (0,0,0) scale (1,1,1)")

	var contacts := [
		car.wheel_fl.is_in_contact(),
		car.wheel_fr.is_in_contact(),
		car.wheel_rl.is_in_contact(),
		car.wheel_rr.is_in_contact(),
	]
	print("VEHICLE_SPAWN pos=", car.global_position, " vel_y=", car.linear_velocity.y, " contacts=", contacts)
	_check(contacts[0] and contacts[1] and contacts[2] and contacts[3], "All 4 vehicle wheels in contact at spawn")
	_check(absf(car.linear_velocity.y) < 0.25, "Vehicle settled with no excessive bouncing")


func _verify_enter_drive_exit_cycle() -> void:
	var player: CharacterBody3D = _world.player
	var car: VehicleBody3D = _world.vehicle
	var vi = _world.vehicle_interaction
	var hud = _world.hud
	var trans_cam: Camera3D = _world.transition_camera

	# Respawn player and move into proximity (< 3.5 m) of car at (223, 11.88, 316)
	player.respawn()
	await _frames(15)
	_check(not hud.prompt_panel.visible, "Interact prompt hidden when far from vehicle")

	# Walk/sprint toward the vehicle using real camera-relative controls
	var to_car: Vector3 = car.global_position - player.global_position
	var yaw_to_car := atan2(-to_car.x, -to_car.z)
	player.set_camera_yaw(yaw_to_car)
	_key_ev(KEY_W, true)
	_key_ev(KEY_SHIFT, true)
	for i in 220:
		await _frames(1)
		if car.global_position.distance_to(player.global_position) <= 2.4:
			break
	_key_ev(KEY_W, false)
	_key_ev(KEY_SHIFT, false)
	await _frames(20)

	var doors := _get_door_pivots(car)
	var door_l: Node3D = doors[0]
	var door_r: Node3D = doors[1]

	var dist := car.global_position.distance_to(player.global_position)
	print("APPROACH dist=", dist, " prompt=", hud.prompt_label.text)
	_check(dist <= 3.5, "Player walked into vehicle range (dist=" + str(dist) + ")")
	_check(hud.prompt_panel.visible and hud.prompt_label.text == "[E / Y] Enter Vehicle",
		"HUD shows [E / Y] Enter Vehicle prompt")
	_check(_door_angle(door_l) < 0.01 and _door_angle(door_r) < 0.01,
		"Doors remain flush closed while parked before enter")

	# Enter vehicle with E
	var player_cam_pos: Vector3 = player.get_camera().global_position
	var chase_cam_pos: Vector3 = car.get_camera().global_position
	_key_ev(KEY_E, true)
	await _frames(1)
	_key_ev(KEY_E, false)

	_check(vi.is_driving and player.is_in_vehicle(), "Interact enters vehicle")
	_check(not player.visible and player.collision_shape.disabled, "Player hidden and collision disabled while driving")
	_check(car.driver_active, "Vehicle driver_active=true")
	_check(vi.is_transitioning and root.get_camera_3d() == trans_cam, "TransitionCamera active during enter blend")
	_check(hud.mode_label.text == "DRIVING", "HUD mode switches to DRIVING")

	# Sample TransitionCamera smoothness & DoorL_Pivot open->close animation
	var trans_positions: Array[Vector3] = []
	var enter_door_peak_rad := _door_angle(door_l)
	for i in 28:
		await _frames(1)
		trans_positions.append(trans_cam.global_position)
		enter_door_peak_rad = maxf(enter_door_peak_rad, _door_angle(door_l))
	for i in 8:
		if _door_angle(door_l) < 0.01:
			break
		await _frames(1)
	var enter_door_end_l := _door_angle(door_l)
	var enter_door_end_r := _door_angle(door_r)
	var start_gap := trans_positions[0].distance_to(player_cam_pos)
	var mid_dist_from_start := trans_positions[10].distance_to(player_cam_pos)
	var mid_dist_to_end := trans_positions[10].distance_to(chase_cam_pos)
	var max_step := 0.0
	for i in range(1, trans_positions.size()):
		max_step = maxf(max_step, trans_positions[i].distance_to(trans_positions[i - 1]))
	print("ENTER_BLEND start_gap=", start_gap, " mid_from_start=", mid_dist_from_start, " mid_to_end=", mid_dist_to_end,
		" max_step=", max_step, " door_peak=", enter_door_peak_rad, " door_end_L=", enter_door_end_l, " door_end_R=", enter_door_end_r)
	_check(start_gap < 1.5 and mid_dist_from_start > 0.5 and mid_dist_to_end > 0.5 and max_step < 1.5,
		"Enter TransitionCamera interpolates smoothly without snapping")
	_check(not vi.is_transitioning and root.get_camera_3d() == car.get_camera(),
		"TransitionCamera hands off cleanly to ChaseCamera")
	_check(enter_door_peak_rad > 0.3,
		"Interact (E) enter animates DoorL_Pivot open > 0.3 rad (peak=" + str(enter_door_peak_rad) + ")")
	_check(enter_door_end_l < 0.01 and enter_door_end_r < 0.01 and not car.is_driver_door_open(),
		"Doors close flush to Vector3.ZERO when seated/driving (L=" + str(enter_door_end_l) + ", R=" + str(enter_door_end_r) + ")")

	# Accelerate forward (W) > 2.0 m/s and verify wheel spin (rotation.x + RPM)
	var car_start: Vector3 = car.global_position
	var wheels := [car.wheel_fl, car.wheel_fr, car.wheel_rl, car.wheel_rr]
	_key_ev(KEY_W, true)
	await _frames(65)
	var prev_rx := [car.wheel_fl.rotation.x, car.wheel_fr.rotation.x, car.wheel_rl.rotation.x, car.wheel_rr.rotation.x]
	var fwd_spin := [0.0, 0.0, 0.0, 0.0]
	for i in 25:
		await _frames(1)
		for wi in 4:
			var w: VehicleWheel3D = wheels[wi]
			fwd_spin[wi] += absf(angle_difference(prev_rx[wi], w.rotation.x))
			prev_rx[wi] = w.rotation.x
	var fwd_rpms := [car.wheel_fl.get_rpm(), car.wheel_fr.get_rpm(), car.wheel_rl.get_rpm(), car.wheel_rr.get_rpm()]
	var accel_speed: float = car.get_speed_mps()
	var fwd_speed: float = car.get_forward_speed_mps()
	print("DRIVE_ACCEL speed=", accel_speed, " fwd=", fwd_speed, " fwd_spin=", fwd_spin, " fwd_rpm=", fwd_rpms,
		" hud_speed=", hud.speed_label.text, " prompt=", hud.prompt_label.text)
	_check(fwd_speed > 8.0 and car.global_position.z < car_start.z - 5.0,
		"Vehicle accelerates forward along -Z (fwd_speed=" + str(fwd_speed) + ")")
	_check(fwd_spin[0] > 0.5 and fwd_spin[1] > 0.5 and fwd_spin[2] > 0.5 and fwd_spin[3] > 0.5,
		"All 4 wheels physically spin (rotation.x changes) during forward acceleration (spin=" + str(fwd_spin) + ")")
	_check(absf(fwd_rpms[0]) > 10.0 and absf(fwd_rpms[1]) > 10.0 and absf(fwd_rpms[2]) > 10.0 and absf(fwd_rpms[3]) > 10.0,
		"All 4 wheels report non-zero RPM during forward acceleration (rpm=" + str(fwd_rpms) + ")")
	_check(_door_angle(door_l) < 0.01 and _door_angle(door_r) < 0.01,
		"Both doors stay flush closed while driving")
	_check(hud.prompt_panel.visible and hud.prompt_label.text == "Stop vehicle to exit",
		"HUD shows 'Stop vehicle to exit' above 2.0 m/s")

	# Try exiting while moving > 2.0 m/s -> must NOT exit
	_key_ev(KEY_E, true)
	await _frames(2)
	_key_ev(KEY_E, false)
	_check(vi.is_driving and player.is_in_vehicle(), "Interact does NOT exit while speed > 2.0 m/s")

	# Test speed-sensitive steering (left with A, then right with D) -> front wheels steer, rear wheels stay straight
	var yaw_before: float = car.global_rotation.y
	_key_ev(KEY_A, true)
	await _frames(20)
	var steer_left_val: float = car.steering
	var fl_yaw_left: float = _wheel_steer_yaw(car.wheel_fl)
	var fr_yaw_left: float = _wheel_steer_yaw(car.wheel_fr)
	var rl_yaw_left: float = _wheel_steer_yaw(car.wheel_rl)
	var rr_yaw_left: float = _wheel_steer_yaw(car.wheel_rr)
	var yaw_after: float = car.global_rotation.y
	var yaw_delta_left: float = angle_difference(yaw_before, yaw_after)
	_key_ev(KEY_A, false)
	print("STEER_LEFT steer_rad=", steer_left_val, " fl_y=", fl_yaw_left, " fr_y=", fr_yaw_left,
		" rl_y=", rl_yaw_left, " rr_y=", rr_yaw_left, " yaw_delta_deg=", rad_to_deg(yaw_delta_left), " up_y=", car.global_basis.y.y)
	_check(steer_left_val > 0.05 and steer_left_val <= car.low_speed_steer_rad and yaw_delta_left > 0.08,
		"Vehicle steers left smoothly with speed-sensitive steering")
	_check(fl_yaw_left > 0.05 and fr_yaw_left > 0.05 and absf(rl_yaw_left) < 0.001 and absf(rr_yaw_left) < 0.001,
		"Left steer rotates front wheels (FL/FR) while rear wheels (RL/RR) stay straight (rot_y=0)")
	_check(car.global_basis.y.y > 0.96, "Vehicle remains stable without flipping during left turn")

	var yaw_mid: float = car.global_rotation.y
	_key_ev(KEY_D, true)
	await _frames(35)
	var steer_right_val: float = car.steering
	var fl_yaw_right: float = _wheel_steer_yaw(car.wheel_fl)
	var fr_yaw_right: float = _wheel_steer_yaw(car.wheel_fr)
	var rl_yaw_right: float = _wheel_steer_yaw(car.wheel_rl)
	var rr_yaw_right: float = _wheel_steer_yaw(car.wheel_rr)
	var yaw_after_right: float = car.global_rotation.y
	var yaw_delta_right: float = angle_difference(yaw_mid, yaw_after_right)
	_key_ev(KEY_D, false)
	_key_ev(KEY_W, false)
	print("STEER_RIGHT steer_rad=", steer_right_val, " fl_y=", fl_yaw_right, " fr_y=", fr_yaw_right,
		" rl_y=", rl_yaw_right, " rr_y=", rr_yaw_right, " yaw_delta_deg=", rad_to_deg(yaw_delta_right), " up_y=", car.global_basis.y.y)
	_check(steer_right_val < -0.05 and steer_right_val >= -car.low_speed_steer_rad and yaw_delta_right < -0.08,
		"Vehicle steers right smoothly with speed-sensitive steering")
	_check(fl_yaw_right < -0.05 and fr_yaw_right < -0.05 and absf(rl_yaw_right) < 0.001 and absf(rr_yaw_right) < 0.001,
		"Right steer rotates front wheels (FL/FR) while rear wheels (RL/RR) stay straight (rot_y=0)")
	_check(car.global_basis.y.y > 0.96, "Vehicle remains stable without flipping during right turn")

	# Brake (S) to stop, then hold S to reverse and verify reverse wheel spin + opposite RPM
	_key_ev(KEY_S, true)
	for i in 120:
		await _frames(1)
		if car.get_forward_speed_mps() < -1.5:
			break
	var rev_prev_rx := [car.wheel_fl.rotation.x, car.wheel_fr.rotation.x, car.wheel_rl.rotation.x, car.wheel_rr.rotation.x]
	var rev_spin := [0.0, 0.0, 0.0, 0.0]
	for i in 25:
		await _frames(1)
		for wi in 4:
			var w: VehicleWheel3D = wheels[wi]
			rev_spin[wi] += absf(angle_difference(rev_prev_rx[wi], w.rotation.x))
			rev_prev_rx[wi] = w.rotation.x
	for i in 40:
		if car.get_forward_speed_mps() < -3.0:
			break
		await _frames(1)
	var rev_rpms := [car.wheel_fl.get_rpm(), car.wheel_fr.get_rpm(), car.wheel_rl.get_rpm(), car.wheel_rr.get_rpm()]
	var rev_speed: float = car.get_forward_speed_mps()
	print("REVERSE fwd_speed=", rev_speed, " rev_spin=", rev_spin, " rev_rpm=", rev_rpms, " hud_speed=", hud.speed_label.text)
	_check(rev_speed < -3.0 and hud.speed_label.text.contains("[REV]"),
		"Brake -> Reverse shifts smoothly and HUD shows [REV] (fwd_speed=" + str(rev_speed) + ")")
	_check(rev_spin[0] > 0.3 and rev_spin[1] > 0.3 and rev_spin[2] > 0.3 and rev_spin[3] > 0.3,
		"All 4 wheels physically spin (rotation.x changes) during reverse (spin=" + str(rev_spin) + ")")
	_check(absf(rev_rpms[0]) > 5.0 and absf(rev_rpms[1]) > 5.0 and absf(rev_rpms[2]) > 5.0 and absf(rev_rpms[3]) > 5.0
		and signf(rev_rpms[0]) != signf(fwd_rpms[0]),
		"All 4 wheels report reversed non-zero RPM during reverse (rpm=" + str(rev_rpms) + ")")
	_key_ev(KEY_S, false)

	# Handbrake (Space) to complete stop
	_key_ev(KEY_SPACE, true)
	await _frames(60)
	_key_ev(KEY_SPACE, false)
	await _frames(15)
	print("STOPPED speed=", car.get_speed_mps(), " can_exit=", car.can_exit(), " prompt=", hud.prompt_label.text)
	_check(car.can_exit() and car.get_speed_mps() < 2.0, "Handbrake stops vehicle cleanly (can_exit=true)")
	_check(hud.prompt_label.text == "[E / Y] Exit Vehicle", "HUD shows [E / Y] Exit Vehicle when stopped")

	# Exit vehicle cleanly
	var exit_cam_start: Vector3 = car.get_camera().global_position
	_key_ev(KEY_E, true)
	await _frames(1)
	_key_ev(KEY_E, false)
	_check(not vi.is_driving and not player.is_in_vehicle(), "Interact exits vehicle when stopped")
	_check(player.visible and not player.collision_shape.disabled, "Player visible and collision restored after exit")
	_check(vi.is_transitioning and root.get_camera_3d() == trans_cam, "TransitionCamera active during exit blend")

	var exit_dist_from_car := player.global_position.distance_to(car.global_position)
	_check(exit_dist_from_car > 1.2 and exit_dist_from_car < 4.0,
		"Player exited safely beside vehicle (dist=" + str(exit_dist_from_car) + " m)")

	var exit_positions: Array[Vector3] = []
	var exit_door_peak_rad := _door_angle(door_l)
	for i in 28:
		await _frames(1)
		exit_positions.append(trans_cam.global_position)
		exit_door_peak_rad = maxf(exit_door_peak_rad, _door_angle(door_l))
	for i in 8:
		if _door_angle(door_l) < 0.01:
			break
		await _frames(1)
	var exit_door_end_l := _door_angle(door_l)
	var exit_door_end_r := _door_angle(door_r)
	var exit_start_gap := exit_positions[0].distance_to(exit_cam_start)
	var exit_max_step := 0.0
	for i in range(1, exit_positions.size()):
		exit_max_step = maxf(exit_max_step, exit_positions[i].distance_to(exit_positions[i - 1]))
	print("EXIT_BLEND start_gap=", exit_start_gap, " max_step=", exit_max_step,
		" door_peak=", exit_door_peak_rad, " door_end_L=", exit_door_end_l, " door_end_R=", exit_door_end_r)
	_check(exit_start_gap < 1.5 and exit_max_step < 1.5, "Exit TransitionCamera interpolates smoothly without snapping")
	_check(not vi.is_transitioning and root.get_camera_3d() == player.get_camera(),
		"TransitionCamera hands off cleanly back to PlayerCamera")
	_check(exit_door_peak_rad > 0.3,
		"Interact (E) exit animates DoorL_Pivot open > 0.3 rad (peak=" + str(exit_door_peak_rad) + ")")
	_check(exit_door_end_l < 0.01 and exit_door_end_r < 0.01 and not car.is_driver_door_open(),
		"Doors close flush to Vector3.ZERO after exit (L=" + str(exit_door_end_l) + ", R=" + str(exit_door_end_r) + ")")
	_check(hud.mode_label.text == "ON FOOT", "HUD mode returns to ON FOOT")

	# Verify on-foot controls resume cleanly
	var p_before := player.global_position
	_key_ev(KEY_W, true)
	await _frames(20)
	_key_ev(KEY_W, false)
	var moved := player.global_position.distance_to(p_before)
	_check(moved > 0.5, "On-foot movement resumes cleanly after vehicle exit (moved=" + str(moved) + " m)")


func _make_box_obstacle(pos: Vector3, extents: Vector3) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = extents
	cs.shape = box
	sb.add_child(cs)
	_world.add_child(sb)
	sb.global_position = pos
	return sb


func _verify_obstacle_blocked_exit() -> void:
	var car: VehicleBody3D = _world.vehicle
	var player: CharacterBody3D = _world.player
	var vi = _world.vehicle_interaction
	var hud = _world.hud

	car.respawn()
	await _frames(25)

	# Block left exit side only -> verify find_safe_exit_transform picks right/rear side (NOT left)
	var left_pt: Vector3 = car.global_transform * Vector3(-1.68, 0.85, 0.15)
	var left_wall := _make_box_obstacle(left_pt, Vector3(1.5, 2.5, 4.0))
	await _frames(4)
	var safe_xform: Transform3D = car.find_safe_exit_transform(0.32, 1.78)
	var local_exit: Vector3 = car.global_transform.affine_inverse() * safe_xform.origin
	print("OBSTACLE_LEFT_BLOCKED chosen_local_exit=", local_exit)
	_check(local_exit.x > 0.5, "Left-blocked exit falls back to safe unobstructed right side (local=" + str(local_exit) + ")")
	left_wall.queue_free()
	await _frames(3)

	# Move player near car and enter
	player.global_position = car.global_position + Vector3(-2.0, 0.2, 0.0)
	await _frames(5)
	_key_ev(KEY_E, true)
	await _frames(2)
	_key_ev(KEY_E, false)
	await _frames(28)
	_check(vi.is_driving, "Entered vehicle for surrounded-exit test")

	# Surround ALL candidate exits with 4 walls around car
	var walls: Array[StaticBody3D] = [
		_make_box_obstacle(car.global_transform * Vector3(-1.85, 1.0, 0.2), Vector3(1.2, 3.0, 6.5)),
		_make_box_obstacle(car.global_transform * Vector3(1.85, 1.0, 0.2), Vector3(1.2, 3.0, 6.5)),
		_make_box_obstacle(car.global_transform * Vector3(0.0, 1.0, 3.1), Vector3(4.5, 3.0, 1.2)),
		_make_box_obstacle(car.global_transform * Vector3(0.0, 1.0, -3.1), Vector3(4.5, 3.0, 1.2)),
	]
	await _frames(15)
	_key_ev(KEY_E, true)
	await _frames(2)
	_key_ev(KEY_E, false)
	await _frames(2)
	print("SURROUNDED_EXIT is_driving=", vi.is_driving, " prompt=", hud.prompt_label.text)
	_check(vi.is_driving and hud.prompt_label.text == "Exit blocked",
		"Surrounded vehicle blocks exit and shows 'Exit blocked' prompt")

	for w in walls:
		w.queue_free()
	await _frames(15)

	# Exit now that obstacles are cleared
	_key_ev(KEY_E, true)
	await _frames(2)
	_key_ev(KEY_E, false)
	await _frames(28)
	_check(not vi.is_driving, "Exit succeeds once obstacles are cleared")


func _verify_camera_spring_arms() -> void:
	var player: CharacterBody3D = _world.player
	var car: VehicleBody3D = _world.vehicle

	# Player SpringArm3D collision test (layer 1 wall 1.1m behind player camera pivot)
	player.respawn()
	await _frames(20)
	var p_pivot: Node3D = player.camera_pivot
	var p_cam: Camera3D = player.get_camera()
	var p_dist_open := p_cam.global_position.distance_to(p_pivot.global_position)
	# At yaw=PI, camera is behind player at -Z relative to world? Wait: pivot rotation.y = PI -> -Z is +Z world, +Z (arm back) is -Z world!
	var arm_dir: Vector3 = p_pivot.global_basis.z.normalized()
	var p_wall := _make_box_obstacle(p_pivot.global_position + arm_dir * 1.1, Vector3(4.0, 4.0, 0.4))
	await _frames(10)
	var p_dist_blocked := p_cam.global_position.distance_to(p_pivot.global_position)
	p_wall.queue_free()
	await _frames(5)
	print("PLAYER_SPRING_ARM open=", p_dist_open, " blocked=", p_dist_blocked)
	_check(p_dist_open > 2.8 and p_dist_blocked < 1.5,
		"Player SpringArm3D shortens against layer-1 wall (open=" + str(p_dist_open) + ", blocked=" + str(p_dist_blocked) + ")")

	# Vehicle SpringArm3D collision test (layer 1 wall 1.6m behind vehicle camera pivot)
	car.respawn()
	player.global_position = car.global_position + Vector3(-2.0, 0.2, 0.0)
	await _frames(10)
	_key_ev(KEY_E, true)
	await _frames(2)
	_key_ev(KEY_E, false)
	await _frames(28)

	var v_pivot: Node3D = car.camera_pivot
	var v_cam: Camera3D = car.get_camera()
	var v_dist_open := v_cam.global_position.distance_to(v_pivot.global_position)
	var v_arm_dir: Vector3 = v_pivot.global_basis.z.normalized()
	var v_wall := _make_box_obstacle(v_pivot.global_position + v_arm_dir * 1.6, Vector3(5.0, 4.0, 0.4))
	await _frames(10)
	var v_dist_blocked := v_cam.global_position.distance_to(v_pivot.global_position)
	v_wall.queue_free()
	await _frames(5)
	print("VEHICLE_SPRING_ARM open=", v_dist_open, " blocked=", v_dist_blocked)
	_check(v_dist_open > 4.5 and v_dist_blocked < 2.2,
		"Vehicle SpringArm3D shortens against layer-1 wall (open=" + str(v_dist_open) + ", blocked=" + str(v_dist_blocked) + ")")

	# Exit back to on-foot cleanly
	_key_ev(KEY_E, true)
	await _frames(2)
	_key_ev(KEY_E, false)
	await _frames(28)


func _verify_flyover_toggles() -> void:
	var vi = _world.vehicle_interaction
	var hud = _world.hud
	var car: VehicleBody3D = _world.vehicle

	# On-Foot -> Flyover -> On-Foot
	_key_ev(KEY_F7, true)
	await _frames(3)
	_key_ev(KEY_F7, false)
	_check(not _world.walking and root.get_camera_3d() == _world.camera and hud.mode_label.text == "FLYOVER",
		"F7 toggles On-Foot -> Flyover")
	var car_fly_pos := car.global_position
	await _frames(10)
	var fly_drift := car.global_position.distance_to(car_fly_pos)
	print("FLYOVER_PAUSE paused=", vi.is_vehicle_paused(), " grav=", car.gravity_scale, " phys=", car.is_physics_processing(), " drift=", fly_drift)
	_check(vi.is_vehicle_paused() and is_zero_approx(car.gravity_scale) and not car.is_physics_processing() and fly_drift < 0.25,
		"Vehicle pauses cleanly in Flyover mode (drift=" + str(fly_drift) + ")")

	_key_ev(KEY_F7, true)
	await _frames(3)
	_key_ev(KEY_F7, false)
	await _frames(2)
	var car_pos_valid := is_finite(car.global_position.x) and is_finite(car.global_position.y) and is_finite(car.global_position.z)
	_check(car_pos_valid, "Vehicle transform remains finite after Flyover -> On-Foot resume")
	if not car_pos_valid:
		return
	await _frames(3)
	_check(_world.walking and root.get_camera_3d() == _world.player.get_camera() and hud.mode_label.text == "ON FOOT",
		"F7 toggles Flyover -> On-Foot cleanly")
	_check(not vi.is_vehicle_paused() and is_equal_approx(car.gravity_scale, 1.0) and car.is_physics_processing(),
		"Vehicle resumes cleanly returning from Flyover")

	# Enter vehicle -> Driving -> Flyover -> Bookmark 3 (far Airport) -> Driving
	_world.player.global_position = car.global_position + Vector3(-2.0, 0.2, 0.0)
	await _frames(5)
	_key_ev(KEY_E, true)
	await _frames(2)
	_key_ev(KEY_E, false)
	await _frames(28)
	_check(vi.is_driving, "Entered vehicle before Driving->Flyover check")

	_key_ev(KEY_F7, true)
	await _frames(3)
	_key_ev(KEY_F7, false)
	_check(not _world.walking and root.get_camera_3d() == _world.camera and hud.mode_label.text == "FLYOVER",
		"F7 toggles Driving -> Flyover")
	_check(vi.is_vehicle_paused(), "Vehicle pauses in Driving -> Flyover")

	# Jump to Bookmark 3 (Airport) while in Flyover, wait for tile update, then F7 back to Driving
	_key_ev(KEY_3, true)
	await _frames(2)
	_key_ev(KEY_3, false)
	await _frames(25)
	_check(not _world.walking and _world.camera.position.distance_to(Vector3(3800, 350, -2700)) < 1.0,
		"Bookmark 3 moves Flyover camera to Airport")

	_key_ev(KEY_F7, true)
	await _frames(3)
	_key_ev(KEY_F7, false)
	await _frames(8)
	_check(_world.walking and vi.is_driving and root.get_camera_3d() == car.get_camera() and hud.mode_label.text == "DRIVING",
		"F7 toggles far Flyover (Bookmark 3) -> Driving cleanly")
	_check(not vi.is_vehicle_paused() and car.global_position.is_finite(),
		"Vehicle unpauses on ground after far Flyover -> Driving return")

	# F9 overlay toggle while driving, then restore
	var overlay: CanvasLayer = _world.get_node("Overlay")
	_key_ev(KEY_F9, true)
	await _frames(2)
	_key_ev(KEY_F9, false)
	_check(not overlay.visible, "F9 hides Overlay/HUD")
	_key_ev(KEY_F9, true)
	await _frames(2)
	_key_ev(KEY_F9, false)
	_check(overlay.visible, "F9 restores Overlay/HUD")

	# Exit back on foot
	_key_ev(KEY_E, true)
	await _frames(2)
	_key_ev(KEY_E, false)
	await _frames(28)

	# F8 ground mode toggle check (Terrain3D <-> GLB) and restore
	var initial_native: bool = _world.native_terrain
	_key_ev(KEY_F8, true)
	await _frames(5)
	_key_ev(KEY_F8, false)
	_check(_world.native_terrain != initial_native, "F8 toggles ground mode (" + str(initial_native) + " -> " + str(_world.native_terrain) + ")")
	_key_ev(KEY_F8, true)
	await _frames(5)
	_key_ev(KEY_F8, false)
	_check(_world.native_terrain == initial_native, "F8 toggles back to initial ground mode")


func _verify_joypad_action_inputs() -> void:
	var player: CharacterBody3D = _world.player
	var car: VehicleBody3D = _world.vehicle
	var vi = _world.vehicle_interaction

	# On-foot Left Stick + L3 Sprint + Right Stick Camera
	player.respawn()
	await _frames(15)
	var yaw_before: float = player.camera_pivot.get_yaw()
	_joy_axis_ev(JOY_AXIS_RIGHT_X, 1.0)
	await _frames(15)
	_joy_axis_ev(JOY_AXIS_RIGHT_X, 0.0)
	var yaw_after: float = player.camera_pivot.get_yaw()
	_check(absf(yaw_after - yaw_before) > 0.2, "On-foot Right Stick rotates camera")

	_joy_axis_ev(JOY_AXIS_LEFT_Y, -1.0)
	_joy_btn_ev(JOY_BUTTON_LEFT_STICK, true)
	await _frames(30)
	var joy_run_speed := Vector2(player.velocity.x, player.velocity.z).length()
	_joy_btn_ev(JOY_BUTTON_LEFT_STICK, false)
	_joy_axis_ev(JOY_AXIS_LEFT_Y, 0.0)
	_check(joy_run_speed > 6.0 and player.get_current_animation_state() == "FastRun",
		"On-foot Left Stick + L3 Sprint works cleanly (speed=" + str(joy_run_speed) + ")")

	# Joypad Y to enter vehicle, RT to accelerate, LT to brake/reverse, Y to exit
	car.respawn()
	await _frames(15)
	var j_doors := _get_door_pivots(car)
	var j_door_l: Node3D = j_doors[0]
	var j_door_r: Node3D = j_doors[1]
	player.global_position = car.global_position + Vector3(-2.0, 0.2, 0.0)
	await _frames(5)
	_joy_btn_ev(JOY_BUTTON_Y, true)
	await _frames(1)
	_joy_btn_ev(JOY_BUTTON_Y, false)
	var joy_enter_peak := _door_angle(j_door_l)
	for i in 28:
		await _frames(1)
		joy_enter_peak = maxf(joy_enter_peak, _door_angle(j_door_l))
	for i in 8:
		if _door_angle(j_door_l) < 0.01:
			break
		await _frames(1)
	_check(vi.is_driving, "Joypad Y enters vehicle")
	_check(joy_enter_peak > 0.3 and _door_angle(j_door_l) < 0.01 and _door_angle(j_door_r) < 0.01,
		"Joypad Y enter animates DoorL_Pivot open > 0.3 rad and closes flush (peak=" + str(joy_enter_peak) + ")")

	var v_cam_yaw_before: float = car.camera_pivot.global_rotation.y
	_joy_axis_ev(JOY_AXIS_RIGHT_X, 1.0)
	await _frames(15)
	_joy_axis_ev(JOY_AXIS_RIGHT_X, 0.0)
	var v_cam_yaw_after: float = car.camera_pivot.global_rotation.y
	_check(absf(v_cam_yaw_after - v_cam_yaw_before) > 0.15, "Driving Right Stick rotates chase camera")

	_joy_axis_ev(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	await _frames(60)
	var rt_speed: float = car.get_forward_speed_mps()
	_joy_axis_ev(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	_check(rt_speed > 5.0, "Driving RT trigger accelerates vehicle (fwd_speed=" + str(rt_speed) + ")")

	_joy_axis_ev(JOY_AXIS_TRIGGER_LEFT, 1.0)
	await _frames(90)
	var lt_speed: float = car.get_forward_speed_mps()
	_joy_axis_ev(JOY_AXIS_TRIGGER_LEFT, 0.0)
	_check(lt_speed < -1.5, "Driving LT trigger brakes and reverses vehicle (fwd_speed=" + str(lt_speed) + ")")

	_joy_btn_ev(JOY_BUTTON_B, true)
	await _frames(50)
	_joy_btn_ev(JOY_BUTTON_B, false)
	await _frames(10)
	_check(car.can_exit(), "Driving B handbrake stops vehicle")

	_joy_btn_ev(JOY_BUTTON_Y, true)
	await _frames(1)
	_joy_btn_ev(JOY_BUTTON_Y, false)
	var joy_exit_peak := _door_angle(j_door_l)
	for i in 28:
		await _frames(1)
		joy_exit_peak = maxf(joy_exit_peak, _door_angle(j_door_l))
	for i in 8:
		if _door_angle(j_door_l) < 0.01:
			break
		await _frames(1)
	_check(not vi.is_driving, "Joypad Y exits vehicle")
	_check(joy_exit_peak > 0.3 and _door_angle(j_door_l) < 0.01 and _door_angle(j_door_r) < 0.01,
		"Joypad Y exit animates DoorL_Pivot open > 0.3 rad and closes flush (peak=" + str(joy_exit_peak) + ")")
