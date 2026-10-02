extends Node
## The match: authoritative on the host, mirrored on every client.
##
## Lives at /root/Main/World/Match on every peer so RPC paths line up.
## Server-only code is guarded with `if not Net.is_server(): return`.
## UI reads the mirrored vars below and listens to the signals.

const Market = preload("res://scripts/sim/market.gd")
const News = preload("res://scripts/sim/news.gd")
const Ledger = preload("res://scripts/sim/ledger.gd")
const Rules = preload("res://scripts/sim/rules.gd")
const SaveGame = preload("res://scripts/net/save_game.gd")
const Brands = preload("res://scripts/sim/brands.gd")
const DayEvents = preload("res://scripts/sim/day_events.gd")
const Contracts = preload("res://scripts/sim/contracts.gd")

const TICK := 0.25
const COP_SYNC := 0.1

signal state_changed
signal market_full
signal market_tick
signal news(ev: Dictionary)
signal news_early(ev: Dictionary)
signal tip(hint: String, eta: float)
signal trade_closed(info: Dictionary)
signal trade_opened(info: Dictionary)
signal slot_result(peer: int, reels: Array, payout: float, bet: float)
signal arrested(peer: int, booking_no: int)
signal released(peer: int)
signal raid_changed(target: int, active: bool)
signal day_ended(summary: Dictionary)
signal game_over(summary: Dictionary)
signal toast(msg: String)
signal luxury_bought(peer: int, key: String)
signal pawned(peer: int, key: String)
signal relieved(peer: int, line: String)
signal ranked_up(peer: int, rank: int)
signal posted(ev: Dictionary)
signal chat(from_name: String, msg: String)
signal error_msg(msg: String)
signal contract_done(peer: int, c: Dictionary, cash: float)
signal shock(kind: String, stage: String)
signal milestone(amount: float, xp: float)
signal saved(info: Dictionary)
signal cash_moved(peer: int, withdrawn: float, total: float)
signal shot(peer: int, hit: Vector3)
signal pursuit_changed(peer: int, stage: String)   # "start" / "lost" / "busted"
signal morning(late_by: Dictionary)                 # everyone wakes up at home     # someone fired (hit = where the round landed)

# ---------------- mirrored state (all peers) ----------------
var phase := "lobby"            # lobby | trading | intermission | gameover
var day := 0
var time_left := 0.0
var quota := 0.0
var accounts := {}              # ledger payload
var heat := {}                  # peer -> float
var jail := {}                  # peer -> seconds left
var inventory := {}             # peer -> {item: count}
var owned := {}                 # peer -> {luxury: count} (flex items, never consumed)
var pressure := {}              # peer -> blood pressure 0..100 (see Rules.PRESSURE_*)
var careers := {}               # peer -> {xp, rank, best_day, days} (host-saved by name)
const CAREER_PATH := "user://careers.cfg"
var effects := {}               # peer -> {effect: seconds left}
var stats := {}                 # peer -> {pnl_day, pnl_total, trades, arrests, biggest}
var raid := {}                  # {target, t} when active
var last_news := {}
var news_log: Array = []
var m_assets: Array = []        # client market mirror: [{sym,name,kind,candles,cur,price,open_day}]
var fast_mkt := {}              # client mirror: tickers in a fast market -> spread multiplier now
var m_ci := 0
var day_event := ""             # today's random event (DayEvents), "" = a normal day
var next_event := ""            # tomorrow's, rolled at the closing bell (the forecast)
var event_at := -1.0            # time_left when today's announced shock hits (Fed / earnings), -1 = none
var halt := 0.0                 # circuit breaker: seconds of trading halt left
var contracts := {}             # peer -> [contract] (Tony's contracts for today)
var milestones := 0             # co-op: how many fund milestones this run has hit
var wallet := {}                # peer -> cash on hand (out of the ATM), counts toward the quota
var spreads := {}               # peer -> {pos, yaw, amount}: cash laid out for the photo
var drawn := {}                 # peer -> gun key they're holding out (BIG IRON)
var late := {}                  # this morning: peer -> seconds they overslept
var arrived := {}               # this morning: peer -> seconds late when they got to the office (0 = on time)
var _last_shot := {}            # server: peer -> time of their last shot (rate + "called in")
var ready_up := {}                 # peer -> true: pressed ENTER, waiting for the bell (lobby / after hours)

# ---------------- server-only ----------------
var market
var newsdeck
var ledger
var rng := RandomNumberGenerator.new()
var _acc := 0.0
var _cop_acc := 0.0
var _next_event: Dictionary = {}
var _next_event_in := 0.0
var _post_sent := false
var _leaked := false              # the next headline's leak has started (News.LEAK_S before it airs)
var _followups: Array = []        # [{in, ev}] second chyrons: corrections, "priced in"
var _booking_no := 4298
var _dirty := false
var save_slot := ""              # this run autosaves here at every closing bell ("" = don't save)
var _resume := {}                # a loaded save: players get their things back by name as they join
var _restored := {}              # peer -> true once their saved things were handed back
var _sched: Array = []           # today's timed shocks (DayEvents.schedule)
var _day_len := Rules.DAY_SECONDS
var _early_to := {}              # peer -> true once they got the next headline early
var _raid_warned := {}           # police scanner: peer -> warned
var _halt_shock := {}            # the crash that tripped the circuit breaker
var _morning := {}               # the run as it stood at this morning's bell (what a mid-day save keeps)

@onready var world = get_parent()


func _ready() -> void:
	if Net.is_server():
		rng.randomize()
		market = Market.new()
		newsdeck = News.new(rng)
		ledger = Ledger.new()
		ledger.exit_cost = _exit_cost
		# Pre-warm some history so the charts aren't empty.
		for i in 1200:
			market.step(TICK)
		market.mark_day_open()
		_reset_run()
		_open_save()
		_mirror_market_full(market.full_payload())
	else:
		_ask_for_sync()
	Net.players_changed.connect(_on_players_changed)


## Joining: ask the host for the market until it arrives. On a loaded host the first
## request (or its answer) can go missing while both sides are still building the world,
## and without the market the client would sit in the lobby forever.
func _ask_for_sync() -> void:
	while m_assets.is_empty() and is_inside_tree() and multiplayer.has_multiplayer_peer():
		_req_sync.rpc_id(1)
		await get_tree().create_timer(2.0).timeout


# ======================================================================
# helpers usable everywhere
# ======================================================================

func acct_for(peer: int) -> int:
	return 0 if Net.mode == "coop" else peer


func my_acct() -> Dictionary:
	return accounts.get(acct_for(Net.my_id()), {})


func price_of(sym: String) -> float:
	for a in m_assets:
		if a.sym == sym:
			return a.price
	return 0.0


func asset_mirror(sym: String) -> Dictionary:
	for a in m_assets:
		if a.sym == sym:
			return a
	return {}


func is_jailed(peer: int) -> bool:
	return jail.get(peer, 0.0) > 0.0


func effect_left(peer: int, eff: String) -> float:
	return effects.get(peer, {}).get(eff, 0.0)


func item_count(peer: int, item: String) -> int:
	return inventory.get(peer, {}).get(item, 0)


## What a trader's rank, flex and office upgrades give them (Rules.perks_for).
func perks(peer: int) -> Dictionary:
	return Rules.perks_for(rank_idx(peer), owned.get(peer, {}))


## Today's day-event modifier (DayEvents.MODS), or `default` on a normal day.
func ev_mod(key: String, default = 1.0):
	return DayEvents.mod(day_event, key, default)


## The bid/ask spread this trader pays on this ticker right now (fast market,
## their perks, the day's event).
func spread_for(peer: int, sym: String) -> float:
	return market.spread_of(sym) * perks(peer).spread * float(ev_mod("spread"))


## Getting out: half the spread + slippage on the size (Ledger.exit_cost).
func _exit_cost(pos: Dictionary, price: float) -> float:
	return spread_for(int(pos.get("trader_id", 0)), pos.sym) * 0.5 + market.impact(pos.sym, pos.units * price)


## Boutique price right now (Black Friday takes its cut).
func lux_price(key: String) -> float:
	return float(Rules.LUXURY[key].price) * (1.0 - float(ev_mod("lux_discount", 0.0)))


## The heat where the cops come (a crackdown lowers it).
func raid_threshold() -> float:
	return float(ev_mod("raid_at", Rules.HEAT_MAX))


func halted() -> bool:
	return halt > 0.0


func equity_of(acct_id: int) -> float:
	var a: Dictionary = accounts.get(acct_id, {})
	if a.is_empty():
		return 0.0
	var e: float = a.balance
	for pos in a.positions:
		e += pos.margin + maxf(Ledger.pnl_of(pos, price_of(pos.sym)), -pos.margin)
	return e


# ======================================================================
# client -> server requests
# ======================================================================

@rpc("any_peer", "reliable")
func _req_sync() -> void:
	if not Net.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	_ensure_peer(id)
	_s_market_full.rpc_id(id, market.full_payload())
	_push_state()
	if not last_news.is_empty():
		_s_news.rpc_id(id, last_news)


func request_start() -> void:
	_req_start.rpc_id(1)


## ENTER: in the lobby and after hours it toggles your READY; the bell rings
## once everyone in the office is ready. After a run is over the host's
## ENTER takes everyone back to the lobby.
@rpc("any_peer", "call_local", "reliable")
func _req_start() -> void:
	if not Net.is_server():
		return
	var id := _sender()
	if phase == "lobby" or phase == "intermission":
		set_ready(id, not ready_up.has(id))
	elif phase == "gameover" and id == 1:
		_reset_run()
		_resume = {}
		_restored.clear()
		if save_slot != "":
			save_slot = SaveGame.new_slot(Net.mode)   # a fresh run gets a fresh save
		_push_state()


