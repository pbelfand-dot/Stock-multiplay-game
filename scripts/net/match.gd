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
signal relieved(peer: int, line: String)
signal ranked_up(peer: int, rank: int)
signal posted(ev: Dictionary)
signal chat(from_name: String, msg: String)
signal error_msg(msg: String)

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
var m_ci := 0

# ---------------- server-only ----------------
var market
var newsdeck
var ledger
var rng := RandomNumberGenerator.new()
var _acc := 0.0
var _cop_acc := 0.0
var _next_event: Dictionary = {}
var _next_event_in := 0.0
var _early_sent := false
var _post_sent := false
var _booking_no := 4298
var _dirty := false

@onready var world = get_parent()


func _ready() -> void:
	if Net.is_server():
		rng.randomize()
		market = Market.new()
		newsdeck = News.new(rng)
		ledger = Ledger.new()
		# Pre-warm some history so the charts aren't empty.
		for i in 1200:
			market.step(TICK)
		market.mark_day_open()
		_reset_run()
		_mirror_market_full(market.full_payload())
	else:
		_req_sync.rpc_id(1)
	Net.players_changed.connect(_on_players_changed)


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


@rpc("any_peer", "call_local", "reliable")
func _req_start() -> void:
	if not Net.is_server():
		return
	if _sender() != 1:
		return  # only the host rings the bell
	if phase == "lobby":
		_start_run()
	elif phase == "gameover":
		_reset_run()
		_push_state()


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
	if pressure_of(id) >= Rules.PRESSURE_FAT_FINGER and rng.randf() < 0.6:
		margin *= 2.0 if rng.randf() < 0.5 else 0.5   # shaking hands: fat-finger the size
		_s_error.rpc_id(id, "FAT FINGER! Your hands are shaking. Go relieve the pressure.")
	if lev > 100 and not has_rank_for(id, "lev_125"):
		_s_error.rpc_id(id, "x125 unlocks at DEGEN. Rookie numbers.")
		return
	var fee_rate := 0.0 if effect_left(id, "cigar") > 0.0 else Ledger.FEE_RATE
	var r: Dictionary = ledger.open_position(acct_for(id), sym, side, margin, lev,
		market.price_of(sym), Net.player_name(id), fee_rate, market.spread_of(sym))
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
	if is_jailed(id):
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
	if a.is_empty() or a.balance < def.price:
		_s_error.rpc_id(id, "Can't afford %s." % def.name)
		return
	ledger.adjust(acct, -def.price)
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
	if a.is_empty() or a.balance < def.price:
		_s_error.rpc_id(id, "Can't afford %s." % def.name)
		return
	ledger.adjust(acct, -def.price)
	owned[id][key] = lux_count(id, key) + 1
	_save_careers()
	_add_heat(id, def.get("heat", 0.0))
	_s_toast.rpc("%s copped a %s (%s)" % [Net.player_name(id), def.name, Rules.money(def.price)])
	_s_luxury.rpc(id, key)
	_push_state()


# ---------------- careers (host saves them, keyed by player name) ----------------

func xp_of(peer: int) -> float:
	return float(careers.get(peer, {}).get("xp", 0.0))


func rank_idx(peer: int) -> int:
	return Rules.rank_of(xp_of(peer))


func has_rank_for(peer: int, gate: String) -> bool:
	return rank_idx(peer) >= int(Rules.RANK_GATES.get(gate, 0))


## Tests run with --smoke and must not read or write a real career file.
func _careers_on_disk() -> bool:
	return Net.is_server() and not Config.cli.has("smoke")


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
	var cash: float = Rules.LUXURY[key].price * Rules.PAWN_RATE
	ledger.adjust(acct_for(id), cash)
	_s_toast.rpc("%s pawned a %s for %s" % [Net.player_name(id), Rules.LUXURY[key].name, Rules.money(cash)])
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
	if a.is_empty() or a.balance < Rules.HOTDOG_PRICE:
		_s_error.rpc_id(id, "Can't even afford a hot dog. Rookie numbers.")
		return
	ledger.adjust(acct_for(id), -Rules.HOTDOG_PRICE)
	pressure[id] = maxf(pressure_of(id) - Rules.HOTDOG_RELIEF, 0.0)
	_s_toast.rpc_id(id, "Dirty water dog. Blood pressure -%d." % int(Rules.HOTDOG_RELIEF))
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
			if phase == "trading" and not _next_event.is_empty():
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
	if phase == "lobby" or phase == "trading":
		closed_candle = market.step(dt)
	_dirty = closed_candle or _dirty
	# timers on players
	for id in effects.keys():
		for e in effects[id].keys():
			effects[id][e] = maxf(effects[id][e] - dt, 0.0)
			if effects[id][e] <= 0.0:
				effects[id].erase(e)
	for id in heat.keys():
		heat[id] = maxf(heat[id] - Rules.HEAT_DECAY * dt, 0.0)
	if phase == "trading":
		for id in pressure.keys():
			if not is_jailed(id) and effect_left(id, "relief") <= 0.0:
				pressure[id] = minf(pressure[id] + Rules.PRESSURE_RISE * dt, Rules.PRESSURE_MAX)
	for id in jail.keys():
		jail[id] -= dt
		if jail[id] <= 0.0:
			jail.erase(id)
			_s_released.rpc(id)
			_dirty = true

	if phase == "trading":
		time_left -= dt
		_step_news(dt)
		for r in ledger.check_triggers(market.price_of):
			_after_close(r, r.acct, r.pos.get("trader_id", 0))
			_dirty = true
		for r in ledger.check_liquidations(market.price_of):
			_after_close(r, r.acct, r.pos.get("trader_id", 0))
			_dirty = true
		_step_raid(dt)
		_check_bust()
		if time_left <= 0.0:
			_end_day()
	elif phase == "intermission":
		time_left -= dt
		if time_left <= 0.0:
			_start_day()

	_s_tick.rpc(market.tick_payload(), time_left, heat, raid, pressure)
	if _dirty:
		_push_state()


