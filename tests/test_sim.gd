extends SceneTree
## Headless unit tests for the pure simulation.
## Run: godot --headless --path . -s tests/test_sim.gd

const Market = preload("res://scripts/sim/market.gd")
const News = preload("res://scripts/sim/news.gd")
const Ledger = preload("res://scripts/sim/ledger.gd")
const Rules = preload("res://scripts/sim/rules.gd")
const DayEvents = preload("res://scripts/sim/day_events.gd")
const Contracts = preload("res://scripts/sim/contracts.gd")

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
	test_auto_sell()
	test_liquidation()
	test_news()
	test_slots()
	test_format()
	test_day_events()
	test_event_market()
	test_contracts()
	test_perks()
	print("sim tests: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func test_market() -> void:
	var m = Market.new(1234)
	check(m.assets.size() == Market.ASSET_DEFS.size() and m.assets.size() == 18, "18 tickers on the board")
	check(m.assets[0].sym == "BTC" and m.assets[5].sym == "REX", "the first six stay put (terminal keys 1-6)")
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
	check(tp.p.size() == Market.ASSET_DEFS.size() and tp.c.size() == Market.ASSET_DEFS.size(), "tick payload shape")
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


func test_auto_sell() -> void:
	var l = Ledger.new()
	l.create_account(1, "p", 1_000_000.0)
	var r: Dictionary = l.open_position(1, "BTC", 1, 1_000.0, 5, 1000.0, "p")
	var set: Dictionary = l.set_auto_pct(1, r.pos.pid, 10.0, 5.0)
	check(approx(set.tp, 1100.0) and approx(set.sl, 950.0), "long: sell at +10%% / -5%%: %s" % str(set))
	var prices := {"BTC": 1050.0}
	var pf := func(s): return prices[s]
	check(l.check_triggers(pf).is_empty(), "nothing between the auto-sell prices")
	prices.BTC = 949.0
	var hit: Array = l.check_triggers(pf)
	check(hit.size() == 1 and hit[0].trigger == "SL", "auto-sold when it went too low")
	r = l.open_position(1, "BTC", -1, 1_000.0, 5, 1000.0, "p")
	set = l.set_auto_pct(1, r.pos.pid, 5.0, 10.0)
	check(approx(set.tp, 900.0) and approx(set.sl, 1050.0), "short: high = stop, low = take: %s" % str(set))
	r = l.open_position(1, "BTC", 1, 1_000.0, 100, 1000.0, "p")
	set = l.set_auto_pct(1, r.pos.pid, 0.0, 50.0)
	check(set.sl > Ledger.liq_price(r.pos), "a too-deep stop is pulled in before liquidation")
	check(approx(set.tp, 0.0), "high off = no take-profit")


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
	check(queued >= ev2.effects.size(), "apply queues impulses (+ sector followers)")
	# every ticker a headline can name exists on the board
	var syms := {}
	for a in m.assets:
		syms[a.sym] = true
	var unknown := {}
	for i in 3000:
		for e in n.roll().effects:
			if not syms.has(e.sym):
				unknown[e.sym] = true
	check(unknown.is_empty(), "headlines only name real tickers (%s)" % str(unknown.keys()))
	# sectors: SPX news drags the followers along, a beat later; FEAR goes the other way
	var mk = Market.new(9)
	mk.add_impulse("SPX", -0.08, 4.0, 0.0)
	var fear: Array = mk.assets[mk.index_of("FEAR")].impulses
	var nv: Array = mk.assets[mk.index_of("NVDUH")].impulses
	check(fear.size() == 1 and fear[0].rate > 0.0 and fear[0].delay > 0.5, "FEAR spikes when the S&P dumps, a beat later")
	check(nv.size() == 1 and nv[0].rate < 0.0, "tech follows the S&P down")
	check(mk.assets[mk.index_of("PEAR")].impulses.size() == 1, "followers don't chain (NVDUH -> PEAR not doubled)")
	mk.add_impulse("OIL", 0.05, 4.0, 0.0)
	check(mk.assets[mk.index_of("AIRX")].impulses[-1].rate < 0.0, "oil up grounds the airline")


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
	check(approx(Rules.quota_for_day(1), Rules.START_FUND * Rules.QUOTA_GROWTH), "day1 quota")
	check(approx(Rules.overhead_for_day(1, 2), Rules.OVERHEAD_PER_TRADER * 2), "day1 overhead for 2 traders")
	check(Rules.overhead_for_day(3, 1) > Rules.overhead_for_day(2, 1), "overhead creeps up")
	check(Rules.LUXURY.roflex.price > Rules.START_FUND * 5, "a Crownwell has to be saved up for")
	var GFX = load("res://scripts/net/graphics.gd")
	var gb := 1073741824
	check(GFX.detect("Apple Apple M1", "", 8 * gb) == "medium", "M1 8GB -> medium")
	check(GFX.detect("Apple Apple M2 Pro", "", 16 * gb) == "high", "M2 Pro -> high")
	check(GFX.detect("Apple Apple M3 Max", "", 36 * gb) == "ultra", "M3 Max -> ultra")
	check(GFX.detect("Intel Inc. Intel(R) Iris(TM) Plus Graphics", "", 8 * gb) == "low", "Intel Iris Mac -> low")
	check(GFX.detect("NVIDIA Corporation NVIDIA GeForce RTX 3060", "", 16 * gb) == "ultra", "RTX + 16GB -> ultra")
	check(GFX.detect("Mesa llvmpipe (LLVM 15)", "", 8 * gb) == "low", "software GL -> low")



func test_day_events() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var seen := {}
	var none := 0
	var last := ""
	var repeats := 0
	for i in 2000:
		var e := DayEvents.roll(rng, 3, last)
		if e == "":
			none += 1
		else:
			seen[e] = true
			check(DayEvents.EVENTS.has(e) and DayEvents.MODS.has(e), "day event %s has info + mods" % e)
			if e == last:
				repeats += 1
		last = e
	check(seen.size() == DayEvents.EVENTS.size(), "every day event shows up (%d/%d)" % [seen.size(), DayEvents.EVENTS.size()])
	check(repeats == 0, "never the same event two days running")
	check(none > 300 and none < 700, "about a quarter of days are normal (%d/2000)" % none)
	for i in 300:
		var d1 := DayEvents.roll(rng, 1)
		check(d1 == "" or d1 in DayEvents.DAY1_OK, "day 1 only gets the friendly events (%s)" % d1)
	# timed shocks: Fed halfway, earnings late, the crash somewhere in the middle
	var fed: Array = DayEvents.schedule("fed_day", rng, 300.0)
	check(fed.size() == 1 and approx(fed[0].at, 150.0), "Fed speaks halfway through the day")
	var hit: Dictionary = DayEvents.shock_news(fed[0], "hit")
	var moves := 0.0
	for e in hit.effects:
		moves += e.pct
	check(signf(moves) == signf(fed[0].dir) and absf(moves) > 0.15, "the Fed moves everything the way it decided (%.2f)" % moves)
	check(DayEvents.shock_news(fed[0], "warn").effects.is_empty(), "the 30-second warning doesn't move anything")
	for i in 50:
		var cr: Array = DayEvents.schedule("flash_crash", rng, 300.0)
		check(cr[0].at >= 60.0 and cr[0].at <= 225.0, "crash lands mid-day (%.0f)" % cr[0].at)
	var crash: Dictionary = DayEvents.shock_news(DayEvents.schedule("flash_crash", rng, 300.0)[0], "hit")
	var btc := 0.0
	var gold := 0.0
	for e in crash.effects:
		if e.sym == "BTC":
			btc = e.pct
		if e.sym == "GOLD":
			gold = e.pct
	check(btc < -0.08 and gold > 0.0, "the crash dumps BTC, gold catches a bid")
	check(DayEvents.schedule("bull_run", rng, 300.0).is_empty(), "no timed shocks on a bull run")
	check(DayEvents.morning_news("fed_day", 300.0).headline.contains("2:30"), "morning show says when Powww speaks")
	check(DayEvents.mod("black_friday", "lux_discount", 0.0) > 0.3 and DayEvents.mod("", "lux_discount", 0.0) == 0.0,
		"Black Friday discount, none on a normal day")


## Bull runs drift up, bear markets drift down, meme mania shakes memecoins.
func test_event_market() -> void:
	var up := 0.0
	var down := 0.0
	var calm := 0.0
	var wild := 0.0
	for seed_v in 20:
		var a := Market.new(1000 + seed_v)
		a.bias = DayEvents.mod("bull_run", "bias", 0.0)
		var b := Market.new(1000 + seed_v)
		b.bias = DayEvents.mod("bear_market", "bias", 0.0)
		var c := Market.new(2000 + seed_v)
		var d := Market.new(2000 + seed_v)
		d.vol_mult = DayEvents.mod("meme_mania", "vol", {})
		var ci := c.index_of("WAGMI")
		var cp := c.price(ci)
		var dp := d.price(ci)
		for i in 1200:                     # one 5-minute day at 0.25s ticks
			a.step(0.25)
			b.step(0.25)
			c.step(0.25)
			d.step(0.25)
			calm += absf(log(c.price(ci) / cp))
			wild += absf(log(d.price(ci) / dp))
			cp = c.price(ci)
			dp = d.price(ci)
		up += a.change_pct(a.index_of("BTC")) + a.change_pct(a.index_of("REX"))
		down += b.change_pct(b.index_of("BTC")) + b.change_pct(b.index_of("REX"))
	check(up > 0.0 and down < 0.0 and up - down > 40.0, "bull run drifts up, bear market down (%.1f vs %.1f)" % [up, down])
	check(wild > calm * 1.6, "meme mania makes WAGMI move a lot more (%.2f vs %.2f)" % [wild, calm])
	# the news desk follows the event: a tweetstorm is mostly Tramp
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var n := News.new(rng)
	n.boost = DayEvents.mod("tweetstorm", "news", {})
	var tramp := 0
	for i in 1000:
		if n.roll().speaker == "TRAMP":
			tramp += 1
	check(tramp > 450, "tweetstorm: Tramp dominates the headlines (%d/1000)" % tramp)


func test_contracts() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 200:
		var cs: Array = Contracts.deal(rng, 1 + i % 6, Rules.START_FUND, "", i % 3)
		check(cs.size() == 3 + i % 3, "3 contracts + extras")
		var ids := {}
		for c in cs:
			ids[c.id] = true
		check(ids.size() == cs.size(), "no duplicate contracts")
		check(cs[0].tier == 1 and cs[1].tier == 2 and cs[2].tier == 3, "easy, medium, hard")
	var d1: Array = Contracts.deal(rng, 1, Rules.START_FUND)
	check(d1[0].cash <= 800.0 and d1[2].cash <= 4000.0, "contracts pay a bonus, not the quota (day 1: %s / %s)" % [d1[0].cash, d1[2].cash])
	check(Rules.PVP_DAYS == 5, "a PvP match is 5 days")
	var themed: Array = Contracts.deal(rng, 2, Rules.START_FUND, "flash_crash")
	check(themed.any(func(c): return c.id == "short_big"), "crash day: Tony wants you short")
	# progress
	var g := Contracts.make("green3", 1, Rules.START_FUND, rng)
	check(not Contracts.note(g, "close", {"pnl": 100.0, "side": 1, "sym": "BTC", "lev": 10, "pct": 5.0}), "1/3")
	Contracts.note(g, "close", {"pnl": -50.0, "side": 1, "sym": "BTC", "lev": 10, "pct": -5.0})
	Contracts.note(g, "close", {"pnl": 80.0, "side": -1, "sym": "OIL", "lev": 10, "pct": 5.0})
	check(Contracts.note(g, "close", {"pnl": 10.0, "side": 1, "sym": "BTC", "lev": 10, "pct": 1.0}) and g.done, "3 winners done")
	check(not Contracts.note(g, "close", {"pnl": 10.0, "side": 1, "sym": "BTC", "lev": 10, "pct": 1.0}), "a done contract pays once")
	var st := Contracts.make("streak", 1, Rules.START_FUND, rng)
	Contracts.note(st, "close", {"pnl": 1.0, "side": 1, "sym": "BTC", "lev": 1, "pct": 1.0})
	Contracts.note(st, "close", {"pnl": 1.0, "side": 1, "sym": "BTC", "lev": 1, "pct": 1.0})
	Contracts.note(st, "close", {"pnl": -1.0, "side": 1, "sym": "BTC", "lev": 1, "pct": -1.0})
	check(st.prog == 0.0 and not st.done, "a loss breaks the streak")
	var p := Contracts.make("profit", 3, Rules.START_FUND, rng)
	check(p.goal > Contracts.make("profit", 1, Rules.START_FUND, rng).goal, "profit goals grow with the days")
	check(Contracts.note(p, "close", {"pnl": 1.0, "side": 1, "sym": "BTC", "lev": 1, "pct": 1.0, "pnl_day": p.goal + 1.0}), "profit goal hit")
	var nc := Contracts.make("no_casino", 1, Rules.START_FUND, rng)
	check(not Contracts.note(nc, "close", {"pnl": 5.0, "side": 1, "sym": "BTC", "lev": 1, "pct": 1.0}), "end-of-day contracts wait for the bell")
	check(Contracts.settle(nc, {"heat": 0.0}) and nc.done, "stayed off the slots")
	var nc2 := Contracts.make("no_casino", 1, Rules.START_FUND, rng)
	Contracts.note(nc2, "slots", {"mult": 0})
	check(nc2.failed and not Contracts.settle(nc2, {}), "played the slots: failed")
	var cl := Contracts.make("clean", 1, Rules.START_FUND, rng)
	check(not Contracts.settle(cl, {"heat": 45.0}) and cl.failed, "too hot at the bell")
	var ss := Contracts.make("short_big", 2, Rules.START_FUND, rng)
	Contracts.note(ss, "close", {"pnl": ss.goal * 0.6, "side": -1, "sym": "BTC", "lev": 1, "pct": 1.0})
	Contracts.note(ss, "close", {"pnl": 5000.0, "side": 1, "sym": "BTC", "lev": 1, "pct": 1.0})
	check(not ss.done, "longs don't count toward short money")
	check(Contracts.note(ss, "close", {"pnl": ss.goal * 0.5, "side": -1, "sym": "REX", "lev": 1, "pct": 1.0}), "short money adds up")


func test_perks() -> void:
	var base := Rules.perks_for(0, {})
	check(base.fee == 1.0 and base.contracts == 0 and base.early_news == 0.0, "an intern gets nothing")
	var wolf := Rules.perks_for(Rules.RANKS.size() - 1, {})
	check(wolf.contracts == 1 and approx(wolf.fee, 0.85) and wolf.early_news == 3.0 and approx(wolf.overhead, 0.75),
		"ranks stack their perks up to WOLF")
	var loaded := Rules.perks_for(0, {"up_prime": 1, "louie": 2, "up_bloomberg": 1, "roflex_iced": 1, "up_rolodex": 1, "champ": 3})
	check(approx(loaded.fee, 0.6 * 0.85), "Prime Broker x Valmont bag fees (%.3f)" % loaded.fee)
	check(loaded.early_news == 3.0, "early news takes the best source, doesn't add up")
	check(loaded.contracts == 1, "the Rolodex adds a contract")
	for key in Rules.UPGRADES:
		check(Rules.UPGRADES[key].price >= 20_000.0, "upgrades cost real money (%s)" % key)
	# a normal day-2 overhead is more than a Rolodex costs? no: upgrades take saving up
	check(Rules.UPGRADES.up_prime.price > Rules.overhead_for_day(3, 1) * 20.0, "Prime Broker is a long save")
