extends CanvasLayer
## The replay's bar along the bottom of the screen (replay.gd fills it in every frame): the
## timeline (what's recorded, the playhead, GO and the finish marked; click or drag on it to
## scrub), the time and the total, PLAY / PAUSED and the speed, the camera and the car it
## follows, and the keys in a line under it (a controller's buttons when one's plugged in).
## Top left a red REPLAY tag, as TV puts on its replays; a line in the middle for the moment
## ("CAM 2 PLACED"). Its own look: the menus' Oswald type, yellow and red on dark glass.

const UI = preload("res://scripts/ui/ui_kit.gd")

signal seek(frac: float)             # the timeline clicked or dragged to (0..1)
signal scrubbing(on: bool)           # the mouse is down on the timeline (the replay holds the clock)

var timeline: Control                # (tests: where to click)
var _root: Control
var _panel: PanelContainer
var _state: Label
var _time: Label
var _speed: Label
var _cam: Label
var _car: Label
var _hints: Label
var _tag: Control
var _flash: Label
var _flash_t := 0.0
var _blink := 0.0


## The timeline: a bar with the recorded run, the played part in yellow, a knob for the playhead,
## ticks for GO (green), the finish (white) and where the run was paused (red).
class Timeline extends Control:
	const UIK = preload("res://scripts/ui/ui_kit.gd")
	var frac := 0.0
	var marks: Array = []            # [[frac, Color]]
	var bar: Node                    # the ReplayBar (its signals)
	var _down := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		custom_minimum_size = Vector2(0, 26)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func _draw() -> void:
		var h := size.y
		var y := h * 0.5
		var w := size.x
		draw_rect(Rect2(0, y - 4, w, 8), Color(1, 1, 1, 0.16))
		draw_rect(Rect2(0, y - 4, w * frac, 8), UIK.YELLOW)
		for m in marks:
			var x: float = clampf(float(m[0]), 0.0, 1.0) * w
			draw_rect(Rect2(x - 1.5, y - 10, 3, 20), m[1])
		var kx := w * frac
		draw_circle(Vector2(kx, y), 10.0, Color(0.05, 0.05, 0.06))
		draw_circle(Vector2(kx, y), 7.5, UIK.YELLOW)

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			_down = (e as InputEventMouseButton).pressed
			bar.scrubbing.emit(_down)
			if _down:
				bar.seek.emit(clampf((e as InputEventMouseButton).position.x / maxf(size.x, 1.0), 0.0, 1.0))
			accept_event()
		elif e is InputEventMouseMotion and _down:
			bar.seek.emit(clampf((e as InputEventMouseMotion).position.x / maxf(size.x, 1.0), 0.0, 1.0))
			accept_event()


func _ready() -> void:
	layer = 20
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	# the tag, top left
	var tag := PanelContainer.new()
	tag.add_theme_stylebox_override("panel", UI.box(UI.RED, 6, 10))
	tag.position = Vector2(28, 24)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tl := UI.label("REPLAY", 30, UI.CREAM, true)
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.add_child(tl)
	_root.add_child(tag)
	_tag = tag
	# the moment's line, middle
	_flash = UI.label("", 34, UI.YELLOW, true)
	_flash.add_theme_color_override("font_outline_color", Color.BLACK)
	_flash.add_theme_constant_override("outline_size", 8)
	_flash.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_flash.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_flash.offset_top = 120
	_flash.offset_left = -500
	_flash.offset_right = 500
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_flash)
	# the bar, bottom
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UI.box(Color(0.02, 0.03, 0.05, 0.74), 10, 14))
	_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_panel.offset_left = 16
	_panel.offset_right = -16
	_panel.offset_bottom = -14
	_panel.offset_top = -132
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(vb)
	timeline = Timeline.new()
	timeline.bar = self
	vb.add_child(timeline)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(row)
	_state = _label(row, 26, UI.YELLOW, true)
	_time = _label(row, 26, UI.CREAM, true)
	_speed = _label(row, 26, UI.YELLOW, true)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)
	_cam = _label(row, 24, UI.CREAM, true)
	_car = _label(row, 24, UI.YELLOW, true)
	_hints = _label(vb, 16, UI.DIM, false)
	_hints.clip_text = true
	_hints.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS


func _label(parent: Control, size: int, col: Color, heavy: bool) -> Label:
	var l := UI.label("", size, col, heavy)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


## This frame's numbers: {t, total, frac, playing, speed (x), shuttle (x, 0: none), cam, car,
## marks [[frac, Color]], pad (a controller's buttons in the hints)}.
func show_info(d: Dictionary) -> void:
	var shuttle := float(d.get("shuttle", 0.0))
	if shuttle < 0.0:
		_state.text = "REWIND"
	elif shuttle > 0.0:
		_state.text = "FAST FORWARD"
	else:
		_state.text = "PLAY" if d.get("playing", false) else "PAUSED"
	_time.text = "%s / %s" % [fmt(float(d.get("t", 0.0))), fmt(float(d.get("total", 0.0)))]
	var x := float(maxi(roundi(absf(shuttle)), 1)) if shuttle != 0.0 else float(d.get("speed", 1.0))
	_speed.text = (("%d" % int(x)) if is_equal_approx(x, roundf(x)) else ("%.2f" % x).rstrip("0").trim_prefix("0")) + "x"
	_cam.text = str(d.get("cam", ""))
	_car.text = str(d.get("car", ""))
	var tl := timeline as Timeline
	tl.frac = float(d.get("frac", 0.0))
	tl.marks = d.get("marks", [])
	tl.queue_redraw()
	_hints.text = hints(bool(d.get("pad", false)), str(d.get("mode", "")))


## The keys, one line: the camera's own first (the free cam's flying, the orbit's).
static func hints(pad: bool, mode: String) -> String:
	var own := ""
	if pad:
		if mode == "free":
			own = "L STICK fly · R STICK look · LB/RB down/up · RT fast · LT slow · R3 place cam   "
		elif mode == "orbit":
			own = "R STICK orbit · LT/RT zoom · LB/RB lower/raise   "
		return own + "A play · D-PAD step/speed · LT/RT rewind/ff · START start/end · Y car · X camera · R3 place cam · L3 hide · B exit"
	if mode == "free":
		own = "WASD fly · Q/E down/up · RIGHT MOUSE look · SHIFT fast · CTRL slow · P place cam   "
	elif mode == "orbit":
		own = "RIGHT MOUSE orbit · WHEEL zoom · Q/E lower/raise   "
	return own + "SPACE play · LEFT/RIGHT step (hold: rew/ff) · UP/DOWN speed · HOME/END · TAB car · C/X camera · 1-0 pick · P place · G director · H hide · ESC exit"


## The moment's line ("CAM 2 PLACED"), for a couple of seconds.
func flash(text: String) -> void:
	_flash.text = text
	_flash_t = 2.2


func _process(dt: float) -> void:
	_flash_t -= dt
	_flash.modulate.a = clampf(_flash_t / 0.5, 0.0, 1.0)
	_blink += dt
	_tag.modulate.a = 0.75 + 0.25 * sin(_blink * 3.0)


## The bar and the tag shown or hidden (H); the moment's line stays.
func set_hud(on: bool) -> void:
	_panel.visible = on
	_tag.visible = on


func hud_on() -> bool:
	return _panel.visible


static func fmt(t: float) -> String:
	return "%d:%04.1f" % [int(t) / 60, fmod(maxf(t, 0.0), 60.0)]
