extends Node3D
## A car's own interior made live, without changing it (cockpit.gd adds one to
## every car; data/dash/<model>.json says where a car's instruments are):
##   * "displays": a material's surfaces keep their material and get an overlay
##     pass on top (next_pass: the same faces drawn again, only where it has
##     something to show; everywhere else the original shows through, untouched):
##       - screens: a rectangle of the surface's UVs shows a live page instead
##         (dash_page.gd: a digital cluster, the centre screen's map and driving data)
##       - needles: a dial painted in the texture gets a moving needle; the painted
##         one is covered with the dial face from a little further round
##       - glow: at night the backlit parts light up (the texture as if lit from behind)
##       - warning lamps: a lamp's icon lights up while it's on
##       - "leds": the model's own LED blocks (sharing one patch of texture, told apart by
##         where they sit: "x" their centres in the model's axes, "y" the row's band) lit,
##         in their own colour, up to a reading ("max", or "at": each LED's value)
##   * "panels": a screen modelled with no UVs of its own to show anything on (its
##     faces share the interior's material): its faces (those of the material in a
##     box, facing the driver) copied into a mesh of their own a hair in front, with
##     UVs across it, showing the pages
##   * "needle_meshes": needles modelled as parts (merged into the body): each one cut
##     out into a part of its own and turned about its dial's hub ("max_size": needles in a
##     material the trim shares, told apart by their size)
##   * "boards": a dial or screen that's blank and can't be picked out by its faces (it
##     shares a material with everything round it): a quad of its own placed by measure
##     ("c": its middle, "w" x "h" m, facing the driver's eye or "normal"; "round": a
##     dial's disc) a hair in front of it, showing a page ("dial", "cluster", "nav")
##   * the warning lamps: the handbrake, ABS and traction control working, the shift
##     lamp near the limiter, the lights at night, the flash; all of them for a moment
##     when the engine starts (the bulb check)
##   * the dome light: a soft light under the roof, switched (L / the d-pad up)
##   * "ambient": the ambient lighting, on at night: soft coloured lights low in the cabin
##     ({"color", "energy", "range", "at": [[x, y, z], ...]} from the steering wheel's
##     centre; without "at": the centre console's footwell and both door cards)
##   * "electric": the readings are a charge (the "fuel") and a range ("range_km" full,
##     else 420); an electric car's engine (its regen) says so when the spec doesn't
## Spec coordinates: a display's are its texture's pixels ("units": "px", x right, y
## down) or its UVs ("units": "uv"; "uv_wrap": a model whose screen's UVs sit a whole tile
## over, measured in the texture's own 0..1); a panel's and a needle mesh's are metres from the
## steering wheel's centre (the model's axes: x right, y up, z back). Needle angles
## on a texture are degrees, 0 = pointing right, 90 = down (clockwise).

const DashPage = preload("res://scripts/vehicle/dash_page.gd")
const MAX_SCREENS := 3
const MAX_NEEDLES := 8
const MAX_RECTS := 8
const MAX_LED_ROWS := 4
const BULB_CHECK := 1.6             # s every lamp's lit after the engine starts
const SCREEN_HZ := 30.0             # the screens redraw this often
const ALL := [-1e4, -1e4, 1e4, 1e4] # a rect that's the whole surface

var car
var cockpit
var spec := {}
var night := false                  # the backlit parts lit (the game: a night stage)
var dome_on := false
var data := {}                      # this frame's readings (the pages and the needles show them)
var fake := {}                      # readings to show instead (pictures, tests)
var pages: Array = []               # DashPage, one per screen
var overlays: Array = []            # [{"mat": ShaderMaterial, "needles": [...], "warns": [...]}]
var needle_parts: Array = []        # [{"pivot": Node3D, "axis": Vector3, "n": spec}]
var needle_mats: Array = []         # the needle parts' material (lit up at night)
var panels: Array = []              # the panels' meshes
var boards: Array = []              # the boards' meshes
var missing: Array = []             # spec entries that found nothing (the tests list them)
var _dome: OmniLight3D
var ambient: Array = []             # the ambient lights (on at night)
var _t := 0.0                       # s since it was built (the bulb check)
var _screen_t := 0.0
var _gfx := Vector2.ZERO            # g, smoothed (x: across, + = right; y: along, + = braking)
var _prev_v := Vector3.ZERO
var _warm := 0.0                     # 0 cold ... 1 at running temperature (the water, oil and gearbox)
var _lit := false                   # the needles lit (night)
var _overlaid := {}                 # a display's material -> its copy with the overlay (one per material)


static func spec_for(model: String) -> Dictionary:
	var p := "res://data/dash/%s.json" % model
	if model == "" or not FileAccess.file_exists(p):
		return {}
	var d = JSON.parse_string(FileAccess.open(p, FileAccess.READ).get_as_text())
	return d if d is Dictionary else {}


func setup(the_car, the_cockpit, the_spec: Dictionary) -> void:
	car = the_car
	cockpit = the_cockpit
	spec = the_spec
	name = "DashLive"
	_read(0.0)
	for d in spec.get("displays", []):
		if not _surfaces(str(d.get("mat", "^$")), func(m, si, base): _overlay(m, si, base, d)):
			missing.append("display " + str(d.get("mat")))
	for p in spec.get("panels", []):
		_panel(p)
	for b in spec.get("boards", []):
		_board(b)
	for n in spec.get("needle_meshes", []):
		_needle_mesh(n)
	_make_dome()
	_make_ambient()


## Calls fn(mesh instance, surface, material) for every surface of the body whose
## material's name matches; false if there were none.
func _surfaces(pattern: String, fn: Callable) -> bool:
	var re := RegEx.new()
	re.compile(pattern)
	var body = car.body_model
	if body == null:
		return false
	var found := false
	for mi in body.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null or m.name == "LivePanel":
			continue
		for si in m.mesh.get_surface_count():
			var base := m.get_active_material(si)
			if base != null and re.search(base.resource_name) != null:
				fn.call(m, si, base)
				found = true
	return found