## Host: START ANYWAY (somebody went AFK on the street).
func request_force_start() -> void:
	_req_force_start.rpc_id(1)


@rpc("any_peer", "call_local", "reliable")
func _req_force_start() -> void:
	if Net.is_server() and _sender() == 1 and (phase == "lobby" or phase == "intermission"):
		_s_toast.rpc("%s rang the bell anyway." % Net.player_name(1))
		_ring_bell()


func set_ready(id: int, on: bool) -> void:
	if not Net.players.has(id):
		return
	if on:
		ready_up[id] = true
	else:
		ready_up.erase(id)
	var n := ready_count()
	if Net.players.size() > 1:
		_s_toast.rpc("%s is %s (%d/%d ready)" % [Net.player_name(id), "READY" if on else "not ready", n, Net.players.size()])
	_check_ready()
	_push_state()


## How many of the players in the office are ready.
func ready_count() -> int:
	var n := 0
	for id in Net.players:
		if ready_up.has(id):
			n += 1
	return n


func _check_ready() -> void:
	if (phase == "lobby" or phase == "intermission") and not Net.players.is_empty() and ready_count() == Net.players.size():
		_ring_bell()


func _ring_bell() -> void:
	ready_up.clear()
	if phase == "lobby":
		_start_run()
	elif phase == "intermission":
		_to_morning()


# ---------------- the commute ----------------

## Seconds between waking up and the opening bell (0 = no commute: tests,
## or a world without the neighborhood).
func commute_seconds() -> float:
	if Config.cli.has("commute"):
		return float(Config.cli.commute)
	if Config.cli.has("autostart") or world == null or world.get("hood") == null:
		return 0.0
	return Rules.COMMUTE_S


## Everyone wakes up at home; the bell rings when the commute's up.
func _to_morning() -> void:
	var secs := commute_seconds()
	if secs <= 0.0:
		_start_day()
		return
	phase = "morning"
	time_left = secs
	late.clear()
	arrived.clear()
	for id in Net.players:
		var chance := Rules.LATE_CHANCE + (Rules.LATE_BP_BONUS if pressure_of(id) > 60.0 else 0.0)
		if day >= 1 and rng.randf() < chance:
			late[id] = minf(Rules.LATE_SLEEP, secs * 0.6)
		if Config.cli.has("oversleep"):
			late[id] = float(Config.cli.oversleep)
	_s_morning.rpc(late)
	_s_toast.rpc("Morning. The opening bell rings in %d:%02d. Get to BAGHOLDER CAPITAL." % [int(secs) / 60, int(secs) % 60])
	_push_state()


@rpc("authority", "call_local", "reliable")
func _s_morning(late_by: Dictionary) -> void:
	late = late_by
	arrived.clear()
	morning.emit(late_by)


## Made it up the elevator to the trading floor.
func request_arrived() -> void:
	_req_arrived.rpc_id(1)


@rpc("any_peer", "call_local", "reliable")
func _req_arrived() -> void:
	if not Net.is_server():
		return
	var id := _sender()
	if arrived.has(id) or not (phase == "morning" or phase == "trading"):
		return
	if phase == "morning":
		arrived[id] = 0.0
		if Net.players.size() > 1:
			_s_toast.rpc("%s made it in with %d:%02d to spare." % [Net.player_name(id), int(time_left) / 60, int(time_left) % 60])
	else:
		var by := _day_len - time_left
		arrived[id] = by
		_s_toast.rpc("%s strolled in %d:%02d LATE." % [Net.player_name(id), int(by) / 60, int(by) % 60])
	_push_state()


func is_late(peer: int) -> bool:
	return phase == "trading" and not late.is_empty() and not arrived.has(peer) and commute_seconds() > 0.0


# ---------------- cash on hand (ATM, spreads) ----------------

func cash_of(peer: int) -> float:
	return float(wallet.get(peer, 0.0))


## Every trader's cash on hand together (co-op: it's all the desk's money).
func total_cash() -> float:
	var t := 0.0
	for id in wallet:
		t += float(wallet[id])
	return t


## Pay for something: cash on hand first, the account covers the rest.
func _pay(id: int, amount: float) -> bool:
	var acct := acct_for(id)
	var a: Dictionary = ledger.get_acct(acct)
	var cash := cash_of(id)
	if a.is_empty() or cash + float(a.get("balance", 0.0)) < amount:
		return false
	var from_cash := minf(cash, amount)
	wallet[id] = cash - from_cash
	if amount - from_cash > 0.0:
		ledger.adjust(acct, -(amount - from_cash))
	_shrink_spread(id)
	return true


## The ATM: take cash out of the trading account (co-op: the fund) / put it back.
func request_withdraw(amount: float) -> void:
	_req_cash.rpc_id(1, amount)


func request_deposit(amount: float) -> void:
	_req_cash.rpc_id(1, -amount)


@rpc("any_peer", "call_local", "reliable")
func _req_cash(amount: float) -> void:
	if not Net.is_server():
		return
	var id := _sender()
	_ensure_peer(id)
	if is_jailed(id):
		_s_error.rpc_id(id, "No ATMs in jail.")
		return
	var acct := acct_for(id)
	var a: Dictionary = ledger.get_acct(acct)
	var moved := 0.0                                     # + came out, - went in
	if amount > 0.0:                                     # withdraw
		amount = minf(amount, float(a.get("balance", 0.0)))
		if amount < 1.0:
			_s_error.rpc_id(id, "Insufficient funds. Go make some trades.")
			return
		ledger.adjust(acct, -amount)
		wallet[id] = cash_of(id) + amount
		moved = amount
		if Net.mode == "coop" and Net.players.size() > 1:
			_s_toast.rpc("%s pulled %s out of the fund in cash" % [Net.player_name(id), Rules.money(amount)])
	else:                                                # deposit
		amount = minf(-amount, cash_of(id))
		if amount < 1.0:
			return
		wallet[id] = cash_of(id) - amount
		ledger.adjust(acct, amount)
		_shrink_spread(id)
		moved = -amount
	_s_cash.rpc(id, moved, cash_of(id))
	_push_state()


## Lay your cash out on the floor / a table for the photo (everyone sees it).
## Nobody can take it; it's still your wallet. amount 0 = pick it back up.
func request_spread(pos: Vector3, yaw: float, pick_up: bool) -> void:
	_req_spread.rpc_id(1, pos, yaw, pick_up)


@rpc("any_peer", "call_local", "reliable")
func _req_spread(pos: Vector3, yaw: float, pick_up: bool) -> void:
	if not Net.is_server():
		return
	var id := _sender()
	if pick_up or cash_of(id) < 100.0:
		spreads.erase(id)
	else:
		spreads[id] = {"pos": pos, "yaw": yaw, "amount": cash_of(id)}
	_push_state()


func _shrink_spread(id: int) -> void:
	if spreads.has(id):
		if cash_of(id) < 100.0:
			spreads.erase(id)
		else:
			spreads[id].amount = cash_of(id)


@rpc("authority", "call_local", "reliable")
func _s_cash(peer: int, amount: float, total: float) -> void:
	cash_moved.emit(peer, amount, total)


# ---------------- cars ----------------

## The car you drive: the one you picked at the dealership, else your best
## one. "" = no car yet (you start without one: cab it or buy the used TOROLA).
func car_of(peer: int) -> String:
	var ride := lux_count(peer, "ride") - 1
	if ride >= 0 and ride < Rules.CAR_ORDER.size() and owns_car(peer, Rules.CAR_ORDER[ride]):
		return Rules.CAR_ORDER[ride]
	var best := ""
	for k in Rules.SHOW_ORDER:          # cheapest to priciest: the last one owned wins
		if owns_car(peer, k):
			best = k
	return best


func owns_car(peer: int, key: String) -> bool:
	return lux_count(peer, key) > 0


## No car: a cab to work. The meter's on the account (cash first).
func request_cab() -> void:
	_req_cab.rpc_id(1)


@rpc("any_peer", "call_local", "reliable")
func _req_cab() -> void:
	if not Net.is_server():
		return
	var id := _sender()
	if _pay(id, Rules.CAB_FARE):
		_push_state()


func paint_of(peer: int, key: String) -> Color:
	var i := lux_count(peer, "paint_" + key) - 1
	return Rules.PAINTS[i][1] if i >= 0 and i < Rules.PAINTS.size() else Rules.CARS[key].paint


## The dealerships (BEMZE, and the brands round the loop: Brands): buy a car
## in a factory color (it's yours for good, saved with your career) / respray
## one you own / pick which one you drive.
func request_buy_car(key: String, paint: int) -> void:
	_req_car.rpc_id(1, "buy", key, paint)


func request_respray(key: String, paint: int) -> void:
	_req_car.rpc_id(1, "paint", key, paint)


func request_pick_car(key: String) -> void:
	_req_car.rpc_id(1, "pick", key, 0)


