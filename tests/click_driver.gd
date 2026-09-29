extends Node
## UI regression: really CLICK the terminal's BUY and SELL buttons with the
## mouse (through the whole HUD/CRT/phone stack) and check trades happen.
##   godot --headless --path . -- --host --autostart --clicktest

var m
var hud


func _ready() -> void:
	_run.call_deferred()


func _say(s: String) -> void:
	print("[click] ", s)


func _done(ok: bool, why := "") -> void:
	_say(("CLICK PASS " if ok else "CLICK FAIL: ") + why)
	Sfx.quit_game(0 if ok else 1)


func _click(b: Control) -> void:
	var p := b.get_global_rect().get_center()
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = p
		ev.global_position = p
		get_viewport().push_input(ev, true)
		await get_tree().process_frame


func _find_btn(root: Node, text: String) -> Button:
	for n in root.find_children("*", "Button", true, false):
		if (n as Button).text == text and n.is_visible_in_tree():
			return n
	return null


func _positions() -> Array:
	return m.my_acct().get("positions", [])


func _run() -> void:
	get_tree().create_timer(40.0).timeout.connect(func(): _done(false, "timeout"))
	while get_node_or_null("/root/Main/World/Match") == null:
		await get_tree().process_frame
	var w = get_node("/root/Main/World")
	m = w.match_node
	hud = w.hud
	while m.phase != "trading":
		await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	hud.open_interact({"type": "terminal", "id": 0})
	for f in 20:
		await get_tree().process_frame
	var buy: Button = hud.terminal.buy_btn
	var sell: Button = hud.terminal.sell_btn
	if buy == null or sell == null or not buy.is_visible_in_tree():
		_done(false, "no BUY/SELL button")
		return
	if not sell.text.begins_with("SHORT") or not buy.text.contains("LONG"):
		_done(false, "with nothing open the buttons should say LONG / SHORT: %s / %s" % [buy.text, sell.text])
		return
	_say("BUY at %s, SELL at %s" % [buy.get_global_rect(), sell.get_global_rect()])
	var mv := InputEventMouseMotion.new()
	mv.position = buy.get_global_rect().get_center()
	mv.global_position = mv.position
	get_viewport().push_input(mv, true)
	await get_tree().process_frame
	var hov := get_viewport().gui_get_hovered_control()
	_say("under the BUY button: %s (%s)" % [hov, hov.get_path() if hov else ""])
	await _click(buy)
	await get_tree().create_timer(0.5).timeout
	var ps := _positions()
	if ps.size() != 1 or ps[0].side != 1:
		_done(false, "clicking BUY didn't open a long: %s" % str(ps))
		return
	_say("BUY click opened a long")
	await get_tree().create_timer(0.3).timeout
	if not sell.text.begins_with("SELL"):
		_done(false, "holding a long, the sell button should say SELL: %s" % sell.text)
		return
	await _click(sell)
	await get_tree().create_timer(0.5).timeout
	ps = _positions()
	if not ps.is_empty():
		_done(false, "clicking SELL didn't sell the long: %s" % str(ps))
		return
	_say("SELL click sold the long")
	await _click(sell)
	await get_tree().create_timer(0.5).timeout
	ps = _positions()
	if ps.size() != 1 or ps[0].side != -1:
		_done(false, "SELL with nothing to sell should open a short: %s" % str(ps))
		return
	_say("SHORT (SELL with no long) opened a short")
	await get_tree().create_timer(0.3).timeout
	if not buy.text.begins_with("BUY BACK"):
		_done(false, "while short, the buy button should say BUY BACK: %s" % buy.text)
		return
	await _click(buy)      # buys the short back
	await get_tree().create_timer(0.5).timeout
	# AUTO-SELL: click + on HIGH twice (+1%) and + on LOW three times (-2%), then BUY
	var plus: Array = []
	for n in hud.terminal.find_children("*", "Button", true, false):
		if (n as Button).text == "+" and n.get_parent() is HBoxContainer and n.get_parent().get_child_count() == 7:
			plus.append(n)
	if plus.size() != 2:
		_done(false, "AUTO row not found")
		return
	for k in 2:
		await _click(plus[0])
	for k in 3:
		await _click(plus[1])
	await _click(buy)
	await get_tree().create_timer(0.5).timeout
	ps = _positions()
	if ps.size() != 1 or ps[0].side != 1:
		_done(false, "BUY with auto-sell didn't open a long: %s" % str(ps))
		return
	var e: float = ps[0].entry
	if absf(ps[0].tp - e * 1.01) > e * 0.0005 or ps[0].sl <= 0.0 or ps[0].sl >= e:
		_done(false, "auto-sell prices wrong: entry %f tp %f sl %f" % [e, ps[0].tp, ps[0].sl])
		return
	_say("auto-sell set: sell at %.2f (high) / %.2f (low), entry %.2f" % [ps[0].tp, ps[0].sl, e])
	if not await _phone_at_terminal():
		return
	_done(true)


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = pressed
		get_viewport().push_input(ev)
		await get_tree().process_frame


## The phone at the terminal: P takes it out and puts it away, ESC puts it
## away (and leaves the terminal up), tapping app icons opens them and doesn't
## trade, and every app draws.
func _phone_at_terminal() -> bool:
	var phone = hud.phone
	var n0 := _positions().size()
	await _key(KEY_P)
	if not phone.open or not hud.terminal.visible:
		_done(false, "P at the terminal didn't take the phone out (open %s, terminal %s)" % [phone.open, hud.terminal.visible])
		return false
	await get_tree().create_timer(0.6).timeout          # it slides up
	await _click(phone.find_child("app_bank", true, false))
	await get_tree().create_timer(0.7).timeout
	if phone.app != "bank" or _positions().size() != n0:
		_done(false, "tapping BANK: app %s, positions %d -> %d" % [phone.app, n0, _positions().size()])
		return false
	_say("P took the phone out at the terminal, tapped BANK")
	for a in ["home", "feed", "kwik", "maps", "rides", "tony", "homes", "bank"]:
		phone.open_app(a)
		for f in 45:
			await get_tree().process_frame
		if phone.app != a:
			_done(false, "couldn't open %s" % a)
			return false
	await _key(KEY_P)
	if phone.open or not hud.terminal.visible:
		_done(false, "P at the terminal didn't put the phone away (open %s, terminal %s)" % [phone.open, hud.terminal.visible])
		return false
	await _key(KEY_P)
	await _key(KEY_ESCAPE)
	if phone.open or not hud.terminal.visible:
		_done(false, "ESC should put the phone away first (open %s, terminal %s)" % [phone.open, hud.terminal.visible])
		return false
	_say("every app opened; P and ESC put the phone away, the terminal stayed up")
	return true
