extends RefCounted
## Draw-call reducer: merges MeshInstance3Ds that share a material into one
## mesh. Nodes are kept (they may hold collision bodies, labels or other
## children) but their mesh is cleared, so nothing else has to change.

const MERGEABLE := ["BoxMesh", "CylinderMesh", "SphereMesh", "TorusMesh", "ArrayMesh", "PrismMesh", "QuadMesh"]


## Merge every static mesh under `root` (in root-local space), skipping any
## subtree whose top node is in `skip` (e.g. animated characters).
## With `cell` > 0 the merge is also split into cell x cell (m) floor tiles so
## frustum culling still skips what's behind the camera. Meshes are only merged
## with others that share material, render layers and shadow casting.
static func merge_static(root: Node3D, skip: Array = [], cell := 0.0) -> int:
	var groups := {}   # [material, layers, shadow, tile] -> Array[MeshInstance3D]
	_collect(root, root, skip, groups, cell)
	var merged := 0
	var inv := root.global_transform.affine_inverse()
	for key in groups:
		var list: Array = groups[key]
		if list.size() < 2:
			continue
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for mi in list:
			st.append_from(mi.mesh, 0, inv * mi.global_transform)
		var combined := MeshInstance3D.new()
		combined.mesh = st.commit()
		combined.material_override = key[0]
		combined.layers = key[1]
		combined.cast_shadow = key[2]
		combined.name = "Batch"
		root.add_child(combined)
		for mi in list:
			mi.mesh = null
		merged += list.size()
	return merged


static func _collect(node: Node, root: Node3D, skip: Array, groups: Dictionary, cell: float) -> void:
	if node in skip:
		return
	if node is MeshInstance3D and node != root:
		var mi := node as MeshInstance3D
		var m = mi.material_override
		if mi.visible and mi.is_visible_in_tree() and mi.mesh != null and m is StandardMaterial3D \
				and m.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED \
				and mi.mesh.get_class() in MERGEABLE and mi.mesh.get_surface_count() == 1 \
				and not mi.has_meta("no_batch"):
			var tile := Vector2i.ZERO
			if cell > 0.0:
				var p := root.to_local(mi.global_position)
				tile = Vector2i(floori(p.x / cell), floori(p.z / cell))
			var key := [m, mi.layers, mi.cast_shadow, tile]
			if not groups.has(key):
				groups[key] = []
			groups[key].append(mi)
	for c in node.get_children():
		_collect(c, root, skip, groups, cell)


## Per-joint merge for characters: parts under the same joint never move
## relative to each other, so each joint collapses to one mesh per material.
static func merge_joints(joints: Array) -> void:
	for jn in joints:
		var groups := {}
		for c in jn.get_children():
			if c is MeshInstance3D and c.mesh != null and c.material_override != null \
					and not c.has_meta("no_batch") and c.mesh.get_surface_count() == 1:
				var m = c.material_override
				if not groups.has(m):
					groups[m] = []
				groups[m].append(c)
		for m in groups:
			var list: Array = groups[m]
			if list.size() < 2:
				continue
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			for mi in list:
				st.append_from(mi.mesh, 0, mi.transform)
			var combined := MeshInstance3D.new()
			combined.mesh = st.commit()
			combined.material_override = m
			jn.add_child(combined)
			for mi in list:
				jn.remove_child(mi)
				mi.queue_free()
