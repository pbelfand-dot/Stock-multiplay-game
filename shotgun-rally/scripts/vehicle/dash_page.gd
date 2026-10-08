extends Control
## One live screen in a car's own interior (dash_live.gd shows it on the screen's
## part of the surface):
##   * "cluster" over the car's own painted cluster ("bg", the default when the
##     surface has a texture): drawn in the texture's pixels; what changes is drawn
##     over the picture from the spec's "layout" (data/dash/<model>.json): "cover"
##     rectangles hide the painted readings, then "text" (the speed, the gear, the
##     clock, the stage time), "arc" (the revs or the speed filling along a band:
##     the points down its middle), "gdot" (the g-meter's dot), "lamp" (warning lamps)
##   * "cluster" on a blank screen ("bg": false): a digital cluster of its own, drawn
##     on a canvas the screen's shape ("aspect": its width / height as you see it):
##     the revs in a band across the top (the shift lamps above), the speed, the
##     gear, the warning lamps along the bottom, in the car's accent colour
##   * "nav": the centre screen: a menu down the left (the page you're on lit in the
##     accent colour) and the page: NAVIGATION, the road around you heading up, your
##     car in the middle, the distance to go; DRIVING INFORMATION, the speed, gear,
##     revs, a g-meter and the stage clock. M (the d-pad right) flips the page.
##   * "lcd": a small segment display (an old car's clock): one reading ("what": the
##     clock by default) in its colour, the unlit segments ("88:88") faint behind it

var live                            # DashLive (its data, warning())
var cfg := {}
var base: Texture2D                 # the texture the screen is part of
var src := Rect2()                  # the part of it the screen covers (its pixels)
var view := Rect2()                 # what's drawn in: the texture's pixels, or the canvas
var page := 0
var _font: Font
var _font_b: Font

const NAV_ITEMS := ["Navigation", "Driving information", "Vehicle status", "Settings"]
const WIDTH := 900.0                # the screen's picture, px across


func setup(the_live, the_cfg: Dictionary, tex: Texture2D, region: Rect2) -> void:
	live = the_live
	cfg = the_cfg
	base = tex
	src = region
	if _painted():
		view = region
	else:
		var aspect := float(cfg.get("aspect", region.size.x / maxf(region.size.y, 1e-4)))
		var canvas: Array = cfg.get("canvas", [1000.0, 1000.0 / aspect])
		view = Rect2(0, 0, float(canvas[0]), float(canvas[1]))
	var k := float(cfg.get("px", WIDTH)) / view.size.x
	size = view.size * k
	_font = load("res://assets/fonts/Oswald-Medium.woff2")
	_font_b = load("res://assets/fonts/Oswald-Bold.woff2")
	mouse_filter = Control.MOUSE_FILTER_IGNORE


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


# ── a painted cluster, made live ──────────────────────────────────────────

func _cluster() -> void:
	var d: Dictionary = live.data
	var lay: Dictionary = cfg.get("layout", {})
	draw_texture_rect_region(base, src, src)
	for c in lay.get("cover", []):
		var col := Color(str(c[4])) if c.size() > 4 else Color(0.0, 0.0, 0.0)
		draw_rect(Rect2(c[0], c[1], float(c[2]) - float(c[0]), float(c[3]) - float(c[1])), col)
	for a in lay.get("arc", []):
		_arc(a, d)
	for t in lay.get("text", []):
		_text(t, d)
	if lay.has("gdot"):
		var g: Dictionary = lay.gdot
		var gv: Vector2 = d.get("g", Vector2.ZERO)
		var p := Vector2(g.c[0], g.c[1]) + (gv / float(g.get("g", 1.2))).limit_length(1.0) * float(g.r)
		draw_circle(p, float(g.get("dot", 2.2)), Color(str(g.get("color", "#ff2a1a"))))
	for l in lay.get("lamp", []):
		_lamp(l)


func _value(what: String, d: Dictionary) -> float:
	return float(d.get(what, 0.0))


