extends Control
## One live screen in a car's own interior (dash_live.gd shows it on the screen's
## part of the surface):
##   * "cluster" over the car's own painted cluster ("bg", the default when the
##     surface has a texture): drawn in the texture's pixels; what changes is drawn
##     over the picture from the spec's "layout" (data/dash/<model>.json): "cover"
##     rectangles hide the painted readings, then "text" (the speed, the gear, the
##     clock, the stage time), "arc" (the revs or the speed filling along a band:
##     the points down its middle; "invert": what's left of it, to dim a painted bar's empty end),
##     "needle" (a live needle on a painted dial), "gdot" (the g-meter's dot), "sel" (the gear
##     selector's painted letters: all but the gear's dimmed), "lit" (painted lamps and banners
##     shown only while what they show is on: hidden, or dimmed, the rest of the time), "lamp"
##     (warning lamps drawn); a text with "when" is drawn only while that is on
##   * "cluster" on a blank screen ("bg": false): a digital cluster of its own, drawn
##     on a canvas the screen's shape ("aspect": its width / height as you see it):
##     the revs in a band across the top (the shift lamps above), the speed, the
##     gear, the fuel (an electric car: its charge and range), the warning lamps along
##     the bottom, in the car's accent colour; "style": "dials": two round dials drawn
##     on the screen instead (the speed on the left, the revs or, electric, the power
##     on the right, their needles sweeping), the gear and the fuel between them
##   * "nav": the centre screen: a menu down the left (the page you're on lit in the
##     accent colour) and the page: NAVIGATION, the road around you heading up, your
##     car in the middle, the distance to go, what's playing along the bottom; DRIVING
##     INFORMATION, the speed, gear, revs, the fuel or charge, a g-meter and the stage
##     clock. M (the d-pad right) flips the page.
##   * "lcd": a small segment display (an old car's clock): one reading ("what": the
##     clock by default) in its colour, the unlit segments ("88:88") faint behind it
##   * "dial": one round dial on a board of its own (a car whose dials are blank):
##     "what" kmh or rpm (the scale to "max", numbers every "step", red past "red" for the
##     revs), its face colour "face", the needle "needle"

var live                            # DashLive (its data, warning())
var cfg := {}
var base: Texture2D                 # the texture the screen is part of
var src := Rect2()                  # the part of it the screen covers (its pixels)
var view := Rect2()                 # what's drawn in: the texture's pixels, or the canvas
var page := 0
var _font: Font
var _font_b: Font

const NAV_ITEMS := ["Navigation", "Driving information", "Vehicle status", "Settings"]
const NAV_TABS := ["MAP", "DRIVE", "CAR", "SETUP"]   # (a tall screen's menu: tabs across its top)
const WIDTH := 900.0                # the screen's picture, px across


func setup(the_live, the_cfg: Dictionary, tex: Texture2D, region: Rect2) -> void:
	live = the_live
	cfg = the_cfg
	base = tex
	src = region
	var across := Vector2(region.size.y, region.size.x) if cfg.get("transpose", false) else region.size   # (as it's seen)
	if _painted():
		view = Rect2(Vector2.ZERO, across) if cfg.get("transpose", false) else region
	else:
		var aspect := float(cfg.get("aspect", across.x / maxf(across.y, 1e-4)))
		var canvas: Array = cfg.get("canvas", [1000.0, 1000.0 / aspect])
		view = Rect2(0, 0, float(canvas[0]), float(canvas[1]))
	var k := float(cfg.get("px", WIDTH)) / view.size.x
	size = view.size * k
	_font = load("res://assets/fonts/Oswald-Medium.woff2")
	_font_b = load("res://assets/fonts/Oswald-Bold.woff2")
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## A portrait or squarish screen (the centre screen's menu goes across its top, short).
func tall() -> bool:
	return view.size.x < view.size.y * 1.3


func _painted() -> bool:
	return str(cfg.get("page", "")) == "cluster" and base != null and cfg.get("bg", true)


func next_page() -> void:
	if str(cfg.get("page", "")) == "nav":
		page = (page + 1) % 2


func _draw() -> void:
	var k := size.x / view.size.x
	draw_set_transform(-view.position * k, 0.0, Vector2(k, k))
	match str(cfg.get("page", "")):
		"cluster":
			if _painted():
				_cluster()
			else:
				_own_cluster()
		"nav":
			_nav()
		"lcd":
			_lcd()
		"dial":
			_one_dial()


# ── a painted cluster, made live ──────────────────────────────────────────