func _overlay(m: MeshInstance3D, si: int, base: Material, d: Dictionary) -> void:
	if _overlaid.has(base):                              # (the material on another mesh too: the same overlay, the same pages)
		m.set_surface_override_material(si, _overlaid[base])
		return
	var ov := _overlay_material(base, d)
	var mat: Material = base.duplicate()
	mat.next_pass = ov
	if mat is StandardMaterial3D and (mat as StandardMaterial3D).albedo_texture and d.get("needles", []).any(func(n): return n.has("painted")):
		# (the painted needles taken out of a copy of the texture: the face under them, lit as the rest of it is)
		(mat as StandardMaterial3D).albedo_texture = uncovered((mat as StandardMaterial3D).albedo_texture, d.needles, _tex_size(base, d))
		overlays[-1].baked = true
	m.set_surface_override_material(si, mat)
	_overlaid[base] = mat
	var rel := Transform3D()                             # (the LED rows are in the model's axes; the shader sees the mesh's own)
	var nd: Node = m
	while nd != null and nd != car.body_model:
		if nd is Node3D:
			rel = (nd as Node3D).transform * rel
		nd = nd.get_parent()
	overlays[-1].to_local = rel.affine_inverse()


## The overlay material for a display (its screens get their pages and viewports).
func _overlay_material(base: Material, d: Dictionary) -> ShaderMaterial:
	var tex: Texture2D = base.albedo_texture if base is StandardMaterial3D else null
	var size := Vector2(tex.get_width(), tex.get_height()) if tex else Vector2(512, 512)
	if str(d.get("units", "px")) == "uv":
		size = Vector2.ONE
	elif d.has("tex"):
		size = Vector2(d.tex[0], d.tex[1]) if d.tex is Array else Vector2(float(d.tex), float(d.tex))
	var ov := ShaderMaterial.new()
	ov.shader = _shader(d.get("solid", false))
	ov.render_priority = 1
	ov.set_shader_parameter("base_tex", tex)
	ov.set_shader_parameter("has_base", tex != null)
	ov.set_shader_parameter("aspect", size.x / size.y)
	ov.set_shader_parameter("wrap_uv", d.get("uv_wrap", false))   # (a model whose screen's UVs sit a tile over)
	# the screens: a page each, drawn into its own viewport
	var rects: Array = []
	var flips: Array = []
	var k := 0
	for s in d.get("screens", []):
		if k >= MAX_SCREENS:
			break
		var r: Array = s.rect
		var page := DashPage.new()
		var tex_px := Vector2(tex.get_width(), tex.get_height()) if tex else size
		var src := Rect2(float(r[0]), float(r[1]), float(r[2]) - float(r[0]), float(r[3]) - float(r[1]))
		src = Rect2(src.position / size * tex_px, src.size / size * tex_px)       # (in the texture's pixels)
		var vp := SubViewport.new()
		vp.transparent_bg = false
		vp.disable_3d = true
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		add_child(vp)
		page.setup(self, s, tex, src)
		vp.size = Vector2i(page.size.round())
		vp.add_child(page)
		pages.append(page)
		ov.set_shader_parameter("screen_tex%d" % k, vp.get_texture())
		rects.append(_uv_rect(r, size))
		flips.append(2.0 if s.get("transpose", false) else (1.0 if s.get("flip_v", false) else 0.0))
		k += 1
	ov.set_shader_parameter("screen_count", k)
	ov.set_shader_parameter("screen_rect", _pad(rects, MAX_SCREENS))
	while flips.size() < MAX_SCREENS:
		flips.append(0.0)
	ov.set_shader_parameter("screen_flip", PackedFloat32Array(flips))
	ov.set_shader_parameter("screen_light", float(d.get("screen_light", 0.92)))
	# the needles
	var geo: Array = []
	var col: Array = []
	var offs: Array = []
	var needles: Array = []
	for n in d.get("needles", []):
		if needles.size() >= MAX_NEEDLES:
			break
		var c: Array = n.c
		geo.append(Vector4(float(c[0]) / size.x, float(c[1]) / size.y, float(n.r) / size.y, float(n.get("w", 3.0)) * 0.5 / size.y))
		var cc := Color(str(n.get("color", "#e8401c")))
		col.append(Vector4(cc.r, cc.g, cc.b, float(n.get("tail", 0.18))))
		var off: Array = n.get("cover_off", [])          # (a patterned face: the cover copied from beside the needle, along the pattern)
		offs.append(Vector4(float(off[0]) / size.x, float(off[1]) / size.y, 1.0, 0.0) if off.size() == 2 else Vector4.ZERO)
		needles.append(n)
	ov.set_shader_parameter("needle_count", needles.size())
	ov.set_shader_parameter("needle_geo", _pad(geo, MAX_NEEDLES))
	ov.set_shader_parameter("needle_col", _pad(col, MAX_NEEDLES))
	ov.set_shader_parameter("needle_off", _pad(offs, MAX_NEEDLES))
	# the glow and the warning lamps
	var glows: Array = []
	if str(d.get("glow", "")) == "all":
		glows.append(_uv_rect(ALL, Vector2.ONE))
	elif d.get("glow") is Array:
		for g in d.glow:
			glows.append(_uv_rect(g, size))
	ov.set_shader_parameter("glow_count", mini(glows.size(), MAX_RECTS))
	ov.set_shader_parameter("glow_tint", Color(str(d.get("glow_color", "#ffffff"))))
	ov.set_shader_parameter("glow_rect", _pad(glows, MAX_RECTS))
	var warns: Array = []
	var wrect: Array = []
	var wcol: Array = []
	for w in d.get("warn", []):
		if warns.size() >= MAX_RECTS:
			break
		warns.append(str(w.what))
		wrect.append(_uv_rect(ALL, Vector2.ONE) if str(w.get("rect", "all")) == "all" else _uv_rect(w.rect, size))
		var wc := Color(str(w.get("color", "#ff3b1f")))
		wcol.append(Vector4(wc.r, wc.g, wc.b, 1.0))
	ov.set_shader_parameter("warn_count", warns.size())
	ov.set_shader_parameter("warn_rect", _pad(wrect, MAX_RECTS))
	ov.set_shader_parameter("warn_col", _pad(wcol, MAX_RECTS))
	var leds: Array = d.get("leds", []).slice(0, MAX_LED_ROWS)   # (the model's own LED blocks: lit up to the reading)
	ov.set_shader_parameter("led_count", leds.size())
	overlays.append({"mat": ov, "needles": needles, "warns": warns, "leds": leds, "to_local": Transform3D()})
	return ov


