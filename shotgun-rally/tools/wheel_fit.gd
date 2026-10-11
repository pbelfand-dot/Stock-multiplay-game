extends SceneTree
## Which wheel presets fit which car: data/wheel_fit.json, read by WheelPresets.offered (the garage
## offers only those that fit). For every car model in the registry and every preset of its class,
## at every corner: the preset's tyre (its width, offset, the car's own diameter) at full steering
## lock (the fronts), up to the bump stop, and half of each together, against the body's own geometry
## (every vertex and triangle centre of the car's meshes but its wheels). It fits if it touches
## nothing the STOCK tyre, swept the same way, doesn't already touch (a model's arch liner can sit
## inside its own tyre; only what the new wheel adds counts).
##   godot --headless --path . -s tools/wheel_fit.gd [-- --only=gt3r_992,s15]
## tests/wheel_check.gd recomputes a few cars and checks the file isn't stale.

const WheelPresets = preload("res://scripts/vehicle/wheel_presets.gd")
const CarSpecs = preload("res://scripts/vehicle/car_specs.gd")
const OUT := "res://data/wheel_fit.json"
const SKIP := ["Wheel_", "Caliper_", "SteeringWheel", "Shifter", "Handbrake"]
const MARGIN := 0.006                # m round the tyre: closer than this is a touch
const MAX_EXTRA := 3                 # body points inside the new tyre's sweep and not the stock one's (mesh noise)


func _initialize() -> void:
	var only: Array = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.trim_prefix("--only=").split(",")
	var models := car_models()
	var out := {"_doc": "Made by tools/wheel_fit.gd: per car model, per wheel preset of its class, does it clear the body at full lock and full bump (ok), the closest it comes (clear_mm: the body's nearest point outside the tyre, worst corner) and why not. Don't edit: run the tool.",
		"presets_hash": presets_hash(), "models": {}}
	if FileAccess.file_exists(OUT) and not only.is_empty():
		var old = JSON.parse_string(FileAccess.get_file_as_string(OUT))
		if old is Dictionary:
			out.models = old.get("models", {})
	for m in models:
		if not only.is_empty() and not m.model in only:
			continue
		var t := Time.get_ticks_msec()
		out.models[m.model] = measure(m.model, str(m.role))
		var oks: Array = []
		for p in out.models[m.model]:
			if out.models[m.model][p].ok:
				oks.append(p)
		print("[fit] %-16s %-14s %4d ms  fits: %s" % [m.model, m.role, Time.get_ticks_msec() - t, ", ".join(oks)])
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string(JSON.stringify(out, " ", false) + "\n")
	f.close()
	print("[fit] wrote ", OUT)
	quit(0)


## Every car model in the registry: [{model, role}].
static func car_models() -> Array:
	var out: Array = []
	var seen := {}
	var d := DirAccess.open("res://data/vehicles")
	for fn in d.get_files():
		if not fn.ends_with(".json"):
			continue
		var v = JSON.parse_string(FileAccess.get_file_as_string("res://data/vehicles/" + fn))
		if v is Dictionary and str(v.get("model", "")) != "" and v.has("garage") and not seen.has(v.model):
			seen[v.model] = true
			out.append({"model": str(v.model), "role": str(v.get("role", ""))})
	out.sort_custom(func(a, b): return a.model < b.model)
	return out


## A hash of the presets' numbers that decide the fit (classes, width, offset, sidewall, rim size):
## the fit's stale when they change, not when a name or a far stand-in does.
static func presets_hash() -> String:
	var parts: Array = []
	for id in WheelPresets.ids():
		var p := WheelPresets.preset(id)
		parts.append([id, p.get("classes", []), p.get("width_k", 1.0), p.get("offset", 0.0), p.get("aspect", 0.35), p.get("rim_in", 0)])
	return JSON.stringify(parts).md5_text()


