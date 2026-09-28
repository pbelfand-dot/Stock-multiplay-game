extends PanelContainer
## BAGHOLDER BANK ATM: take cash out of your trading account (co-op: the
## fund) or put it back. Cash on hand counts toward the quota, pays for things
## first, and the cops seize half of it if they catch you with it.

const UI = preload("res://scripts/ui/ui_theme.gd")
const Rules = preload("res://scripts/sim/rules.gd")

signal closed

const SCREEN := Color(0.03, 0.12, 0.1)
const INK := Color(0.45, 1.0, 0.7)

var match_node
var step := 2                     # index into Rules.ATM_STEPS
var acct_lbl: Label
var cash_lbl: Label
var amt_lbl: Label
var msg_lbl: Label
var slot: Control                 # the dispensing animation
var _shown_cash := 0.0            # the cash number counts up/down to the real value
var _bills: Array = []            # [ColorRect, t, dir] sliding out of / into the slot


func setup(m) -> void:
	match_node = m
	m.state_changed.connect(_refresh)
	m.cash_moved.connect(_on_cash_moved)


func _ready() -> void:
	add_theme_stylebox_override("panel", UI.panel_box(Color(0.14, 0.15, 0.17), Color(0.5, 0.52, 0.56), 16, 6))
	UI.center(self, Vector2(640, 600))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	add_child(v)
	var head := UI.lbl("BAGHOLDER BANK", 38, UI.GOLD, true)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(head)
	var scr := PanelContainer.new()
	scr.add_theme_stylebox_override("panel", UI.panel_box(SCREEN, Color(0.08, 0.3, 0.22), 8, 3))
	v.add_child(scr)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 6)
	scr.add_child(sv)
	acct_lbl = UI.lbl("", 24, INK, true)
	sv.add_child(acct_lbl)
	cash_lbl = UI.lbl("", 30, Color(0.95, 1.0, 0.6), true)
	sv.add_child(cash_lbl)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	sv.add_child(row)
	var minus := UI.btn(" - ", Color(0.08, 0.25, 0.18), 26)
	minus.pressed.connect(func(): _step(-1))
	row.add_child(minus)
	amt_lbl = UI.lbl("", 34, UI.GOLD, true)
	amt_lbl.custom_minimum_size.x = 220
	amt_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(amt_lbl)
	var plus := UI.btn(" + ", Color(0.08, 0.25, 0.18), 26)
	plus.pressed.connect(func(): _step(1))
	row.add_child(plus)
	msg_lbl = UI.lbl("", 15, INK)
	msg_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	msg_lbl.custom_minimum_size.x = 560
	sv.add_child(msg_lbl)
	# the cash slot: bills slide out of it (withdraw) or into it (deposit)
	slot = Control.new()
	slot.custom_minimum_size = Vector2(560, 110)
	slot.clip_contents = true
	v.add_child(slot)
	var mouth := ColorRect.new()
	mouth.color = Color(0.02, 0.02, 0.03)
	mouth.position = Vector2(170, 4)
	mouth.size = Vector2(220, 12)
	slot.add_child(mouth)
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 8)
	v.add_child(btns)
	var wd := UI.btn("WITHDRAW", UI.GREEN.darkened(0.3), 24)
	wd.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wd.pressed.connect(func(): _go(1))
	btns.add_child(wd)
	var dp := UI.btn("DEPOSIT", UI.NAVY_2, 24)
	dp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dp.pressed.connect(func(): _go(-1))
	btns.add_child(dp)
	var all := UI.btn("DEPOSIT ALL", UI.NAVY_2, 20)
	all.pressed.connect(func():
		var c: float = match_node.cash_of(Net.my_id())
		if c >= 1.0:
			Sfx.play("click")
			match_node.request_deposit(c))
	btns.add_child(all)
	var bye := UI.btn("TAKE CARD  [ESC]", Color(0.3, 0.1, 0.1), 18)
	bye.pressed.connect(func(): closed.emit())
	v.add_child(bye)
	_shown_cash = match_node.cash_of(Net.my_id()) if match_node else 0.0
	_refresh()


func _step(d: int) -> void:
	step = clampi(step + d, 0, Rules.ATM_STEPS.size() - 1)
	Sfx.play("click")
	_refresh()


func _go(dir: int) -> void:
	var amt: float = Rules.ATM_STEPS[step]
	Sfx.play("click")
	if dir > 0:
		match_node.request_withdraw(amt)
	else:
		match_node.request_deposit(amt)


func _on_cash_moved(peer: int, withdrawn: float, _total: float) -> void:
	if peer != Net.my_id() or not visible:
		return
	var n := clampi(int(log(maxf(absf(withdrawn), 1.0) / 1000.0 + 1.0) * 5.0) + 4, 4, 22)
	var dir := 1 if withdrawn > 0.0 else -1
	for k in n:
		var b := ColorRect.new()
		b.color = Color(0.55, 0.72, 0.5).lerp(Color(0.7, 0.8, 0.62), randf())
		b.size = Vector2(200, 84)
		b.position = Vector2(180, -90 if dir > 0 else 30)
		b.visible = false
		slot.add_child(b)
		_bills.append([b, -k * 0.06, dir])
	Sfx.play("brrt", -3.0)
	if dir < 0:
		Sfx.play("cash", -4.0)


func _process(delta: float) -> void:
	if not visible or match_node == null:
		return
	# the cash number rolls to the real value like a counter
	var real: float = match_node.cash_of(Net.my_id())
	if absf(real - _shown_cash) > 0.5:
		_shown_cash = move_toward(_shown_cash, real, maxf(absf(real - _shown_cash) * delta * 4.0, 50.0))
	else:
		_shown_cash = real
	cash_lbl.text = "CASH ON YOU   %s" % Rules.money(_shown_cash)
	# bills sliding out of (down) / into (up) the slot
	for i in range(_bills.size() - 1, -1, -1):
		var e: Array = _bills[i]
		e[1] += delta
		var t: float = e[1]
		var b: ColorRect = e[0]
		if t < 0.0:
			continue
		b.visible = true
		var k := clampf(t / 0.35, 0.0, 1.0)
		if e[2] > 0:
			b.position.y = lerpf(-90.0, 20.0 + randf() * 2.0, k)
		else:
			b.position.y = lerpf(30.0, -95.0, k)
		if t > (0.9 if e[2] > 0 else 0.4):
			b.queue_free()
			_bills.remove_at(i)


func _refresh() -> void:
	if acct_lbl == null or match_node == null:
		return
	var a: Dictionary = match_node.my_acct()
	var coop: bool = Net.mode == "coop"
	acct_lbl.text = "%s   %s" % ["THE FUND" if coop else "ACCOUNT", Rules.money(a.get("balance", 0.0))]
	amt_lbl.text = Rules.money(Rules.ATM_STEPS[step]).replace(".00", "")
	msg_lbl.text = ("Cash counts toward the quota and pays for things first. %sCops keep %d%% of whatever cash you're carrying if they catch you." % [
			"It's the desk's money: everyone sees what you pull. " if coop else "", int(Rules.CASH_SEIZED * 100.0)])
