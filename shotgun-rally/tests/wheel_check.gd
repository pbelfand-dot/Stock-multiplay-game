extends SceneTree
## The WheelPreset system (data/wheel_presets.json, scripts/vehicle/wheel_presets.gd, wheel_gen.gd,
## the converted CC0 wheels in assets/wheels/, data/wheel_fit.json).
## Run: godot --headless --fixed-fps 120 --path . -s tests/wheel_check.gd
##   * the presets: every one complete (a kind, classes, a fictional name, its brakes, its mesh
##     there), every kind the garage needs (stock, street, vintage, wide, track, formula)
##   * the converted wheels: each loads with its Tyre and Rim apart, its wheel.json true to the tyre,
##     the axle on x, centred on the tyre, the face at +x
##   * every preset at every corner of three cars: the axle centre on the hub, round about the axle
##     (it spins in place), the tyre's bottom on the ground at the physics radius, the width it
##     should be, the face outwards on both sides (a left wheel mirrored, not a copy), the caliper
##     over the disc inside the barrel and clear of the rim, the tyre, rim and disc separate from
##     the caliper, near / lighter / far meshes by distance
##   * the fit: data/wheel_fit.json up to date with the presets, every garage car measured, three
##     cars measured again agree, the garage offering only what fits and suits the car's class
##   * on a car: a preset goes on (its own wheels hidden, the physics radius unchanged), the tyre
##     and disc roll with the wheel and the caliper doesn't, both steer; STOCK brings its own back;
##     a new car doesn't keep the old car's wheels
## Prints one [wheels] line per check; exits 1 on any FAIL.

const WheelPresets = preload("res://scripts/vehicle/wheel_presets.gd")
const WheelGen = preload("res://scripts/vehicle/wheel_gen.gd")
const CarSpecs = preload("res://scripts/vehicle/car_specs.gd")
const KINDS := ["stock", "street", "vintage", "wide", "track", "formula"]
const REAL_BRANDS := ["BBS", "OZ ", "ENKEI", "VOLK", "RAYS", "HRE", "VOSSEN", "WORK ", "ADVAN", "MICHELIN", "PIRELLI",
	"BRIDGESTONE", "BREMBO", "MOMO", "ROTIFORM", "WEDS", "BORBET", "RONAL", "FIKSE", "FORGIATO", "YOKOHAMA", "CONTINENTAL"]
const CARS := ["gt3r_992", "s15", "id4"]

var fails := 0


