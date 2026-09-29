extends Control
## Your phone (P opens it, P or ESC puts it away, even at the terminal): a home
## screen with the clock, a fund widget and the apps.
##   FEED    the posts. Donny J. Tramp lands here a few seconds BEFORE the TV
##           ("you're one post away from getting rich"), plus streamers, the Fed
##           and @TradingMemes filler
##   KWIK    the KWIK LIVE stream from the studio (and a ride there)
##   BANK    the fund / your account, cash on hand, today's P&L, open positions
##   MAPS    the commute: you, home, the office and BEMZE on a live map
##   RIDES   your cars (pick today's), or a cab
##   TONY    today's contracts, as texts from Tony
##   HOMES   your place and the Magnolia Heights listings
##   CAMERA  photo mode
## Slides up in the bottom-right corner; you can still walk with it out. The
## mouse is free while it's up, so the apps are clickable.

const UI = preload("res://scripts/ui/ui_theme.gd")
const Rules = preload("res://scripts/sim/rules.gd")
const Ledger = preload("res://scripts/sim/ledger.gd")

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
const MAX_POSTS := 12
const CHAT := ["OH MY GOD TRADE", "W", "L", "ratio", "first", "wagmi", "ngmi", "LONG IT", "SHORT IT",
	"is this financial advice", "KEKW", "chat is this real", "rug incoming", "sir this is a casino",
	"who's buying the top", "bro is cooked", "BASED", "send it", "diamond hands", "paper hands",
	"liquidated again lmao", "trust the process", "pump it", "mods??", "Tramp just posted!!",
	"GG", "rip my portfolio", "buy the dip", "which dip", "all of them"]
const CHATTERS := ["degen420", "wsb_andy", "bagholder99", "moonboi", "papertrader", "lambo_soon",
	"sec_intern", "tonys_cousin", "averagedown", "margin_call_mike", "hodl_harold", "fomo_fiona"]

## app id -> [name, tile color]. Grid on the home screen, then the dock.
const APPS := {
	"kwik": ["KWIK LIVE", Color(0.55, 0.3, 0.95)],
	"rides": ["RIDES", Color(0.98, 0.78, 0.12)],
	"homes": ["HOMES", Color(0.95, 0.48, 0.2)],
	"camera": ["CAMERA", Color(0.3, 0.32, 0.36)],
	"feed": ["FEED", Color(0.12, 0.55, 0.95)],
	"tony": ["TONY", Color(0.2, 0.78, 0.36)],
	"bank": ["BANK", Color(0.08, 0.42, 0.26)],
	"maps": ["MAPS", Color(0.82, 0.9, 0.84)],
}
const GRID := ["kwik", "rides", "homes", "camera"]
const DOCK := ["feed", "tony", "bank", "maps"]
const W := 380.0
const H := 660.0

