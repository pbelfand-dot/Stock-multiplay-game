extends Node
## Graphics settings (autoload "Graphics"). On first launch it reads the GPU
## and picks a preset; in a match it watches the frame rate for a while and
## steps down a notch if the machine can't keep up. Everything is adjustable
## from the GRAPHICS panel (main menu + pause menu) and saved in settings.cfg.

signal changed

const UI = preload("res://scripts/ui/ui_theme.gd")

const PRESETS := {
	"low": {"scale": 0.67, "msaa": 0, "shadows": false, "detail": 5.0, "far": 220.0, "fps": 60},
	"medium": {"scale": 0.85, "msaa": 0, "shadows": false, "detail": 8.0, "far": 600.0, "fps": 60},
	"high": {"scale": 1.0, "msaa": 1, "shadows": true, "detail": 11.0, "far": 2000.0, "fps": 120},
	"ultra": {"scale": 1.0, "msaa": 2, "shadows": true, "detail": 16.0, "far": 4000.0, "fps": 0},
}
const ORDER := ["low", "medium", "high", "ultra"]
const MSAA := [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X]
const WATCH_SECONDS := 20.0        # frame-rate check window once you're in the office
const MIN_FPS := 40.0

var mode := "auto"                 # "auto" or a preset name the player picked
var detected := "medium"           # what auto chose for this machine
var gpu := ""
var vsync := true
var cur: Dictionary = PRESETS["medium"]
var _watch_t := -1.0
var _frames := 0
var _elapsed := 0.0


func _ready() -> void:
	gpu = "%s %s" % [RenderingServer.get_video_adapter_vendor(), RenderingServer.get_video_adapter_name()]
	detected = detect(gpu.strip_edges(), OS.get_processor_name(), OS.get_memory_info().get("physical", 0))
	var cf := ConfigFile.new()
	if cf.load(Config.SAVE_PATH) == OK:
		mode = cf.get_value("graphics", "mode", "auto")
		vsync = cf.get_value("graphics", "vsync", true)
		# a machine that was auto-lowered before remembers it
		detected = cf.get_value("graphics", "auto_level", detected) if cf.get_value("graphics", "gpu", "") == gpu else detected
	apply()


## GPU name -> preset. Conservative: better smooth than pretty.
static func detect(adapter: String, cpu: String, ram_bytes: int) -> String:
	var a := adapter.to_lower()
	var ram_gb := ram_bytes / 1073741824.0
	if a == "" or "llvmpipe" in a or "swiftshader" in a or "software" in a:
		return "low"
	if "apple" in a:                                   # Apple Silicon
		if "max" in a or "ultra" in a:
			return "ultra"
		if "pro" in a or "m3" in a or "m4" in a or "m5" in a:
			return "high"
		return "medium" if ram_gb < 15.0 else "high"       # base M1/M2
	if "intel" in a and not ("arc" in a):
		return "low"                                   # Intel HD / UHD / Iris (older Macs)
	if "nvidia" in a or "geforce" in a or "rtx" in a:
		return "ultra" if ("rtx" in a and ram_gb >= 15.0) else "high"
	if "amd" in a or "radeon" in a or "ati " in a:
		return "high" if ("rx" in a and ram_gb >= 15.0) else "medium"
	return "medium"


func level() -> String:
	return detected if mode == "auto" else mode


func set_mode(m: String) -> void:
	mode = m
	apply()
	save()


func set_vsync(on: bool) -> void:
	vsync = on
	apply()
	save()


func apply() -> void:
	cur = PRESETS[level()]
	if DisplayServer.get_name() == "headless":
		changed.emit()
		return
	var vp := get_viewport()
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = cur.scale
	vp.msaa_3d = MSAA[cur.msaa]
	Engine.max_fps = cur.fps
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	changed.emit()


func save() -> void:
	var cf := ConfigFile.new()
	cf.load(Config.SAVE_PATH)
	cf.set_value("graphics", "mode", mode)
	cf.set_value("graphics", "vsync", vsync)
	cf.set_value("graphics", "gpu", gpu)
	cf.set_value("graphics", "auto_level", detected)
	cf.save(Config.SAVE_PATH)


## Called when a match starts: if we're on AUTO, watch the frame rate for a bit
## and drop a level (once per check) when it can't hold MIN_FPS.
func start_watch() -> void:
	_watch_t = WATCH_SECONDS
	_frames = 0
	_elapsed = 0.0


func _process(delta: float) -> void:
	if _watch_t < 0.0:
		return
	_watch_t -= delta
	_frames += 1
	_elapsed += delta
	if _watch_t > 0.0:
		return
	_watch_t = -1.0
	var fps := _frames / maxf(_elapsed, 0.001)
	var i := ORDER.find(detected)
	if mode == "auto" and fps < MIN_FPS and i > 0 and DisplayServer.get_name() != "headless":
		detected = ORDER[i - 1]
		apply()
		save()
		var hud = get_tree().root.find_child("HUD", true, false)
		if hud and hud.has_method("show_toast"):
			hud.show_toast("Graphics lowered to %s for smoother play (%d fps). Change it in Pause → GRAPHICS." % [
					detected.to_upper(), int(fps)], Color(0.7, 0.85, 1.0))


## The GRAPHICS panel rows (for the main menu and the pause menu).
func settings_box(_ui = null) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	var info := UI.lbl("", 16, UI.DIM)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD
	var row := HBoxContainer.new()
	row.add_child(UI.lbl("Graphics", 18, UI.DIM))
	var btns := {}
	for m in ["auto"] + ORDER:
		var b = UI.btn(m.to_upper(), UI.NAVY_2, 16)
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func(): set_mode(m))
		row.add_child(b)
		btns[m] = b
	v.add_child(row)
	var vs := CheckBox.new()
	vs.text = "V-Sync"
	vs.button_pressed = vsync
	vs.toggled.connect(func(on: bool): set_vsync(on))
	v.add_child(vs)
	v.add_child(info)
	var refresh := func() -> void:
		for m in btns:
			btns[m].set_pressed_no_signal(m == mode)
		info.text = "Detected: %s → %s.  Now: %s (%d%% resolution, %s, shadows %s, %s fps)" % [
				gpu.strip_edges() if gpu.strip_edges() != "" else "unknown GPU", detected.to_upper(), level().to_upper(),
				int(cur.scale * 100), ["no AA", "MSAA 2x", "MSAA 4x"][cur.msaa], "on" if cur.shadows else "off",
				str(cur.fps) if cur.fps > 0 else "unlimited"]
	refresh.call()
	changed.connect(refresh)
	v.tree_exiting.connect(func() -> void:
		if changed.is_connected(refresh):
			changed.disconnect(refresh))
	return v


## A centered GRAPHICS popup with a CLOSE button (the main menu uses this).
func popup(_ui, parent: Control) -> PanelContainer:
	var p := PanelContainer.new()
	UI.center(p, Vector2(640, 260))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	v.add_child(UI.lbl("GRAPHICS", 34, UI.GOLD, true))
	v.add_child(settings_box())
	var close = UI.btn("CLOSE", UI.NAVY_2, 20)
	close.pressed.connect(p.queue_free)
	v.add_child(close)
	parent.add_child(p)
	return p