func _cluster() -> void:
	var d: Dictionary = live.data
	var lay: Dictionary = cfg.get("layout", {})
	if cfg.get("transpose", false):                 # (laid sideways in its texture: drawn as it's seen, the layout
		var kt := size.x / view.size.x               # measured on it that way, its across the texture's down)
		var at_t := Transform2D(0.0, Vector2(kt, kt), 0.0, -view.position * kt)
		draw_set_transform_matrix(at_t * Transform2D(Vector2(0, 1), Vector2(1, 0), Vector2(-src.position.y, -src.position.x)))
		draw_texture_rect_region(base, src, src)
		draw_set_transform_matrix(at_t)
	elif cfg.get("flip_v", false):                  # (a texture stored upside down: drawn the right way up here,
		var k := size.x / view.size.x               # the layout measured on it that way; the screen turns it back)
		var at := Transform2D(0.0, Vector2(k, k), 0.0, -view.position * k)
		draw_set_transform_matrix(at * Transform2D(Vector2(1, 0), Vector2(0, -1), Vector2(0, src.position.y * 2.0 + src.size.y)))
		draw_texture_rect_region(base, src, src)
		draw_set_transform_matrix(at)
	else:
		draw_texture_rect_region(base, src, src)
	for c in lay.get("cover", []):
		var col := Color(str(c[4])) if c.size() > 4 else Color(0.0, 0.0, 0.0)
		draw_rect(Rect2(c[0], c[1], float(c[2]) - float(c[0]), float(c[3]) - float(c[1])), col)
	for li in lay.get("lit", []):                   # (a painted lamp or banner: shown only while it's on)
		if not live.warning(str(li.what)):
			var r: Array = li.rect
			draw_rect(Rect2(r[0], r[1], float(r[2]) - float(r[0]), float(r[3]) - float(r[1])), Color(str(li.get("dim", "#000000"))))
	for a in lay.get("arc", []):
		_arc(a, d)
	for n in lay.get("needle", []):
		_needle(n, d)
	for t in lay.get("text", []):
		_text(t, d)
	if lay.has("gdot"):
		var g: Dictionary = lay.gdot
		var gv: Vector2 = d.get("g", Vector2.ZERO)
		var p := Vector2(g.c[0], g.c[1]) + (gv / float(g.get("g", 1.2))).limit_length(1.0) * float(g.r)
		draw_circle(p, float(g.get("dot", 2.2)), Color(str(g.get("color", "#ff2a1a"))))
	if lay.has("sel"):
		var lit := _selector(d)
		for sl in lay.sel:
			if str(sl.g) != lit:
				var r: Array = sl.rect
				draw_rect(Rect2(r[0], r[1], float(r[2]) - float(r[0]), float(r[3]) - float(r[1])), Color(str(sl.get("dim", "#000000c0"))))
	for l in lay.get("lamp", []):
		_lamp(l)


## The gear selector's letter for the gear: P, R, N, or D (any forward gear, the box in D or M).
func _selector(d: Dictionary) -> String:
	var g := _gear(d, "bmw")
	return g if g in ["P", "R", "N"] else "D"


func _value(what: String, d: Dictionary) -> float:
	return float(d.get(what, 0.0))


## A band filling up with the value: thick segments along the points ("at": each point's value, for
## a scale whose numbers aren't evenly spaced; "hot_at": the value it turns "hot" from, else "hot_from":
## the share of the band).
func _arc(a: Dictionary, d: Dictionary) -> void:
	var pts: Array = a.pts
	var v := absf(_value(str(a.what), d))
	if a.get("invert", false):                      # (what's left: a painted bar's empty end, from its far end)
		v = maxf(float(a.get("max", 1.0)) - v, 0.0)
	var lens: Array = [0.0]
	for i in range(1, pts.size()):
		lens.append(lens[-1] + Vector2(pts[i][0], pts[i][1]).distance_to(Vector2(pts[i - 1][0], pts[i - 1][1])))
	var total: float = lens[-1]
	var at: Array = a.get("at", [])
	var want := arc_reach(at, lens, v) if at.size() == pts.size() else clampf(v / maxf(float(a.get("max", 1.0)), 1e-3), 0.0, 1.0) * total
	var hot := arc_reach(at, lens, float(a.hot_at)) if a.has("hot_at") and at.size() == pts.size() else float(a.get("hot_from", 0.85)) * total
	var w := float(a.get("w", 4.0))
	var lo := Color(str(a.get("color", "#f2f2f2")))
	var hi := Color(str(a.get("hot", "#ff3b1f")))
	for i in range(1, pts.size()):
		if lens[i - 1] >= want:
			break
		var p0 := Vector2(pts[i - 1][0], pts[i - 1][1])
		var p1 := Vector2(pts[i][0], pts[i][1])
		var seg: float = maxf(lens[i] - lens[i - 1], 1e-3)
		var f := clampf((want - lens[i - 1]) / seg, 0.0, 1.0)
		var fh := clampf((hot - lens[i - 1]) / seg, 0.0, f)       # (where it turns hot, in this segment)
		if fh > 0.0:
			draw_line(p0, p0.lerp(p1, fh), lo, w, true)
		if f > fh:
			draw_line(p0.lerp(p1, fh), p0.lerp(p1, f), hi, w, true)


