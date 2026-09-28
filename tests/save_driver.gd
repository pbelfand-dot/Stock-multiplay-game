extends Node
## Save -> continue, end to end (two headless runs, see tests/run_all.sh):
##   --savecheck=1 --host --autostart --day_seconds=3 : play a day, the closing
##                  bell must write a save with the fund and the player's items
##   --savecheck=2 --host : CONTINUE that save; day/fund/items must come back,
##                  and ringing the bell must start the NEXT day.
##   --savecheck=3 --host --name=Bob : someone else can't load Trader's save.
## Uses its own save folder so real saves are never touched.

const SaveGame = preload("res://scripts/net/save_game.gd")
const Rules = preload("res://scripts/sim/rules.gd")
const DIR := "user://savecheck"

var phase := ""


func _init() -> void:
	phase = str(Config.cli.get("savecheck", "1"))
	SaveGame.dir_override = DIR
	if phase == "1":
		for s in SaveGame.list():            # start clean
			SaveGame.remove(str(s.slot))
	else:
		var last := SaveGame.latest_open()
		Config.load_slot = str(last.get("slot", ""))
		_slot = Config.load_slot


var _slot := ""


func _ready() -> void:
	_run.call_deferred()


func _done(ok: bool, msg: String) -> void:
	print("[save] %s %s" % ["SAVE PASS" if ok else "SAVE FAIL:", msg])
	Sfx.quit_game(0 if ok else 1)


func _wait(cond: Callable, secs: float) -> bool:
	var t := 0.0
	while not cond.call():
		await get_tree().process_frame
		t += get_process_delta_time()
		if t > secs:
			return false
	return true


func _run() -> void:
	if not await _wait(func(): return get_node_or_null("/root/Main/World/Match") != null, 20.0):
		_done(false, "no match")
		return
	var m = get_node("/root/Main/World/Match")
	if phase == "1":
		if not await _wait(func(): return m.phase == "trading", 20.0):
			_done(false, "day never started")
			return
		m.ledger.get_acct(0).balance = 55_555.0
		m.inventory[1] = {"cigar": 2, "lawyer": 1}
		if not await _wait(func(): return m.phase in ["intermission", "gameover"], 30.0):
			_done(false, "day never ended")
			return
		var s := SaveGame.latest_open()
		var want: float = 55_555.0 - Rules.overhead_for_day(1, 1) + _contract_pay(m)
		if str(s.get("owner", "")) != "Trader" or not s.has("next_event"):
			_done(false, "save doesn't record who started it / tomorrow's event: %s" % str(s))
			return
		if s.is_empty() or int(s.day) != 1 or absf(float(s.fund) - want) > 1.0:
			_done(false, "bad save after day 1: %s" % str(s))
			return
		if int(s.players.get("trader", {}).get("inventory", {}).get("cigar", 0)) != 2:
			_done(false, "items not saved: %s" % str(s.players))
			return
		_done(true, "day 1 saved: fund %s, cigar x2, lawyer x1 (%s)" % [Rules.money(float(s.fund)), s.slot])
	elif phase == "3":
		await get_tree().create_timer(1.0).timeout
		if m.day != 0 or m.save_slot == _slot or _slot == "":
			_done(false, "Bob loaded Trader's save (day %d, slot %s)" % [m.day, m.save_slot])
			return
		_done(true, "Bob can't load Trader's save (fresh run instead)")
	else:
		if not await _wait(func(): return m.day == 1, 10.0):
			_done(false, "didn't continue from day 1 (day %d)" % m.day)
			return
		var fund: float = m.ledger.get_acct(0).balance
		var want: float = float(SaveGame.read(_slot).get("fund", -1.0))
		if absf(fund - want) > 1.0 or m.item_count(1, "cigar") != 2 or m.item_count(1, "lawyer") != 1:
			_done(false, "continue lost things: fund %f, items %s" % [fund, str(m.inventory.get(1, {}))])
			return
		m.request_start()
		if not await _wait(func(): return m.day == 2 and m.phase == "trading", 10.0):
			_done(false, "bell didn't start day 2 (day %d, %s)" % [m.day, m.phase])
			return
		_done(true, "continued: day 2 open with %s and the items back" % Rules.money(fund))


## Tony's end-of-day contracts (clean / no slots) pay into the fund at the bell.
func _contract_pay(m) -> float:
	var total := 0.0
	for c in m.contracts.get(1, []):
		if c.done:
			total += c.cash
	return total
