extends Node
## Takes screenshots of the office + UIs. Needs a real display (e.g. xvfb-run):
##   xvfb-run -s "-screen 0 1600x900x24" godot --path . -- --host --autostart --shots=/tmp/shots

var out_dir := ""


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
	var p = world.local_player
	var views := [
		["01_spawn_bullpen", Vector3(0, 0.1, 9), 0.0, -0.05],
		["02_desk_crt", Vector3(-5, 0.1, 4.2), 0.0, -0.35],
		["03_casino", Vector3(14, 0.1, -3), -1.9, -0.1],
		["04_tv_wall", Vector3(12, 0.1, 5.5), -PI / 2, 0.05],
		["05_lounge_tony", Vector3(-12, 0.1, 5), 0.9, -0.1],
		["06_west_wall", Vector3(-14, 0.1, -4), 1.3, 0.05],
		["07_windows", Vector3(3, 0.1, -6), 0.3, 0.12],
		["16_streamer_corner", Vector3(11.5, 0.1, 6.5), -2.45, 0.02],
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
	world._say("TJZ", "OH MY GOD, TRADE! LONG BTC RIGHT NOW!", 30.0)
	world._say("KIMCHEE", "APING MY WHOLE BAG INTO $WAGMI. NFA", 30.0)
	for v in views:
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
	world._say("TJZ", "OH MY GOD, TRADE! LONG BTC RIGHT NOW!", 30.0)
	world._say("KIMCHEE", "APING MY WHOLE BAG INTO $WAGMI. NFA", 30.0)
	for v in [["q1_streamers", Vector3(12.5, 0.1, 7.5), -2.3, 0.0], ["q2_teammates", Vector3(2.0, 0.1, 8.6), 0.0, -0.1],
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
