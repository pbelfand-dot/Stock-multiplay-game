extends RefCounted
## The WheelPreset system: a wheel type (data/wheel_presets.json) fitted to a car, corner by corner,
## and built as an assembly of separate parts. Static: `const WheelPresets = preload(...)`.
##
##   WheelPresets.preset(id) -> Dictionary          its entry ("stock" for an unknown id)
##   WheelPresets.ids() -> Array                    every preset, in the file's order
##   WheelPresets.offered(car_id, model) -> Array   the presets the garage offers that car: its class
##                                                  (road / track / formula) and data/wheel_fit.json's
##                                                  verdict (clears the arches at full lock and bump)
##   WheelPresets.fit(id, parts, k) -> Dictionary   corner k's numbers {outer_r, width, rim_r, offset,
##                                                  side, disc_r, brake}: the tyre's outside always the
##                                                  car's own (the physics radius doesn't change)
##   WheelPresets.assemble(id, fit) -> Dictionary   {spin: Node3D (tyre, rim, disc: they roll), fixed:
##                                                  Node3D (the caliper: on the upright)}, each part a
##                                                  MeshInstance3D named Tyre / Rim / Disc / Caliper,
##                                                  near and far meshes (LODs by visibility range); a
##                                                  left wheel mirrored, as it's mounted
##
## RallyCar puts the assembly on a car with a model of its own (its STOCK wheels hidden, not
## replaced: STOCK shows them again). In the car model's frame: x right, the wheel's face outwards.

const WheelGen = preload("res://scripts/vehicle/wheel_gen.gd")
const DATA := "res://data/wheel_presets.json"
const FIT := "res://data/wheel_fit.json"
const MESHES := "res://assets/wheels/"
const NEAR_M := 22.0                 # the full-detail mesh out to here, the lighter one past it

static var _data := {}
static var _fit := {}
static var _scenes := {}


static func _load() -> void:
	if not _data.is_empty():
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	_data = d if d is Dictionary else {"presets": {"stock": {"name": "STOCK", "kind": "stock"}}, "brakes": {}, "far": {}}
	var f = JSON.parse_string(FileAccess.get_file_as_string(FIT)) if FileAccess.file_exists(FIT) else null
	_fit = f.get("models", {}) if f is Dictionary else {}


static func ids() -> Array:
	_load()
	return (_data.presets as Dictionary).keys()


static func preset(id: String) -> Dictionary:
	_load()
	return _data.presets.get(id, _data.presets.stock)


static func brake(id: String) -> Dictionary:
	_load()
	return _data.brakes.get(id, {"disc_k": 0.8, "pistons": 2, "caliper": [0.16, 0.16, 0.17]})


## A car's class for the wheels: what it races in.
static func car_class(role: String) -> String:
	if role in ["formula"]:
		return "formula"
	if role in ["track", "race_prototype"]:
		return "track"
	return "road"


## The presets offered on a car (its registry role; its model's fit, measured): STOCK always.
static func offered(role: String, model: String) -> Array:
	_load()
	var out: Array = ["stock"]
	if model == "":
		return out                                       # (the Higgsfield rally cars keep their rally wheels)
	var cls := car_class(role)
	var fits: Dictionary = _fit.get(model, {})
	for id in ids():
		if id == "stock":
			continue
		var p := preset(id)
		if not cls in (p.get("classes", []) as Array):
			continue
		if bool((fits.get(id, {}) as Dictionary).get("ok", false)):
			out.append(id)
	return out


## Why a preset isn't offered on a model (the fit tool's words), "" if it is.
static func fit_note(model: String, id: String) -> String:
	_load()
	var f: Dictionary = (_fit.get(model, {}) as Dictionary).get(id, {})
	return "" if bool(f.get("ok", false)) else str(f.get("why", "not measured"))


