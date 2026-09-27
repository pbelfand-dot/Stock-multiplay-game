extends Node
## Renders the "LIVE" news broadcast onto the office TV via a SubViewport:
## podium + flags for TRAMP, a streamer cam for TJZ / KIMCHEE, etc.

const UI = preload("res://scripts/ui/ui_theme.gd")

var vp: SubViewport
var canvas: Control
var match_node
var ev := {}
var t := 0.0


func attach(screen: MeshInstance3D, m) -> void:
	match_node = m
	vp = SubViewport.new()
	vp.size = Vector2i(840, 460)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = false
	add_child(vp)
	canvas = Control.new()
	canvas.size = Vector2(840, 460)
	canvas.draw.connect(_draw_tv)
	vp.add_child(canvas)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = vp.get_texture()
	screen.material_override = mat
	m.news.connect(func(e): ev = e)


func _process(delta: float) -> void:
	t += delta
	if canvas:
		canvas.queue_redraw()


func _draw_tv() -> void:
	var c := canvas
	var W := 840.0
	var H := 460.0
	var f := UI.bold()
	var role: String = ev.get("role", "")
	match role:
		"PRESIDENT":
			c.draw_rect(Rect2(0, 0, W, H), Color(0.72, 0.74, 0.8))
			for i in 7:
				c.draw_rect(Rect2(0, i * 50, W, 22), Color(0.66, 0.68, 0.74))
			c.draw_rect(Rect2(90, 110, 90, 130), Color(0.2, 0.6, 0.65))
			c.draw_rect(Rect2(660, 110, 90, 130), Color(0.2, 0.6, 0.65))
			_flag(c, Vector2(250, 120))
			_flag(c, Vector2(560, 120))
			_person(c, Vector2(W / 2, 250), Color(0.12, 0.14, 0.25), Color(0.98, 0.75, 0.2), true)
			c.draw_rect(Rect2(W / 2 - 120, 300, 240, 160), Color(0.1, 0.2, 0.55))
			c.draw_circle(Vector2(W / 2, 360), 40, Color(0.95, 0.8, 0.3))
		"STREAMER":
			c.draw_rect(Rect2(0, 0, W, H), Color(0.12, 0.05, 0.2))
			for i in 12:
				c.draw_rect(Rect2(i * 70, 0, 35, H), Color(0.5 + 0.3 * sin(t * 2 + i), 0.1, 0.8, 0.25))
			_person(c, Vector2(W / 2, 260), Color(0.1, 0.1, 0.1), Color(0.15, 0.1, 0.08), false)
			c.draw_rect(Rect2(W / 2 - 60, 180, 120, 20), Color(0.05, 0.05, 0.05))  # headset
			c.draw_rect(Rect2(20, 20, 150, 40), Color(0.55, 0.2, 0.95))
			c.draw_string(f, Vector2(32, 52), "KWIK LIVE", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color.WHITE)
			c.draw_string(f, Vector2(W - 220, 52), "%dK watching" % (40 + int(t) % 60), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color.WHITE)
		"FED":
			c.draw_rect(Rect2(0, 0, W, H), Color(0.3, 0.33, 0.28))
			for i in 6:
				c.draw_rect(Rect2(60 + i * 130, 60, 40, 300), Color(0.85, 0.83, 0.75))
			_person(c, Vector2(W / 2, 260), Color(0.1, 0.1, 0.12), Color(0.85, 0.85, 0.85), false)
		"TV":
			c.draw_rect(Rect2(0, 0, W, H), Color(0.05, 0.2, 0.35))
			c.draw_string(f, Vector2(40, 90), "MAD MONIES", HORIZONTAL_ALIGNMENT_LEFT, -1, 64, Color(1, 0.85, 0.1))
			_person(c, Vector2(W / 2 + 120, 260), Color(0.95, 0.95, 0.95), Color(0.85, 0.7, 0.6), false)
		"BREAKING":
			c.draw_rect(Rect2(0, 0, W, H), Color(0.5, 0.05, 0.05))
			c.draw_string(f, Vector2(60, 220), "BREAKING", HORIZONTAL_ALIGNMENT_LEFT, -1, 150, Color(1, 1, 1, 0.9))
			c.draw_string(f, Vector2(60, 310), "NEWS", HORIZONTAL_ALIGNMENT_LEFT, -1, 110, Color(1, 0.85, 0.2))
		_:
			c.draw_rect(Rect2(0, 0, W, H), Color(0.05, 0.08, 0.15))
			c.draw_string(f, Vector2(150, 230), "BAGHOLDER NEWS NETWORK", HORIZONTAL_ALIGNMENT_LEFT, -1, 54, UI.GOLD)
			c.draw_string(f, Vector2(250, 290), "markets open soon", HORIZONTAL_ALIGNMENT_LEFT, -1, 36, UI.DIM)
	# chyron
	c.draw_rect(Rect2(0, H - 80, W, 80), Color(0.03, 0.03, 0.04))
	c.draw_rect(Rect2(0, H - 80, 120, 80), Color(0.85, 0.05, 0.08))
	c.draw_string(f, Vector2(14, H - 24), "LIVE", HORIZONTAL_ALIGNMENT_LEFT, -1, 50, Color.WHITE)
	var text: String = ev.get("headline", "STAY TUNED")
	var fs := 34
	while fs > 16 and f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > W - 140:
		fs -= 2
	c.draw_string(f, Vector2(132, H - 28), text, HORIZONTAL_ALIGNMENT_LEFT, W - 140, fs, Color.WHITE)


func _flag(c: Control, p: Vector2) -> void:
	c.draw_line(p, p + Vector2(0, 200), Color(0.3, 0.25, 0.2), 4)
	for i in 7:
		c.draw_rect(Rect2(p + Vector2(4, i * 12), Vector2(60, 6)), Color(0.8, 0.1, 0.15))
	c.draw_rect(Rect2(p + Vector2(4, 0), Vector2(28, 40)), Color(0.15, 0.2, 0.5))


func _person(c: Control, p: Vector2, suit: Color, hair: Color, big_hair: bool) -> void:
	c.draw_rect(Rect2(p.x - 110, p.y, 220, 220), suit)
	c.draw_rect(Rect2(p.x - 22, p.y, 44, 90), Color(0.95, 0.95, 0.95))
	c.draw_rect(Rect2(p.x - 8, p.y + 4, 16, 80), Color(0.8, 0.1, 0.1))
	c.draw_circle(p + Vector2(0, -60), 70, Color(0.97, 0.78, 0.6))
	if big_hair:
		c.draw_colored_polygon(PackedVector2Array([p + Vector2(-80, -80), p + Vector2(-40, -150), p + Vector2(70, -145), p + Vector2(95, -95), p + Vector2(20, -110)]), hair)
	else:
		c.draw_rect(Rect2(p.x - 70, p.y - 140, 140, 40), hair)
	var talk := absf(sin(t * 12.0)) * 12.0
	c.draw_circle(p + Vector2(-25, -70), 9, Color.WHITE)
	c.draw_circle(p + Vector2(25, -70), 9, Color.WHITE)
	c.draw_circle(p + Vector2(-25, -68), 4, Color.BLACK)
	c.draw_circle(p + Vector2(25, -68), 4, Color.BLACK)
	c.draw_rect(Rect2(p.x - 18, p.y - 32, 36, 4 + talk), Color(0.35, 0.05, 0.05))
