extends RefCounted
## Shared look: navy terminal panels, gold accents, Oswald everywhere.

const NAVY := Color(0.06, 0.1, 0.17)
const NAVY_2 := Color(0.09, 0.15, 0.24)
const LINE := Color(0.55, 0.62, 0.72)
const GOLD := Color(0.98, 0.74, 0.14)
const GREEN := Color(0.2, 0.78, 0.35)
const RED := Color(0.9, 0.2, 0.2)
const TEXT := Color(0.93, 0.95, 0.98)
const DIM := Color(0.6, 0.66, 0.75)

static var _bold: Font
static var _medium: Font
static var _theme: Theme


static func bold() -> Font:
	if _bold == null:
		_bold = load("res://assets/fonts/Oswald-Bold.woff2")
	return _bold


static func medium() -> Font:
	if _medium == null:
		_medium = load("res://assets/fonts/Oswald-Medium.woff2")
	return _medium


static func panel_box(bg: Color, border: Color = LINE, radius: int = 10, bw: int = 3) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = medium()
	t.default_font_size = 20
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("panel", "PanelContainer", panel_box(NAVY))
	t.set_stylebox("panel", "Panel", panel_box(NAVY))
	var bn := panel_box(NAVY_2, LINE, 6, 2)
	var bh := panel_box(NAVY_2.lightened(0.15), GOLD, 6, 2)
	var bp := panel_box(NAVY_2.darkened(0.2), GOLD, 6, 2)
	var bd := panel_box(Color(0.15, 0.15, 0.18), Color(0.3, 0.3, 0.35), 6, 2)
	t.set_stylebox("normal", "Button", bn)
	t.set_stylebox("hover", "Button", bh)
	t.set_stylebox("pressed", "Button", bp)
	t.set_stylebox("disabled", "Button", bd)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", GOLD)
	t.set_font("font", "Button", bold())
	t.set_stylebox("normal", "LineEdit", panel_box(Color(0.03, 0.05, 0.09), LINE, 6, 2))
	t.set_stylebox("focus", "LineEdit", panel_box(Color(0.03, 0.05, 0.09), GOLD, 6, 2))
	t.set_color("font_color", "LineEdit", TEXT)
	_theme = t
	return t


static func lbl(text: String, size: int = 20, color: Color = TEXT, is_bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if is_bold:
		l.add_theme_font_override("font", bold())
	return l


static func btn(text: String, color: Color = NAVY_2, size: int = 22) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	if color != NAVY_2:
		b.add_theme_stylebox_override("normal", panel_box(color, color.lightened(0.3), 6, 2))
		b.add_theme_stylebox_override("hover", panel_box(color.lightened(0.12), Color.WHITE, 6, 2))
		b.add_theme_stylebox_override("pressed", panel_box(color.darkened(0.2), Color.WHITE, 6, 2))
		b.add_theme_color_override("font_hover_color", Color.WHITE)
	return b


## Center a control on screen at a fixed minimum size, growing both ways.
static func center(c: Control, sz: Vector2) -> void:
	c.custom_minimum_size = sz
	c.anchor_left = 0.5
	c.anchor_right = 0.5
	c.anchor_top = 0.5
	c.anchor_bottom = 0.5
	c.offset_left = -sz.x / 2
	c.offset_right = sz.x / 2
	c.offset_top = -sz.y / 2
	c.offset_bottom = sz.y / 2
	c.grow_horizontal = Control.GROW_DIRECTION_BOTH
	c.grow_vertical = Control.GROW_DIRECTION_BOTH