## A needle on a painted dial ("c", "r": its hub and length; "a0" / "a1": its angle at 0 and at "max",
## degrees, 0 right, 90 down): the painted needle ("hide": its angle, "hide_w" either side, from
## "hide_r0" out) covered with the dial's face copied from "shift" degrees further round, then the
## live one drawn over it, turning with the reading.
func _needle(n: Dictionary, d: Dictionary) -> void:
	var c := Vector2(n.c[0], n.c[1])
	var r := float(n.r)
	if n.has("hide"):
		var a := deg_to_rad(float(n.hide))
		var half := deg_to_rad(float(n.get("hide_w", 6.0)))
		var sh := deg_to_rad(float(n.get("shift", 20.0)))
		var r0 := maxf(float(n.get("hide_r0", 4.0)), 1.0)
		var pts := PackedVector2Array()
		for i in 7:                                         # (the wedge: out along one side, back along the other)
			var t := a - half + half * i / 3.0
			pts.append(c + Vector2(cos(t), sin(t)) * float(n.get("hide_r1", r * 1.04)))
		for i in range(6, -1, -1):
			var t := a - half + half * i / 3.0
			pts.append(c + Vector2(cos(t), sin(t)) * r0)
		var uvs := PackedVector2Array()
		for q in pts:
			uvs.append(_tex_uv(c + (q - c).rotated(sh)))
		draw_polygon(pts, PackedColorArray([Color.WHITE]), uvs, base)
	var ang := needle_angle(n, _value(str(n.what), d))
	var dir := Vector2(cos(ang), sin(ang))
	draw_line(c - dir * r * float(n.get("tail", 0.1)), c + dir * r, Color(str(n.get("color", "#ff3b1f"))), float(n.get("w", 3.0)), true)
	if float(n.get("hub", 0.0)) > 0.0:
		draw_circle(c, float(n.hub), Color(str(n.get("hub_color", "#101010"))))


## Where a painted dial's needle points for a reading (radians, 0 right, down positive).
static func needle_angle(n: Dictionary, v: float) -> float:
	var u := clampf(absf(v) / maxf(float(n.get("max", 1.0)), 1e-3), 0.0, 1.0)
	return deg_to_rad(lerpf(float(n.a0), float(n.a1), u))


## A point of a painted page (its own pixels: sideways or upside down as the texture has it) as the
## texture's UV.
func _tex_uv(p: Vector2) -> Vector2:
	var t := p
	if cfg.get("transpose", false):
		t = Vector2(src.position.x + p.y, src.position.y + p.x)
	elif cfg.get("flip_v", false):
		t = Vector2(p.x, src.position.y * 2.0 + src.size.y - p.y)
	return t / Vector2(base.get_width(), base.get_height())


## How far along a band (its points' running lengths) a value reaches, given each point's value.
static func arc_reach(at: Array, lens: Array, v: float) -> float:
	if at.is_empty() or v <= float(at[0]):
		return 0.0
	for i in range(1, at.size()):
		if v <= float(at[i]):
			return lens[i - 1] + (lens[i] - lens[i - 1]) * (v - float(at[i - 1])) / maxf(float(at[i]) - float(at[i - 1]), 1e-6)
	return lens[-1]


func _text(t: Dictionary, d: Dictionary) -> void:
	if t.has("when") and not live.warning(str(t.when)):
		return
	var s := _reading(str(t.what), d, t)
	var px := float(t.get("size", 10.0))
	_say(s, Vector2(t.at[0], t.at[1]), px, Color(str(t.get("color", "#ffffff"))), str(t.get("align", "center")), t.get("bold", true), float(t.get("max_w", -1.0)))


func _reading(what: String, d: Dictionary, t := {}) -> String:
	match what:
		"speed":
			return "%d" % roundi(absf(_value("kmh", d)))
		"mph":
			return "%d" % roundi(absf(_value("kmh", d)) / 1.609344)
		"gear_n":                                   # (the gear on its own: the number, or P / N / R)
			var gn := _gear(d, "bmw")
			return gn.substr(1) if gn.length() > 1 else gn
		"gear_mode":                                # (the box's mode beside it: D or M, nothing at P / N / R)
			var gm := _gear(d, "bmw")
			return gm.substr(0, 1) if gm.length() > 1 else ""
		"gear":
			return _gear(d, str(t.get("style", cfg.get("style", ""))))
		"unit":
			return str(t.get("text", "km/h"))
		"clock":
			var tm := Time.get_time_dict_from_system()
			return "%d:%02d" % [tm.hour, tm.minute]
		"time":
			var tt: float = _value("time", d)
			return "%d:%04.1f" % [int(tt / 60.0), fmod(tt, 60.0)]
		"rpm":
			return "%d" % (roundi(_value("rpm", d) / 100.0) * 100)
		"fuel":
			return "%d %%" % roundi(clampf(_value("fuel", d), 0.0, 1.0) * 100.0)
		"throttle", "brake":                        # (the pedals, as far down as they are)
			return "%d %%" % roundi(clampf(_value(what, d), 0.0, 1.0) * 100.0)
		"time_ms":                                  # (a race display's lap time: 01:23:456)
			var ms := roundi(maxf(_value("time", d), 0.0) * 1000.0)
			return "%02d:%02d:%03d" % [ms / 60000, (ms / 1000) % 60, ms % 1000]
		"speed_dec":                                # (to a tenth, a decimal comma: 61,8)
			return ("%.1f" % absf(_value("kmh", d))).replace(".", ",")
		"fuel_l":
			return "%.1f" % maxf(_value("fuel_l", d), 0.0)
		"time3":                                    # (a race display's lap time: 1:23.456)
			var m3 := roundi(maxf(_value("time", d), 0.0) * 1000.0)
			return "%d:%02d.%03d" % [m3 / 60000, (m3 / 1000) % 60, m3 % 1000]
		"oil_bar":                                  # (the oil pressure, climbing with the revs; 0 with the engine off)
			return "%.2f" % (lerpf(1.2, 5.6, clampf(_value("rpm01", d), 0.0, 1.0)) if _value("rpm", d) > 1.0 else 0.0)
		"tyre_fl", "tyre_fr", "tyre_rl", "tyre_rr":  # (Track Mode's tyre temperatures; "--" without them)
			var tc: Array = d.get("tyre_c", [])
			var k := ["tyre_fl", "tyre_fr", "tyre_rl", "tyre_rr"].find(what)
			return "%d" % roundi(float(tc[k])) if k < tc.size() else "--"
		"track":                                    # (the track: DRY, or WET in the rain)
			return "WET" if _value("wet", d) > 0.3 else "DRY"
		"abs_set", "tc_set":                        # (the ABS / TC map: Track Mode's level, else on 1 / off 0)
			return "%d" % int(_value(what, d))
		"t_water", "t_oil", "t_gear":               # (warming from the air to running temperature)
			var hot := {"t_water": 86.0, "t_oil": 102.0, "t_gear": 82.0}[what] as float
			return "%d" % roundi(lerpf(float(d.get("ambient", 20.0)), hot, clampf(_value("warm", d), 0.0, 1.0)))
		"range":
			return "%d km" % roundi(_value("range", d))
	return str(t.get("text", ""))


