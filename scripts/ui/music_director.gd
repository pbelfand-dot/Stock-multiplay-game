extends Node
## Picks the soundtrack in a match (the song -> moment table the owner gave):
##   VYZEE "Up Up Up"         the main menu only (fades out as you walk into the office)
##   twentythree "Queen St"   normal trading day / walking the city (default)
##   Lelo "No Contempt"       research: phone open (news, Tramp, tips), the studio
##   Rick Ross "Stay Schemin" high-stakes trade open (x50+, big short, all-in, comeback)
##   Solveig & GTA "Intoxicated" inside the luxury stores and the casino
##   "Type A"                 rival moment: the cops raid you, a PvP rival takes the lead
##   "Blue Bands"             up big / payday / jackpot / buying flex / rank up
##   "12 Stout Street"        end of a day where you lost money (only then)
## Beds follow what you're doing; events override them for a while.

var hud
var m
var now_label: Label
var _check_t := 0.0
var _want := ""
var _want_t := 0.0
var _bed_t := 0.0                 # how long the current bed has played
var _leader := 0                  # PvP: who was on top last check
var _label_t := 0.0
var _placed := false
var _while := Callable()          # the current event's song lasts only while this is true              # current bed came from a place/phase (leaving it is instant too)

const CHECK := 0.5
const SETTLE := 2.5               # a new bed must be wanted this long before we switch
const MIN_BED := 12.0             # ...and the old one must have had this long (places skip it)


func _init(h) -> void:
	hud = h
	m = h.match_node


func _ready() -> void:
	m.trade_closed.connect(_on_trade_closed)
	m.raid_changed.connect(_on_raid)
	m.slot_result.connect(_on_slots)
	m.luxury_bought.connect(_on_luxury)
	m.ranked_up.connect(_on_rank_up)
	m.day_ended.connect(_on_day_ended)
	m.game_over.connect(_on_day_ended)
	m.state_changed.connect(_on_state)
	m.shock.connect(_on_shock)
	m.milestone.connect(func(_a, _x): _event("blue_bands", 20.0, 1))
	Music.now_playing.connect(_on_now_playing)
	now_label = Label.new()
	now_label.add_theme_font_size_override("font_size", 18)
	now_label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.7))
	now_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	now_label.add_theme_constant_override("outline_size", 6)
	now_label.anchor_top = 1.0
	now_label.anchor_bottom = 1.0
	now_label.offset_left = 20
	now_label.offset_top = -118
	now_label.modulate.a = 0.0
	now_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.root.add_child(now_label)
	_bed_t = MIN_BED
	_decide(true)


func _exit_tree() -> void:
	if Music.now_playing.is_connected(_on_now_playing):
		Music.now_playing.disconnect(_on_now_playing)


func _process(delta: float) -> void:
	_bed_t += delta
	if _label_t > 0.0:
		_label_t -= delta
		now_label.modulate.a = clampf(_label_t, 0.0, 1.0)
	_check_t -= delta
	if _check_t <= 0.0:
		_check_t = CHECK
		if Music._event_t > 0.0 and _while.is_valid() and not _while.call():
			Music.clear_event()                          # the moment is over
			_while = Callable()
		_decide(false)
		_check_rival()


# ---------------------------------------------------------------- beds

## [track, urgent] for what you're doing right now. Urgent = a place or a
## phase change, which switches right away instead of waiting.
func bed() -> Array:
	if m.phase == "lobby":
		return ["", true]                                # intro faded; quiet until the opening bell
	var me = hud.world.local_player
	match hud.world.street_zone(me) if me else "":
		"lux", "casino":
			return ["intoxicated", true]
	if me and hud.world.in_studio(me):
		return ["lelo", true]
	var s: Dictionary = m.stats.get(Net.my_id(), {})
	var day_pnl: float = s.get("pnl_day", 0.0)
	var q: float = maxf(m.quota, 50000.0)
	var mine := _my_positions()
	if _high_stakes(mine) or (day_pnl <= -0.05 * q and not mine.is_empty()):
		return ["stay_schemin", false]                   # risky trade / comeback attempt
	if day_pnl >= 0.15 * q:
		return ["blue_bands", false]                     # up big
	if hud.phone and hud.phone.open:
		return ["lelo", false]                           # reading the feed / tips
	return ["queen_st", false]


func _my_positions() -> Array:
	var out := []
	for pos in m.my_acct().get("positions", []):
		if pos.get("trader_id", Net.my_id()) == Net.my_id():
			out.append(pos)
	return out


