extends PanelContainer
## The trading terminal from the trailer: chart + watchlist + order panel +
## positions + MY SESSION. Opened from any desk CRT.

const UI = preload("res://scripts/ui/ui_theme.gd")
const Rules = preload("res://scripts/sim/rules.gd")
const Ledger = preload("res://scripts/sim/ledger.gd")
const ChartScript = preload("res://scripts/ui/chart.gd")
const CrtFrame = preload("res://scripts/ui/crt_frame.gd")

signal closed

var match_node
var sym := "BTC"
var size_idx := 2
var lev_idx := 5
var closed_trades: Array = []
var last_trade := 0.0
var show_closed := false

var chart
var title_lbl: Label
var mode_tag: Label
var watch_rows := {}     # sym -> {btn, price, chg}
var asset_name: Label
var asset_kind: Label
var price_lbl: Label
var chg_lbl: Label
var size_lbl: Label
var lev_btn: Button
var open_tab: Button
var closed_tab: Button
var rows_box: VBoxContainer
var open_profit_lbl: Label
var last_trade_lbl: Label
var balance_lbl: Label
var pen_btn: Button


func setup(m) -> void:
	match_node = m
	m.market_tick.connect(_refresh_prices)
	m.market_full.connect(_refresh_all)
	m.state_changed.connect(_refresh_all)
	m.trade_closed.connect(_on_trade_closed)