## Text with its middle (or left / right end) at `at`, its letters' middle on at.y; smaller
## if it would be wider than `max_w` (px; a narrow screen's).
func _say(s: String, at: Vector2, px: float, col: Color, align := "center", bold := true, max_w := -1.0) -> void:
	var f: Font = _font_b if bold else _font
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(int(px), 1)).x
	if max_w > 0.0 and w > max_w:
		px *= max_w / w
		w = max_w
	match align:
		"center":
			at.x -= w * 0.5
		"right":
			at.x -= w
	draw_string(f, at + Vector2(0, px * 0.36), s, HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(int(px), 1), col)


func _gear(d: Dictionary, style: String) -> String:
	var g := int(d.get("gear", 1))
	if str(d.get("state", "")) in ["grid", ""] and absf(float(d.get("kmh", 0.0))) < 1.0:
		return "P" if style in ["bmw", "ev"] else "N"
	if g < 0:
		return "R"
	if g == 0:
		return "N"
	if style == "bmw":
		return ("D%d" if d.get("auto", false) else "M%d") % g
	if style == "ev":                               # (one gear: an electric car's selector)
		return "D"
	return str(g)


## A warning lamp: its symbol lit in its colour (nothing, or a dim outline, when it's off).
func _lamp(l: Dictionary) -> void:
	var on: bool = live.warning(str(l.what))
	var at := Vector2(l.at[0], l.at[1])
	var px := float(l.get("size", 7.0))
	var col := Color(str(l.get("color", "#ff3b1f")))
	if not on:
		col = Color(col.r, col.g, col.b, float(l.get("off", 0.0)))
		if col.a <= 0.0:
			return
	match str(l.what):
		"shift":
			var w := float(l.get("w", 40.0))
			for k in 6:
				var c := Color("#ffcc00") if k < 2 else (Color("#ff7a00") if k < 4 else Color("#ff2010"))
				c.a = col.a
				draw_rect(Rect2(at.x - w * 0.5 + k * w / 6.0 + w * 0.012, at.y - px * 0.25, w / 6.0 - w * 0.024, px * 0.5), c)
		_:
			var label := str(l.get("label", {"handbrake": "(P)", "abs": "ABS", "tc": "DSC", "lights": "◖", "flash": "≡D"}.get(str(l.what), "!")))
			_say(label, at, px, col)


# ── a cluster of its own, on a blank screen ───────────────────────────────

