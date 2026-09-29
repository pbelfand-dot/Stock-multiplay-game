extends CanvasLayer
## Everything on screen while in the office + the modal panels.

const UI = preload("res://scripts/ui/ui_theme.gd")
const Rules = preload("res://scripts/sim/rules.gd")
const Ledger = preload("res://scripts/sim/ledger.gd")
const TerminalScript = preload("res://scripts/ui/terminal.gd")
const SlotsScript = preload("res://scripts/ui/slots_ui.gd")
const ShopScript = preload("res://scripts/ui/shop_ui.gd")
const PopupScript = preload("res://scripts/ui/trade_popup.gd")
const Overlays = preload("res://scripts/ui/overlays.gd")
const PhoneScript = preload("res://scripts/ui/phone.gd")
const CrtFrame = preload("res://scripts/ui/crt_frame.gd")
const MusicDirector = preload("res://scripts/ui/music_director.gd")
const EmoteWheel = preload("res://scripts/ui/emote_wheel.gd")
const DayEvents = preload("res://scripts/sim/day_events.gd")
const Contracts = preload("res://scripts/sim/contracts.gd")

var world
var match_node
var root: Control

var fund_lbl: Label
var quota_lbl: Label
var day_lbl: Label
var time_lbl: Label
var phase_lbl: Label
var heat_bar: ProgressBar
var bp_bar: ProgressBar
var rank_lbl: Label
var rank_banner: Label
var _rank_t := 0.0
var bp_lbl: Label
var bp_vignette: ColorRect
var relief_panel: ColorRect
var relief_lbl: Label
var relief_t := 0.0
var _beat_t := 0.0
var _bp_warned := false
var heat_lbl: Label
var chyron: PanelContainer
var chyron_speaker: Label
var chyron_text: Label
var prompt_lbl: Label
var crosshair: Label
var toasts: VBoxContainer
var inv_box: HBoxContainer
var chat_log: VBoxContainer
var chat_edit: LineEdit
var scoreboard: PanelContainer
var score_body: VBoxContainer
var tip_panel: PanelContainer
var tip_lbl: Label
var jail_lbl: Label
var raid_flash: ColorRect

var terminal
var slots
var shop
var lux_shop
var phone
var music                  # MusicDirector: picks the soundtrack
var emote_wheel            # hold B
var tailor
var crt
var _last_post := ""
var unbox
var popup
var mugshot
var summary
var pause_menu: PanelContainer
var pause_save_lbl: Label

var event_banner: Label           # "DAY 3 — FED DAY" at the opening bell
var _event_t := 0.0
var _banner_day := -1
var contracts_panel: PanelContainer
var contracts_box: VBoxContainer
var _contracts_sig := ""
var _shock_t := 0.0              # red flash while a crash hits
var _chat_open := false
var _last_phase := ""
var _tip_eta := 0.0
var _raid_t := 0.0


func setup(w, m) -> void:
	world = w
	match_node = m
	layer = 5
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UI.theme()
	add_child(root)
	_build_top_bar()
	_build_chyron()
	_build_misc()
	_build_modals()
	m.state_changed.connect(_on_state)
	m.market_tick.connect(_on_tick)
	m.news.connect(_on_news)
	m.news_early.connect(_on_news_early)
	m.tip.connect(_on_tip)
	m.trade_closed.connect(_on_trade_closed)
	m.trade_opened.connect(_on_trade_opened)
	m.arrested.connect(_on_arrested)
	m.released.connect(_on_released)
	m.raid_changed.connect(_on_raid)
	m.day_ended.connect(_on_day_ended)
	m.game_over.connect(_on_day_ended)
	m.toast.connect(show_toast)
	m.error_msg.connect(func(e): show_toast(e, UI.RED))
	m.chat.connect(_on_chat)
	m.luxury_bought.connect(_on_luxury)
	m.relieved.connect(_on_relieved)
	m.ranked_up.connect(_on_rank_up)
	m.posted.connect(_on_posted)
	m.contract_done.connect(_on_contract_done)
	m.shock.connect(_on_shock)
	m.milestone.connect(_on_milestone)
	m.saved.connect(_on_saved)
	music = MusicDirector.new(self)
	add_child(music)
	emote_wheel = EmoteWheel.new(self)
	root.add_child(emote_wheel)
	_on_state()


# ---------------------------------------------------------------- build