## Corner k's wheel (parts: the model's parts.json): the tyre's outside the car's own size.
static func fit(id: String, parts: Dictionary, k: int) -> Dictionary:
	var p := preset(id)
	var outer_r := float(parts.radius[k])
	var stock_w := float(parts.width[k])
	var width := stock_w * float(p.get("width_k", 1.0))
	var rim_r: float
	if p.has("rim_in"):
		rim_r = float(p.rim_in) * 0.0254 * 0.5
	else:
		rim_r = outer_r - float(p.get("aspect", 0.35)) * width
	rim_r = clampf(rim_r, outer_r * 0.55, outer_r - 0.045)          # (no toy rims, no rubber bands)
	var b := brake(str(p.get("brake", "street")))
	var inner := WheelGen.drop_r(rim_r)                               # (the barrel's narrowest: its drop centre)
	var disc_r := minf(inner * float(b.disc_k), inner - 0.008 - (WheelGen.caliper_reach(0.0)))   # (the caliper clears it by 8 mm)
	return {"outer_r": outer_r, "width": width, "stock_w": stock_w, "rim_r": rim_r, "offset": float(p.get("offset", 0.0)),
		"side": 1.0 if float(parts.wheels[k][0]) > 0.0 else -1.0, "disc_r": disc_r, "brake": str(p.get("brake", "street")),
		"front": k < 2}


## The assembly for one corner.
static func assemble(id: String, f: Dictionary) -> Dictionary:
	var p := preset(id)
	var spin := Node3D.new()
	spin.name = "WheelAssembly"
	var fixed := Node3D.new()
	fixed.name = "BrakeFixed"
	var mirror := Transform3D(Basis.from_scale(Vector3(float(f.side), 1.0, 1.0)), Vector3(float(f.side) * float(f.offset), 0.0, 0.0))
	var b := brake(str(f.brake))
	if str(p.get("build", "gen")) == "mesh":
		_mesh_wheel(spin, str(p.mesh), f, mirror)
	else:
		var tread := str(p.get("tread", "street"))
		_lod(spin, "Tyre", WheelGen.tyre(f.outer_r, f.width, f.rim_r, tread, WheelGen.SEG_HI),
			WheelGen.tyre(f.outer_r, f.width, f.rim_r, tread, WheelGen.SEG_LO), mirror, far_m())
		var style: Dictionary = p.get("rim", {})
		_lod(spin, "Rim", WheelGen.rim(f.rim_r, f.width, style, WheelGen.SEG_HI), WheelGen.rim(f.rim_r, f.width, style, WheelGen.SEG_LO), mirror, far_m())
	var bx := WheelGen.brake_x(f.width, p.get("rim", {}), int(b.pistons))
	var disc_mesh := WheelGen.disc(f.disc_r, f.rim_r * 0.42, bx, WheelGen.SEG_HI)
	var disc := _lod(spin, "Disc", disc_mesh, WheelGen.disc(f.disc_r, f.rim_r * 0.42, bx, WheelGen.SEG_LO), mirror, NEAR_M * 3.0)
	if b.has("disc_colour"):
		var dm := StandardMaterial3D.new()
		dm.albedo_color = _col(b.disc_colour)
		dm.roughness = 0.55
		for mi in disc:
			(mi as MeshInstance3D).set_surface_override_material(0, dm)
	var cal := MeshInstance3D.new()
	cal.name = "Caliper"
	cal.mesh = WheelGen.caliper(f.disc_r, bx, int(b.pistons))
	cal.transform = mirror
	cal.visibility_range_end = NEAR_M * 3.0
	var cm := StandardMaterial3D.new()
	cm.albedo_color = _col(b.caliper)
	cm.roughness = 0.32
	cm.metallic = 0.2
	cal.set_surface_override_material(0, cm)
	fixed.add_child(cal)
	_far(spin, str(p.get("far", _data.far.get(str(p.get("kind", "street")), _data.far.get("street", "")))), f, mirror)
	return {"spin": spin, "fixed": fixed}


## Where the far stand-ins take over (m).
static func far_m() -> float:
	_load()
	return float(_data.far.get("far_m", 70.0))