func _own_cluster() -> void:
	if str(cfg.get("style", "")) == "dials":
		_dials()
		return
	var d: Dictionary = live.data
	var r := view
	var accent := Color(str(cfg.get("accent", "#1c69d4")))
	draw_rect(r, Color(0.015, 0.017, 0.022))
	var w := r.size.x
	var h := r.size.y
	# the revs: a band across the top, filling left to right, red past the shift point
	var band := Rect2(r.position + Vector2(w * 0.06, h * 0.2), Vector2(w * 0.88, h * 0.1))
	draw_rect(band, Color(1, 1, 1, 0.08))
	var u := clampf(float(d.get("rpm01", 0.0)), 0.0, 1.0)
	var fill := Rect2(band.position, Vector2(band.size.x * u, band.size.y))
	draw_rect(fill, Color("#ff3b1f") if u > 0.9 else accent.lightened(0.15))
	for k in 9:                                         # the thousands, under the band
		var x := band.position.x + band.size.x * k / 8.0
		draw_line(Vector2(x, band.end.y), Vector2(x, band.end.y + h * 0.04), Color(1, 1, 1, 0.5), maxf(w * 0.002, 1.0))
		var top: float = float(d.get("limiter", 7000.0))
		_say("%d" % roundi(top * k / 8000.0), Vector2(x, band.end.y + h * 0.1), h * 0.065, Color(0.75, 0.77, 0.8), "center", false)
	if live.warning("shift"):
		_lamp({"what": "shift", "at": [r.position.x + w * 0.5, r.position.y + h * 0.1], "w": w * 0.3, "size": h * 0.1})
	# the speed in the middle, the gear beside it
	_say(_reading("speed", d), r.position + Vector2(w * 0.42, h * 0.58), h * 0.34, Color(1, 1, 1))
	_say("km/h", r.position + Vector2(w * 0.42, h * 0.8), h * 0.075, Color(0.7, 0.72, 0.76), "center", false)
	_say(_gear(d, str(cfg.get("style", "bmw"))), r.position + Vector2(w * 0.66, h * 0.58), h * 0.26, accent.lightened(0.3))
	# the clock and the stage time in the corners, the lamps along the bottom
	_say(_reading("clock", d), r.position + Vector2(w * 0.08, h * 0.9), h * 0.075, Color(0.8, 0.82, 0.85), "left", false)
	_say(_reading("time", d), r.position + Vector2(w * 0.92, h * 0.9), h * 0.075, Color(0.8, 0.82, 0.85), "right", false)
	var lamps := [["handbrake", "#ff3b1f"], ["abs", "#ffb000"], ["tc", "#ffb000"]]
	for i in lamps.size():
		_lamp({"what": lamps[i][0], "at": [r.position.x + w * (0.42 + (i - 1) * 0.07), r.position.y + h * 0.92], "size": h * 0.08, "color": lamps[i][1]})
	# the fuel (or the charge and the range) on the right, under the gear
	_tank(d, Rect2(r.position + Vector2(w * 0.78, h * 0.5), Vector2(w * 0.15, h * 0.06)), accent, h * 0.07)


## The fuel left (an electric car: its charge, and the range under it): a bar, its figure.
func _tank(d: Dictionary, bar: Rect2, accent: Color, px: float) -> void:
	var f := clampf(_value("fuel", d), 0.0, 1.0)
	draw_rect(bar, Color(1, 1, 1, 0.1))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * f, bar.size.y)), Color("#ffb000") if f < 0.15 else accent.lightened(0.2))
	var ev: bool = d.get("electric", false)
	_say(("%s  %s" % ["⚡" if ev else "FUEL", _reading("fuel", d)]), bar.position + Vector2(0, -px * 0.9), px, Color(0.82, 0.84, 0.87), "left", false)
	if ev:
		_say(_reading("range", d), bar.position + Vector2(0, bar.size.y + px * 0.9), px, Color(0.82, 0.84, 0.87), "left", false)


## Two round dials on the screen (as the luxury cars' digital clusters draw them): the speed
## on the left, the revs (electric: the power used, 0-100 %) on the right, the gear, the
## fuel and the lamps between them.
func _dials() -> void:
	var d: Dictionary = live.data
	var r := view
	var accent := Color(str(cfg.get("accent", "#9fd3ff")))
	var needle := Color(str(cfg.get("needle", "#ff4a1c")))
	draw_rect(r, Color(0.01, 0.012, 0.016))
	var w := r.size.x
	var h := r.size.y
	var rr := minf(h * 0.44, w * 0.2)
	var ev: bool = d.get("electric", false)
	var top_kmh := float(cfg.get("kmh_max", 260.0))
	var lim: float = float(d.get("limiter", 7000.0))
	_dial(r.position + Vector2(w * 0.24, h * 0.5), rr, absf(_value("kmh", d)) / top_kmh, top_kmh, 20.0 if top_kmh <= 280.0 else 40.0, "km/h", accent, needle)
	if ev:
		_dial(r.position + Vector2(w * 0.76, h * 0.5), rr, clampf(_value("rpm01", d), 0.0, 1.0), 100.0, 10.0, "% POWER", accent, needle)
	else:
		_dial(r.position + Vector2(w * 0.76, h * 0.5), rr, clampf(_value("rpm", d) / lim, 0.0, 1.0), lim / 1000.0, 1.0, "x1000/min", accent, needle, lim * 0.88 / 1000.0)
	# between them: the gear, the speed in figures, the fuel, the clock, the lamps
	var mid := r.position + Vector2(w * 0.5, 0.0)
	_say(_gear(d, str(cfg.get("gear_style", "bmw"))), mid + Vector2(0, h * 0.34), h * 0.2, accent.lightened(0.3))
	_say(_reading("speed", d), mid + Vector2(0, h * 0.58), h * 0.13, Color(1, 1, 1))
	_tank(d, Rect2(mid + Vector2(-w * 0.07, h * 0.76), Vector2(w * 0.14, h * 0.035)), accent, h * 0.055)
	_say(_reading("clock", d), mid + Vector2(0, h * 0.1), h * 0.06, Color(0.8, 0.82, 0.85), "center", false)
	var lamps := [["handbrake", "#ff3b1f"], ["abs", "#ffb000"], ["tc", "#ffb000"]]
	for i in lamps.size():
		_lamp({"what": lamps[i][0], "at": [mid.x + w * (i - 1) * 0.045, r.position.y + h * 0.94], "size": h * 0.055, "color": lamps[i][1]})
	if live.warning("shift"):
		_lamp({"what": "shift", "at": [mid.x, r.position.y + h * 0.2], "w": w * 0.14, "size": h * 0.05})


