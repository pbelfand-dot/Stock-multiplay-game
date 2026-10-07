extends Node3D
## HIGHWAY BATTLES on the LAKESHORE LOOP (cut up): now and then a RIVAL shows up in
## the traffic, a garage car with a name over it, cruising a little under your
## pace. Catch it, get right behind it and FLASH YOUR LIGHTS (H): 3, 2, 1, and it's a
## race through the traffic to a finish 3 km up the road (a gate across the
## highway). First through wins; so does leaving the other 500 m behind; after 3
## minutes whoever's ahead does. A win pays into the cut-up score (more for a
## better rival). Like Tokyo Xtreme Racer's battles and Need for Speed's outruns,
## kept simple: no health bars, the road decides.
## The rivals drive in Traffic (Traffic.add_rival / _drive_racer): the same lanes,
## the same cars to get past.

const VehicleRegistry = preload("res://scripts/game/vehicle_registry.gd")

## [registry id, nickname, level 1..5]
const ROSTER := [
	["raiden", "BLUE THUNDER", 3], ["akatsuki", "RED SUN", 2], ["rotora_fd", "ROTARY GHOST", 3],
	["lancer", "TURBO KNIGHT", 2], ["hellhound", "BLACK DEMON", 3], ["kaiser_4", "BAVARIAN BLADE", 3],
	["elfer_rs", "WINGED FALCON", 4], ["sylph", "SILVER WIND", 1], ["hachi", "TOFU RUNNER", 1],
	["brawler", "MUSCLE KING", 2], ["kaiser_8", "GRAND TOURER", 2], ["kombi", "THE ESTATE", 2],
	["ghost", "NORTHERN GHOST", 5], ["vento", "VENTO", 5], ["centuria", "MONSIEUR SEIZE", 5],
	["pleiad", "STAR SEVEN", 2], ["kaiser_2", "LITTLE BAVARIAN", 2],
]
const RACE_LEN := 3000.0            # m to the finish gate from the start
const CHALLENGE_GAP := 45.0         # m: as close behind as you have to be to flash a rival
const GAP_WIN := 500.0              # m: lead by this much and it's over
const TIME_LIMIT := 180.0
const BONUS := [0, 2000, 3500, 5000, 7500, 10000]   # points for beating a rival of each level

var traffic
var st
var rival := {}                     # the rival's traffic car (it has .rival)
var state := "none"                 # "none", "cruise", "intro", "race", "after"
var finish_s := 0.0
var race_t := 0.0
var beaten := 0
var lost := 0
var events: Array = []              # [[text, colour, bonus points]]: the game shows them
var _t := 0.0
var _next := 25.0                   # s until the next rival shows up
var _count := -1
var _gate: Node3D
var _rng := RandomNumberGenerator.new()
var _used := {}
var pick_only := ""                 # (tests: this rival, by registry id, every time)


func setup(traffic_, st_, seed_value: int) -> void:
	traffic = traffic_
	st = st_
	_rng.seed = hash([seed_value, "rivals"])
	_next = _rng.randf_range(12.0, 25.0)


## One tick. player: {s, d, v}; flash: the lights were flashed this tick.
func tick(dt: float, player: Dictionary, flash: bool) -> void:
	var ps: float = player.s
	match state:
		"none":
			_next -= dt
			if _next <= 0.0:
				_spawn(ps)
		"cruise":
			var rel: float = float(rival.s) - ps
			if rel < -traffic.BEHIND - 60.0 or rel > traffic.AHEAD + 400.0:
				_drop()
			elif flash and can_challenge(player):
				state = "intro"
				_t = 3.0
				_count = -1
				events.append(["BATTLE!  %s" % rival.rival.nick, Color(1.0, 0.82, 0.2), 0])
		"intro":
			_t -= dt
			var n := ceili(_t)
			if n != _count and n > 0:
				_count = n
				events.append([str(n), Color.WHITE, 0])
			if _t <= 0.0:
				state = "race"
				race_t = 0.0
				rival.rival.racing = true
				finish_s = maxf(ps, float(rival.s)) + RACE_LEN
				_build_gate()
				events.append(["GO!", Color(0.4, 1.0, 0.45), 0])
		"race":
			race_t += dt
			var gap: float = float(rival.s) - ps
			if ps >= finish_s:
				_result(true, "THROUGH THE FINISH FIRST")
			elif float(rival.s) >= finish_s:
				_result(false, "%s GOT THERE FIRST" % rival.rival.nick)
			elif gap < -GAP_WIN:
				_result(true, "LEFT %s BEHIND" % rival.rival.nick)
			elif gap > GAP_WIN:
				_result(false, "%s GOT AWAY" % rival.rival.nick)
			elif race_t > TIME_LIMIT:
				_result(gap < 0.0, "TIME")
		"after":
			_t -= dt
			var rel2: float = float(rival.s) - ps
			if _t <= 0.0 or rel2 < -traffic.BEHIND - 60.0 or rel2 > traffic.AHEAD + 400.0:
				_drop()


## Close enough behind the rival, in its lane, to flash it?
func can_challenge(player: Dictionary) -> bool:
	if state != "cruise" or rival.is_empty():
		return false
	var gap: float = float(rival.s) - float(player.s)
	return gap > 0.0 and gap < CHALLENGE_GAP and absf(float(rival.d) - float(player.d)) < 3.0 and float(player.v) > 15.0