func _ready() -> void:
	# the CRT's dark glass; CrtFrame draws the beige bezel over the edges
	var glass := UI.panel_box(Color(0.06, 0.1, 0.16), Color(0.06, 0.1, 0.16), 0, 0)
	glass.content_margin_left = 26
	glass.content_margin_right = 26
	glass.content_margin_top = 18
	glass.content_margin_bottom = 16
	add_theme_stylebox_override("panel", glass)
	var hole: Rect2 = CrtFrame.HOLE
	anchor_left = hole.position.x
	anchor_top = hole.position.y
	anchor_right = hole.end.x
	anchor_bottom = hole.end.y
	offset_left = 0
	offset_top = 0
	offset_right = 0
	offset_bottom = 0
	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	add_child(root)

	# ---------------- left column ----------------
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 2.6
	root.add_child(left)
	var head := HBoxContainer.new()
	left.add_child(head)
	mode_tag = UI.lbl(" Free Mode ", 20, Color.BLACK, true)
	var tag_bg := PanelContainer.new()
	tag_bg.add_theme_stylebox_override("panel", UI.panel_box(UI.GOLD, UI.GOLD, 4, 1))
	tag_bg.add_child(mode_tag)
	head.add_child(tag_bg)
	pen_btn = UI.btn("PEN", UI.NAVY_2, 16)
	pen_btn.toggle_mode = true
	pen_btn.toggled.connect(func(on): chart.pen_enabled = on)
	head.add_child(pen_btn)
	var trash := UI.btn("CLEAR", UI.NAVY_2, 16)
	trash.pressed.connect(func(): chart.clear_drawings())
	head.add_child(trash)
	var vol := UI.btn("VOL", UI.NAVY_2, 16)
	vol.toggle_mode = true
	vol.button_pressed = true
	vol.toggled.connect(func(on):
		chart.show_volume = on
		chart.queue_redraw())
	head.add_child(vol)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	title_lbl = UI.lbl("BTC", 24, UI.TEXT, true)
	head.add_child(title_lbl)

	chart = ChartScript.new()
	chart.match_node = match_node
	chart.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chart.size_flags_stretch_ratio = 2.2
	left.add_child(chart)

	var pos_panel := PanelContainer.new()
	pos_panel.add_theme_stylebox_override("panel", UI.panel_box(UI.NAVY, UI.LINE, 8, 2))
	pos_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(pos_panel)
	var pv := VBoxContainer.new()
	pos_panel.add_child(pv)
	var tabs := HBoxContainer.new()
	pv.add_child(tabs)
	open_tab = UI.btn("OPEN 0", UI.GOLD.darkened(0.3), 16)
	open_tab.pressed.connect(func():
		show_closed = false
		_refresh_rows())
	tabs.add_child(open_tab)
	closed_tab = UI.btn("CLOSED 0", UI.NAVY_2, 16)
	closed_tab.pressed.connect(func():
		show_closed = true
		_refresh_rows())
	tabs.add_child(closed_tab)
	var sp2 := Control.new()
	sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.add_child(sp2)
	var close_all := UI.btn("Close All", UI.NAVY_2, 16)
	close_all.pressed.connect(func(): match_node.request_close_all())
	tabs.add_child(close_all)
	pv.add_child(_row(["Asset", "Side", "Margin", "Units", "Profit", "Fees", "Trader", ""], UI.DIM))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pv.add_child(scroll)
	rows_box = VBoxContainer.new()
	rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows_box)

	# ---------------- right column ----------------
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 5)
	root.add_child(right)
	var wl := PanelContainer.new()
	wl.add_theme_stylebox_override("panel", UI.panel_box(UI.NAVY, UI.LINE, 8, 2))
	right.add_child(wl)
	var wv := VBoxContainer.new()
	wl.add_child(wv)
	for d in preload("res://scripts/sim/market.gd").ASSET_DEFS:
		var b := Button.new()
		b.flat = true
		b.custom_minimum_size.y = 29
		var hb := HBoxContainer.new()
		hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(hb)
		var s := UI.lbl(d.sym, 20, UI.TEXT, true)
		s.custom_minimum_size.x = 80
		hb.add_child(s)
		var p := UI.lbl("-", 20)
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		p.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		hb.add_child(p)
		var c := UI.lbl("-", 18)
		c.custom_minimum_size.x = 80
		c.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		hb.add_child(c)
		var sym_copy: String = d.sym
		b.pressed.connect(func(): select(sym_copy))
		wv.add_child(b)
		watch_rows[d.sym] = {"btn": b, "price": p, "chg": c}

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UI.panel_box(UI.NAVY, UI.LINE, 8, 2))
	right.add_child(card)
	var cv := VBoxContainer.new()
	card.add_child(cv)
	asset_name = UI.lbl("Bitcoin", 28, UI.TEXT, true)
	cv.add_child(asset_name)
	asset_kind = UI.lbl("BTC | Crypto", 18, UI.DIM)
	cv.add_child(asset_kind)
	var ph := HBoxContainer.new()
	cv.add_child(ph)
	price_lbl = UI.lbl("$0", 30, UI.TEXT, true)
	ph.add_child(price_lbl)
	chg_lbl = UI.lbl("+0.00%", 20, Color.BLACK, true)
	var chg_bg := PanelContainer.new()
	chg_bg.name = "ChgBg"
	chg_bg.add_child(chg_lbl)
	chg_bg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ph.add_child(chg_bg)
	var sz := HBoxContainer.new()
	cv.add_child(sz)
	var minus := UI.btn(" - ", UI.NAVY_2, 26)
	minus.pressed.connect(func(): _step_size(-1))
	sz.add_child(minus)
	var sz_bg := PanelContainer.new()
	sz_bg.add_theme_stylebox_override("panel", UI.panel_box(Color(0.25, 0.2, 0.05), UI.GOLD, 6, 2))
	sz_bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sz.add_child(sz_bg)
	size_lbl = UI.lbl("$10K", 26, UI.GOLD, true)
	size_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sz_bg.add_child(size_lbl)
	var plus := UI.btn(" + ", UI.NAVY_2, 26)
	plus.pressed.connect(func(): _step_size(1))
	sz.add_child(plus)
	var orders := HBoxContainer.new()
	cv.add_child(orders)
	var buy := UI.btn("BUY", UI.GREEN.darkened(0.15), 26)
	buy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buy.pressed.connect(func(): _order(1))
	orders.add_child(buy)
	lev_btn = UI.btn("x100", Color(0.25, 0.2, 0.05), 24)
	lev_btn.pressed.connect(_cycle_lev)
	orders.add_child(lev_btn)
	var sell := UI.btn("SELL", UI.RED.darkened(0.1), 26)
	sell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sell.pressed.connect(func(): _order(-1))
	orders.add_child(sell)

	var sess := PanelContainer.new()
	sess.add_theme_stylebox_override("panel", UI.panel_box(UI.NAVY, UI.LINE, 8, 2))
	sess.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(sess)
	var sv := VBoxContainer.new()
	sess.add_child(sv)
	sv.add_child(UI.lbl("MY SESSION", 24, UI.TEXT, true))
	sv.add_child(UI.lbl("OPEN PROFIT", 14, UI.DIM))
	open_profit_lbl = UI.lbl("$0", 34, UI.GOLD, true)
	sv.add_child(open_profit_lbl)
	var lt := HBoxContainer.new()
	sv.add_child(lt)
	lt.add_child(UI.lbl("LAST TRADE", 18, UI.GOLD, true))
	last_trade_lbl = UI.lbl("$0", 18, UI.GOLD, true)
	last_trade_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	last_trade_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lt.add_child(last_trade_lbl)
	balance_lbl = UI.lbl("CASH $0", 18, UI.DIM)
	sv.add_child(balance_lbl)
	var spv := Control.new()
	spv.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sv.add_child(spv)
	var close_btn := UI.btn("LOG OFF  [ESC]", UI.NAVY_2, 18)
	close_btn.pressed.connect(func(): closed.emit())
	sv.add_child(close_btn)

	select("BTC")
	_update_size_labels()