## x50+ leverage, a big short, or most of the account on the line.
func _high_stakes(mine: Array) -> bool:
	var eq: float = maxf(m.equity_of(m.acct_for(Net.my_id())), 1.0)
	var margin := 0.0
	for pos in mine:
		margin += pos.margin
		if pos.lev >= 50:
			return true
		if pos.side < 0 and pos.margin * pos.lev >= 1.5 * eq:
			return true
	return margin >= 0.4 * eq


func _decide(force: bool) -> void:
	var b := bed()
	var id: String = b[0]
	if id == Music._bed:
		_want = ""
		return
	if force or b[1] or _placed:
		_set_bed(id)
		_placed = b[1]
		return
	if id != _want:
		_want = id
		_want_t = 0.0
	_want_t += CHECK
	if _want_t >= SETTLE and _bed_t >= MIN_BED:
		_set_bed(id)


func _set_bed(id: String) -> void:
	Music.set_bed(id)
	_want = ""
	_bed_t = 0.0


# ---------------------------------------------------------------- events

## Play an event song for at most `hold` seconds, and stop it as soon as the
## action is over (`while_true` returns false), e.g. you walk out of the store.
func _event(id: String, hold: float, prio: int, while_true: Callable = Callable()) -> void:
	Music.event(id, hold, prio)
	if Music._event == id and is_equal_approx(Music._event_t, hold):   # it took (not outranked)
		_while = while_true


func _zone() -> String:
	var me = hud.world.local_player
	return hud.world.street_zone(me) if me else ""

func _on_trade_closed(info: Dictionary) -> void:
	if info.get("trader_id", 0) != Net.my_id():
		return
	var q: float = maxf(m.quota, 50000.0)
	if not info.liquidated and (info.pnl >= 0.1 * q or info.pct >= 150.0):
		_event("blue_bands", 25.0, 1)


func _on_luxury(peer: int, _key: String) -> void:
	if peer == Net.my_id():                          # flexing: plays while you're still in the store
		var z := _zone()
		_event("blue_bands", 45.0, 2, func() -> bool: return _zone() == z)


func _on_rank_up(peer: int, _rank: int) -> void:
	if peer == Net.my_id():
		_event("blue_bands", 15.0, 1)


func _on_raid(target: int, active: bool) -> void:
	if target != Net.my_id():
		return
	if active:
		_event("type_a", 999.0, 3)
	else:
		Music.clear_event("type_a")


func _on_slots(peer: int, _reels: Array, payout: float, bet: float) -> void:
	if peer == Net.my_id() and payout >= bet * 10.0:   # jackpot: until you walk away from the machines
		var z := _zone()
		_event("blue_bands", 30.0, 2, func() -> bool: return _zone() == z)


## End of day: lost money today -> "12 Stout Street" (the only time it plays).
## Made money / hit the quota -> "Blue Bands" payday.
func _on_day_ended(s: Dictionary) -> void:
	var mine: Dictionary = s.get("players", {}).get(Net.my_id(), {}).get("stats", {})
	var pnl: float = mine.get("pnl_day", m.stats.get(Net.my_id(), {}).get("pnl_day", 0.0))
	_while = Callable()
	if pnl < 0.0:
		Music.event("stout_street", 999.0, 4)
	elif pnl > 0.0 or s.get("passed", false):
		Music.event("blue_bands", 999.0, 4)


## Flash crash: rival music through the dump and the halt.
func _on_shock(kind: String, stage: String) -> void:
	if kind == "crash" and stage == "hit":
		_event("type_a", 30.0, 3)


var _last_phase := ""


func _on_state() -> void:
	# a new day starting (the bell) ends the day-end song; any other state
	# update during the day must leave the music alone
	if m.phase != _last_phase:
		if m.phase == "trading" and Music._event_prio >= 4:
			Music.clear_event()                        # new day: back to the beds
		_last_phase = m.phase


## PvP: someone takes the lead from you -> rival music.
func _check_rival() -> void:
	if Net.mode != "pvp" or m.phase != "trading":
		return
	var best := 0
	var best_v := -INF
	for id in m.stats:
		var v: float = m.equity_of(m.acct_for(id))
		if v > best_v:
			best_v = v
			best = id
	if _leader == Net.my_id() and best != Net.my_id() and best != 0:
		_event("type_a", 25.0, 2)
		hud.show_toast("%s just passed you. Take it back." % Net.player_name(best), Color(1, 0.55, 0.3))
	_leader = best


func _on_now_playing(id: String) -> void:
	now_label.text = "♪  " + Music.title_of(id)
	_label_t = 4.0