## The HUD's lines for the battle (or "" when there's none to show).
func hud_text(player: Dictionary) -> String:
	match state:
		"cruise":
			var rel: float = float(rival.s) - float(player.s)
			if can_challenge(player):
				return "%s\nFLASH YOUR LIGHTS (H) TO RACE" % rival.rival.nick
			if rel > 0.0 and rel < 600.0:
				return "RIVAL AHEAD  %s  %.0f m" % [rival.rival.nick, rel]
		"intro", "race":
			var gap: float = float(rival.s) - float(player.s)
			return "VS %s\n%s  %.0f m   FINISH %.1f km" % [rival.rival.nick, "BEHIND" if gap > 0.0 else "AHEAD", absf(gap),
				maxf(finish_s - float(player.s), 0.0) / 1000.0 if state == "race" else RACE_LEN / 1000.0]
	return ""


func _spawn(ps: float) -> void:
	var picks: Array = ROSTER.filter(func(r): return not _used.has(r[0]) and VehicleRegistry.entry(r[0]) != null)
	if pick_only != "":
		picks = ROSTER.filter(func(r): return r[0] == pick_only)
	if picks.is_empty():
		_used.clear()
		picks = ROSTER.filter(func(r): return VehicleRegistry.entry(r[0]) != null)
	if picks.is_empty():
		return
	var r: Array = picks[_rng.randi() % picks.size()]
	var entry: Dictionary = VehicleRegistry.entry(r[0])
	for k in 6:
		var c: Dictionary = traffic.add_rival(ps + _rng.randf_range(380.0, 520.0), _rng.randi() % traffic.lanes, entry, int(r[2]), r[1])
		if not c.is_empty():
			rival = c
			state = "cruise"
			_used[r[0]] = true
			events.append(["A RIVAL'S ON THE HIGHWAY: %s" % r[1], Color(1.0, 0.82, 0.2), 0])
			return
	_next = 3.0                                          # (no room just now: in a moment)


func _result(won: bool, why: String) -> void:
	state = "after"
	_t = 10.0
	rival.rival.racing = false
	rival.v0 = 95.0 / 3.6                                # (it eases off and drops back)
	if won:
		beaten += 1
		var pts: int = BONUS[clampi(int(rival.rival.level), 1, 5)]
		events.append(["YOU WIN · %s  +%d" % [why, pts], Color(0.4, 1.0, 0.45), pts])
	else:
		lost += 1
		events.append(["YOU LOSE · %s" % why, Color(1.0, 0.35, 0.3), 0])
	if _gate:
		_gate.queue_free()
		_gate = null


func _drop() -> void:
	if not rival.is_empty():
		traffic.remove_rival(rival)
	rival = {}
	state = "none"
	_next = _rng.randf_range(25.0, 50.0)
	if _gate:
		_gate.queue_free()
		_gate = null


## The finish: a gate across our carriageway, posts each side, a chequered banner.
func _build_gate() -> void:
	_gate = Node3D.new()
	_gate.name = "FinishGate"
	add_child(_gate)
	var bas := Basis(Vector3.UP, -st.heading_at(finish_s))
	var c: Vector3 = st.world_at(finish_s, 0.0)
	var half: float = st.EDGE + st.SHOULDER_R
	var post_m := StandardMaterial3D.new()
	post_m.albedo_color = Color(0.85, 0.85, 0.85)
	var banner_m := StandardMaterial3D.new()
	banner_m.albedo_texture = _chequer()
	banner_m.uv1_scale = Vector3(12.0, 2.0, 1.0)
	banner_m.emission_enabled = true
	banner_m.emission_texture = banner_m.albedo_texture
	banner_m.emission_energy_multiplier = 0.4
	for d in [-half, half]:
		var post := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.5, 7.5, 0.5)
		post.mesh = bm
		post.material_override = post_m
		post.transform = Transform3D(bas, st.world_at(finish_s, d) + Vector3.UP * 3.75)
		_gate.add_child(post)
	var banner := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(half * 2.0, 1.4, 0.2)
	banner.mesh = bb
	banner.material_override = banner_m
	banner.transform = Transform3D(bas, c + Vector3.UP * 6.8)
	_gate.add_child(banner)
	var lbl := Label3D.new()
	lbl.text = "FINISH"
	lbl.font_size = 140
	lbl.pixel_size = 0.02
	lbl.outline_size = 16
	lbl.modulate = Color(1.0, 0.85, 0.2)
	lbl.transform = Transform3D(bas * Basis(Vector3.UP, PI), c + Vector3.UP * 8.6 - st.forward_at(finish_s) * 0.3)
	_gate.add_child(lbl)


func _chequer() -> ImageTexture:
	var img := Image.create(8, 8, false, Image.FORMAT_RGB8)
	for y in 8:
		for x in 8:
			img.set_pixel(x, y, Color.WHITE if ((x / 4) + (y / 4)) % 2 == 0 else Color(0.05, 0.05, 0.05))
	var tex := ImageTexture.create_from_image(img)
	return tex