## One round dial: a 240-degree scale (from bottom left round to bottom right), its numbers
## every `step` (major ticks), red past `red`, the needle at share u (0..1).
func _dial(c: Vector2, rr: float, u: float, top: float, step: float, unit: String, accent: Color, needle: Color, red := -1.0) -> void:
	var a0 := deg_to_rad(150.0)
	var sweep := deg_to_rad(240.0)
	var line := maxf(rr * 0.02, 1.0)
	draw_arc(c, rr, a0, a0 + sweep, 64, Color(accent.r, accent.g, accent.b, 0.35), line, true)
	if red > 0.0:
		draw_arc(c, rr * 0.97, a0 + sweep * red / top, a0 + sweep, 24, Color("#ff2a12"), line * 3.0, true)
	var n := int(round(top / step))
	for k in n + 1:
		var a := a0 + sweep * float(k) / float(n)
		var dir := Vector2(cos(a), sin(a))
		draw_line(c + dir * rr * 0.86, c + dir * rr, Color(0.9, 0.92, 0.95), line * 1.6, true)
		if n <= 14 or k % 2 == 0:
			_say("%d" % roundi(k * step), c + dir * rr * 0.72, rr * 0.13, Color(0.86, 0.88, 0.92), "center", false)
	for k in n * 2:
		var a := a0 + sweep * (float(k) + 0.5) / float(n * 2)
		var dir := Vector2(cos(a), sin(a))
		draw_line(c + dir * rr * 0.92, c + dir * rr, Color(0.7, 0.72, 0.76), line, true)
	var an := a0 + sweep * clampf(u, 0.0, 1.0)
	var dn := Vector2(cos(an), sin(an))
	draw_line(c - dn * rr * 0.12, c + dn * rr * 0.93, needle, rr * 0.035, true)
	draw_circle(c, rr * 0.07, Color(0.12, 0.13, 0.15))
	_say(unit, c + Vector2(0, rr * 0.45), rr * 0.1, Color(0.65, 0.68, 0.72), "center", false)


# ── the centre screen ─────────────────────────────────────────────────────

func _nav() -> void:
	var d: Dictionary = live.data
	var accent := Color(str(cfg.get("accent", "#c8102e")))
	var r := view
	draw_rect(r, Color(0.035, 0.038, 0.045))
	var tall := tall()
	var bar := minf(r.size.y * 0.085, r.size.x * 0.06)
	# the status bar: the radio, the clock
	draw_rect(Rect2(r.position, Vector2(r.size.x, bar)), Color(0.0, 0.0, 0.0))
	var right := "%s    %s" % [str(cfg.get("radio", "SHOTGUN FM 98.6")), _reading("clock", d)]
	_say(right, Vector2(r.end.x - 4.0 * r.size.x / 344.0, r.position.y + bar * 0.45), bar * 0.8, Color(0.85, 0.86, 0.88), "right", false, r.size.x * 0.94)
	var lit := 0 if page == 0 else 1
	var pad := r.size.x * 0.009
	if tall:
		var tab_h := r.size.x * 0.1
		var tab_w := r.size.x / NAV_TABS.size()
		for i in NAV_TABS.size():
			var box := Rect2(r.position.x + i * tab_w + pad, r.position.y + bar + pad, tab_w - pad * 2.0, tab_h - pad * 2.0)
			draw_rect(box, Color(accent.r, accent.g, accent.b, 0.55) if i == lit else Color(1, 1, 1, 0.045))
			if i == lit:
				draw_rect(Rect2(Vector2(box.position.x, box.end.y - pad * 0.8), Vector2(box.size.x, pad * 0.8)), accent)
			_say(NAV_TABS[i], box.get_center(), tab_h * 0.4, Color(0.92, 0.93, 0.95) if i == lit else Color(0.62, 0.64, 0.68), "center", false, box.size.x * 0.9)
		var under := Rect2(r.position.x + pad, r.position.y + bar + tab_h + pad, r.size.x - pad * 2.0, r.size.y - bar - tab_h - pad * 2.0)
		if page == 0:
			_map(under, d, accent)
		else:                                           # (the readings in a landscape box, at the top)
			_info(Rect2(under.position, Vector2(under.size.x, minf(under.size.y, under.size.x / 1.6))), d, accent)
		return
	# the menu down the left
	var menu_w := r.size.x * 0.34
	var item_h := (r.size.y - bar) / NAV_ITEMS.size()
	for i in NAV_ITEMS.size():
		var y := r.position.y + bar + i * item_h
		var box := Rect2(r.position.x + pad, y + pad * 0.3, menu_w - pad * 2.0, item_h - pad * 0.6)
		if i == lit:
			draw_rect(box, Color(accent.r, accent.g, accent.b, 0.55))
			draw_rect(Rect2(box.position, Vector2(pad * 0.6, box.size.y)), accent)
		else:
			draw_rect(box, Color(1, 1, 1, 0.045))
		_say(NAV_ITEMS[i], Vector2(box.position.x + pad * 2.0, y + item_h * 0.5), item_h * 0.44,
			Color(0.92, 0.93, 0.95) if i == lit else Color(0.62, 0.64, 0.68), "left", false, box.size.x - pad * 3.0)
	var area := Rect2(r.position.x + menu_w + pad * 0.6, r.position.y + bar + pad * 0.6, r.size.x - menu_w - pad * 1.5, r.size.y - bar - pad * 1.2)
	if page == 0:
		_map(area, d, accent)
	else:
		_info(area, d, accent)


