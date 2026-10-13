extends RefCounted
## A car's own cabin made to look as a real one does, once its model is built (RallyCar._build_own_model,
## after CarLook): the game rips' materials come with every kind of setting.
##   * matte(): the cabin's leather, plastic, fabric and headliner matte. A material that covers the
##     cabin (its faces inside the cabin's box: between the doors, the floor to the roof, the windscreen
##     to behind the seats) left shiny (roughness under ROUGH_FLOOR: the KAISER 235 GC's whole cabin at 0,
##     half metallic, a mirror; the BOLT W16's left at glTF's default metallic 1) gets the roughness its
##     kind has (leather, suede, fabric, plastic ...) and no metal. Lacquered trim (piano black, gloss,
##     carbon: by name) stays glossy but not a mirror (GLOSS_FLOOR, no metal; a whole cabin "in gloss",
##     more than GLOSS_AREA of it, satin). Left as they are: glass and screens, chrome and bare metal
##     (by name: a game rip's metallic setting says nothing), mirrors, lamps, the paint, the wheels,
##     logos, and a material mostly outside the cabin.
##   * wheel_strays(): pieces the import's steering wheel cut took from round it (the KAISER 235 GC's two
##     slivers of A-pillar trim, turning with the wheel): every touching piece of the wheel's mesh whose
##     middle lies further than WHEEL_ROOM past its rim, or WHEEL_AXIS along its column, or any point of
##     which reaches past WHEEL_REACH (the WARHAWK's stalk), goes back into the body (a piece of the wheel
##     itself reaching a little further, a paddle, a rim's edge, stays).
##   * glass_inside(): the windows hardly reflect seen from your seat (RallyCar.set_outside).
## tests/interior_check.gd checks the first two in every car.

const ROUGH_FLOOR := 0.4                  # a cabin surface under this is shiny unless it's glass, chrome or lacquer
const GLASS_WORDS := ["glass", "window", "windshield", "windscreen", "vitre", "cristal", "crystal", "screen", "display",
	"lcd", "monitor", "mirror", "miroir"]
const METAL_WORDS := ["chrome", "metal", "alu", "steel", "silver", "brushed", "titan", "nickel"]
const LEAVE_WORDS := ["paint", "lamp", "headl", "taill", "light_", "_light", "lights", "lens", "glow", "emis", "rim_", "_rim",
	"rims", "tire", "tyre", "logo", "badge", "emblem"]
const GLOSS_WORDS := ["piano", "gloss", "lacquer", "carbon"]
const GLOSS_FLOOR := 0.18                 # lacquered trim's roughness, at the least: glossy, not a mirror
const GLOSS_AREA := 3.0                   # m2: more than this of the cabin "in gloss" is the whole cabin: satin (ROUGH_FLOOR)
const KINDS := [                          # [words in the material's name, its roughness]
	[["alcantara", "suede", "textil", "fabric", "cloth", "felt", "headliner", "roof", "carpet", "floor"], 0.9],
	[["leather", "leder", "nappa", "seat"], 0.62],
	[["plastic", "plas", "dash", "trim", "door", "panel"], 0.7],
]
const ROUGH_DEFAULT := 0.66
const CABIN_SHARE := 0.4                  # a material with less of its area inside the cabin than this is the outside's
const CABIN_AREA := 0.05                  # m2: less than this inside: not the cabin's
const WHEEL_ROOM := 0.1                   # m past the rim's radius a piece of the steering wheel may sit (paddles, the rim's edge)
const WHEEL_AXIS := 0.25                  # m along the column either way (the models' axes point either way): the hub, the boss
const WHEEL_REACH := 0.16                 # m past the rim no point of anything on the wheel goes
const WHEEL_REACH_AXIS := 0.33            # ... nor along its column

const GLASS_INSIDE_SPECULAR := 0.1        # the windows' reflection, seen from your seat (CarLook's glass: 0.65)

const DashLive = preload("res://scripts/vehicle/dash_live.gd")