var open := false
var app := "home"          # home | feed | kwik | bank | maps | rides | tony | homes
var world                  # World (studio cam, travel, the map)
var hud                    # the HUD (photo mode)
var frame: PanelContainer
var screen: Control
var pages := {}            # app id -> its page
var title: Label           # the open app's title
var app_bar: Control       # back button + title (hidden on the home screen)
var clock_lbl: Label       # status bar
var big_clock: Label       # home screen
var date_lbl: Label
var widget_lbl: Label
var widget_pnl: Label
var badges := {}           # app id -> its red badge
var badge: Label           # "[P] PHONE • 3 new" when it's away
var list: VBoxContainer    # FEED
var kwik: VBoxContainer
var cam_vp: SubViewport
var cam: Camera3D
var chat_box: VBoxContainer
var viewers_lbl: Label
var bank_box: VBoxContainer
var map_view: Control
var map_lbl: Label
var rides_box: VBoxContainer
var tony_box: VBoxContainer
var homes_box: VBoxContainer
var _chat_t := 0.0
var _cam_t := 0.0
var _slide := 0.0
var _meme_t := 25.0
var _unread := 0
var _refresh_t := 0.0
var _sig := ""             # what the open app last showed (rebuild only on change)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame = PanelContainer.new()
	var body := UI.panel_box(Color(0.03, 0.03, 0.04), Color(0.2, 0.2, 0.23), 44, 9)
	body.set_content_margin_all(12)
	frame.add_theme_stylebox_override("panel", body)
	frame.custom_minimum_size = Vector2(W, H)
	frame.size = Vector2(W, H)
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(frame)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	frame.add_child(v)
	# status bar: clock, the notch, signal + battery
	var bar := HBoxContainer.new()
	bar.custom_minimum_size.y = 26
	v.add_child(bar)
	clock_lbl = UI.lbl("9:41", 17, UI.TEXT, true)
	clock_lbl.custom_minimum_size.x = 110
	bar.add_child(clock_lbl)
	var notch := PanelContainer.new()
	notch.add_theme_stylebox_override("panel", UI.panel_box(Color(0, 0, 0), Color(0, 0, 0), 12, 0))
	notch.custom_minimum_size = Vector2(96, 22)
	notch.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_SHRINK_CENTER
	bar.add_child(notch)
	var sig := UI.lbl("5G  ▮▮▮  87%", 15, UI.TEXT, true)
	sig.custom_minimum_size.x = 110
	sig.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bar.add_child(sig)
	# the app bar: back to home + the app's name
	app_bar = HBoxContainer.new()
	v.add_child(app_bar)
	var back := Button.new()
	back.flat = true
	back.text = "‹ Home"
	back.add_theme_font_size_override("font_size", 18)
	back.add_theme_color_override("font_color", Color(0.4, 0.7, 1.0))
	back.focus_mode = Control.FOCUS_NONE
	back.pressed.connect(go_home)
	back.custom_minimum_size.x = 80
	app_bar.add_child(back)
	title = UI.lbl("", 26, UI.TEXT, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	app_bar.add_child(title)
	var pad := Control.new()
	pad.custom_minimum_size.x = 80
	app_bar.add_child(pad)
	# the screen: one page per app
	screen = Control.new()
	screen.clip_contents = true
	screen.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(screen)
	_build_home()
	_build_feed()
	_build_kwik()
	_build_bank()
	_build_maps()
	pages["rides"] = _scroll_page(func(b): rides_box = b)
	pages["tony"] = _scroll_page(func(b): tony_box = b)
	pages["homes"] = _scroll_page(func(b): homes_box = b)
	# the home bar
	var hb := Button.new()
	hb.flat = true
	hb.focus_mode = Control.FOCUS_NONE
	hb.custom_minimum_size = Vector2(0, 22)
	hb.pressed.connect(go_home)
	hb.draw.connect(func():
		var c := hb.size / 2.0
		hb.draw_rect(Rect2(c.x - 60, c.y - 3, 120, 6), Color(0.85, 0.85, 0.88)))
	v.add_child(hb)
	badge = UI.lbl("", 20, UI.GOLD, true)
	badge.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	badge.position = Vector2(-330, -150)
	badge.add_theme_color_override("font_outline_color", Color.BLACK)
	badge.add_theme_constant_override("outline_size", 8)
	add_child(badge)
	post("MEMES", MEMES[0], false)
	_show_app()


# ------------------------------------------------------------------ open / close

## P: take the phone out (home screen) or put it away.
func toggle() -> void:
	if open:
		close()
	else:
		open_app("home")


func close() -> void:
	if not open:
		return
	open = false
	_show_app()
	Sfx.play("click")


func go_home() -> void:
	open_app("home")


## Open straight into an app ("home" for the home screen).
func open_app(id: String) -> void:
	if id == "camera":
		close()
		if hud and hud.photo and not hud.photo.active:
			hud.close_modals()
			hud.photo.toggle()
		return
	if not open:
		open = true
		Sfx.play("click")
	else:
		Sfx.play("click", -6.0, 1.3)
	app = id
	if app == "feed":
		_unread = 0
	_sig = ""
	_refresh_t = 0.0
	_show_app()


func _show_app() -> void:
	for id in pages:
		pages[id].visible = id == app
	app_bar.visible = app != "home"
	if APPS.has(app):
		title.text = APPS[app][0]
		title.add_theme_color_override("font_color", Color(0.8, 0.55, 1) if app == "kwik" else UI.TEXT)
	cam_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if open and app == "kwik" else SubViewport.UPDATE_DISABLED
	frame.mouse_filter = Control.MOUSE_FILTER_STOP if open else Control.MOUSE_FILTER_IGNORE


## A page filling the screen.
func _page(id: String, c: Control) -> Control:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.add_child(c)
	pages[id] = c
	return c


## A scrolling page with a VBox in it (handed to `grab`).
func _scroll_page(grab: Callable) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.add_child(s)
	var b := VBoxContainer.new()
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_constant_override("separation", 8)
	s.add_child(b)
	grab.call(b)
	return s


# ------------------------------------------------------------------ home screen

func _build_home() -> void:
	var home := _page("home", Control.new())
	var wall := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.16, 0.08, 0.32))
	g.set_color(1, Color(0.02, 0.2, 0.16))
	g.add_point(0.55, Color(0.05, 0.1, 0.24))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0.3, 1)
	gt.width = 64
	gt.height = 128
	wall.texture = gt
	wall.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	wall.stretch_mode = TextureRect.STRETCH_SCALE
	wall.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wall.mouse_filter = Control.MOUSE_FILTER_IGNORE
	home.add_child(wall)
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.add_theme_constant_override("separation", 6)
	home.add_child(v)
	big_clock = UI.lbl("9:41", 64, Color(1, 1, 1), true)
	big_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(big_clock)
	date_lbl = UI.lbl("", 17, Color(0.85, 0.88, 0.95), true)
	date_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(date_lbl)
	# the fund widget (tap it for BANK)
	var wb := Button.new()
	wb.focus_mode = Control.FOCUS_NONE
	var ws := UI.panel_box(Color(1, 1, 1, 0.12), Color(1, 1, 1, 0.18), 18, 1)
	wb.add_theme_stylebox_override("normal", ws)
	wb.add_theme_stylebox_override("hover", UI.panel_box(Color(1, 1, 1, 0.18), Color(1, 1, 1, 0.3), 18, 1))
	wb.add_theme_stylebox_override("pressed", ws)
	wb.custom_minimum_size = Vector2(0, 74)
	wb.pressed.connect(func(): open_app("bank"))
	v.add_child(wb)
	var wv := VBoxContainer.new()
	wv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wv.offset_left = 16
	wv.offset_top = 8
	wv.add_theme_constant_override("separation", -4)
	wv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wb.add_child(wv)
	widget_lbl = UI.lbl("", 26, Color(1, 1, 1), true)
	widget_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wv.add_child(widget_lbl)
	widget_pnl = UI.lbl("", 16, UI.DIM, true)
	widget_pnl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wv.add_child(widget_pnl)
	var sp := Control.new()
	sp.custom_minimum_size.y = 12
	v.add_child(sp)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 16)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(grid)
	for id in GRID:
		grid.add_child(_tile(id, true))
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(fill)
	var hint := UI.lbl("[P] or [ESC] put it away", 14, Color(1, 1, 1, 0.55))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(hint)
	# the dock
	var dock := PanelContainer.new()
	var ds := UI.panel_box(Color(1, 1, 1, 0.14), Color(1, 1, 1, 0.14), 26, 0)
	ds.set_content_margin_all(10)
	dock.add_theme_stylebox_override("panel", ds)
	v.add_child(dock)
	var dh := HBoxContainer.new()
	dh.alignment = BoxContainer.ALIGNMENT_CENTER
	dh.add_theme_constant_override("separation", 16)
	dock.add_child(dh)
	for id in DOCK:
		dh.add_child(_tile(id, false))