@rpc("any_peer", "call_local", "reliable")
func _req_car(what: String, key: String, paint: int) -> void:
	if not Net.is_server() or not key in Rules.CAR_ORDER:
		return
	var id := _sender()
	_ensure_peer(id)
	paint = clampi(paint, 0, Rules.PAINTS.size() - 1)
	var d: Dictionary = Rules.CARS[key]
	match what:
		"buy":
			if owns_car(id, key):
				_s_error.rpc_id(id, "You already own the %s." % d.name)
				return
			if not _pay(id, d.price):
				_s_error.rpc_id(id, "The %s is %s. Go make some trades." % [d.name, Rules.money(d.price)])
				return
			owned[id][key] = 1
			owned[id]["paint_" + key] = paint + 1
			owned[id]["ride"] = Rules.CAR_ORDER.find(key) + 1
			_s_toast.rpc("%s drove a %s %s off the %s lot (%s)" % [Net.player_name(id), Rules.PAINTS[paint][0], d.name,
					Brands.name_of(Brands.of(key)), Rules.money(d.price)])
			_s_luxury.rpc(id, key)
		"paint":
			if not owns_car(id, key) or Rules.CARS[key].model.begins_with("TCar_"):   # the used car's paint is what it is
				return
			if not _pay(id, Rules.RESPRAY):
				_s_error.rpc_id(id, "A respray is %s." % Rules.money(Rules.RESPRAY))
				return
			owned[id]["paint_" + key] = paint + 1
		"pick":
			if not owns_car(id, key):
				return
			owned[id]["ride"] = Rules.CAR_ORDER.find(key) + 1
	_save_careers()
	_push_state()


# ---------------- guns (BIG IRON) ----------------

func gun_of(peer: int) -> String:
	return str(drawn.get(peer, ""))


## The guns you own, in Q order.
func guns_of(peer: int) -> Array:
	return Rules.GUN_ORDER.filter(func(k): return lux_count(peer, k) > 0)


## Q: draw the next gun you own, or put it away after the last one.
func request_draw(key: String) -> void:
	_req_draw.rpc_id(1, key)


@rpc("any_peer", "call_local", "reliable")
func _req_draw(key: String) -> void:
	if not Net.is_server():
		return
	var id := _sender()
	if key == "":
		drawn.erase(id)
	elif Rules.is_gun(key) and lux_count(id, key) > 0 and not is_jailed(id):
		drawn[id] = key
	else:
		return
	_push_state()


## Pulled the trigger (the shooter already saw it; everyone else sees it now).
## Outside the range it brings heat: the first shot after a quiet spell gets
## called in.
func request_shot(hit: Vector3) -> void:
	_req_shot.rpc_id(1, hit)


@rpc("any_peer", "call_local", "unreliable_ordered")
func _req_shot(hit: Vector3) -> void:
	if not Net.is_server():
		return
	var id := _sender()
	var key := gun_of(id)
	if key == "" or is_jailed(id):
		return
	var now := Time.get_ticks_msec() / 1000.0
	var last: float = _last_shot.get(id, -100.0)
	if now - last < float(Rules.LUXURY[key].rate) * 0.6:     # faster than the gun can cycle
		return
	_last_shot[id] = now
	var p = world.player_node(id) if world else null
	if p and world.street_zone(p) != "iron" and phase == "trading":
		var h := Rules.SHOT_HEAT
		if now - last > Rules.SHOTS_QUIET:
			h += Rules.SHOTS_CALLED_IN
			_s_toast.rpc("SHOTS FIRED: %s is letting the %s rip. Somebody called it in." % [
					Net.player_name(id), Rules.LUXURY[key].name])
		_add_heat(id, h)
		_dirty = true
	_s_shot.rpc(id, hit)


@rpc("authority", "call_local", "unreliable_ordered")
func _s_shot(peer: int, hit: Vector3) -> void:
	shot.emit(peer, hit)


func request_open(sym: String, side: int, margin: float, lev: int) -> void:
	_req_open.rpc_id(1, sym, side, margin, lev)


## The terminal's BUY / SELL: SELL first sells the longs YOU hold on this asset
## (BUY first buys back your shorts). With nothing to close it opens a new
## position, with optional auto-sell up/down percentages.
func request_order(sym: String, side: int, margin: float, lev: int, up_pct := 0.0, down_pct := 0.0) -> void:
	_req_order.rpc_id(1, sym, side, margin, lev, up_pct, down_pct)


@rpc("any_peer", "call_local", "reliable")
func _req_order(sym: String, side: int, margin: float, lev: int, up_pct: float, down_pct: float) -> void:
	if not Net.is_server():
		return
	var id := _sender()
	if is_jailed(id):
		_s_error.rpc_id(id, "You're in jail, genius.")
		return
	if _halt_msg(id):
		return
	var acct := acct_for(id)
	var closing: Array = []
	for pos in ledger.get_acct(acct).get("positions", []):
		if pos.sym == sym and pos.side == -side and pos.get("trader_id", id) == id:
			closing.append(pos.pid)
	if not closing.is_empty():
		for pid in closing:
			var r: Dictionary = ledger.close_position(acct, pid, market.price_of(sym))
			if r.ok:
				_after_close(r, acct, id)
		_push_state()
		return
	var before: int = ledger.get_acct(acct).get("positions", []).size()
	_req_open(sym, side, margin, lev)
	var ps: Array = ledger.get_acct(acct).get("positions", [])
	if ps.size() > before and (up_pct > 0.0 or down_pct > 0.0):
		ledger.set_auto_pct(acct, ps[-1].pid, up_pct, down_pct)
		_push_state()


@rpc("any_peer", "call_local", "reliable")
func _req_open(sym: String, side: int, margin: float, lev: int) -> void:
	if not Net.is_server():
		return
	var id := _sender()
	if phase != "trading":
		_s_error.rpc_id(id, "Market's closed. Host presses ENTER to ring the bell.")
		return
	if is_jailed(id):
		_s_error.rpc_id(id, "You're in jail, genius.")
		return
	if _halt_msg(id):
		return
	if pressure_of(id) >= Rules.PRESSURE_FAT_FINGER and rng.randf() < 0.6:
		margin *= 2.0 if rng.randf() < 0.5 else 0.5   # shaking hands: fat-finger the size
		_s_error.rpc_id(id, "FAT FINGER! Your hands are shaking. Go relieve the pressure.")
	if lev > 100 and not has_rank_for(id, "lev_125"):
		_s_error.rpc_id(id, "x125 unlocks at DEGEN. Rookie numbers.")
		return
	var cap := Market.max_lev(sym)
	if lev > cap:
		lev = cap
		_s_error.rpc_id(id, "Your broker caps %s at x%d. Sized down to x%d." % [sym, cap, cap])
	var pk := perks(id)
	var fee_rate: float = 0.0 if effect_left(id, "cigar") > 0.0 else Ledger.FEE_RATE * pk.fee * float(ev_mod("fee"))
	var slip: float = market.impact(sym, margin * lev)
	var r: Dictionary = ledger.open_position(acct_for(id), sym, side, margin, lev,
		market.price_of(sym), Net.player_name(id), fee_rate, spread_for(id, sym), slip)
	if not r.ok:
		_s_error.rpc_id(id, r.error)
		return
	r.pos["trader_id"] = id
	stats[id].trades += 1
	_s_trade_opened.rpc({"acct": acct_for(id), "trader": Net.player_name(id), "pos": r.pos})
	_push_state()


func request_close(pid: int) -> void:
	_req_close.rpc_id(1, pid)


@rpc("any_peer", "call_local", "reliable")
func _req_close(pid: int) -> void:
	if not Net.is_server():
		return
	var id := _sender()
	if is_jailed(id):
		_s_error.rpc_id(id, "You're in jail. Your teammates can close it.")
		return
	if _halt_msg(id):
		return
	var acct := acct_for(id)
	var sym := ""
	for pos in ledger.get_acct(acct).get("positions", []):
		if pos.pid == pid:
			sym = pos.sym
	if sym.is_empty():
		return
	var r: Dictionary = ledger.close_position(acct, pid, market.price_of(sym))
	if r.ok:
		_after_close(r, acct, id)
	_push_state()


## Take-profit / stop-loss for one of your positions (0 = off).
func request_set_tpsl(pid: int, tp: float, sl: float) -> void:
	_req_set_tpsl.rpc_id(1, pid, tp, sl)


@rpc("any_peer", "call_local", "reliable")
func _req_set_tpsl(pid: int, tp: float, sl: float) -> void:
	if not Net.is_server():
		return
	var id := _sender()
	if not ledger.set_tpsl(acct_for(id), pid, tp, sl):
		_s_error.rpc_id(id, "TP goes on the profit side, SL between entry and LIQ.")
	_push_state()


func request_close_all() -> void:
	_req_close_all.rpc_id(1)


@rpc("any_peer", "call_local", "reliable")
func _req_close_all() -> void:
	if not Net.is_server():
		return
	var id := _sender()
	if is_jailed(id) or _halt_msg(id):
		return
	var acct := acct_for(id)
	for r in ledger.close_all(acct, market.price_of):
		if r.ok:
			_after_close(r, acct, id)
	_push_state()


func request_buy(item: String) -> void:
	_req_buy.rpc_id(1, item)


@rpc("any_peer", "call_local", "reliable")
func _req_buy(item: String) -> void:
	if not Net.is_server():
		return
	var id := _sender()
	if not Rules.ITEMS.has(item):
		return
	var def: Dictionary = Rules.ITEMS[item]
	if def.get("pvp_only", false) and Net.mode != "pvp":
		_s_error.rpc_id(id, "Snitching is PvP only.")
		return
	var acct := acct_for(id)
	var a: Dictionary = ledger.get_acct(acct)
	if not _pay(id, def.price):
		_s_error.rpc_id(id, "Can't afford %s." % def.name)
		return
	inventory[id][item] = inventory[id].get(item, 0) + 1
	if Net.mode == "coop":
		_s_toast.rpc("%s spent %s of the fund on %s" % [Net.player_name(id), Rules.money(def.price), def.name])
	_push_state()


