extends SceneTree
## The cars' interiors made live (dash_live.gd, data/dash/<model>.json), without
## changing them:
##   * every car's spec finds what it names (its displays' materials, its panels'
##     faces, its needles' parts): nothing missing
##   * a spec'd car gets its screens (a page each), its panels and its needles
##   * the needles follow the readings: a modelled needle turns about its hub by its
##     share of the sweep (and back to where it was modelled at its rest value), a
##     painted one's angle follows too
##   * the warning lamps: all lit for the bulb check when the engine starts, then
##     each follows what it shows (the handbrake on or off, the shift lamp near the
##     limiter)
##   * the screens: the centre screen's page flips (M / the d-pad right) and back
##   * the dome light: every car has one, off, and it switches on and off
##   * the boards (measured quads over blank dials and screens): each there, facing the
##     driver's eye, its page; a dial's needle follows its reading (the speed, the revs); a
##     board on the steering wheel turns with it
##   * the ambient lighting: off by day, every light on at night
##   * the readings: the fuel (an electric car: its charge) and the range from it; the pedals;
##     a painted gear selector's letter
##   * a model's own LED blocks light in order with their reading
##   * a painted needle taken out of a copy of the texture; a needle along an uneven scale
##   * a race display: its pit banner only with the pit limiter on, the lap time, the fuel in
##     litres, the temperatures warming up
##   * a painted cluster laid sideways (or mirrored) in its texture is seen the right way round, and a live
##     needle on a painted dial sweeps from its 0 to its top value
##   * modelled needles cut from a material the cabin's trim shares: small parts only, the
##     steering wheel's surfaces of it left to turn
##   * a painted map's window: inside its screen, the road cut at its edges; today's date
##   * a screen showing the model's own picture first ("intro"), then its live page
##   * the steering wheel's pieces the model left in the body moved onto it (they turn with it), the
##     cabin's pieces left in a moving part moved back into the body;
##     LEDs lit in their row's own colour
##   * the original materials are untouched: an overlay is a duplicate's next pass (on both
##     sides for a double-sided material)
## Prints one [dash] line per check; exits 1 on any FAIL.
## Run: godot --headless --path . -s tests/dash_check.gd

const DT := 1.0 / 60.0

var RallyCar
var Catalog
var Cockpit
var DashLive
var st
var fails := 0
var _done := false


func _initialize() -> void:
	RallyCar = load("res://scripts/vehicle/rally_car.gd")
	Catalog = load("res://scripts/game/catalog.gd")
	Cockpit = load("res://scripts/vehicle/cockpit.gd")
	DashLive = load("res://scripts/vehicle/dash_live.gd")
	st = load("res://scripts/stage/stage_gen.gd").new()
	st.generate(4)


func _process(_dt: float) -> bool:
	if _done:
		return true
	_done = true                                     # (in the first frame: a car added in _initialize isn't ready yet)
	var specs := 0
	var domes := 0
	var why_dome: Array = []
	for c in Catalog.CARS:
		var made: Array = _car(c.id)
		var car = made[0]
		var cp = made[1]
		var dash = cp.dash
		if dash == null:
			why_dome.append(c.id + ": no DashLive")
			car.queue_free()
			continue
		# the dome light: there, off, switched on and off
		var dome: OmniLight3D = cp.find_child("DomeLight", true, false)
		if dome and not dome.visible:
			dash.toggle_dome()
			var on := dome.visible
			dash.toggle_dome()
			if on and not dome.visible:
				domes += 1
			else:
				why_dome.append(c.id + ": doesn't switch")
		else:
			why_dome.append(c.id + (": no dome light" if dome == null else ": on from the start"))
		var spec: Dictionary = DashLive.spec_for(str(c.get("model", "")))
		if not spec.is_empty():
			specs += 1
			_spec(c.id, car, cp, dash, spec)
		car.queue_free()
	fails += _check(why_dome.is_empty(), "the dome light in %d of %d cars, off, switched on and off%s" % [
		domes, Catalog.CARS.size(), "" if why_dome.is_empty() else " (" + " | ".join(why_dome) + ")"])
	fails += _check(specs >= 5, "%d cars have a live interior spec" % specs)
	print("[dash] %s" % ("DASH OK" if fails == 0 else "DASH FAIL"))
	quit(1 if fails > 0 else 0)
	return true