## An app icon: the tile (drawn glyph), its name under it, a red badge.
func _tile(id: String, named: bool) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(64, 64)
	b.tooltip_text = APPS[id][0]
	var c: Color = APPS[id][1]
	b.add_theme_stylebox_override("normal", UI.panel_box(c, c.lightened(0.15), 16, 1))
	b.add_theme_stylebox_override("hover", UI.panel_box(c.lightened(0.1), Color.WHITE, 16, 2))
	b.add_theme_stylebox_override("pressed", UI.panel_box(c.darkened(0.25), Color.WHITE, 16, 2))
	b.pressed.connect(func(): open_app(id))
	b.name = "app_" + id
	col.add_child(b)
	var g := Glyph.new()
	g.kind = id
	g.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(g)
	var bd := UI.lbl("", 13, Color.WHITE, true)
	bd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bd.add_theme_stylebox_override("normal", UI.panel_box(Color(0.95, 0.2, 0.2), Color(0.95, 0.2, 0.2), 10, 0))
	(bd.get_theme_stylebox("normal") as StyleBoxFlat).set_content_margin_all(2)
	bd.position = Vector2(46, -6)
	bd.custom_minimum_size = Vector2(22, 20)
	bd.visible = false
	b.add_child(bd)
	badges[id] = bd
	if named:
		var n := UI.lbl(APPS[id][0].capitalize() if id != "kwik" else "Kwik", 13, Color.WHITE)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(n)
	return col


## The drawings on the app tiles.
class Glyph extends Control:
	var kind := ""

	func _draw() -> void:
		var c := size / 2.0
		var w := Color.WHITE
		match kind:
			"feed":        # a speech bubble
				draw_circle(c + Vector2(0, -3), 17, w)
				draw_colored_polygon(PackedVector2Array([c + Vector2(-12, 6), c + Vector2(-2, 12), c + Vector2(-16, 20)]), w)
			"kwik":        # play
				draw_colored_polygon(PackedVector2Array([c + Vector2(-9, -14), c + Vector2(15, 0), c + Vector2(-9, 14)]), w)
				draw_circle(c + Vector2(19, -19), 5, Color(1, 0.2, 0.25))
			"bank":        # a dollar sign in a coin
				draw_arc(c, 21, 0, TAU, 32, Color(1, 1, 1, 0.8), 2.5)
				draw_string(UI.bold(), c + Vector2(-15, 13), "$", HORIZONTAL_ALIGNMENT_CENTER, 30, 34, w)
			"maps":        # roads and a pin
				draw_line(Vector2(0, size.y * 0.75), Vector2(size.x, size.y * 0.25), Color(0.6, 0.62, 0.66), 7)
				draw_line(Vector2(0, size.y * 0.75), Vector2(size.x, size.y * 0.25), Color(1, 0.85, 0.2), 1.5)
				draw_line(Vector2(size.x * 0.3, 0), Vector2(size.x * 0.4, size.y), Color(1, 1, 1), 5)
				draw_colored_polygon(PackedVector2Array([c + Vector2(-8, -8), c + Vector2(8, -8), c + Vector2(0, 12)]), Color(0.9, 0.2, 0.2))
				draw_circle(c + Vector2(0, -10), 10, Color(0.9, 0.2, 0.2))
				draw_circle(c + Vector2(0, -10), 4, w)
			"rides":       # a car
				var k := Color(0.1, 0.1, 0.12)
				draw_rect(Rect2(c + Vector2(-22, -2), Vector2(44, 12)), k)
				draw_colored_polygon(PackedVector2Array([c + Vector2(-13, -2), c + Vector2(-8, -12), c + Vector2(9, -12), c + Vector2(15, -2)]), k)
				draw_circle(c + Vector2(-12, 11), 6, k)
				draw_circle(c + Vector2(12, 11), 6, k)
				draw_circle(c + Vector2(-12, 11), 2.5, Color(0.7, 0.7, 0.7))
				draw_circle(c + Vector2(12, 11), 2.5, Color(0.7, 0.7, 0.7))
			"tony":        # a text bubble
				var pts := PackedVector2Array()
				for i in 24:
					var a := TAU * i / 24.0
					pts.append(c + Vector2(cos(a) * 21, sin(a) * 16 - 2))
				draw_colored_polygon(pts, w)
				draw_colored_polygon(PackedVector2Array([c + Vector2(-14, 8), c + Vector2(-6, 12), c + Vector2(-20, 18)]), w)
				for i in 3:
					draw_circle(c + Vector2(-9 + i * 9, -2), 2.8, Color(0.2, 0.78, 0.36))
			"homes":       # a house
				draw_colored_polygon(PackedVector2Array([c + Vector2(-20, -2), c + Vector2(0, -19), c + Vector2(20, -2)]), w)
				draw_rect(Rect2(c + Vector2(-14, -3), Vector2(28, 20)), w)
				draw_rect(Rect2(c + Vector2(-4, 5), Vector2(8, 12)), Color(0.95, 0.48, 0.2))
			"camera":      # a camera
				draw_rect(Rect2(c + Vector2(-20, -11), Vector2(40, 26)), Color(0.85, 0.86, 0.88))
				draw_rect(Rect2(c + Vector2(-8, -16), Vector2(14, 6)), Color(0.85, 0.86, 0.88))
				draw_circle(c + Vector2(0, 2), 10, Color(0.15, 0.15, 0.18))
				draw_circle(c + Vector2(0, 2), 6, Color(0.35, 0.45, 0.6))
				draw_circle(c + Vector2(14, -6), 2, Color(1, 0.8, 0.3))


