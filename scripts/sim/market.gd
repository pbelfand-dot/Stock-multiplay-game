extends RefCounted
## Server-side market simulation. Pure logic — no nodes, no rendering —
## so it can be unit-tested headless and run only on the host.
##
## Price model per asset (per tick, dt seconds):
##   log-return = (trend + mean_reversion + impulses) * dt + vol * sqrt(dt) * N(0,1)
## Trend is a regime that flips every 8–25 s. Impulses come from news events
## and let skilled players "read the tape" after a headline.

const CANDLE_SECONDS := 5.0
const MAX_CANDLES := 120

## sym, name, kind, start price, per-second volatility
const ASSET_DEFS := [
	{"sym": "BTC", "name": "Bitcoin", "kind": "Crypto", "price": 1000.0, "vol": 0.0012},
	{"sym": "GOLD", "name": "Gold", "kind": "Commodity", "price": 1500.0, "vol": 0.0005},
	{"sym": "OIL", "name": "Crude Oil", "kind": "Commodity", "price": 1500.0, "vol": 0.0008},
	{"sym": "BNN", "name": "Banana Corp", "kind": "Stock", "price": 100.0, "vol": 0.0009},
	{"sym": "REX", "name": "Rex Motors", "kind": "Stock", "price": 1500.0, "vol": 0.0007},
	{"sym": "WAGMI", "name": "WAGMI Coin", "kind": "Memecoin", "price": 0.42, "vol": 0.0035},
]

var assets: Array = []          # Array[Dictionary]
var time := 0.0                 # seconds since market open (monotonic across days)
var candle_index := 0           # index of the currently forming candle
var rng := RandomNumberGenerator.new()


func _init(seed_value: int = 0) -> void:
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	for d in ASSET_DEFS:
		var a := {
			"sym": d.sym, "name": d.name, "kind": d.kind,
			"price": d.price, "base": d.price, "open_day": d.price,
			"vol": d.vol, "trend": 0.0, "trend_timer": 0.0,
			"impulses": [],       # [{delay, dur, rate}] rate = log-return per second
			"candles": [],        # completed: [o, h, l, c, v]
			"cur": [d.price, d.price, d.price, d.price, 0.0],
		}
		assets.append(a)


func index_of(sym: String) -> int:
	for i in assets.size():
		if assets[i].sym == sym:
			return i
	return -1


func price(i: int) -> float:
	return assets[i].price


func price_of(sym: String) -> float:
	var i := index_of(sym)
	return assets[i].price if i >= 0 else 0.0


func _gauss() -> float:
	return rng.randfn(0.0, 1.0)


## Queue a price move: total_pct (e.g. +0.03 = +3%) spread over dur seconds,
## starting after delay seconds.
func add_impulse(sym: String, total_pct: float, dur: float, delay: float = 0.0) -> void:
	var i := index_of(sym)
	if i < 0:
		return
	dur = maxf(dur, 0.25)
	var rate := log(1.0 + total_pct) / dur
	assets[i].impulses.append({"delay": delay, "dur": dur, "rate": rate})


## Advance the simulation. Returns true when a candle closed this step.
func step(dt: float) -> bool:
	time += dt
	for a in assets:
		_step_asset(a, dt)
	var new_index := int(floor(time / CANDLE_SECONDS))
	if new_index != candle_index:
		_close_candles()
		candle_index = new_index
		return true
	return false


func _step_asset(a: Dictionary, dt: float) -> void:
	a.trend_timer -= dt
	if a.trend_timer <= 0.0:
		a.trend_timer = rng.randf_range(8.0, 25.0)
		a.trend = rng.randf_range(-0.7, 0.7) * a.vol
	var mr := -0.004 * log(a.price / a.base)
	var impulse := 0.0
	var still: Array = []
	for imp in a.impulses:
		if imp.delay > 0.0:
			imp.delay -= dt
			still.append(imp)
			continue
		var used := minf(dt, imp.dur)
		impulse += imp.rate * (used / dt)
		imp.dur -= dt
		if imp.dur > 0.0:
			still.append(imp)
	a.impulses = still
	var r: float = (a.trend + mr + impulse) * dt + a.vol * sqrt(dt) * _gauss()
	a.price = maxf(a.price * exp(r), 0.0001)
	var c: Array = a.cur
	c[1] = maxf(c[1], a.price)
	c[2] = minf(c[2], a.price)
	c[3] = a.price
	c[4] += absf(r) * 1_000_000.0 * dt + rng.randf() * 20.0 * dt


func _close_candles() -> void:
	for a in assets:
		a.candles.append(a.cur.duplicate())
		if a.candles.size() > MAX_CANDLES:
			a.candles.pop_front()
		a.cur = [a.price, a.price, a.price, a.price, 0.0]


func mark_day_open() -> void:
	for a in assets:
		a.open_day = a.price


func change_pct(i: int) -> float:
	var a: Dictionary = assets[i]
	return (a.price / a.open_day - 1.0) * 100.0


# ---------- network serialisation ----------

## Small per-tick payload: price + forming candle for each asset.
func tick_payload() -> Dictionary:
	var prices := PackedFloat64Array()
	var curs: Array = []
	var lasts: Array = []
	var opens := PackedFloat64Array()
	for a in assets:
		prices.append(a.price)
		curs.append(a.cur)
		lasts.append(a.candles[-1] if not a.candles.is_empty() else a.cur)
		opens.append(a.open_day)
	return {"t": time, "ci": candle_index, "p": prices, "c": curs, "l": lasts, "o": opens}


## Full history for late joiners.
func full_payload() -> Dictionary:
	var out: Array = []
	for a in assets:
		out.append({"sym": a.sym, "name": a.name, "kind": a.kind,
			"candles": a.candles.duplicate(true), "cur": a.cur, "price": a.price, "open_day": a.open_day})
	return {"t": time, "ci": candle_index, "assets": out}
