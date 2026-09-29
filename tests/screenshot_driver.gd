extends Node
## Takes screenshots of the office + UIs. Needs a real display (e.g. xvfb-run):
##   xvfb-run -s "-screen 0 1600x900x24" godot --path . -- --host --autostart --shots=/tmp/shots

const Rules = preload("res://scripts/sim/rules.gd")

var out_dir := ""
var _fakes: Array = []


func _ready() -> void:
	out_dir = Config.cli.get("shots", "user://shots")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [out_dir, name])
	print("shot: %s  (draws %d, prims %d)" % [name,
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _run() -> void:
	if not Config.cli.has("host"):
		await _frames(30)
		await _snap("00_menu")
		var gp = Graphics.popup(null, get_node("/root/Main/Menu"))
		await _frames(5)
		await _snap("00b_menu_graphics")
		gp.queue_free()
		get_node("/root/Main/Menu")._open_saves()
		await _frames(5)
		await _snap("00c_menu_saves")
		if Config.cli.has("tailor"):
			var menu = get_node("/root/Main/Menu")
			menu._open_tailor()
			await _frames(40)
			await _snap("20_tailor")
			var t = menu.get_child(menu.get_child_count() - 1)
			var looks := [
				{"outfit": "suit", "suit": Color(0.33, 0.32, 0.36), "hair_style": "swept", "hair": Color(0.3, 0.18, 0.12), "glasses": "shades", "watch": "gold"},
				{"outfit": "hoodie", "suit": Color(0.8, 0.55, 0.1), "hair_style": "afro", "hair": Color(0.06, 0.05, 0.05), "skin": Color(0.38, 0.25, 0.17), "shoe_style": "sneaker", "shoes": Color(0.9, 0.9, 0.9), "chain": true},
				{"outfit": "suit", "suit": Color(0.4, 0.1, 0.12), "tie": Color(0.9, 0.7, 0.1), "hair_style": "long", "hair": Color(0.86, 0.66, 0.14), "beard": "full", "hat": "cap", "hat_color": Color(0.15, 0.3, 0.75)},
			]
			for k in looks.size():
				t.look = load("res://scripts/art/character.gd").full_look(looks[k])
				t._refresh()
				await _frames(30)
				await _snap("21_tailor_%d" % k)
		Sfx.quit_game()
		return
	while get_node_or_null("/root/Main/World/Match") == null:
		await get_tree().process_frame
	var world = get_node("/root/Main/World")
	var m = world.match_node
	var hud = world.hud
	await get_tree().create_timer(12.0).timeout   # let the first headline air
	if Config.cli.has("quick"):
		await _quick(world, m, hud)
		return
	if Config.cli.has("streetonly"):
		await _street_only(world, m, hud)
		Sfx.quit_game()
		return
	if Config.cli.has("handtest"):              # which way does a prop sit in the right hand?
		var rots := [Vector3(0, PI / 2, 0), Vector3(-PI / 2, 0, 0), Vector3(-PI / 2, PI / 2, 0), Vector3(0, 0, PI / 2),
			Vector3(PI / 2, 0, PI / 2), Vector3(0, PI / 2, PI / 2)]
		m.wallet[1] = 150_000.0
		m._push_state()
		var dudes := []
		for k in rots.size():
			var d = load("res://scripts/player/player.gd").new()
			d.setup(900 + k, "R%d" % k, load("res://scripts/art/character.gd").player_look(1), false, world)
			world.players_node.add_child(d)
			d.teleport(Vector3(-2.5 + k * 1.0, 0.1, 4.0))
			d.rotation.y = PI
			d.name_tag.text = "%d" % k
			dudes.append(d)
		await _frames(5)
		for k in rots.size():
			var st = load("res://scripts/art/cash_art.gd").fan() if Config.cli.has("fan") else load("res://scripts/art/cash_art.gd").hand_stack(80_000.0)
			st.rotation = rots[k]
			dudes[k].model.prop_right.add_child(st)
			dudes[k].model.pose = "fan" if Config.cli.has("fan") else "flash"
			dudes[k].set_physics_process(false)
		var p1 = world.local_player
		p1.teleport(Vector3(0, 0.1, 6.8))
		p1.rotation.y = 0.0
		await get_tree().create_timer(1.0).timeout
		var cam := Camera3D.new()
		world.add_child(cam)
		cam.fov = 40
		cam.current = true
		for k in rots.size():
			var hand: Vector3 = dudes[k].model.prop_right.global_position
			cam.global_position = hand + Vector3(-0.3, 0.3, 0.7)
			cam.look_at(hand)
			await _frames(4)
			await _snap("hand_rot_%d" % k)
		Sfx.quit_game()
		return
	if Config.cli.has("lotonly"):              # the BEMZE dealership off the highway
		hud.root.visible = false
		var lot: Vector3 = world.builder.hood.hw.dealership_lot
		var cam := Camera3D.new()
		world.add_child(cam)
		cam.current = true
		cam.fov = 70
		world.hood.hood.traffic.force_awake = true
		for v in [["lot_a", Vector3(-45, 9, -30), Vector3(5, 2, 0)], ["lot_b", Vector3(-25, 2.2, 8), Vector3(10, 1, 0)],
				["lot_c", Vector3(4, 1.7, 6), Vector3(18, 0.8, -1)], ["lot_d", Vector3(8, 1.7, -4), Vector3(8, 0.5, 8)]]:
			cam.global_position = lot + v[1]
			cam.look_at(lot + v[2])
			await get_tree().create_timer(1.2).timeout
			await _snap(v[0])
		Sfx.quit_game()
		return
	if Config.cli.has("dealeronly"):           # the BEMZE showroom menu
		m.ledger.get_acct(0).balance = 150_000.0
		m.owned[1]["bz_m2"] = 1
		m.owned[1]["paint_bz_m2"] = 6
		m._push_state()
		hud.open_interact({"type": "dealer", "id": 0})
		hud.dealer.paint["bz_m3"] = 3
		hud.dealer._refresh()
		await _frames(6)
		await _snap("dl_showroom")
		Sfx.quit_game()
		return
	if Config.cli.has("driveonly"):            # get in, drive down the street, chase cam, cockpit, brake lights
		var p0 = world.local_player
		m.owned[1]["bz_m3"] = 1
		m._push_state()
		world.go_to_street()
		await get_tree().create_timer(0.8).timeout
		var car = world.cars[Net.my_id()]
		p0.enter_car(car)
		await _frames(5)
		await _snap("d0_in_car")
		# Input.action_press drives it like the keyboard would
		Input.action_press("move_forward")
		await get_tree().create_timer(2.5).timeout
		Input.action_press("move_right", 0.25)
		await get_tree().create_timer(0.4).timeout
		await _snap("d1_chase_accel")
		Input.action_release("move_right")
		await get_tree().create_timer(0.6).timeout
		print("speed %.0f mph" % car.mph())
		Input.action_release("move_forward")
		Input.action_press("move_back")
		await get_tree().create_timer(0.25).timeout
		await _snap("d2_braking")
		Input.action_release("move_back")
		p0.drive_cam.toggle()
		p0.model.set_first_person(true)
		await get_tree().create_timer(0.5).timeout
		await _snap("d3_cockpit")
		# crash into the parked car ahead of us
		p0.drive_cam.toggle()
		p0.model.set_first_person(false)
		hud.root.visible = false
		Input.action_press("move_forward")
		var hits := []
		car.crashed.connect(func(i): hits.append(i))
		await get_tree().create_timer(3.0).timeout
		Input.action_release("move_forward")
		await _snap("d4_after_driving")
		print("hits %s, speed now %.0f mph" % [str(hits), car.mph()])
		Sfx.quit_game()
		return
	if Config.cli.has("counteronly"):          # money counters: the one by the ATM, then your desk's
		var p0 = world.local_player
		m.wallet[1] = 250_000.0
		m.owned[1]["counter"] = 1
		m._push_state()
		hud.root.visible = false
		await get_tree().create_timer(1.0).timeout
		var cc = world.counter_node(1000)
		var cam := Camera3D.new()
		world.add_child(cam)
		cam.fov = 50
		cam.current = true
		var fwd: Vector3 = cc.global_basis.z                # the counter's front
		cam.global_position = cc.global_position + fwd * 0.75 + Vector3(0.25, 0.45, 0) + cc.global_basis.x * 0.1
		cam.look_at(cc.global_position + Vector3(0, 0.1, 0))
		await _snap("k0_counter_idle")
		world._run_counter(1000)
		await get_tree().create_timer(1.3).timeout
		await _snap("k1_counting")
		await get_tree().create_timer(6.5).timeout
		await _snap("k2_counted_250k")
		cam.global_position = cc.global_position + fwd * 2.2 + Vector3(0.8, 0.9, 0)
		cam.look_at(cc.global_position)
		await _snap("k3_counter_by_atm")
		var dc = world.counter_node(world.builder.PLAYER_DESK0)
		if dc:
			m.wallet[1] = 60_000.0
			world._run_counter(world.builder.PLAYER_DESK0)
			var f2: Vector3 = dc.global_basis.z
			cam.global_position = dc.global_position + f2 * 0.8 + Vector3(0, 0.5, 0)
			cam.look_at(dc.global_position + Vector3(0, 0.08, 0))
			await get_tree().create_timer(4.0).timeout
			await _snap("k4_desk_counter_60k")
		else:
			print("no desk counter")
		Sfx.quit_game()
		return
	if Config.cli.has("gunonly"):              # BIG IRON: the store, gun poses, first person, a shot
		var st = world.builder.street
		var guns := ["pistol", "pistol", "deagle", "shotgun", "ak", "ak_gold"]
		var aim := [false, true, true, false, true, true]
		var dudes := []
		for k in guns.size():
			var id: int = 900 + k
			var d = load("res://scripts/player/player.gd").new()
			d.setup(id, "G%d" % k, load("res://scripts/art/character.gd").player_look(k + 1), false, world)
			world.players_node.add_child(d)
			d.teleport(st.P(28.4 + k * 1.0, 0.2, st.WALK + 0.4 + 3.2))
			d.rotation.y = 0.0                       # facing -z: out toward the door
			d.name_tag.visible = false
			m.owned[id] = {guns[k]: 1}
			m.drawn[id] = guns[k]
			d.photo_aim = aim[k]
			dudes.append(d)
		var p0 = world.local_player
		p0.teleport(st.P(30.0 - 3.4, 0.2, st.WALK + 0.4 + 1.2))
		p0.rotation.y = PI                           # facing +z: down the range
		m.owned[1]["pistol"] = 1
		m.owned[1]["ak"] = 1
		m.drawn[1] = "pistol"
		m._push_state()
		hud.root.visible = false
		await get_tree().create_timer(1.5).timeout
		var cam := Camera3D.new()
		world.add_child(cam)
		cam.fov = 55
		cam.current = true
		cam.global_position = dudes[2].global_position + Vector3(0.5, 1.5, -4.2)
		cam.look_at(dudes[2].global_position + Vector3(0.5, 1.1, 0))
		await _frames(4)
		await _snap("g1_lineup")
		for k in guns.size():
			var d = dudes[k]
			cam.global_position = d.global_position + Vector3(0.55, 1.5, -1.6)
			cam.look_at(d.global_position + Vector3(0, 1.25, 0))
			await _frames(4)
			await _snap("g2_pose_%d_%s%s" % [k, guns[k], "_aim" if aim[k] else ""])
		# do the hands cross? (the model faces -z, so its right hand should stay at +x of its left)
		for k in guns.size():
			var d = dudes[k]
			var sk: Skeleton3D = d.model.skel
			var hl: Vector3 = d.model.to_local(sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Hand_L")).origin)
			var hr: Vector3 = d.model.to_local(sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Hand_R")).origin)
			print("hands %s%s: L %s  R %s  gap_x %.3f %s" % [guns[k], "_aim" if aim[k] else "", hl, hr, hr.x - hl.x,
					"CROSSED" if hr.x - hl.x < 0.02 else "ok"])
			cam.global_position = d.global_position + Vector3(0.0, 2.5, -0.55)
			cam.look_at(d.global_position + Vector3(0, 1.2, -0.45), Vector3(0, 0, -1))
			await _frames(3)
			await _snap("g2t_top_%d_%s%s" % [k, guns[k], "_aim" if aim[k] else ""])
		# the store from the door
		cam.global_position = st.P(30.0 + 2.5, 1.7, st.WALK + 0.9)
		cam.look_at(st.P(30.0 - 1.0, 1.2, st.WALK + 0.4 + 6.5))
		cam.fov = 75
		await _frames(4)
		await _snap("g3_store")
		# first person down the range: G19 at the low ready, aimed, a shot
		cam.current = false
		p0.cam.current = true
		p0.pitch = 0.0
		await get_tree().create_timer(0.8).timeout
		await _snap("g4_fp_pistol")
		p0.photo_aim = true
		await get_tree().create_timer(0.8).timeout
		p0._fire(Rules.LUXURY.pistol)
		await _frames(1)
		await _snap("g5_fp_pistol_fire")
		m.drawn[1] = "ak"
		m._push_state()
		p0.photo_aim = false
		await get_tree().create_timer(1.0).timeout
		await _snap("g6a_fp_ak_low")
		p0.photo_aim = true
		await get_tree().create_timer(0.6).timeout
		p0._fire(Rules.LUXURY.ak)
		await _frames(1)
		await _snap("g6_fp_ak_fire")
		await get_tree().create_timer(1.0).timeout
		for n in 12:
			p0._shot_cd = 0.0
			p0._fire(Rules.LUXURY.ak)
			await _frames(3)
		await get_tree().create_timer(0.8).timeout
		cam.current = true
		cam.fov = 45
		var tgt: Vector3 = st.P(30.0 - 4.1, 1.45, st.WALK + 0.4 + 7.4)
		cam.global_position = tgt + Vector3(0.4, 0.1, -1.6)
		cam.look_at(tgt)
		await _frames(3)
		await _snap("g7_target_holes")
		Sfx.quit_game()
		return
	if Config.cli.has("cashonly"):             # ATM, the stack in your hand, the fan, a spread
		var p0 = world.local_player
		m.ledger.get_acct(0).balance = 900_000.0
		m._push_state()
		p0.teleport(world.atms[0].global_position + Vector3(0, 0.1, -1.3))
		p0.rotation.y = 0.0
		p0.pitch = -0.1
		p0.head.rotation.x = -0.1
		hud.open_interact({"type": "atm", "id": 0})
		hud.atm.step = 6
		hud.atm._go(1)
		await get_tree().create_timer(0.35).timeout
		await _snap("c1_atm_withdraw")
		await get_tree().create_timer(1.5).timeout
		hud.close_modals()
		print("cash on hand: %s" % m.cash_of(1))
		# flash it (third person via photo mode so we see ourselves)
		p0.teleport(Vector3(0, 0.1, 6))
		p0.rotation.y = 0.0
		p0.play_emote("flash")
		await _frames(10)
		var pm = hud.photo
		pm.toggle()
		pm.cam.global_position = p0.global_position + Vector3(0.9, 1.55, -1.3)
		pm.cam.look_at(p0.global_position + Vector3(0.15, 1.2, 0))
		pm._yaw = pm.cam.rotation.y
		pm._pitch = pm.cam.rotation.x
		await _frames(10)
		await _snap("c2_flash_250k")
		p0.play_emote("fan")
		await get_tree().create_timer(0.6).timeout
		await _snap("c3_money_fan")
		pm.toggle()
		# lay it out on the floor
		p0.emote = 0
		world.toggle_spread()
		await get_tree().create_timer(0.6).timeout
		p0.teleport(Vector3(0, 0.1, 7.5))
		p0.pitch = -0.75
		p0.head.rotation.x = -0.75
		await _frames(10)
		await _snap("c4_spread_250k")
		m.wallet[1] = 4_500.0
		m._shrink_spread(1)
		m._push_state()
		await _frames(6)
		await _snap("c5_spread_4k")
		Sfx.quit_game()
		return
	if Config.cli.has("photoonly"):            # photo mode: pose, filter, snap
		var pm = hud.photo
		pm.dir_override = out_dir + "/photos"
		for d in 2:                             # a friend in the shot
			var f = load("res://scripts/player/player.gd").new()
			f.setup(900 + d, ["Bob", "Dave"][d], load("res://scripts/art/character.gd").player_look(d + 1), false, world)
			world.players_node.add_child(f)
			f.teleport(world.local_player.global_position + Vector3(-0.9 + d * 1.8, 0, -0.4))
			f.rotation.y = world.local_player.rotation.y
		pm.toggle()
		pm._pose("fistpump")
		await get_tree().create_timer(0.4).timeout
		pm._freeze(true)
		pm._set_filter(2)
		await _frames(10)
		await _snap("ph1_photo_mode_ui")
		var path: String = await pm.snap_photo()
		print("photo saved: %s exists=%s" % [path, FileAccess.file_exists(path)])
		pm._set_filter(1)
		pm.cam.global_position += Vector3(0.8, -0.6, 0.6)
		pm._yaw += 0.3
		await _frames(6)
		var path2: String = await pm.snap_photo()
		print("photo saved: %s exists=%s" % [path2, FileAccess.file_exists(path2)])
		pm.toggle()
		await _frames(4)
		print("photo mode off: fp=%s cam=%s" % [world.local_player.model.fp, world.local_player.cam.current])
		Sfx.quit_game()
		return
	if Config.cli.has("termonly"):             # the trading terminal with the full board
		m.request_open("NVDUH", -1, 5_000.0, 10)
		await get_tree().create_timer(1.0).timeout
		hud.open_interact({"type": "terminal", "id": 0})
		hud.terminal.select("NVDUH")
		await _frames(20)
		await _snap("t1_terminal_short")
		hud.terminal.select("PEAR")
		await _frames(10)
		await _snap("t2_terminal_watchlist")
		Sfx.quit_game()
		return
	if Config.cli.has("progonly"):
		await _progress_shots(world, m, hud)
		Sfx.quit_game()
		return
	if Config.cli.has("elevonly"):
		await _elevator_shots(world)
		Sfx.quit_game()
		return
	if Config.cli.has("fponly"):
		await _fp_shots(world, m, hud)
		Sfx.quit_game()
		return
	var p = world.local_player
	var views := [
		["01_spawn_bullpen", Vector3(0, 0.1, 9), 0.0, -0.05],
		["02_desk_crt", Vector3(-5, 0.1, 4.2), 0.0, -0.35],
		["03_casino", Vector3(14, 0.1, -3), -1.9, -0.1],
		["04_tv_wall", Vector3(12, 0.1, 5.5), -PI / 2, 0.05],
		["05_lounge_tony", Vector3(-12, 0.1, 5), 0.9, -0.1],
		["06_west_wall", Vector3(-14, 0.1, -4), 1.3, 0.05],
		["07_windows", Vector3(3, 0.1, -6), 0.3, 0.12],
		["16_streamer_corner", Vector3(72.5, 0.1, 3.4), 0.55, 0.0],
		["16b_kwik_ad", Vector3(16.5, 0.1, 7.5), PI, 0.1],
		["18_teammates", Vector3(2.0, 0.1, 9.0), 0.0, -0.1],
		["19_tony_close", Vector3(-14.2, 0.1, 6.6), 2.75, -0.05],
		["17_hoop_ball", Vector3(-15.0, 0.1, -9.0), PI / 2 - 0.1, 0.25],
		["20_elevator", Vector3(1.5, 0.1, 8.5), PI - 0.2, 0.08],
		["21_lounge", Vector3(-11.5, 0.1, 8.0), 1.6, -0.2],
		["22_holding_cell", Vector3(-1.5, 0.1, 40.3), PI - 0.55, -0.1],
		["23_skyline", Vector3(8.5, 0.1, -11.5), -0.1, 0.3],
		["24_restroom_door", Vector3(-15.5, 0.1, 4.2), 1.85, 0.0],
		["25_restroom", Vector3(-20.4, 0.1, 2.4), 1.45, -0.15],
	]
	# a fake remote teammate so we can see player models
	for k in 2:
		var d = load("res://scripts/player/player.gd").new()
		d.setup(900 + k, ["Bob", "Dave"][k], load("res://scripts/art/character.gd").player_look(k + 1), false, world)
		world.players_node.add_child(d)
		d.teleport(Vector3(1.2 + k * 1.3, 0.1, 5.5 - k * 0.6))
		d.rotation.y = PI + 0.3
	_fakes = []
	for c in world.players_node.get_children():
		if int(str(c.name)) >= 900:
			_fakes.append(c)
	world._say("TJZ", "OH MY GOD, TRADE! LONG BTC RIGHT NOW!", 30.0)
	world._say("KIMCHEE", "APING MY WHOLE BAG INTO $WAGMI. NFA", 30.0)
	# emotes + chairs on the two fake teammates (as if they came over the network)
	views.append(["34_emotes", Vector3(-6.8, 0.1, 6.2), 0.25, -0.05])
	for v in views:
		if v[0] == "34_emotes":
			var ch: Dictionary = world.builder.chairs[world.builder.chairs.keys()[19]]
			_fakes[0].net_tf(Vector3(-7.6, 0.1, 3.9), PI + 0.4, 0.0, 1 << 3)            # the finger
			_fakes[1].net_tf(ch.pos + Vector3(0, 0.1, 0), ch.rot + PI, 0.0, (3 << 3) | ((world.builder.chairs.keys()[19] + 1) << 6))
			await get_tree().create_timer(0.8).timeout
		p.teleport(v[1])
		p.rotation.y = v[2]
		p.pitch = v[3]
		p.head.rotation.x = v[3]
		await _frames(10)
		await _snap(v[0])
	# Terminal with a live position
	m.request_open("BTC", 1, 25_000.0, 100)
	m.request_open("BTC", -1, 5_000.0, 25)
	await get_tree().create_timer(3.0).timeout
	await get_tree().process_frame
	for pos in m.my_acct().get("positions", []):
		if pos.side > 0:
			var mv: float = pos.margin / pos.units
			m.request_set_tpsl(pos.pid, pos.entry + mv * 0.4, pos.entry - mv * 0.3)
	await get_tree().create_timer(0.3).timeout
	hud.open_interact({"type": "terminal", "id": 0})
	await _frames(10)
	await _snap("08_terminal")
	m.request_close_all()
	await get_tree().create_timer(0.4).timeout
	await _snap("09_trade_closed_popup")
	hud.close_modals()
	hud.open_interact({"type": "slots", "id": 0})
	hud.slots.spin()
	await get_tree().create_timer(2.2).timeout
	await _snap("10_slots")
	hud.close_modals()
	# the machine itself after a big win: marquee amount + coin burst
	p.teleport(Vector3(17.2, 0.1, -10.6))
	p.rotation.y = -PI / 2 - 0.35
	p.pitch = 0.1
	p.head.rotation.x = 0.1
	await _frames(5)
	world._on_slot_result(Net.my_id(), [4, 4, 4], 3750.0, 300.0)
	await get_tree().create_timer(0.35).timeout
	await _snap("10b_slot_jackpot")
	hud.open_interact({"type": "shop", "id": 0})
	await _frames(5)
	await _snap("11_shop")
	hud.close_modals()
	m.request_buy("cigar")
	m.request_buy("moneygun")
	await get_tree().create_timer(0.5).timeout
	m.request_use("cigar")
	await get_tree().create_timer(1.5).timeout
	await _snap("12_hud_items")
	# flex: the shop, the unboxing, then the trophies on your desk
	p.teleport(Vector3(-10.0, 0.1, 10.6))
	p.rotation.y = PI
	p.pitch = -0.1
	p.head.rotation.x = -0.1
	await _frames(5)
	await _snap("26_flex_counter")
	hud.open_interact({"type": "luxury", "id": 0})
	await _frames(5)
	await _snap("27_flex_shop")
	hud.close_modals()
	m.careers[Net.my_id()]["xp"] = 500.0   # DEGEN: everything unlocked for the shots
	m._push_state()
	m.request_buy_lux("roflex")
	await get_tree().create_timer(1.6).timeout
	await _snap("28_roflex_unbox")
	for k in ["louie", "louie", "counter", "supreme", "supreme", "supreme"]:
		m.request_buy_lux(k)
	await get_tree().create_timer(2.2).timeout
	var dp: Vector3 = world.builder.desks[world.desk_of(Net.my_id())]
	p.teleport(dp + Vector3(0.9, 0.1, 2.3))
	p.rotation.y = 0.35
	p.pitch = -0.38
	p.head.rotation.x = -0.38
	await _frames(8)
	await _snap("29_flex_desk")
	world._run_counter(world.desk_of(Net.my_id()))
	await get_tree().create_timer(1.2).timeout
	await _snap("29b_money_counter")
	await get_tree().create_timer(1.8).timeout
	# blood pressure: redline it, then go to the restroom
	m.pressure[Net.my_id()] = 93.0
	p.teleport(Vector3(-14.0, 0.1, 2.2))
	p.rotation.y = PI / 2
	p.pitch = 0.0
	p.head.rotation.x = 0.0
	await get_tree().create_timer(1.2).timeout
	await _snap("30_blood_pressure")
	p.teleport(world.builder.toilet_pos + Vector3(1.1, 0.1, 0.4))
	await get_tree().create_timer(0.3).timeout
	m.request_relieve()
	await get_tree().create_timer(1.4).timeout
	await _snap("31_relief")
	await get_tree().create_timer(3.0).timeout
	# the phone feed with a Tramp post dropping before the TV has it
	p.teleport(Vector3(0, 0.1, 6))
	p.rotation.y = 0.0
	hud.phone.toggle()
	m._s_post({"speaker": "TRAMP", "role": "PRESIDENT", "headline": "TRAMP: WE ARE IN WAR", "day": 1})
	await get_tree().create_timer(0.8).timeout
	await _snap("32_phone_feed")
	hud.phone.toggle()
	await get_tree().create_timer(2.5).timeout
	await _snap("33_phone_kwik")
	hud.phone.toggle()
	# the street outside: elevator down, then a tour of the block and the stores
	var so: Vector3 = world.builder.street.ORIGIN
	world.go_to_street()
	await get_tree().create_timer(0.8).timeout
	for v in [["40_street_arrival", Vector3(-6, 0.25, -6.5), PI + 0.35, 0.05],
			["41_street_east", Vector3(-20, 0.25, 7.0), -PI / 2 + 0.25, 0.05],
			["42_street_west", Vector3(20, 0.25, -7.0), PI / 2 + 0.2, 0.08],
			["43_boutiques", Vector3(-24, 0.25, -3.0), PI - 0.1, 0.12],
			["44_guccero_inside", Vector3(-30, 0.25, -10.0), 0.0, 0.0],
			["45_crownwell_inside", Vector3(18, 0.25, -10.0), 0.0, 0.0],
			["46_tailor_inside", Vector3(-6, 0.25, 10.0), PI, 0.0],
			["47_casino_inside", Vector3(6, 0.25, 10.0), PI, 0.05],
			["48_hotdog", Vector3(2.0, 0.25, -3.2), PI, -0.05],
			["49_lobby", Vector3(-6, 0.25, -10.0), 0.0, 0.05]]:
		p.teleport(so + v[1])
		p.rotation.y = v[2]
		p.pitch = v[3]
		p.head.rotation.x = v[3]
		await _frames(8)
		await _snap(v[0])
	hud.open_interact({"type": "lux", "id": 0})
	await _frames(5)
	await _snap("50_guccero_shop")
	hud.close_modals()
	hud.open_interact({"type": "pawn", "id": 0})
	await _frames(5)
	await _snap("51_pawn_shop")
	hud.close_modals()
	world.leave_street()
	await _frames(5)
	hud._on_rank_up(Net.my_id(), 3)
	await get_tree().create_timer(0.4).timeout
	await _snap("35_rank_up")
	hud.mugshot.play(4298, "Trader", world.local_player.look)
	await get_tree().create_timer(1.0).timeout
	await _snap("13_mugshot")
	hud.mugshot.visible = false
	hud.summary.show_summary({"day": 1, "quota": 150000.0, "mode": "coop", "balance": 187000.0, "passed": true,
		"next_quota": 225000.0, "over": false, "players": {1: {"name": "Trader", "stats": m.stats.get(1, {})}}})
	await _frames(5)
	await _snap("14_summary")
	hud.summary.visible = false
	# Cops raid on ourselves
	p.teleport(Vector3(-3, 0.1, -12))
	p.rotation.y = PI
	p.pitch = -0.05
	p.head.rotation.x = -0.05
	m._add_heat(1, 200.0)
	await get_tree().create_timer(2.2).timeout
	await _snap("15_cops_raid")
	Sfx.quit_game()


## Only the character views (faster iteration).
func _quick(world, m, hud) -> void:
	var p = world.local_player
	for k in 2:
		var d = load("res://scripts/player/player.gd").new()
		d.setup(900 + k, ["Bob", "Dave"][k], load("res://scripts/art/character.gd").player_look(k + 1), false, world)
		world.players_node.add_child(d)
		d.teleport(Vector3(1.2 + k * 1.3, 0.1, 5.5 - k * 0.6))
		d.rotation.y = PI + 0.3
	_fakes = []
	for c in world.players_node.get_children():
		if int(str(c.name)) >= 900:
			_fakes.append(c)
	world._say("TJZ", "OH MY GOD, TRADE! LONG BTC RIGHT NOW!", 30.0)
	world._say("KIMCHEE", "APING MY WHOLE BAG INTO $WAGMI. NFA", 30.0)
	for v in [["q1_streamers", Vector3(72.5, 0.1, 3.4), 0.55, 0.0], ["q2_teammates", Vector3(2.0, 0.1, 8.6), 0.0, -0.1],
			["q3_tony", Vector3(-14.2, 0.1, 6.6), 2.75, -0.05], ["q4_crammer", Vector3(15.5, 0.1, 1.6), -PI / 2, 0.0]]:
		p.teleport(v[1])
		p.rotation.y = v[2]
		p.pitch = v[3]
		p.head.rotation.x = v[3]
		await _frames(10)
		await _snap(v[0])
		print("draw calls %s: %d  objects: %d" % [v[0], Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)])
	m.request_buy("cigar")
	await get_tree().create_timer(0.3).timeout
	m.request_use("cigar")
	p.teleport(Vector3(0, 0.1, 6))
	p.rotation.y = 0.0
	p.pitch = 0.0
	p.head.rotation.x = 0.0
	await get_tree().create_timer(0.8).timeout
	await _snap("q5_fp_cigar")
	p.teleport(Vector3(-3, 0.1, -12))
	p.rotation.y = PI
	m._add_heat(1, 200.0)
	await get_tree().create_timer(2.4).timeout
	await _snap("q6_cops")
	world._on_news({})
	var tv = world.tv
	for e in [{"speaker": "TRAMP", "role": "PRESIDENT", "headline": "TRAMP: YOU'LL BE TIRED OF WINNING"},
			{"speaker": "TJZ", "role": "STREAMER", "headline": "TJZ (LIVE): OH MY GOD, TRADE! LONG BTC RIGHT NOW!"}]:
		tv._on_news(e)
		await _frames(15)
		await RenderingServer.frame_post_draw
		tv.vp.get_texture().get_image().save_png("%s/q7_tv_%s.png" % [out_dir, e.role])
	hud.mugshot.play(4298, "Trader", world.local_player.look)
	await get_tree().create_timer(1.0).timeout
	await _snap("q8_mugshot_front")
	await get_tree().create_timer(2.0).timeout
	await _snap("q9_mugshot_side")
	Sfx.quit_game()


## First-person body (Content Warning style): what you see of yourself.
## Progression: the day-event banner, Tony's contracts, the circuit breaker,
## the office upgrades counter, the after-hours forecast, a fully kitted desk.
func _progress_shots(world, m, hud) -> void:
	const DayEvents = preload("res://scripts/sim/day_events.gd")
	var p = world.local_player
	p.teleport(Vector3(0, 0.1, 6))
	p.rotation.y = 0.0
	m._set_day_event("fed_day")
	m._sched = DayEvents.schedule("fed_day", m.rng, m._day_len)
	m._update_event_at()
	m.contracts.clear()
	m._deal_contracts(1)
	_mark_done(m.contracts[1][0])
	m._push_state()
	hud._show_event_banner()
	await _frames(20)
	await _snap("p1_event_banner")
	hud._event_t = 0.0
	await _frames(10)
	await _snap("p2_contracts_fed_countdown")
	m.halt = 14.0
	await _frames(6)
	await _snap("p3_circuit_breaker")
	m.halt = 0.0
	m._set_day_event("black_friday")
	m.ledger.get_acct(0).balance = 180_000.0
	m._push_state()
	hud.open_interact({"type": "luxury"})
	await _frames(10)
	await _snap("p4_office_upgrades")
	hud.close_modals()
	var s: Dictionary = {"day": 2, "quota": 56_250.0, "mode": "coop", "players": {1: {"name": "Trader",
		"stats": {"pnl_day": 18_400.0, "trades": 9, "arrests": 0, "biggest": 9_100.0}}}, "overhead": 5_400.0,
		"balance": 71_000.0, "passed": true, "next_quota": 84_375.0, "over": false, "event": "flash_crash",
		"contracts": m.contracts.duplicate(true), "tomorrow": "black_friday",
		"xp": {1: {"gain": 57.0, "xp": 212.0, "rank": 2, "ranked_up": false}}, "saved": {"slot": "x", "cloud": false}}
	hud.summary.show_summary(s)
	await _frames(10)
	await _snap("p5_summary_forecast")
	hud.summary.visible = false
	# a kitted-out desk: every upgrade + two championship trophies
	var own: Dictionary = m.owned[1]
	for k in ["up_bloomberg", "up_scanner", "up_rolodex", "up_intern", "up_prime", "up_standing"]:
		own[k] = 1
	own["champ"] = 2
	own["roflex"] = 1
	m._push_state()
	var desk: int = world.desk_of(1)
	var dp: Vector3 = world.builder.desks[desk]
	p.teleport(dp + Vector3(0.5, 0.1, 1.7))
	p.rotation.y = 0.15
	p.pitch = -0.5
	p.head.rotation.x = -0.5
	await _frames(20)
	await _snap("p6_desk_upgrades")


func _mark_done(c: Dictionary) -> void:
	c.done = true
	c.prog = c.goal


## Elevator arrival: from inside the car (doors shut, then open), and a friend
## riding up seen from the floor.
func _elevator_shots(world) -> void:
	var p = world.local_player
	p.teleport(world.CAR_POS)
	p.rotation.y = 0.0
	p.begin_arrival()
	await _frames(2)
	await _snap("e1_in_car")                       # doors still shut
	world._p_arrive(Net.my_id())
	await get_tree().create_timer(0.9).timeout
	await _snap("e2_doors_open")
	await get_tree().create_timer(2.4).timeout
	await _snap("e3_walked_out")
	# a friend rides up while we watch from the floor
	var d = load("res://scripts/player/player.gd").new()
	d.setup(901, "Bob", load("res://scripts/art/character.gd").player_look(1), false, world)
	world.players_node.add_child(d)
	d.teleport(world.CAR_POS)
	await get_tree().create_timer(3.0).timeout   # doors shut again
	p.teleport(Vector3(0.6, 0.1, 9.0))
	p.rotation.y = PI
	world._p_arrive(901)
	await get_tree().create_timer(1.1).timeout
	await _snap("e4_friend_doors_open")
	for t in 12:
		d.net_tf(d.global_position + Vector3(0, 0, -0.25), 0.0, 0.0, 0)
		await get_tree().create_timer(0.1).timeout
	await _snap("e5_friend_walks_out")


func _fp_shots(world, m, hud) -> void:
	var p = world.local_player
	m.careers[Net.my_id()]["xp"] = 500.0
	m.ledger.adjust(m.acct_for(Net.my_id()), 50000.0)
	m._push_state()
	var at := Vector3(0, 0.1, 6.5)
	var aim := func(yaw: float, pitch: float) -> void:
		p.rotation.y = yaw
		p.pitch = pitch
		p.head.rotation.x = pitch
	p.teleport(at)
	aim.call(0.0, 0.0)
	await get_tree().create_timer(0.6).timeout
	await _snap("fp_01_ahead")
	aim.call(0.0, -1.1)
	await get_tree().create_timer(0.4).timeout
	await _snap("fp_02_look_down")
	aim.call(0.0, -0.45)
	for e in ["finger", "fistpump", "watch", "point"]:
		p.emote = p.EMOTES.find(e)
		p._emote_t = 3.0
		await get_tree().create_timer(0.6).timeout
		await _snap("fp_03_" + e)
	p.emote = 0
	await get_tree().create_timer(0.4).timeout
	m.request_buy("cigar")
	await get_tree().create_timer(0.3).timeout
	m.request_use("cigar")
	await get_tree().create_timer(0.35).timeout
	await _snap("fp_04_zippo")
	await get_tree().create_timer(2.5).timeout
	await _snap("fp_05_cigar")
	m.request_buy("moneygun")
	await get_tree().create_timer(0.3).timeout
	m.request_use("moneygun")
	await get_tree().create_timer(0.8).timeout
	await _snap("fp_06_money_gun")
	# the emote wheel (hold B)
	hud.emote_wheel._show(true)
	await get_tree().create_timer(1.2).timeout
	await _snap("fp_09_emote_wheel")
	hud.emote_wheel.sel = 2
	hud.emote_wheel._refresh()
	await get_tree().create_timer(0.6).timeout
	await _snap("fp_09_emote_wheel_b")
	hud.emote_wheel._show(false)
	# the dance, from inside it
	p.emote = p.EMOTES.find("dance")
	p._emote_t = 30.0
	aim.call(0.0, -0.35)
	for t in [1.2, 2.0, 4.8, 5.6]:
		p.model.anim_hold = t
		await get_tree().create_timer(1.0).timeout
		await _snap("fp_07_dance_%.1f" % t)
	p.model.anim_hold = -1.0
	p.emote = 0
	# sitting at a desk
	p.sit(0)
	await get_tree().create_timer(0.8).timeout
	aim.call(p.rotation.y, -0.6)
	await get_tree().create_timer(0.3).timeout
	await _snap("fp_08_sitting")


## Just the street: outside views of the block + inside every store.
func _street_only(world, m, hud) -> void:
	var p = world.local_player
	hud.pause_menu.visible = true
	await _frames(5)
	await _snap("s00_pause_menu")
	hud.pause_menu.visible = false
	var so: Vector3 = world.builder.street.ORIGIN
	world.go_to_street()
	await get_tree().create_timer(0.8).timeout
	var views := [["s01_block_east", Vector3(-28, 0.25, 0.0), -PI / 2 + 0.05, 0.28],
			["s02_block_west", Vector3(28, 0.25, 0.0), PI / 2 - 0.05, 0.28],
			["s03_corner", Vector3(35, 0.25, 7.5), PI * 0.75, 0.3],
			["s04_rooftops", Vector3(0, 0.25, 0), 0.0, 0.9],
			["s05_north_row", Vector3(0, 0.25, 6.5), 0.0, 0.2],
			["s06_south_row", Vector3(0, 0.25, -6.5), PI, 0.2]]
	for st in world.builder.street.NORTH + world.builder.street.SOUTH:
		var side := -1 if world.builder.street.NORTH.has(st) else 1
		views.append(["s1_" + str(st.kind).replace(":", "_"), Vector3(st.x, 0.25, side * 9.8), 0.0 if side < 0 else PI, -0.08])
	var cw: float = 18.0          # Crownwell (north row): close-ups of the cases and the wall
	views.append(["s2_watch_case", Vector3(cw - 2.0, 0.25, -11.2), 0.0, -0.75])
	views.append(["s2_watch_wall", Vector3(cw - 3.0, 0.25, -12.0), PI / 2 + 0.1, -0.1])
	views.append(["s2_watch_counter", Vector3(cw + 0.55, 0.25, -14.0), 0.0, -0.7])
	for v in views:
		p.teleport(so + v[1])
		p.rotation.y = v[2]
		p.pitch = v[3]
		p.head.rotation.x = v[3]
		await _frames(8)
		await _snap(v[0])
