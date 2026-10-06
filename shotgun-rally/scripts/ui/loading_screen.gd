extends CanvasLayer
## The loading screen while a stage is built: the art (assets/ui/loading.jpg,
## made with Higgsfield), the stage's name and numbers, a rally tip and a
## progress bar that follows the build step by step. It stays up for the
## first frames of the stage too (the first draw compiles shaders and
## stutters) and then fades out.

const TIPS := [
	"Co-driver: call each corner about two seconds before it. Too early and the driver forgets it.",
	"The number is how sharp the corner is: 6 is nearly flat out, 1 is very slow. Hairpins are slower still.",
	"Brake in a straight line, then turn in: braking loads the nose, and a loaded nose bites.",
	"Hairpin? Turn in, a flick of the handbrake, then power out.",
	"Full steering is the most grip the tyres have. If it pushes wide, you're simply too fast: brake earlier.",
	"\"Over crest\" means you can't see what's behind it. Trust the call, not your eyes.",
	"Mud on the windshield? Wipers are the co-driver's job (F / A). Alone, the AI does it.",
	"Driving alone? The AI co-driver reads the stage for you in the Fraser voice.",
	"Moving before the green is a jump start: +10 seconds.",
	"Driver: press C (right stick click) for the chase camera.",
	"Stuck? R puts you back on the road for a 5-second penalty.",
	"\"Tightens\": the corner gets slower as you go. Don't commit to the entry speed.",
]

var _bar: ProgressBar
var _step: Label
var _root: Control
var _shown_at := 0
var _fading := false


func _ready() -> void:
	layer = 50
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.08)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)
	if ResourceLoader.exists("res://assets/ui/loading.jpg"):
		var art := TextureRect.new()
		art.texture = load("res://assets/ui/loading.jpg")
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_root.add_child(art)
	# a dark band at the bottom for the words
	var shade := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0, 0, 0, 0.0))
	grad.set_color(1, Color(0, 0, 0, 0.85))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	shade.texture = gt
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.anchor_left = 0.0
	shade.anchor_right = 1.0
	shade.anchor_top = 0.5
	shade.anchor_bottom = 1.0
	_root.add_child(shade)


## Fill it in: stage number (or a story stage's title), what's coming (the stage
## itself is generated a moment later, so the numbers come with set_stage).
func begin(stage_no: int, title_text := "") -> void:
	_shown_at = Time.get_ticks_msec()
	var bold: Font = load("res://assets/fonts/Oswald-Bold.woff2")
	var medium: Font = load("res://assets/fonts/Oswald-Medium.woff2")
	var box := VBoxContainer.new()
	box.anchor_left = 0.0
	box.anchor_right = 1.0
	box.anchor_top = 1.0
	box.anchor_bottom = 1.0
	box.offset_left = 60
	box.offset_right = -60
	box.offset_top = -250
	box.offset_bottom = -40
	box.add_theme_constant_override("separation", 6)
	_root.add_child(box)
	var title := _label(title_text if title_text != "" else "STAGE %d" % stage_no, bold, 64, Color(1.0, 0.85, 0.25))
	title.name = "Title"
	box.add_child(title)
	var info := _label("Reading the road book...", medium, 24, Color(0.92, 0.92, 0.92))
	info.name = "Info"
	box.add_child(info)
	var tip := _label("TIP  " + TIPS[randi() % TIPS.size()], medium, 21, Color(0.75, 0.85, 1.0))
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(tip)
	_bar = ProgressBar.new()
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 14)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(1.0, 0.8, 0.2)
	fill.set_corner_radius_all(7)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(1, 1, 1, 0.15)
	back.set_corner_radius_all(7)
	_bar.add_theme_stylebox_override("fill", fill)
	_bar.add_theme_stylebox_override("background", back)
	box.add_child(_bar)
	_step = _label("", medium, 18, Color(0.8, 0.8, 0.8))
	box.add_child(_step)


## The stage's numbers, once it's generated.
func set_stage(length_m: float, corners: int, seed_value: int) -> void:
	var info: Label = _root.find_child("Info", true, false)
	if info:
		info.text = "%.1f km of gravel  ·  %d corners  ·  stage seed %d" % [length_m / 1000.0, corners, seed_value]


func progress(fraction: float, what: String) -> void:
	if _bar:
		_bar.value = fraction
		_step.text = what


## Done building: fill the bar, keep it up a moment (at least ~0.9 s in all, and
## through the first frames of the stage), then fade out and go.
func finish() -> void:
	progress(1.0, "Ready")
	var held := (Time.get_ticks_msec() - _shown_at) / 1000.0
	await get_tree().create_timer(maxf(0.9 - held, 0.25)).timeout
	_fading = true
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, 0.35)
	await tw.finished
	queue_free()


func _label(t: String, f: Font, px: int, c: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", c)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 6)
	return l
