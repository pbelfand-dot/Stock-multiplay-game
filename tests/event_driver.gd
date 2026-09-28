extends Node
## Day events, Tony's contracts, office upgrades and milestones, end to end on
## a real (headless, host-only) match:
##   --eventcheck --host --autostart --day_seconds=150 --day_event=flash_crash
##       crash day: morning headline, themed contract, the crash dumps the
##       market, the circuit breaker halts trading (no fills, frozen prices),
##       then it reopens. Then: contracts pay, upgrades change perks, Black
##       Friday prices, the Fed tip, a co-op milestone, tomorrow's forecast.
##   --eventcheck --pvp --host --autostart --day_seconds=4 --day_event=none
##       PvP: the winner takes the championship trophy home.

const Rules = preload("res://scripts/sim/rules.gd")
const DayEvents = preload("res://scripts/sim/day_events.gd")
const Contracts = preload("res://scripts/sim/contracts.gd")

var m
var shocks: Array = []
var tips: Array = []
var done_contracts: Array = []
var hit_milestone := 0.0
var summary := {}


func _ready() -> void:
	_run.call_deferred()


func _say(msg: String) -> void:
	print("[events] " + msg)


func _done(ok: bool, msg: String) -> void:
	print("[events] %s %s" % ["EVENTS PASS" if ok else "EVENTS FAIL:", msg])
	Sfx.quit_game(0 if ok else 1)


func _wait(cond: Callable, secs: float) -> bool:
	var t := 0.0
	while not cond.call():
		await get_tree().process_frame
		t += get_process_delta_time()
		if t > secs:
			return false
	return true


func _now() -> float:
	return m._day_len - m.time_left


func _run() -> void:
	if not await _wait(func(): return get_node_or_null("/root/Main/World/Match") != null, 20.0):
		_done(false, "no match")
		return
	m = get_node("/root/Main/World/Match")
	m.shock.connect(func(k, st): shocks.append("%s:%s" % [k, st]))
	m.tip.connect(func(h, _eta): tips.append(h))
	m.contract_done.connect(func(_p, c, cash): done_contracts.append([c.id, cash]))
	m.milestone.connect(func(a, _x): hit_milestone = a)
	m.day_ended.connect(func(s): summary = s)
	m.game_over.connect(func(s): summary = s)
	if not await _wait(func(): return m.phase == "trading", 20.0):
		_done(false, "day never started")
		return
	if Net.mode == "pvp":
		await _pvp()
	else:
		await _coop()


