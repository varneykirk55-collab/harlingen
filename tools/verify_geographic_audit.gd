extends SceneTree

func _initialize() -> void:
	call_deferred("_verify")

func _verify() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://source/geographic_sites.geojson"))
	var found := 0
	for feature: Dictionary in data.features:
		var properties: Dictionary = feature.properties
		var x: float = properties.label[0]
		var z: float = properties.label[1]
		var ix := floori(x / 2000.0)
		var iz := floori(z / 2000.0)
		var tile_id := "%+03d_%+03d" % [ix, iz]
		var scene := load("res://tiles/%s/district.tscn" % tile_id) as PackedScene
		if scene == null:
			push_error("Could not load landmark district " + tile_id)
			quit(1)
			return
		var district := scene.instantiate() as Node3D
		root.add_child(district)
		var sites := district.get_node_or_null("GeographicSites")
		if sites == null:
			push_error("Missing GeographicSites in " + tile_id)
			quit(1)
			return
		var verified := false
		for site: Node3D in sites.get_children():
			if site.get_meta("geographic_source", "") != feature.id:
				continue
			var label := site.get_node("MapLabel") as Label3D
			if Vector2(site.global_position.x, site.global_position.z).distance_to(Vector2(x, z)) >= 0.01:
				break
			if label.text != properties.name:
				break
			if feature.id == "thc:iwo-jima" and (
				not site.has_node("IwoJimaMemorial") or not site.has_node("PedestalCollision/Shape")
			):
				break
			print("Verified ", label.text, " in ", tile_id)
			verified = true
			found += 1
			break
		district.free()
		if not verified:
			push_error("Landmark scene or coordinates failed for " + str(feature.id))
			quit(1)
			return
	print("Geographic labels verified: ", found)
	quit(0)