## The fake wall clock: the bell rings at 9:30, the close is 4:00.
func _wall_clock() -> String:
	var m = world.match_node if world else null
	if m == null:
		return "9:41"
	var mins := 0.0
	match m.phase:
		"trading":
			var day_len: float = maxf(float(m.get("_day_len")), 1.0)
			mins = 9.5 * 60.0 + clampf(1.0 - m.time_left / day_len, 0.0, 1.0) * 390.0
		"morning":
			mins = 9.5 * 60.0 - maxf(m.time_left, 0.0)
		"lobby":
			mins = 8.0 * 60.0 + 45.0
		_:
			mins = 16.0 * 60.0 + 5.0
	var h := int(mins / 60.0)
	var mm := int(mins) % 60
	return "%d:%02d" % [(h - 1) % 12 + 1, mm]


func _tick_home() -> void:
	var m = world.match_node if world else null
	var t := _wall_clock()
	clock_lbl.text = t
	big_clock.text = t
	if m == null:
		return
	var what := {"lobby": "BEFORE THE BELL", "morning": "COMMUTE", "trading": "MARKET OPEN"}
	date_lbl.text = "DAY %d  ·  %s" % [maxi(m.day, 1) if m.phase != "morning" else m.day + 1, what.get(m.phase, "AFTER HOURS")]
	var me := Net.my_id()
	var eq: float = m.equity_of(m.acct_for(me))
	widget_lbl.text = "%s  %s" % ["FUND" if Net.mode == "coop" else "ACCT", Rules.money(eq)]
	var pnl: float = m.stats.get(me, {}).get("pnl_day", 0.0)
	widget_pnl.text = "Today %s%s   ·   cash %s" % ["+" if pnl >= 0.0 else "-", Rules.money(absf(pnl)), Rules.money(m.cash_of(me))]
	widget_pnl.add_theme_color_override("font_color", UI.GREEN if pnl > 0.0 else (UI.RED if pnl < 0.0 else UI.DIM))
	_set_badge("feed", _unread)
	var todo := 0
	for c in m.contracts.get(me, []):
		if not c.done and not c.failed:
			todo += 1
	_set_badge("tony", todo)


func _set_badge(id: String, n: int) -> void:
	var b: Label = badges.get(id)
	if b:
		b.visible = n > 0
		b.text = str(n) if n < 10 else "9+"


# ------------------------------------------------------------------ FEED

func _build_feed() -> void:
	_page("feed", Control.new())
	var s := ScrollContainer.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pages["feed"].add_child(s)
	list = VBoxContainer.new()
	list.add_theme_constant_override("separation", 10)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.add_child(list)


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
	body.custom_minimum_size.x = 320
	row.add_child(body)
	var n := func(lo: float, hi: float) -> String:
		var x := randf_range(lo, hi)
		return "%.2fK" % (x / 1000.0) if x >= 1000.0 else str(int(x))
	var big := speaker == "TRAMP"
	row.add_child(UI.lbl("%s replies    %s likes    %s reposts" % [n.call(80, 4000 if big else 300), n.call(900, 60000 if big else 3000),
			n.call(40, 3000 if big else 200)], 15, UI.DIM))
	var line := ColorRect.new()
	line.color = Color(1, 1, 1, 0.08)
	line.custom_minimum_size.y = 1
	row.add_child(line)
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
	if is_new and not (open and app == "feed"):
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


# ------------------------------------------------------------------ KWIK LIVE

func _build_kwik() -> void:
	kwik = VBoxContainer.new()
	kwik.add_theme_constant_override("separation", 6)
	_page("kwik", kwik)
	# live camera in the studio (shares the game world)
	cam_vp = SubViewport.new()
	cam_vp.size = Vector2i(352, 220)
	cam_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(cam_vp)
	cam = Camera3D.new()
	cam.fov = 62
	cam_vp.add_child(cam)
	var stream := TextureRect.new()
	stream.texture = cam_vp.get_texture()
	stream.custom_minimum_size = Vector2(340, 212)
	stream.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stream.mouse_filter = Control.MOUSE_FILTER_IGNORE
	kwik.add_child(stream)
	var live := HBoxContainer.new()
	live.add_theme_constant_override("separation", 8)
	kwik.add_child(live)
	var tag := PanelContainer.new()
	tag.add_theme_stylebox_override("panel", UI.panel_box(Color(0.9, 0.1, 0.15), Color(0.9, 0.1, 0.15), 4, 0))
	tag.add_child(UI.lbl("LIVE", 16, Color.WHITE, true))
	live.add_child(tag)
	viewers_lbl = UI.lbl("", 17, UI.TEXT, true)
	live.add_child(viewers_lbl)
	kwik.add_child(UI.lbl("TJZ · KIMCHEE · ROARING KITTEH", 16, UI.DIM))
	chat_box = VBoxContainer.new()
	chat_box.add_theme_constant_override("separation", 1)
	chat_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chat_box.clip_contents = true
	kwik.add_child(chat_box)
	var go := UI.btn("PULL UP TO THE STUDIO  [G]", Color(0.4, 0.2, 0.7), 18)
	go.focus_mode = Control.FOCUS_NONE
	go.pressed.connect(go_to_studio)
	kwik.add_child(go)