func lux_count(peer: int, key: String) -> int:
	return int(owned.get(peer, {}).get(key, 0))


func request_buy_lux(key: String) -> void:
	_req_buy_lux.rpc_id(1, key)


@rpc("any_peer", "call_local", "reliable")
func _req_buy_lux(key: String) -> void:
	if not Net.is_server() or not Rules.LUXURY.has(key):
		return
	var id := _sender()
	_ensure_peer(id)
	var def: Dictionary = Rules.LUXURY[key]
	if not has_rank_for(id, key):
		_s_error.rpc_id(id, "%s unlocks at %s." % [def.name, Rules.RANKS[Rules.RANK_GATES[key]].name])
		return
	if lux_count(id, key) >= int(def.max):
		_s_error.rpc_id(id, "You already flex enough %s." % def.name)
		return
	var acct := acct_for(id)
	var a: Dictionary = ledger.get_acct(acct)
	var price := lux_price(key)
	if a.is_empty() or not _pay(id, price):
		_s_error.rpc_id(id, "Can't afford %s." % def.name)
		return
	owned[id][key] = lux_count(id, key) + 1
	_save_careers()
	_add_heat(id, def.get("heat", 0.0))
	_s_toast.rpc("%s copped a %s (%s%s)" % [Net.player_name(id), def.name, Rules.money(price),
			" — BLACK FRIDAY" if price < def.price else ""])
	_s_luxury.rpc(id, key)
	_contract(id, "lux")
	_push_state()


## Office upgrades: bought once, kept forever (with your career), perks apply.
func request_buy_upgrade(key: String) -> void:
	_req_buy_upgrade.rpc_id(1, key)


@rpc("any_peer", "call_local", "reliable")
func _req_buy_upgrade(key: String) -> void:
	if not Net.is_server() or not Rules.UPGRADES.has(key):
		return
	var id := _sender()
	_ensure_peer(id)
	var def: Dictionary = Rules.UPGRADES[key]
	if lux_count(id, key) > 0:
		_s_error.rpc_id(id, "You already have the %s." % def.name)
		return
	var acct := acct_for(id)
	var a: Dictionary = ledger.get_acct(acct)
	if a.is_empty() or not _pay(id, def.price):
		_s_error.rpc_id(id, "Can't afford the %s." % def.name)
		return
	owned[id][key] = 1
	_save_careers()
	_s_toast.rpc("%s upgraded their desk: %s" % [Net.player_name(id), def.name])
	_s_luxury.rpc(id, key)
	_push_state()


# ---- neighborhood (houses) ----
## Magnolia Heights homes (Rules.HOUSES). One owner per house among the players
## in this session; owned[peer]["house_<id>"] = 1 is saved with the career.

func house_owner(id: String) -> int:
	for peer in owned:
		if Net.players.has(peer) and int(owned[peer].get("house_" + id, 0)) > 0:
			return peer
	return 0


func house_of(peer: int) -> String:
	var own: Dictionary = owned.get(peer, {})
	for id in Rules.HOUSES:
		if int(own.get("house_" + id, 0)) > 0:
			return id
	return ""


func request_buy_house(id: String) -> void:
	_req_buy_house.rpc_id(1, id)


@rpc("any_peer", "call_local", "reliable")
func _req_buy_house(id: String) -> void:
	if not Net.is_server():
		return
	var id_peer := _sender()
	var err := buy_house(id_peer, id)
	if err != "":
		_s_error.rpc_id(id_peer, err)


## Server: the whole purchase. Returns "" or why not.
func buy_house(peer: int, id: String) -> String:
	if not Net.is_server() or not Rules.HOUSES.has(id):
		return "That house isn't for sale."
	_ensure_peer(peer)
	var def: Dictionary = Rules.HOUSES[id]
	var owner := house_owner(id)
	if owner == peer:
		return "You already own %s." % def.address
	if owner != 0:
		return "%s is already SOLD to %s." % [def.address, Net.player_name(owner)]
	if house_of(peer) != "":
		return "You already own %s. One house at a time, tycoon." % Rules.HOUSES[house_of(peer)].address
	var acct := acct_for(peer)
	var a: Dictionary = ledger.get_acct(acct)
	if a.is_empty() or a.balance < def.price:
		return "Can't afford %s (%s). The bank laughed." % [def.address, Rules.money(def.price)]
	ledger.adjust(acct, -def.price)
	owned[peer]["house_" + id] = 1
	_save_careers()
	_s_toast.rpc("%s bought %s (%s) for %s. Home sweet home." % [Net.player_name(peer), def.address, def.name,
			Rules.money(def.price)])
	_push_state()
	return ""
# ---- /neighborhood (houses) ----


# ---------------- careers (host saves them, keyed by player name) ----------------

func xp_of(peer: int) -> float:
	return float(careers.get(peer, {}).get("xp", 0.0))


func rank_idx(peer: int) -> int:
	return Rules.rank_of(xp_of(peer))


func has_rank_for(peer: int, gate: String) -> bool:
	return rank_idx(peer) >= int(Rules.RANK_GATES.get(gate, 0))


## Tests run with --smoke and must not read or write a real career file.
func _careers_on_disk() -> bool:
	return Net.is_server() and not Config.cli.has("smoke") and not Config.cli.has("savecheck") and not Config.cli.has("eventcheck") \
			and not Config.cli.has("hoodcheck") and not Config.cli.has("hoodshots") \
			and not Config.cli.has("commutecheck") and not Config.cli.has("shots") and not Config.cli.has("cabcheck")   # tests never touch the real careers


func _load_career(id: int) -> void:
	var cf := ConfigFile.new()
	if _careers_on_disk():
		cf.load(CAREER_PATH)
	var key := Net.player_name(id).to_lower()
	careers[id] = {"xp": float(cf.get_value(key, "xp", 0.0)), "best_day": float(cf.get_value(key, "best_day", 0.0)),
		"days": int(cf.get_value(key, "days", 0))}
	owned[id] = cf.get_value(key, "owned", {})


func _save_careers() -> void:
	if not _careers_on_disk():
		return
	var cf := ConfigFile.new()
	cf.load(CAREER_PATH)
	for id in careers:
		if not Net.players.has(id):
			continue
		var key := Net.player_name(id).to_lower()
		cf.set_value(key, "xp", careers[id].xp)
		cf.set_value(key, "best_day", careers[id].best_day)
		cf.set_value(key, "days", careers[id].days)
		cf.set_value(key, "owned", owned.get(id, {}))
	cf.save(CAREER_PATH)


## Returns {gain, xp, rank, ranked_up}
func _add_xp(id: int, gain: float, pnl_day: float) -> Dictionary:
	_ensure_peer(id)
	var c: Dictionary = careers[id]
	var before := Rules.rank_of(c.xp)
	c.xp += gain
	c.days += 1
	c.best_day = maxf(c.best_day, pnl_day)
	var after := Rules.rank_of(c.xp)
	if after > before:
		_s_rank_up.rpc(id, after)
	return {"gain": gain, "xp": c.xp, "rank": after, "ranked_up": after > before}


@rpc("authority", "call_local", "reliable")
func _s_rank_up(peer: int, rank: int) -> void:
	ranked_up.emit(peer, rank)


## Pawn King: sell a luxury item back for half its price.
func request_pawn(key: String) -> void:
	_req_pawn.rpc_id(1, key)


@rpc("any_peer", "call_local", "reliable")
func _req_pawn(key: String) -> void:
	if not Net.is_server() or not Rules.LUXURY.has(key):
		return
	var id := _sender()
	if lux_count(id, key) <= 0:
		return
	owned[id][key] = lux_count(id, key) - 1
	if gun_of(id) == key and lux_count(id, key) <= 0:
		drawn.erase(id)
	var cash: float = Rules.LUXURY[key].price * Rules.PAWN_RATE
	ledger.adjust(acct_for(id), cash)
	_s_toast.rpc("%s pawned a %s for %s" % [Net.player_name(id), Rules.LUXURY[key].name, Rules.money(cash)])
	_s_pawned.rpc(id, key)
	_save_careers()
	_push_state()


## The hot dog cart: $20, knocks your blood pressure down.
func request_hotdog() -> void:
	_req_hotdog.rpc_id(1)


@rpc("any_peer", "call_local", "reliable")
func _req_hotdog() -> void:
	if not Net.is_server():
		return
	var id := _sender()
	_ensure_peer(id)
	var a: Dictionary = ledger.get_acct(acct_for(id))
	if a.is_empty() or not _pay(id, Rules.HOTDOG_PRICE):
		_s_error.rpc_id(id, "Can't even afford a hot dog. Rookie numbers.")
		return
	pressure[id] = maxf(pressure_of(id) - Rules.HOTDOG_RELIEF, 0.0)
	_s_toast.rpc_id(id, "Dirty water dog. Blood pressure -%d." % int(Rules.HOTDOG_RELIEF))
	_contract(id, "hotdog")
	_push_state()


func pressure_of(peer: int) -> float:
	return float(pressure.get(peer, 0.0))


## Go take care of it (only in the restroom, see World.near_toilet).
func request_relieve() -> void:
	_req_relieve.rpc_id(1)