## A display's spec size (what its pixel coordinates are measured in).
static func _tex_size(base: Material, d: Dictionary) -> Vector2:
	var tex: Texture2D = base.albedo_texture if base is StandardMaterial3D else null
	if str(d.get("units", "px")) == "uv":
		return Vector2.ONE
	if d.has("tex"):
		return Vector2(d.tex[0], d.tex[1]) if d.tex is Array else Vector2(float(d.tex), float(d.tex))
	return Vector2(tex.get_width(), tex.get_height()) if tex else Vector2(512, 512)


## A copy of a texture with its painted needles taken out: within each one's wedge (as wide as the
## overlay's cover), the face copied from beside it ("cover_off", px: along a striped face's
## stripes) or from "shift" degrees further round. Then only the live needle is drawn over it.
static func uncovered(tex: Texture2D, needles: Array, size: Vector2) -> Texture2D:
	var img := tex.get_image()
	if img == null:
		return tex
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	img.clear_mipmaps()
	var src := img.duplicate()
	var k := Vector2(img.get_width(), img.get_height()) / size        # (spec px -> the image's)
	for n in needles:
		if not n.has("painted"):
			continue
		var c := Vector2(float(n.c[0]), float(n.c[1])) * k
		var r := (float(n.r) + 1.5) * k.y                  # (a pixel or so past the overlay's cover, all round: the
		var hw := float(n.get("w", 3.0)) * 0.5 * k.y        # painted needle's soft edges and its tip)
		var margin := 1.2 * k.y
		var a0 := deg_to_rad(float(n.painted))
		var off: Array = n.get("cover_off", [])
		var sh := deg_to_rad(float(n.get("shift", 18.0)))
		for y in range(maxi(int(c.y - r), 0), mini(int(c.y + r) + 1, img.get_height())):
			for x in range(maxi(int(c.x - r), 0), mini(int(c.x + r) + 1, img.get_width())):
				var d := Vector2(x + 0.5, y + 0.5) - c
				var dist := d.length()
				if dist > r:
					continue
				if absf(wrapf(d.angle() - a0, -PI, PI)) >= (hw * 2.4 + margin) / maxf(dist, hw * 2.0) + 0.015:
					continue
				var q := Vector2(x, y) + Vector2(float(off[0]), float(off[1])) * k if off.size() == 2 else c + d.rotated(sh) - Vector2(0.5, 0.5)
				img.set_pixel(x, y, src.get_pixel(clampi(roundi(q.x), 0, img.get_width() - 1), clampi(roundi(q.y), 0, img.get_height() - 1)))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## How many of a row of LEDs are lit for a reading: "at" (each LED's value), else an even share of
## "max" each.
static func leds_lit(row: Dictionary, v: float) -> int:
	var n: int = row.x.size()
	if row.has("at"):
		return (row.at as Array).filter(func(a): return v >= float(a)).size()
	return clampi(roundi(v / maxf(float(row.get("max", 1.0)), 1e-4) * n), 0, n)


## A row of LEDs' lit part, in the mesh's own axes: x from before the first LED to the gap after the
## last one lit ("x": the LEDs' centres in the order they light, in the model's axes; "y": the row's
## band, low and high).
static func led_box(row: Dictionary, to_local: Transform3D, v: float) -> Vector4:
	var xs: Array = row.x
	var k := leds_lit(row, v)
	var step: float = float(xs[1]) - float(xs[0]) if xs.size() > 1 else 0.004
	var x0: float = float(xs[0]) - step * 0.5
	var x1: float = x0 if k == 0 else (float(xs[k - 1]) + (float(xs[k]) - float(xs[k - 1])) * 0.5 if k < xs.size() else float(xs[-1]) + step * 0.5)
	var a := to_local * Vector3(x0, float(row.y[0]), 0.0)
	var b := to_local * Vector3(x1, float(row.y[1]), 0.0)
	return Vector4(a.x, b.x, minf(a.y, b.y), maxf(a.y, b.y))


static func _uv_rect(r: Array, size: Vector2) -> Vector4:
	return Vector4(float(r[0]) / size.x, float(r[1]) / size.y, float(r[2]) / size.x, float(r[3]) / size.y)


static func _pad(a: Array, n: int) -> Array:
	var out := a.duplicate()
	while out.size() < n:
		out.append(Vector4.ZERO)
	return out


func _wheel() -> Vector3:
	return cockpit.wheel_c - car.model_offset()         # (the model's own space)