func go_to_studio() -> void:
	close()
	if world:
		world.go_to_studio()


func _tick_kwik(delta: float) -> void:
	if world == null or cam == null:
		return
	# slow pan across the studio set, like an unattended stream cam
	_cam_t += delta
	var b: Vector3 = world.builder.studio_cam_pos
	cam.global_position = b + Vector3(sin(_cam_t * 0.15) * 1.6, 0.0, 0.0)
	cam.look_at(world.builder.STUDIO + Vector3(sin(_cam_t * 0.15) * 0.8, 1.0, -1.8))
	viewers_lbl.text = "%s watching" % ("%.1fK" % (12.0 + sin(_cam_t * 0.05) * 3.0 + randf() * 0.05))
	_chat_t -= delta
	if _chat_t <= 0.0:
		_chat_t = randf_range(0.3, 1.1)
		var who: String = CHATTERS[randi() % CHATTERS.size()]
		var l := UI.lbl("%s: %s" % [who, CHAT[randi() % CHAT.size()]], 15, Color.from_hsv(float(who.hash() % 360) / 360.0, 0.45, 1.0))
		chat_box.add_child(l)
		while chat_box.get_child_count() > 9:
			var o := chat_box.get_child(0)
			chat_box.remove_child(o)
			o.queue_free()


# ------------------------------------------------------------------ BANK

func _build_bank() -> void:
	_scroll_page(func(b): bank_box = b)
	pages["bank"] = bank_box.get_parent()


func _tick_bank() -> void:
	var m = world.match_node
	var me := Net.my_id()
	var a: Dictionary = m.my_acct()
	var eq: float = m.equity_of(m.acct_for(me))
	var st: Dictionary = m.stats.get(me, {})
	var pos_rows: Array = []
	for p in a.get("positions", []):
		var pnl: float = maxf(Ledger.pnl_of(p, m.price_of(p.sym)), -p.margin)
		pos_rows.append([p.sym, p.side, p.lev, pnl, p.margin, p.get("trader_id", me)])
	var sig := "%d|%d|%d|%s" % [int(eq), int(m.cash_of(me)), int(st.get("pnl_day", 0.0)), str(pos_rows)]
	if sig == _sig:
		return
	_sig = sig
	_clear(bank_box)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UI.panel_box(Color(0.06, 0.3, 0.2), Color(0.2, 0.7, 0.45), 16, 1))
	bank_box.add_child(card)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", -2)
	card.add_child(cv)
	cv.add_child(UI.lbl("BAGHOLDER CAPITAL · %s" % ("THE FUND" if Net.mode == "coop" else "YOUR ACCOUNT"), 14, Color(0.7, 0.95, 0.8), true))
	cv.add_child(UI.lbl(Rules.money(eq), 40, Color.WHITE, true))
	cv.add_child(UI.lbl("buying power %s   ·   quota %s" % [Rules.money(float(a.get("balance", 0.0))), Rules.money(m.quota)], 14, Color(0.8, 0.95, 0.85)))
	_row(bank_box, "Cash on hand", Rules.money(m.cash_of(me)), UI.GOLD)
	var pd: float = st.get("pnl_day", 0.0)
	_row(bank_box, "Your P&L today", "%s%s" % ["+" if pd >= 0.0 else "-", Rules.money(absf(pd))], UI.GREEN if pd >= 0.0 else UI.RED)
	var pt: float = st.get("pnl_total", 0.0)
	_row(bank_box, "All time", "%s%s" % ["+" if pt >= 0.0 else "-", Rules.money(absf(pt))], UI.GREEN if pt >= 0.0 else UI.RED)
	bank_box.add_child(UI.lbl("OPEN POSITIONS", 16, UI.DIM, true))
	if pos_rows.is_empty():
		bank_box.add_child(UI.lbl("Nothing open. Get to a desk.", 16, UI.DIM))
	for r in pos_rows:
		var who: String = "" if Net.mode != "coop" or r[5] == me else "  (%s)" % Net.player_name(r[5])
		_row(bank_box, "%s %s x%d%s" % [r[0], "LONG" if r[1] > 0 else "SHORT", r[2], who],
				"%s%s (%+.0f%%)" % ["+" if r[3] >= 0.0 else "-", Rules.money(absf(r[3])), r[3] / maxf(r[4], 1.0) * 100.0],
				UI.GREEN if r[3] >= 0.0 else UI.RED)
	bank_box.add_child(UI.lbl("Cash out at any ATM: by the elevator, or outside the bank on the street.", 14, UI.DIM))
	(bank_box.get_child(bank_box.get_child_count() - 1) as Label).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


# ------------------------------------------------------------------ MAPS

