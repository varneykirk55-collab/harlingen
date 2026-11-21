extends SceneTree
## Compile the editable Terrain3D regions from the included signed-range R16.

func _initialize() -> void:
	call_deferred("_import")

func _import() -> void:
	var terrain := Terrain3D.new()
	terrain.region_size = 256
	terrain.vertex_spacing = 5.0
	terrain.free_editor_textures = false
	root.add_child(terrain)
	var map_path := ProjectSettings.globalize_path("res://terrain/harlingen_height.r16")
	var height := Terrain3DUtil.load_image(map_path, ResourceLoader.CACHE_MODE_IGNORE,
		Vector2(-4, 28), Vector2i(2560, 2560))
	var color := Image.load_from_file(ProjectSettings.globalize_path("res://terrain/surface_color.png"))
	if height == null or height.is_empty() or color == null or color.is_empty():
		push_error("Terrain raster load failed")
		quit(1)
		return
	var images: Array[Image] = [height, null, color]
	terrain.data.import_images(images, Vector3(-6400, 0, -6400), 0.0, 1.0)
	var count := terrain.data.get_regions_active().size()
	print("REGIONS=",count," SAMPLE=",terrain.data.get_height(Vector3(300,0,440)))
	if count != 100:
		quit(2)
		return
	var directory := "res://terrain/regions"
	DirAccess.make_dir_recursive_absolute(directory)
	terrain.data.save_directory(directory)
	quit()
