extends RefCounted
## News / streamer event deck. The server pre-rolls the NEXT event so items
## like the Insider Tip can reveal it early. Every event is parody.
##
## Event dictionary:
##   speaker  : who is talking (shown on the TV chyron)
##   role     : "PRESIDENT" / "STREAMER" / "FED" / "BREAKING" / "TV"
##   headline : chyron text
##   effects  : [{sym, pct, dur, delay}] — price impulses (delay is after REACTION_DELAY)
##   hint     : short "what really happens" string for tips (e.g. "OIL ▲ big")

const REACTION_DELAY := 1.5   # seconds between headline and the market reacting

const SYMS := ["BTC", "GOLD", "OIL", "SPX", "BNN", "REX", "WAGMI"]
const TRAMP_MULT := 1.7   # "you're one post away from getting rich... or losing it all"

var rng: RandomNumberGenerator


func _init(r: RandomNumberGenerator) -> void:
	rng = r


func _pick(arr: Array):
	return arr[rng.randi() % arr.size()]


func _dir_word(d: int) -> String:
	return "LONG" if d > 0 else "SHORT"


func _arrow(pct: float) -> String:
	return "UP" if pct > 0 else "DOWN"


func roll() -> Dictionary:
	var roll_v := rng.randf()
	if roll_v < 0.22:
		return _tramp()
	elif roll_v < 0.40:
		return _tjz()
	elif roll_v < 0.54:
		return _kimchee()
	elif roll_v < 0.64:
		return _crammer()
	elif roll_v < 0.72:
		return _kitteh()
	elif roll_v < 0.84:
		return _fed()
	else:
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
	]
	var l: Array = _pick(lines)
	var effects: Array = []
	for pair in l[1]:
		effects.append({"sym": pair[0], "pct": pair[1] * TRAMP_MULT * rng.randf_range(0.8, 1.25), "dur": rng.randf_range(3.0, 6.0), "delay": 0.0})
	return _ev("TRAMP", "PRESIDENT", "TRAMP: " + l[0], effects)


## TJR-style day-trading streamer. Right ~65% of the time.
func _tjz() -> Dictionary:
	var sym: String = _pick(["BTC", "GOLD", "OIL", "REX", "BNN"])
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
func _kimchee() -> Dictionary:
	var rug := rng.randf() < 0.7
	var pump := rng.randf_range(0.15, 0.4)
	var effects := [{"sym": "WAGMI", "pct": pump, "dur": rng.randf_range(8.0, 14.0), "delay": 0.0}]
	if rug:
		effects.append({"sym": "WAGMI", "pct": -rng.randf_range(0.35, 0.6), "dur": rng.randf_range(2.0, 4.0), "delay": rng.randf_range(16.0, 24.0)})
	var line: String = _pick([
		"APING MY WHOLE BAG INTO $WAGMI. NFA",
		"$WAGMI TO A BILLI. I'M NOT SELLING (I'M SELLING)",
		"JUST BOUGHT 40 MILLI OF $WAGMI. SEND IT",
		"DEV IS BASED. $WAGMI IS THE ONE. TRUST",
	])
	var ev := _ev("KIMCHEE", "STREAMER", "KIMCHEE: " + line, effects)
	ev.hint = "WAGMI pump%s" % (" then RUG" if rug else " — no rug this time")
	return ev


## Inverse-Cramer: his calls are wrong 75% of the time.
func _crammer() -> Dictionary:
	var sym: String = _pick(["REX", "BNN", "BTC", "OIL"])
	var d := 1 if rng.randf() < 0.5 else -1
	var right := rng.randf() < 0.25
	var move := d * (1 if right else -1) * rng.randf_range(0.015, 0.035)
	var line := "BUY BUY BUY %s! BOOYAH!" % sym if d > 0 else "SELL SELL SELL %s! GET OUT NOW!" % sym
	var ev := _ev("JIM CRAMMER", "TV", "JIM CRAMMER: " + line, [{"sym": sym, "pct": move, "dur": rng.randf_range(6.0, 10.0), "delay": 0.0}])
	ev.hint = "Crammer is %s — %s %s" % ["RIGHT (rare)" if right else "WRONG (as usual)", sym, _arrow(move)]
	return ev


## Roaring-Kitty-style meme-stock legend. Posts a single emoji, REX goes nuts.
func _kitteh() -> Dictionary:
	var effects := [{"sym": "REX", "pct": rng.randf_range(0.05, 0.1), "dur": rng.randf_range(5.0, 9.0), "delay": 0.0}]
	if rng.randf() < 0.5:
		effects.append({"sym": "REX", "pct": -rng.randf_range(0.04, 0.08), "dur": 6.0, "delay": rng.randf_range(14.0, 20.0)})
	var line: String = _pick(["*posts a single cat meme*", "I LIKE THE STOCK.", "*is streaming in a headband*"])
	return _ev("ROARING KITTEH", "STREAMER", "ROARING KITTEH: " + line, effects)


func _fed() -> Dictionary:
	var cut := rng.randf() < 0.55
	if cut:
		return _ev("JEROME POWWW", "FED", "FED CHAIR POWWW: RATES CUT. MONEY PRINTER GO BRRR", [
			{"sym": "GOLD", "pct": 0.025, "dur": 6.0, "delay": 0.0},
			{"sym": "BTC", "pct": 0.03, "dur": 7.0, "delay": 0.0},
			{"sym": "REX", "pct": 0.015, "dur": 7.0, "delay": 0.0},
		])
	return _ev("JEROME POWWW", "FED", "FED CHAIR POWWW: RATES HIKED. PARTY'S OVER", [
		{"sym": "GOLD", "pct": -0.012, "dur": 6.0, "delay": 0.0},
		{"sym": "BTC", "pct": -0.03, "dur": 7.0, "delay": 0.0},
		{"sym": "REX", "pct": -0.02, "dur": 7.0, "delay": 0.0},
		{"sym": "BNN", "pct": -0.02, "dur": 7.0, "delay": 0.0},
	])


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
	]
	var it: Array = _pick(items)
	var pct: float = it[2] * rng.randf_range(0.8, 1.2)
	return _ev("BREAKING", "BREAKING", "BREAKING: " + it[0], [{"sym": it[1], "pct": pct, "dur": rng.randf_range(4.0, 8.0), "delay": 0.0}])


## Push the event's effects into the market.
func apply(market, ev: Dictionary) -> void:
	for e in ev.effects:
		market.add_impulse(e.sym, e.pct, e.dur, REACTION_DELAY + e.get("delay", 0.0))
