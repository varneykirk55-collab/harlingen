extends SceneTree
## Headless smoke test, or frame capture on a running graphical display.

func _initialize() -> void:
	call_deferred("_check")

func _check() -> void:
	var city: Node3D = load("res://preview/Harlingen.tscn").instantiate()
	root.add_child(city)
	for i in 5:
		await physics_frame
		await process_frame
	var scene_tiles: Dictionary = city.loaded
	var city_terrain: Terrain3D = city.terrain
	var active_regions: int = city_terrain.data.get_regions_active().size()
	var native_ground: bool = city.native_terrain
	var world := root.world_3d.direct_space_state
	var ground := world.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(205, 74, 320), Vector3(205, -5, 320)))
	var tower := world.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(211, 90, 350), Vector3(211, 13, 350)))
	var compiled_height: float = city_terrain.data.get_height(Vector3(300, 0, 440))
	print("MODE=", "Terrain3D" if native_ground else "GLB", " REGIONS=",active_regions,
		" DISTRICTS=",scene_tiles.size()," TERRAIN_Y=",compiled_height," GROUND=",ground.get("position"),
		" BAXTER_ROOF=",tower.get("position"))
	if active_regions != 100 or scene_tiles.is_empty() or not is_finite(compiled_height):
		quit(1)
		return
	var args := OS.get_cmdline_user_args()
	var non_downtown := false
	for arg: String in args:
		if arg.begins_with("--view=") and not arg.ends_with("=1"):
			non_downtown = true
	if not non_downtown and (ground.is_empty() or tower.is_empty() or tower.position.y < 40.0):
		push_error("Expected ground and Baxter roof collision")
		quit(2)
		return
	for arg: String in args:
		if arg.begins_with("--capture="):
			if DisplayServer.get_name() == "headless":
				quit(3)
				return
			await RenderingServer.frame_post_draw
			var start_us := Time.get_ticks_usec()
			for step in 24:
				await process_frame
				await RenderingServer.frame_post_draw
			var mean_ms := (Time.get_ticks_usec() - start_us) / 24000.0
			var shot := root.get_texture().get_image()
			var path := arg.trim_prefix("--capture=")
			if not shot or shot.save_png(path) != OK:
				quit(4)
				return
			print("CAPTURE ",shot.get_size()," MEAN_FRAME_MS=",mean_ms,
				" DRAW_CALLS=",RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
				" PRIMITIVES=",RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	quit()
