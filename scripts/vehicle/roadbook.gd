extends Node3D
## The co-driver's ROADBOOK ROLL: a wooden board with two brass rollers and a
## strip of paper that scrolls as the car drives (like a Dakar roadbook), with
## a little stopwatch clipped on top. Ours, not the reference's orange tablet.
##
## Each note is a row: the distance since the last note (small, left), a hand
## drawn "tulip" arrow of the corner (middle), and the call (right): grade +
## direction, then modifiers (TIGHTENS 2, DON'T CUT, LONG, CAUTION in red).
## "INTO" / "AND" sit between rows that run together. The current note sits
## just under the red line; the ones below are coming.
##
## The paper is drawn into a SubViewport (2D) shown on a quad: holder-local
## units are metres, the paper faces +Z (toward the co-driver's eyes).

const Notes = preload("res://scripts/stage/pacenotes.gd")
const PAPER_PX := Vector2i(300, 420)
const PAPER_M := Vector2(0.21, 0.294)
const ROW_H := 92.0

var notes: Array = []
var stage_len := 1.0
var car_s := 0.0                  # set by the game every frame
var clock_text := "0:00.0"        # the stopwatch
var clock_red := false            # countdown in red
var _vp: SubViewport
var _paper: Control
var _scroll := 0.0                # rows scrolled (smooth)
var _font: Font


func setup(stage_notes: Array, length: float) -> void:
	notes = stage_notes
	stage_len = length
	_font = load("res://assets/fonts/Oswald-Bold.woff2")
	_board()
	_vp = SubViewport.new()
	_vp.size = PAPER_PX
	_vp.transparent_bg = false
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	_paper = Control.new()
	_paper.size = Vector2(PAPER_PX)
	_paper.draw.connect(_draw_paper)
	_vp.add_child(_paper)
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = PAPER_M
	q.mesh = qm
	var m := StandardMaterial3D.new()
	m.albedo_texture = _vp.get_texture()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	q.material_override = m
	q.position = Vector3(0, -0.01, 0.012)
	add_child(q)


func _board() -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.52, 0.34, 0.18)
	wood.roughness = 0.8
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.8, 0.64, 0.25)
	brass.metallic = 0.6
	brass.roughness = 0.35
	var b := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.27, 0.38, 0.02)
	b.mesh = bm
	b.material_override = wood
	add_child(b)
	for y in [0.165, -0.185]:
		var r := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.018
		cm.bottom_radius = 0.018
		cm.height = 0.25
		cm.radial_segments = 8
		cm.rings = 1
		r.mesh = cm
		r.material_override = brass
		r.rotation.z = PI / 2.0
		r.position = Vector3(0, y, 0.02)
		add_child(r)
	# the stopwatch on top
	var w := MeshInstance3D.new()
	var wm := BoxMesh.new()
	wm.size = Vector3(0.09, 0.04, 0.025)
	w.mesh = wm
	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = Color(0.12, 0.12, 0.13)
	w.material_override = wmat
	w.position = Vector3(0.0, 0.205, 0.02)
	add_child(w)


func _process(dt: float) -> void:
	if notes.is_empty():
		return
	var cur := current_index()
	# progress between the previous note's end and the current note's start: scroll smoothly
	var prev_end: float = notes[cur - 1].s_end if cur > 0 else 0.0
	var frac := clampf((car_s - prev_end) / maxf(notes[cur].s - prev_end, 1.0), 0.0, 1.0)
	var target := float(cur) - 1.0 + frac * 0.6
	_scroll = lerpf(_scroll, target, clampf(dt * 6.0, 0.0, 1.0))
	_paper.queue_redraw()


## The note you're on or coming to next (the first that hasn't ended yet).
func current_index() -> int:
	for i in notes.size():
		if notes[i].s_end > car_s:
			return i
	return notes.size() - 1


func _draw_paper() -> void:
	var w := float(PAPER_PX.x)
	var h := float(PAPER_PX.y)
	_paper.draw_rect(Rect2(0, 0, w, h), Color(0.96, 0.93, 0.84))
	var top := 62.0                             # under the stopwatch band
	var cur := current_index()
	for i in range(maxi(0, int(_scroll) - 1), mini(notes.size(), int(_scroll) + 6)):
		var y := top + (i - _scroll) * ROW_H
		if y < top - ROW_H or y > h:
			continue
		_draw_row(notes[i], y, i == cur)
	# the "now" line
	var now_y := top + (cur - _scroll) * ROW_H - 4.0
	_paper.draw_line(Vector2(0, now_y), Vector2(w, now_y), Color(0.85, 0.1, 0.1, 0.8), 3.0)
	# stopwatch band
	_paper.draw_rect(Rect2(0, 0, w, 54), Color(0.1, 0.1, 0.11))
	_text(clock_text, Vector2(w * 0.5, 40), 36, Color(1.0, 0.25, 0.2) if clock_red else Color(0.95, 0.9, 0.5), true)
	# progress down the side
	var p := clampf(car_s / maxf(stage_len, 1.0), 0.0, 1.0)
	_paper.draw_rect(Rect2(w - 7, 58, 4, h - 64), Color(0.8, 0.76, 0.66))
	_paper.draw_rect(Rect2(w - 7, 58, 4, (h - 64) * p), Color(0.85, 0.1, 0.1))


