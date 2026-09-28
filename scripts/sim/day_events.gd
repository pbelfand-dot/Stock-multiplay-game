extends RefCounted
## Random day events: "today on the Street". Most days something is going on:
## a flash crash, Fed day, meme mania, an SEC audit, Black Friday on the
## boutiques... Tomorrow's event is rolled at the closing bell so the
## after-hours summary can show the forecast and you can plan for it (save
## your cash for Black Friday, go into Fed day with dry powder).
##
## Pure data + helpers: the host's match uses them, the unit tests too.
##
## Modifier keys (MODS):
##   vol        {sym: x}  volatility multiplier
##   bias       trend drift for every asset, in units of its volatility (+ = up)
##   news       {speaker: x} how often each speaker shows up
##   news_every x on the time between headlines (< 1 = more headlines)
##   tramp      x on how hard Tramp's posts move things
##   heat_gain / heat_decay   x on heat
##   raid_at    the heat where the cops come (default Rules.HEAT_MAX)
##   lux_discount  boutiques take this much off
##   spread / fee  x on trading costs
##   overhead   x on tonight's overhead

const CHANCE := 0.75             # day 2+: most days have something going on
const DAY1_CHANCE := 0.4         # day 1 only gets the friendly ones
const DAY1_OK := ["meme_mania", "bull_run", "tweetstorm", "black_friday", "bonus_day", "fed_day", "earnings"]

const EVENTS := {
	"flash_crash": {"name": "FLASH CRASH", "color": Color(1.0, 0.3, 0.25),
		"blurb": "Something breaks today. When it goes, everything dumps 10%+ in seconds and the circuit breaker halts trading. Shorts eat.",
		"forecast": "The desk smells a crash tomorrow. Nobody knows when."},
	"fed_day": {"name": "FED DAY", "color": Color(0.55, 0.8, 1.0),
		"blurb": "Chair Powww speaks halfway through the day. Everything moves 5-8% on his first word. Pick a side before he talks.",
		"forecast": "Powww speaks tomorrow. Cut or hike, it'll move everything."},
	"meme_mania": {"name": "MEME MANIA", "color": Color(0.7, 1.0, 0.35),
		"blurb": "WAGMI and BANANA COIN go feral (2x volatility) and the streamers won't stop posting.",
		"forecast": "Group chats are buzzing. Memecoins go feral tomorrow."},
	"bull_run": {"name": "BULL RUN", "color": Color(0.35, 1.0, 0.5),
		"blurb": "Everything grinds up all day. Longs get paid. Don't short the tape.",
		"forecast": "Futures are ripping overnight. Tomorrow looks green."},
	"bear_market": {"name": "BEAR MARKET", "color": Color(1.0, 0.45, 0.35),
		"blurb": "Everything bleeds all day. Shorts get paid. Catching knives gets you cut.",
		"forecast": "Futures are bleeding overnight. Tomorrow looks red."},
	"sec_audit": {"name": "SEC AUDIT", "color": Color(1.0, 0.75, 0.3),
		"blurb": "Auditors are on the floor. Heat builds twice as fast and cools at half speed. Keep it clean.",
		"forecast": "The SEC is sending auditors tomorrow. Keep it clean."},
	"tweetstorm": {"name": "TRAMP TWEETSTORM", "color": Color(1.0, 0.85, 0.3),
		"blurb": "Tramp is up at 3am posting. His posts come way more often and hit harder. Keep your phone out.",
		"forecast": "Tramp just got his phone back. Tomorrow's going to be loud."},
	"black_friday": {"name": "BLACK FRIDAY", "color": Color(1.0, 0.4, 0.85),
		"blurb": "Every boutique on the street is 35% off today. Bags, watches, all of it.",
		"forecast": "BLACK FRIDAY tomorrow: every boutique 35% off. Save your cash."},
	"earnings": {"name": "REX EARNINGS", "color": Color(0.85, 0.85, 1.0),
		"blurb": "Rex Motors reports late in the day. REX moves 10-15% in one go. Guess right.",
		"forecast": "Rex Motors reports tomorrow. Beat or miss, REX is moving."},
	"crackdown": {"name": "CRACKDOWN", "color": Color(0.4, 0.55, 1.0),
		"blurb": "The cops are itching for it. They raid at 70 heat instead of 100.",
		"forecast": "The mayor promised a crackdown. Cops are itching tomorrow."},
	"liquidity_crunch": {"name": "LIQUIDITY CRUNCH", "color": Color(0.75, 0.6, 1.0),
		"blurb": "Spreads are 3x wider and fees are doubled. Every in-and-out costs you. Hold your trades.",
		"forecast": "Market makers are on vacation tomorrow. Trading gets expensive."},
	"bonus_day": {"name": "BONUS DAY", "color": Color(1.0, 0.84, 0.2),
		"blurb": "The firm covers tonight's overhead. Whatever you make, you keep.",
		"forecast": "Bonus day tomorrow: the firm pays the overhead."},
}

