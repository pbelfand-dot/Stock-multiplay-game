extends Node
## Magnolia Heights + the highway, end to end on a real (host-only) match.
##   --hoodcheck --host --autostart          headless: the neighborhood builds, a
##       house can be bought (balance, owned, a second buyer refused), the realtor
##       panel / door key / mailbox follow ownership, taxis go to the neighborhood,
##       home (standing by the bed, not falling through) and back downtown, and
##       30 simulated seconds of traffic never overlap cars or break speed limits.
##   --hoodshots=<dir> --host --autostart    review screenshots (needs a display):
##       xvfb-run -a -s "-screen 0 1600x900x24" godot --path . -- --host --autostart --hoodshots=/tmp/hood

const Rules = preload("res://scripts/sim/rules.gd")
const Highway = preload("res://scripts/world/highway.gd")

const MIN_GAP := 0.5          # metres: bumper to bumper, same lane
const V_LIMIT := 45.0

var w
var m
var hood
var out_dir := ""


func _ready() -> void:
	_run.call_deferred()


func _say(msg: String) -> void:
	print("[hood] " + msg)


func _done(ok: bool, msg: String) -> void:
	print("[hood] %s %s" % ["HOOD PASS" if ok else "HOOD FAIL:", msg])
	Sfx.quit_game(0 if ok else 1)


func _wait(cond: Callable, secs: float) -> bool:
	var t := 0.0
	while not cond.call():
		await get_tree().process_frame
		t += get_process_delta_time()
		if t > secs:
			return false
	return true