func check(ok: bool, what: String) -> void:
	print("[wheels] %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		fails += 1


func _initialize() -> void:
	await process_frame
	_presets()
	_converted()
	_assemblies()
	_fit()
	await _on_car()
	print("[wheels] %s" % ("WHEELS OK" if fails == 0 else "WHEELS FAIL"))
	quit(1 if fails else 0)


# ── the data ──────────────────────────────────────────────────────────────

func _presets() -> void:
	var kinds := {}
	var bad: Array = []
	for id in WheelPresets.ids():
		var p := WheelPresets.preset(id)
		kinds[str(p.get("kind", ""))] = true
		var nm := str(p.get("name", "")).to_upper() + " "
		for b in REAL_BRANDS:
			if nm.contains(b):
				bad.append("%s: a real brand (%s)" % [id, b])
		if not p.has("classes") or not p.has("price") or not p.has("kind"):
			bad.append("%s: incomplete" % id)
		if id == "stock":
			continue
		if not WheelPresets.brake(str(p.get("brake", ""))).has("name"):
			bad.append("%s: no brake package %s" % [id, p.get("brake")])
		for k in ["tread", "width_k", "offset", "compound", "pressure_kpa"]:
			if not p.has(k):
				bad.append("%s: no %s" % [id, k])
		if str(p.get("build", "gen")) == "mesh" and WheelPresets._scene(str(p.mesh)) == null:
			bad.append("%s: its mesh %s isn't there" % [id, p.mesh])
	var missing := KINDS.filter(func(k): return not kinds.has(k))
	check(bad.is_empty() and missing.is_empty(), "presets: %d, every one complete with its brakes and fictional names; kinds %s%s" % [
		WheelPresets.ids().size(), ", ".join(kinds.keys()), "" if bad.is_empty() and missing.is_empty() else " (%s)" % "; ".join(bad + missing.map(func(k): return "no " + k))])
	var far_ok := true
	for kind in KINDS:
		if kind != "stock" and WheelPresets._scene(str(WheelPresets._data.far.get(kind, ""))) == null:
			far_ok = false
	check(far_ok, "presets: every kind has its far stand-in (a converted CC0 wheel) past %.0f m" % WheelPresets.far_m())


func _converted() -> void:
	var d := DirAccess.open("res://assets/wheels")
	var ids := d.get_directories()
	var bad: Array = []
	for id in ids:
		var sc: PackedScene = WheelPresets._scene(id)
		var info := WheelPresets._info(id)
		if sc == null or info.is_empty():
			bad.append("%s: missing" % id)
			continue
		var n: Node3D = sc.instantiate()
		var tyre := n.find_child("Tyre", true, false) as MeshInstance3D
		var rim := n.find_child("Rim", true, false) as MeshInstance3D
		if tyre == null or rim == null:
			bad.append("%s: Tyre / Rim not apart" % id)
			n.free()
			continue
		var ab := _aabb(tyre, n)                             # (wheel.json gives the tyre's size; the rim's nuts may stand proud)
		var dia := maxf(ab.size.y, ab.size.z)
		var mid := ab.get_center()
		if absf(dia - float(info.diameter)) > float(info.diameter) * 0.02 or absf(ab.size.x - float(info.width)) > float(info.width) * 0.06:
			bad.append("%s: wheel.json %.3f x %.3f, the mesh %.3f x %.3f" % [id, info.diameter, info.width, dia, ab.size.x])
		if ab.size.x > minf(ab.size.y, ab.size.z) or mid.length() > dia * 0.02:
			bad.append("%s: not on the x axle / not centred (%s)" % [id, mid])
		var face := _mean_x(rim, n)
		if face <= 0.0:
			bad.append("%s: its face isn't at +x" % id)
		n.free()
	check(bad.is_empty() and ids.size() >= 11, "converted CC0 wheels: %d (%s), each with its Tyre and Rim apart, the tyre true to its wheel.json, on the x axle, centred, face at +x%s" % [
		ids.size(), ", ".join(ids), "" if bad.is_empty() else " (%s)" % "; ".join(bad)])


# ── the assemblies ────────────────────────────────────────────────────────

func _assemblies() -> void:
	for model in CARS:
		var parts := CarSpecs.parts(model)
		var bad: Array = []
		var n_ok := 0
		for id in WheelPresets.ids():
			if id == "stock":
				continue
			for k in 4:
				var f := WheelPresets.fit(id, parts, k)
				var a := WheelPresets.assemble(id, f)
				var spin: Node3D = a.spin
				var fixed: Node3D = a.fixed
				var tyre := spin.get_node_or_null("Tyre") as MeshInstance3D
				var rim := spin.get_node_or_null("Rim") as MeshInstance3D
				var disc := spin.get_node_or_null("Disc") as MeshInstance3D
				var cal := fixed.get_node_or_null("Caliper") as MeshInstance3D
				var tag := "%s %s %s" % [model, id, ["FL", "FR", "RL", "RR"][k]]
				if tyre == null or rim == null or disc == null or cal == null:
					bad.append(tag + ": a part missing")
					continue
				if cal.get_parent() == spin or tyre.get_parent() != spin:
					bad.append(tag + ": the caliper would spin / the tyre wouldn't")
				var tb := _aabb(tyre, spin)
				var outer_r := float(f.outer_r)
				var c := tb.get_center() - Vector3(float(f.side) * float(f.offset), 0, 0)
				if c.length() > 0.002:
					bad.append(tag + ": the axle's off the hub by %.1f mm" % (c.length() * 1000.0))
				if absf(tb.size.y - tb.size.z) > outer_r * 0.02:
					bad.append(tag + ": not round about the axle (%.3f / %.3f)" % [tb.size.y, tb.size.z])
				if absf(-tb.position.y - outer_r) > 0.003:
					bad.append(tag + ": the tyre's bottom %.1f mm off the physics radius" % ((-tb.position.y - outer_r) * 1000.0))
				if absf(tb.size.x - float(f.width)) > float(f.width) * 0.04:
					bad.append(tag + ": %.3f wide, should be %.3f" % [tb.size.x, f.width])
				if signf(_mean_x(rim, spin) - float(f.side) * float(f.offset)) != signf(float(f.side)):
					bad.append(tag + ": the face isn't outwards (mirroring)")
				# the caliper: over the disc, inside the barrel, clear of the rim's metal
				var cb := _aabb(cal, fixed)
				var reach := 0.0
				for v in _verts(cal, fixed):
					reach = maxf(reach, Vector2(v.y, v.z).length())
				if reach > WheelGen.drop_r(float(f.rim_r)) - 0.004 or reach < float(f.disc_r):
					bad.append(tag + ": the caliper reaches %.3f m (disc %.3f, the barrel's drop centre %.3f)" % [reach, f.disc_r, WheelGen.drop_r(float(f.rim_r))])
				# (in the caliper's own polar box: its radii, its angles round the axle, its x)
				var rr := Vector2(INF, -INF)
				var aa := Vector2(INF, -INF)
				for v in _verts(cal, fixed):
					var r := Vector2(v.y, v.z).length()
					var an := atan2(v.y, v.z)
					rr = Vector2(minf(rr.x, r), maxf(rr.y, r))
					aa = Vector2(minf(aa.x, an), maxf(aa.y, an))
				var hits := 0
				for v in _verts(rim, spin):
					var r := Vector2(v.y, v.z).length()
					var an := atan2(v.y, v.z)
					if r > rr.x + 0.002 and r < rr.y - 0.002 and an > aa.x + 0.01 and an < aa.y - 0.01 and v.x > cb.position.x + 0.002 and v.x < cb.end.x - 0.002:
						hits += 1
				if hits > 0:
					bad.append(tag + ": the rim runs through the caliper (%d points)" % hits)
				if spin.get_node_or_null("Tyre_LOD1") == null and str(WheelPresets.preset(id).get("build", "gen")) == "gen":
					bad.append(tag + ": no lighter mesh")
				if tyre.visibility_range_end <= 0.0:
					bad.append(tag + ": no LOD range")
				if spin.get_node_or_null("Far") == null:
					bad.append(tag + ": no far stand-in")
				else:
					var fb := _aabb_tree(spin.get_node("Far"), spin)
					if absf(fb.size.y - outer_r * 2.0) > outer_r * 0.06:
						bad.append(tag + ": the far stand-in is %.3f m across, the wheel %.3f" % [fb.size.y, outer_r * 2.0])
				n_ok += 1
				spin.free()
				fixed.free()
		check(bad.is_empty(), "assemblies on the %s: %d (every preset x 4 corners): the axle on the hub, round, the tyre on the ground at the physics radius, its width, the face outwards both sides, the caliper over the disc inside the barrel clear of the rim, LODs and a far stand-in%s" % [
			model, n_ok, "" if bad.is_empty() else " (%s)" % "; ".join(bad.slice(0, 6))])


# ── the fit ───────────────────────────────────────────────────────────────

func _fit() -> void:
	var Fit = load("res://tools/wheel_fit.gd")
	var data = JSON.parse_string(FileAccess.get_file_as_string(WheelPresets.FIT))
	check(data is Dictionary and str(data.get("presets_hash", "")) == Fit.presets_hash(),
		"fit: data/wheel_fit.json is up to date with the presets (else: godot --headless --path . -s tools/wheel_fit.gd)")
	var models: Array = Fit.car_models()
	var missing := models.filter(func(m): return not (data.models as Dictionary).has(m.model))
	check(missing.is_empty(), "fit: every garage car model measured (%d)" % models.size())
	for model in CARS:
		var role := ""
		for m in models:
			if m.model == model:
				role = m.role
		var again: Dictionary = Fit.measure(model, role)
		var same := true
		for id in again:
			if bool(again[id].ok) != bool(data.models.get(model, {}).get(id, {}).get("ok", not again[id].ok)):
				same = false
		check(same and not again.is_empty(), "fit: the %s measured again agrees (%s)" % [model,
			", ".join(again.keys().map(func(id): return "%s %s" % [id, "fits" if again[id].ok else "no"]))])
	var road := WheelPresets.offered("drift", "s15")
	var track := WheelPresets.offered("track", "gt3r_992")
	var formula_on_road := "formula_18" in road or "formula_18" in track
	check(road[0] == "stock" and not "apex_cl6" in road and "apex_cl6" in track and not "oldsmith_dish" in track and not formula_on_road,
		"fit: the garage offers a road car road wheels (%s), a GT car track and street ones (%s), nobody the formula wheel" % [", ".join(road), ", ".join(track)])
	check(WheelPresets.offered("rally", "") == ["stock"], "fit: the Higgsfield rally cars keep their own rally wheels")


# ── on a car ──────────────────────────────────────────────────────────────

func _on_car() -> void:
	var Catalog = load("res://scripts/game/catalog.gd")
	var RallyCar = load("res://scripts/vehicle/rally_car.gd")
	var car = RallyCar.new()
	root.add_child(car)
	var s: Dictionary = Catalog.setup("elfer_r")
	s["tyre"] = "tarmac"
	s["preset"] = "tarmac"
	car.apply_setup(s)
	await physics_frame
	var r0: float = car.config.tyre_radius
	s["wheel_type"] = "apex_cl6"
	car.apply_setup(s)
	await physics_frame
	var asm := 0
	var hidden := true
	var cal_on_pivot := true
	for mw in car._model_wheels:
		var spinner: Node3D = mw[1]
		var pivot: Node3D = mw[0]
		for n in spinner.get_children():
			if n.name == "WheelAssembly":
				asm += 1
			elif (n as Node3D).visible:
				hidden = false
		var has_cal := false
		for n in pivot.get_children():
			if n.name == "BrakeFixed":
				has_cal = true
		cal_on_pivot = cal_on_pivot and has_cal
	check(asm == 4 and hidden and cal_on_pivot and car.wheel_type == "apex_cl6" and car.config.tyre_radius == r0,
		"on a car: APEX CL6 on the ELFER R, all four (its own wheels hidden, the calipers on the uprights, the physics radius %.3f m unchanged)" % r0)
	# roll and steer: the tyre turns with the spinner, the caliper doesn't; both turn with the pivot
	var mw0: Array = car._model_wheels[0]
	var spinner0: Node3D = mw0[1]
	var pivot0: Node3D = mw0[0]
	var tyre: Node3D = spinner0.get_node("WheelAssembly/Tyre")
	var cal: Node3D = pivot0.get_node("BrakeFixed/Caliper")
	var t_before := tyre.global_transform.basis
	var c_before := cal.global_transform.basis
	spinner0.rotate_x(0.7)
	var rolled := not tyre.global_transform.basis.is_equal_approx(t_before) and cal.global_transform.basis.is_equal_approx(c_before)
	var t2 := tyre.global_transform.basis
	var c2 := cal.global_transform.basis
	pivot0.rotate_y(0.3)
	var steered := not tyre.global_transform.basis.is_equal_approx(t2) and not cal.global_transform.basis.is_equal_approx(c2)
	spinner0.rotate_x(-0.7)
	pivot0.rotate_y(-0.3)
	check(rolled and steered, "on a car: the tyre rolls with the wheel and the caliper stays put; both steer")
	s["wheel_type"] = "stock"
	car.apply_setup(s)
	await physics_frame
	var back := true
	for mw in car._model_wheels:
		for n in (mw[1] as Node3D).get_children():
			if n.name == "WheelAssembly" or not (n as Node3D).visible:
				back = false
	check(back and car.wheel_type == "stock", "on a car: STOCK brings its own wheels back")
	s["wheel_type"] = "strada_5"
	car.apply_setup(s)
	var s2: Dictionary = Catalog.setup("sylph")
	s2["tyre"] = "tarmac"
	s2["preset"] = "tarmac"
	car.apply_setup(s2)
	await physics_frame
	var leftover := false
	for mw in car._model_wheels:
		for n in (mw[1] as Node3D).get_children():
			if n.name == "WheelAssembly":
				leftover = true
	check(not leftover and car.wheel_type == "stock" and car.model_id == "s15", "on a car: another car comes on its own wheels (no old assembly left)")
	car.queue_free()
	await process_frame


# ── helpers ───────────────────────────────────────────────────────────────

## A mesh instance's box in `frame`'s space.
func _aabb(mi: MeshInstance3D, frame: Node3D) -> AABB:
	var vs := _verts(mi, frame)
	var ab := AABB(vs[0], Vector3.ZERO)
	for v in vs:
		ab = ab.expand(v)
	return ab


func _aabb_tree(n: Node, frame: Node3D) -> AABB:
	var ab := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false) + ([n] if n is MeshInstance3D else []):
		var b := _aabb(mi, frame)
		ab = b if first else ab.merge(b)
		first = false
	return ab


func _verts(mi: MeshInstance3D, frame: Node3D) -> PackedVector3Array:
	var xf := Transform3D.IDENTITY
	var n: Node = mi
	while n != null and n != frame:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	var out := PackedVector3Array()
	for i in mi.mesh.get_surface_count():
		for v in (mi.mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			out.append(xf * v)
	return out


func _mean_x(mi: MeshInstance3D, frame: Node3D) -> float:
	var vs := _verts(mi, frame)
	var t := 0.0
	for v in vs:
		t += v.x
	return t / maxf(1.0, vs.size())