func _car(id: String) -> Array:
	var car = RallyCar.new()
	car.setup = Catalog.setup(id)
	root.add_child(car)
	car.freeze = true
	car.set_physics_process(false)
	var cp = Cockpit.new()
	car.add_child(cp)
	cp.build(car, st)
	cp.set_process(false)
	return [car, cp]


func _spec(id: String, car, cp, dash, spec: Dictionary) -> void:
	# nothing it names is missing; a page per screen, its panels and needles
	var screens := 0
	for d in spec.get("displays", []) + spec.get("panels", []):
		screens += d.get("screens", []).size()
	screens += spec.get("boards", []).size()
	var needles := 0
	for nm in spec.get("needle_meshes", []):
		needles += nm.needles.size()
	fails += _check(dash.missing.is_empty() and dash.pages.size() == screens and dash.panels.size() == spec.get("panels", []).size()
		and dash.needle_parts.size() == needles and dash.boards.size() == spec.get("boards", []).size(),
		"%s: everything found (missing %s), %d screens, %d panels, %d boards, %d modelled needles" % [
		id, str(dash.missing), dash.pages.size(), dash.panels.size(), dash.boards.size(), dash.needle_parts.size()])
	# the boards face the driver's eye
	if not dash.boards.is_empty():
		var eye: Vector3 = cp.eye_driver - car.model_offset()
		var worst_face := 1.0
		for b in dash.boards:
			var arr: Array = (b as MeshInstance3D).mesh.surface_get_arrays(0)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var mid := Vector3.ZERO
			for v in vs:
				mid += v
			mid /= vs.size()
			var nrm: Vector3 = (arr[Mesh.ARRAY_NORMAL] as PackedVector3Array)[0]
			worst_face = minf(worst_face, nrm.dot((eye - mid).normalized()))
		fails += _check(worst_face > 0.85 or spec.get("boards", []).any(func(x): return x.has("normal")),
			"%s: its %d boards face the driver (worst %.2f)" % [id, dash.boards.size(), worst_face])
		# a screen on the steering wheel (the Jesko's): its board turns with the wheel
		var on_wheel: Array = spec.boards.filter(func(x): return x.get("on_wheel", false))
		if not on_wheel.is_empty():
			var sw: Node3D = car.cockpit_nodes.get("wheel")
			var riding: Array = dash.boards.filter(func(b): return sw != null and b.get_parent() == sw)
			fails += _check(riding.size() == on_wheel.size(), "%s: %d of its boards on the steering wheel, turning with it" % [id, riding.size()])
	# a painted cluster's bands: one whose numbers aren't evenly spaced ("at") reaches each of its points
	# at that point's value (the 320i's: 120 km/h at its hexagon's corner)
	for pg in dash.pages:
		for a in pg.cfg.get("layout", {}).get("arc", []):
			if not a.has("at"):
				continue
			var lens: Array = [0.0]
			for i in range(1, a.pts.size()):
				lens.append(lens[-1] + Vector2(a.pts[i][0], a.pts[i][1]).distance_to(Vector2(a.pts[i - 1][0], a.pts[i - 1][1])))
			var ok: bool = a.at.size() == a.pts.size()
			for i in a.at.size():
				ok = ok and absf(pg.arc_reach(a.at, lens, float(a.at[i])) - float(lens[i])) < 0.01 and (i == 0 or float(a.at[i]) > float(a.at[i - 1]))
			fails += _check(ok and pg._painted(), "%s: its painted cluster's %s band reaches each mark at its value (%s)" % [id, str(a.what), str(a.at)])
	# a race display's tyre temperatures (Track Mode's; "--" without), DRY or WET; a screen whose UVs sit a
	# tile over (the 911 GT3 R's) measured in its texture's own 0..1
	for pg in dash.pages:
		if not pg.cfg.get("layout", {}).get("text", []).any(func(t): return str(t.what) == "tyre_fl"):
			continue
		var tyres: String = "%s %s" % [pg._reading("tyre_fr", {"tyre_c": [80.2, 81.4, 82.0, 83.0]}), pg._reading("tyre_rr", {})]
		var wet: String = "%s %s" % [pg._reading("track", {"wet": 0.6}), pg._reading("track", {"wet": 0.0})]
		var wraps: int = spec.get("displays", []).filter(func(x): return x.get("uv_wrap", false)).size()
		var wrapped: int = dash.overlays.filter(func(o): return o.mat.get_shader_parameter("wrap_uv") == true).size()
		fails += _check(tyres == "81 --" and wet == "WET DRY" and wrapped >= wraps,
			"%s: its race display's tyres (%s), the track (%s), %d screen(s) with UVs a tile over wrapped" % [id, tyres, wet, wrapped])
	# a painted needle taken out of a copy of the texture (lit as the face round it is), the overlay's
	# cover off; a needle along an uneven scale (the GT-R's speedometer) at each of its marks
	for o in dash.overlays:
		if o.needles.any(func(n): return n.has("painted")):
			var baked: bool = o.get("baked", false)
			var copies := 0
			for mi in car.body_model.find_children("*", "MeshInstance3D", true, false):
				for si in (mi as MeshInstance3D).get_surface_override_material_count():
					var m: Material = mi.get_surface_override_material(si)
					if m is StandardMaterial3D and m.next_pass == o.mat and (m as StandardMaterial3D).albedo_texture is ImageTexture:
						copies += 1
			fails += _check(baked and copies > 0, "%s: its painted needles taken out of a copy of the texture (%d surfaces), the cover off" % [id, copies])
		for n in o.needles:
			if not n.has("marks"):
				continue
			var hit := true
			for mk in n.marks:
				hit = hit and absf(DashLive.marks_deg(n.marks, float(mk[0])) - float(mk[1])) < 1e-4
			# (halfway between two marks: halfway between their angles; the last mark the scale's end)
			var v1 := (float(n.marks[1][0]) + float(n.marks[2][0])) * 0.5
			var mid: float = DashLive.marks_deg(n.marks, v1)
			var want: float = (float(n.marks[1][1]) + float(n.marks[2][1])) * 0.5
			fails += _check(hit and absf(mid - want) < 1e-3 and float(n.marks[-1][1]) == float(n.a1),
				"%s: its %s needle on each of its %d marks (%.1f between two of them: %.1f deg)" % [id, str(n.value), n.marks.size(), v1, mid])
	# the model's own LED blocks (the Bolide's fuel gauge and shift lights): none lit at 0, all at the top, in
	# order between, the lit part ending in the gap after the last one lit
	for o in dash.overlays:
		for row in o.leds:
			var n: int = row.x.size()
			var top := float(row.at[-1]) if row.has("at") else float(row.get("max", 1.0))
			var mid := float(row.at[1]) if row.has("at") else top * 2.0 / n
			var b0: Vector4 = DashLive.led_box(row, Transform3D(), 0.0)
			var b2: Vector4 = DashLive.led_box(row, Transform3D(), mid)
			var gap := (float(row.x[1]) + float(row.x[2])) * 0.5 if n > 2 else 0.0
			fails += _check(DashLive.leds_lit(row, 0.0) == 0 and DashLive.leds_lit(row, top) == n and DashLive.leds_lit(row, mid) == 2
				and absf(b0.y - b0.x) < 1e-6 and absf(b2.y - gap) < 1e-6 and o.mat.get_shader_parameter("led_count") == o.leds.size(),
				"%s: its %d %s LEDs light in order (none at 0, 2 at %s, all at %s)" % [id, n, str(row.what), str(mid), str(top)])
	# a painted cluster laid sideways in its texture (the Supra's): its picture's corners are the texture
	# rect's, its across the texture's down; a needle drawn on a painted dial at 0 and at its top value
	for pg in dash.pages:
		if pg.cfg.get("transpose", false):
			var ts := Vector2(pg.base.get_width(), pg.base.get_height())
			var c0: Vector2 = pg._tex_uv(Vector2.ZERO) * ts
			var c1: Vector2 = pg._tex_uv(pg.view.size) * ts
			fails += _check(pg.view.size == Vector2(pg.src.size.y, pg.src.size.x) and c0.distance_to(pg.src.position) < 0.5 and c1.distance_to(pg.src.end) < 0.5,
				"%s: its sideways cluster seen the right way round (%s from the texture's %s)" % [id, str(pg.view.size), str(pg.src.size)])
		if pg.cfg.get("flip_h", false):                # (a page the texture holds mirrored, the Trackhawk's radio: its left is the texture's right)
			var tsz := Vector2(pg.base.get_width(), pg.base.get_height())
			var m0: Vector2 = pg._tex_uv(pg.view.position) * tsz
			var want0 := Vector2(pg.src.end.x, pg.src.end.y if pg.cfg.get("flip_v", false) else pg.src.position.y)
			fails += _check(m0.distance_to(want0) < 0.5 and pg.view == pg.src,
				"%s: its mirrored%s page's corner is the texture's %s" % [id, " (and upside-down)" if pg.cfg.get("flip_v", false) else "", str(want0)])
		for n in pg.cfg.get("layout", {}).get("needle", []):
			var at0: float = pg.needle_angle(n, 0.0)
			var at1: float = pg.needle_angle(n, float(n.max))
			fails += _check(absf(at0 - deg_to_rad(float(n.a0))) < 1e-4 and absf(at1 - deg_to_rad(float(n.a1))) < 1e-4 and absf(pg.needle_angle(n, float(n.max) * 2.0) - at1) < 1e-4,
				"%s: its painted dial's live %s needle sweeps %s to %s deg (held at the end past %s)" % [id, str(n.what), str(n.a0), str(n.a1), str(n.max)])
	# a dial's needle follows its reading
	var dials: Array = dash.pages.filter(func(p): return str(p.cfg.get("page", "")) == "dial")
	if not dials.is_empty():
		dash.fake = {"kmh": 0.0, "rpm": 800.0, "rpm01": 0.0}
		_run(dash, DT)
		var lo: Array = dials.map(func(p): return p.share())
		dash.fake = {"kmh": 180.0, "rpm": 5500.0, "rpm01": 0.75}
		_run(dash, DT)
		var hi: Array = dials.map(func(p): return p.share())
		var moved := true
		for i in dials.size():
			if hi[i] <= lo[i] + 0.2:
				moved = false
		fails += _check(moved, "%s: its dials' needles follow the speed and the revs (%s -> %s)" % [id, str(lo), str(hi)])
	# the ambient lighting: off by day, on at night
	if spec.has("ambient"):
		dash.night = false
		_run(dash, DT)
		var day_off: bool = not dash.ambient.is_empty() and dash.ambient.all(func(l): return not l.visible)
		dash.night = true
		_run(dash, DT)
		var night_on: bool = dash.ambient.all(func(l): return l.visible)
		dash.night = false
		_run(dash, DT)
		fails += _check(day_off and night_on, "%s: its %d ambient lights off by day, on at night" % [id, dash.ambient.size()])
	# a display showing the pedals (the A45's): they read as far down as they are
	if dash.pages.any(func(p): return p.cfg.get("layout", {}).get("text", []).any(func(t): return str(t.what) in ["throttle", "brake"])):
		dash.fake = {}
		car.inp.throttle = 0.7
		car.inp.brake = 0.25
		_run(dash, DT)
		fails += _check(absf(float(dash.data.throttle) - 0.7) < 1e-3 and absf(float(dash.data.brake) - 0.25) < 1e-3,
			"%s: the pedals read as far down as they are (%.2f, %.2f)" % [id, dash.data.throttle, dash.data.brake])
		car.inp.throttle = 0.0
		car.inp.brake = 0.0
	# a painted selector (the A45's R N P D): the gear's letter the one left lit
	for pg in dash.pages:
		if pg.cfg.get("layout", {}).has("sel"):
			var lit := []
			for f in [{"state": "grid", "kmh": 0.0, "gear": 1}, {"state": "running", "kmh": 3.0, "gear": -1},
					{"state": "running", "kmh": 3.0, "gear": 0}, {"state": "running", "kmh": 60.0, "gear": 3}]:
				lit.append(pg._selector(f))
			fails += _check(lit == ["P", "R", "N", "D"], "%s: its selector lights the gear's letter (parked, reverse, neutral, 3rd: %s)" % [id, str(lit)])
	# the fuel (or the charge) and the range from it
	dash.fake = {"fuel": 0.5}
	_run(dash, DT)
	fails += _check(absf(float(dash.data.range) - 0.5 * float(spec.get("range_km", 420.0))) < 0.5 and dash.data.has("electric"),
		"%s: the fuel reads 50 %% and the range %d km%s" % [id, roundi(dash.data.range), " (electric)" if dash.data.electric else ""])
	# the originals untouched: each overlaid surface draws a duplicate, the overlay its next pass
	var same := true
	for mi in car.body_model.find_children("*", "MeshInstance3D", true, false):
		for si in (mi as MeshInstance3D).get_surface_override_material_count():
			var m: Material = mi.get_surface_override_material(si)
			var own_m: Material = mi.mesh.surface_get_material(si)
			if m and m.next_pass is ShaderMaterial and own_m and (own_m == m or own_m.next_pass == m.next_pass):
				same = false
	fails += _check(same, "%s: the model's own materials untouched (the overlays ride on copies)" % id)
	# an overlay on a double-sided material (the Camaro's dial photographs, modelled facing away) drawn on both sides too
	var sided := 0
	var both := true
	for mi in car.body_model.find_children("*", "MeshInstance3D", true, false):
		for si in (mi as MeshInstance3D).get_surface_override_material_count():
			var m: Material = mi.get_surface_override_material(si)
			if m is BaseMaterial3D and m.next_pass is ShaderMaterial and (m as BaseMaterial3D).cull_mode == BaseMaterial3D.CULL_DISABLED:
				sided += 1
				both = both and ((m.next_pass as ShaderMaterial).shader.code.contains("cull_disabled"))
	if sided > 0:
		fails += _check(both, "%s: its overlays on %d double-sided surfaces drawn on both sides" % [id, sided])
	# the bulb check, then the lamps follow what they show
	dash.fake = {"kmh": 0.0, "rpm01": 0.1, "rpm": 1000.0, "handbrake": false, "fuel": 0.5}
	_run(dash, 0.2)
	var bulbs: bool = dash.warning("handbrake") and dash.warning("abs") and dash.warning("ignition")
	_run(dash, DashLive.BULB_CHECK + 0.2)
	var off: bool = not dash.warning("handbrake") and not dash.warning("shift") and not dash.warning("ignition")
	dash.fake.handbrake = true
	dash.fake.rpm01 = 0.97
	_run(dash, 0.1)
	var on: bool = dash.warning("handbrake") and dash.warning("shift")
	fails += _check(bulbs and off and on, "%s: the lamps: all lit at the start (%s), then off (%s), the handbrake and shift lamps on when they should be (%s)" % [
		id, bulbs, off, on])
	# a race display (the AMG GT3's): its pit banner only with the pit limiter on, the lap time to the
	# thousandth, the fuel in litres, the temperatures warming from the air to running
	for pg in dash.pages:
		var lay: Dictionary = pg.cfg.get("layout", {})
		if not lay.get("lit", []).any(func(l): return str(l.what) == "pit"):
			continue
		dash.fake = {"fuel": 0.5}
		_run(dash, DT)
		var shut: bool = not dash.warning("pit")
		dash.fake.pit = true
		_run(dash, DT)
		var shown: bool = dash.warning("pit")
		var tank := float(spec.get("tank_l", 120.0))
		var lap: String = pg._reading("time_ms", {"time": 83.456})
		dash._warm = 0.0
		_run(dash, DT)
		var cold: String = pg._reading("t_water", dash.data)
		dash._warm = 1.0
		_run(dash, DT)
		var hot: String = pg._reading("t_oil", dash.data)
		fails += _check(shut and shown and lap == "01:23:456" and absf(float(dash.data.fuel_l) - 0.5 * tank) < 0.01 and cold == "20" and hot == "102",
			"%s: its race display: the pit banner only with the limiter on (%s, %s), the lap %s, %.1f l of %d, the water %s C cold, the oil %s C warm" % [
			id, shut, shown, lap, dash.data.fuel_l, tank, cold, hot])
		dash.fake = {}
	# modelled needles sharing their material with the cabin's trim (the SLR's chrome, "max_size"): each needle a
	# small part, the steering wheel's surfaces of that material left alone (they still turn with the wheel)
	for nm in spec.get("needle_meshes", []):
		if not nm.has("max_size"):
			continue
		var small := true
		for np in dash.needle_parts:
			for part in (np.pivot as Node3D).get_children():
				var bb: AABB = (part as MeshInstance3D).get_aabb()
				small = small and bb.size[bb.get_longest_axis_index()] <= float(nm.max_size) + 1e-4
		var wheel_kept := true
		var sw: Node = car.body_model.find_child("SteeringWheel*", true, false)
		if sw:
			for mi in sw.find_children("*", "MeshInstance3D", true, false) + ([sw] if sw is MeshInstance3D else []):
				for si in (mi as MeshInstance3D).get_surface_override_material_count():
					if mi.get_surface_override_material(si) == DashLive._hidden():
						wheel_kept = false
		var still: int = car.body_model.find_children("NeedlesStill", "MeshInstance3D", true, false).size()
		fails += _check(small and wheel_kept and still > 0, "%s: its needles cut from the trim's material, each under %.2f m (%s), the rest kept (%d), the steering wheel's left to turn (%s)" % [
			id, float(nm.max_size), small, still, wheel_kept])
	# the steering wheel's own pieces left in the body (the AMG ONE's grips, buttons, LEDs and screens): moved onto the
	# wheel's node (they turn with it), every corner inside the spec's box, the originals hidden
	if spec.has("wheel_parts"):
		var sw: Node3D = car.cockpit_nodes.get("wheel")
		var on_wheel: bool = sw != null and not dash.wheel_parts.is_empty() and dash.wheel_parts.all(func(p): return p.get_parent() == sw)
		var boxed := true
		var spaces: Array = spec.wheel_parts.map(func(wp): return dash.wheel_space(wp))
		for p in dash.wheel_parts:
			var vs: PackedVector3Array = (p as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			var xf: Transform3D = sw.transform * (p as MeshInstance3D).transform
			for v in vs:
				boxed = boxed and spaces.any(func(f): return f.call(xf * v))
		var turned := false
		if on_wheel:
			var p0: Vector3 = (dash.wheel_parts[0] as Node3D).global_position
			var a0: Basis = (dash.wheel_parts[0] as Node3D).global_basis
			sw.basis = Basis(Vector3(0, 0.44, 0.9).normalized(), 0.8)
			turned = not (dash.wheel_parts[0] as Node3D).global_basis.is_equal_approx(a0) or not (dash.wheel_parts[0] as Node3D).global_position.is_equal_approx(p0)
			sw.basis = Basis()
		fails += _check(on_wheel and boxed and turned, "%s: %d pieces of its steering wheel moved onto it from the body (inside the box: %s), turning with it (%s)" % [
			id, dash.wheel_parts.size(), boxed, turned])
	# pieces of the cabin the model left in something that moves (the Zonda's cluster bits in a front brake caliper,
	# swinging with the steering): moved back into the body, inside the spec's box, out of the moving part
	if spec.has("body_parts"):
		var home: bool = not dash.body_parts.is_empty() and dash.body_parts.all(func(p): return p.get_parent() == car.body_model)
		var inbox := true
		var spaces: Array = spec.body_parts.map(func(bp): return dash.wheel_space(bp))
		for p in dash.body_parts:
			for v in ((p as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
				inbox = inbox and spaces.any(func(f): return f.call((p as MeshInstance3D).transform * v))
		fails += _check(home and inbox, "%s: %d pieces of its cabin moved back into the body from a moving part (inside the box: %s)" % [id, dash.body_parts.size(), inbox])
	# LEDs painted plain white lit in their row's own colour (the AMG ONE's green, red and blue shift lights)
	for o in dash.overlays:
		var coloured: Array = o.leds.filter(func(r): return r.has("color"))
		if coloured.is_empty():
			continue
		var cols: Array = o.mat.get_shader_parameter("led_col")
		var ok := true
		for i in o.leds.size():
			var want := Color(str(o.leds[i].get("color", "#ffffff")))
			ok = ok and (cols[i].w > 0.5) == o.leds[i].has("color") and (not o.leds[i].has("color") or Color(cols[i].x, cols[i].y, cols[i].z).is_equal_approx(want))
		fails += _check(ok, "%s: %d LED rows lit in their own colours" % [id, coloured.size()])
	# a painted map's window (the M235i's iDrive): inside its screen; the road cut at the window's edges; today's date
	for pg in dash.pages:
		for m in pg.cfg.get("layout", {}).get("map", []):
			var wr := Rect2(m.rect[0], m.rect[1], float(m.rect[2]) - float(m.rect[0]), float(m.rect[3]) - float(m.rect[1]))
			var runs: Array = pg.clip_line(PackedVector2Array([wr.position - Vector2(30, 0), wr.get_center(), wr.end + Vector2(40, 40)]), wr)
			var cut: bool = runs.size() == 1 and runs[0].size() == 3 and wr.grow(0.01).has_point(runs[0][0]) and wr.grow(0.01).has_point(runs[0][-1]) \
				and absf(runs[0][0].x - wr.position.x) < 0.01 and pg.clip_line(PackedVector2Array([wr.end + Vector2(5, 5), wr.end + Vector2(50, 9)]), wr).is_empty()
			fails += _check(pg.view.encloses(wr) and cut, "%s: its painted map's window %s inside its screen, the road cut at its edges (%s)" % [id, str(wr), cut])
		var dt: Dictionary = Time.get_date_dict_from_system()
		if pg.cfg.get("layout", {}).get("text", []).any(func(t): return str(t.what) in ["date_d", "month"]):
			fails += _check(pg._reading("date_d", {}) == "%02d" % int(dt.day) and pg._reading("month", {}) == pg.MONTHS[int(dt.month) - 1],
				"%s: today's date on its screen (%s %s)" % [id, pg._reading("date_d", {}), pg._reading("month", {})])
	# a screen showing the model's own picture first (the X3's iDrive welcome page, "intro"), then its live page
	for pg in dash.pages:
		if float(pg.cfg.get("intro", 0.0)) <= 0.0:
			continue
		var t0: float = dash._t
		dash._t = 0.5
		var first: bool = pg.art_now()
		dash._t = float(pg.cfg.intro) + 0.5
		var then: bool = pg.art_now()
		dash._t = t0
		fails += _check(first and not then, "%s: its %s screen shows the model's own picture for %.0f s (%s), then its live page (%s)" % [
			id, str(pg.cfg.page), float(pg.cfg.intro), first, not then])
	# the modelled needles turn about their hubs, by their share of the sweep
	var worst := 0.0
	for np in dash.needle_parts:
		var n: Dictionary = np.n
		var what := str(n.get("value", "kmh"))
		var lo := float(n.get("min", 0.0))
		var hi := float(n.get("max", 1.0))
		for share in [0.0, 0.5, 1.0]:
			dash.fake[what] = lerpf(lo, hi, share)
			_run(dash, DT)
			var rest_share := (float(n.get("rest", lo)) - lo) / (hi - lo)
			var want: float = deg_to_rad(float(n.sweep)) * (share - rest_share) if not n.has("marks") \
				else deg_to_rad(DashLive.marks_deg(n.marks, lerpf(lo, hi, share)))
			var got := Quaternion((np.pivot as Node3D).basis.orthonormalized())
			worst = maxf(worst, got.angle_to(Quaternion(Basis(np.axis, -want))))
	if not dash.needle_parts.is_empty():
		fails += _check(worst < 0.01, "%s: the modelled needles turn by their share of the sweep or along their marks (worst off by %.2f deg)" % [id, rad_to_deg(worst)])
	# the painted needles' angles follow too
	for o in dash.overlays:
		if o.needles.is_empty():
			continue
		var n: Dictionary = o.needles[0]
		dash.fake[str(n.get("value", "kmh"))] = float(n.get("max", 1.0))
		_run(dash, DT)
		var ang: Array = o.mat.get_shader_parameter("needle_ang")
		fails += _check(absf(ang[0].x - deg_to_rad(float(n.a1))) < 0.01, "%s: a painted needle at its top value points at its end" % id)
	# the centre screen's page flips and back
	var navs: Array = dash.pages.filter(func(p): return str(p.cfg.get("page", "")) == "nav")
	if not navs.is_empty():
		dash.next_page()
		var p1: int = navs[0].page
		dash.next_page()
		fails += _check(p1 == 1 and navs[0].page == 0, "%s: the centre screen flips to driving information and back to the map" % id)
		# (a portrait screen's menu across its top: the Maybach's, the Senna's; a wide one's down the left)
		var want_tall := id in ["affalter_s", "woking_800"]
		if want_tall or id in ["kaiser_5g", "kasten", "gls"]:
			fails += _check(navs[0].tall() == want_tall, "%s: the centre screen laid out for its shape (%s)" % [id, "tall: tabs across the top" if want_tall else "wide: the menu down the left"])
	# every screen's viewport sized like its screen
	var sized := true
	for p in dash.pages:
		var vp := p.get_parent() as SubViewport
		if vp == null or vp.size.x < 64 or vp.size.y < 16:
			sized = false
	fails += _check(sized, "%s: every screen has its own picture, sized to the screen" % id)


func _run(dash, seconds: float) -> void:
	for f in maxi(roundi(seconds / DT), 1):
		dash._process(DT)


func _check(ok: bool, msg: String) -> int:
	print("[dash] %s %s" % ["ok  " if ok else "FAIL", msg])
	return 0 if ok else 1