func _build_top_bar() -> void:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UI.panel_box(Color(0.04, 0.07, 0.12, 0.85), UI.LINE, 10, 2))
	bar.position = Vector2(16, 12)
	root.add_child(bar)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 26)
	bar.add_child(h)
	fund_lbl = UI.lbl("FUND $0", 30, UI.GREEN, true)
	h.add_child(fund_lbl)
	quota_lbl = UI.lbl("QUOTA $0", 24, UI.GOLD, true)
	h.add_child(quota_lbl)
	day_lbl = UI.lbl("LOBBY", 24, UI.TEXT, true)
	h.add_child(day_lbl)
	time_lbl = UI.lbl("5:00", 30, UI.TEXT, true)
	h.add_child(time_lbl)
	rank_lbl = UI.lbl("INTERN", 22, Color(0.8, 0.7, 1.0), true)
	h.add_child(rank_lbl)
	rank_banner = UI.lbl("", 54, UI.GOLD, true)
	rank_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	rank_banner.offset_left = -500
	rank_banner.offset_right = 500
	rank_banner.offset_top = -260
	rank_banner.offset_bottom = -60
	rank_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rank_banner.add_theme_color_override("font_outline_color", Color.BLACK)
	rank_banner.add_theme_constant_override("outline_size", 14)
	rank_banner.modulate.a = 0.0
	rank_banner.z_index = 10                     # above the day summary / shops
	root.add_child(rank_banner)

	event_banner = UI.lbl("", 30, Color.WHITE, true)
	event_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	event_banner.offset_left = -560
	event_banner.offset_right = 560
	event_banner.offset_top = -300
	event_banner.offset_bottom = -40
	event_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	event_banner.autowrap_mode = TextServer.AUTOWRAP_WORD
	event_banner.add_theme_color_override("font_outline_color", Color.BLACK)
	event_banner.add_theme_constant_override("outline_size", 12)
	event_banner.modulate.a = 0.0
	event_banner.z_index = 10
	root.add_child(event_banner)

	phase_lbl = UI.lbl("", 24, UI.GOLD, true)
	phase_lbl.position = Vector2(20, 72)
	phase_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	phase_lbl.add_theme_constant_override("outline_size", 6)
	root.add_child(phase_lbl)

	# Tony's contracts for today (left side, under the top bar)
	contracts_panel = PanelContainer.new()
	contracts_panel.add_theme_stylebox_override("panel", UI.panel_box(Color(0.1, 0.07, 0.04, 0.8), Color(0.55, 0.4, 0.15), 8, 2))
	contracts_panel.position = Vector2(16, 112)
	contracts_panel.custom_minimum_size.x = 430
	contracts_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	contracts_panel.visible = false
	root.add_child(contracts_panel)
	contracts_box = VBoxContainer.new()
	contracts_box.add_theme_constant_override("separation", 2)
	contracts_panel.add_child(contracts_box)

	var heat_panel := PanelContainer.new()
	heat_panel.add_theme_stylebox_override("panel", UI.panel_box(Color(0.04, 0.07, 0.12, 0.85), UI.LINE, 10, 2))
	heat_panel.anchor_left = 1.0
	heat_panel.anchor_right = 1.0
	heat_panel.offset_left = -320
	heat_panel.offset_right = -16
	heat_panel.offset_top = 12
	root.add_child(heat_panel)
	var heat_box := VBoxContainer.new()
	heat_panel.add_child(heat_box)
	heat_lbl = UI.lbl("HEAT 0", 22, UI.TEXT, true)
	heat_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	heat_box.add_child(heat_lbl)
	heat_bar = ProgressBar.new()
	heat_bar.max_value = Rules.HEAT_MAX
	heat_bar.show_percentage = false
	heat_bar.custom_minimum_size = Vector2(280, 18)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(1, 0.35, 0.1)
	fill.set_corner_radius_all(6)
	heat_bar.add_theme_stylebox_override("fill", fill)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.5)
	bg.set_corner_radius_all(6)
	heat_bar.add_theme_stylebox_override("background", bg)
	heat_box.add_child(heat_bar)
	bp_lbl = UI.lbl("BLOOD PRESSURE", 18, Color(1, 0.55, 0.55), true)
	bp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	heat_box.add_child(bp_lbl)
	bp_bar = ProgressBar.new()
	bp_bar.max_value = Rules.PRESSURE_MAX
	bp_bar.show_percentage = false
	bp_bar.custom_minimum_size = Vector2(280, 12)
	var bfill := StyleBoxFlat.new()
	bfill.bg_color = Color(0.9, 0.1, 0.2)
	bfill.set_corner_radius_all(5)
	bp_bar.add_theme_stylebox_override("fill", bfill)
	bp_bar.add_theme_stylebox_override("background", bg)
	heat_box.add_child(bp_bar)
	jail_lbl = UI.lbl("", 26, UI.RED, true)
	jail_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	heat_box.add_child(jail_lbl)


func _build_chyron() -> void:
	chyron = PanelContainer.new()
	chyron.add_theme_stylebox_override("panel", UI.panel_box(Color(0.02, 0.02, 0.03, 0.88), Color(0, 0, 0, 0), 0, 0))
	chyron.anchor_top = 1.0
	chyron.anchor_bottom = 1.0
	chyron.anchor_right = 1.0
	chyron.offset_top = -64
	chyron.offset_bottom = -8
	chyron.offset_left = 360
	chyron.offset_right = -16
	root.add_child(chyron)
	var h := HBoxContainer.new()
	chyron.add_child(h)
	var live := PanelContainer.new()
	live.add_theme_stylebox_override("panel", UI.panel_box(Color(0.85, 0.05, 0.08), Color(0, 0, 0, 0), 0, 0))
	live.add_child(UI.lbl(" LIVE ", 30, Color.WHITE, true))
	h.add_child(live)
	chyron_speaker = UI.lbl("", 18, UI.GOLD, true)
	h.add_child(chyron_speaker)
	chyron_text = UI.lbl("Waiting for the opening bell...", 28, Color.WHITE, true)
	chyron_text.clip_text = true
	chyron_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(chyron_text)
	chyron.visible = true