func _physics(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _run() -> void:
	if not await _wait(func(): return get_node_or_null("/root/Main/World/Match") != null, 30.0):
		_done(false, "no match")
		return
	w = get_node("/root/Main/World")
	m = w.match_node
	hood = w.builder.hood
	await _wait(func(): return m.phase == "trading", 20.0)
	await _wait(func(): return w.local_player != null, 10.0)
	if Config.cli.has("hoodshots"):
		out_dir = str(Config.cli.hoodshots)
		DirAccess.make_dir_recursive_absolute(out_dir)
		await _shots()
		Sfx.quit_game()
		return
	await _check()


# ================================================================== checks

func _check() -> void:
	var p = w.local_player
	var me := Net.my_id()
	# ---- it built: houses, listings, interiors lined up with the bed spawn
	var n: int = hood.houses.size()
	if n < 20 or n > 30:
		_done(false, "%d houses (want 20-30)" % n)
		return
	if hood.buyable.size() < 5 or hood.buyable.size() > 6 or hood.buyable.size() != Rules.HOUSES.size():
		_done(false, "%d buyable houses, Rules.HOUSES has %d" % [hood.buyable.size(), Rules.HOUSES.size()])
		return
	for id in Rules.HOUSES:
		var h: Dictionary = hood.houses[hood.buyable[id]]
		if h.address != Rules.HOUSES[id].address:
			_done(false, "%s is at %s but Rules says %s" % [id, h.address, Rules.HOUSES[id].address])
			return
		if h.interior == null or (h.interior as Node3D).get_child_count() == 0:
			_done(false, "%s has no interior" % id)
			return
		if Vector2(h.spawn.x - h.bed.x, h.spawn.z - h.bed.z).length() > 2.2:
			_done(false, "%s spawn is %.1f m from the bed" % [id, h.spawn.distance_to(h.bed)])
			return
		if hood.houses[hood.buyable[id]].id != id or not w.hood.inside_house_at(h.spawn).begins_with(id):
			_done(false, "%s spawn isn't inside the house (%s)" % [id, w.hood.inside_house_at(h.spawn)])
			return
	_say("built: %d houses, %d for sale, highway %.0f m, %d ramp/road paths, build %d ms" % [n, hood.buyable.size(),
			hood.hw.length, hood.hw.paths.size(), hood.build_ms])
	var far: float = Vector2(hood.r2.x - 40.0, hood.r2.z - 240.0).length()
	if far < 500.0 or far > 900.0:
		_done(false, "the neighborhood is %.0f m from downtown (want ~500-800)" % far)
		return
	# ---- collision where you walk: the flyover deck over the highway, a porch, a house floor
	var space: PhysicsDirectSpaceState3D = w.get_world_3d().direct_space_state
	var probes := {"flyover": hood.hw.point(Highway.SB_DOWNTOWN, 0.0, 20.0), "highway": hood.hw.point(700.0, 7.0, 5.0),
		"ranch_a floor": (hood.houses[hood.buyable.ranch_a].xf as Transform3D) * Vector3(-3.0, 5.0, -2.0)}
	for k in probes:
		var from: Vector3 = probes[k]
		var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -30, 0))
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			_done(false, "nothing to stand on at the %s (%s)" % [k, str(from)])
			return
		_say("ground at the %s: y=%.2f" % [k, hit.position.y])
	# ---- the realtor: open a listing for a house nobody owns
	var idx: int = hood.buyable["ranch_a"]
	w.hood.interact({"type": "hood_sign", "id": idx})
	await get_tree().process_frame
	if not w.hud.is_modal_open() or not w.hood.ui_open():
		_done(false, "the realtor panel didn't open")
		return
	w.hud.close_modals()
	# ---- buy it (co-op: the shared fund pays)
	var acct: int = m.acct_for(me)
	var a: Dictionary = m.ledger.get_acct(acct)
	m.ledger.adjust(acct, 1_000_000.0 - float(a.balance))
	m._push_state()
	var before: float = m.ledger.get_acct(acct).balance
	m.request_buy_house("ranch_a")
	if not await _wait(func(): return int(m.owned.get(me, {}).get("house_ranch_a", 0)) == 1, 5.0):
		_done(false, "buying ranch_a didn't set owned")
		return
	var paid: float = before - float(m.ledger.get_acct(acct).balance)
	if absf(paid - Rules.HOUSES.ranch_a.price) > 0.5:
		_done(false, "ranch_a cost %.0f, expected %.0f" % [paid, Rules.HOUSES.ranch_a.price])
		return
	if m.house_of(me) != "ranch_a" or m.house_owner("ranch_a") != me:
		_done(false, "house_of / house_owner disagree")
		return
	# a second buyer is refused, and nobody owns two
	Net.players[901] = {"name": "Rival", "color": Color.RED, "look": {}}
	var err: String = m.buy_house(901, "ranch_a")
	var err2: String = m.buy_house(me, "tin_a")
	var bal_after: float = m.ledger.get_acct(acct).balance
	Net.players.erase(901)
	m.owned.erase(901)
	m.careers.erase(901)
	if err == "" or not err.contains("SOLD"):
		_done(false, "a second buyer got ranch_a (%s)" % err)
		return
	if err2 == "" or absf(bal_after - (before - paid)) > 0.5:
		_done(false, "bought a second house (%s)" % err2)
		return
	_say("bought ranch_a for %s; rival refused (\"%s\"); second house refused" % [Rules.money(paid), err])
	# ---- the world follows: SOLD sign, name on the mailbox, the key
	await get_tree().process_frame
	var h: Dictionary = hood.houses[idx]
	var body: StaticBody3D = h.door.get_node("Body")
	if str(body.get_meta("prompt", "")) != "[E] Home sweet home" or str(body.get_meta("interact", "")) != "hood_door":
		_done(false, "the owner's door prompt is '%s'" % str(body.get_meta("prompt", "")))
		return
	if (h.sign_labels[0][0] as Label3D).text != "SOLD" or (h.mailbox_label as Label3D).text != Net.player_name(me).to_upper():
		_done(false, "sign/mailbox didn't update ('%s' / '%s')" % [(h.sign_labels[0][0] as Label3D).text,
				(h.mailbox_label as Label3D).text])
		return
	w.hood.interact({"type": "hood_door", "id": idx})
	if float(h.door_open) < 1.0:
		_done(false, "the key didn't open the door")
		return
	_say("sign SOLD, mailbox '%s', door opens with the key" % (h.mailbox_label as Label3D).text)
	# ---- taxis: to the neighborhood, home (by the bed), downtown
	w.hood.open_taxi(0)
	await get_tree().process_frame
	if w.hood.ui.body.get_node_or_null("Dest_home") == null or w.hood.ui.body.get_node_or_null("Dest_hood") == null:
		_done(false, "taxi panel is missing MY HOUSE / MAGNOLIA HEIGHTS")
		return
	w.hud.close_modals()
	if not w.go_to_neighborhood(true):
		_done(false, "go_to_neighborhood refused")
		return
	await _physics(40)
	if not w.in_neighborhood(p) or p.global_position.y < -0.5:
		_done(false, "taxi to the neighborhood: at %s" % str(p.global_position))
		return
	if not w.go_home(true):
		_done(false, "go_home refused")
		return
	await _physics(60)
	var d: float = Vector2(p.global_position.x - h.spawn.x, p.global_position.z - h.spawn.z).length()
	if d > 0.6 or absf(p.global_position.y - float(h.spawn.y) + 0.15) > 0.35 or w.hood.inside_house(p) != "ranch_a":
		_done(false, "go_home: %.2f m from the spawn, y %.2f (spawn %.2f), inside '%s'" % [d, p.global_position.y, h.spawn.y,
				w.hood.inside_house(p)])
		return
	_say("taxi: neighborhood ok, home ok (%.2f m from the bed spawn, standing at y=%.2f)" % [d, p.global_position.y])
	# ---- walk in: from the front walk, up the steps, through the front door (real input, real collision)
	for id in Rules.HOUSES:
		var hh: Dictionary = hood.houses[hood.buyable[id]]
		var front: Vector3 = hh.front
		var start: Vector3 = hh.entry + front * 3.2 - Vector3(0, hh.entry.y - 0.35, 0)
		p.teleport(start)
		p.rotation.y = atan2(front.x, front.z)          # look at the house (-z forward = -front)
		await _physics(10)
		Input.action_press("move_forward")
		var t_in := 0.0
		while t_in < 6.0 and w.hood.inside_house(p) != id:
			await get_tree().physics_frame
			t_in += 1.0 / 60.0
		Input.action_release("move_forward")
		if w.hood.inside_house(p) != id:
			_done(false, "couldn't walk into %s (%s): stuck at %s" % [id, hh.address, str(p.global_position)])
			return
	_say("walked up the steps and in the front door of all %d for-sale houses" % Rules.HOUSES.size())
	w.hood.ride("downtown", true)
	await _physics(20)
	if not w.in_street(p):
		_done(false, "taxi downtown ended at %s" % str(p.global_position))
		return
	# ---- traffic: 30 simulated seconds
	var tr = hood.traffic
	if Config.cli.has("hoodseed"):
		tr.rng.seed = int(Config.cli.hoodseed)
	var worst := INF
	var vmax := 0.0
	var steps := int(60.0 * tr.SIM_HZ)     # (the brief asks for 30 s; a minute also sees exits and merges)
	for i in steps:
		tr.step(1.0 / tr.SIM_HZ)
		var g: float = tr.min_gap()
		worst = minf(worst, g)
		if g < MIN_GAP:
			_done(false, "two cars %.2f m apart at t=%.1f s: %s / %s" % [g, tr.sim_time, tr.describe_car(tr.last_pair[0]),
					tr.describe_car(tr.last_pair[1])])
			return
		for c in tr.cars:
			if c.waiting:
				continue
			if is_nan(c.s) or is_nan(c.v) or c.v < 0.0 or c.v > V_LIMIT:
				_done(false, "car %d: s=%s v=%s" % [c.id, str(c.s), str(c.v)])
				return
			vmax = maxf(vmax, c.v)
			if c.on_main and c.truck and c.lane == 0 and c.lc_t >= 1.0:
				_done(false, "a truck in the fast lane")
				return
			if not c.on_main and c.v > c.path.v_max + 3.0:
				_done(false, "car %d at %.1f m/s on %s (limit %.0f)" % [c.id, c.v, c.path.name, c.path.v_max])
				return
	for c in tr.cars:
		var lo := 22.0 if c.truck else 25.0
		var hi := 26.0 if c.truck else 38.0
		if c.v0 < lo - 0.01 or c.v0 > hi + 0.01:
			_done(false, "car %d wants %.1f m/s" % [c.id, c.v0])
			return
	var st: Dictionary = tr.stats
	_say("traffic 60 s: %d cars, min gap %.2f m, top speed %.1f m/s, %d lane changes, %d merges, %d exits (%d missed), %d recycled" %
			[tr.cars.size(), worst, vmax, st.lane_changes, st.merges, st.exits, st.missed_exits, st.recycled])
	if st.lane_changes < 3 or st.merges < 1 or st.exits < 1:
		_done(false, "traffic too static (lane changes %d, merges %d, exits %d)" % [st.lane_changes, st.merges, st.exits])
		return
	# ---- an outside car stopped in the middle eastbound lane: traffic brakes / goes round, never through
	var hw = hood.hw
	var obs := Node3D.new()
	obs.name = "StalledCar"
	w.add_child(obs)
	# it "appears" somewhere in lane 1 that everybody behind can still stop for
	var s_obs := -1.0
	for attempt in 600:
		var cand := 480.0
		while cand < 950.0 and s_obs < 0.0:
			var clear := true
			for c in tr.cars:
				if c.waiting or not c.on_main or c.dir != 1 or not (c.lane == 1 or c.from_lane == 1):
					continue
				var gap: float = cand - c.s - (c.L + 4.6) / 2.0
				if gap > -30.0 and gap < c.v * c.v / (2.0 * 7.0) + 6.0:
					clear = false
			if clear:
				s_obs = cand
			cand += 5.0
		if s_obs >= 0.0:
			break
		tr.step(1.0 / tr.SIM_HZ)       # wait for a gap to come along
	if s_obs < 0.0:
		_done(false, "no room anywhere in lane 1 for the stalled-car test")
		return
	obs.global_position = hw.lane_center(1, 1, s_obs)
	tr.register_obstacle(obs, 4.6, 1.9)
	var queued := 0
	var passed_by := 0
	var hist := {}
	for i in int(25.0 * tr.SIM_HZ):
		tr.step(1.0 / tr.SIM_HZ)
		for c in tr.cars:
			if c.waiting or not c.on_main or c.dir != 1:
				continue
			var ds: float = s_obs - c.s
			if c.lane == 1 or (c.lc_t < 0.5 and c.from_lane == 1):
				if ds > -(c.L + 4.6) / 2.0 and ds < (c.L + 4.6) / 2.0 + MIN_GAP:
					for hline in hist.get(c.id, []):
						print("   ", hline)
					var ob = tr.obstacles[tr.obstacles.size() - 1]
					_done(false, "car %d drove into the stalled car (%.2f m, lane %d): %s / obstacle %s" % [c.id, ds, c.lane,
							tr.describe_car(c), tr.describe_car(ob) if not ob.waiting else "waiting"])
					return
				if absf(ds) < 120.0:
					var hl: Array = hist.get(c.id, [])
					hl.append("t=%.2f %s ds=%.1f" % [tr.sim_time, tr.describe_car(c), ds])
					if hl.size() > 12:
						hl.pop_front()
					hist[c.id] = hl
				if ds > 0.0 and ds < 12.0 and c.v < 1.0:
					queued += 1
			elif absf(ds) < 3.0 and c.v > 5.0:
				passed_by += 1
	tr.unregister_obstacle(obs)
	_say("stalled car in lane 1: %d car-steps queued behind it, %d car-steps passing in other lanes, no contact" % [queued, passed_by])
	if passed_by == 0:
		_done(false, "nobody changed lanes around a stalled car")
		return
	# ---- every traffic car is a solid body on layer 1 near the player
	tr.watch = obs
	tr.force_awake = true
	await _physics(8)
	var solid_car = null
	for c in tr.cars:
		if not c.waiting and not c.shape.disabled:
			solid_car = c
			break
	if solid_car == null or (solid_car.node as CollisionObject3D).collision_layer != 1:
		_done(false, "no traffic collider near the watched node")
		return
	var top: Vector3 = solid_car.node.global_position + Vector3(0, 6, 0)
	var hit2 := space.intersect_ray(PhysicsRayQueryParameters3D.create(top, top + Vector3(0, -8, 0)))
	if hit2.is_empty() or hit2.collider != solid_car.node:
		_done(false, "a ray onto traffic car %d hit %s" % [solid_car.id, str(hit2.get("collider"))])
		return
	tr.watch = null
	tr.force_awake = false
	obs.queue_free()
	var act: Array = tr.active_cars()
	if act.is_empty() or not act[0].has("node") or not act[0].has("lane") or not act[0].has("speed"):
		_done(false, "active_cars() is missing fields")
		return
	_say("colliders ok (%s on layer 1, hit by a ray); active_cars() lists %d" % [solid_car.node.name, act.size()])
	# ---- the nice-car hook: another kit's car shows up about 1 in 12
	var kept: Array = tr.nice_models.duplicate()      # the game's own nice cars (the BEMZE lineup) step aside for this
	tr.nice_models.clear()
	tr.add_nice_model("Car_Bemze")
	var nice := 0
	var other := 0
	var probe = tr.Car.new()
	for i in 600:
		tr._assign_model(probe)
		if probe.nice:
			if probe.model == "Car_Bemze":
				nice += 1
			else:
				other += 1
	tr.nice_models.clear()
	tr.nice_models.append_array(kept)
	var regular := 0
	for i in 200:
		tr._assign_model(probe)
		if not probe.nice and str(probe.model).begins_with("TCar_"):
			regular += 1
	if other > 0 or nice < 20 or nice > 90 or regular < 150 or probe.L < 3.0:
		_done(false, "nice-car mix: %d Car_Bemze, %d other nice of 600; %d regular of 200" % [nice, other, regular])
		return
	_say("nice cars: %d / 600 from nice_models (~1 in %d), everyday cars otherwise" % [nice, int(600.0 / maxf(nice, 1))])
	# ---- routes + the dealership lot
	for rn in ["home_to_office", "office_to_home"]:
		var rt: Dictionary = hw.route(rn)
		var pts: PackedVector3Array = rt.points
		if pts.size() < 50:
			_done(false, "route %s has %d points" % [rn, pts.size()])
			return
		var a0: Vector3 = pts[0]
		var a1: Vector3 = pts[pts.size() - 1]
		var hood_end: Vector3 = a0 if rn == "home_to_office" else a1
		var town_end: Vector3 = a1 if rn == "home_to_office" else a0
		if hood_end.distance_to(hood.r2) > 40.0 or town_end.distance_to(w.builder.street.ORIGIN) > 90.0:
			_done(false, "route %s runs %s -> %s" % [rn, str(a0), str(a1)])
			return
		var worst_jump := 0.0
		for i in range(1, pts.size()):
			worst_jump = maxf(worst_jump, pts[i].distance_to(pts[i - 1]))
		if worst_jump > 45.0:
			_done(false, "route %s jumps %.0f m" % [rn, worst_jump])
			return
	var lot: Vector3 = hood.dealership_marker.global_position
	var q2 := PhysicsRayQueryParameters3D.create(lot + Vector3(0, 10, 0), lot + Vector3(0, -10, 0))
	var hit3 := space.intersect_ray(q2)
	if hood.dealership_marker.name != "DealershipLot" or hit3.is_empty() or absf(hit3.position.y) > 0.05 \
			or not hw.dealership_rect.has_point(Vector2(lot.x, lot.z)):
		_done(false, "dealership lot marker at %s, ground %s" % [str(lot), str(hit3.get("position"))])
		return
	_say("routes ok; dealership lot at (%.1f, %.1f, %.1f), exit at station %.0f eastbound" % [lot.x, lot.y, lot.z, hw.DEALER_S])
	_done(true, "neighborhood, purchase, taxis and traffic all ok")