## One car model: {preset: {ok, clear_mm, why}} for the presets of its class.
static func measure(model: String, role: String) -> Dictionary:
	var parts := CarSpecs.parts(model)
	var res := {}
	if parts.is_empty():
		return res
	var pts := body_points(model)
	var cfg = CarSpecs.config(model)
	var lock := deg_to_rad(float(cfg.steering.max_angle_deg))
	var bumps := bump_room(cfg)
	var cls := WheelPresets.car_class(role)
	for id in WheelPresets.ids():
		if id == "stock":
			continue
		var p := WheelPresets.preset(id)
		if not cls in (p.get("classes", []) as Array):
			continue
		var ok := true
		var why := ""
		var clear := INF
		for k in 4:
			var c := Vector3(float(parts.wheels[k][0]), float(parts.wheels[k][1]), float(parts.wheels[k][2]))
			var f := WheelPresets.fit(id, parts, k)
			var near := points_near(pts, c, float(f.outer_r) + 0.14)
			# (as a fitment check is done: full lock at ride height, full bump straight, and half of
			# each together; full lock and full bump at once is the bump stop's job, not the tyre's)
			var bump := float(bumps[0 if k < 2 else 1])
			var poses: Array = [[0.0, 0.0], [0.0, bump]]
			if k < 2:
				poses += [[lock, 0.0], [-lock, 0.0], [lock * 0.5, bump * 0.5], [-lock * 0.5, bump * 0.5]]
			var extra := 0
			var worst := ""
			for ps in poses:
				var n_new := 0
				for q in near:
					var a := inside(q, c, f, float(ps[0]), float(ps[1]), false, parts, k)
					if a < 0.0:
						var b := inside(q, c, f, float(ps[0]), float(ps[1]), true, parts, k)
						if b >= 0.0:
							n_new += 1
					elif ps[0] == 0.0 and ps[1] == 0.0:
						clear = minf(clear, a)
				if n_new > extra:
					extra = n_new
					worst = "%s, %s, %s" % [["front left", "front right", "rear left", "rear right"][k],
						"straight" if ps[0] == 0.0 else ("full lock" if absf(ps[0]) >= lock * 0.99 else "half lock"),
						"at ride height" if ps[1] == 0.0 else ("full bump" if ps[1] >= bump * 0.99 else "half bump")]
			if extra > MAX_EXTRA:
				ok = false
				why = "the tyre touches the body: %d points, %s" % [extra, worst]
				break
		res[id] = {"ok": ok, "clear_mm": snappedf(clear * 1000.0, 0.1) if clear != INF else -1.0, "why": why}
	return res


## The room up to the bump stops (front, rear): the travel past the car's rest (its static
## compression), at least 3 cm.
static func bump_room(cfg) -> Array:
	var Suspension = load("res://scripts/vehicle/physics/suspension.gd")
	var g := 9.8
	var loads: Array = cfg.static_loads(g)
	var out: Array = []
	for k in 2:
		var s = cfg.front_suspension if k == 0 else cfg.rear_suspension
		var c: float = Suspension.static_compression(s, loads[k])
		out.append(clampf(float(s.bump_stop_start) - c, 0.03, 0.14))
	return out


## Where a body point q is against corner k's tyre (steered `steer`, raised `up`): < 0 inside
## (the preset's tyre, or the stock one if `stock`), else the distance outside it (m).
static func inside(q: Vector3, c: Vector3, f: Dictionary, steer: float, up: float, stock: bool, parts: Dictionary, k: int) -> float:
	var r: float = float(parts.radius[k]) if stock else float(f.outer_r)
	var w: float = float(parts.width[k]) if stock else float(f.width)
	var off: float = 0.0 if stock else float(f.offset) * float(f.side)
	var l := q - c - Vector3(0.0, up, 0.0)
	l = l.rotated(Vector3.UP, -steer)
	l.x -= off
	var radial := Vector2(l.y, l.z).length() - (r + MARGIN)
	var axial := absf(l.x) - (w * 0.5 + MARGIN)
	if radial < 0.0 and axial < 0.0:
		return -1.0
	if radial > 0.0 and axial > 0.0:
		return Vector2(radial, axial).length()
	return maxf(radial, axial)


static func points_near(pts: PackedVector3Array, c: Vector3, reach: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for q in pts:
		if absf(q.x - c.x) < reach and absf(q.y - c.y) < reach and absf(q.z - c.z) < reach:
			out.append(q)
	return out


## Every vertex and triangle centre of the car model's meshes but its wheels, calipers and moving
## cockpit parts, in the model's frame (m, its origin on the ground).
static func body_points(model: String) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var sc: PackedScene = load(CarSpecs.MODELS + model + "/" + model + ".glb")
	var root := sc.instantiate()
	_collect(root, root, Transform3D.IDENTITY, pts)
	root.free()
	return pts


static func _collect(n: Node, root: Node, xf: Transform3D, pts: PackedVector3Array) -> void:
	var here := xf
	if n is Node3D and n != root:
		here = xf * (n as Node3D).transform
	for s in SKIP:
		if str(n.name).begins_with(s):
			return
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var mesh := (n as MeshInstance3D).mesh
		for i in mesh.get_surface_count():
			var arr := mesh.surface_get_arrays(i)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			for p in v:
				pts.append(here * p)
			for t in range(0, idx.size() - 2, 3):
				pts.append(here * ((v[idx[t]] + v[idx[t + 1]] + v[idx[t + 2]]) / 3.0))
	for ch in n.get_children():
		_collect(ch, root, here, pts)
