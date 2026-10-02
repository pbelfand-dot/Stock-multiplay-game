extends SceneTree
## Balance probe: how easy is money? A bot that only trades the headlines, the
## way the game runs them (the leak, fast markets, spreads both ways, slippage,
## leverage caps, corrections). 200 five-minute days per run; prints the day
## multiplier (the quota needs 1.5x a day) and what each speaker is worth.
##   godot --headless --path . -s tests/balance_bot.gd -- --lev=25 --react=1
## Flags: --lev --size (of balance per trade) --react (seconds to get the order in)
##   --early (headline lead: Bloomberg 3, Nose Candy 6) --hold (seconds it rides)
##   --start (balance) --mode=random (no news reading) --bail=0 (ignore corrections)
## Tuned (Oct 2026): a 2s reader loses, a 1s reader makes ~1.2x/day, the
## Bloomberg Terminal ~2-3x, a random clicker ~0.93x; $100M+ needs small size.
const Market = preload("res://scripts/sim/market.gd")
const News = preload("res://scripts/sim/news.gd")
const Ledger = preload("res://scripts/sim/ledger.gd")

var LEV := 100
var SIZE := 0.25      # fraction of balance per trade
var REACT := 1.0      # seconds after the headline before the bot's order lands
var EARLY := 0.0      # early-news lead (Bloomberg 3, powder 6)
var START := 25000.0
var DAYS := 200
var MODE := "news"    # news / random
var BAIL := 1         # 1 = closes when a correction / priced-in chyron airs
var by_spk := {}      # speaker -> [sum unlevered return, n]
var HOLD := 6.0       # seconds a player rides it after getting in

func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		if kv.size() == 2:
			match kv[0]:
				"lev": LEV = int(kv[1])
				"size": SIZE = float(kv[1])
				"react": REACT = float(kv[1])
				"early": EARLY = float(kv[1])
				"start": START = float(kv[1])
				"mode": MODE = kv[1]
				"bail": BAIL = int(kv[1])
				"days": DAYS = int(kv[1])
				"hold": HOLD = float(kv[1])
	var mults: Array = []
	var wins := 0; var trades := 0; var liqs := 0
	for d in DAYS:
		var r := _day(d + 1)
		mults.append(r.mult)
		wins += r.wins; trades += r.trades; liqs += r.liqs
	mults.sort()
	var logsum := 0.0
	for m in mults: logsum += log(maxf(m, 0.0001))
	var keys := by_spk.keys()
	keys.sort()
	var parts: PackedStringArray = []
	for k in keys:
		parts.append("%s %+.2f%% n%d" % [k, by_spk[k][0] / by_spk[k][1] * 100.0, by_spk[k][1]])
	print("  per trade (unlevered, net): ", ", ".join(parts))
	print("%s x%d size %.0f%% react %.1fs early %.0fs start $%dK | day mult median %.2f p10 %.2f p90 %.2f geo %.2f | win %.0f%% liq %.1f%% of %d" % [
		MODE, LEV, SIZE * 100, REACT, EARLY, int(START / 1000), mults[DAYS / 2], mults[DAYS / 10], mults[DAYS * 9 / 10], exp(logsum / DAYS),
		100.0 * wins / maxi(trades, 1), 100.0 * liqs / maxi(trades, 1), trades])
	quit()