func _step_news(dt: float) -> void:
	_next_event_in -= dt
	if not _early_sent and _next_event_in <= 6.0:
		_early_sent = true
		for id in effects.keys():
			if effect_left(id, "powder") > 0.0:
				_s_news_early.rpc_id(id, _public(_next_event))
	# Tramp posts before the TV covers it: phone-watchers get a head start
	if not _post_sent and _next_event_in <= 4.0 and _next_event.speaker == "TRAMP":
		_post_sent = true
		_s_post.rpc(_public(_next_event))
	if _next_event_in <= 0.0:
		newsdeck.apply(market, _next_event)
		last_news = _public(_next_event)
		_s_news.rpc(last_news)
		_roll_next_event()


func _roll_next_event() -> void:
	_next_event = newsdeck.roll()
	_next_event_in = rng.randf_range(22.0, 40.0)
	_early_sent = false
	_post_sent = false


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
	_s_trade_closed.rpc({"acct": acct, "trader": pos.trader, "sym": pos.sym, "side": pos.side,
		"pnl": r.pnl, "pct": r.pct, "liquidated": r.liquidated, "lev": pos.lev, "trigger": r.get("trigger", "")})


func _add_heat(id: int, amount: float) -> void:
	if not heat.has(id):
		return
	heat[id] = minf(heat[id] + amount, Rules.HEAT_MAX)
	if heat[id] >= Rules.HEAT_MAX and raid.is_empty() and not is_jailed(id) and phase == "trading":
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
	_s_arrested.rpc(target, _booking_no)
	_s_toast.rpc("%s GOT ARRESTED. Fined %s." % [Net.player_name(target), Rules.money(fine)])
	_end_raid(true)
	_push_state()


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
	if not raid.is_empty():
		_end_raid(false)
	if Net.mode == "coop":
		ledger.create_account(0, "BAGHOLDER CAPITAL", Rules.START_FUND)
	for id in Net.players:
		_ensure_peer(id)
	quota = Rules.quota_for_day(1)


func _start_run() -> void:
	_reset_run()
	day = 0
	_s_toast.rpc("DING DING DING. THE MARKET IS OPEN.")
	_start_day()


func _start_day() -> void:
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
	_roll_next_event()
	_next_event_in = 10.0
	_s_market_full.rpc(market.full_payload())
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
	var summary := {"day": day, "quota": quota, "mode": Net.mode, "players": {}}
	for id in Net.players:
		summary.players[id] = {"name": Net.player_name(id), "stats": stats.get(id, {}).duplicate()}
	var over := false
	var desk_passed := false
	if Net.mode == "coop":
		var bal: float = ledger.get_acct(0).balance
		summary["balance"] = bal
		summary["passed"] = bal >= quota
		desk_passed = bal >= quota
		over = bal < quota
	else:
		var ranking: Array = []
		var alive := 0
		for id in ledger.accounts:
			var a: Dictionary = ledger.accounts[id]
			if not a.busted and a.balance < quota:
				a.busted = true
			if not a.busted:
				alive += 1
			ranking.append({"id": id, "name": a.name, "balance": a.balance, "busted": a.busted})
		ranking.sort_custom(func(x, y): return x.balance > y.balance)
		summary["ranking"] = ranking
		var needed_alive := 1 if ledger.accounts.size() > 1 else 0
		over = day >= Rules.PVP_DAYS or alive <= needed_alive
		if over and not ranking.is_empty():
			summary["winner"] = ranking[0].name
	# career XP: green days + making quota
	summary["xp"] = {}
	for id in Net.players:
		var st: Dictionary = stats.get(id, {})
		var made: bool = desk_passed if Net.mode == "coop" else not ledger.get_acct(id).get("busted", true)
		var gain: float = maxf(st.get("pnl_day", 0.0), 0.0) / 1000.0 * Rules.XP_PER_1K + (Rules.XP_QUOTA_DAY if made else 0.0)
		summary.xp[id] = _add_xp(id, gain, st.get("pnl_day", 0.0))
	_save_careers()
	if over:
		phase = "gameover"
		summary["over"] = true
		_s_game_over.rpc(summary)
	else:
		phase = "intermission"
		time_left = Rules.INTERMISSION_SECONDS
		summary["over"] = false
		summary["next_quota"] = Rules.quota_for_day(day + 1)
		_s_day_ended.rpc(summary)
	_push_state()


func _push_state() -> void:
	_dirty = false
	accounts = ledger.payload()
	_s_state.rpc({"phase": phase, "day": day, "time_left": time_left, "quota": quota,
		"accounts": accounts, "heat": heat, "jail": jail, "inventory": inventory, "owned": owned, "careers": careers,
		"effects": effects, "stats": stats, "raid": raid})


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
func _s_tick(p: Dictionary, t_left: float, h: Dictionary, r: Dictionary, bp: Dictionary = {}) -> void:
	pressure = bp
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
func _s_toast(msg: String) -> void:
	toast.emit(msg)


@rpc("authority", "call_local", "reliable")
func _s_error(msg: String) -> void:
	error_msg.emit(msg)


@rpc("authority", "call_local", "reliable")
func _s_chat(from_name: String, msg: String) -> void:
	chat.emit(from_name, msg)
