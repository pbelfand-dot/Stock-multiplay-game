extends RefCounted
## The menus' look: Oswald type, rally red and yellow, and the big menu buttons
## that slide out with a yellow bar when you point at them (mouse, keys or pad).
## Panels and buttons wear the art in assets/ui (made with Higgsfield), in two
## styles: "rally" (carbon and steel, a red and yellow corner: the rally screens)
## and "night" (smoked glass edged in amber: the touge, cut up and online). Static
## helpers; every screen builds from these.

const YELLOW := Color(1.0, 0.8, 0.18)
const RED := Color(0.86, 0.14, 0.1)
const CREAM := Color(0.98, 0.95, 0.86)
const DIM := Color(0.72, 0.74, 0.7)
const GLASS := Color(0.04, 0.05, 0.06, 0.78)

## The panels' and buttons' art: 9-slice margins (left, top, right, bottom) in
## the texture's pixels, and whether its middle tiles (carbon weave) or stretches.
const SKINS := {
	"panel_rally": [44, 44, 12, 12, true],
	"panel_night": [34, 34, 10, 10, false],
	"button_rally": [10, 10, 10, 10, true],
	"button_rally_lit": [10, 10, 10, 10, false],
	"button_night": [10, 10, 10, 10, false],
	"button_night_lit": [12, 12, 12, 12, false],
}

static var _bold: Font
static var _med: Font
static var _tex := {}


static func bold() -> Font:
	if _bold == null:
		_bold = load("res://assets/fonts/Oswald-Bold.woff2")
	return _bold


static func med() -> Font:
	if _med == null:
		_med = load("res://assets/fonts/Oswald-Medium.woff2")
	return _med


## A picture from assets/ui (png, else jpg), or null when it isn't there.
static func art(name: String) -> Texture2D:
	if not _tex.has(name):
		_tex[name] = null
		for ext in ["png", "jpg"]:
			var p := "res://assets/ui/%s.%s" % [name, ext]
			if ResourceLoader.exists(p):
				_tex[name] = load(p)
				break
	return _tex[name]


## A panel or button in the art (SKINS), with its words margin from the edges;
## falls back to the plain dark glass when the art is missing.
static func skin(name: String, margin := 22.0, alpha := 1.0) -> StyleBox:
	var t := art(name)
	if t == null:
		return box(Color(GLASS, GLASS.a * alpha), 12, int(margin))
	var m: Array = SKINS.get(name, [10, 10, 10, 10, false])
	var sb := StyleBoxTexture.new()
	sb.texture = t
	sb.texture_margin_left = m[0]
	sb.texture_margin_top = m[1]
	sb.texture_margin_right = m[2]
	sb.texture_margin_bottom = m[3]
	if m[4]:
		sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
		sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	sb.set_content_margin_all(margin)
	sb.modulate_color = Color(1, 1, 1, alpha)
	return sb


## A screen's panel background: "rally" or "night".
static func panel_skin(style := "rally", margin := 22.0) -> StyleBox:
	return skin("panel_" + style, margin, 0.94)


static func label(text: String, size := 22, col := CREAM, heavy := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", bold() if heavy else med())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


static func box(col := GLASS, radius := 12, margin := 22) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	return sb


static func panel(col := GLASS) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(col))
	return p


## A screen's panel in the art ("rally" or "night").
static func art_panel(style := "rally") -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel_skin(style))
	return p


## A plain button in the menus' style: a dark plate, lit (yellow, or amber at
## night) when hovered / focused / pressed.
static func button(text: String, cb: Callable, size := 22, min_w := 0.0, style := "rally") -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", bold())
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", CREAM)
	b.add_theme_color_override("font_hover_color", Color(0.08, 0.08, 0.08))
	b.add_theme_color_override("font_focus_color", Color(0.08, 0.08, 0.08))
	b.add_theme_color_override("font_pressed_color", Color(0.08, 0.08, 0.08))
	b.add_theme_color_override("font_disabled_color", Color(0.5, 0.5, 0.5))
	if art("button_" + style) != null:
		var lit := skin("button_%s_lit" % style, 10.0) as StyleBoxTexture
		lit.content_margin_left = 16
		lit.content_margin_right = 16
		var plate := skin("button_" + style, 10.0) as StyleBoxTexture
		plate.content_margin_left = 16
		plate.content_margin_right = 16
		b.add_theme_stylebox_override("normal", plate)
		b.add_theme_stylebox_override("hover", lit)
		b.add_theme_stylebox_override("focus", lit)
		var down := lit.duplicate() as StyleBoxTexture
		down.modulate_color = Color(0.85, 0.85, 0.85)
		b.add_theme_stylebox_override("pressed", down)
		b.add_theme_stylebox_override("hover_pressed", down)
		var off := plate.duplicate() as StyleBoxTexture
		off.modulate_color = Color(0.6, 0.6, 0.6, 0.7)
		b.add_theme_stylebox_override("disabled", off)
	else:
		b.add_theme_stylebox_override("normal", box(Color(0.12, 0.13, 0.14, 0.92), 8, 10))
		b.add_theme_stylebox_override("hover", box(YELLOW, 8, 10))
		b.add_theme_stylebox_override("focus", box(YELLOW, 8, 10))
		b.add_theme_stylebox_override("pressed", box(YELLOW.darkened(0.15), 8, 10))
		b.add_theme_stylebox_override("disabled", box(Color(0.1, 0.1, 0.1, 0.7), 8, 10))
	b.custom_minimum_size = Vector2(min_w, 0)
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(cb)
	return b