func _build_maps() -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	_page("maps", v)
	map_view = MapView.new()
	map_view.phone = self
	map_view.custom_minimum_size = Vector2(340, 400)
	map_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(map_view)
	var legend := HBoxContainer.new()
	legend.add_theme_constant_override("separation", 10)
	v.add_child(legend)
	for k in [["YOU", Color(0.3, 0.7, 1.0)], ["HOME", Color(0.3, 0.9, 0.4)], ["OFFICE", UI.GOLD], ["BEMZE", Color(0.5, 0.7, 1.0)]]:
		legend.add_child(UI.lbl("● " + k[0], 14, k[1], true))
	map_lbl = UI.lbl("", 17, UI.TEXT, true)
	map_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(map_lbl)


func _tick_maps() -> void:
	map_view.queue_redraw()
	var m = world.match_node
	var me := Net.my_id()
	var t: float = maxf(m.time_left, 0.0)
	var d := int(world.office_distance())
	if map_view.upstairs():
		map_lbl.text = "You're at BAGHOLDER CAPITAL."
	elif m.phase == "morning" and not m.arrived.has(me):
		map_lbl.text = "BELL IN %d:%02d  ·  office %d m" % [int(t) / 60, int(t) % 60, d]
	else:
		map_lbl.text = "Office %d m away" % d
	map_lbl.add_theme_color_override("font_color", UI.RED if m.phase == "morning" and t < 30.0 and not m.arrived.has(me) else UI.TEXT)


## The commute on a little map: the drive to work, home, the office, the
## dealership, the other traders, and you (an arrow, the way you're facing).
class MapView extends Control:
	var phone
	var _pts: PackedVector3Array
	var _back: PackedVector3Array
	var _box := Rect2()

	func _ready() -> void:
		clip_contents = true

	func _load() -> bool:
		if _box.size != Vector2.ZERO:
			return true
		var w = phone.world
		if w == null or w.builder == null or w.builder.get("hood") == null or w.builder.hood.get("hw") == null:
			return false
		_pts = w.builder.hood.hw.route("home_to_office").points
		_back = w.builder.hood.hw.route("office_to_home").points
		if _pts.is_empty():
			return false
		_box = Rect2(Vector2(_pts[0].x, _pts[0].z), Vector2.ZERO)
		for p in _pts:
			_box = _box.expand(Vector2(p.x, p.z))
		_box = _box.expand(Vector2(w.builder.hood.hw.dealership_lot.x, w.builder.hood.hw.dealership_lot.z))
		_box = _box.grow(45.0)
		return true

	func to_map(p: Vector3) -> Vector2:
		var k := minf(size.x / _box.size.x, size.y / _box.size.y)
		var off := (size - _box.size * k) / 2.0
		return off + (Vector2(p.x, p.z) - _box.position) * k

	## On the trading floor / in the studio (they're not on the map).
	func upstairs() -> bool:
		var w = phone.world
		var me = w.local_player if w else null
		if me == null:
			return false
		var at: Vector3 = me.global_position
		return absf(at.z) < 40.0 and at.x > -40.0 and at.x < 90.0

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.1, 0.13, 0.12))
		var w = phone.world
		if w == null or not _load():
			draw_string(UI.medium(), Vector2(20, 40), "No signal", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UI.DIM)
			return
		# the grid
		for i in range(1, 8):
			draw_line(Vector2(size.x * i / 8.0, 0), Vector2(size.x * i / 8.0, size.y), Color(1, 1, 1, 0.03), 1.0)
			draw_line(Vector2(0, size.y * i / 8.0), Vector2(size.x, size.y * i / 8.0), Color(1, 1, 1, 0.03), 1.0)
		# the roads: back route under, the way to work on top (blue, like GPS)
		for route in [_back, _pts]:
			var line := PackedVector2Array()
			for p in route:
				line.append(to_map(p))
			draw_polyline(line, Color(0.35, 0.38, 0.42), 7.0, true)
		var gps := PackedVector2Array()
		for p in _pts:
			gps.append(to_map(p))
		draw_polyline(gps, Color(0.25, 0.6, 1.0), 3.0, true)
		# places
		var office: Vector3 = w.builder.street.lobby_exit
		var home: Dictionary = w.home_of(Net.my_id())
		var dealer: Vector3 = w.builder.hood.hw.dealership_lot
		_pin(dealer, Color(0.5, 0.7, 1.0), "BEMZE")
		if not home.is_empty():
			_pin(home.spawn, Color(0.3, 0.9, 0.4), "HOME")
		_pin(office, UI.GOLD, "OFFICE")
		# the other traders
		for p in w.players_node.get_children():
			if p != w.local_player and p is Node3D:
				var at: Vector3 = p.driving.global_position if p.get("driving") else p.global_position
				draw_circle(to_map(at), 4.5, Color(1, 0.55, 0.9))
		# you
		var me = w.local_player
		if me == null:
			return
		var body: Node3D = me.driving if me.get("driving") else me
		var here: Vector3 = office if upstairs() else body.global_position
		var f: Vector3 = -body.global_transform.basis.z
		var dir := Vector2(f.x, f.z).normalized() if Vector2(f.x, f.z).length() > 0.01 else Vector2.UP
		var c := to_map(here)
		var sd := Vector2(-dir.y, dir.x)
		draw_circle(c, 11, Color(0.3, 0.7, 1.0, 0.25))
		draw_colored_polygon(PackedVector2Array([c + dir * 10, c - dir * 6 + sd * 7, c - dir * 3, c - dir * 6 - sd * 7]), Color(0.3, 0.7, 1.0))
		draw_polyline(PackedVector2Array([c + dir * 10, c - dir * 6 + sd * 7, c - dir * 3, c - dir * 6 - sd * 7, c + dir * 10]), Color.WHITE, 1.5)

	func _pin(at: Vector3, col: Color, label: String) -> void:
		var c := to_map(at)
		draw_circle(c, 7, col)
		draw_circle(c, 3, Color(0.1, 0.13, 0.12))
		var tw := UI.bold().get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		var at2 := c + Vector2(10, 5) if c.x + 10 + tw < size.x - 2 else c + Vector2(-10 - tw, 5)   # flip at the edge
		draw_string(UI.bold(), at2, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)