func _coop() -> void:
	# ---- the morning: today's event, the headline, Tony's contracts
	if Net.mode != "coop":
		_done(false, "the crash-day run should be co-op (events are for every mode)")
		return
	if m.day_event != "flash_crash":
		_done(false, "forced day event didn't take (%s)" % m.day_event)
		return
	if not str(m.last_news.get("headline", "")).contains("FLASH CRASH"):
		_done(false, "no morning headline: %s" % str(m.last_news))
		return
	var mine: Array = m.contracts.get(1, [])
	if mine.size() != 3 or not mine.any(func(c): return c.id == "short_big"):
		_done(false, "contracts wrong on a crash day: %s" % str(mine.map(func(c): return c.id)))
		return
	_say("crash day: headline on air, %d contracts incl. short the crash" % mine.size())

	# ---- the crash: pull it forward so the test doesn't wait all day
	m._sched[0].at = _now() + 10.0
	var btc0: float = m.market.price_of("BTC")
	var gold0: float = m.market.price_of("GOLD")
	if not await _wait(func(): return shocks.has("crash:warn"), 6.0):
		_done(false, "no sirens before the crash")
		return
	if not await _wait(func(): return m.halted(), 20.0):
		_done(false, "circuit breaker never tripped (%s)" % str(shocks))
		return
	var btc1: float = m.market.price_of("BTC")
	var gold1: float = m.market.price_of("GOLD")
	if btc1 > btc0 * 0.95 or gold1 < gold0 * 0.995:
		_done(false, "crash didn't dump BTC / lift gold: BTC %.1f -> %.1f, GOLD %.1f -> %.1f" % [btc0, btc1, gold0, gold1])
		return
	_say("CRASH: BTC %.1f -> %.1f (%.1f%%), gold %.1f -> %.1f, trading halted" % [btc0, btc1, (btc1 / btc0 - 1.0) * 100.0, gold0, gold1])
	# halted: no fills, frozen prices
	var n_pos: int = m.ledger.get_acct(0).positions.size()
	m.request_open("BTC", -1, 1_000.0, 10)
	await get_tree().create_timer(1.5).timeout
	if m.ledger.get_acct(0).positions.size() != n_pos:
		_done(false, "an order filled during the halt")
		return
	if not is_equal_approx(m.market.price_of("BTC"), btc1):
		_done(false, "prices moved during the halt")
		return
	_say("halt: order refused, prices frozen at %.1f" % btc1)
	if not await _wait(func(): return not m.halted(), 25.0):
		_done(false, "trading never reopened")
		return
	if not str(m.last_news.get("headline", "")).contains("CIRCUIT BREAKER LIFTED"):
		_done(false, "no reopen headline: %s" % str(m.last_news))
		return
	await get_tree().create_timer(1.0).timeout
	if is_equal_approx(m.market.price_of("BTC"), btc1):
		_done(false, "market didn't start moving again")
		return
	_say("reopened: BTC trading again at %.1f" % m.market.price_of("BTC"))

	# ---- a contract pays on the spot
	var hd: Dictionary = Contracts.make("hotdog", m.day, Rules.START_FUND, m.rng)
	m.contracts[1] = [hd]
	var bal0: float = m.ledger.get_acct(0).balance
	var xp0: float = m.xp_of(1)
	m.request_hotdog()
	if not await _wait(func(): return not done_contracts.is_empty(), 3.0):
		_done(false, "hot dog contract didn't pay")
		return
	var paid: float = m.ledger.get_acct(0).balance - bal0 + Rules.HOTDOG_PRICE
	if absf(paid - hd.cash) > 1.0 or m.xp_of(1) <= xp0:
		_done(false, "contract paid %f (want %f), xp %f -> %f" % [paid, hd.cash, xp0, m.xp_of(1)])
		return
	_say("contract done: hot dog paid %s + %d XP" % [Rules.money(paid), int(m.xp_of(1) - xp0)])

	# ---- an office upgrade changes your perks
	m.ledger.get_acct(0).balance = 400_000.0
	var fee_before: float = m.perks(1).fee
	m.request_buy_upgrade("up_prime")
	if not await _wait(func(): return m.lux_count(1, "up_prime") == 1, 3.0):
		_done(false, "couldn't buy the Prime Broker account")
		return
	if not is_equal_approx(m.perks(1).fee, fee_before * 0.6) or m.ledger.get_acct(0).balance > 400_000.0 - 149_999.0:
		_done(false, "upgrade perk/price wrong: fee %f, balance %f" % [m.perks(1).fee, m.ledger.get_acct(0).balance])
		return
	m.request_buy_upgrade("up_prime")
	await get_tree().create_timer(0.5).timeout
	if m.ledger.get_acct(0).balance < 400_000.0 - 150_001.0:
		_done(false, "bought the same upgrade twice")
		return
	_say("Prime Broker installed: fees x%.2f, can't buy it twice" % m.perks(1).fee)

	# ---- Black Friday: boutiques 35% off
	m._set_day_event("black_friday")
	var price: float = m.lux_price("louie")
	var bal1: float = m.ledger.get_acct(0).balance
	m.request_buy_lux("louie")
	if not await _wait(func(): return m.lux_count(1, "louie") >= 1, 3.0):
		_done(false, "couldn't buy the bag on Black Friday")
		return
	if not is_equal_approx(price, Rules.LUXURY.louie.price * 0.65) or absf(bal1 - m.ledger.get_acct(0).balance - price) > 1.0:
		_done(false, "Black Friday price wrong: %f, paid %f" % [price, bal1 - m.ledger.get_acct(0).balance])
		return
	_say("Black Friday: Keepall for %s instead of %s" % [Rules.money(price), Rules.money(Rules.LUXURY.louie.price)])

	# ---- Fed day: the Insider Tip knows what Powww will do
	m._set_day_event("fed_day")
	m._sched = DayEvents.schedule("fed_day", m.rng, m._day_len)
	m._sched[0].at = _now() + 40.0
	m._update_event_at()
	m.inventory[1]["tip"] = 1
	m.request_use("tip")
	if not await _wait(func(): return not tips.is_empty(), 3.0):
		_done(false, "no tip")
		return
	if not str(tips[0]).contains("POWWW WILL"):
		_done(false, "tip didn't reveal the Fed: %s" % tips[0])
		return
	_say("insider tip on Fed day: \"%s\"" % tips[0])

	# ---- co-op milestone: the fund crosses $100K -> everyone gets XP
	if m.milestones < 1:
		if not await _wait(func(): return hit_milestone > 0.0, 3.0):
			_done(false, "no milestone at %s" % Rules.money(m.ledger.equity(0, m.market.price_of)))
			return
	if m.milestones < 1:
		_done(false, "milestone count didn't move")
		return
	_say("milestone: the fund passed %s (%d hit)" % [Rules.money(Rules.MILESTONES[0]), m.milestones])

	# ---- the ATM, cash on hand, the spread, and the cops taking half
	if not await _wallet():
		return

	# ---- the closing bell: summary knows today's event and tomorrow's forecast
	m.time_left = 0.5
	if not await _wait(func(): return not summary.is_empty(), 5.0):
		_done(false, "day never ended")
		return
	if summary.get("event", "") != "fed_day" or not summary.has("tomorrow") or not summary.has("contracts"):
		_done(false, "summary missing event/forecast/contracts: %s" % str(summary.keys()))
		return
	if m.next_event != summary.tomorrow:
		_done(false, "forecast doesn't match tomorrow's event")
		return
	# after hours waits for the host; ringing the bell starts tomorrow with its event
	await get_tree().create_timer(2.0).timeout
	if m.phase != "intermission":
		_done(false, "the next day started without the host")
		return
	var tomorrow: String = summary.tomorrow
	Config.cli.erase("day_event")          # stop forcing crashes: day 2 is whatever the forecast said
	m.request_start()
	if not await _wait(func(): return m.phase == "trading" and m.day == 2, 5.0):
		_done(false, "host couldn't start day 2")
		return
	if m.day_event != tomorrow:
		_done(false, "day 2 isn't the forecast event (%s vs %s)" % [m.day_event, tomorrow])
		return
	_done(true, "crash + halt + reopen, contracts, upgrades, Black Friday, Fed tip, milestone, forecast (tomorrow: %s)" % (
			summary.tomorrow if summary.tomorrow != "" else "normal day"))


