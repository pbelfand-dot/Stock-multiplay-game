extends Control
## Track Mode's car panel, bottom left (RaceSim.readout()): the four tyres as a car seen from
## above, each coloured by where its temperature sits against the compound's window (blue cold,
## green in it, red hot) with its surface temperature, a wear bar and its hot pressure; the
## compound; the brakes' heat (front, rear); the fuel and the laps it's good for; the car's
## ABS and TC levels (a Formula car: its hybrid's charge and mode instead, none of either); PIT
## LIMITER when it's on; DRS (a Formula car): grey, white when it may open, green open.

const UI = preload("res://scripts/ui/ui_kit.gd")
const COLD := Color(0.3, 0.55, 1.0)
const GOOD := Color(0.35, 0.9, 0.4)
const HOT := Color(1.0, 0.35, 0.25)

var _boxes: Array = []               # per corner: [ColorRect, temp Label, wear ColorRect, pressure Label]
var _compound: Label
var _brakes: Label
var _fuel: Label
var _aids: Label
var _limiter: Label
var _drs: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	offset_left = 28
	offset_top = -310
	offset_right = 300
	offset_bottom = -28
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.03, 0.05, 0.62)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_compound = _label(Vector2(14, 8), 22)
	for k in 4:
		var col := k % 2
		var row := k / 2
		var at := Vector2(14 + col * 128, 44 + row * 96)
		var r := ColorRect.new()
		r.position = at
		r.size = Vector2(56, 80)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(r)
		var t := _label(at + Vector2(60, 2), 24)
		var w := ColorRect.new()
		w.position = at + Vector2(62, 40)
		w.size = Vector2(52, 8)
		w.color = Color(0.9, 0.9, 0.9)
		w.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(w)
		var p := _label(at + Vector2(60, 50), 16)
		_boxes.append([r, t, w, p])
	_brakes = _label(Vector2(14, 226), 17)
	_fuel = _label(Vector2(150, 8), 18)
	_aids = _label(Vector2(14, 248), 17)
	_limiter = _label(Vector2(14, -34), 24)
	_limiter.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	_limiter.text = "PIT LIMITER"
	_drs = _label(Vector2(200, -34), 24)
	_drs.text = "DRS"
	_drs.visible = false


func _label(at: Vector2, size: int) -> Label:
	var l := Label.new()
	l.position = at
	l.add_theme_font_override("font", load("res://assets/fonts/Oswald-Bold.woff2"))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


## r: RaceSim.readout(); race: the RaceSim (its window bands); fuel_per_lap: litres (0: not known yet).
func show_state(r: Dictionary, race, fuel_per_lap := 0.0) -> void:
	_compound.text = "TYRES  %s" % str(r.get("short", "?"))
	for k in 4:
		var t: Dictionary = r.tyres[k]
		var b: Array = _boxes[k]
		var band: int = race.band(float(t.surface) * 0.6 + float(t.core) * 0.4)
		(b[0] as ColorRect).color = (COLD if band < 0 else (HOT if band > 0 else GOOD)).darkened(0.15)
		(b[1] as Label).text = "%d°" % roundi(float(t.surface))
		(b[2] as ColorRect).size.x = 52.0 * (1.0 - float(t.wear))
		(b[2] as ColorRect).color = Color(0.9, 0.9, 0.9) if float(t.wear) < 0.7 else HOT
		(b[3] as Label).text = "%.2f bar" % float(t.pressure)
	var discs: Array = r.get("discs", [0, 0, 0, 0])
	_brakes.text = "BRAKES  %d° / %d°" % [roundi(maxf(discs[0], discs[1])), roundi(maxf(discs[2], discs[3]))]
	var laps := ""
	if fuel_per_lap > 0.1:
		laps = "  ·  %d LAPS" % floori(float(r.fuel) / fuel_per_lap)
	_fuel.text = "FUEL %.1f L%s" % [float(r.fuel), laps]
	if bool(r.get("ers", false)):
		_aids.text = "ERS %d%%  %s  ·  LAP %d%%" % [roundi(float(r.ers_store) * 100.0), str(r.ers_mode), roundi(float(r.ers_left) * 100.0)]
		_aids.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5) if bool(r.ers_on) else Color.WHITE)
		_drs.visible = true
		_drs.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4) if bool(r.drs_open) else (Color.WHITE if bool(r.drs_avail) else Color(0.45, 0.45, 0.48)))
		_drs.text = "DRS OPEN" if bool(r.drs_open) else "DRS"
	else:
		_aids.text = "ABS %s  TC %s" % [str(r.abs) if int(r.abs) > 0 else "OFF", str(r.tc) if int(r.tc) > 0 else "OFF"]
	_limiter.visible = bool(r.get("limiter", false))
