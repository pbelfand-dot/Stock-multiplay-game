extends RefCounted
## Accounts + leveraged positions (CFD-style, like the terminal in the trailer).
##
##   notional = margin * leverage
##   units    = notional / entry
##   pnl      = units * (price - entry) * side        (side: +1 long / -1 short)
##   fee      = notional * fee_rate, paid on open
##   liquidated when pnl <= -margin (you lose the margin, nothing more)
##   tp / sl: optional take-profit / stop-loss prices (0 = off), auto-closed
##
## Co-op: every player trades from account 0 (the shared fund).
## PvP:   every player has their own account keyed by peer id.

const FEE_RATE := 0.0015   # 0.15% of notional per open (clip: $400 x125 -> $75 fee)
const LEVERAGES := [1, 5, 10, 25, 50, 100, 125]

var accounts := {}   # id -> {id, name, balance, positions: [], closed: int, day_start: float}
var _next_pid := 1


func create_account(id: int, acct_name: String, balance: float) -> void:
	accounts[id] = {"id": id, "name": acct_name, "balance": balance, "positions": [],
		"closed": 0, "day_start": balance, "busted": false}


func has(id: int) -> bool:
	return accounts.has(id)


func get_acct(id: int) -> Dictionary:
	return accounts.get(id, {})


static func pnl_of(pos: Dictionary, price: float) -> float:
	return pos.units * (price - pos.entry) * pos.side


## Returns {ok, error, pos}
func open_position(acct_id: int, sym: String, side: int, margin: float, lev: int,
		price: float, trader: String, fee_rate: float = FEE_RATE, spread: float = 0.0) -> Dictionary:
	if not accounts.has(acct_id):
		return {"ok": false, "error": "No account"}
	var a: Dictionary = accounts[acct_id]
	if a.busted:
		return {"ok": false, "error": "Account busted"}
	if side != 1 and side != -1:
		return {"ok": false, "error": "Bad side"}
	if not lev in LEVERAGES:
		return {"ok": false, "error": "Bad leverage"}
	if margin <= 0.0 or price <= 0.0:
		return {"ok": false, "error": "Bad size"}
	var notional := margin * lev
	var fee := notional * fee_rate
	if margin + fee > a.balance + 0.001:
		return {"ok": false, "error": "Not enough cash"}
	a.balance -= margin + fee
	price *= 1.0 + side * spread * 0.5   # you buy the ask / sell the bid
	var pos := {"pid": _next_pid, "sym": sym, "side": side, "margin": margin, "lev": lev,
		"entry": price, "units": notional / price, "fee": fee, "trader": trader, "tp": 0.0, "sl": 0.0}
	_next_pid += 1
	a.positions.append(pos)
	return {"ok": true, "pos": pos}


## Returns {ok, pnl, pct, pos, liquidated}
func close_position(acct_id: int, pid: int, price: float, liquidated: bool = false) -> Dictionary:
	if not accounts.has(acct_id):
		return {"ok": false}
	var a: Dictionary = accounts[acct_id]
	for i in a.positions.size():
		var pos: Dictionary = a.positions[i]
		if pos.pid == pid:
			var pnl := pnl_of(pos, price)
			if liquidated or pnl <= -pos.margin:
				pnl = -pos.margin
				liquidated = true
			a.balance += pos.margin + pnl
			a.positions.remove_at(i)
			a.closed += 1
			return {"ok": true, "pnl": pnl, "pct": pnl / pos.margin * 100.0,
				"pos": pos, "liquidated": liquidated}
	return {"ok": false}


## Price at which this position gets liquidated (pnl == -margin).
static func liq_price(pos: Dictionary) -> float:
	return pos.entry - pos.side * pos.margin / pos.units


## Set take-profit / stop-loss (0 = remove). A TP must be on the profit side of
## the entry, a SL on the loss side (but before liquidation). Returns ok.
func set_tpsl(acct_id: int, pid: int, tp: float, sl: float) -> bool:
	for pos in accounts.get(acct_id, {}).get("positions", []):
		if pos.pid != pid:
			continue
		if tp > 0.0 and (tp - pos.entry) * pos.side <= 0.0:
			return false
		if sl > 0.0 and ((pos.entry - sl) * pos.side <= 0.0 or (sl - liq_price(pos)) * pos.side <= 0.0):
			return false
		pos.tp = maxf(tp, 0.0)
		pos.sl = maxf(sl, 0.0)
		return true
	return false


## Positions whose TP or SL was touched: closes them at the current price.
## Returns close results with "acct" and "trigger" ("TP" / "SL").
func check_triggers(price_fn: Callable) -> Array:
	var out: Array = []
	for id in accounts:
		var hits: Array = []
		for pos in accounts[id].positions:
			var p: float = price_fn.call(pos.sym)
			if pos.get("tp", 0.0) > 0.0 and (p - pos.tp) * pos.side >= 0.0:
				hits.append([pos.pid, p, "TP"])
			elif pos.get("sl", 0.0) > 0.0 and (p - pos.sl) * pos.side <= 0.0:
				hits.append([pos.pid, p, "SL"])
		for h in hits:
			var r := close_position(id, h[0], h[1])
			if r.ok:
				r["acct"] = id
				r["trigger"] = h[2]
				out.append(r)
	return out


## price_fn: Callable(sym) -> float. Returns array of liquidation results.
func check_liquidations(price_fn: Callable) -> Array:
	var out: Array = []
	for id in accounts:
		var a: Dictionary = accounts[id]
		var to_liq: Array = []
		for pos in a.positions:
			if pnl_of(pos, price_fn.call(pos.sym)) <= -pos.margin:
				to_liq.append(pos.pid)
		for pid in to_liq:
			var r := close_position(id, pid, 0.0, true)
			r["acct"] = id
			out.append(r)
	return out


func close_all(acct_id: int, price_fn: Callable) -> Array:
	var out: Array = []
	if not accounts.has(acct_id):
		return out
	var pids: Array = []
	for pos in accounts[acct_id].positions:
		pids.append(pos.pid)
	for pid in pids:
		var sym := ""
		for pos in accounts[acct_id].positions:
			if pos.pid == pid:
				sym = pos.sym
		var r := close_position(acct_id, pid, price_fn.call(sym))
		r["acct"] = acct_id
		out.append(r)
	return out


func equity(acct_id: int, price_fn: Callable) -> float:
	var a: Dictionary = accounts.get(acct_id, {})
	if a.is_empty():
		return 0.0
	var e: float = a.balance
	for pos in a.positions:
		e += pos.margin + maxf(pnl_of(pos, price_fn.call(pos.sym)), -pos.margin)
	return e


func open_pnl(acct_id: int, price_fn: Callable) -> float:
	var a: Dictionary = accounts.get(acct_id, {})
	var t := 0.0
	for pos in a.get("positions", []):
		t += maxf(pnl_of(pos, price_fn.call(pos.sym)), -pos.margin)
	return t


func adjust(acct_id: int, amount: float) -> void:
	if accounts.has(acct_id):
		accounts[acct_id].balance = maxf(accounts[acct_id].balance + amount, 0.0)


func payload() -> Dictionary:
	return accounts.duplicate(true)