## A screen with no UVs to show anything on: the material's faces in touching groups,
## each group wholly inside the box (from the wheel's centre), facing the driver and big
## enough (buttons beside it aren't screen); copied into a mesh of their own a hair
## toward the driver, UVs laid flat across the screen's own plane (u left to right, v top
## to bottom), showing the pages. A screen's "aspect" comes from the faces' real size.
func _panel(p: Dictionary) -> void:
	var c := _wheel()
	var bx: Array = p.box
	var lo := c + Vector3(bx[0], bx[2], bx[4])
	var hi := c + Vector3(bx[1], bx[3], bx[5])
	var near := AABB(lo, hi - lo).grow(0.02)
	var tight := AABB(lo, hi - lo).grow(0.005)
	var eye: Vector3 = cockpit.eye_driver - car.model_offset()
	var tris: Array = []
	var hosts: Array = []
	_surfaces(str(p.mat), func(m: MeshInstance3D, si: int, _base: Material):
		var arr := m.mesh.surface_get_arrays(si)
		var vs: PackedVector3Array = _rel(m) * (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array)
		var ids := _indices(arr)
		var cand: Array = []                             # the triangles with a corner near the box
		for t in ids.size() / 3:
			for k in 3:
				if near.has_point(vs[ids[t * 3 + k]]):
					cand.append(t)
					break
		for g in _groups(vs, ids, cand):
			var inside := true
			for t in g:
				for k in 3:
					if not tight.has_point(vs[ids[t * 3 + k]]):
						inside = false
				if not inside:
					break
			if not inside:
				continue
			# its faces seen from the driver's eye (a screen's a slab: its back and edges aren't)
			var mine: Array = []
			var area := 0.0
			for t in g:
				var a: Vector3 = vs[ids[t * 3]]
				var b: Vector3 = vs[ids[t * 3 + 1]]
				var d: Vector3 = vs[ids[t * 3 + 2]]
				var f := (d - a).cross(b - a)            # (the side it's seen from: clockwise is the front)
				if f.length_squared() < 1e-14 or f.normalized().dot((eye - (a + b + d) / 3.0).normalized()) < float(p.get("facing", 0.5)):
					continue
				mine.append([a, b, d])
				area += f.length() * 0.5
			if area < float(p.get("min_area", 0.01)):
				continue
			tris.append_array(mine)
			if not hosts.has(m):
				hosts.append(m))
	if tris.is_empty():
		missing.append("panel " + str(p.get("mat")))
		return
	# the screen's own plane: its normal (toward the driver), up, right
	var nrm := Vector3.ZERO
	for t in tris:
		nrm += (t[2] - t[0]).cross(t[1] - t[0])
	nrm = nrm.normalized()
	var up := (Vector3.UP - nrm * nrm.dot(Vector3.UP)).normalized()
	var right := up.cross(nrm)
	var u0 := INF
	var u1 := -INF
	var v0 := INF
	var v1 := -INF
	for t in tris:
		for v in t:
			u0 = minf(u0, v.dot(right))
			u1 = maxf(u1, v.dot(right))
			v0 = minf(v0, v.dot(up))
			v1 = maxf(v1, v.dot(up))
	var lift := float(p.get("lift", 0.0012))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for t in tris:
		var fn: Vector3 = (t[2] - t[0]).cross(t[1] - t[0]).normalized()
		for v in t:
			st.set_normal(fn)
			st.set_uv(Vector2((v.dot(right) - u0) / maxf(u1 - u0, 1e-4), (v1 - v.dot(up)) / maxf(v1 - v0, 1e-4)))
			st.add_vertex(v + fn * lift)
	var mi := MeshInstance3D.new()
	mi.name = "LivePanel"
	mi.mesh = st.commit()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var host: MeshInstance3D = hosts[0]
	mi.layers = host.layers
	var screens: Array = []
	for s in p.get("screens", []):
		var r: Array = s.rect
		var sc: Dictionary = s.duplicate()
		if not sc.has("aspect"):
			sc.aspect = (float(r[2]) - float(r[0])) * (u1 - u0) / maxf((float(r[3]) - float(r[1])) * (v1 - v0), 1e-4)
		screens.append(sc)
	var ov := _overlay_material(StandardMaterial3D.new(), p.merged({"units": "uv", "screens": screens, "solid": true}, true))
	ov.render_priority = 0
	mi.material_override = ov
	car.body_model.add_child(mi)
	panels.append(mi)


## A board: a quad of its own at "c" (m from the steering wheel's centre, the model's axes),
## "w" x "h", facing the driver's eye (or "normal"), its top toward "up" (the world's up by
## default), "lift" toward the driver; the page fills it ("round": the disc inside it only).
func _board(b: Dictionary) -> void:
	var c := _wheel() + Vector3(b.c[0], b.c[1], b.c[2])
	var eye: Vector3 = cockpit.eye_driver - car.model_offset()
	var nrm := (eye - c).normalized()
	if b.has("normal"):
		nrm = Vector3(b.normal[0], b.normal[1], b.normal[2]).normalized()
	var upv := Vector3.UP if not b.has("up") else Vector3(b.up[0], b.up[1], b.up[2])
	var up := (upv - nrm * nrm.dot(upv)).normalized()
	var right := up.cross(nrm)
	var w := float(b.get("w", 0.1)) * 0.5
	var h := float(b.get("h", b.get("w", 0.1))) * 0.5
	var at := c + nrm * float(b.get("lift", 0.0015))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners := [[-1.0, 1.0, Vector2(0, 0)], [1.0, 1.0, Vector2(1, 0)], [1.0, -1.0, Vector2(1, 1)], [-1.0, -1.0, Vector2(0, 1)]]
	for k in [0, 1, 2, 0, 2, 3]:
		st.set_normal(nrm)
		st.set_uv(corners[k][2])
		st.add_vertex(at + right * w * corners[k][0] + up * h * corners[k][1])
	var mi := MeshInstance3D.new()
	mi.name = "LiveBoard"
	mi.mesh = st.commit()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var host: MeshInstance3D = null
	for n in car.body_model.find_children("*", "MeshInstance3D", true, false):
		host = n
		break
	if host:
		mi.layers = host.layers
	var sc: Dictionary = b.duplicate()
	sc.rect = [0.0, 0.0, 1.0, 1.0]
	if not sc.has("aspect"):
		sc.aspect = w / h
	var ov := _overlay_material(StandardMaterial3D.new(), {"units": "uv", "screens": [sc], "solid": true})
	ov.render_priority = 0
	ov.set_shader_parameter("round_mask", bool(b.get("round", false)))
	mi.material_override = ov
	car.body_model.add_child(mi)
	boards.append(mi)


