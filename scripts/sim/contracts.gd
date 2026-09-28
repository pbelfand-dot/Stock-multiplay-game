extends RefCounted
## Tony's daily contracts: every morning each trader gets a few goals (one
## easy, one medium, one hard, plus extras from perks). Finish one and Tony
## pays cash + XP on the spot. Day events swap in a themed one (short the
## crash, flex on Black Friday...).
##
## A contract: {id, tier, text, goal, prog, done, failed, end, sym, cash, xp}
##   end = only settled at the closing bell (clean / no_casino)
## Progress comes from match events: note(c, kind, data) with kind one of
##   "close" {pnl, pct, side, sym, lev, pnl_day}   "hotdog"   "relieve"
##   "slots" {mult}   "lux"   and settle(c, {heat, slots_played}) at the bell.

const SYMS := ["BTC", "GOLD", "OIL", "REX", "BNN", "SPX", "PEAR", "NVDUH", "ETHR", "AIRX", "JPMG", "GAMR"]

## tier: 1 easy, 2 medium, 3 hard. goal "U" = scaled by the day's money unit.
const TEMPLATES := {
	"green3": {"tier": 1, "text": "Close 3 winning trades", "goal": 3.0},
	"short_win": {"tier": 1, "text": "Make money on a SHORT", "goal": 1.0},
	"sym_win": {"tier": 1, "text": "Win a trade on %s", "goal": 1.0},
	"hotdog": {"tier": 1, "text": "Eat a street hot dog (doctor's orders)", "goal": 1.0},
	"relieve2": {"tier": 1, "text": "Relieve the pressure twice", "goal": 2.0},
	"clean": {"tier": 1, "text": "Finish the day under 20 heat", "goal": 1.0, "end": true},
	"no_casino": {"tier": 1, "text": "Stay off the slots all day", "goal": 1.0, "end": true},
	"profit": {"tier": 2, "text": "Make %s profit today", "goal_u": 1.6},
	"double_up": {"tier": 2, "text": "Close a trade at +100% or better", "goal": 1.0},
	"lev_win": {"tier": 2, "text": "Win a trade at x50 leverage or higher", "goal": 1.0},
	"flex": {"tier": 2, "text": "Buy something from a boutique", "goal": 1.0},
	"wagmi_win": {"tier": 2, "text": "Make %s in one WAGMI trade", "goal_u": 0.6},
	"big_day": {"tier": 3, "text": "Monster day: finish %s up", "goal_u": 4.0},
	"streak": {"tier": 3, "text": "Win 3 trades in a row", "goal": 3.0},
	"jackpot": {"tier": 3, "text": "Hit x10 or better on the slots", "goal": 1.0},
	"short_big": {"tier": 3, "text": "Make %s on SHORTS today", "goal_u": 2.0},
	"long_big": {"tier": 3, "text": "Make %s on LONGS today", "goal_u": 2.0},
}
## Day events hand out a themed contract in place of one of the normal ones.
const THEMED := {"flash_crash": "short_big", "bear_market": "short_big", "bull_run": "long_big",
	"meme_mania": "wagmi_win", "sec_audit": "clean", "crackdown": "clean", "black_friday": "flex",
	"fed_day": "profit", "earnings": "profit", "liquidity_crunch": "streak"}
const PAY := {1: 0.12, 2: 0.3, 3: 0.6}         # cash in money units (day 1: $750 / $1.9K / $3.75K)
const XP := {1: 10.0, 2: 20.0, 3: 40.0}


## One money unit for `day`: grows with the quota (day 1 = $6.25K).
static func unit(day: int, start: float) -> float:
	return start * 0.25 * pow(1.5, maxi(day - 1, 0))


static func _money(v: float) -> String:
	if v >= 1_000_000.0:
		return "$%.2fM" % (v / 1_000_000.0)
	if v >= 10_000.0:
		return "$%.1fK" % (v / 1000.0)
	return "$%s" % str(int(round(v)))


static func make(id: String, day: int, start: float, rng: RandomNumberGenerator) -> Dictionary:
	var t: Dictionary = TEMPLATES[id]
	var u := unit(day, start)
	var c := {"id": id, "tier": int(t.tier), "prog": 0.0, "done": false, "failed": false,
		"end": t.get("end", false), "sym": "", "cash": round(u * PAY[int(t.tier)] / 50.0) * 50.0, "xp": XP[int(t.tier)]}
	if t.has("goal_u"):
		c.goal = round(u * float(t.goal_u) / 100.0) * 100.0
		c.text = t.text % _money(c.goal)
	elif id == "sym_win":
		c.sym = SYMS[rng.randi() % SYMS.size()]
		c.goal = 1.0
		c.text = t.text % c.sym
	else:
		c.goal = float(t.goal)
		c.text = t.text
	return c