func _build_misc() -> void:
	crosshair = UI.lbl("+", 28, Color(1, 1, 1, 0.8), true)
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.position -= Vector2(6, 18)
	root.add_child(crosshair)
	prompt_lbl = UI.lbl("", 26, UI.GOLD, true)
	prompt_lbl.anchor_left = 0.5
	prompt_lbl.anchor_right = 0.5
	prompt_lbl.anchor_top = 0.5
	prompt_lbl.anchor_bottom = 0.5
	prompt_lbl.offset_left = -200
	prompt_lbl.offset_right = 200
	prompt_lbl.offset_top = 30
	prompt_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_lbl.add_theme_constant_override("outline_size", 8)
	prompt_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	root.add_child(prompt_lbl)

	toasts = VBoxContainer.new()
	toasts.anchor_left = 1.0
	toasts.anchor_right = 1.0
	toasts.offset_left = -560
	toasts.offset_right = -20
	toasts.offset_top = 130
	toasts.alignment = BoxContainer.ALIGNMENT_BEGIN
	toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(toasts)

	inv_box = HBoxContainer.new()
	inv_box.anchor_top = 1.0
	inv_box.anchor_bottom = 1.0
	inv_box.offset_top = -70
	inv_box.offset_left = 16
	inv_box.add_theme_constant_override("separation", 4)
	root.add_child(inv_box)

	chat_log = VBoxContainer.new()
	chat_log.anchor_top = 1.0
	chat_log.anchor_bottom = 1.0
	chat_log.offset_top = -330
	chat_log.offset_bottom = -120
	chat_log.offset_left = 16
	chat_log.offset_right = 520
	chat_log.alignment = BoxContainer.ALIGNMENT_END
	chat_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(chat_log)
	chat_edit = LineEdit.new()
	chat_edit.anchor_top = 1.0
	chat_edit.anchor_bottom = 1.0
	chat_edit.offset_top = -116
	chat_edit.offset_bottom = -80
	chat_edit.offset_left = 16
	chat_edit.offset_right = 520
	chat_edit.placeholder_text = "Say something... (Enter to send)"
	chat_edit.visible = false
	chat_edit.text_submitted.connect(_send_chat)
	root.add_child(chat_edit)

	tip_panel = PanelContainer.new()
	tip_panel.add_theme_stylebox_override("panel", UI.panel_box(Color(0.2, 0.05, 0.3, 0.92), Color(0.8, 0.4, 1), 10, 3))
	tip_panel.anchor_left = 0.5
	tip_panel.anchor_right = 0.5
	tip_panel.offset_left = -330
	tip_panel.offset_right = 330
	tip_panel.offset_top = 90
	tip_lbl = UI.lbl("", 24, Color(0.95, 0.85, 1), true)
	tip_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	tip_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip_panel.add_child(tip_lbl)
	tip_panel.visible = false
	root.add_child(tip_panel)

	raid_flash = ColorRect.new()
	raid_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	raid_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	raid_flash.color = Color(1, 0, 0, 0)
	root.add_child(raid_flash)

	scoreboard = PanelContainer.new()
	UI.center(scoreboard, Vector2(700, 420))
	score_body = VBoxContainer.new()
	scoreboard.add_child(score_body)
	scoreboard.visible = false
	root.add_child(scoreboard)



func _build_modals() -> void:
	terminal = TerminalScript.new()
	terminal.setup(match_node)
	terminal.visible = false
	terminal.closed.connect(close_modals)
	root.add_child(terminal)
	crt = CrtFrame.new()
	crt.follower = terminal
	crt.visible = false
	root.add_child(crt)
	slots = SlotsScript.new()
	slots.setup(match_node)
	slots.visible = false
	slots.closed.connect(close_modals)
	root.add_child(slots)
	shop = ShopScript.new()
	shop.setup(match_node)
	shop.visible = false
	shop.closed.connect(close_modals)
	root.add_child(shop)
	lux_shop = ShopScript.new()
	lux_shop.setup(match_node, "luxury")
	lux_shop.visible = false
	lux_shop.closed.connect(close_modals)
	root.add_child(lux_shop)
	unbox = Overlays.Unbox.new()
	root.add_child(unbox)
	phone = PhoneScript.new()
	phone.world = world
	root.add_child(phone)
	# blood pressure: red, pulsing vignette + the restroom fade
	bp_vignette = ColorRect.new()
	bp_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bp_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