## The rim's paint (the garage's wheel colour) on an assembly.
static func paint(spin: Node3D, colour: Color) -> void:
	var m := StandardMaterial3D.new()
	m.resource_name = "rim_paint"
	m.albedo_color = colour
	m.metallic = 0.75
	m.roughness = 0.3
	var rims: Array = spin.get_children()
	var far := spin.get_node_or_null("Far")
	if far:
		rims += far.find_children("Rim*", "MeshInstance3D", true, false)
	for n in rims:
		if n is MeshInstance3D and str(n.name).begins_with("Rim"):
			var mi := n as MeshInstance3D
			for i in mi.mesh.get_surface_count():
				var sm := mi.mesh.surface_get_material(i)
				if sm and sm.resource_name == "rim_paint":
					mi.set_surface_override_material(i, m)


## Near and far versions of a part: the near one to NEAR_M, the lighter one from there to
## far_end (past it: the far stand-in, or nothing). Returns both.
static func _lod(parent: Node3D, part: String, near: Mesh, far: Mesh, xf: Transform3D, far_end: float) -> Array:
	var a := MeshInstance3D.new()
	a.name = part
	a.mesh = near
	a.transform = xf
	a.visibility_range_end = NEAR_M
	parent.add_child(a)
	var b := MeshInstance3D.new()
	b.name = part + "_LOD1"
	b.mesh = far
	b.transform = xf
	b.visibility_range_begin = NEAR_M
	b.visibility_range_end = far_end
	parent.add_child(b)
	return [a, b]


## Past far_m: a low-poly CC0 stand-in (assets/wheels/: the preset's own, else its kind's),
## scaled to the wheel.
static func _far(parent: Node3D, id: String, f: Dictionary, xf: Transform3D) -> void:
	var src := _scene(id)
	if src == null:
		return
	var n: Node3D = src.instantiate()
	var info := _info(id)
	var d := float(info.get("diameter", 0.0))
	var w := float(info.get("width", 0.0))
	if d <= 0.0 or w <= 0.0:
		n.free()
		return
	n.name = "Far"
	var s: float = f.outer_r * 2.0 / d
	n.transform = xf * Transform3D(Basis.from_scale(Vector3(f.width / w, s, s)), Vector3.ZERO)
	_visibility(n, far_m(), 0.0)
	parent.add_child(n)


## A converted CC0 wheel (assets/wheels/<id>/: its Tyre and Rim nodes, axle on x, face +x),
## scaled to the corner: the tyre's diameter and width.
static func _mesh_wheel(parent: Node3D, id: String, f: Dictionary, xf: Transform3D) -> void:
	var src := _scene(id)
	var info := _info(id)
	if src == null or info.is_empty():
		return
	var n: Node3D = src.instantiate()
	var s: float = f.outer_r * 2.0 / float(info.diameter)
	var sx: float = f.width / float(info.width)
	for part in ["Tyre", "Rim"]:
		var mi := n.find_child(part, true, false) as MeshInstance3D
		if mi == null:
			continue
		var m := MeshInstance3D.new()
		m.name = part
		m.mesh = mi.mesh
		m.transform = xf * Transform3D(Basis.from_scale(Vector3(sx, s, s)), Vector3.ZERO)
		m.visibility_range_end = far_m()
		parent.add_child(m)
	n.free()


static func _visibility(n: Node, begin: float, end: float) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).visibility_range_begin = begin
		(n as GeometryInstance3D).visibility_range_end = end
	for c in n.get_children():
		_visibility(c, begin, end)


static func _scene(id: String) -> PackedScene:
	if id == "":
		return null
	if not _scenes.has(id):
		var path := MESHES + id + "/" + id + ".glb"
		_scenes[id] = load(path) if ResourceLoader.exists(path) else null
	return _scenes[id]


## A converted wheel's numbers (assets/wheels/<id>/wheel.json: tools/import_wheels.py).
static func _info(id: String) -> Dictionary:
	var path := MESHES + id + "/wheel.json"
	if not FileAccess.file_exists(path):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if d is Dictionary else {}


static func _col(a) -> Color:
	return Color(float(a[0]), float(a[1]), float(a[2]))