func _day(seed_v: int) -> Dictionary:
	var m = Market.new(seed_v * 7919)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var deck = News.new(rng)
	var led = Ledger.new()
	led.exit_cost = func(pos, price): return m.spread_of(pos.sym) * 0.5 + m.impact(pos.sym, pos.units * price)
	led.create_account(0, "bot", START)
	var t := 0.0
	var next_in := rng.randf_range(22.0, 40.0)
	var ev: Dictionary = deck.roll()
	var leaked := false
	var seen_early := false
	var pending: Array = []   # [open_at, sym, side, close_at]
	var open: Array = []      # [pid, close_at, sym]
	var follow: Array = []    # [at, syms]
	var wins := 0; var trades := 0; var liqs := 0
	var rand_next := 5.0
	while t < 300.0:
		t += 0.25
		m.step(0.25)
		next_in -= 0.25
		if not leaked and next_in <= News.LEAK_S:
			leaked = true
			deck.leak(m, ev)
		if MODE == "news" and EARLY > 0.0 and not seen_early and next_in <= EARLY:
			seen_early = true
			var plan := _read(ev)
			if not plan.is_empty():
				pending.append([t + REACT, plan.sym, plan.side, t + next_in + HOLD, ev.speaker])
		if next_in <= 0.0:
			deck.apply(m, ev)
			if MODE == "news" and EARLY <= 0.0:
				var plan := _read(ev)
				if not plan.is_empty():
					pending.append([t + REACT, plan.sym, plan.side, t + plan.hold, ev.speaker])
			if ev.has("followup") and BAIL == 1:
				follow.append([t + ev.followup.at + REACT, ev])
			ev = deck.roll()
			next_in = rng.randf_range(22.0, 40.0)
			leaked = false
			seen_early = false
		if MODE == "random":
			rand_next -= 0.25
			if rand_next <= 0.0:
				rand_next = rng.randf_range(15.0, 30.0)
				var sym: String = m.assets[rng.randi() % m.assets.size()].sym
				pending.append([t, sym, 1 if rng.randf() < 0.5 else -1, t + rng.randf_range(5.0, 15.0), "RANDOM"])
		for f in follow.duplicate():
			if t >= f[0]:
				follow.erase(f)
				for o in open:     # the correction / analysts aired: get out
					for e in f[1].effects:
						if e.sym == o[2]:
							o[1] = t
		for p in pending.duplicate():
			if t >= p[0]:
				pending.erase(p)
				var bal: float = led.get_acct(0).balance
				var lev := mini(LEV, Market.max_lev(p[1]))
				var margin: float = bal * SIZE / (1.0 + lev * Ledger.FEE_RATE)
				var slip: float = m.impact(p[1], margin * lev)
				var r = led.open_position(0, p[1], p[2], margin, lev, m.price_of(p[1]), "bot", Ledger.FEE_RATE, m.spread_of(p[1]), slip)
				if r.ok:
					open.append([r.pos.pid, p[3], p[1], p[4]])
		for r in led.check_liquidations(m.price_of):
			liqs += 1; trades += 1
			for o in open.duplicate():
				if o[0] == r.pos.pid: open.erase(o)
		for o in open.duplicate():
			if t >= o[1]:
				open.erase(o)
				var r = led.close_position(0, o[0], m.price_of(o[2]))
				if r.ok:
					trades += 1
					if r.pnl - r.pos.fee > 0.0: wins += 1
					var k: String = o[3]
					if not by_spk.has(k): by_spk[k] = [0.0, 0]
					by_spk[k][0] += (r.pnl - r.pos.fee) / r.pos.margin / r.pos.lev
					by_spk[k][1] += 1
	led.close_all(0, m.price_of)
	return {"mult": led.get_acct(0).balance / START, "wins": wins, "trades": trades, "liqs": liqs}

## What a player who reads the chyron does: the biggest first effect, its direction.
func _read(ev: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var total := {}
	for e in ev.effects:
		if e.get("delay", 0.0) > 0.0:
			continue
		total[e.sym] = total.get(e.sym, 0.0) + e.pct
	for k in total:
		if best.is_empty() or absf(total[k]) > absf(best.pct):
			best = {"sym": k, "pct": total[k]}
	if best.is_empty():
		return {}
	var side := 1 if best.pct > 0 else -1
	var head: String = ev.headline
	# a player can't see the hidden truth: TJZ = follow his call, Crammer = fade it
	if ev.speaker == "TJZ":
		side = 1 if head.contains("LONG") else -1
	elif ev.speaker == "JIM CRAMMER":
		side = -1 if head.contains("BUY BUY") else 1
	var dur := 0.0
	for e in ev.effects:
		if e.sym == best.sym and e.get("delay", 0.0) <= 0.0 and not e.get("pre", false):
			dur = maxf(dur, e.dur)
	var hold: float = REACT + HOLD
	return {"sym": best.sym, "side": side, "hold": hold}
