extends Control
## "TRADE CLOSED +$120.05K +121%" with a spinning sunburst, like the trailer.

const UI = preload("res://scripts/ui/ui_theme.gd")
const Rules = preload("res://scripts/sim/rules.gd")

var _t := 0.0
var _life := 0.0
var _title := ""
var _amount := ""
var _pct := ""
var _color := Color.WHITE


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false


func show_trade(pnl: float, pct: float, liquidated: bool, who: String) -> void:
	_title = "LIQUIDATED" if liquidated else "TRADE CLOSED"
	_amount = ("+" if pnl >= 0 else "") + Rules.money(pnl)
	_pct = "%+.0f%%   %s" % [pct, who]
	_color = UI.GREEN.lightened(0.25) if pnl >= 0 else UI.RED.lightened(0.1)
	_life = 2.6
	_t = 0.0
	visible = true


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	_life -= delta
	if _life <= 0.0:
		visible = false
	queue_redraw()


func _draw() -> void:
	var c := size / 2 + Vector2(0, -60)
	var fade := clampf(_life / 0.5, 0.0, 1.0)
	var pop := 1.0 + maxf(0.0, 0.25 - _t) * 2.0
	# sunburst
	var rays := 18
	for i in rays:
		var a0 := _t * 0.6 + i * TAU / rays
		var a1 := a0 + TAU / rays * 0.5
		var r := 420.0
		draw_colored_polygon(PackedVector2Array([c, c + Vector2(cos(a0), sin(a0)) * r, c + Vector2(cos(a1), sin(a1)) * r]),
			Color(_color, 0.10 * fade))
	var bold := UI.bold()
	var title_size := int(64 * pop)
	var amt_size := int(120 * pop)
	var tw := bold.get_string_size(_title, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size).x
	var aw := bold.get_string_size(_amount, HORIZONTAL_ALIGNMENT_LEFT, -1, amt_size).x
	var pw := bold.get_string_size(_pct, HORIZONTAL_ALIGNMENT_LEFT, -1, 44).x
	draw_string_outline(bold, c + Vector2(-tw / 2, -40), _title, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size, 12, Color(0, 0, 0, 0.7 * fade))
	draw_string(bold, c + Vector2(-tw / 2, -40), _title, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size, Color(UI.GOLD, fade))
	draw_string_outline(bold, c + Vector2(-aw / 2, 80), _amount, HORIZONTAL_ALIGNMENT_LEFT, -1, amt_size, 14, Color(0, 0, 0, 0.7 * fade))
	draw_string(bold, c + Vector2(-aw / 2, 80), _amount, HORIZONTAL_ALIGNMENT_LEFT, -1, amt_size, Color(_color, fade))
	draw_string_outline(bold, c + Vector2(-pw / 2, 140), _pct, HORIZONTAL_ALIGNMENT_LEFT, -1, 44, 10, Color(0, 0, 0, 0.7 * fade))
	draw_string(bold, c + Vector2(-pw / 2, 140), _pct, HORIZONTAL_ALIGNMENT_LEFT, -1, 44, Color(_color, fade))
