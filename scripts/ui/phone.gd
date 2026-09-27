extends Control
## Your phone (P): the FEED from the newer clips. Donny J. Tramp posts land here
## a few seconds BEFORE the TV picks them up ("you're one post away from getting
## rich"), plus streamers, the Fed and @TradingMemes filler. Doesn't block
## movement; slides up in the bottom-right corner.

const UI = preload("res://scripts/ui/ui_theme.gd")

## speaker -> [display name, handle, avatar color, verified]
const WHO := {
	"TRAMP": ["Donny J. Tramp", "@realDonnyTramp", Color(0.98, 0.72, 0.2), true],
	"TJZ": ["TJZ", "@tjz_trades", Color(0.2, 0.2, 0.22), true],
	"KIMCHEE": ["KIMCHEE", "@kimcheecrypto", Color(0.95, 0.95, 0.95), true],
	"JIM CRAMMER": ["Jim Crammer", "@jimcrammer", Color(0.85, 0.15, 0.15), true],
	"ROARING KITTEH": ["Roaring Kitteh", "@TheRoaringKitteh", Color(0.9, 0.2, 0.2), false],
	"JEROME POWWW": ["Fed Chair Powww", "@FederalReserveBrrr", Color(0.2, 0.45, 0.3), true],
	"BREAKING": ["BNN Breaking", "@BNNbreaking", Color(0.8, 0.1, 0.12), true],
	"MEMES": ["Trading Memes", "@TradingMemes", Color(0.85, 0.85, 0.8), false],
}
const MEMES := [
	"Green candles when I don't trade vs. when I do",
	"Me explaining to my wife why we're down 90% but it's \"just a pullback\"",
	"\"I'll just take one more trade\" — last words, 4:59 PM",
	"Stop loss? I don't even know her.",
	"POV: you sold the bottom and it's now up 300%",
	"My portfolio is so red the SEC sent a sympathy card",
	"Buy high sell low. It's called a strategy, look it up.",
	"Guys the chart is literally a smiley face. Bullish.",
	"Mark Hanna said twice a day. He meant trades. Right? RIGHT?",
	"Leverage x100 because x50 is for cowards",
]
const MAX_POSTS := 7

var open := false
var frame: PanelContainer
var list: VBoxContainer
var badge: Label
var _slide := 0.0
var _meme_t := 25.0
var _unread := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame = PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UI.panel_box(Color(0.04, 0.04, 0.05), Color(0.16, 0.16, 0.18), 34, 10))
	frame.custom_minimum_size = Vector2(380, 640)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	frame.add_child(v)
	var notch := ColorRect.new()
	notch.color = Color(0, 0, 0)
	notch.custom_minimum_size = Vector2(110, 14)
	notch.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(notch)
	var head := HBoxContainer.new()
	v.add_child(head)
	var title := UI.lbl("FEED", 32, UI.TEXT, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(title)
	head.add_child(UI.lbl("[P]", 18, UI.DIM))
	var line := ColorRect.new()
	line.color = Color(0.9, 0.9, 0.92)
	line.custom_minimum_size = Vector2(0, 2)
	v.add_child(line)
	list = VBoxContainer.new()
	list.add_theme_constant_override("separation", 10)
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(list)
	badge = UI.lbl("", 20, UI.GOLD, true)
	badge.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	badge.position = Vector2(-330, -150)
	badge.add_theme_color_override("font_outline_color", Color.BLACK)
	badge.add_theme_constant_override("outline_size", 8)
	add_child(badge)
	post("MEMES", MEMES[0], false)


func toggle() -> void:
	open = not open
	if open:
		_unread = 0
		Sfx.play("click")


## Add a post to the top of the feed. `speaker` is a news speaker (see WHO).
func post(speaker: String, text: String, is_new := true) -> void:
	var who: Array = WHO.get(speaker, [speaker.capitalize(), "@" + speaker.to_lower().replace(" ", ""), Color(0.5, 0.5, 0.55), false])
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	row.add_child(top)
	var av := PanelContainer.new()
	av.add_theme_stylebox_override("panel", UI.panel_box(who[2], Color(1, 1, 1, 0.8), 22, 2))
	av.custom_minimum_size = Vector2(44, 44)
	var ini := UI.lbl(who[0].substr(0, 1), 22, Color(0.1, 0.1, 0.1) if who[2].v > 0.6 else Color.WHITE, true)
	ini.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	av.add_child(ini)
	top.add_child(av)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", -4)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(names)
	var nm := HBoxContainer.new()
	nm.add_theme_constant_override("separation", 6)
	names.add_child(nm)
	nm.add_child(UI.lbl(who[0], 21, UI.TEXT, true))
	if who[3]:   # verified: a little blue dot
		var tick := PanelContainer.new()
		tick.add_theme_stylebox_override("panel", UI.panel_box(Color(0.2, 0.55, 1.0), Color(0.2, 0.55, 1.0), 8, 0))
		tick.custom_minimum_size = Vector2(16, 16)
		tick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		nm.add_child(tick)
	names.add_child(UI.lbl(who[1], 16, UI.DIM))
	if is_new:
		top.add_child(UI.lbl("NEW!", 20, UI.GOLD, true))
	var body := UI.lbl(text, 21 if speaker == "TRAMP" else 18, UI.TEXT, speaker == "TRAMP")
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size.x = 330
	row.add_child(body)
	var n := func(lo: float, hi: float) -> String:
		var x := randf_range(lo, hi)
		return "%.2fK" % (x / 1000.0) if x >= 1000.0 else str(int(x))
	var big := speaker == "TRAMP"
	row.add_child(UI.lbl("%s replies    %s likes    %s reposts" % [n.call(80, 4000 if big else 300), n.call(900, 60000 if big else 3000),
			n.call(40, 3000 if big else 200)], 15, UI.DIM))
	list.add_child(row)
	list.move_child(row, 0)
	# only the newest post keeps its NEW! badge
	for i in range(1, list.get_child_count()):
		var t: HBoxContainer = list.get_child(i).get_child(0)
		var last := t.get_child(t.get_child_count() - 1)
		if last is Label and last.text == "NEW!":
			last.queue_free()
	while list.get_child_count() > MAX_POSTS:
		var old := list.get_child(list.get_child_count() - 1)
		list.remove_child(old)
		old.queue_free()
	if is_new and not open:
		_unread += 1
		if speaker == "TRAMP":
			Sfx.play("click", 2.0, 1.4)


## A news event -> a post (text without the "SPEAKER: " prefix).
func post_news(ev: Dictionary) -> void:
	var text: String = ev.get("headline", "")
	var colon := text.find(": ")
	if colon >= 0:
		text = text.substr(colon + 2)
	if ev.get("speaker", "") == "TRAMP":
		text += "!"
	post(ev.get("speaker", "BREAKING"), text)


func _process(delta: float) -> void:
	_slide = move_toward(_slide, 1.0 if open else 0.0, delta * 5.0)
	var vp := get_viewport_rect().size
	var eased := 1.0 - pow(1.0 - _slide, 3.0)
	frame.position = Vector2(vp.x - 404, vp.y - 110 - eased * 560.0)
	frame.visible = _slide > 0.001
	badge.text = "[P] PHONE  •  %d new" % _unread if _unread > 0 and not open else ""
	_meme_t -= delta
	if _meme_t <= 0.0:
		_meme_t = randf_range(35.0, 60.0)
		post("MEMES", MEMES[randi() % MEMES.size()])