# ------------------------------------------------------------------ RIDES

func _tick_rides() -> void:
	var m = world.match_node
	var me := Net.my_id()
	var driving: String = m.car_of(me)
	var owned: Array = Rules.CAR_ORDER.filter(func(k): return m.owns_car(me, k))
	var sig := "%s|%s|%s" % [driving, str(owned), m.phase]
	if sig == _sig:
		return
	_sig = sig
	_clear(rides_box)
	if owned.is_empty():
		rides_box.add_child(_wrap(UI.lbl("No car yet. A used TOROLA Corona is %s at BEMZE, off the highway (on MAPS)." % Rules.money(Rules.CARS.beater.price), 17, UI.TEXT)))
	for k in owned:
		var d: Dictionary = Rules.CARS[k]
		var card := PanelContainer.new()
		var here: bool = k == driving
		card.add_theme_stylebox_override("panel", UI.panel_box(Color(0.1, 0.16, 0.26) if here else Color(0.1, 0.11, 0.14),
				Color(0.3, 0.6, 1.0) if here else Color(0.25, 0.27, 0.32), 12, 2))
		rides_box.add_child(card)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		card.add_child(h)
		var sw := ColorRect.new()
		sw.color = m.paint_of(me, k)
		sw.custom_minimum_size = Vector2(12, 44)
		h.add_child(sw)
		var info := VBoxContainer.new()
		info.add_theme_constant_override("separation", -3)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(info)
		info.add_child(UI.lbl(d.name, 18, UI.TEXT, true))
		info.add_child(UI.lbl("%d MPH  ·  0-60 %.1f s" % [int(d.top * 2.237), d.zero60], 14, UI.DIM))
		if here:
			h.add_child(UI.lbl("DRIVING", 15, Color(0.4, 0.7, 1.0), true))
		else:
			var b := UI.btn("DRIVE", Color(0.15, 0.35, 0.65), 15)
			b.focus_mode = Control.FOCUS_NONE
			var kk: String = k
			b.pressed.connect(func():
				Sfx.play("click")
				m.request_pick_car(kk))
			h.add_child(b)
	# the cab
	var rush: bool = m.phase == "morning" or m.is_late(me)
	rides_box.add_child(UI.lbl("CALL A CAB", 16, UI.DIM, true))
	if rush and driving != "":
		rides_box.add_child(_wrap(UI.lbl("Rush hour: no cabs for you. Your car's in the driveway. DRIVE.", 16, Color(1, 0.6, 0.3))))
	else:
		if rush:
			rides_box.add_child(_wrap(UI.lbl("Rush hour: bumper to bumper, %s on the meter." % Rules.money(Rules.CAB_FARE), 15, Color(1, 0.8, 0.4))))
		for d in [["downtown", "To the office (downtown)"], ["home", "Home"], ["hood", "Magnolia Heights"]]:
			if d[0] == "home" and m.house_of(me) == "":
				continue
			var b := UI.btn(d[1], Color(0.55, 0.45, 0.08), 17)
			b.focus_mode = Control.FOCUS_NONE
			var dest: String = d[0]
			b.pressed.connect(func(): _cab(dest))
			rides_box.add_child(b)


func _cab(dest: String) -> void:
	if world == null or world.hood == null:
		return
	var p = world.local_player
	if p and p.driving:
		if hud:
			hud.show_toast("You're driving. Park it first.", Color(1, 0.6, 0.3))
		return
	close()
	world.hood.ride(dest)


# ------------------------------------------------------------------ TONY

func _tick_tony() -> void:
	var m = world.match_node
	var list_c: Array = m.contracts.get(Net.my_id(), [])
	var sig := str(list_c.map(func(c): return [c.text, int(c.prog), c.done, c.failed]))
	if sig == _sig:
		return
	_sig = sig
	_clear(tony_box)
	var head := HBoxContainer.new()
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	tony_box.add_child(head)
	var av := PanelContainer.new()
	av.add_theme_stylebox_override("panel", UI.panel_box(Color(0.55, 0.35, 0.2), Color.WHITE, 22, 2))
	av.custom_minimum_size = Vector2(44, 44)
	var ini := UI.lbl("T", 22, Color.WHITE, true)
	ini.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	av.add_child(ini)
	head.add_child(av)
	head.add_child(UI.lbl("  Tony (Deli)", 18, UI.TEXT, true))
	if list_c.is_empty():
		_bubble("Market's closed. I'll text you tomorrow morning, kid.", false)
		return
	_bubble("Morning. Got some work for you today:", false)
	for c in list_c:
		var prog := ""
		if float(c.goal) > 1.0 and not c.end:
			prog = "  (%s/%s)" % [Rules.money(c.prog) if c.goal >= 100.0 else str(int(c.prog)), Rules.money(c.goal) if c.goal >= 100.0 else str(int(c.goal))]
		var pay := "%s + %d XP" % [Rules.money(c.cash), int(c.xp)]
		_bubble("%s%s\n→ %s%s" % [c.text, prog, pay, "  (at the bell)" if c.end else ""], false,
				Color(0.2, 0.45, 0.25) if c.done else (Color(0.4, 0.12, 0.12) if c.failed else Color(0.2, 0.21, 0.24)))
		if c.done:
			_bubble("Done. Paid. ✓", true)
		elif c.failed:
			_bubble("Blew it.", true)