uniform float strength = 0.0;
void fragment() {
	float d = distance(UV, vec2(0.5)) * 1.45;
	float v = smoothstep(0.35, 1.0, d) * strength + strength * 0.12;
	COLOR = vec4(0.75, 0.0, 0.03, clamp(v, 0.0, 0.85));
}"""
	var sm := ShaderMaterial.new()
	sm.shader = sh
	bp_vignette.material = sm
	root.add_child(bp_vignette)
	root.move_child(bp_vignette, 0)
	relief_panel = ColorRect.new()
	relief_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	relief_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	relief_panel.color = Color(0.02, 0.02, 0.03, 0.0)
	root.add_child(relief_panel)
	relief_lbl = UI.lbl("", 34, UI.GOLD, true)
	relief_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	relief_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	relief_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	relief_lbl.modulate.a = 0.0
	relief_panel.add_child(relief_lbl)
	summary = Overlays.Summary.new()
	summary.start_pressed.connect(func(): match_node.request_start())
	summary.force_pressed.connect(func(): match_node.request_force_start())
	summary.save_pressed.connect(func(): match_node.request_save())
	summary.close_pressed.connect(close_modals)
	root.add_child(summary)
	mugshot = Overlays.Mugshot.new()
	root.add_child(mugshot)

	pause_menu = PanelContainer.new()
	UI.center(pause_menu, Vector2(620, 540))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	pause_menu.add_child(v)
	v.add_child(UI.lbl("PAUSED (the market isn't)", 34, UI.GOLD, true))
	var resume := UI.btn("RESUME", UI.NAVY_2, 26)
	resume.pressed.connect(close_modals)
	v.add_child(resume)
	if Net.is_server():
		var save := UI.btn("SAVE GAME", UI.GOLD.darkened(0.4), 24)
		save.pressed.connect(func(): match_node.request_save())
		v.add_child(save)
		var force := UI.btn("START THE DAY NOW (skip the ready-up)", UI.RED.darkened(0.4), 20)
		force.pressed.connect(func():
			match_node.request_force_start()
			close_modals())
		v.add_child(force)
	pause_save_lbl = UI.lbl("" if Net.is_server() else "The host keeps the save. Your stuff comes back when you rejoin with the same name.", 15, UI.DIM)
	pause_save_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	v.add_child(pause_save_lbl)
	var sens_row := HBoxContainer.new()
	v.add_child(sens_row)
	sens_row.add_child(UI.lbl("Mouse", 20))
	var sens := HSlider.new()
	sens.min_value = 0.0005
	sens.max_value = 0.008
	sens.step = 0.0001
	sens.value = Config.mouse_sensitivity
	sens.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sens.value_changed.connect(func(val):
		Config.mouse_sensitivity = val
		Config.save_settings())
	sens_row.add_child(sens)
	v.add_child(Music.volume_row(UI.lbl("Music", 20)))
	v.add_child(Graphics.settings_box(UI))
	v.add_child(UI.lbl("WASD move · SHIFT sprint · E interact · 1-6 items\nB emote wheel · H dance · TAB scoreboard · T chat · ENTER (host) start the day\nP phone · In terminal: B buy · S sell · Q/E size · L leverage · C close all", 16, UI.DIM))
	var leave := UI.btn("LEAVE OFFICE", UI.RED.darkened(0.2), 24)
	leave.pressed.connect(func(): get_tree().root.get_node("Main").leave_game())
	v.add_child(leave)
	pause_menu.visible = false
	root.add_child(pause_menu)
	popup = PopupScript.new()
	root.add_child(popup)
	root.move_child(mugshot, -1)


# ---------------------------------------------------------------- modals

func _open_tailor() -> void:
	close_modals()
	tailor = load("res://scripts/ui/tailor.gd").new()
	root.add_child(tailor)
	tailor.done.connect(func():
		Net.set_look(Config.look)
		Config.save_settings()
		tailor.queue_free()
		tailor = null)


func is_modal_open() -> bool:
	return terminal.visible or slots.visible or shop.visible or lux_shop.visible or pause_menu.visible or _chat_open \
			or summary.visible \
			or tailor != null \
			or (world != null and world.get("hood") != null and world.hood.ui_open())   # ---- neighborhood (houses) ----


func close_modals() -> void:
	terminal.visible = false
	slots.visible = false
	shop.visible = false
	lux_shop.visible = false
	crt.visible = false
	pause_menu.visible = false
	if world != null and world.get("hood") != null:   # ---- neighborhood (houses) ----
		world.hood.close_ui()
	if summary.visible:
		summary.visible = false
		if match_node.phase == "intermission":
			Music.clear_event()                 # the payday / bad-day song ends with the summary
	_close_chat()


func open_interact(t: Dictionary) -> void:
	close_modals()
	match t.type:
		"terminal":
			terminal.visible = true
			crt.visible = true
			crt.pop_in()
			terminal._refresh_all()
		"slots":
			slots.visible = true
		"shop":
			shop.set_catalog("items")
			shop.visible = true
		"luxury":
			lux_shop.set_catalog("luxury")
			lux_shop.visible = true
		"lux":   # a street boutique: only that brand's items
			lux_shop.set_catalog("luxury:" + Rules.BOUTIQUES[int(t.id)])
			lux_shop.visible = true
		"pawn":
			lux_shop.set_catalog("pawn")
			lux_shop.visible = true
		"items":   # Tony's Deli on the street
			shop.set_catalog("items", "deli")
			shop.visible = true
		"tailor":
			_open_tailor()


func set_prompt(t: Dictionary) -> void:
	prompt_lbl.text = t.get("prompt", "")


func _process(delta: float) -> void:
	var want_mouse := is_modal_open()
	if not DisplayServer.get_name() == "headless":
		var mm := Input.MOUSE_MODE_VISIBLE if want_mouse else Input.MOUSE_MODE_CAPTURED
		if Input.mouse_mode != mm and get_window().has_focus():
			Input.mouse_mode = mm
	crosshair.visible = not want_mouse
	scoreboard.visible = Input.is_action_pressed("scoreboard") and not _chat_open
	if scoreboard.visible:
		_refresh_scoreboard()
	if tip_panel.visible:
		_tip_eta -= delta
		if _tip_eta < -4.0:
			tip_panel.visible = false
	if not match_node.raid.is_empty():
		_raid_t += delta
		var mine: bool = match_node.raid.get("target", 0) == Net.my_id()
		raid_flash.color = Color(1, 0, 0, (0.12 if mine else 0.05) * (0.5 + 0.5 * sin(_raid_t * 10.0)))
	else:
		raid_flash.color.a = 0.0
	_update_pressure_fx(delta)
	_rank_t = maxf(_rank_t - delta, 0.0)
	rank_banner.modulate.a = clampf(_rank_t, 0.0, 1.0)
	_event_t = maxf(_event_t - delta, 0.0)
	event_banner.modulate.a = clampf(_event_t, 0.0, 1.0)
	if _shock_t > 0.0:
		_shock_t = maxf(_shock_t - delta, 0.0)
		raid_flash.color = Color(1, 0, 0, 0.18 * _shock_t / 3.0 * (0.6 + 0.4 * sin(_shock_t * 18.0)))
	if match_node.phase == "trading":
		phase_lbl.text = _today_line()
	var xp: float = match_node.xp_of(Net.my_id())
	var ri := Rules.rank_of(xp)
	rank_lbl.text = "%s  %d/%s XP" % [Rules.RANKS[ri].name, int(xp), str(Rules.RANKS[ri + 1].xp) if ri + 1 < Rules.RANKS.size() else "MAX"]
	var jl: float = match_node.jail.get(Net.my_id(), 0.0)
	jail_lbl.text = "IN JAIL %ds" % ceili(jl) if jl > 0.0 else ""
	jail_lbl.visible = jl > 0.0


func _unhandled_input(event: InputEvent) -> void:
	if summary.visible and event.is_action_pressed("start_day") and Net.is_server():
		match_node.request_start()              # ENTER on the after-hours summary rings the next bell
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pause"):
		if is_modal_open():
			close_modals()
		else:
			pause_menu.visible = true
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("phone") and not is_modal_open():
		phone.toggle()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("phone_action") and phone.open and phone.app == "kwik" and not is_modal_open():
		world.go_to_studio()
		phone.toggle()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("chat") and not is_modal_open():
		_chat_open = true
		chat_edit.visible = true
		chat_edit.grab_focus.call_deferred()
		get_viewport().set_input_as_handled()


func _send_chat(text: String) -> void:
	if text.strip_edges() != "":
		match_node.send_chat(text)
	chat_edit.text = ""
	_close_chat()


func _close_chat() -> void:
	_chat_open = false
	if chat_edit:
		chat_edit.visible = false
		chat_edit.release_focus()


# ---------------------------------------------------------------- updates

func _on_state() -> void:
	if match_node.phase != _last_phase:
		if match_node.phase == "trading":
			Sfx.play("bell")
		_last_phase = match_node.phase
	var me := Net.my_id()
	var acct_id: int = match_node.acct_for(me)
	var eq: float = match_node.equity_of(acct_id)
	var coop := Net.mode == "coop"
	fund_lbl.text = "%s %s" % ["FUND" if coop else "YOU", Rules.money(eq)]
	quota_lbl.text = "QUOTA %s" % Rules.money(match_node.quota)
	quota_lbl.visible = match_node.phase != "lobby"
	if match_node.phase != "trading":
		phase_lbl.add_theme_color_override("font_color", UI.GOLD)
	match match_node.phase:
		"lobby":
			day_lbl.text = "LOBBY · %s" % ("CO-OP" if coop else "PVP")
			phase_lbl.text = _ready_line("the opening bell") + "   ·   Walk up to a desk and press E"
		"trading":
			day_lbl.text = "DAY %d" % match_node.day
			phase_lbl.text = ""
		"intermission":
			day_lbl.text = "AFTER HOURS"
			phase_lbl.text = "Market closed. " + _ready_line("day %d" % (match_node.day + 1)) \
					+ ("  ·  ESC → SAVE GAME" if Net.is_server() else "")
		"gameover":
			day_lbl.text = "GAME OVER"
			phase_lbl.text = "Host: ENTER to return to lobby" if Net.is_server() else "Waiting for host..."
	if match_node.phase == "trading":
		summary.visible = false
	elif summary.visible:
		summary.update_ready(match_node.day, match_node.ready_up)
	var h: float = match_node.heat.get(me, 0.0)
	heat_bar.value = h
	heat_lbl.text = "HEAT %d" % int(h)
	_refresh_inventory()
	_refresh_contracts()
	if match_node.phase == "trading" and match_node.day != _banner_day:
		_banner_day = match_node.day
		if match_node.day_event != "":
			_show_event_banner()


func _on_tick() -> void:
	_check_margin_calls()
	var t: float = maxf(match_node.time_left, 0.0)
	time_lbl.text = "%d:%02d" % [int(t) / 60, int(t) % 60]
	crt.set_time(t, t < 30 and match_node.phase == "trading")
	time_lbl.add_theme_color_override("font_color", UI.RED if t < 30 and match_node.phase == "trading" else UI.TEXT)
	var acct_id: int = match_node.acct_for(Net.my_id())
	var eq: float = match_node.equity_of(acct_id)
	fund_lbl.text = "%s %s" % ["FUND" if Net.mode == "coop" else "YOU", Rules.money(eq)]
	fund_lbl.add_theme_color_override("font_color", UI.GREEN if eq >= match_node.quota or match_node.phase == "lobby" else UI.GOLD)
	var h: float = match_node.heat.get(Net.my_id(), 0.0)
	heat_bar.value = h
	var bp: float = match_node.pressure_of(Net.my_id())
	bp_bar.value = bp
	bp_lbl.text = "BLOOD PRESSURE %d%s" % [int(bp), "  → RESTROOM!" if bp >= Rules.PRESSURE_WOBBLY else ""]
	if bp >= Rules.PRESSURE_RED and not _bp_warned:
		_bp_warned = true
		show_toast("Blood pressure rising. Mark Hanna's prescription: twice a day, minimum. Restroom's by the whiteboard.", Color(1, 0.55, 0.55))
	elif bp < 10.0:
		_bp_warned = false
	heat_lbl.text = "HEAT %d" % int(h)
	if terminal.visible:
		terminal._refresh_prices()


func _refresh_inventory() -> void:
	for c in inv_box.get_children():
		c.queue_free()
	var me := Net.my_id()
	var i := 0
	for key in Rules.ITEMS:
		i += 1
		var n: int = match_node.item_count(me, key)
		var active: float = match_node.effect_left(me, key)
		if n <= 0 and active <= 0.0:
			continue
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", UI.panel_box(Color(0, 0, 0, 0.6), UI.GOLD if active > 0 else UI.LINE, 6, 2))
		var txt := "[%d] %s x%d" % [i, Rules.ITEMS[key].name, n]
		if active > 0.0:
			txt += "  (%ds)" % ceili(active)
		p.add_child(UI.lbl(txt, 18, UI.GOLD if active > 0 else UI.TEXT, true))
		inv_box.add_child(p)


func _refresh_scoreboard() -> void:
	for c in score_body.get_children():
		c.queue_free()
	score_body.add_child(UI.lbl("THE DESK", 36, UI.GOLD, true))
	for id in Net.players:
		var st: Dictionary = match_node.stats.get(id, {})
		var line := "%s [%s]   heat %d   P&L today %s   trades %d   arrests %d" % [
			Net.player_name(id), Rules.rank_name(match_node.xp_of(id)), int(match_node.heat.get(id, 0.0)), Rules.money(st.get("pnl_day", 0.0)),
			st.get("trades", 0), st.get("arrests", 0)]
		if Net.mode == "pvp":
			line += "   equity %s" % Rules.money(match_node.equity_of(id))
		score_body.add_child(UI.lbl(line, 20, UI.GREEN if id == Net.my_id() else UI.TEXT))


func show_toast(msg: String, color: Color = UI.TEXT) -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.panel_box(Color(0, 0, 0, 0.7), Color(0, 0, 0, 0), 6, 0))
	var l := UI.lbl(msg, 20, color, true)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.custom_minimum_size.x = 520
	p.add_child(l)
	toasts.add_child(p)
	while toasts.get_child_count() > 6:
		toasts.get_child(0).free()
	var pid := p.get_instance_id()   # capture an id, not the node: older toasts get freed early
	get_tree().create_timer(5.0).timeout.connect(func():
		var o = instance_from_id(pid)
		if o:
			o.queue_free())


func _on_posted(ev: Dictionary) -> void:
	_last_post = ev.headline
	phone.post_news(ev)
	if not phone.open:
		show_toast("NEW POST — @realDonnyTramp   [P] check your phone", UI.GOLD)


func _on_news(ev: Dictionary) -> void:
	if ev.headline != _last_post:
		phone.post_news(ev)
	Sfx.play("news", -2.0)
	chyron_speaker.text = " %s " % ev.role
	chyron_text.text = ev.headline
	show_toast("ON AIR: " + ev.headline, UI.GOLD)


func _on_news_early(ev: Dictionary) -> void:
	var src := "THE NOSE KNOWS" if ev.get("src", "powder") == "powder" else "ON YOUR TERMINAL"
	tip_lbl.text = "%s (%ds early):\n%s" % [src, int(ev.get("lead", 6.0)), ev.headline]
	tip_panel.visible = true
	_tip_eta = float(ev.get("lead", 6.0))


func _on_tip(hint: String, eta: float) -> void:
	tip_lbl.text = "INSIDER TIP: next headline in %ds\n%s" % [int(eta), hint]
	tip_panel.visible = true
	_tip_eta = eta


func _on_trade_opened(info: Dictionary) -> void:
	if info.acct == match_node.acct_for(Net.my_id()) and info.pos.get("trader_id", 0) != Net.my_id():
		var p: Dictionary = info.pos
		show_toast("%s opened %s %s x%d with %s" % [info.trader, "LONG" if p.side > 0 else "SHORT", p.sym, p.lev, Rules.money(p.margin)], UI.DIM)


func _on_trade_closed(info: Dictionary) -> void:
	if info.acct == match_node.acct_for(Net.my_id()):
		var trig: String = info.get("trigger", "")
		popup.show_trade(info.pnl, info.pct, info.liquidated, "%s %s%s" % [info.trader, info.sym,
				("  · %s HIT" % trig) if trig != "" else ""])
		if info.liquidated:
			Sfx.play("liquidated")
		elif info.pnl >= 0.0:
			Sfx.play("cash", 0.0, 1.0 + clampf(info.pct / 400.0, 0.0, 0.3))
		else:
			Sfx.play("lose", -3.0)
	elif Net.mode == "pvp" and absf(info.pct) > 150:
		show_toast("%s %s %s on %s" % [info.trader, "cooked" if info.pnl > 0 else "got cooked for", Rules.money(absf(info.pnl)), info.sym], UI.DIM)


func _on_arrested(peer: int, booking_no: int) -> void:
	if peer == Net.my_id():
		close_modals()
		var p = world.player_node(peer)
		var look: Dictionary = p.look if p else {}
		mugshot.play(booking_no, Net.player_name(peer), look)


func _on_released(peer: int) -> void:
	if peer == Net.my_id():
		show_toast("Released on bail. Don't do it again (do it again).", UI.GREEN)


func _on_raid(target: int, active: bool) -> void:
	_raid_t = 0.0
	if active and target == Net.my_id():
		close_modals()
		show_toast("THE COPS ARE COMING FOR YOU. RUN! (Shift) — or make it rain to distract them.", UI.RED)


func _on_day_ended(s: Dictionary) -> void:
	close_modals()
	if s.get("over", false) and not s.get("passed", true):
		Sfx.play("lose")
	elif s.get("passed", false):
		Sfx.play("jackpot")
	summary.show_summary(s)


## MARGIN CALL: warn once per trade when it's 70% of the way to liquidation.
var _warned := {}


func _check_margin_calls() -> void:
	for pos in match_node.my_acct().get("positions", []):
		if pos.get("trader_id", Net.my_id()) != Net.my_id() or _warned.has(pos.pid):
			continue
		var pnl: float = Ledger.pnl_of(pos, match_node.price_of(pos.sym))
		if pnl <= -0.7 * pos.margin:
			_warned[pos.pid] = true
			Sfx.play("news", 0.0, 1.3)
			show_toast("MARGIN CALL: %s x%d is %d%% down. SELL it or it gets wiped out!" % [
					pos.sym, pos.lev, int(-pnl / pos.margin * 100.0)], UI.RED)


## True while you're busy in the restroom (World blocks movement).
func busy() -> bool:
	return relief_t > 0.0


func _update_pressure_fx(delta: float) -> void:
	var bp: float = match_node.pressure_of(Net.my_id())
	var k := clampf((bp - Rules.PRESSURE_RED) / (Rules.PRESSURE_MAX - Rules.PRESSURE_RED), 0.0, 1.0)
	_beat_t -= delta
	var pulse := 0.0
	if k > 0.0 and relief_t <= 0.0:
		if _beat_t <= 0.0:
			_beat_t = lerpf(1.3, 0.55, k)
			Sfx.play("heartbeat", lerpf(-14.0, -2.0, k))
		pulse = maxf(0.0, _beat_t - lerpf(1.3, 0.55, k) + 0.25) * 2.0
	(bp_vignette.material as ShaderMaterial).set_shader_parameter("strength", k * (0.75 + 0.25 * pulse))
	if relief_t > 0.0:
		relief_t -= delta
		var a := clampf(minf(relief_t, Rules.RELIEF_SECONDS - relief_t) * 3.0, 0.0, 1.0)
		relief_panel.color.a = a
		relief_lbl.modulate.a = a


func _on_rank_up(peer: int, rank: int) -> void:
	var r: Dictionary = Rules.RANKS[rank]
	if peer == Net.my_id():
		Sfx.play("jackpot")
		rank_banner.text = "RANK UP\n%s\n%s" % [r.name, r.unlock]
		rank_banner.modulate.a = 1.0
		_rank_t = 5.0
	else:
		show_toast("%s ranked up to %s" % [Net.player_name(peer), r.name], UI.GOLD)


func _on_relieved(peer: int, line: String) -> void:
	if peer == Net.my_id():
		close_modals()
		relief_t = Rules.RELIEF_SECONDS
		relief_lbl.text = "*chest thump*  mm-MM  mm-mm\n\n\"%s\"" % line
		Sfx.play("hum")
	else:
		show_toast("%s is in the restroom. Keeping the blood flowing." % Net.player_name(peer), UI.DIM)


func _on_luxury(peer: int, key: String) -> void:
	if peer == Net.my_id() and key.begins_with("roflex"):   # Crownwell watches
		unbox.play(key == "roflex_iced")


func _on_chat(from_name: String, msg: String) -> void:
	var l := UI.lbl("%s: %s" % [from_name, msg], 18, Color.WHITE, true)
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	chat_log.add_child(l)
	while chat_log.get_child_count() > 8:
		chat_log.get_child(0).free()
	get_tree().create_timer(15.0).timeout.connect(func():
		if is_instance_valid(l):
			l.queue_free())


# ---------------------------------------------------------------- day events + contracts

## The line under the top bar during the day: today's event, countdowns, halts.
func _today_line() -> String:
	var m = match_node
	if m.halt > 0.0:
		phase_lbl.add_theme_color_override("font_color", UI.RED)
		return "CIRCUIT BREAKER — TRADING HALTED %ds" % ceili(m.halt)
	if m.day_event == "":
		return ""
	var e: Dictionary = DayEvents.info(m.day_event)
	phase_lbl.add_theme_color_override("font_color", e.get("color", UI.GOLD))
	var line := "TODAY: %s" % e.name
	if m.event_at >= 0.0:
		var left: float = m.time_left - m.event_at
		if left > 0.0:
			line += "  ·  %s IN %s" % ["POWWW SPEAKS" if m.day_event == "fed_day" else "REX REPORTS", DayEvents.clock(left)]
	match m.day_event:
		"black_friday":
			line += "  ·  boutiques %d%% off" % int(DayEvents.mod("black_friday", "lux_discount", 0.0) * 100.0)
		"crackdown":
			line += "  ·  cops come at %d heat" % int(m.raid_threshold())
	return line


func _show_event_banner() -> void:
	var e: Dictionary = DayEvents.info(match_node.day_event)
	event_banner.text = "DAY %d\n%s\n%s" % [match_node.day, e.name, e.blurb]
	event_banner.add_theme_color_override("font_color", e.get("color", UI.GOLD))
	event_banner.add_theme_font_size_override("font_size", 30)
	_event_t = 7.0
	Sfx.play("news", 0.0, 0.8)


func _refresh_contracts() -> void:
	var mine: Array = match_node.contracts.get(Net.my_id(), [])
	contracts_panel.visible = not mine.is_empty() and match_node.phase == "trading"
	var sig := str(mine)
	if sig == _contracts_sig:
		return
	_contracts_sig = sig
	for c in contracts_box.get_children():
		c.queue_free()
	contracts_box.add_child(UI.lbl("TONY'S CONTRACTS", 18, UI.GOLD, true))
	for c in mine:
		var col: Color = UI.GREEN if c.done else (UI.RED if c.failed else UI.TEXT)
		var mark := "✓" if c.done else ("✗" if c.failed else "•")
		var prog := Contracts.progress_text(c)
		var l := UI.lbl("%s %s%s   %s" % [mark, c.text, ("  (%s)" % prog) if prog != "" and not c.done and not c.failed else "",
				Rules.money(c.cash)], 16, col, c.done)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD
		l.custom_minimum_size.x = 420
		contracts_box.add_child(l)


func _on_contract_done(peer: int, c: Dictionary, cash: float) -> void:
	if peer == Net.my_id():
		Sfx.play("cash")
		show_toast("CONTRACT DONE: %s  +%s  +%d XP" % [c.text, Rules.money(cash), int(c.xp)], UI.GREEN)
	elif Net.mode == "coop":
		show_toast("%s finished a contract: +%s to the fund" % [Net.player_name(peer), Rules.money(cash)], UI.DIM)


func _on_shock(kind: String, stage: String) -> void:
	match [kind, stage]:
		["crash", "warn"]:
			Sfx.play("siren", -4.0)
			show_toast("SIRENS ON WALL ST. Something is about to break.", UI.RED)
		["crash", "hit"]:
			_shock_t = 3.0
			Sfx.play("liquidated", -2.0)
		["crash", "halt"]:
			Sfx.play("bell", 0.0, 0.7)
		["crash", "reopen"]:
			Sfx.play("bell")
		["fed", "warn"], ["earnings", "warn"]:
			show_toast(("POWWW TAKES THE PODIUM IN 30 SECONDS. Pick a side." if kind == "fed"
					else "REX EARNINGS IN 30 SECONDS. Beat or miss?"), UI.GOLD)
		["fed", "hit"], ["earnings", "hit"]:
			Sfx.play("news", 2.0, 0.9)


func _on_milestone(amount: float, xp: float) -> void:
	Sfx.play("jackpot")
	rank_banner.text = "THE FUND HIT %s\n+%d XP FOR THE WHOLE DESK" % [Rules.money(amount), int(xp)]
	rank_banner.modulate.a = 1.0
	_rank_t = 5.0


func _on_saved(info: Dictionary) -> void:
	var txt: String = Overlays.Summary.saved_text(info)
	summary.show_saved(info)
	pause_save_lbl.text = txt
	pause_save_lbl.add_theme_color_override("font_color", UI.RED if info.has("error") else UI.GREEN)
	show_toast(txt, UI.RED if info.has("error") else UI.GREEN)
	if not info.has("error"):
		Sfx.play("coin")


## "Press ENTER when you're ready for day 3 (1/2 ready)" / "✓ You're ready, waiting on Bob".
func _ready_line(what: String) -> String:
	var m = match_node
	var n: int = Net.players.size()
	if m.ready_up.has(Net.my_id()):
		var waiting: Array = []
		for id in Net.players:
			if not m.ready_up.has(id):
				waiting.append(Net.player_name(id))
		return "✓ READY for %s, waiting on %s (ENTER to cancel)" % [what, ", ".join(waiting)]
	if n <= 1:
		return "Press ENTER for %s" % what
	return "Press ENTER when you're ready for %s (%d/%d ready)" % [what, m.ready_count(), n]