func _row(cols: Array, color: Color) -> HBoxContainer:
	var h := HBoxContainer.new()
	for c in cols:
		var l := UI.lbl(str(c), 16, color)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.clip_text = true
		h.add_child(l)
	return h


func select(s: String) -> void:
	sym = s
	chart.sym = s
	chart.clear_drawings()
	_refresh_all()


func _step_size(d: int) -> void:
	size_idx = clampi(size_idx + d, 0, Rules.SIZE_STEPS.size() - 1)
	_update_size_labels()


func _cycle_lev() -> void:
	lev_idx = (lev_idx + 1) % Ledger.LEVERAGES.size()
	_update_size_labels()


func _update_size_labels() -> void:
	var v: float = Rules.SIZE_STEPS[size_idx]
	size_lbl.text = Rules.money(v).replace(".00", "")
	lev_btn.text = "x%d" % Ledger.LEVERAGES[lev_idx]


func _order(side: int) -> void:
	Sfx.play("click")
	match_node.request_open(sym, side, Rules.SIZE_STEPS[size_idx], Ledger.LEVERAGES[lev_idx])


func _on_trade_closed(info: Dictionary) -> void:
	if info.acct != match_node.acct_for(Net.my_id()):
		return
	closed_trades.push_front(info)
	if closed_trades.size() > 40:
		closed_trades.pop_back()
	last_trade = info.pnl
	_refresh_all()


func _refresh_all() -> void:
	if not is_inside_tree():
		return
	var a: Dictionary = match_node.asset_mirror(sym)
	if not a.is_empty():
		asset_name.text = a.name
		asset_kind.text = "%s | %s" % [a.sym, a.kind]
		title_lbl.text = "%s / USD" % a.sym
	mode_tag.text = " Free Mode " if match_node.phase != "trading" else " DAY %d " % match_node.day
	_refresh_prices()
	_refresh_rows()


func _refresh_prices() -> void:
	if not visible:
		return
	for a in match_node.m_assets:
		if not watch_rows.has(a.sym):
			continue
		var r: Dictionary = watch_rows[a.sym]
		var ch: float = (a.price / a.open_day - 1.0) * 100.0
		r.price.text = Rules.price_str(a.price)
		r.chg.text = "%+.2f%%" % ch
		r.chg.add_theme_color_override("font_color", UI.GREEN if ch >= 0 else UI.RED)
		r.btn.add_theme_stylebox_override("normal", UI.panel_box(Color(0.25, 0.2, 0.05) if a.sym == sym else Color(0, 0, 0, 0), UI.GOLD if a.sym == sym else Color(0, 0, 0, 0), 6, 2))
		if a.sym == sym:
			price_lbl.text = "$" + Rules.price_str(a.price)
			chg_lbl.text = " %+.2f%% " % ch
			var bg: PanelContainer = chg_lbl.get_parent()
			bg.add_theme_stylebox_override("panel", UI.panel_box(UI.GREEN if ch >= 0 else UI.RED, Color(0, 0, 0, 0), 5, 0))
	var acct_id: int = match_node.acct_for(Net.my_id())
	var acct: Dictionary = match_node.accounts.get(acct_id, {})
	var op := 0.0
	for pos in acct.get("positions", []):
		op += maxf(Ledger.pnl_of(pos, match_node.price_of(pos.sym)), -pos.margin)
	open_profit_lbl.text = ("+" if op >= 0 else "") + Rules.money(op)
	open_profit_lbl.add_theme_color_override("font_color", UI.GREEN if op > 0 else (UI.RED if op < 0 else UI.GOLD))
	last_trade_lbl.text = Rules.money(last_trade)
	balance_lbl.text = "CASH %s   |   EQUITY %s" % [Rules.money(acct.get("balance", 0.0)), Rules.money(match_node.equity_of(acct_id))]
	chart.queue_redraw()
	if not show_closed:
		_update_open_profits(acct)


