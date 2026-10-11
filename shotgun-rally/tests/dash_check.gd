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
##     driver's eye, its page; a dial's needle follows its reading (the speed, the revs)
##   * the ambient lighting: off by day, every light on at night
##   * the readings: the fuel (an electric car: its charge) and the range from it
##   * the original materials are untouched: an overlay is a duplicate's next pass
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
			var want: float = deg_to_rad(float(n.sweep)) * (share - rest_share)
			var got := Quaternion((np.pivot as Node3D).basis.orthonormalized())
			worst = maxf(worst, got.angle_to(Quaternion(Basis(np.axis, -want))))
	if not dash.needle_parts.is_empty():
		fails += _check(worst < 0.01, "%s: the modelled needles turn by their share of the sweep (worst off by %.2f deg)" % [id, rad_to_deg(worst)])
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