func _pvp() -> void:
	# a rival who's going to bust: the host wins and takes the trophy home
	m.ledger.create_account(999, "Ghost", Rules.START_FUND)
	m.ledger.get_acct(999).balance = 10.0
	m.ledger.get_acct(1).balance = 500_000.0
	if not await _wait(func(): return not summary.is_empty(), 15.0):
		_done(false, "PvP day never ended")
		return
	if summary.get("winner", "") != "Trader" or int(summary.get("champ", 0)) != 1 or m.lux_count(1, "champ") != 1:
		_done(false, "no championship trophy: %s / owned %s" % [str(summary.get("winner")), str(m.owned.get(1, {}))])
		return
	_done(true, "PvP winner Trader took the championship trophy home")


## ATM out/in, cash pays first, the spread follows the wallet, arrest seizes half.
func _wallet() -> bool:
	var moves: Array = []
	m.cash_moved.connect(func(_p, amt, _t): moves.append(amt))
	var a: Dictionary = m.ledger.get_acct(0)
	a.balance = 100_000.0
	m.request_withdraw(25_000.0)
	if not await _wait(func(): return not moves.is_empty(), 3.0):
		_done(false, "ATM withdraw never happened")
		return false
	if not is_equal_approx(m.cash_of(1), 25_000.0) or not is_equal_approx(a.balance, 75_000.0) or moves[0] <= 0.0:
		_done(false, "withdraw wrong: cash %f, balance %f, moved %f" % [m.cash_of(1), a.balance, moves[0]])
		return false
	m.request_withdraw(10_000_000.0)                 # capped at what's in the account
	if not await _wait(func(): return moves.size() >= 2, 3.0):
		_done(false, "second withdraw never happened")
		return false
	if not is_equal_approx(m.cash_of(1), 100_000.0) or a.balance > 0.5:
		_done(false, "withdraw cap wrong: cash %f, balance %f" % [m.cash_of(1), a.balance])
		return false
	m.request_deposit(40_000.0)
	if not await _wait(func(): return moves.size() >= 3, 3.0):
		_done(false, "deposit never happened")
		return false
	if not is_equal_approx(m.cash_of(1), 60_000.0) or not is_equal_approx(a.balance, 40_000.0) or moves[2] >= 0.0:
		_done(false, "deposit wrong: cash %f, balance %f, moved %f" % [m.cash_of(1), a.balance, moves[2]])
		return false
	_say("ATM: took out $25K, then everything (capped), put $40K back: $60K on hand")
	# the spread: everyone sees it, it follows your wallet
	m.request_spread(Vector3(1, 0, 2), 0.3, false)
	if not await _wait(func(): return m.spreads.has(1), 3.0):
		_done(false, "spread never went down")
		return false
	# cash pays first: a hot dog comes out of your pocket, not the account
	m.request_hotdog()
	if not await _wait(func(): return m.cash_of(1) < 60_000.0, 3.0):
		_done(false, "hot dog didn't come out of cash")
		return false
	if not is_equal_approx(a.balance, 40_000.0) or not is_equal_approx(float(m.spreads[1].amount), m.cash_of(1)):
		_done(false, "pay-from-cash wrong: balance %f, spread %s, cash %f" % [a.balance, str(m.spreads[1]), m.cash_of(1)])
		return false
	var cash0: float = m.cash_of(1)
	# busted with cash on you: the cops bag half, the spread's gone
	m.raid = {"target": 1}
	m.server_cop_caught(1)
	if not is_equal_approx(m.cash_of(1), cash0 - floor(cash0 * Rules.CASH_SEIZED)) or m.spreads.has(1):
		_done(false, "seizure wrong: %f -> %f, spread %s" % [cash0, m.cash_of(1), str(m.spreads.get(1))])
		return false
	_say("cash pays first, the spread follows it, cops seized %s of %s" % [Rules.money(floor(cash0 * Rules.CASH_SEIZED)), Rules.money(cash0)])
	m.jail.erase(1)
	return true