@rpc("any_peer", "call_local", "reliable")
func _req_relieve() -> void:
	if not Net.is_server():
		return
	var id := _sender()
	_ensure_peer(id)
	if effect_left(id, "relief") > 0.0 or is_jailed(id) or not world.near_toilet(id):
		return
	effects[id]["relief"] = Rules.RELIEF_SECONDS
	pressure[id] = 0.0
	_s_relieved.rpc(id, Rules.RELIEF_LINES[rng.randi() % Rules.RELIEF_LINES.size()])
	_contract(id, "relieve")
	_push_state()


@rpc("authority", "call_local", "reliable")
func _s_relieved(peer: int, line: String) -> void:
	relieved.emit(peer, line)


func request_use(item: String) -> void:
	_req_use.rpc_id(1, item)


@rpc("any_peer", "call_local", "reliable")
func _req_use(item: String) -> void:
	if not Net.is_server():
		return
	var id := _sender()
	if item_count(id, item) <= 0 or item == "lawyer":
		return
	if is_jailed(id):
		_s_error.rpc_id(id, "Not in here you don't.")
		return
	var def: Dictionary = Rules.ITEMS[item]
	inventory[id][item] -= 1
	_add_heat(id, def.heat)
	match item:
		"cigar", "powder", "moneygun":
			effects[id][item] = Rules.ITEM_DURATION[item]
		"tip":
			var soon := _next_shock(60.0)
			if phase == "trading" and not soon.is_empty():
				_s_tip.rpc_id(id, DayEvents.hint(soon), soon.at - (_day_len - time_left))
			elif phase == "trading" and not _next_event.is_empty():
				_s_tip.rpc_id(id, _next_event.hint, _next_event_in)
			else:
				_s_tip.rpc_id(id, "Market's closed — nothing to tip.", 0.0)
		"snitch":
			var target := _richest_rival(id)
			if target != -1:
				_add_heat(target, 60.0)
				_s_toast.rpc("Someone called the SEC on %s!" % Net.player_name(target))
	_push_state()


func request_slot(bet: float) -> void:
	_req_slot.rpc_id(1, bet)


@rpc("any_peer", "call_local", "reliable")
func _req_slot(bet: float) -> void:
	if not Net.is_server():
		return
	var id := _sender()
	if not bet in Rules.SLOT_BETS:
		return
	var acct := acct_for(id)
	var a: Dictionary = ledger.get_acct(acct)
	if a.is_empty() or a.balance < bet:
		_s_error.rpc_id(id, "Not enough cash for that bet.")
		return
	var reels := [Rules.slot_reel(rng), Rules.slot_reel(rng), Rules.slot_reel(rng)]
	var mult := Rules.slot_multiplier(reels)
	var payout := bet * mult
	ledger.adjust(acct, payout - bet)
	stats[id].pnl_day += payout - bet
	stats[id].pnl_total += payout - bet
	_s_slot_result.rpc(id, reels, payout, bet)
	_contract(id, "slots", {"mult": mult})
	if mult >= 25:
		_s_toast.rpc("%s HIT THE JACKPOT: %s!" % [Net.player_name(id), Rules.money(payout)])
	_push_state()


func send_chat(msg: String) -> void:
	_req_chat.rpc_id(1, msg.substr(0, 140))


@rpc("any_peer", "call_local", "reliable")
func _req_chat(msg: String) -> void:
	if not Net.is_server():
		return
	_s_chat.rpc(Net.player_name(_sender()), msg)


func _sender() -> int:
	var s := multiplayer.get_remote_sender_id()
	return 1 if s == 0 else s


## Circuit breaker: nobody trades (in or out) while the market is halted.
func _halt_msg(id: int) -> bool:
	if not halted():
		return false
	_s_error.rpc_id(id, "CIRCUIT BREAKER: trading halted for %ds. Nobody gets in or out." % ceili(halt))
	return true


# ======================================================================
# server loop
# ======================================================================

func _process(delta: float) -> void:
	if not Net.is_server():
		return
	_acc += delta
	while _acc >= TICK:
		_acc -= TICK
		_server_step(TICK)
	_cop_acc += delta
	if _cop_acc >= COP_SYNC and not raid.is_empty():
		_cop_acc = 0.0
		world.broadcast_cops()


func _server_step(dt: float) -> void:
	var closed_candle := false
	if phase == "lobby" or (phase == "trading" and not halted()):
		closed_candle = market.step(dt)
	_dirty = closed_candle or _dirty
	# timers on players
	for id in effects.keys():
		for e in effects[id].keys():
			effects[id][e] = maxf(effects[id][e] - dt, 0.0)
			if effects[id][e] <= 0.0:
				effects[id].erase(e)
	var cool: float = Rules.HEAT_DECAY * float(ev_mod("heat_decay"))
	for id in heat.keys():
		heat[id] = maxf(heat[id] - cool * perks(id).heat_decay * dt, 0.0)
	if phase == "trading":
		for id in pressure.keys():
			if not is_jailed(id) and effect_left(id, "relief") <= 0.0:
				pressure[id] = minf(pressure[id] + Rules.PRESSURE_RISE * perks(id).bp * dt, Rules.PRESSURE_MAX)
	for id in jail.keys():
		jail[id] -= dt
		if jail[id] <= 0.0:
			jail.erase(id)
			_s_released.rpc(id)
			_dirty = true

	if phase == "morning":
		time_left -= dt
		if time_left <= 0.0:
			var missing: Array = []
			for id in Net.players:
				if not arrived.has(id):
					missing.append(Net.player_name(id))
			_s_toast.rpc("DING DING DING. THE MARKET IS OPEN." + ("" if missing.is_empty() else "  LATE: " + ", ".join(missing)))
			_start_day()
	if phase == "trading":
		time_left -= dt
		_step_shocks(dt)
		if not halted():                     # a halted market: no headlines, no fills, no liquidations
			_step_news(dt)
			for r in ledger.check_triggers(market.price_of):
				_after_close(r, r.acct, r.pos.get("trader_id", 0))
				_dirty = true
			for r in ledger.check_liquidations(market.price_of):
				_after_close(r, r.acct, r.pos.get("trader_id", 0))
				_dirty = true
		_check_milestones()
		_scanner_warnings()
		_step_raid(dt)
		_check_bust()
		if time_left <= 0.0:
			_end_day()

	_s_tick.rpc(market.tick_payload(), time_left, heat, raid, pressure, halt)
	if _dirty:
		_push_state()


func _step_news(dt: float) -> void:
	_next_event_in -= dt
	# early headlines: Nose Candy (6s), the Bloomberg Terminal / Iced Out / WOLF rank perks
	for id in effects.keys():
		if _early_to.has(id) or not Net.players.has(id):
			continue
		var powder := effect_left(id, "powder") > 0.0
		var lead := maxf(6.0 if powder else 0.0, float(perks(id).early_news))
		if lead > 0.0 and _next_event_in <= lead:
			_early_to[id] = true
			var e := _public(_next_event)
			e["lead"] = lead
			e["src"] = "powder" if powder and lead <= 6.0 else "terminal"
			_s_news_early.rpc_id(id, e)
	# Tramp posts before the TV covers it: phone-watchers get a head start
	if not _post_sent and _next_event_in <= 4.0 and _next_event.speaker == "TRAMP":
		_post_sent = true
		_s_post.rpc(_public(_next_event))
	# insiders and the algos read it first: the leak moves the price before it airs
	if not _leaked and _next_event_in <= News.LEAK_S:
		_leaked = true
		newsdeck.leak(market, _next_event)
	if _next_event_in <= 0.0:
		newsdeck.apply(market, _next_event)
		last_news = _public(_next_event)
		_s_news.rpc(last_news)
		if _next_event.has("followup"):
			_followups.append({"in": float(_next_event.followup.at), "ev": _next_event.followup})
		_roll_next_event()
	# the second chyron: a CORRECTION (fake news) or the analysts calling it priced in
	for f in _followups.duplicate():
		f.in -= dt
		if f.in <= 0.0:
			_followups.erase(f)
			last_news = {"speaker": f.ev.speaker, "role": f.ev.role, "headline": f.ev.headline, "day": day, "followup": true}
			_s_news.rpc(last_news)


func _roll_next_event() -> void:
	_next_event = newsdeck.roll()
	_next_event_in = rng.randf_range(22.0, 40.0) * float(ev_mod("news_every"))
	_early_to.clear()
	_post_sent = false
	_leaked = false


func _public(ev: Dictionary) -> Dictionary:
	return {"speaker": ev.speaker, "role": ev.role, "headline": ev.headline, "day": day}


func _after_close(r: Dictionary, acct: int, closer: int) -> void:
	var pos: Dictionary = r.pos
	var trader_id: int = pos.get("trader_id", closer)
	if stats.has(trader_id):
		stats[trader_id].pnl_day += r.pnl
		stats[trader_id].pnl_total += r.pnl
		stats[trader_id].biggest = maxf(stats[trader_id].biggest, r.pnl)
	if r.pct > 100.0 and heat.has(trader_id):
		_add_heat(trader_id, Rules.HEAT_BIG_WIN)
	if stats.has(trader_id):
		_contract(trader_id, "close", {"pnl": r.pnl, "pct": r.pct, "side": pos.side, "sym": pos.sym, "lev": pos.lev,
			"pnl_day": stats[trader_id].pnl_day})
	_s_trade_closed.rpc({"acct": acct, "trader": pos.trader, "trader_id": trader_id, "sym": pos.sym, "side": pos.side,
		"pnl": r.pnl, "pct": r.pct, "liquidated": r.liquidated, "lev": pos.lev, "trigger": r.get("trigger", "")})