const MODS := {
	"flash_crash": {},
	"fed_day": {},
	"meme_mania": {"vol": {"WAGMI": 2.0, "BNN": 2.0}, "news": {"kimchee": 3.0, "kitteh": 3.0, "tjz": 1.5}, "news_every": 0.75},
	"bull_run": {"bias": 0.3},
	"bear_market": {"bias": -0.3},
	"sec_audit": {"heat_gain": 2.0, "heat_decay": 0.5},
	"tweetstorm": {"news": {"tramp": 4.0}, "tramp": 1.35, "news_every": 0.8},
	"black_friday": {"lux_discount": 0.35},
	"earnings": {},
	"crackdown": {"raid_at": 70.0},
	"liquidity_crunch": {"spread": 3.0, "fee": 2.0},
	"bonus_day": {"overhead": 0.0},
}

## When the scheduled shocks go off, as a fraction of the day already gone.
const FED_AT := 0.5
const EARNINGS_AT := 0.72
const CRASH_FROM := 0.2
const CRASH_TO := 0.75
const WARN_SECONDS := 30.0        # "Powww speaks in 30 seconds"
const CRASH_WARN := 8.0           # sirens right before the crash
const HALT_SECONDS := 20.0        # circuit breaker
const HALT_AFTER := 6.0           # the crash plays out, then the halt


static func roll(rng: RandomNumberGenerator, day: int, last: String = "") -> String:
	if day <= 1:
		return DAY1_OK[rng.randi() % DAY1_OK.size()] if rng.randf() < DAY1_CHANCE else ""
	if rng.randf() >= CHANCE:
		return ""
	var ids: Array = EVENTS.keys()
	ids.erase(last)                  # never the same thing two days running
	return ids[rng.randi() % ids.size()]


static func info(id: String) -> Dictionary:
	return EVENTS.get(id, {})


static func title(id: String) -> String:
	return EVENTS.get(id, {}).get("name", "")


static func mod(id: String, key: String, default = 1.0):
	return MODS.get(id, {}).get(key, default)


## The timed shocks for today, with their outcome already decided (so an
## Insider Tip can reveal it). `at` is seconds into the day.
static func schedule(id: String, rng: RandomNumberGenerator, day_len: float) -> Array:
	match id:
		"fed_day":
			return [{"kind": "fed", "at": day_len * FED_AT, "dir": 1 if rng.randf() < 0.55 else -1,
				"size": rng.randf_range(0.85, 1.25), "warned": false, "fired": false}]
		"earnings":
			return [{"kind": "earnings", "at": day_len * EARNINGS_AT, "dir": 1 if rng.randf() < 0.5 else -1,
				"size": rng.randf_range(0.10, 0.15), "warned": false, "fired": false}]
		"flash_crash":
			return [{"kind": "crash", "at": day_len * rng.randf_range(CRASH_FROM, CRASH_TO), "dir": -1,
				"size": rng.randf_range(0.9, 1.3), "warned": false, "fired": false}]
	return []


## Scheduled times players are told about (the crash is a surprise).
static func public_at(s: Dictionary) -> bool:
	return s.kind != "crash"