func _bubble(text: String, mine: bool, col := Color(0.2, 0.21, 0.24)) -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END if mine else BoxContainer.ALIGNMENT_BEGIN
	tony_box.add_child(row)
	var p := PanelContainer.new()
	var st := UI.panel_box(Color(0.1, 0.5, 1.0) if mine else col, Color(0, 0, 0, 0), 14, 0)
	st.set_content_margin_all(9)
	p.add_theme_stylebox_override("panel", st)
	row.add_child(p)
	var l := UI.lbl(text, 16, Color.WHITE)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 150 if mine else 270
	p.add_child(l)


# ------------------------------------------------------------------ HOMES

func _tick_homes() -> void:
	var m = world.match_node
	var me := Net.my_id()
	var mine: String = m.house_of(me)
	var owners: Array = []
	for id in Rules.HOUSES:
		owners.append(m.house_owner(id))
	var sig := "%s|%s|%d" % [mine, str(owners), int(m.cash_of(me) + float(m.my_acct().get("balance", 0.0)))]
	if sig == _sig:
		return
	_sig = sig
	_clear(homes_box)
	var home: Dictionary = world.home_of(me)
	if mine != "":
		homes_box.add_child(_wrap(UI.lbl("HOME: %s, %s" % [Rules.HOUSES[mine].name, Rules.HOUSES[mine].address], 18, Color(0.3, 0.9, 0.4), true)))
		var b := UI.btn("Cab home", Color(0.55, 0.45, 0.08), 17)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func(): _cab("home"))
		homes_box.add_child(b)
	elif not home.is_empty():
		homes_box.add_child(_wrap(UI.lbl("You rent at %s. Buy one and it's yours." % home.address, 17, UI.GOLD, true)))
	homes_box.add_child(UI.lbl("MAGNOLIA HEIGHTS LISTINGS", 16, UI.DIM, true))
	var ids: Array = Rules.HOUSES.keys()
	ids.sort_custom(func(a, b): return Rules.HOUSES[a].price < Rules.HOUSES[b].price)
	for id in ids:
		var h: Dictionary = Rules.HOUSES[id]
		var o: int = m.house_owner(id)
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", UI.panel_box(Color(0.1, 0.11, 0.14), Color(0.3, 0.9, 0.4) if id == mine else Color(0.25, 0.27, 0.32), 12, 2))
		homes_box.add_child(card)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", -2)
		card.add_child(v)
		var top := HBoxContainer.new()
		v.add_child(top)
		var n := UI.lbl(h.name, 18, UI.TEXT, true)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(n)
		top.add_child(UI.lbl(Rules.money(h.price), 18, UI.GOLD, true))
		var status := "YOURS" if o == me else ("SOLD to %s" % Net.player_name(o) if o != 0 else "FOR SALE")
		v.add_child(UI.lbl("%s  ·  %s" % [h.address, status], 14, Color(0.3, 0.9, 0.4) if o == me else (UI.DIM if o != 0 else UI.GREEN)))
	homes_box.add_child(_wrap(UI.lbl("Walk up to a FOR SALE sign in Magnolia Heights to buy.", 14, UI.DIM)))


# ------------------------------------------------------------------ helpers

func _row(box: VBoxContainer, left: String, right: String, col: Color) -> void:
	var h := HBoxContainer.new()
	box.add_child(h)
	var l := UI.lbl(left, 17, UI.TEXT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.clip_text = true
	h.add_child(l)
	h.add_child(UI.lbl(right, 17, col, true))


func _wrap(l: Label) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 320
	return l


func _clear(box: Container) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


func _process(delta: float) -> void:
	_slide = move_toward(_slide, 1.0 if open else 0.0, delta * 5.0)
	var vp := get_viewport_rect().size
	var eased := 1.0 - pow(1.0 - _slide, 3.0)
	frame.size = Vector2(W, H)
	frame.position = Vector2(vp.x - W - 24, vp.y - 110 - eased * (H - 80.0))
	frame.visible = _slide > 0.001
	var hidden: bool = hud != null and hud.is_modal_open()
	badge.text = "[P] PHONE  •  %d new" % _unread if _unread > 0 and not open and not hidden else ""
	if open and world and world.match_node:
		_refresh_t -= delta
		if app == "kwik":
			_tick_kwik(delta)
		elif app == "maps":
			_tick_maps()
		if _refresh_t <= 0.0:
			_refresh_t = 0.5
			match app:
				"home":
					_tick_home()
				"bank":
					_tick_bank()
				"rides":
					_tick_rides()
				"tony":
					_tick_tony()
				"homes":
					_tick_homes()
			clock_lbl.text = _wall_clock()
	_meme_t -= delta
	if _meme_t <= 0.0:
		_meme_t = randf_range(35.0, 60.0)
		post("MEMES", MEMES[randi() % MEMES.size()])
