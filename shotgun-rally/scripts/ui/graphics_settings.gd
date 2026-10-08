extends VBoxContainer
## SETTINGS -> GRAPHICS (in the settings panel's left column): the quality (LOW / MEDIUM /
## HIGH / ULTRA), the 3D resolution, the cars' lights, and the renderer (Forward+ or the
## lighter Compatibility one, after a restart). Saved and applied as you change them
## (Graphics, user://graphics.cfg).

const UI = preload("res://scripts/ui/ui_kit.gd")
const Graphics = preload("res://scripts/render/graphics.gd")

const QUALITIES := [["low", "LOW"], ["medium", "MEDIUM"], ["high", "HIGH"], ["ultra", "ULTRA"]]
const SCALES := [["0", "AUTO"], ["1", "100 %"], ["0.85", "85 %"], ["0.7", "70 %"], ["0.5", "50 %"]]
const LIGHTS := [["auto", "AT NIGHT"], ["on", "ALWAYS"], ["off", "OFF"]]
const RENDERERS := [["auto", "FORWARD+"], ["compatibility", "COMPATIBILITY"]]
const WHAT := {
	"low": "Flat colours, light shadows: weak laptops, Chromebooks.",
	"medium": "Textured roads and ground, AO, glow, full shadows.",
	"high": "Real-looking trees near the road, reflections (SSR, the car's own), SSIL, TAA, soft shadows.",
	"ultra": "Global illumination (SDFGI), sharpest shadows, the farthest view.",
}

var _note: Label
var _restart: Label


func _ready() -> void:
	add_theme_constant_override("separation", 4)
	add_child(UI.label("GRAPHICS", 20, UI.YELLOW, true))
	add_child(_cycle("QUALITY", QUALITIES, Graphics.level(), func(k): Graphics.set_level(k)))
	_note = UI.label("", 12, UI.DIM)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size = Vector2(300, 0)
	add_child(_note)
	var web := OS.has_feature("web")
	add_child(_cycle("RENDER SCALE", SCALES, _scale_key(), func(k): Graphics.set_render_scale(float(k))))
	add_child(_cycle("CAR LIGHTS", LIGHTS, Graphics.car_lights(), func(k): Graphics.set_car_lights(k)))
	if not web:                                      # (a browser only has the one renderer)
		add_child(_cycle("RENDERER", RENDERERS, Graphics.renderer(), func(k): Graphics.set_renderer(k)))
		_restart = UI.label("", 12, UI.YELLOW)
		add_child(_restart)
	_refresh()


func _scale_key() -> String:
	var s := Graphics.render_scale_setting()
	for c in SCALES:
		if absf(float(c[0]) - s) < 0.01:
			return c[0]
	return "0"


func _refresh() -> void:
	var what: String = WHAT.get(Graphics.level(), "")
	if not Graphics.forward() and Graphics.level() != "low":
		what += " (Compatibility: no SSR, SSIL, GI or TAA.)"
	_note.text = what + " Textures change from the next stage."
	if _restart:
		_restart.text = "RESTART THE GAME TO SWITCH THE RENDERER" if Graphics.restart_needed() else ""


## A setting with a few choices ([key, label]): a button that steps through them.
## (The choice it's on is kept on the button: a lambda gets its own copy of a local
## each time it runs, so a local `at` stepped on every click would start from the
## same choice every time, and the second click in a row would change nothing.)
func _cycle(title: String, choices: Array, current: String, apply: Callable) -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	var l := UI.label(title, 16, UI.CREAM)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(l)
	var first := maxi(0, choices.map(func(c): return c[0]).find(current))
	var b := UI.button(choices[first][1], func(): pass, 15, 150)
	b.set_meta("at", first)
	b.pressed.connect(func():
		var at: int = (int(b.get_meta("at")) + 1) % choices.size()
		b.set_meta("at", at)
		b.text = choices[at][1]
		apply.call(choices[at][0])
		_refresh())
	box.add_child(b)
	return box