## The road round the car, heading up, the car in the middle.
func _map(area: Rect2, d: Dictionary, accent: Color) -> void:
	draw_rect(area, Color(0.07, 0.09, 0.11))
	var st = live.cockpit.map_board.st if live.cockpit.map_board else null
	if st == null:
		return
	var car_s: float = d.get("car_s", 0.0)
	var cpos: Vector3 = live.car.global_position
	var fwd: Vector3 = -live.car.global_transform.basis.z
	var yaw := atan2(fwd.x, -fwd.z)
	var span := 260.0                                   # m from the car to the area's top
	var k: float = area.size.y * 0.72 / span
	var centre := area.position + Vector2(area.size.x * 0.5, area.size.y * 0.72)
	var rot := Transform2D(-yaw, Vector2.ZERO)
	var pts := PackedVector2Array()
	var loop: bool = st.has_method("wrap_s")
	var s: float = car_s - span * 0.5
	while s < car_s + span * 1.2:
		var w: Vector3 = st.world_at(st.wrap_s(s) if loop else clampf(s, 0.0, st.length), 0.0)
		var rel := rot * Vector2(w.x - cpos.x, w.z - cpos.z)
		var p := centre + rel * k
		if area.grow(area.size.x * 0.05).has_point(p):
			pts.append(p)
		s += 6.0
	var unit := minf(area.size.x, area.size.y) / 100.0
	if pts.size() > 1:
		draw_polyline(pts, Color(0.3, 0.33, 0.37), unit * 6.0, true)
		draw_polyline(pts, Color(0.86, 0.88, 0.9), unit * 3.8, true)
	# the car: an arrow, pointing up
	var a := centre + Vector2(0, -unit * 6.0)
	draw_colored_polygon(PackedVector2Array([a, centre + Vector2(unit * 4.2, unit * 4.5), centre + Vector2(0, unit * 2.2), centre + Vector2(-unit * 4.2, unit * 4.5)]), accent)
	# the distance to go (a loop has none: the distance driven)
	var togo: float = maxf(float(st.finish_s) - car_s, 0.0) if not loop else -1.0
	var txt := ("%.1f km to the finish" % (togo / 1000.0)) if togo >= 0.0 else ("%.1f km driven" % (maxf(car_s - st.START_S, 0.0) / 1000.0))
	draw_rect(Rect2(area.position, Vector2(area.size.x, area.size.y * 0.16)), Color(0, 0, 0, 0.55))
	_say(txt, area.position + Vector2(unit * 4.0, area.size.y * 0.08), area.size.y * 0.1, Color(0.95, 0.95, 0.96), "left", false, area.size.x - unit * 8.0)
	# what's playing: the station, the song, how far into it
	var strip := Rect2(area.position + Vector2(0, area.size.y * 0.84), Vector2(area.size.x, area.size.y * 0.16))
	draw_rect(strip, Color(0, 0, 0, 0.62))
	var tt: float = float(d.get("time", 0.0)) + 47.0
	var songs: Array = cfg.get("songs", ["NIGHT DRIVE", "GRAVEL & GOLD", "SIDEWAYS", "LAST STAGE"])
	var song: String = str(songs[int(tt / 200.0) % songs.size()])
	_say("♪  %s  ·  %s" % [song, str(cfg.get("radio", "SHOTGUN FM 98.6"))], strip.position + Vector2(unit * 4.0, strip.size.y * 0.4), strip.size.y * 0.42, Color(0.92, 0.93, 0.95), "left", false, strip.size.x - unit * 8.0)
	var prog := Rect2(strip.position + Vector2(unit * 4.0, strip.size.y * 0.8), Vector2(strip.size.x - unit * 8.0, strip.size.y * 0.07))
	draw_rect(prog, Color(1, 1, 1, 0.15))
	draw_rect(Rect2(prog.position, Vector2(prog.size.x * fmod(tt, 200.0) / 200.0, prog.size.y)), accent)