static func hint(s: Dictionary) -> String:
	match s.kind:
		"fed":
			return "POWWW WILL %s — everything %s" % ["CUT" if s.dir > 0 else "HIKE", "UP" if s.dir > 0 else "DOWN"]
		"earnings":
			return "REX EARNINGS: %s — REX %s big" % ["BEAT" if s.dir > 0 else "MISS", "UP" if s.dir > 0 else "DOWN"]
		"crash":
			return "FLASH CRASH INCOMING — everything DOWN hard, GOLD up"
	return ""


static func _fx(pairs: Array, dur: float) -> Array:
	var out: Array = []
	for p in pairs:
		out.append({"sym": p[0], "pct": p[1], "dur": dur, "delay": 0.0})
	return out


## The headline (news event) a shock goes out as. `stage`: "warn", "hit" or "reopen".
static func shock_news(s: Dictionary, stage: String) -> Dictionary:
	var k: float = s.size
	match s.kind:
		"fed":
			if stage == "warn":
				return _news("JEROME POWWW", "FED", "FED CHAIR POWWW TAKES THE PODIUM IN 30 SECONDS", [])
			if s.dir > 0:
				return _news("JEROME POWWW", "FED", "POWWW: EMERGENCY CUT. THE PRINTER IS BACK. BRRRRR", _fx([
						["BTC", 0.07 * k], ["GOLD", 0.04 * k], ["REX", 0.05 * k], ["SPX", 0.04 * k], ["BNN", 0.06 * k]], 6.0))
			return _news("JEROME POWWW", "FED", "POWWW: RATES UP 100 BASIS POINTS. PARTY IS OVER", _fx([
					["BTC", -0.07 * k], ["GOLD", -0.03 * k], ["REX", -0.06 * k], ["SPX", -0.045 * k], ["BNN", -0.06 * k]], 6.0))
		"earnings":
			if stage == "warn":
				return _news("REX MOTORS", "BREAKING", "REX MOTORS REPORTS EARNINGS IN 30 SECONDS", [])
			if s.dir > 0:
				return _news("REX MOTORS", "BREAKING", "REX MOTORS SMASHES EARNINGS: RECORD CYBERVAN SALES", _fx([["REX", k]], 5.0))
			return _news("REX MOTORS", "BREAKING", "REX MOTORS MISSES BADLY: EVERY CYBERVAN RECALLED", _fx([["REX", -k]], 5.0))
		"crash":
			if stage == "warn":
				return _news("BREAKING", "BREAKING", "SIRENS ON WALL ST — SOMETHING IS BREAKING", [])
			if stage == "reopen":
				return _news("BREAKING", "BREAKING", "CIRCUIT BREAKER LIFTED. BUYERS STEPPING IN", _fx([
						["BTC", 0.05 * k], ["SPX", 0.035 * k], ["REX", 0.05 * k], ["OIL", 0.03 * k], ["BNN", 0.06 * k]], 20.0))
			return _news("BREAKING", "BREAKING", "FLASH CRASH! EVERYTHING IS DUMPING", _fx([
					["BTC", -0.12 * k], ["SPX", -0.08 * k], ["REX", -0.14 * k], ["OIL", -0.09 * k],
					["BNN", -0.18 * k], ["WAGMI", -0.3 * k], ["GOLD", 0.03 * k]], 4.0))
	return {}


static func _news(speaker: String, role: String, headline: String, effects: Array) -> Dictionary:
	return {"speaker": speaker, "role": role, "headline": headline, "effects": effects, "hint": ""}


## The morning headline announcing today's event.
static func morning_news(id: String, day_len: float) -> Dictionary:
	var e: Dictionary = info(id)
	var when := ""
	match id:
		"fed_day":
			when = " — POWWW SPEAKS AT %s" % clock(day_len * (1.0 - FED_AT))
		"earnings":
			when = " — REX REPORTS AT %s" % clock(day_len * (1.0 - EARNINGS_AT))
	return _news("MORNING BELL", "TV", "TODAY: %s%s" % [e.get("name", ""), when], [])


## 150.0 -> "2:30"
static func clock(secs: float) -> String:
	var s := int(round(secs))
	return "%d:%02d" % [s / 60, s % 60]