## A surface's triangles as indices (three per triangle).
## A mesh's transform in the model (the car's body_model): its points in the model's space.
func _rel(n: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var p: Node = n
	while p and p != car.body_model:
		if p is Node3D:
			xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf


static func _indices(arr: Array) -> PackedInt32Array:
	var idx = arr[Mesh.ARRAY_INDEX]
	if idx != null and idx.size() > 0:
		return idx
	var ids := PackedInt32Array()
	for i in (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size():
		ids.append(i)
	return ids


## The triangles (of `tris`) in touching groups: ones sharing a corner (by position).
static func _groups(vs: PackedVector3Array, ids: PackedInt32Array, tris: Array) -> Array:
	var parent: Array = []
	var by_key := {}
	var find := func(x: int) -> int:
		while parent[x] != x:
			parent[x] = parent[parent[x]]
			x = parent[x]
		return x
	for i in tris.size():
		parent.append(i)
	for i in tris.size():
		var t: int = tris[i]
		for k in 3:
			var key := Vector3i((vs[ids[t * 3 + k]] * 4000.0).round())
			if by_key.has(key):
				var a: int = find.call(i)
				var b: int = find.call(by_key[key])
				if a != b:
					parent[a] = b
			else:
				by_key[key] = i
	var out := {}
	for i in tris.size():
		var r: int = find.call(i)
		if not out.has(r):
			out[r] = []
		out[r].append(tris[i])
	return out.values()


static func _mid(vs: PackedVector3Array, ids: PackedInt32Array, g: Array) -> Vector3:
	var m := Vector3.ZERO
	for t in g:
		m += vs[ids[t * 3]]
	return m / maxf(g.size(), 1.0)


## Needles modelled as parts: the material's triangles in touching groups; a needle is
## the groups passing through its hub (the hub within "grow" of the group's box; "max_size":
## no group longer than that, m, a needle sharing its material with the cabin's trim), cut
## out into a part of its own turning about the hub (the axis: toward the driver, or
## the dial's own); the rest of that surface stays where it is (lit at night with the needles,
## unless the material is shared with the trim, "max_size": then in its own material); the
## original faces hidden. A surface of the material holding none of the needles (the steering
## wheel's, cut out to turn) is left alone.
func _needle_mesh(nm: Dictionary) -> void:
	var c := _wheel()
	var todo: Array = nm.needles.duplicate()
	var biggest := float(nm.get("max_size", INF))
	var found := _surfaces(str(nm.mat), func(m: MeshInstance3D, si: int, base: Material):
		if todo.is_empty():
			return
		var arr := m.mesh.surface_get_arrays(si)
		var xf := _rel(m)
		var vs: PackedVector3Array = xf * (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array)
		var ns = arr[Mesh.ARRAY_NORMAL]
		if ns != null and ns.size() > 0:
			ns = PackedVector3Array(Array(ns).map(func(x): return (xf.basis * x).normalized()))
		var tg = arr[Mesh.ARRAY_TANGENT]
		if tg != null and tg.size() > 0:                 # (the normal map's tangents turned into the model's space too)
			var tt := PackedFloat32Array(tg)
			for i in tt.size() / 4:
				var t3: Vector3 = (xf.basis * Vector3(tt[i * 4], tt[i * 4 + 1], tt[i * 4 + 2])).normalized()
				tt[i * 4] = t3.x
				tt[i * 4 + 1] = t3.y
				tt[i * 4 + 2] = t3.z
			tg = tt
		var uvs = arr[Mesh.ARRAY_TEX_UV]
		var ids := _indices(arr)
		var all_t: Array = range(ids.size() / 3)
		var groups := _groups(vs, ids, all_t)
		var boxes: Array = []
		for g in groups:
			var box := AABB(vs[ids[g[0] * 3]], Vector3.ZERO)
			for t in g:
				for k in 3:
					box = box.expand(vs[ids[t * 3 + k]])
			boxes.append(box)
		var eye: Vector3 = cockpit.eye_driver - car.model_offset()
		var used := {}
		var mat: Material = base.duplicate()
		for n in todo.duplicate():
			var hub: Vector3 = c + Vector3(n.hub[0], n.hub[1], n.hub[2])
			var grow := float(n.get("grow", 0.008))
			var mine: Array = []
			for gi in groups.size():
				var box: AABB = boxes[gi]
				if not used.has(gi) and box.size[box.get_longest_axis_index()] <= biggest and box.grow(grow).has_point(hub):
					mine.append(gi)
			if mine.is_empty():
				continue
			todo.erase(n)
			var tris: Array = []
			for gi in mine:
				used[gi] = true
				tris.append_array(groups[gi])
			var pivot := Node3D.new()
			pivot.name = "Needle_" + str(n.get("value", "kmh"))
			pivot.position = hub
			car.body_model.add_child(pivot)
			pivot.add_child(_part(vs, ns, uvs, ids, tris, hub, mat, m, tg))
			var axis := (eye - hub).normalized()
			if n.has("axis"):
				axis = Vector3(n.axis[0], n.axis[1], n.axis[2]).normalized()
			needle_parts.append({"pivot": pivot, "axis": axis, "n": n})
		if used.is_empty():
			return                                       # (none of the needles here: the surface as it was)
		var rest: Array = []
		for gi in groups.size():
			if not used.has(gi):
				rest.append_array(groups[gi])
		if not rest.is_empty():
			var still := _part(vs, ns, uvs, ids, rest, Vector3.ZERO, base if nm.has("max_size") else mat, m, tg)
			still.name = "NeedlesStill"
			car.body_model.add_child(still)
		needle_mats.append(mat)
		m.set_surface_override_material(si, _hidden()))   # (the original needles: drawn by nothing)
	for n in todo:
		missing.append("needle " + str(n.get("value")))
	if not found:
		missing.append("needle mesh " + str(nm.mat))


func _part(vs: PackedVector3Array, ns, uvs, ids: PackedInt32Array, tris: Array, origin: Vector3, mat: Material, host: MeshInstance3D, tg = null) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for t in tris:
		for k in 3:
			var vi: int = ids[t * 3 + k]
			if ns != null and ns.size() > vi:
				st.set_normal(ns[vi])
			if tg != null and tg.size() >= vi * 4 + 4:
				st.set_tangent(Plane(tg[vi * 4], tg[vi * 4 + 1], tg[vi * 4 + 2], tg[vi * 4 + 3]))
			if uvs != null and uvs.size() > vi:
				st.set_uv(uvs[vi])
			st.add_vertex(vs[vi] - origin)
	var part := MeshInstance3D.new()
	part.mesh = st.commit()
	part.material_override = mat
	part.layers = host.layers
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return part


static var _hide: ShaderMaterial

static func _hidden() -> ShaderMaterial:
	if _hide == null:
		var sh := Shader.new()
		sh.code = "shader_type spatial;\nrender_mode unshaded, shadows_disabled;\nvoid fragment() { discard; }\n"
		_hide = ShaderMaterial.new()
		_hide.shader = sh
	return _hide


## The dome light: under the roof between the front seats (off until it's switched).
func _make_dome() -> void:
	_dome = OmniLight3D.new()
	_dome.name = "DomeLight"
	_dome.light_color = Color(1.0, 0.95, 0.86)
	_dome.light_energy = 0.42
	_dome.omni_range = 1.6
	_dome.omni_attenuation = 1.2
	_dome.shadow_enabled = false
	_dome.visible = false
	var at: Vector3 = (cockpit.eye_driver + cockpit.eye_codriver) * 0.5 + Vector3(0.0, 0.2, 0.1)
	if spec.has("dome"):
		at = Vector3(spec.dome[0], spec.dome[1], spec.dome[2]) + car.model_offset()
	_dome.position = at
	cockpit.add_child(_dome)


## The ambient lighting: soft coloured lights low in the cabin, lit with the night.
func _make_ambient() -> void:
	var a = spec.get("ambient")
	if not (a is Dictionary):
		return
	var spots: Array = []
	if a.has("at"):
		var c := cockpit.wheel_c as Vector3
		for p in a.at:
			spots.append(c + Vector3(p[0], p[1], p[2]))
	else:
		var ed: Vector3 = cockpit.eye_driver
		var ec: Vector3 = cockpit.eye_codriver
		var out := signf(ed.x - ec.x)                    # (the driver's side, outward)
		spots = [(ed + ec) * 0.5 + Vector3(0.0, -0.62, -0.34),
			ed + Vector3(out * 0.3, -0.42, -0.05), ec + Vector3(-out * 0.3, -0.42, -0.05)]
	for i in spots.size():
		var l := OmniLight3D.new()
		l.name = "Ambient%d" % i
		l.light_color = Color(str(a.get("color", "#ffb070")))
		l.light_energy = float(a.get("energy", 0.3))
		l.omni_range = float(a.get("range", 0.75))
		l.omni_attenuation = 1.6
		l.shadow_enabled = false
		l.position = spots[i]
		l.visible = false
		cockpit.add_child(l)
		ambient.append(l)


func toggle_dome() -> void:
	dome_on = not dome_on
	_dome.visible = dome_on


func next_page() -> void:
	for p in pages:
		p.next_page()


## What the instruments read this frame.
func _read(dt: float) -> void:
	var v: Vector3 = car.linear_velocity
	if dt > 0.0:
		var a: Vector3 = (v - _prev_v) / dt
		var b: Basis = car.global_transform.basis
		var g := Vector2(a.dot(b.x), a.dot(b.z)) / 9.8
		_gfx = _gfx.lerp(g, clampf(dt * 6.0, 0.0, 1.0))
	_prev_v = v
	_warm = minf(_warm + dt * (0.3 + float(car.rpm)) / 240.0, 1.0)   # (a few minutes' running, quicker at high revs)
	var eng = car.config.engine if car.config else null
	var idle: float = eng.idle_rpm if eng else 900.0
	var top: float = eng.limiter_rpm if eng else 7000.0
	var game = car.get_parent()
	var ev: bool = bool(spec.get("electric", eng != null and "regen_torque" in eng and float(eng.regen_torque) > 0.0))
	data = {
		"kmh": car.kmh(), "rpm01": float(car.rpm), "rpm": lerpf(idle, top, float(car.rpm)) if car.rpm > 0.001 else 0.0,
		"limiter": top, "gear": int(car.gear), "g": _gfx, "handbrake": car.handbrake_on(),
		"throttle": clampf(maxf(float(car.inp.get("throttle", 0.0)), float(car.net_throttle)), 0.0, 1.0),
		"brake": clampf(float(car.inp.get("brake", 0.0)), 0.0, 1.0),
		"auto": str(cockpit.own.get("gearbox", "")) == "auto",
		"time": float(game.stage_time) if game and "stage_time" in game else 0.0,
		"state": str(game.state) if game and "state" in game else "",
		"car_s": float(cockpit.map_board.car_s) if cockpit.map_board else 0.0,
		"night": night,
		"fuel": clampf(0.86 - float(game.stage_time if game and "stage_time" in game else 0.0) / 3600.0, 0.1, 1.0),
		"electric": ev,
	}
	var rs = car.race                                      # (Track Mode's: its fuel in litres, its ABS and TC maps, the pit limiter)
	var aid = car.assist
	data.merge({
		"pit": rs != null and bool(rs.limiter),
		"abs_set": int(rs.abs_level) if rs else (1 if aid and aid.cfg.anti_lock else 0),
		"tc_set": int(rs.tc_level) if rs else (1 if aid and aid.cfg.traction_control else 0),
		"warm": _warm, "ambient": float(rs.ambient) if rs else 20.0,
		# (the water, oil and gearbox warming from the air to running temperature, C)
		"t_water": lerpf(float(rs.ambient) if rs else 20.0, 86.0, _warm),
		"t_oil": lerpf(float(rs.ambient) if rs else 20.0, 102.0, _warm),
		"t_gear": lerpf(float(rs.ambient) if rs else 20.0, 82.0, _warm),
		"tyre_c": rs.tyres.map(func(t): return float(t.surface)) if rs else [],   # (FL, FR, RL, RR)
		"wet": float(rs.wet) if rs else 0.0,
	})
	data.merge(fake, true)
	data.range = float(data.fuel) * float(spec.get("range_km", 420.0))
	if not fake.has("fuel_l"):
		data.fuel_l = float(rs.fuel_l) if rs else float(data.fuel) * float(spec.get("tank_l", 120.0))


func warning(what: String) -> bool:
	if _t < BULB_CHECK:
		return true
	match what:
		"handbrake":
			return data.get("handbrake", false)
		"abs":
			return car.assist != null and car.assist.cfg.anti_lock and car.assist.abs_ease.min() < 0.9
		"tc":
			return car.assist != null and car.assist.cfg.traction_control and car.assist.tc_cut < 0.9
		"shift":
			return float(data.get("rpm01", 0.0)) > 0.93
		"lights":
			return night
		"flash":
			return Input.is_action_pressed("flash")
		"pit":
			return bool(data.get("pit", false))
	return false                                         # ("ignition": only the bulb check)


func _process(dt: float) -> void:
	if car == null:
		return
	_t += dt
	_read(dt)
	var glow := 1.0 if night else 0.0
	if night != _lit:
		_lit = night
		for l in ambient:
			(l as OmniLight3D).visible = night
		for m in needle_mats:
			if m is StandardMaterial3D:
				m.emission_enabled = night
				m.emission = Color(1, 1, 1)
				m.emission_texture = m.albedo_texture
				m.emission_energy_multiplier = 0.9
	for o in overlays:
		var ov: ShaderMaterial = o.mat
		var ang: Array = []
		for n in o.needles:
			var a := deg_to_rad(_needle_deg(n))
			ang.append(Vector4(a, deg_to_rad(float(n.get("painted", 0.0))), deg_to_rad(float(n.get("shift", 18.0))),
				1.0 if n.has("painted") and not o.get("baked", false) else 0.0))
		ov.set_shader_parameter("needle_ang", _pad(ang, MAX_NEEDLES))
		var on: Array = []
		for w in o.warns:
			on.append(1.0 if warning(w) else 0.0)
		while on.size() < MAX_RECTS:
			on.append(0.0)
		ov.set_shader_parameter("warn_on", PackedFloat32Array(on))
		ov.set_shader_parameter("glow", glow)
		if not o.leds.is_empty():
			var boxes: Array = []
			for row in o.leds:
				boxes.append(led_box(row, o.to_local, float(data.get(str(row.what), 0.0))))
			ov.set_shader_parameter("led_box", _pad(boxes, MAX_LED_ROWS))
	for np in needle_parts:
		var n: Dictionary = np.n
		# its turn from where it was modelled (pointing at "rest"), clockwise as the driver sees it
		var turn := deg_to_rad(float(n.sweep)) * (_share(n) - _share(n, float(n.get("rest", n.get("min", 0.0)))))
		(np.pivot as Node3D).basis = Basis(np.axis, -turn)
	_screen_t += dt
	if _screen_t >= 1.0 / SCREEN_HZ:
		_screen_t = 0.0
		for p in pages:
			p.queue_redraw()
			(p.get_parent() as SubViewport).render_target_update_mode = SubViewport.UPDATE_ONCE


## How far round its scale a needle is (0..1): its value now, or v.
## A painted dial's needle angle (degrees) for its reading: along "marks" ([[value, deg], ...]: a scale
## whose numbers aren't evenly spaced, the GT-R's speedometer's), else "a0" to "a1" by its share.
func _needle_deg(n: Dictionary) -> float:
	if n.has("marks"):
		return marks_deg(n.marks, absf(float(data.get(str(n.get("value", "kmh")), 0.0))))
	return lerpf(float(n.a0), float(n.a1), _share(n))


static func marks_deg(marks: Array, v: float) -> float:
	if v <= float(marks[0][0]):
		return float(marks[0][1])
	for i in range(1, marks.size()):
		if v <= float(marks[i][0]):
			var f := (v - float(marks[i - 1][0])) / maxf(float(marks[i][0]) - float(marks[i - 1][0]), 1e-4)
			return lerpf(float(marks[i - 1][1]), float(marks[i][1]), f)
	return float(marks[-1][1])


func _share(n: Dictionary, v = null) -> float:
	var x: float = float(data.get(str(n.get("value", "kmh")), 0.0)) if v == null else float(v)
	if str(n.get("value", "")) == "kmh":
		x = absf(x)
	return clampf((x - float(n.get("min", 0.0))) / maxf(float(n.get("max", 260.0)) - float(n.get("min", 0.0)), 1e-3), 0.0, 1.0)


static var _sh: Shader
static var _sh_solid: Shader

## The overlay's shader: drawn over a surface (blended, it writes no depth), or solid
## (a panel: a mesh of its own, so the interior's see-through parts drawn after it,
## a screen's glass, can't cover it).
static func _shader(solid := false) -> Shader:
	if _sh == null:
		_sh = Shader.new()
		_sh.code = OVERLAY
		_sh_solid = Shader.new()
		_sh_solid.code = OVERLAY.replace("blend_mix, unshaded, depth_draw_never,", "unshaded,").replace("ALPHA = outc.a;", "")
	return _sh_solid if solid else _sh


const OVERLAY := """
shader_type spatial;
render_mode blend_mix, unshaded, depth_draw_never, shadows_disabled, fog_disabled;
uniform sampler2D base_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool has_base = false;
uniform float aspect = 1.0;
uniform int screen_count = 0;
uniform vec4 screen_rect[3];
uniform sampler2D screen_tex0 : source_color, filter_linear;
uniform sampler2D screen_tex1 : source_color, filter_linear;
uniform sampler2D screen_tex2 : source_color, filter_linear;
uniform float screen_flip[3];
uniform float screen_light = 0.92;
uniform int needle_count = 0;
uniform vec4 needle_geo[8];   // centre u, v, radius, half width (the radius and width in the texture's height)
uniform vec4 needle_ang[8];   // angle now, the painted needle's angle, the cover's shift (rad), covered (0 / 1)
uniform vec4 needle_col[8];   // colour, its tail (a share of the radius)
uniform vec4 needle_off[8];   // the cover copied from this far over (u, v), on (z): a striped face, along its stripes
uniform int glow_count = 0;
uniform vec4 glow_rect[8];
uniform float glow = 0.0;
uniform vec3 glow_tint : source_color = vec3(1.0);
uniform int warn_count = 0;
uniform vec4 warn_rect[8];
uniform float warn_on[8];
uniform vec4 warn_col[8];
uniform bool round_mask = false;   // (a round board: only its disc)
uniform bool wrap_uv = false;      // (UVs a whole tile over: measured in the texture's own 0..1)
uniform int led_count = 0;
uniform vec4 led_box[4];           // a row of LEDs' lit part: x from, x to, y low, y high (the mesh's own axes)
varying vec3 mpos;

void vertex() {
	mpos = VERTEX;
}

bool inside(vec2 uv, vec4 r) {
	return uv.x >= r.x && uv.y >= r.y && uv.x <= r.z && uv.y <= r.w;
}

float wrap_pi(float a) {
	return mod(a + PI, TAU) - PI;
}

vec3 base_at(vec2 uv) {
	return has_base ? texture(base_tex, uv).rgb : vec3(1.0);
}

vec3 screen_at(int i, vec2 q) {
	if (i == 0) return texture(screen_tex0, q).rgb;
	if (i == 1) return texture(screen_tex1, q).rgb;
	return texture(screen_tex2, q).rgb;
}

void fragment() {
	vec2 uv = wrap_uv ? fract(UV) : UV;
	if (round_mask && length(uv - vec2(0.5)) > 0.5) {
		discard;
	}
	vec4 outc = vec4(0.0);
	for (int i = 0; i < glow_count; i++) {
		if (inside(uv, glow_rect[i])) {
			outc = vec4(base_at(uv) * glow_tint, glow);
		}
	}
	for (int i = 0; i < needle_count; i++) {
		vec4 g = needle_geo[i];
		vec2 d = (uv - g.xy) * vec2(aspect, 1.0);
		float dist = length(d);
		if (dist > g.z * 1.02) {
			continue;
		}
		vec4 an = needle_ang[i];
		float a = atan(d.y, d.x);
		if (an.w > 0.5 && dist < g.z * 0.97) {
			// the painted needle: within its wedge, the dial face from a little further round
			float half_w = (g.w * 2.4) / max(dist, g.w * 2.0);
			if (abs(wrap_pi(a - an.y)) < half_w + 0.015) {
				vec2 q = needle_off[i].z > 0.5 ? uv + needle_off[i].xy : g.xy + vec2(cos(a + an.z), sin(a + an.z)) * dist / vec2(aspect, 1.0);
				outc = vec4(base_at(q), 1.0);
			}
		}
		vec2 dir = vec2(cos(an.x), sin(an.x));
		float along = dot(d, dir);
		float across = abs(dot(d, vec2(-dir.y, dir.x)));
		float tail = -needle_col[i].a * g.z;
		float len = g.z * 0.9;
		float t = clamp((along - tail) / (len - tail), 0.0, 1.0);
		float w = mix(g.w * 1.25, g.w * 0.45, t);
		if (along > tail && along < len && across < w) {
			outc = vec4(needle_col[i].rgb, 1.0);
		}
		if (dist < g.w * 2.0) {
			outc = vec4(vec3(0.06), 1.0);       // the hub
		}
	}
	for (int i = 0; i < screen_count; i++) {
		vec4 r = screen_rect[i];
		if (inside(uv, r)) {
			vec2 q = (uv - r.xy) / (r.zw - r.xy);
			if (screen_flip[i] > 1.5) {
				q = q.yx;                       // (a screen laid sideways in its texture: its across is the texture's down)
			} else if (screen_flip[i] > 0.5) {
				q.y = 1.0 - q.y;
			}
			outc = vec4(screen_at(i, q) * screen_light, 1.0);
		}
	}
	for (int i = 0; i < warn_count; i++) {
		if (warn_on[i] > 0.5 && inside(uv, warn_rect[i])) {
			vec3 b = base_at(uv);
			float lum = has_base ? max(b.r, max(b.g, b.b)) : 0.5;   // (an untextured lamp: its colour, lit)
			outc = vec4(warn_col[i].rgb * (0.35 + lum * 1.6), 1.0);
		}
	}
	for (int i = 0; i < led_count; i++) {
		vec4 b = led_box[i];
		if (mpos.x >= min(b.x, b.y) && mpos.x <= max(b.x, b.y) && mpos.y >= b.z && mpos.y <= b.w) {
			vec3 c = base_at(uv);                  // (lit in its own colour: the dark red or green, bright)
			outc = vec4(c / max(max(c.r, max(c.g, c.b)), 0.04), 1.0);
		}
	}
	if (outc.a <= 0.002) {
		discard;
	}
	ALBEDO = outc.rgb;
	ALPHA = outc.a;
}
"""
