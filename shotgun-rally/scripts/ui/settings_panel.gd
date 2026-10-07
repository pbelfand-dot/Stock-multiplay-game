extends PanelContainer
## SETTINGS: the controls, the sound, the AI co-driver's timing, what surface
## quick stages are, and the driving aids, each its own switch (off: the car as it
## is). Saved as you change them (Config, user://settings.cfg).

signal back

const UI = preload("res://scripts/ui/ui_kit.gd")
## What PLAY NOW and online stages are (Config.quick_surface, Main.quick_opts).
const SURFACES := [["any", "ANY: GRAVEL, TARMAC OR MIXED"], ["gravel", "GRAVEL"], ["tarmac", "TARMAC"], ["mixed", "MIXED: GRAVEL + TARMAC"]]
## Extra tyre grip (Config.grip_assist, TireModel.grippy).
const GRIPS := [["2.0", "ARCADE (OUT OF THE BOX)"], ["1.5", "MORE GRIP"], ["1.0", "GRIPPY"], ["0.0", "REAL (SLIPPERY GRAVEL)"]]
## The road modes' handling (Config.street_handling): SIM, the car on its real road
## tyres without the drift helpers (Assetto Corsa-like), or the rally game's ARCADE.
const STREETS := [["sim", "SIM (REAL ROAD TYRES)"], ["arcade", "ARCADE (AS THE RALLY)"]]
const AIDS := [
	["anti_lock", "ABS", "A locking wheel gets its brake eased off: brake hard and still steer."],
	["traction_control", "TRACTION CONTROL", "Spinning wheels get the throttle cut: flat out off the line, no smoke."],
	["stability_control", "STABILITY CONTROL", "Brakes one wheel to stop a slide getting away, or to tuck the nose in."],
	["steering_smoothing", "STEERING SMOOTHING", "Keys ramp the steering in (gentler at speed); a stick is left almost raw."],
	["steering_damping", "STEERING DAMPING", "The wheels turn more slowly at speed: calmer when it's quick."],
	["countersteer_help", "COUNTERSTEER HELP", "When the tail slides, the front wheels point where you're going (drift assist does it when on)."],
	["speed_sensitive_steering", "SPEED-SENSITIVE STEERING", "Steering asks for a share of the tyres' grip: precise at any speed, never past it."],
	["drift_assist", "DRIFT ASSIST", "In a drift your steering sets the angle; let go and it straightens. No spins."],
	["high_speed_stability", "HIGH-SPEED STABILITY", "At speed, wobbles and a clipped tail are damped at once."],
]


func _ready() -> void:
	add_theme_stylebox_override("panel", UI.box())
	custom_minimum_size = Vector2(1040, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	add_child(v)
	v.add_child(UI.label("SETTINGS", 28, UI.CREAM, true))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 30)
	v.add_child(cols)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(310, 0)
	left.add_theme_constant_override("separation", 8)
	cols.add_child(left)
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(620, 0)
	right.add_theme_constant_override("separation", 2)
	cols.add_child(right)
	var config := get_node("/root/Config")
	left.add_child(UI.label("CONTROLS", 20, UI.YELLOW, true))
	left.add_child(_slider("MOUSE LOOK", 0.0008, 0.005, config.mouse_sens, func(x): config.mouse_sens = x))
	left.add_child(_toggle("INVERT MOUSE Y", "", config.invert_y, func(on): config.invert_y = on))
	left.add_child(UI.gap(6))
	left.add_child(UI.label("SOUND", 20, UI.YELLOW, true))
	left.add_child(_slider("VOLUME", 0.0, 1.0, config.volume, func(x):
		config.volume = x
		config.apply_volumes()))
	left.add_child(_slider("EFFECTS  (ENGINE, GRAVEL)", 0.0, 1.0, config.sfx_volume, func(x):
		config.sfx_volume = x
		config.apply_volumes()))
	left.add_child(_slider("CO-DRIVER VOICE", 0.0, 1.0, config.voice_volume, func(x):
		config.voice_volume = x
		config.apply_volumes()))
	left.add_child(UI.gap(6))
	left.add_child(UI.label("CO-DRIVER", 20, UI.YELLOW, true))
	left.add_child(_slider("CALLS  LATE  ·  EARLY", -1.0, 1.0, config.call_early, func(x): config.call_early = x))
	right.add_child(UI.label("DRIVING AIDS", 20, UI.YELLOW, true))
	for a in AIDS:
		right.add_child(_toggle(a[1], a[2], bool(config.aids.get(a[0], false)), func(on): config.aids[a[0]] = on))
	right.add_child(_cycle("TYRE GRIP  (RALLY)", GRIPS, "%.1f" % config.grip_assist, func(k): config.grip_assist = float(k)))
	right.add_child(_cycle("STREET HANDLING  (CUT UP, TOUGE)", STREETS, config.street_handling, func(k): config.street_handling = k))
	right.add_child(_cycle("STAGES  (PLAY NOW, ONLINE)", SURFACES, config.quick_surface, func(k): config.quick_surface = k))
	var back_btn := UI.button("BACK", func(): back.emit(), 20, 140)
	back_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.add_child(back_btn)
	back_btn.grab_focus.call_deferred()


## A switch: its name (and a line on what it does), an ON / OFF button; apply(on) is
## called, then the settings are saved.
func _toggle(title: String, what: String, on: bool, apply: Callable) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 0)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_child(UI.label(title, 16, UI.CREAM))
	if what != "":
		text.add_child(_note(what, 500, 12))
	row.add_child(text)
	var b := UI.button("ON" if on else "OFF", func(): pass, 15, 78)
	b.toggle_mode = true
	b.button_pressed = on
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.toggled.connect(func(now: bool):
		b.text = "ON" if now else "OFF"
		apply.call(now)
		get_node("/root/Config").save())
	row.add_child(b)
	return row


## A setting with a few choices ([key, label]): a button that steps through them;
## apply(key) is called, then the settings are saved.
func _cycle(title: String, choices: Array, current: String, apply: Callable) -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	var l := UI.label(title, 18, UI.CREAM)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(l)
	var at := maxi(0, choices.map(func(c): return c[0]).find(current))
	var b := UI.button(choices[at][1], func(): pass, 17, 300)
	b.pressed.connect(func():
		at = (at + 1) % choices.size()
		b.text = choices[at][1]
		apply.call(choices[at][0])
		get_node("/root/Config").save())
	box.add_child(b)
	return box


## A slider with its name; apply(value) is called, then the settings are saved.
func _slider(title: String, lo: float, hi: float, value: float, apply: Callable) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.add_child(UI.label(title, 18, UI.CREAM))
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = (hi - lo) / 100.0
	s.value = value
	s.custom_minimum_size = Vector2(280, 24)
	s.focus_mode = Control.FOCUS_ALL
	s.value_changed.connect(func(x: float):
		apply.call(x)
		get_node("/root/Config").save())
	box.add_child(s)
	return box


func _note(text: String, width := 300.0, size := 14) -> Label:
	var l := UI.label(text, size, UI.DIM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(width, 0)
	return l