func _refresh_rows() -> void:
	if rows_box == null:
		return
	for c in rows_box.get_children():
		c.queue_free()
	var acct: Dictionary = match_node.my_acct()
	var positions: Array = acct.get("positions", [])
	open_tab.text = "OPEN %d" % positions.size()
	closed_tab.text = "CLOSED %d" % closed_trades.size()
	if show_closed:
		for t in closed_trades:
			var r := _row([t.sym, "LONG" if t.side > 0 else "SHORT", "x%d" % t.lev, "",
				("+" if t.pnl >= 0 else "") + Rules.money(t.pnl) + (" LIQ" if t.liquidated else ""),
				"%+.0f%%" % t.pct, t.trader, ""], UI.GREEN if t.pnl >= 0 else UI.RED)
			rows_box.add_child(r)
		return
	for pos in positions:
		var r := _row([pos.sym, "LONG" if pos.side > 0 else "SHORT", Rules.money(pos.margin),
			"%.3f" % pos.units, "", Rules.money(pos.fee), pos.trader, ""], UI.TEXT)
		r.set_meta("pid", pos.pid)
		var x := UI.btn("CLOSE", UI.RED.darkened(0.2), 14)
		var pid: int = pos.pid
		x.pressed.connect(func(): match_node.request_close(pid))
		r.get_child(7).queue_free()
		# one-click TP (+50% on margin) / SL (-30%); drag the lines on the chart to fine-tune
		var move: float = pos.margin / pos.units
		var tpb := UI.btn("TP" if pos.get("tp", 0.0) <= 0.0 else "TP ✓", UI.GREEN.darkened(0.35), 14)
		tpb.pressed.connect(func(): match_node.request_set_tpsl(pid, pos.entry + pos.side * move * 0.5, pos.sl))
		var slb := UI.btn("SL" if pos.get("sl", 0.0) <= 0.0 else "SL ✓", UI.RED.darkened(0.45), 14)
		slb.pressed.connect(func(): match_node.request_set_tpsl(pid, pos.tp, pos.entry - pos.side * move * 0.3))
		r.add_child(tpb)
		r.add_child(slb)
		r.add_child(x)
		rows_box.add_child(r)
	_update_open_profits(acct)


func _update_open_profits(acct: Dictionary) -> void:
	var positions: Array = acct.get("positions", [])
	for r in rows_box.get_children():
		if not r.has_meta("pid") or r.is_queued_for_deletion():
			continue
		for pos in positions:
			if pos.pid == r.get_meta("pid"):
				var pnl: float = maxf(Ledger.pnl_of(pos, match_node.price_of(pos.sym)), -pos.margin)
				var l: Label = r.get_child(4)
				l.text = "%s (%+.0f%%)" % [("+" if pnl >= 0 else "") + Rules.money(pnl), pnl / pos.margin * 100.0]
				l.add_theme_color_override("font_color", UI.GREEN if pnl >= 0 else UI.RED)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_B:
				_order(1)
			KEY_S:
				_order(-1)
			KEY_Q:
				_step_size(-1)
			KEY_E:
				_step_size(1)
			KEY_L:
				_cycle_lev()
			KEY_C:
				match_node.request_close_all()
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6:
				var i: int = event.physical_keycode - KEY_1
				select(match_node.m_assets[i].sym)
			_:
				return
		get_viewport().set_input_as_handled()
