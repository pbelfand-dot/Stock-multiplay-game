extends SceneTree
## The environment library's numbers as a Markdown table (for docs/ENVIRONMENT_INVENTORY.md):
## each asset in data/environment_assets.json, its kind, file, triangles at each level of
## detail, size (m) and source.  godot --headless --path . -s tools/env_stats.gd

func _tris(m: Mesh) -> int:
	if m == null:
		return 0
	var n := 0
	for si in m.get_surface_count():
		var idx: int = m.surface_get_array_index_len(si)
		n += (idx if idx > 0 else m.surface_get_array_len(si)) / 3
	return n


func _initialize() -> void:
	var EnvAssets = load("res://scripts/stage/env_assets.gd")
	var f := FileAccess.open("res://data/environment_assets.json", FileAccess.READ)
	var all: Dictionary = JSON.parse_string(f.get_as_text()).assets
	print("| Asset | Kind | Runtime file | Triangles (LOD0 / LOD1 / far card) | Size (m) | Source |")
	print("|---|---|---|---|---|---|")
	var ids: Array = all.keys()
	ids.sort()
	for id in ids:
		var a: Dictionary = all[id]
		var tris := ""
		var size := Vector3.ZERO
		if str(a.kind) == "tree":
			var m0: Mesh = EnvAssets.mesh(id, "LOD0")
			tris = "%d / %d / %d" % [_tris(m0), _tris(EnvAssets.mesh(id, "LOD1")), _tris(EnvAssets.mesh(id, "BB"))]
			size = m0.get_aabb().size if m0 else Vector3.ZERO
		else:
			var m: Mesh = EnvAssets.mesh(id)
			tris = str(_tris(m))
			size = m.get_aabb().size if m else Vector3.ZERO
			size *= float(a.get("scale", 1.0))
		print("| `%s` | %s | %s | %s | %.1f x %.1f x %.1f | %s |" % [id, a.kind, str(a.glb).get_file(), tris, size.x, size.y, size.z, a.get("source", "")])
	quit()