## Today's contracts: easy + medium + hard (+ `extra` more), a themed one
## swapped in for its tier on event days. No duplicates.
static func deal(rng: RandomNumberGenerator, day: int, start: float, event_id: String = "", extra: int = 0) -> Array:
	var by_tier := {1: [], 2: [], 3: []}
	for id in TEMPLATES:
		if id == "short_big" or id == "long_big":
			continue                                   # themed days only
		by_tier[int(TEMPLATES[id].tier)].append(id)
	var picks: Array = []
	var themed: String = THEMED.get(event_id, "")
	for tier in [1, 2, 3]:
		if themed != "" and int(TEMPLATES[themed].tier) == tier:
			picks.append(themed)
			continue
		var pool: Array = by_tier[tier].filter(func(i): return not picks.has(i))
		picks.append(pool[rng.randi() % pool.size()])
	var rest: Array = []
	for tier in [1, 2, 3]:
		for id in by_tier[tier]:
			if not picks.has(id) and not TEMPLATES[id].get("end", false):
				rest.append(id)          # extras skip the end-of-day ones
	for i in extra:
		if rest.is_empty():
			break
		var id: String = rest.pop_at(rng.randi() % rest.size())
		picks.append(id)
	var out: Array = []
	for id in picks:
		out.append(make(id, day, start, rng))
	return out


## Feed one thing that happened into a contract. Returns true when that just
## finished it.
static func note(c: Dictionary, kind: String, d: Dictionary = {}) -> bool:
	if c.done or c.failed:
		return false
	var win: bool = kind == "close" and d.get("pnl", 0.0) > 0.0
	match c.id:
		"green3":
			if kind == "close" and win:
				c.prog += 1.0
		"short_win":
			if win and d.side < 0:
				c.prog = 1.0
		"sym_win":
			if win and d.sym == c.sym:
				c.prog = 1.0
		"hotdog":
			if kind == "hotdog":
				c.prog = 1.0
		"relieve2":
			if kind == "relieve":
				c.prog += 1.0
		"no_casino":
			if kind == "slots":
				c.failed = true
				return false
		"profit", "big_day":
			if kind == "close":
				c.prog = maxf(d.get("pnl_day", 0.0), 0.0)
		"double_up":
			if kind == "close" and d.get("pct", 0.0) >= 100.0:
				c.prog = 1.0
		"lev_win":
			if win and int(d.get("lev", 0)) >= 50:
				c.prog = 1.0
		"flex":
			if kind == "lux":
				c.prog = 1.0
		"wagmi_win":
			if win and d.sym == "WAGMI":
				c.prog = maxf(c.prog, d.pnl)
		"streak":
			if kind == "close":
				c.prog = c.prog + 1.0 if win else 0.0
		"jackpot":
			if kind == "slots" and d.get("mult", 0) >= 10:
				c.prog = 1.0
		"short_big":
			if kind == "close" and d.side < 0:
				c.prog = maxf(c.prog + d.pnl, 0.0)
		"long_big":
			if kind == "close" and d.side > 0:
				c.prog = maxf(c.prog + d.pnl, 0.0)
	if c.prog >= c.goal and not c.end:
		c.done = true
		return true
	return false


## The closing bell: settle the end-of-day contracts. Returns true when that
## finished this one.
static func settle(c: Dictionary, d: Dictionary) -> bool:
	if c.done or c.failed or not c.end:
		return false
	match c.id:
		"clean":
			if d.get("heat", 100.0) < 20.0:
				c.prog = 1.0
		"no_casino":
			c.prog = 1.0
	if c.prog >= c.goal:
		c.done = true
		return true
	c.failed = true
	return false


## "2/3", "$4.1K/$10K", "✓"
static func progress_text(c: Dictionary) -> String:
	if c.done:
		return "DONE"
	if c.failed:
		return "FAILED"
	if c.end:
		return "at the bell"
	if TEMPLATES[c.id].has("goal_u"):
		return "%s / %s" % [_money(c.prog), _money(c.goal)]
	if c.goal > 1.0:
		return "%d / %d" % [int(c.prog), int(c.goal)]
	return ""