## A band filling up with the value: thick segments along the points.
func _arc(a: Dictionary, d: Dictionary) -> void:
	var pts: Array = a.pts
	var u := clampf(absf(_value(str(a.what), d)) / maxf(float(a.get("max", 1.0)), 1e-3), 0.0, 1.0)
	var lens: Array = [0.0]
	for i in range(1, pts.size()):
		lens.append(lens[-1] + Vector2(pts[i][0], pts[i][1]).distance_to(Vector2(pts[i - 1][0], pts[i - 1][1])))
	var total: float = lens[-1]
	var want := u * total
	var w := float(a.get("w", 4.0))
	var lo := Color(str(a.get("color", "#f2f2f2")))
	var hi := Color(str(a.get("hot", "#ff3b1f")))
	var hot_from := float(a.get("hot_from", 0.85))
	for i in range(1, pts.size()):
		if lens[i - 1] >= want:
			break
		var p0 := Vector2(pts[i - 1][0], pts[i - 1][1])
		var p1 := Vector2(pts[i][0], pts[i][1])
		var seg: float = lens[i] - lens[i - 1]
		var f := clampf((want - lens[i - 1]) / maxf(seg, 1e-3), 0.0, 1.0)
		var mid: float = (lens[i - 1] + seg * f * 0.5) / total
		draw_line(p0, p0.lerp(p1, f), hi if mid > hot_from else lo, w, true)


func _text(t: Dictionary, d: Dictionary) -> void:
	var s := _reading(str(t.what), d, t)
	var px := float(t.get("size", 10.0))
	_say(s, Vector2(t.at[0], t.at[1]), px, Color(str(t.get("color", "#ffffff"))), str(t.get("align", "center")), t.get("bold", true))


func _reading(what: String, d: Dictionary, t := {}) -> String:
	match what:
		"speed":
			return "%d" % roundi(absf(_value("kmh", d)))
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
	return str(t.get("text", ""))


## Text with its middle (or left / right end) at `at`, its letters' middle on at.y.
func _say(s: String, at: Vector2, px: float, col: Color, align := "center", bold := true) -> void:
	var f: Font = _font_b if bold else _font
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(int(px), 1)).x
	match align:
		"center":
			at.x -= w * 0.5
		"right":
			at.x -= w
	draw_string(f, at + Vector2(0, px * 0.36), s, HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(int(px), 1), col)


func _gear(d: Dictionary, style: String) -> String:
	var g := int(d.get("gear", 1))
	if str(d.get("state", "")) in ["grid", ""] and absf(float(d.get("kmh", 0.0))) < 1.0:
		return "P" if style == "bmw" else "N"
	if g < 0:
		return "R"
	if g == 0:
		return "N"
	if style == "bmw":
		return ("D%d" if d.get("auto", false) else "M%d") % g
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


# ── the centre screen ─────────────────────────────────────────────────────

func _nav() -> void:
	var d: Dictionary = live.data
	var accent := Color(str(cfg.get("accent", "#c8102e")))
	var r := view
	draw_rect(r, Color(0.035, 0.038, 0.045))
	var bar := r.size.y * 0.085
	# the status bar: the radio, the clock
	draw_rect(Rect2(r.position, Vector2(r.size.x, bar)), Color(0.0, 0.0, 0.0))
	var right := "%s    %s" % [str(cfg.get("radio", "SHOTGUN FM 98.6")), _reading("clock", d)]
	_say(right, Vector2(r.end.x - 4.0 * r.size.x / 344.0, r.position.y + bar * 0.45), bar * 0.8, Color(0.85, 0.86, 0.88), "right", false)
	# the menu down the left
	var menu_w := r.size.x * 0.34
	var item_h := (r.size.y - bar) / NAV_ITEMS.size()
	var lit := 0 if page == 0 else 1
	var pad := r.size.x * 0.009
	for i in NAV_ITEMS.size():
		var y := r.position.y + bar + i * item_h
		var box := Rect2(r.position.x + pad, y + pad * 0.3, menu_w - pad * 2.0, item_h - pad * 0.6)
		if i == lit:
			draw_rect(box, Color(accent.r, accent.g, accent.b, 0.55))
			draw_rect(Rect2(box.position, Vector2(pad * 0.6, box.size.y)), accent)
		else:
			draw_rect(box, Color(1, 1, 1, 0.045))
		_say(NAV_ITEMS[i], Vector2(box.position.x + pad * 2.0, y + item_h * 0.5), item_h * 0.44,
			Color(0.92, 0.93, 0.95) if i == lit else Color(0.62, 0.64, 0.68), "left", false)
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
	var unit := area.size.y / 100.0
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
	_say(txt, area.position + Vector2(unit * 4.0, area.size.y * 0.08), area.size.y * 0.1, Color(0.95, 0.95, 0.96), "left", false)


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