func _add_heat(id: int, amount: float) -> void:
	if not heat.has(id):
		return
	if amount > 0.0:
		amount *= float(ev_mod("heat_gain"))        # SEC audit
	heat[id] = minf(heat[id] + amount, Rules.HEAT_MAX)
	if heat[id] >= raid_threshold() and raid.is_empty() and not is_jailed(id) and phase == "trading":
		_start_raid(id)


func _richest_rival(me: int) -> int:
	var best := -1
	var best_v := -1.0
	for id in Net.players:
		if id == me or is_jailed(id):
			continue
		var v: float = ledger.equity(acct_for(id), market.price_of)
		if v > best_v:
			best_v = v
			best = id
	return best


# ---------------- police ----------------

func _start_raid(target: int) -> void:
	raid = {"target": target, "t": Rules.RAID_CHASE_SECONDS}
	world.spawn_cops(target)
	_s_raid.rpc(target, true)
	_s_toast.rpc("COPS ARE HERE FOR %s. RUN!" % Net.player_name(target).to_upper())


func _step_raid(dt: float) -> void:
	if raid.is_empty():
		return
	raid.t -= dt
	if not Net.players.has(raid.target):
		_end_raid(false)
	elif raid.t <= 0.0:
		heat[raid.target] = 60.0
		_s_toast.rpc("%s lost the cops. For now." % Net.player_name(raid.target))
		_end_raid(false)


func _end_raid(_caught: bool) -> void:
	var target: int = raid.get("target", 0)
	raid = {}
	world.despawn_cops()
	_s_raid.rpc(target, false)


## Called by a cop (server side) when it touches the target.
func server_cop_caught(target: int) -> void:
	if raid.is_empty() or raid.target != target:
		return
	if item_count(target, "lawyer") > 0:
		inventory[target]["lawyer"] -= 1
		heat[target] = 30.0
		_s_toast.rpc("SAUL GOODMANN: \"%s is innocent.\" CASE DISMISSED." % Net.player_name(target))
		_end_raid(true)
		_push_state()
		return
	_booking_no += 1 + rng.randi() % 37
	jail[target] = Rules.JAIL_SECONDS
	heat[target] = 0.0
	stats[target].arrests += 1
	var acct := acct_for(target)
	var fine: float = ledger.get_acct(acct).get("balance", 0.0) * Rules.ARREST_FINE
	ledger.adjust(acct, -fine)
	var seized: float = floor(cash_of(target) * Rules.CASH_SEIZED)
	if seized > 0.0:
		wallet[target] = cash_of(target) - seized
		spreads.erase(target)
		_s_toast.rpc("The cops bagged %s of %s's cash as evidence." % [Rules.money(seized), Net.player_name(target)])
	var gun := gun_of(target)
	if gun != "":                    # caught with it out: it's evidence now
		drawn.erase(target)
		owned[target][gun] = maxi(lux_count(target, gun) - 1, 0)
		_save_careers()
		_s_toast.rpc("The cops confiscated %s's %s." % [Net.player_name(target), Rules.LUXURY[gun].name])
	_s_arrested.rpc(target, _booking_no)
	_s_toast.rpc("%s GOT ARRESTED. Fined %s." % [Net.player_name(target), Rules.money(fine)])
	_end_raid(true)
	_push_state()


## Highway patrol caught up with `target` and boxed them in: pulled over.
## A speeding ticket off the account, a night in the cells (same jail).
func server_pull_over(target: int) -> void:
	if not Net.is_server() or is_jailed(target):
		return
	_booking_no += 1 + rng.randi() % 37
	jail[target] = Rules.JAIL_SECONDS
	heat[target] = 0.0
	if stats.has(target):
		stats[target].arrests += 1
	var acct := acct_for(target)
	var fine: float = maxf(ledger.get_acct(acct).get("balance", 0.0) * Rules.ARREST_FINE * 0.5, 0.0) + Rules.SPEEDING_TICKET
	ledger.adjust(acct, -fine)
	_s_arrested.rpc(target, _booking_no)
	_s_toast.rpc("HIGHWAY PATROL PULLED OVER %s. Ticket + impound fees: %s." % [Net.player_name(target), Rules.money(fine)])
	_push_state()


@rpc("authority", "call_local", "reliable")
func s_pursuit(target: int, stage: String) -> void:
	pursuit_changed.emit(target, stage)


# ---------------- run / day flow ----------------

func _ensure_peer(id: int) -> void:
	if not heat.has(id):
		heat[id] = 0.0
	if not inventory.has(id):
		inventory[id] = {}
	if not owned.has(id):
		owned[id] = {}
	if not pressure.has(id):
		pressure[id] = 0.0
	if not careers.has(id):
		_load_career(id)
	if not effects.has(id):
		effects[id] = {}
	if not stats.has(id):
		stats[id] = {"pnl_day": 0.0, "pnl_total": 0.0, "trades": 0, "arrests": 0, "biggest": 0.0}
	if Net.mode == "pvp" and not ledger.has(id):
		ledger.create_account(id, Net.player_name(id), Rules.START_FUND)
	if not _resume.is_empty() and not _restored.has(id):
		_restore_peer(id)
	if phase == "trading" and not contracts.has(id) and Net.players.has(id):
		_deal_contracts(id)


func _on_players_changed() -> void:
	if not Net.is_server():
		return
	for id in Net.players:
		_ensure_peer(id)
	for id in heat.keys():
		if not Net.players.has(id):
			heat.erase(id)
			effects.erase(id)
			jail.erase(id)
	for id in ready_up.keys():
		if not Net.players.has(id):
			ready_up.erase(id)
	_check_ready()                        # whoever left was the last one not ready
	_push_state()


func _reset_run() -> void:
	phase = "lobby"
	day = 0
	time_left = 0.0
	ledger = Ledger.new()
	heat.clear()
	inventory.clear()
	pressure.clear()
	effects.clear()
	stats.clear()
	jail.clear()
	contracts.clear()
	milestones = 0
	ready_up.clear()
	wallet.clear()
	spreads.clear()
	drawn.clear()
	_set_day_event("")
	next_event = ""
	if not raid.is_empty():
		_end_raid(false)
	if Net.mode == "coop":
		ledger.create_account(0, "BAGHOLDER CAPITAL", Rules.START_FUND)
	for id in Net.players:
		_ensure_peer(id)
	quota = Rules.quota_for_day(1)


func _start_run() -> void:
	if _resume.is_empty():
		_reset_run()
		day = 0
		next_event = _roll_day_event(1)
		_s_toast.rpc("Day 1. Rise and grind." if commute_seconds() > 0.0 else "DING DING DING. THE MARKET IS OPEN.")
	else:   # a loaded run picks up the morning after its last closing bell
		_s_toast.rpc("Day %d — the fund is back in business." % (day + 1))
	_to_morning()


# ---------------- save games ----------------

## Server start: continue the save the menu picked, or give this run a new slot
## (written at the first closing bell). Tests don't touch real saves.
func _open_save() -> void:
	save_slot = ""
	if (Config.cli.has("smoke") or Config.cli.has("eventcheck") or Config.cli.has("hoodcheck") or Config.cli.has("hoodshots")) \
			and not Config.cli.has("savecheck"):   # ---- neighborhood (houses): tests don't save ----
		return
	if Config.load_slot != "":
		var s := SaveGame.read(Config.load_slot)
		Config.load_slot = ""
		if not s.is_empty() and not s.get("over", false) and SaveGame.owned_by(s, Net.player_name(1)):
			save_slot = str(s.slot)
			_apply_save(s)
			return
	save_slot = SaveGame.new_slot(Net.mode)


func _apply_save(s: Dictionary) -> void:
	_resume = s
	_restored.clear()
	day = int(s.get("day", 0))
	quota = Rules.quota_for_day(day + 1)
	next_event = str(s.get("next_event", ""))
	milestones = int(s.get("milestones", 0))
	if Net.mode == "coop":
		ledger.get_acct(0).balance = float(s.get("fund", Rules.START_FUND))
	for id in Net.players:
		_restore_peer(id)
	_push_state()


## Hand a (re)joining player their things from the save, matched by name.
func _restore_peer(id: int) -> void:
	_restored[id] = true
	var p: Dictionary = _resume.get("players", {}).get(Net.player_name(id).to_lower(), {})
	if p.is_empty():
		return
	inventory[id] = (p.get("inventory", {}) as Dictionary).duplicate()
	wallet[id] = float(p.get("cash", 0.0))
	for item in inventory[id]:
		inventory[id][item] = int(inventory[id][item])
	var st: Dictionary = p.get("stats", {})
	stats[id] = {"pnl_day": 0.0, "pnl_total": float(st.get("pnl_total", 0.0)), "trades": int(st.get("trades", 0)),
		"arrests": int(st.get("arrests", 0)), "biggest": float(st.get("biggest", 0.0))}
	if Net.mode == "pvp":
		if not ledger.has(id):
			ledger.create_account(id, Net.player_name(id), Rules.START_FUND)
		var a: Dictionary = ledger.get_acct(id)
		a.balance = float(p.get("balance", Rules.START_FUND))
		a.busted = bool(p.get("busted", false))