## Speed, gear, revs, a g-meter, the stage clock.
func _info(area: Rect2, d: Dictionary, accent: Color) -> void:
	draw_rect(area, Color(0.05, 0.055, 0.065))
	var h := area.size.y
	var x0 := area.position.x + h * 0.05
	var y0 := area.position.y
	_say(_reading("speed", d), Vector2(x0, y0 + h * 0.27), h * 0.36, Color(1, 1, 1), "left")
	_say("km/h", Vector2(x0, y0 + h * 0.52), h * 0.1, Color(0.7, 0.72, 0.75), "left", false)
	_say(_gear(d, "bmw"), Vector2(x0 + area.size.x * 0.32, y0 + h * 0.28), h * 0.3, accent.lightened(0.25), "left")
	# the revs: a bar
	var bar := Rect2(x0, y0 + h * 0.64, area.size.x * 0.56, h * 0.07)
	draw_rect(bar, Color(1, 1, 1, 0.1))
	var u := clampf(float(d.get("rpm01", 0.0)), 0.0, 1.0)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * u, bar.size.y)), Color("#ff3b1f") if u > 0.9 else Color(0.92, 0.93, 0.95))
	_say("%d rpm" % (roundi(float(d.get("rpm", 0.0)) / 50.0) * 50), Vector2(x0, y0 + h * 0.8), h * 0.1, Color(0.7, 0.72, 0.75), "left", false)
	_say(("CHARGE " if d.get("electric", false) else "FUEL ") + _reading("fuel", d) + ("   " + _reading("range", d) if d.get("electric", false) else ""),
		Vector2(x0 + area.size.x * 0.3, y0 + h * 0.8), h * 0.1, Color(0.7, 0.72, 0.75), "left", false)
	_say("STAGE  " + _reading("time", d), Vector2(x0, y0 + h * 0.93), h * 0.1, Color(0.92, 0.93, 0.95), "left", false)
	# the g-meter
	var c := Vector2(area.end.x - h * 0.4, y0 + h * 0.5)
	var rr := h * 0.34
	var line := maxf(h * 0.008, 1.0)
	draw_arc(c, rr, 0.0, TAU, 40, Color(1, 1, 1, 0.25), line, true)
	draw_arc(c, rr * 0.5, 0.0, TAU, 32, Color(1, 1, 1, 0.15), line, true)
	draw_line(c - Vector2(rr, 0), c + Vector2(rr, 0), Color(1, 1, 1, 0.12), line)
	draw_line(c - Vector2(0, rr), c + Vector2(0, rr), Color(1, 1, 1, 0.12), line)
	var g: Vector2 = d.get("g", Vector2.ZERO)
	draw_circle(c + (g / 1.5).limit_length(1.0) * rr, h * 0.035, accent.lightened(0.2))
	_say("%.1f g" % g.length(), c + Vector2(-rr, rr + h * 0.08), h * 0.09, Color(0.7, 0.72, 0.75), "left", false)


# ── one dial on a board ───────────────────────────────────────────────────

## How far round its scale a dial's needle is now (0..1; the tests read it).
func share() -> float:
	var d: Dictionary = live.data
	if str(cfg.get("what", "kmh")) == "rpm":
		return clampf(_value("rpm", d) / float(cfg.get("max", d.get("limiter", 7000.0))), 0.0, 1.0)
	return clampf(absf(_value("kmh", d)) / float(cfg.get("max", 260.0)), 0.0, 1.0)


func _one_dial() -> void:
	var d: Dictionary = live.data
	var r := view
	var accent := Color(str(cfg.get("accent", "#e8eef6")))
	var needle := Color(str(cfg.get("needle", "#ff4a1c")))
	draw_rect(r, Color(str(cfg.get("face", "#0b0c10"))))
	var c := r.position + r.size * 0.5
	var rr := minf(r.size.x, r.size.y) * 0.46
	var what := str(cfg.get("what", "kmh"))
	if what == "rpm":
		var lim: float = float(cfg.get("max", d.get("limiter", 7000.0)))
		_dial(c, rr, clampf(_value("rpm", d) / lim, 0.0, 1.0), lim / 1000.0, float(cfg.get("step", 1.0)), str(cfg.get("unit", "x1000/min")),
			accent, needle, float(cfg.get("red", lim * 0.88)) / 1000.0)
	else:
		var top := float(cfg.get("max", 260.0))
		_dial(c, rr, absf(_value("kmh", d)) / top, top, float(cfg.get("step", 20.0)), str(cfg.get("unit", "km/h")), accent, needle)
	draw_arc(c, rr * 1.06, 0.0, TAU, 64, Color(0.55, 0.57, 0.6), rr * 0.035, true)     # (the chrome ring)


# ── a segment display ─────────────────────────────────────────────────────

func _lcd() -> void:
	var r := view
	draw_rect(r, Color(str(cfg.get("bg_color", "#0a0202"))))
	var col := Color(str(cfg.get("color", "#ff2a12")))
	var px := r.size.y * float(cfg.get("size", 0.72))
	var at := r.position + r.size * 0.5
	var s := _reading(str(cfg.get("what", "clock")), live.data, cfg)
	var ghost := ""
	for ch in s:
		ghost += "8" if ch >= "0" and ch <= "9" else ch
	_say(ghost.lpad(s.length()), at, px, Color(col.r, col.g, col.b, 0.07))
	_say(s, at, px, col)
