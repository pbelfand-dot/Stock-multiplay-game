extends SceneTree
## Headless unit tests for the pure simulation.
## Run: godot --headless --path . -s tests/test_sim.gd

const Market = preload("res://scripts/sim/market.gd")
const News = preload("res://scripts/sim/news.gd")
const Ledger = preload("res://scripts/sim/ledger.gd")
const Rules = preload("res://scripts/sim/rules.gd")

var failures := 0
var checks := 0


func check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		printerr("FAIL: ", msg)


func approx(a: float, b: float, eps: float = 0.01) -> bool:
	return absf(a - b) <= eps * maxf(1.0, absf(b))


func _init() -> void:
	test_market()
	test_impulse()
	test_ledger()
	test_tpsl()
	test_spread_and_fees()
	test_ranks()
	test_liquidation()
	test_news()
	test_slots()
	test_format()
	print("sim tests: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func test_market() -> void:
	var m = Market.new(1234)
	check(m.assets.size() == Market.ASSET_DEFS.size() and m.assets.size() == 7, "7 assets (clip watchlist + WAGMI)")
	var closes := 0
	for i in 1200:  # 300 s at 4 Hz
		if m.step(0.25):
			closes += 1
	check(closes == 59 or closes == 60, "~60 candles in 300s, got %d" % closes)
	check(m.assets[0].candles.size() == closes, "candles stored")
	for a in m.assets:
		check(a.price > 0.0, "%s positive" % a.sym)
		check(a.price / a.base < 1.5 and a.price / a.base > 0.66, "%s stays sane over a day: %f" % [a.sym, a.price / a.base])
		var c: Array = a.candles[-1]
		check(c[1] >= c[0] and c[1] >= c[3] and c[2] <= c[0] and c[2] <= c[3], "OHLC consistent")
	var tp: Dictionary = m.tick_payload()
	check(tp.p.size() == 7 and tp.c.size() == 7, "tick payload shape")
	var fp: Dictionary = m.full_payload()
	check(fp.assets[0].candles.size() == closes, "full payload history")


func test_impulse() -> void:
	# Averaged over many seeds, a +10% impulse should move price ~+10%.
	var total := 0.0
	var n := 40
	for s in n:
		var m = Market.new(100 + s)
		var p0: float = m.price_of("GOLD")
		m.add_impulse("GOLD", 0.10, 5.0, 1.0)
		for i in 40:  # 10 s
			m.step(0.25)
		total += m.price_of("GOLD") / p0 - 1.0
	var avg := total / n
	check(avg > 0.08 and avg < 0.12, "impulse avg move ~10%%, got %f" % avg)


func test_ledger() -> void:
	var l = Ledger.new()
	l.create_account(0, "FUND", 100_000.0)
	var r: Dictionary = l.open_position(0, "BTC", 1, 10_000.0, 100, 1000.0, "tester")
	check(r.ok, "open ok")
	var fee := 10_000.0 * 100 * Ledger.FEE_RATE
	check(approx(l.get_acct(0).balance, 100_000.0 - 10_000.0 - fee), "margin+fee deducted")
	# Trailer check: x100, +1.21% move => +121% on margin
	var pid: int = r.pos.pid
	var c: Dictionary = l.close_position(0, pid, 1012.1)
	check(c.ok and approx(c.pct, 121.0, 0.001), "+1.21%% at x100 = +121%%, got %f" % c.pct)
	check(approx(l.get_acct(0).balance, 100_000.0 - fee + 12_100.0), "balance after win")
	# Short
	r = l.open_position(0, "GOLD", -1, 1_000.0, 10, 1500.0, "tester")
	c = l.close_position(0, r.pos.pid, 1485.0)
	check(approx(c.pnl, 100.0), "short profits when price drops: %f" % c.pnl)
	# Validation
	check(not l.open_position(0, "BTC", 1, 1e12, 1, 1000.0, "x").ok, "cannot exceed balance")
	check(not l.open_position(0, "BTC", 1, 100.0, 7, 1000.0, "x").ok, "leverage must be allowed")
	check(not l.open_position(0, "BTC", 0, 100.0, 1, 1000.0, "x").ok, "side must be +-1")
	check(not l.open_position(0, "BTC", 1, -5.0, 1, 1000.0, "x").ok, "positive size")
	check(not l.open_position(99, "BTC", 1, 5.0, 1, 1000.0, "x").ok, "account must exist")


func test_ranks() -> void:
	check(Rules.rank_name(0.0) == "INTERN", "start as an intern")
	check(Rules.rank_name(59.9) == "INTERN" and Rules.rank_name(60.0) == "ANALYST", "analyst at 60 XP")
	check(Rules.rank_name(1_000_000.0) == "WOLF", "wolf caps the ladder")
	var last := -1.0
	var ok := true
	for r in Rules.RANKS:
		ok = ok and r.xp > last
		last = r.xp
	check(ok, "rank thresholds strictly increase")
	for g in Rules.RANK_GATES:
		check(Rules.RANK_GATES[g] < Rules.RANKS.size(), "gate %s points at a real rank" % g)


func test_spread_and_fees() -> void:
	var l = Ledger.new()
	l.create_account(1, "p", 100_000.0)
	# the clip's numbers: $400 margin at x125 pays a $75 fee
	var r: Dictionary = l.open_position(1, "BTC", 1, 400.0, 125, 1000.0, "p")
	check(r.ok and approx(r.pos.fee, 75.0), "clip fee: $400 x125 -> $75, got %f" % r.pos.fee)
	r = l.open_position(1, "BTC", 1, 1_000.0, 10, 1000.0, "p", Ledger.FEE_RATE, 0.002)
	check(approx(r.pos.entry, 1001.0), "long buys the ask (+half spread)")
	r = l.open_position(1, "BTC", -1, 1_000.0, 10, 1000.0, "p", Ledger.FEE_RATE, 0.002)
	check(approx(r.pos.entry, 999.0), "short sells the bid (-half spread)")
	var closed: Dictionary = l.close_position(1, r.pos.pid, 1000.0)
	check(closed.pnl < 0.0, "round trip at the same mid loses the spread")


func test_tpsl() -> void:
	var l = Ledger.new()
	l.create_account(1, "p", 100_000.0)
	var r: Dictionary = l.open_position(1, "BTC", 1, 1_000.0, 10, 1000.0, "p")
	var pid: int = r.pos.pid
	check(approx(Ledger.liq_price(r.pos), 900.0), "long x10 liquidates at -10%%: %f" % Ledger.liq_price(r.pos))
	check(not l.set_tpsl(1, pid, 990.0, 0.0), "TP below entry rejected for a long")
	check(not l.set_tpsl(1, pid, 0.0, 1010.0), "SL above entry rejected for a long")
	check(not l.set_tpsl(1, pid, 0.0, 880.0), "SL past liquidation rejected")
	check(l.set_tpsl(1, pid, 1050.0, 960.0), "valid TP/SL accepted")
	var prices := {"BTC": 1020.0}
	var pf := func(s): return prices[s]
	check(l.check_triggers(pf).is_empty(), "no trigger between SL and TP")
	prices.BTC = 1051.0
	var hit: Array = l.check_triggers(pf)
	check(hit.size() == 1 and hit[0].trigger == "TP" and approx(hit[0].pnl, 510.0), "TP closes in profit")
	r = l.open_position(1, "BTC", -1, 1_000.0, 10, 1000.0, "p")
	check(approx(Ledger.liq_price(r.pos), 1100.0), "short x10 liquidates at +10%%")
	check(l.set_tpsl(1, r.pos.pid, 950.0, 1030.0), "short TP below / SL above")
	prices.BTC = 1031.0
	hit = l.check_triggers(pf)
	check(hit.size() == 1 and hit[0].trigger == "SL" and hit[0].pnl < 0.0, "SL cuts the short loss")


func test_liquidation() -> void:
	var l = Ledger.new()
	l.create_account(7, "p", 10_000.0)
	l.open_position(7, "BTC", 1, 1_000.0, 100, 1000.0, "p")
	var prices := {"BTC": 995.0}
	var pf := func(s): return prices[s]
	check(l.check_liquidations(pf).size() == 0, "no liq at -0.5%")
	prices.BTC = 989.0
	var liq: Array = l.check_liquidations(pf)
	check(liq.size() == 1 and liq[0].liquidated, "liquidated past -1% at x100")
	check(approx(liq[0].pnl, -1_000.0), "lose exactly the margin")
	check(l.get_acct(7).positions.is_empty(), "position removed")
	# equity & close_all
	l.open_position(7, "BTC", 1, 500.0, 10, 1000.0, "p")
	l.open_position(7, "BTC", -1, 500.0, 10, 1000.0, "p")
	prices.BTC = 1010.0
	var eq: float = l.equity(7, pf)
	var closed: Array = l.close_all(7, pf)
	check(closed.size() == 2, "close_all closes both")
	check(approx(l.get_acct(7).balance, eq), "equity == balance after close_all")


func test_news() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var n = News.new(rng)
	var speakers := {}
	for i in 400:
		var ev: Dictionary = n.roll()
		speakers[ev.speaker] = true
		check(ev.headline.length() > 5, "headline text")
		check(ev.effects.size() > 0, "has effects")
		for e in ev.effects:
			check(e.sym in News.SYMS, "valid sym " + str(e.sym))
			check(e.pct > -1.0, "pct > -100%")
		check(ev.hint.length() > 0, "hint present")
	for s in ["TRAMP", "TJZ", "KIMCHEE", "JIM CRAMMER", "ROARING KITTEH", "JEROME POWWW", "BREAKING"]:
		check(speakers.has(s), "speaker appears: " + s)
	var m = Market.new(5)
	var ev2: Dictionary = n.roll()
	n.apply(m, ev2)
	var queued := 0
	for a in m.assets:
		queued += a.impulses.size()
	check(queued == ev2.effects.size(), "apply queues impulses")


func test_slots() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var spent := 0.0
	var won := 0.0
	for i in 200_000:
		var reels := [Rules.slot_reel(rng), Rules.slot_reel(rng), Rules.slot_reel(rng)]
		spent += 1.0
		won += Rules.slot_multiplier(reels)
	var rtp := won / spent
	check(rtp > 0.88 and rtp < 1.0, "slot RTP between 88%% and 100%%, got %f" % rtp)
	check(Rules.slot_multiplier([4, 4, 4]) == 60, "777 pays 60x")
	check(Rules.slot_multiplier([0, 0, 2]) == 2, "two cherries pay 2x")
	check(Rules.slot_multiplier([1, 2, 3]) == 0, "mixed pays 0")


func test_format() -> void:
	check(Rules.money(120_050.0) == "$120.05K", "money K: " + Rules.money(120_050.0))
	check(Rules.money(1_030_000.0) == "$1.03M", "money M")
	check(Rules.money(-500.0) == "-$500", "money neg")
	check(Rules.money(5000.0) == "$5,000", "money commas: " + Rules.money(5000.0))
	check(Rules.price_str(1015.38) == "1,015.38", "price commas: " + Rules.price_str(1015.38))
	check(Rules.price_str(0.4213) == "0.4213", "small price")
	check(approx(Rules.quota_for_day(1), 150_000.0), "day1 quota")