func _draw_row(n: Dictionary, y: float, is_current: bool) -> void:
	var ink := Color(0.12, 0.1, 0.09)
	if is_current:
		_paper.draw_rect(Rect2(4, y, PAPER_PX.x - 14, ROW_H - 6), Color(1.0, 0.92, 0.55, 0.55))
	_paper.draw_line(Vector2(6, y + ROW_H - 4), Vector2(PAPER_PX.x - 12, y + ROW_H - 4), Color(0.75, 0.7, 0.6), 1.0)
	# the tulip
	_tulip(n, Vector2(62, y + ROW_H * 0.5), ink)
	# the call
	var main := ""
	var sub: Array = []
	match n.kind:
		"corner":
			main = (n.shape.to_upper() if n.shape != "" else str(n.grade)) + (" L" if n.dir < 0 else " R")
			for m in n.mods:
				match m:
					"tightens":
						sub.append("TIGHTENS %d" % n.grade2 if n.grade2 > 0 else "TIGHTENS")
					"dont-cut":
						sub.append("DON'T CUT")
					_:
						sub.append(String(m).to_upper())
		"crest":
			main = "CREST"
		"jump":
			main = "JUMP!"
		"water":
			main = "SPLASH"
		"finish":
			main = "FINISH"
	if n.get("caution", false):
		_text("CAUTION", Vector2(122, y + 20), 17, Color(0.85, 0.1, 0.1))
	_text(main, Vector2(122, y + 52), 38, ink)
	if not sub.is_empty():
		_text(" ".join(sub), Vector2(122, y + 76), 16, Color(0.45, 0.1, 0.08))
	# what's after it: INTO / AND / a distance
	var after := ""
	if n.link != "":
		after = String(n.link).to_upper()
	elif n.dist > 0:
		after = str(n.dist)
	if after != "":
		_text(after, Vector2(PAPER_PX.x - 52, y + ROW_H - 10), 18, Color(0.15, 0.3, 0.6), true)


## A hand-drawn arrow: the road comes up from the bottom and turns by the
## corner's angle (sharper for slower grades); crests are humps, water waves.
func _tulip(n: Dictionary, c: Vector2, ink: Color) -> void:
	match n.kind:
		"crest", "jump":
			var pts := PackedVector2Array()
			for k in 9:
				var u := k / 8.0
				pts.append(c + Vector2(-34 + u * 68, 14 - sin(u * PI) * (26 if n.kind == "jump" else 18)))
			_paper.draw_polyline(pts, ink, 4.0)
			if n.kind == "jump":
				_paper.draw_line(c + Vector2(-6, -24), c + Vector2(6, -34), ink, 3.0)
			return
		"water":
			for row in 2:
				var pts := PackedVector2Array()
				for k in 13:
					pts.append(c + Vector2(-34 + k * 5.7, -6 + row * 14 + sin(k * 1.4) * 4.0))
				_paper.draw_polyline(pts, Color(0.15, 0.35, 0.7), 3.0)
			return
		"finish":
			for i in 4:
				for j in 3:
					if (i + j) % 2 == 0:
						_paper.draw_rect(Rect2(c + Vector2(-24 + i * 12, -18 + j * 12), Vector2(12, 12)), ink)
			_paper.draw_rect(Rect2(c + Vector2(-24, -18), Vector2(48, 36)), ink, false, 2.0)
			return
	# corner: a stem, then an arc turning by the angle
	var turn_deg: float = 180.0 if n.shape == "hairpin" else (90.0 if n.shape == "square" else 25.0 + (6 - n.grade) * 22.0)
	var dir := float(n.dir)
	var pts := PackedVector2Array([c + Vector2(0, 36), c + Vector2(0, 8)])
	var heading := -PI / 2.0                    # pointing up the page
	var p := c + Vector2(0, 8)
	var steps := 8
	var seg := 34.0 / steps * (1.4 if turn_deg > 120.0 else 1.0)
	for k in steps:
		heading += deg_to_rad(turn_deg / steps) * dir
		p += Vector2(cos(heading), sin(heading)) * seg
		pts.append(p)
	_paper.draw_polyline(pts, ink, 5.0)
	# arrow head
	var hd := Vector2(cos(heading), sin(heading))
	var sd := Vector2(-hd.y, hd.x)
	_paper.draw_colored_polygon(PackedVector2Array([p + hd * 10, p - hd * 4 + sd * 8, p - hd * 4 - sd * 8]), ink)
	_paper.draw_circle(c + Vector2(0, 36), 4.0, ink)
	if "dont-cut" in n.mods:
		var inside := c + Vector2(dir * 18.0, -4)
		_paper.draw_circle(inside, 6.0, Color(0.5, 0.48, 0.44))


func _text(t: String, at: Vector2, size: int, col: Color, centered := false) -> void:
	var x := at.x
	if centered:
		x -= _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x * 0.5
	_paper.draw_string(_font, Vector2(x, at.y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