## Everything a run needs to continue, keyed by player name. Players from the
## save who aren't here tonight are carried over untouched.
func snapshot(over: bool) -> Dictionary:
	var players: Dictionary = (_resume.get("players", {}) as Dictionary).duplicate(true)
	var names: Array = []
	var best := 0.0
	for id in Net.players:
		var nm := Net.player_name(id)
		names.append(nm)
		var st: Dictionary = stats.get(id, {})
		var p := {"name": nm, "inventory": inventory.get(id, {}).duplicate(), "cash": cash_of(id),
			"stats": {"pnl_total": st.get("pnl_total", 0.0), "trades": st.get("trades", 0),
				"arrests": st.get("arrests", 0), "biggest": st.get("biggest", 0.0)}}
		if Net.mode == "pvp" and ledger.has(id):
			var a: Dictionary = ledger.get_acct(id)
			p["balance"] = a.balance
			p["busted"] = a.busted
			best = maxf(best, a.balance)
		players[nm.to_lower()] = p
	var fund: float = ledger.get_acct(0).balance if Net.mode == "coop" else best
	return {"mode": Net.mode, "day": day, "fund": fund, "balance": fund, "over": over,
		"names": names, "players": players, "owner": Net.player_name(1), "next_event": next_event,
		"milestones": milestones}


## The SAVE GAME button (host only). Between days it saves right now; during
## a trading day it saves the run as it stood at this morning's bell, since
## a half-played day (open trades, the clock) can't be resumed.
func request_save() -> void:
	_req_save.rpc_id(1)


@rpc("any_peer", "call_local", "reliable")
func _req_save() -> void:
	if not Net.is_server():
		return
	var id := _sender()
	if id != 1:
		_s_error.rpc_id(id, "Only the host keeps the save.")
		return
	var info := {}
	if save_slot == "":
		info = {"error": "Saving is off for this session."}
	elif phase == "gameover":
		info = {"error": "This run is over. Start a new one to save."}
	else:
		var mid_day := phase == "trading" and not _morning.is_empty()
		var data: Dictionary = _morning.duplicate(true) if mid_day else snapshot(false)
		if SaveGame.write(save_slot, data):
			info = {"slot": save_slot, "cloud": SaveGame.in_cloud(), "mid_day": mid_day, "next_day": int(data.day) + 1}
		else:
			info = {"error": "Couldn't write the save file."}
	_s_saved.rpc_id(id, info)


@rpc("authority", "call_local", "reliable")
func _s_saved(info: Dictionary) -> void:
	saved.emit(info)


func _autosave(over: bool) -> Dictionary:
	if save_slot == "":
		return {}
	if not SaveGame.write(save_slot, snapshot(over)):
		return {"error": true}
	return {"slot": save_slot, "cloud": SaveGame.in_cloud()}


# ---------------- day events (DayEvents) ----------------

## Tomorrow's event. Tests pin it with --day_event=<id|none> (smoke runs
## default to none so they stay predictable).
func _roll_day_event(for_day: int) -> String:
	return DayEvents.roll(rng, for_day, day_event)


func _forced_event(rolled: String) -> String:
	var f := str(Config.cli.get("day_event", "none" if Config.cli.has("smoke") or Config.cli.has("savecheck") else ""))
	if f == "":
		return rolled
	return "" if f == "none" or not DayEvents.EVENTS.has(f) else f


## Switch today's event on: market drift / volatility, who's on the news.
func _set_day_event(id: String) -> void:
	day_event = id
	if market == null:
		return
	market.vol_mult = (ev_mod("vol", {}) as Dictionary).duplicate()
	market.bias = float(ev_mod("bias", 0.0))
	newsdeck.boost = (ev_mod("news", {}) as Dictionary).duplicate()
	newsdeck.tramp_boost = float(ev_mod("tramp"))


func _update_event_at() -> void:
	event_at = -1.0
	for s in _sched:
		if not s.fired and DayEvents.public_at(s):
			event_at = _day_len - s.at
			return


## The next unfired shock within `within` seconds (for the Insider Tip).
func _next_shock(within: float) -> Dictionary:
	var now := _day_len - time_left
	for s in _sched:
		if not s.fired and s.at - now <= within:
			return s
	return {}


## Timed shocks: the warning, the hit, and for a crash the circuit breaker.
func _step_shocks(dt: float) -> void:
	if halted():
		halt = maxf(halt - dt, 0.0)
		if not halted():
			_fire(DayEvents.shock_news(_halt_shock, "reopen"))
			_s_shock.rpc(_halt_shock.kind, "reopen")
			_s_toast.rpc("CIRCUIT BREAKER LIFTED. TRADING RESUMES.")
			_dirty = true
	var now := _day_len - time_left
	for s in _sched:
		var lead: float = DayEvents.CRASH_WARN if s.kind == "crash" else DayEvents.WARN_SECONDS
		if not s.warned and now >= s.at - lead:
			s.warned = true
			_fire(DayEvents.shock_news(s, "warn"))
			_s_shock.rpc(s.kind, "warn")
		if not s.fired and now >= s.at:
			s.fired = true
			s["halt_at"] = now + DayEvents.HALT_AFTER
			_fire(DayEvents.shock_news(s, "hit"))
			_s_shock.rpc(s.kind, "hit")
			_update_event_at()
			_dirty = true
		if s.kind == "crash" and s.fired and not s.get("halted", false) and now >= s.halt_at:
			s["halted"] = true
			_halt_shock = s
			halt = DayEvents.HALT_SECONDS
			_s_shock.rpc(s.kind, "halt")
			_s_toast.rpc("CIRCUIT BREAKER TRIPPED. TRADING HALTED %ds." % int(DayEvents.HALT_SECONDS))
			_dirty = true


## Put a headline on the air (and move the market if it has effects).
func _fire(ev: Dictionary) -> void:
	newsdeck.apply(market, ev)
	last_news = _public(ev)
	_s_news.rpc(last_news)


# ---------------- Tony's contracts ----------------

func _deal_contracts(id: int) -> void:
	var extra: int = perks(id).contracts
	contracts[id] = Contracts.deal(rng, maxi(day, 1), Rules.START_FUND, day_event, extra)


## Something happened to `id`: move their contracts along.
func _contract(id: int, kind: String, data: Dictionary = {}) -> void:
	if phase != "trading" or not contracts.has(id):
		return
	for c in contracts[id]:
		if Contracts.note(c, kind, data):
			_pay_contract(id, c)
	_dirty = true


func _pay_contract(id: int, c: Dictionary) -> void:
	var pk := perks(id)
	var cash: float = c.cash * pk.contract_pay
	ledger.adjust(acct_for(id), cash)
	_bonus_xp(id, c.xp * pk.xp)
	_s_contract_done.rpc(id, c, cash)
	_dirty = true


## XP outside the closing bell (contracts, milestones).
func _bonus_xp(id: int, gain: float) -> void:
	_ensure_peer(id)
	var c: Dictionary = careers[id]
	var before := Rules.rank_of(c.xp)
	c.xp += gain
	var after := Rules.rank_of(c.xp)
	if after > before:
		_s_rank_up.rpc(id, after)


## Co-op: the fund crossing $100K, $250K, $1M... pays everyone XP once a run.
func _check_milestones() -> void:
	if Net.mode != "coop" or milestones >= Rules.MILESTONES.size():
		return
	var amount: float = Rules.MILESTONES[milestones]
	if ledger.equity(0, market.price_of) < amount:
		return
	var xp: float = Rules.MILESTONE_XP[milestones]
	milestones += 1
	for id in Net.players:
		_bonus_xp(id, xp * perks(id).xp)
	_s_milestone.rpc(amount, xp)
	_dirty = true


## Police Scanner upgrade: a heads-up before the cops come.
func _scanner_warnings() -> void:
	var th := raid_threshold()
	for id in heat:
		if perks(id).raid_warn <= 0:
			continue
		var h: float = heat[id]
		if h >= th * 0.75 and not _raid_warned.has(id):
			_raid_warned[id] = true
			_s_toast.rpc_id(id, "SCANNER: \"All units, eyes on %s. Heat %d.\" Cool it." % [Net.player_name(id).to_upper(), int(h)])
		elif h < th * 0.5:
			_raid_warned.erase(id)


func _start_day() -> void:
	_morning = snapshot(false)          # a mid-day SAVE GAME keeps this
	day += 1
	phase = "trading"
	time_left = Rules.DAY_SECONDS
	if Config.cli.has("day_seconds"):
		time_left = float(Config.cli.day_seconds)
	quota = Rules.quota_for_day(day)
	market.mark_day_open()
	for id in ledger.accounts:
		ledger.accounts[id].day_start = ledger.accounts[id].balance
	for id in stats:
		stats[id].pnl_day = 0.0
	_day_len = time_left
	halt = 0.0
	_set_day_event(_forced_event(next_event))
	_sched = DayEvents.schedule(day_event, rng, _day_len)
	_update_event_at()
	contracts.clear()
	for id in Net.players:
		_deal_contracts(id)
	_followups.clear()
	_roll_next_event()
	_next_event_in = 10.0
	_s_market_full.rpc(market.full_payload())
	if day_event != "":
		_fire(DayEvents.morning_news(day_event, _day_len))
	_push_state()


func _check_bust() -> void:
	if Net.mode != "coop":
		return
	var a: Dictionary = ledger.get_acct(0)
	if a.positions.is_empty() and a.balance < 1.0:
		time_left = 0.0