# ================================================================== screenshots

func _snap(nm: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [out_dir, nm])
	print("shot: %s  (draws %d, prims %d)" % [nm,
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## Stand at `pos` (feet) looking toward `at`.
func _look(pos: Vector3, at: Vector3) -> void:
	var p = w.local_player
	p.teleport(pos)
	var d := at - (pos + Vector3(0, 1.6, 0))
	p.rotation.y = atan2(-d.x, -d.z)
	var pitch := atan2(d.y, Vector2(d.x, d.z).length())
	p.pitch = pitch
	p.head.rotation.x = pitch


func _view(nm: String, pos: Vector3, at: Vector3, frames := 12) -> void:
	m.pressure[Net.my_id()] = 0.0
	_look(pos, at)
	await _frames(frames)
	await _snap(nm)


func _shots() -> void:
	# llvmpipe picks LOW (220 m view): review at HIGH without saving it to settings
	Graphics.cur = Graphics.PRESETS["high"]
	Graphics.changed.emit()
	var hw = hood.hw
	var tr = hood.traffic
	tr.force_awake = true
	for i in 200:          # let the traffic spread out
		tr.step(0.1)
	await get_tree().create_timer(4.0).timeout   # the elevator arrival walk
	var only := str(Config.cli.get("hoodonly", ""))
	if only == "perf":
		await _perf()
		return
	# top-down overview (a separate camera, for the layout)
	if only == "" or only == "map":
		var cam := Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = 1250.0
		cam.far = 3000.0
		cam.position = Vector3(560, 700, 420)
		w.add_child(cam)
		cam.rotation = Vector3(-PI / 2, 0, 0)
		cam.current = true
		await _frames(6)
		await _snap("h00_map")
		cam.size = 320.0
		cam.position = Vector3(hood.r2.x + 60.0, 200, hood.r2.z + 20.0)
		await _frames(4)
		await _snap("h00b_map_hood")
		cam.size = 360.0
		cam.position = Vector3(170, 400, 300)
		await _frames(4)
		await _snap("h00c_map_downtown_link")
		cam.size = 300.0
		cam.position = hw.point(Highway.SB_HOOD - 60.0, 40.0, 400.0)
		await _frames(4)
		await _snap("h00d_map_hood_interchange")
		cam.current = false
		cam.queue_free()
		w.local_player.cam.current = true
	var sb: float = Highway.SB_DOWNTOWN
	if only == "" or only == "hwy":
		await _view("h01_highway_from_flyover", hw.point(sb + 2.0, -6.0, 7.45), hw.point(sb + 400.0, 0.0, 2.0))
		await _view("h02_highway_eastbound", hw.point(250.0, 17.5, 0.0), hw.point(420.0, 6.0, 1.0))
		await _view("h03_highway_traffic_close", hw.point(480.0, -19.0, 0.0), hw.point(430.0, 0.0, 0.5))
		await _view("h04_flyover_from_below", hw.point(sb + 40.0, -17.0, 0.0), hw.point(sb, 0.0, 6.0))
		await _view("h05_tunnel_portal", hw.point(150.0, 8.0, 0.0), hw.point(60.0, 0.0, 5.0))
		await _view("h06_hood_interchange", hw.point(Highway.SB_HOOD + 30.0, 22.0, 0.0), hw.point(Highway.SB_HOOD - 80.0, 20.0, 3.0))
		await _view("h07_downtown_gap", Vector3(20, 0.25, 238.0), Vector3(120, 3.0, 250.0))
		await _view("h08_connector_roundabout", Vector3(105, 0.25, 255.0), Vector3(70, 1.0, 238.0))
		var lot: Vector3 = hood.dealership_marker.global_position
		await _view("h09_dealership_exit", hw.point(Highway.DEALER_S - 30.0, 15.0, 0.0), hw.point(Highway.DEALER_S + 60.0, 40.0, 0.0))
		await _view("h09b_dealership_lot", lot + Vector3(-40.0, 0.3, 30.0), lot + Vector3(0, 1.0, 0))
		await _view("h09c_downtown_from_hood", Vector3(hood.r2.x - 30.0, 0.35, hood.r2.z + 30.0), Vector3(0, 20.0, 240.0))
	var r2: Vector3 = hood.r2
	if only == "" or only == "street":
		await _view("h10_magnolia_st", Vector3(r2.x + 18.0, 0.25, r2.z + 1.5), Vector3(r2.x + 120.0, 2.0, r2.z))
		await _view("h11_pecan_st", Vector3(r2.x + 130.0, 0.25, r2.z + 70.0 - 1.5), Vector3(r2.x + 10.0, 2.0, r2.z + 70.0))
		await _view("h12_hood_entrance", Vector3(r2.x - 10.0, 0.35, r2.z + 26.0), Vector3(r2.x + 30.0, 2.0, r2.z))
		await _view("h13_tin_row", Vector3(r2.x + 30.0, 0.25, r2.z + 64.0), Vector3(r2.x + 30.0, 2.0, r2.z + 90.0))
	if only == "" or only == "types":
		var done := {}
		for h in hood.houses:
			if h.id != "" or done.has(h.type):
				continue
			done[h.type] = true
			var xf: Transform3D = h.xf
			await _view("h2%d_type_%s" % [done.size(), h.type], xf * Vector3(5.5, 0.35, 16.0), xf * Vector3(0.0, 2.6, -4.0))
	if only == "" or only == "sale":
		var idx: int = hood.buyable["ranch_a"]
		var h: Dictionary = hood.houses[idx]
		var sp: Vector3 = (h.sign as Node3D).global_position
		var front: Vector3 = h.front
		await _view("h30_for_sale_sign", sp + front * 3.2 + Vector3(-1.0, 0.1, 0), sp + Vector3(0, 1.1, 0))
		w.hood.interact({"type": "hood_sign", "id": idx})
		await _frames(6)
		await _snap("h31_realtor_panel")
		w.hud.close_modals()
		var ts: Dictionary = hood.taxi[1]
		await _view("h32_taxi_hood", ts.pos + Vector3(-5.0, 0.0, -5.5), ts.pos + Vector3(0.0, 1.5, 1.5))
		w.hood.open_taxi(1)
		await _frames(6)
		await _snap("h33_taxi_panel")
		w.hud.close_modals()
		var td: Dictionary = hood.taxi[0]
		await _view("h34_taxi_downtown", td.pos + Vector3(-6.0, 0.0, -3.5), td.pos + Vector3(0.0, 1.5, 1.5))
	if only == "" or only == "int":
		for id in Rules.HOUSES:
			var h: Dictionary = hood.houses[hood.buyable[id]]
			var xf: Transform3D = h.xf
			var I: Dictionary = hood.layout.interiors[id]
			var FH: float = float(hood.layout.types[h.type].FH)
			for r in I.rooms:
				if not (r[0] in ["living", "kitchen", "bedroom", "bath"]):
					continue
				var x0: float = r[1]
				var z0: float = r[2]
				var x1: float = r[3]
				var z1: float = r[4]
				var c := Vector3((x0 + x1) / 2, FH, (z0 + z1) / 2)
				# stand in the corner by the door side, look across the room
				var corner := Vector3(x1 - 0.45, FH + 0.02, z1 - 0.45) if r[0] != "kitchen" else Vector3(x1 - 0.45, FH + 0.02, z1 - 0.45)
				if r[0] == "bedroom":
					corner = Vector3(x0 + 0.45, FH + 0.02, z1 - 0.45)
				var pos: Vector3 = xf * corner
				var at: Vector3 = xf * (c + Vector3(0, 0.9, 0))
				w.local_player.teleport(pos)
				await _frames(3)
				await _view("h4_%s_%s" % [id, r[0]], pos, at, 10)
			# the front door from the porch
			await _view("h4_%s_zfront" % id, h.entry + h.front * 4.0, h.entry + Vector3(0, 1.4, 0) - h.front * 2.0)


## Draw calls from a few spots, and what each part of the world costs there.
func _perf() -> void:
	var r2: Vector3 = hood.r2
	var spots := [["hood_west", Vector3(r2.x + 130.0, 0.25, r2.z + 68.5), Vector3(r2.x + 10.0, 2.0, r2.z + 70.0)],
		["highway", hood.hw.point(480.0, -19.0, 0.0), hood.hw.point(430.0, 0.0, 0.5)],
		["hood_east", Vector3(r2.x + 18.0, 0.25, r2.z + 1.5), Vector3(r2.x + 120.0, 2.0, r2.z)],
		["street_east", Vector3(20, 0.25, 238.0), Vector3(120, 3.0, 250.0)],
		["street_west", Vector3(20, 0.25, 238.0), Vector3(-80, 3.0, 240.0)],
		["office", Vector3(0, 0.1, 9), Vector3(0, 1.6, 0)]]
	var parts := {"hood_far": hood.g_far, "hood_mid": hood.g_mid, "hood_road": hood.g_road, "hood_dyn": hood.g_dyn,
		"traffic": hood.traffic}
	for sp in spots:
		_look(sp[1], sp[2])
		await _frames(8)
		await RenderingServer.frame_post_draw
		var total := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		var line := "perf %s: %d draws" % [sp[0], total]
		for k in parts:
			var n: Node3D = parts[k]
			n.visible = false
			await _frames(3)
			await RenderingServer.frame_post_draw
			var without := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
			line += "  %s %d" % [k, total - without]
			n.visible = true
		print(line)