## The chosen one of a row of tabs: its plate in rally red.
static func mark(b: Button) -> void:
	if art("button_rally") == null:
		b.add_theme_stylebox_override("normal", box(RED, 8, 10))
		return
	var sel := skin("button_rally_lit", 10.0) as StyleBoxTexture
	sel.content_margin_left = 16
	sel.content_margin_right = 16
	sel.modulate_color = Color(1.0, 0.28, 0.2)
	b.add_theme_stylebox_override("normal", sel)
	b.add_theme_color_override("font_color", CREAM)


## A big home-screen item: its icon (assets/ui/icon_<icon>), a title and a line
## under it, on a carbon plate; pointed at, it slides right, a yellow bar grows
## on its left and the title turns yellow. Returns the Button that covers it
## (focus, clicks).
static func menu_item(title: String, sub: String, cb: Callable, accent := false, icon := "") -> Control:
	const W := 500.0
	const H := 76.0
	var item := Control.new()
	item.custom_minimum_size = Vector2(W, H)
	var card := Panel.new()
	card.add_theme_stylebox_override("panel", skin("button_rally", 0.0, 0.9) if art("button_rally") else box(Color(0.04, 0.05, 0.06, 0.72), 10, 0))
	card.size = Vector2(W, H)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item.add_child(card)
	var bar := ColorRect.new()
	bar.color = YELLOW if accent else RED
	bar.position = Vector2(3, 6)
	bar.size = Vector2(6, H - 12)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(bar)
	var x := 26.0
	var pic := art("icon_" + icon) if icon != "" else null
	if pic:
		var ic := TextureRect.new()
		ic.texture = pic
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.position = Vector2(22, 10)
		ic.size = Vector2(H - 20, H - 20)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(ic)
		x = 22.0 + H - 20.0 + 14.0
	var t := label(title, 34, YELLOW if accent else CREAM, true)
	t.position = Vector2(x, 0)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(t)
	var s := label(sub, 15, DIM)
	s.position = Vector2(x + 2, 46)
	s.size = Vector2(W - x - 14, 22)
	s.clip_text = true
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(s)
	var hit := Button.new()
	hit.flat = true
	hit.size = Vector2(W, H)
	hit.focus_mode = Control.FOCUS_ALL
	hit.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	hit.pressed.connect(cb)
	item.add_child(hit)
	var lit := func(on: bool) -> void:
		var tw := card.create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(card, "position:x", 18.0 if on else 0.0, 0.16)
		tw.tween_property(bar, "size:x", 12.0 if on else 6.0, 0.16)
		tw.tween_property(bar, "color", YELLOW if on or accent else RED, 0.16)
		t.add_theme_color_override("font_color", YELLOW if on or accent else CREAM)
	hit.mouse_entered.connect(func(): hit.grab_focus())
	hit.focus_entered.connect(lit.bind(true))
	hit.focus_exited.connect(lit.bind(false))
	item.set_meta("button", hit)
	return item


## A row of small coloured squares (paint chips): pick(i) when one is clicked.
static func swatches(colours: Array, current: Color, pick: Callable) -> GridContainer:
	var g := GridContainer.new()
	g.columns = 12
	g.add_theme_constant_override("h_separation", 6)
	g.add_theme_constant_override("v_separation", 6)
	for i in colours.size():
		var c: Color = colours[i]
		var b := Button.new()
		b.custom_minimum_size = Vector2(38, 30)
		b.tooltip_text = ""
		var sel := c.is_equal_approx(current)
		var sb := box(c, 6, 0)
		if sel:
			sb.border_color = YELLOW
			sb.set_border_width_all(4)
		b.add_theme_stylebox_override("normal", sb)
		var hov := box(c.lightened(0.15), 6, 0)
		hov.border_color = Color.WHITE
		hov.set_border_width_all(3)
		b.add_theme_stylebox_override("hover", hov)
		b.add_theme_stylebox_override("focus", hov)
		b.add_theme_stylebox_override("pressed", hov)
		b.pressed.connect(pick.bind(i))
		g.add_child(b)
	return g


## A labelled bar: what (0..1 of the way between the slowest and quickest car).
static func stat_bar(name: String, value: float, text: String, width := 260.0) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var l := label(name, 17, DIM)
	l.custom_minimum_size = Vector2(76, 0)
	row.add_child(l)
	var back := Panel.new()
	back.add_theme_stylebox_override("panel", box(Color(1, 1, 1, 0.12), 4, 0))
	back.custom_minimum_size = Vector2(width, 12)
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(back)
	var fill := Panel.new()
	fill.add_theme_stylebox_override("panel", box(YELLOW, 4, 0))
	fill.size = Vector2(width * clampf(value, 0.04, 1.0), 12)
	back.add_child(fill)
	var t := label(text, 17, CREAM)
	t.custom_minimum_size = Vector2(70, 0)
	row.add_child(t)
	return row


static func gap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c