## The car's windows as you see them from your seat (RallyCar.set_outside): inside, they hardly
## reflect (a real windscreen shows you little of the sky; ours, made to shine from outside, put a sun's
## glint and a bright band of sky on the glass by the pillar that slid across it as the car turned: "a
## piece of the windscreen moving with the steering", the KAISER 320); outside, they shine again.
static func glass_inside(model: Node3D, inside: bool) -> void:
	if not model.has_meta("glass_swaps"):
		var swaps: Array = []
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.mesh == null:
				continue
			for s in m.mesh.get_surface_count():
				var mat := m.get_active_material(s)
				if not (mat is BaseMaterial3D) or (mat as BaseMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_DISABLED \
						or kind(mat as BaseMaterial3D) != "glass":
					continue
				var dim := (mat as BaseMaterial3D).duplicate() as BaseMaterial3D
				dim.metallic_specular = minf(dim.metallic_specular, GLASS_INSIDE_SPECULAR)
				dim.specular_mode = BaseMaterial3D.SPECULAR_DISABLED   # (no sun glint)
				dim.metallic = 0.0
				swaps.append([m, s, m.get_surface_override_material(s), dim])
		model.set_meta("glass_swaps", swaps)
	for sw in model.get_meta("glass_swaps"):
		if is_instance_valid(sw[0]):
			(sw[0] as MeshInstance3D).set_surface_override_material(sw[1], sw[3] if inside else sw[2])


## The cabin's box (model space), from parts.json's cockpit: AABB() when it has none.
static func cabin_box(info: Dictionary) -> AABB:
	var ck: Dictionary = info.get("cockpit", {})
	if ck.is_empty() or not ck.has("eye") or not info.has("body_min"):
		return AABB()
	var eye := Vector3(ck.eye[0], ck.eye[1], ck.eye[2])
	var wz: float = float(ck.wheel.centre[2]) if ck.has("wheel") else eye.z - 0.5
	var lo := Vector3(info.body_min[0], info.body_min[1], info.body_min[2])
	var hi := Vector3(info.body_max[0], info.body_max[1], info.body_max[2])
	return AABB(Vector3(lo.x + 0.06, eye.y - 1.0, wz - 0.75), Vector3(hi.x - lo.x - 0.12, 1.3, eye.z + 1.3 - (wz - 0.75)))


## The materials on the model's surfaces (not the wheels'): {material: [area inside the cabin m2, all m2]}.
static func cabin_materials(model: Node3D, box: AABB) -> Dictionary:
	var out := {}
	if not box.has_volume():
		return out
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null or _on_wheels(m, model):
			continue
		var xf := _rel(m, model)
		for s in m.mesh.get_surface_count():
			var mat := m.get_active_material(s)
			if not (mat is BaseMaterial3D) or m.mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var arr := m.mesh.surface_get_arrays(s)
			var vs: PackedVector3Array = xf * (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array)
			var ids = arr[Mesh.ARRAY_INDEX]
			if ids == null or (ids as PackedInt32Array).is_empty():
				ids = PackedInt32Array(range(vs.size()))
			var inside := 0.0
			var all := 0.0
			for t in range(0, ids.size() - 2, 3):
				var a: Vector3 = vs[ids[t]]
				var b: Vector3 = vs[ids[t + 1]]
				var c: Vector3 = vs[ids[t + 2]]
				var ar := (b - a).cross(c - a).length() * 0.5
				all += ar
				if box.has_point((a + b + c) / 3.0):
					inside += ar
			var e: Array = out.get(mat, [0.0, 0.0])
			out[mat] = [e[0] + inside, e[1] + all]
	return out


## What a cabin material is, by its name: "glass" (and screens, mirrors), "metal" (chrome, alu ...), "leave"
## (paint, lamps, logos ...), "gloss" (piano black, lacquered carbon) or "" (leather, plastic, fabric ...).
static func kind(mat: BaseMaterial3D) -> String:
	var n := String(mat.resource_name).to_lower()
	for k in [["glass", GLASS_WORDS], ["metal", METAL_WORDS], ["leave", LEAVE_WORDS], ["gloss", GLOSS_WORDS]]:
		for w in k[1]:
			if w in n:
				return k[0]
	if mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED and mat.roughness <= 0.1 and mat.metallic <= 0.05:
		return "glass"                           # (see-through, smooth, no metal: a window by another name)
	return ""


## Whether a cabin material may stay under ROUGH_FLOOR: glass, chrome, lacquer (not a mirror), what's left alone.
static func may_shine(mat: BaseMaterial3D, area_in: float) -> bool:
	var k := kind(mat)
	if k == "gloss":
		return area_in <= GLOSS_AREA and mat.roughness >= GLOSS_FLOOR - 1e-4 and mat.metallic <= 0.1 + 1e-4
	return k != ""


## Whether a material covers the cabin (by its area there): the ones matte() looks at.
static func of_cabin(e: Array) -> bool:
	return float(e[0]) >= CABIN_AREA and float(e[0]) >= CABIN_SHARE * float(e[1])


## The cabin's shiny leather, plastic and fabric made matte (copies of their materials, on every surface
## that has them). Returns how many materials it changed.
static func matte(model: Node3D, info: Dictionary) -> int:
	var mats := cabin_materials(model, cabin_box(info))
	var swap := {}
	for mat in mats:
		var bm := mat as BaseMaterial3D
		var e: Array = mats[mat]
		if not of_cabin(e) or bm.roughness >= ROUGH_FLOOR or may_shine(bm, e[0]):
			continue
		var k := kind(bm)
		var c := bm.duplicate() as BaseMaterial3D
		if k == "gloss":                         # (lacquer: glossy, no metal; a whole cabin of it, satin)
			c.roughness = maxf(bm.roughness, GLOSS_FLOOR if float(e[0]) <= GLOSS_AREA else ROUGH_FLOOR)
			c.metallic = minf(bm.metallic, 0.1)
			swap[mat] = c
			continue
		c.roughness = maxf(bm.roughness, rough_for(String(bm.resource_name)))
		c.metallic = minf(bm.metallic, 0.05)
		c.metallic_specular = minf(c.metallic_specular, 0.5)
		c.clearcoat_enabled = false
		swap[mat] = c
	if swap.is_empty():
		return 0
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		for s in m.mesh.get_surface_count():
			var cur := m.get_active_material(s)
			if swap.has(cur):
				m.set_surface_override_material(s, swap[cur])
	return swap.size()


## The roughness a cabin material's kind has (by its name).
static func rough_for(name: String) -> float:
	var n := name.to_lower()
	for k in KINDS:
		for w in k[0]:
			if w in n:
				return float(k[1])
	return ROUGH_DEFAULT


## The steering wheel's own space: whether a point (model space) is within the wheel (its rim's radius
## and `room`, WHEEL_AXIS along the column either way).
static func on_wheel_space(p: Vector3, info: Dictionary, room := WHEEL_ROOM, axis_room := WHEEL_AXIS) -> bool:
	var w: Dictionary = info.get("cockpit", {}).get("wheel", {})
	if not w.has("centre"):
		return true
	var c := Vector3(w.centre[0], w.centre[1], w.centre[2])
	var ax := Vector3(w.axis[0], w.axis[1], w.axis[2]).normalized() if w.has("axis") else Vector3.BACK
	var d := p - c
	var along := d.dot(ax)
	return absf(along) <= axis_room and (d - ax * along).length() <= float(w.get("radius", 0.18)) + room


## The pieces of the steering wheel's own mesh (the node, and meshes under it the import made) outside the
## wheel's space moved back into the body (a mesh of their own, where they were). Returns the triangles moved.
static func wheel_strays(model: Node3D, wheel: Node3D, info: Dictionary) -> int:
	if wheel == null or info.get("cockpit", {}).is_empty():
		return 0
	var moved := 0
	var meshes: Array = wheel.find_children("*", "MeshInstance3D", true, false)
	if wheel is MeshInstance3D:
		meshes.append(wheel)
	for mi in meshes:
		var m := mi as MeshInstance3D
		if m.mesh == null or m.name in ["WheelPart", "LivePanel", "LiveBoard"]:
			continue
		var xf := _rel(m, model)
		var split: Array = []                    # per surface: [arrays, indices, the triangles kept, the ones moved]
		var any := false
		for s in m.mesh.get_surface_count():
			var arr := m.mesh.surface_get_arrays(s)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var wv: PackedVector3Array = xf * vs
			var ids = arr[Mesh.ARRAY_INDEX]
			if ids == null or (ids as PackedInt32Array).is_empty():
				ids = PackedInt32Array(range(vs.size()))
			var ins: Array = []
			var outs: Array = []
			for g in DashLive._groups(wv, ids, range(ids.size() / 3)):
				var mid := Vector3.ZERO
				var reach := true
				for t in g:
					for k in 3:
						mid += wv[ids[t * 3 + k]]
						reach = reach and on_wheel_space(wv[ids[t * 3 + k]], info, WHEEL_REACH, WHEEL_REACH_AXIS)
				if reach and on_wheel_space(mid / (g.size() * 3.0), info):
					ins.append_array(g)
				else:
					outs.append_array(g)
			split.append([arr, ids, ins, outs])
			if not outs.is_empty():
				any = true
				moved += outs.size()
		if not any:
			continue
		var keep := ArrayMesh.new()
		var stray := ArrayMesh.new()
		for s in split.size():
			var mat := m.mesh.surface_get_material(s)
			_add(keep, split[s][0], split[s][1], split[s][2], mat)
			_add(stray, split[s][0], split[s][1], split[s][3], mat)
		var overrides: Array = []
		for s in m.mesh.get_surface_count():
			overrides.append(m.get_surface_override_material(s))
		m.mesh = keep
		for s in mini(overrides.size(), keep.get_surface_count()):
			m.set_surface_override_material(s, overrides[s])
		var back := MeshInstance3D.new()
		back.name = "WheelStrays"
		back.mesh = stray
		back.transform = xf
		back.layers = m.layers
		back.cast_shadow = m.cast_shadow
		model.add_child(back)
	return moved


## Some of a surface's triangles as a surface of `to` (an empty surface when there are none: the surfaces stay
## numbered as the source's, its overrides with them).
static func _add(to: ArrayMesh, arr: Array, ids: PackedInt32Array, tris: Array, mat: Material) -> void:
	var out := arr.duplicate()
	for a in [Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3, Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS]:
		out[a] = null                          # (a static mesh: no custom channels or skin, whose formats would need flags)
	var idx := PackedInt32Array()
	for t in tris:
		idx.append(ids[t * 3])
		idx.append(ids[t * 3 + 1])
		idx.append(ids[t * 3 + 2])
	if idx.is_empty():                         # (a degenerate triangle keeps the surface's place)
		idx = PackedInt32Array([0, 0, 0])
	out[Mesh.ARRAY_INDEX] = idx
	to.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	to.surface_set_material(to.get_surface_count() - 1, mat)


static func _on_wheels(n: Node, top: Node) -> bool:
	var p: Node = n
	while p and p != top:
		var s := String(p.name)
		if s.begins_with("Wheel_") or s.begins_with("Caliper_"):
			return true
		p = p.get_parent()
	return false


static func _rel(n: Node3D, top: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var p: Node = n
	while p and p != top:
		if p is Node3D:
			xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf
