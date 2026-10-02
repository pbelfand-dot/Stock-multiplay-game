extends RefCounted
## News / streamer event deck. The server pre-rolls the NEXT event so items
## like the Insider Tip can reveal it early. Every event is parody.
##
## Event dictionary:
##   speaker  : who is talking (shown on the TV chyron)
##   role     : "PRESIDENT" / "STREAMER" / "FED" / "BREAKING" / "TV"
##   headline : chyron text
##   effects  : [{sym, pct, dur, delay, pre}] — price impulses (delay is after REACTION_DELAY;
##              pre = part of the leak, plays out in the LEAK_S before the TV airs it)
##   hint     : short "what really happens" string for tips (e.g. "OIL ▲ big")
##   outcome  : "real" / "priced_in" / "fake" (hidden; the Insider Tip tells you)
##   followup : optional second chyron {at, speaker, role, headline}: a CORRECTION,
##              or the analysts calling it priced in (at = seconds after the first)

const REACTION_DELAY := 0.5   # seconds between headline and the market reacting
## Insiders and the algos read it first: a slice of the move (LEAK_MIN..LEAK_MAX of
## it) happens in the LEAK_S seconds BEFORE the TV airs it. Tramp's phone posts and
## the early-news perks (Bloomberg, WOLF, Nose Candy) are how you beat the leak.
const LEAK_S := 3.0
const LEAK_MIN := 0.5
const LEAK_MAX := 0.8
## Not every headline pays. Tramp, BREAKING and the Fed can be:
##   real      the move plays out
##   priced_in the leak already took it; once it airs, "sell the news" pulls it back
##   fake      it goes, then a CORRECTION airs and it all reverses (and then some)
const OUTCOMES := {"real": 0.5, "priced_in": 0.3, "fake": 0.2}
## The knee-jerk: often the first second after it airs, the algos run the stops
## the WRONG way (KNEE_MIN..KNEE_MAX of the price) before it goes. x100 chasers die here.
const KNEE_CHANCE := 0.6
const KNEE_MIN := 0.006
const KNEE_MAX := 0.018

const SYMS := ["BTC", "GOLD", "OIL", "SPX", "BNN", "REX", "WAGMI", "ETHR", "DOGGO", "PEAR", "NVDUH", "GAMR",
	"AIRX", "BURG", "PHRM", "JPMG", "GAS", "FEAR"]
const TRAMP_MULT := 1.7   # "you're one post away from getting rich... or losing it all"

## How often each speaker comes up (day events scale these, see DayEvents).
const WEIGHTS := {"tramp": 0.22, "tjz": 0.18, "kimchee": 0.14, "crammer": 0.10, "kitteh": 0.08, "fed": 0.12, "breaking": 0.16}

var rng: RandomNumberGenerator
var boost := {}               # speaker -> weight multiplier for today
var tramp_boost := 1.0        # tweetstorm: his posts hit harder


func _init(r: RandomNumberGenerator) -> void:
	rng = r


func _pick(arr: Array):
	return arr[rng.randi() % arr.size()]


func _dir_word(d: int) -> String:
	return "LONG" if d > 0 else "SHORT"


func _arrow(pct: float) -> String:
	return "UP" if pct > 0 else "DOWN"


func roll() -> Dictionary:
	var total := 0.0
	for k in WEIGHTS:
		total += WEIGHTS[k] * float(boost.get(k, 1.0))
	var r := rng.randf() * total
	var who := "breaking"
	for k in WEIGHTS:
		r -= WEIGHTS[k] * float(boost.get(k, 1.0))
		if r < 0.0:
			who = k
			break
	match who:
		"tramp":
			return _tramp()
		"tjz":
			return _tjz()
		"kimchee":
			return _kimchee()
		"crammer":
			return _crammer()
		"kitteh":
			return _kitteh()
		"fed":
			return _fed()
	return _breaking()


func _ev(speaker: String, role: String, headline: String, effects: Array) -> Dictionary:
	var hint_parts: PackedStringArray = []
	for e in effects:
		if e.get("delay", 0.0) > 0.0 and e.pct < 0 and hint_parts.size() > 0:
			hint_parts.append("then RUG")
			continue
		var size_word := "big" if absf(e.pct) >= 0.03 else "small"
		hint_parts.append("%s %s %s" % [e.sym, _arrow(e.pct), size_word])
	return {"speaker": speaker, "role": role, "headline": headline,
		"effects": effects, "hint": ", ".join(hint_parts)}


# ---------------- speakers ----------------

func _tramp() -> Dictionary:
	var lines := [
		["YOU'LL BE TIRED OF WINNING", [["BTC", 0.012], ["GOLD", 0.006], ["OIL", 0.01], ["BNN", 0.012], ["REX", 0.012]]],
		["TARIFFS ON OIL. HUGE TARIFFS. THE BIGGEST", [["OIL", 0.035]]],
		["I LOVE BITCOIN. TREMENDOUS COIN. MAYBE THE BEST COIN", [["BTC", 0.04]]],
		["BITCOIN? NEVER HEARD OF IT. SAD!", [["BTC", -0.035]]],
		["BANANAS ARE FAKE NEWS", [["BNN", -0.05]]],
		["REX MOTORS, BEAUTIFUL CARS. I DROVE ONE. PERFECT", [["REX", 0.04]]],
		["GOLD IS FOR LOSERS. I HAVE THE MOST GOLD", [["GOLD", -0.02]]],
		["WE'RE BUYING GREENLAND WITH WAGMI COIN", [["WAGMI", 0.25]]],
		["NOBODY KNOWS MORE ABOUT MARKETS THAN ME", [["BTC", -0.01], ["REX", -0.012], ["BNN", -0.012], ["SPX", -0.01]]],
		["WE ARE IN WAR!", [["OIL", 0.05], ["GOLD", 0.025], ["SPX", -0.03], ["BTC", -0.03]]],
		["THE S&P IS AT ALL TIME HIGHS BECAUSE OF ME", [["SPX", 0.025]]],
		["BANANA COIN IS A SCAM. TOTAL SCAM", [["BNN", -0.07]]],
		["PEAR PHONES ARE MADE OVERSEAS. VERY BAD. SAD!", [["PEAR", -0.03]]],
		["THE AIRLINES ARE A DISASTER. I'M GROUNDING THEM ALL", [["AIRX", -0.05]]],
		["BIG PHARMA IS RIPPING YOU OFF. PRICES DOWN 90%. MAYBE 1000%", [["PHRM", -0.06]]],
		["BURGER BARON. BEST BURGERS. I ATE 12 TODAY", [["BURG", 0.04]]],
		["DOGGO COIN TO THE MOON. MY FAVORITE DOG", [["DOGGO", 0.15]]],
		["AI CHIPS? WE MAKE THE BEST CHIPS. NVIDOOH, GREAT COMPANY", [["NVDUH", 0.04]]],
	]
	var l: Array = _pick(lines)
	var effects: Array = []
	for pair in l[1]:
		effects.append({"sym": pair[0], "pct": pair[1] * TRAMP_MULT * tramp_boost * rng.randf_range(0.8, 1.25), "dur": rng.randf_range(3.0, 6.0), "delay": 0.0})
	return _shape(_ev("TRAMP", "PRESIDENT", "TRAMP: " + l[0], effects), _roll_outcome(),
		"TRAMP: (POST DELETED) \"THAT WAS A JOKE. FAKE NEWS MEDIA!\"")


## TJR-style day-trading streamer. Right ~65% of the time.
func _tjz() -> Dictionary:
	var sym: String = _pick(["BTC", "GOLD", "OIL", "REX", "BNN", "NVDUH", "PEAR", "ETHR", "GAMR", "JPMG"])
	var d := 1 if rng.randf() < 0.5 else -1
	var right := rng.randf() < 0.65
	var move := d * (1 if right else -1) * rng.randf_range(0.012, 0.03)
	var hype: String = _pick([
		"OH MY GOD, TRADE! %s %s RIGHT NOW!",
		"CHAT, THIS IS THE ONE. %s %s. OH MY GOD.",
		"LIQUIDITY SWEPT. %s %s. TRADE!!",
		"I'M NOT EVEN KIDDING CHAT, %s %s",
	])
	var headline := "TJZ (LIVE): " + hype % [_dir_word(d), sym]
	var ev := _ev("TJZ", "STREAMER", headline, [{"sym": sym, "pct": move, "dur": rng.randf_range(6.0, 12.0), "delay": 0.0}])
	ev.hint = "TJZ is %s — %s %s" % ["RIGHT" if right else "WRONG", sym, _arrow(move)]
	return ev


## Kimchi-style memecoin whale. Pumps WAGMI then (usually) rugs it.
## Kimchi-style memecoin whale. Pump and dump: he buys BEFORE he posts (the leak),
## his post pumps it a little more, then he (usually) rugs it on his followers.
func _kimchee() -> Dictionary:
	var coin: String = "WAGMI" if rng.randf() < 0.65 else "DOGGO"
	var rug := rng.randf() < 0.8
	var pump := rng.randf_range(0.15, 0.4)
	var pre := pump * rng.randf_range(0.5, 0.7)
	var effects := [{"sym": coin, "pct": pre, "dur": LEAK_S, "delay": 0.0, "pre": true},
		{"sym": coin, "pct": (1.0 + pump) / (1.0 + pre) - 1.0, "dur": rng.randf_range(4.0, 8.0), "delay": 0.0}]
	if rug:
		effects.append({"sym": coin, "pct": -rng.randf_range(0.35, 0.6), "dur": rng.randf_range(2.0, 4.0), "delay": rng.randf_range(6.0, 12.0)})
	var line: String = _pick([
		"APING MY WHOLE BAG INTO $%s. NFA",
		"$%s TO A BILLI. I'M NOT SELLING (I'M SELLING)",
		"JUST BOUGHT 40 MILLI OF $%s. SEND IT",
		"DEV IS BASED. $%s IS THE ONE. TRUST",
	]) % coin
	var ev := _ev("KIMCHEE", "STREAMER", "KIMCHEE: " + line, effects)
	ev.hint = "%s pump%s" % [coin, " then RUG (fast)" if rug else " — no rug this time"]
	return ev


## Inverse-Cramer: his calls are wrong 75% of the time.
func _crammer() -> Dictionary:
	var sym: String = _pick(["REX", "BNN", "BTC", "OIL", "PEAR", "NVDUH", "GAMR", "AIRX", "BURG", "PHRM"])
	var d := 1 if rng.randf() < 0.5 else -1
	var right := rng.randf() < 0.25
	var move := d * (1 if right else -1) * rng.randf_range(0.015, 0.035)
	var line := "BUY BUY BUY %s! BOOYAH!" % sym if d > 0 else "SELL SELL SELL %s! GET OUT NOW!" % sym
	var ev := _ev("JIM CRAMMER", "TV", "JIM CRAMMER: " + line, [{"sym": sym, "pct": move, "dur": rng.randf_range(6.0, 10.0), "delay": 0.0}])
	ev.hint = "Crammer is %s — %s %s" % ["RIGHT (rare)" if right else "WRONG (as usual)", sym, _arrow(move)]
	return ev


## Roaring-Kitty-style meme-stock legend. Posts a single emoji, GameShop goes nuts.
func _kitteh() -> Dictionary:
	var effects := [{"sym": "GAMR", "pct": rng.randf_range(0.08, 0.16), "dur": rng.randf_range(5.0, 9.0), "delay": 0.0}]
	if rng.randf() < 0.5:
		effects.append({"sym": "GAMR", "pct": -rng.randf_range(0.06, 0.12), "dur": 6.0, "delay": rng.randf_range(14.0, 20.0)})
	var line: String = _pick(["*posts a single cat meme*", "I LIKE THE STOCK.", "*is streaming in a headband*"])
	return _shape(_ev("ROARING KITTEH", "STREAMER", "ROARING KITTEH: " + line, effects), _roll_outcome(false), "")


func _fed() -> Dictionary:
	var cut := rng.randf() < 0.55
	var walk_back := "FED: POWWW 'MISSPOKE'. STATEMENT WALKED BACK"
	if cut:
		return _shape(_ev("JEROME POWWW", "FED", "FED CHAIR POWWW: RATES CUT. MONEY PRINTER GO BRRR", [
			{"sym": "GOLD", "pct": 0.025, "dur": 6.0, "delay": 0.0},
			{"sym": "BTC", "pct": 0.03, "dur": 7.0, "delay": 0.0},
			{"sym": "REX", "pct": 0.015, "dur": 7.0, "delay": 0.0},
			{"sym": "JPMG", "pct": -0.012, "dur": 7.0, "delay": 0.0},   # banks earn less when rates drop
		]), _roll_outcome(), walk_back)
	return _shape(_ev("JEROME POWWW", "FED", "FED CHAIR POWWW: RATES HIKED. PARTY'S OVER", [
		{"sym": "GOLD", "pct": -0.012, "dur": 6.0, "delay": 0.0},
		{"sym": "BTC", "pct": -0.03, "dur": 7.0, "delay": 0.0},
		{"sym": "REX", "pct": -0.02, "dur": 7.0, "delay": 0.0},
		{"sym": "BNN", "pct": -0.02, "dur": 7.0, "delay": 0.0},
		{"sym": "JPMG", "pct": 0.02, "dur": 7.0, "delay": 0.0},        # ...and more when they go up
	]), _roll_outcome(), walk_back)


func _breaking() -> Dictionary:
	var items := [
		["REX MOTORS CEO ARRESTED FOR TWEETING", "REX", -0.06],
		["REX MOTORS UNVEILS FLYING CYBERVAN", "REX", 0.05],
		["BANANA COIN LISTED ON EVERY EXCHANGE AT ONCE", "BNN", 0.07],
		["BANANA COIN DEV WALLET MOVES 40M COINS: 'JUST TESTING'", "BNN", -0.06],
		["S&P 500 FUTURES LIMIT DOWN OVERNIGHT", "SPX", -0.03],
		["JOBS REPORT CRUSHES EXPECTATIONS", "SPX", 0.02],
		["TANKER STUCK SIDEWAYS IN CANAL AGAIN", "OIL", 0.04],
		["OPEC SAYS 'WE HAVE TOO MUCH OIL LOL'", "OIL", -0.035],
		["MAJOR EXCHANGE 'MISPLACES' 90K BITCOIN", "BTC", -0.045],
		["COUNTRY MAKES BITCOIN LEGAL TENDER (IT'S A SMALL ONE)", "BTC", 0.03],
		["CENTRAL BANKS HOARDING GOLD IN SECRET BUNKERS", "GOLD", 0.02],
		["WAGMI DEV WALLET MOVES 90% OF SUPPLY", "WAGMI", -0.4],
		["NVIDOOH UNVEILS AI CHIP THAT WRITES ITS OWN EARNINGS", "NVDUH", 0.06],
		["NVIDOOH CHIPS FOUND TO BE 90% FAN", "NVDUH", -0.07],
		["PEAR LAUNCHES THE iPEAR 17. IT'S THE SAME PHONE", "PEAR", -0.03],
		["PEAR BUYS A SMALL COUNTRY FOR THE VIBES", "PEAR", 0.03],
		["AIR EXCESS LOSES ANOTHER DOOR MID-FLIGHT", "AIRX", -0.07],
		["BURGER BARON E. COLI SCARE IN 40 STATES", "BURG", -0.06],
		["PHARMABRO CLAIMS IT CURED BALDNESS", "PHRM", 0.08],
		["PHARMABRO CEO SUBPOENAED (AGAIN)", "PHRM", -0.06],
		["JP MORGUN LOSES $2B TO A 'FAT FINGER'", "JPMG", -0.05],
		["COLD SNAP: NATURAL GAS DEMAND SPIKES", "GAS", 0.06],
		["GAMESHOP CEO POSTS A PICTURE OF A FROG", "GAMR", 0.1],
		["ETHERIUM UPGRADE DELAYED FOR THE 9TH TIME", "ETHR", -0.05],
		["DOGGO COIN ACCEPTED AT BURGER BARON", "DOGGO", 0.12],
	]
	var it: Array = _pick(items)
	var pct: float = it[2] * rng.randf_range(0.8, 1.2)
	return _shape(_ev("BREAKING", "BREAKING", "BREAKING: " + it[0], [{"sym": it[1], "pct": pct, "dur": rng.randf_range(4.0, 8.0), "delay": 0.0}]),
		_roll_outcome(), "CORRECTION: THAT %s REPORT WAS FALSE. WE REGRET THE ERROR" % it[1])


## can_fake = false: a "fake" roll comes out priced in instead (nobody retracts a cat meme).
func _roll_outcome(can_fake := true) -> String:
	var r := rng.randf()
	for k in OUTCOMES:
		r -= OUTCOMES[k]
		if r < 0.0:
			return "priced_in" if k == "fake" and not can_fake else k
	return "real"


## Split the headline's first wave into the leak (before it airs) and the rest,
## then bend it to the outcome. fake_line = the CORRECTION chyron.
func _shape(ev: Dictionary, outcome: String, fake_line: String) -> Dictionary:
	var leak := rng.randf_range(LEAK_MIN, LEAK_MAX)
	var out: Array = []
	var first := ""                     # the ticker the follow-up chyron is about
	var fake_at := rng.randf_range(3.5, 7.0)
	var pull_at := rng.randf_range(1.0, 2.5)
	for e in ev.effects:
		if e.get("delay", 0.0) > 0.0:   # already a second wave (Kitteh's dump): keep it
			out.append(e)
			continue
		if first.is_empty():
			first = e.sym
		var pct: float = e.pct
		match outcome:
			"priced_in":
				var pre := pct * 0.85
				out.append({"sym": e.sym, "pct": pre, "dur": LEAK_S, "delay": 0.0, "pre": true})
				out.append({"sym": e.sym, "pct": (1.0 + pct) / (1.0 + pre) - 1.0, "dur": 2.0, "delay": 0.0})
				out.append({"sym": e.sym, "pct": (1.0 - pct * 0.55) / (1.0 + pct) - 1.0,
					"dur": rng.randf_range(6.0, 9.0), "delay": pull_at})
			"fake":
				var pre := pct * leak
				out.append({"sym": e.sym, "pct": pre, "dur": LEAK_S, "delay": 0.0, "pre": true})
				var post := ((1.0 + pct) / (1.0 + pre) - 1.0) * 0.5      # it runs out of steam...
				out.append({"sym": e.sym, "pct": post, "dur": e.dur, "delay": 0.0})
				out.append({"sym": e.sym, "pct": (1.0 - pct * 0.15) / ((1.0 + pre) * (1.0 + post)) - 1.0,
					"dur": rng.randf_range(3.0, 5.0), "delay": fake_at})
			_:
				var pre := pct * leak
				out.append({"sym": e.sym, "pct": pre, "dur": LEAK_S, "delay": 0.0, "pre": true})
				out.append({"sym": e.sym, "pct": (1.0 + pct) / (1.0 + pre) - 1.0, "dur": e.dur, "delay": 0.0})
	if not first.is_empty() and rng.randf() < KNEE_CHANCE:
		var dir := 1.0 if ev.effects[0].pct > 0.0 else -1.0
		var k := rng.randf_range(KNEE_MIN, KNEE_MAX)
		out.append({"sym": first, "pct": -dir * k, "dur": 0.6, "delay": 0.0})
		out.append({"sym": first, "pct": 1.0 / (1.0 - k) - 1.0 if dir > 0.0 else 1.0 / (1.0 + k) - 1.0,
			"dur": 1.2, "delay": 0.6})
	ev.effects = out
	ev["outcome"] = outcome
	match outcome:
		"priced_in":
			ev.hint += " — but it's PRICED IN: sells off once it airs"
			ev["followup"] = {"at": REACTION_DELAY + pull_at + 2.0, "speaker": "ANALYSTS", "role": "TV",
				"headline": "ANALYSTS: THE %s NEWS WAS ALREADY PRICED IN. SELL THE NEWS" % first}
		"fake":
			ev.hint += " — FAKE NEWS: a correction reverses it"
			ev["followup"] = {"at": REACTION_DELAY + fake_at - 0.5, "speaker": ev.speaker, "role": ev.role,
				"headline": fake_line}
		_:
			if ev.speaker != "ROARING KITTEH":
				ev.hint += " — the real deal"
	return ev


## The leak: the "pre" part of the move starts now, LEAK_S before the headline
## airs, and the ticker goes into a fast market.
func leak(market, ev: Dictionary) -> void:
	if ev.get("leaked", false):
		return
	ev["leaked"] = true
	for e in ev.effects:
		if e.get("pre", false):
			market.add_impulse(e.sym, e.pct, e.dur, 0.0)
			market.start_fast(e.sym)


## The headline airs: push the rest of its effects into the market (and the leak
## too if it never got the chance, e.g. a headline scheduled at the last second).
func apply(market, ev: Dictionary) -> void:
	var leaked: bool = ev.get("leaked", false)
	for e in ev.effects:
		if e.get("pre", false):
			if not leaked:
				market.add_impulse(e.sym, e.pct, e.dur, 0.0)
			market.start_fast(e.sym)
			continue
		market.add_impulse(e.sym, e.pct, e.dur, REACTION_DELAY + e.get("delay", 0.0))
		if e.get("delay", 0.0) <= 0.0:
			market.start_fast(e.sym)