func _end_day() -> void:
	if not raid.is_empty():
		_end_raid(false)
	for id in ledger.accounts.keys():
		for r in ledger.close_all(id, market.price_of):
			if r.ok:
				_after_close(r, id, r.pos.get("trader_id", 0))
	# the bills come due before anyone checks the quota
	# Tony's end-of-day contracts (clean hands, stayed off the slots) settle first
	for id in contracts:
		for c in contracts[id]:
			if Contracts.settle(c, {"heat": heat.get(id, 0.0)}):
				_pay_contract(id, c)
	var overhead := 0.0
	var ov_day: float = float(ev_mod("overhead"))            # bonus day: the firm pays
	if Net.mode == "coop":
		for id in Net.players:
			overhead += Rules.overhead_for_day(day, 1) * perks(id).overhead * ov_day
		ledger.adjust(0, -overhead)
	else:
		for id in ledger.accounts:
			var own_bill: float = Rules.overhead_for_day(day, 1) * perks(id).overhead * ov_day
			overhead = maxf(overhead, own_bill)
			ledger.adjust(id, -own_bill)
	var summary := {"day": day, "quota": quota, "mode": Net.mode, "players": {}, "overhead": overhead,
		"event": day_event, "contracts": contracts.duplicate(true)}
	for id in Net.players:
		summary.players[id] = {"name": Net.player_name(id), "stats": stats.get(id, {}).duplicate()}
	var over := false
	var desk_passed := false
	if Net.mode == "coop":
		var bal: float = ledger.get_acct(0).balance + total_cash()   # the desk's cash on hand counts
		summary["balance"] = bal
		summary["passed"] = bal >= quota
		desk_passed = bal >= quota
		over = bal < quota
	else:
		var ranking: Array = []
		var alive := 0
		for id in ledger.accounts:
			var a: Dictionary = ledger.accounts[id]
			if not a.busted and a.balance + cash_of(id) < quota:
				a.busted = true
			if not a.busted:
				alive += 1
			ranking.append({"id": id, "name": a.name, "balance": a.balance + cash_of(id), "busted": a.busted})
		ranking.sort_custom(func(x, y): return x.balance > y.balance)
		summary["ranking"] = ranking
		var needed_alive := 1 if ledger.accounts.size() > 1 else 0
		over = day >= Rules.PVP_DAYS or alive <= needed_alive
		if over and not ranking.is_empty():
			summary["winner"] = ranking[0].name
			if ranking.size() > 1 and owned.has(ranking[0].id):   # the champion's trophy stays on their desk for good
				var champ: int = ranking[0].id
				owned[champ]["champ"] = lux_count(champ, "champ") + 1
				summary["champ"] = lux_count(champ, "champ")
	# career XP: green days + making quota
	summary["xp"] = {}
	for id in Net.players:
		var st: Dictionary = stats.get(id, {})
		var made: bool = desk_passed if Net.mode == "coop" else not ledger.get_acct(id).get("busted", true)
		var gain: float = maxf(st.get("pnl_day", 0.0), 0.0) / 1000.0 * Rules.XP_PER_1K + (Rules.XP_QUOTA_DAY if made else 0.0)
		summary.xp[id] = _add_xp(id, gain * perks(id).xp, st.get("pnl_day", 0.0))
	_save_careers()
	if not over:                                   # tomorrow's forecast (the save keeps it)
		next_event = _roll_day_event(day + 1)
		summary["tomorrow"] = next_event
	summary["saved"] = _autosave(over)          # the closing bell saves the run (a busted run is marked over)
	if over:
		phase = "gameover"
		summary["over"] = true
		_s_game_over.rpc(summary)
	else:
		phase = "intermission"               # waits for the host to start the next day
		time_left = 0.0
		summary["over"] = false
		summary["next_quota"] = Rules.quota_for_day(day + 1)
		_s_day_ended.rpc(summary)
	_push_state()


func _push_state() -> void:
	_dirty = false
	accounts = ledger.payload()
	_s_state.rpc({"phase": phase, "day": day, "time_left": time_left, "quota": quota,
		"accounts": accounts, "heat": heat, "jail": jail, "inventory": inventory, "owned": owned, "careers": careers,
		"effects": effects, "stats": stats, "raid": raid, "day_event": day_event, "next_event": next_event,
		"event_at": event_at, "halt": halt, "contracts": contracts, "milestones": milestones, "ready": ready_up,
		"wallet": wallet, "spreads": spreads, "drawn": drawn, "late": late, "arrived": arrived})


# ======================================================================
# server -> clients
# ======================================================================

@rpc("authority", "call_local", "reliable")
func _s_state(s: Dictionary) -> void:
	phase = s.phase
	day = s.day
	time_left = s.time_left
	quota = s.quota
	accounts = s.accounts
	heat = s.heat
	jail = s.jail
	inventory = s.inventory
	owned = s.get("owned", {})
	careers = s.get("careers", {})
	effects = s.effects
	stats = s.stats
	raid = s.raid
	day_event = s.get("day_event", "")
	next_event = s.get("next_event", "")
	event_at = s.get("event_at", -1.0)
	halt = s.get("halt", 0.0)
	contracts = s.get("contracts", {})
	milestones = s.get("milestones", 0)
	ready_up = s.get("ready", {})
	wallet = s.get("wallet", {})
	spreads = s.get("spreads", {})
	drawn = s.get("drawn", {})
	late = s.get("late", {})
	arrived = s.get("arrived", {})
	state_changed.emit()


@rpc("authority", "call_local", "reliable")
func _s_market_full(p: Dictionary) -> void:
	_mirror_market_full(p)


func _mirror_market_full(p: Dictionary) -> void:
	m_assets = []
	for a in p.assets:
		m_assets.append({"sym": a.sym, "name": a.name, "kind": a.kind,
			"candles": a.candles.duplicate(true), "cur": a.cur.duplicate(),
			"price": a.price, "open_day": a.open_day})
	m_ci = p.ci
	market_full.emit()


@rpc("authority", "call_local", "unreliable_ordered")
func _s_tick(p: Dictionary, t_left: float, h: Dictionary, r: Dictionary, bp: Dictionary = {}, hl: float = 0.0) -> void:
	pressure = bp
	halt = hl
	if m_assets.size() != p.p.size():
		return
	var new_candle: bool = p.ci != m_ci
	for i in m_assets.size():
		var a: Dictionary = m_assets[i]
		if new_candle:
			a.candles.append(p.l[i])
			if a.candles.size() > Market.MAX_CANDLES:
				a.candles.pop_front()
		a.price = p.p[i]
		a.cur = p.c[i]
		a.open_day = p.o[i]
	m_ci = p.ci
	fast_mkt = p.get("fm", {})
	time_left = t_left
	heat = h
	raid = r
	market_tick.emit()


@rpc("authority", "call_local", "reliable")
func _s_news(ev: Dictionary) -> void:
	last_news = ev
	news_log.append(ev)
	if news_log.size() > 30:
		news_log.pop_front()
	news.emit(ev)


@rpc("authority", "call_local", "reliable")
func _s_news_early(ev: Dictionary) -> void:
	news_early.emit(ev)


@rpc("authority", "call_local", "reliable")
func _s_tip(hint: String, eta: float) -> void:
	tip.emit(hint, eta)


@rpc("authority", "call_local", "reliable")
func _s_trade_opened(info: Dictionary) -> void:
	trade_opened.emit(info)


@rpc("authority", "call_local", "reliable")
func _s_trade_closed(info: Dictionary) -> void:
	trade_closed.emit(info)


@rpc("authority", "call_local", "reliable")
func _s_slot_result(peer: int, reels: Array, payout: float, bet: float) -> void:
	slot_result.emit(peer, reels, payout, bet)


@rpc("authority", "call_local", "reliable")
func _s_arrested(peer: int, booking_no: int) -> void:
	world.on_arrested(peer)
	arrested.emit(peer, booking_no)


@rpc("authority", "call_local", "reliable")
func _s_released(peer: int) -> void:
	world.on_released(peer)
	released.emit(peer)


@rpc("authority", "call_local", "reliable")
func _s_raid(target: int, active: bool) -> void:
	if not active and not Net.is_server():
		world.despawn_cops()
	raid_changed.emit(target, active)


@rpc("authority", "call_local", "reliable")
func _s_day_ended(summary: Dictionary) -> void:
	day_ended.emit(summary)


@rpc("authority", "call_local", "reliable")
func _s_game_over(summary: Dictionary) -> void:
	game_over.emit(summary)


@rpc("authority", "call_local", "reliable")
func _s_post(ev: Dictionary) -> void:
	posted.emit(ev)


@rpc("authority", "call_local", "reliable")
func _s_luxury(peer: int, key: String) -> void:
	luxury_bought.emit(peer, key)


@rpc("authority", "call_local", "reliable")
func _s_pawned(peer: int, key: String) -> void:
	pawned.emit(peer, key)


@rpc("authority", "call_local", "reliable")
func _s_contract_done(peer: int, c: Dictionary, cash: float) -> void:
	contract_done.emit(peer, c, cash)


@rpc("authority", "call_local", "reliable")
func _s_shock(kind: String, stage: String) -> void:
	shock.emit(kind, stage)


@rpc("authority", "call_local", "reliable")
func _s_milestone(amount: float, xp: float) -> void:
	milestone.emit(amount, xp)


@rpc("authority", "call_local", "reliable")
func _s_toast(msg: String) -> void:
	toast.emit(msg)


@rpc("authority", "call_local", "reliable")
func _s_error(msg: String) -> void:
	error_msg.emit(msg)


@rpc("authority", "call_local", "reliable")
func _s_chat(from_name: String, msg: String) -> void:
	chat.emit(from_name, msg)
