extends SceneTree
## The look's code (scripts/render/), headless (no pictures: those need a screen):
##   * every graphics level has every setting, the draw distance grows with the level
##   * the material library hands out a material for every surface, every mood has its
##     sky, sun and environment, and the skies' and textures' files are there
##   * the lamp finder: lamp names in, look-alikes out; front / back / both / neither by place
##   * the card trees: each kind builds, a sensible size and triangle count
##   * smooth normals: averaged on rolling ground, kept across a sharp fold
##   * a stage builds with all of it (its sky, its sun with shadows, its road's material)
##   * the time of day: the sun's arc, smooth changes, night fading in at dusk
##   * the night: street lamps (none by day; lit, a few real lights follow the car, the pool
##     added on Compatibility or where pools overlap, else multiplied on Forward+), a touge lit by the hour alone, the
##     LAKESHORE LOOP's lamp posts and lit windows, a car's lamps (CarLamps: fitted once per
##     body, its glow where the lamps are, hazards), one lamp material over both ends split
## Run: godot --headless --path . -s tests/render_check.gd   (prints [render] lines; exit 1 on a FAIL)

const Graphics = preload("res://scripts/render/graphics.gd")
const WorldMaterials = preload("res://scripts/render/world_materials.gd")
const CarLook = preload("res://scripts/render/car_look.gd")
const Foliage = preload("res://scripts/render/foliage.gd")
const MeshBuf = preload("res://scripts/stage/mesh_buf.gd")
const CarLamps = preload("res://scripts/vehicle/car_lamps.gd")

var fails := 0


func _initialize() -> void:
	_levels()
	_materials()
	_moods()
	_hours()
	_lamps()
	_trees()
	_smooth()
	_stage()
	await process_frame                                   # (the tree live: global transforms)
	_street_lamps()
	await _touge_by_hour()
	_loop_night()
	_car_lamps()
	_split()
	print("[render] %s" % ("RENDER OK" if fails == 0 else "RENDER FAIL (%d)" % fails))
	quit(1 if fails > 0 else 0)


func _check(ok: bool, what: String) -> void:
	print("[render] %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		fails += 1


func _levels() -> void:
	var keys: Array = Graphics.PRESETS.low.keys()
	var all := true
	var view := 0.0
	var growing := true
	for l in Graphics.LEVELS:
		for k in keys:
			all = all and Graphics.PRESETS[l].has(k)
		growing = growing and float(Graphics.PRESETS[l].view) >= view
		view = float(Graphics.PRESETS[l].view)
	_check(all, "every graphics level has all %d settings" % keys.size())
	_check(growing, "the draw distance grows from LOW to ULTRA")
	_check(Graphics.level() in Graphics.LEVELS and not Graphics.textured(), "a level is picked; no textures without a screen")


func _materials() -> void:
	var got := 0
	var names := ["asphalt", "road_paint", "concrete", "grass", "dirt", "gravel", "rock", "snow", "ice", "water", "puddle",
		"steel", "glass_windows", "terrain", "buildings", "foliage", "props"]
	var lib: GDScript = WorldMaterials
	for n in names:
		if lib.call(n) is Material and lib.call(n, {"vertex": "colour", "uv": true}) is Material:
			got += 1
	_check(got == names.size(), "a material for every surface (%d of %d), with and without options" % [got, names.size()])
	var info: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(WorldMaterials.TEX_DIR + "textures.json"))
	var files := true
	for t in ["asphalt", "gravel", "grass", "dirt", "rock", "concrete", "snow"]:
		files = files and info.has(t) and float(info[t].size_m) > 0.5 and ResourceLoader.exists(WorldMaterials.TEX_DIR + t + "_albedo.webp") \
			and ResourceLoader.exists(WorldMaterials.TEX_DIR + t + "_normal.webp")
	_check(files, "the 7 world textures and their sizes are there")
	_check(ResourceLoader.exists(Foliage.ATLAS), "the card trees' twig atlas is there")


func _moods() -> void:
	var ok := true
	for m in ["day", "golden", "overcast", "night"]:
		var env := WorldMaterials.environment(m)
		var sun := WorldMaterials.sun(m)
		ok = ok and env.sky != null and env.sky.sky_material is ShaderMaterial and sun.light_energy > 0.0
		if m != "night":
			ok = ok and ResourceLoader.exists(WorldMaterials.SKY_DIR + m + ".webp")
		sun.free()
	_check(ok, "every mood has its sky (a photo, by day), environment and sun")
	var day_sun := WorldMaterials.sun("day")
	var day_elev := -rad_to_deg(day_sun.rotation.x)
	day_sun.free()
	_check(absf(day_elev - 47.9) < 1.0, "the day sun stands where the sky photo has it (%.1f degrees up)" % day_elev)


## The time of day: the sun's arc, night coming and going smoothly, every hour lit.
func _hours() -> void:
	var rise := WorldMaterials.sun_arc(6.0).x
	var noon := WorldMaterials.sun_arc(13.0).x
	var dusk := WorldMaterials.sun_arc(19.5).x
	var late := WorldMaterials.sun_arc(1.0).x
	_check(absf(rise) < 2.0 and absf(noon - 60.0) < 1.0 and absf(dusk) < 2.0 and late < 0.0,
		"the sun's arc: up at 06:00 (%.1f), %.0f degrees at 13:00, down at 19:30 (%.1f), under at 01:00" % [rise, noon, dusk])
	var smooth := true
	var lit := true
	var prev: Dictionary = WorldMaterials.state("day", 0.0)
	var h := 0.1
	while h < 24.0:
		var s: Dictionary = WorldMaterials.state("day", h)
		smooth = smooth and absf(float(s.exposure) - float(prev.exposure)) < 0.2 and absf(float(s.night) - float(prev.night)) < 0.25 \
			and absf(float(s.sun_energy) - float(prev.sun_energy)) < 1.0
		prev = s
		h += 0.1
	for hr in [0.0, 5.5, 6.3, 7.0, 13.0, 18.5, 19.8, 21.0]:
		var env := WorldMaterials.environment_at(hr)
		var sun := WorldMaterials.sun_at(hr, hr == 13.0)
		lit = lit and env.sky.sky_material is ShaderMaterial and sun.light_energy >= 0.0
		sun.free()
	_check(smooth, "the light changes smoothly through the day (no jumps a tenth of an hour apart)")
	_check(lit, "every hour builds its sky, environment and sun, clear and overcast")
	var n13 := float(WorldMaterials.state("day", 13.0).night)
	var n01 := float(WorldMaterials.state("day", 1.0).night)
	var n_dusk := float(WorldMaterials.state("day", 19.9).night)
	_check(n13 == 0.0 and n01 == 1.0 and n_dusk > 0.0 and n_dusk < 1.0,
		"night: none at 13:00, full at 01:00, fading in at dusk (%.2f at 19:54)" % n_dusk)
	var oc: Dictionary = WorldMaterials.state("overcast", 13.0)
	_check(oc.mood == "overcast" and float(oc.sun_energy) < 1.0, "overcast at 13:00: a dim sun (%.2f)" % float(oc.sun_energy))
	WorldMaterials.night_amount = 0.0


func _lamps() -> void:
	var m := StandardMaterial3D.new()
	var yes := ["Taillight", "BrakeLight", "HeadlightGlass", "red_glass", "LEds", "Rear lights", "m8f92_headlight", "HGLOW", "Led_Strip", "front LED"]
	var no := ["Reverselight", "Signal.L", "Details_AT", "glass_Windows", "Brake Disc", "INT_Mat_Steer_Fabric", "paint", "FrontMarkerLight",
		"BMW_M5SedanRewardRecycled_2024Grille1A_Material", "untitled:phong1",
		"TurningLights", "speed_meter", "Orange Refractor"]
	var bad: Array = []
	for n in yes:
		if not CarLook._lamp_candidate(n.to_lower(), m):
			bad.append(n)
	for n in no:
		if CarLook._lamp_candidate(n.to_lower(), m):
			bad.append(n)
	_check(bad.is_empty(), "the lamp finder takes lamps and leaves look-alikes %s" % ("" if bad.is_empty() else str(bad)))
	var look: Node3D = CarLook.new()
	look._box = AABB(Vector3(-0.9, 0.1, -2.2), Vector3(1.8, 1.2, 4.4))
	var kinds := [look._lamp_kind(AABB(Vector3(0.5, 0.6, -2.15), Vector3(0.3, 0.15, 0.3)), m),
		look._lamp_kind(AABB(Vector3(0.5, 0.8, 1.9), Vector3(0.3, 0.1, 0.25)), m),
		look._lamp_kind(AABB(Vector3(-0.8, 0.6, -2.1), Vector3(1.6, 0.3, 4.2)), m),
		look._lamp_kind(AABB(Vector3(0.4, 0.9, -0.2), Vector3(0.2, 0.1, 0.2)), m)]
	look.free()
	_check(kinds == ["head", "tail", "both", ""], "a lamp's place on the car: %s" % str(kinds))


func _trees() -> void:
	var ok := true
	var tris: Array = []
	for k in ["pine", "cedar", "round", "birch"]:
		var mesh := Foliage.tree_mesh(k)
		var n := mesh.surface_get_array_len(0) / 3
		var box := mesh.get_aabb()
		tris.append(n)
		ok = ok and n > 120 and n < 900 and box.size.y > 6.0 and box.size.y < 14.0 and box.size.x < 7.0
	_check(ok, "the card trees build (triangles %s)" % str(tris))


func _smooth() -> void:
	var mb := MeshBuf.new()
	var h := func(x: float) -> float: return 0.3 * sin(x * 0.5)
	for i in 6:
		var x0 := float(i)
		var x1 := x0 + 1.0
		mb.quad(Vector3(x0, h.call(x0), 0), Vector3(x1, h.call(x1), 0), Vector3(x1, h.call(x1), 1), Vector3(x0, h.call(x0), 1), Color.GREEN)
	mb.quad(Vector3(6, h.call(6.0), 0), Vector3(6, h.call(6.0) + 1.0, 0), Vector3(6, h.call(6.0) + 1.0, 1), Vector3(6, h.call(6.0), 1), Color.GRAY)
	var n := mb.smooth_normals()
	var same := 0
	for i in mb.verts.size():
		if mb.verts[i].x > 0.5 and mb.verts[i].x < 5.5 and n[i].dot(mb.norms[i]) < 0.9999:
			same += 1
	var wall_kept := true
	for i in range(mb.verts.size() - 6, mb.verts.size()):
		wall_kept = wall_kept and n[i].dot(mb.norms[i]) > 0.999
	_check(same > 10 and wall_kept, "smooth normals: blended on the slope (%d corners), the wall's fold kept" % same)


func _stage() -> void:
	var StageGen = load("res://scripts/stage/stage_gen.gd")
	var StageBuilder = load("res://scripts/stage/stage_builder.gd")
	var st = StageGen.new()
	st.generate(12, 700.0)
	var b = StageBuilder.new()
	b.mood = "golden"
	root.add_child(b)
	b.build(st)
	var we := b.get_node_or_null("WorldEnvironment") as WorldEnvironment
	var sun := b.get_node_or_null("Sun") as DirectionalLight3D
	var road := b.get_node_or_null("Road") as MeshInstance3D
	if road == null:
		road = b.get_node_or_null("Road_asphalt") as MeshInstance3D
	_check(we != null and we.environment.sky != null and sun != null and sun.shadow_enabled and road != null and road.material_override != null,
		"a stage builds with its sky, its sun's shadows and its road's material")
	b.queue_free()


## Street lamps: nothing by day; at night a StreetLamps with every lamp, its few real
## lights on round the car under one (and off away from them); the faked pools added on
## Compatibility (and here, headless), multiplied on Forward+.
func _street_lamps() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	var lamps: Array = []
	for k in 12:
		lamps.append({"head": Vector3(3.0, 8.0, -k * 40.0), "ground": Vector3(1.0, 0.0, -k * 40.0), "s": k * 40.0})
	WorldMaterials.night_amount = 0.0
	var day = WorldMaterials.street_lights(holder, lamps)
	WorldMaterials.night_amount = 1.0
	var sl = WorldMaterials.street_lights(holder, lamps)
	var car := Node3D.new()
	holder.add_child(car)
	car.position = Vector3(1.0, 0.5, -80.0)
	sl.target = car
	sl._process(0.25)
	var on: Array = sl._lights.filter(func(o): return o.visible and o.light_energy > 0.5)
	car.position = Vector3(500.0, 0.5, 500.0)
	sl._t = 0.0
	sl._process(0.25)
	var off: bool = sl._lights.all(func(o): return not o.visible or o.light_energy < 0.05)
	var pool: ShaderMaterial = sl._pools.material_override
	var added := "blend_add" in pool.shader.code
	_check(day == null and sl != null and sl.lamps.size() == 12 and on.size() >= 1 and on.size() <= sl.REAL and off,
		"street lamps: none by day; at night %d lit, %d real lights round the car under one, none far off" % [sl.lamps.size(), on.size()])
	_check(added != Graphics.forward() and (pool.next_pass != null) == Graphics.forward(),
		"street lamps: the pool of light %s on this renderer (%s)" % ["added" if added else "multiplied", RenderingServer.get_current_rendering_method()])
	var dense: Array = []                               # (a highway's: 48 m apart, wide pools that overlap)
	for k in 6:
		for x in [5.0, -5.0]:                           # (an arm over each carriageway)
			dense.append({"head": Vector3(x, 10.7, -k * 48.0), "ground": Vector3(x, 0.0, -k * 48.0), "radius": 25.0})
	var hw = WorldMaterials.street_lights(holder, dense)
	_check(hw.overlapping and "blend_add" in (hw._pools.material_override as ShaderMaterial).shader.code and not sl.overlapping,
		"street lamps: pools that overlap only add (multiplied twice over they'd blow out); apart, they may multiply")
	WorldMaterials.night_amount = 0.5
	var dusk = WorldMaterials.street_lights(holder, lamps)
	_check(dusk != null and is_equal_approx(dusk.lit, 0.5), "street lamps: at dusk lit, at half strength (%.2f)" % dusk.lit)
	WorldMaterials.night_amount = 0.0
	holder.free()


## The time of day alone makes a touge night (its street lamps lit) or day (the posts only).
func _touge_by_hour() -> void:
	var StageGen = load("res://scripts/stage/stage_gen.gd")
	var StageBuilder = load("res://scripts/stage/stage_builder.gd")
	var st = StageGen.new()
	st.opts = {"kind": "touge", "dir": "down"}
	st.generate(7, 1600.0)
	var res := []
	for hour in [23.0, 13.0, 19.9]:
		var b = StageBuilder.new()
		b.mood = "day"
		b.time_of_day = hour
		root.add_child(b)
		b.build(st)
		res.append([b.mood, b.street_lamps != null, WorldMaterials.night_amount])
		b.queue_free()
		await process_frame
	_check(res[0][0] == "night" and res[0][1] and res[1][0] == "day" and not res[1][1] and res[2][1] and res[2][2] < 1.0,
		"a touge by the hour: 23:00 night, its lamps lit; 13:00 day, unlit; 19:54 lit, dimmer (%.2f)" % res[2][2])
	WorldMaterials.night_amount = 0.0


## The LAKESHORE LOOP at night: its lamp posts' heads lit (the viaducts, the bridges, the
## city), the towers' windows lit; by day neither.
func _loop_night() -> void:
	var LoopGen = load("res://scripts/stage/loop_gen.gd")
	var LoopBuilder = load("res://scripts/stage/loop_builder.gd")
	var st = LoopGen.new()
	st.generate(5)
	var res := {}
	for mood in ["night", "day"]:
		var b = LoopBuilder.new()
		b.mood = mood
		root.add_child(b)
		b._prepare(st)
		b._environment()
		b._lamp_posts()
		var towers: ShaderMaterial = b._mat("building")
		res[mood] = [b.lamp_heads.size(), b.street_lamps != null, float(towers.get_shader_parameter("night")), b.get_node_or_null("WorldEnvironment") != null]
		b.free()
	_check(res.night[0] > 100 and res.night[1] and res.night[2] > 0.9 and res.night[3] and res.day[0] == res.night[0] and not res.day[1] and res.day[2] < 0.05,
		"the loop at night: %d lamp heads lit (the viaducts, bridges, city), the towers' windows lit; by day neither" % res.night[0])
	WorldMaterials.night_amount = 0.0


## A car's lamps (CarLamps): fitted once per body (again: the same node; a new body: a new
## one); nothing floats in front of a car whose lamps nobody found (no glow; the beam at the
## body's front); a body whose lamps are only painted on gets a flat glow on each lamp (not a
## ball: laid on it, facing out); the light starts at each side's lamp lens; hazards blink
## (on the glows, or on blinkers of their own on the lamps).
func _car_lamps() -> void:
	var car := Node3D.new()
	root.add_child(car)
	var body := Node3D.new()
	car.add_child(body)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.8, 1.3, 4.4)
	mi.mesh = bm
	mi.position = Vector3(0, 0.75, 0)
	body.add_child(mi)
	var a = CarLamps.fit(car, body, true, true)
	var again = CarLamps.fit(car, body, true, true)
	var none_glow: int = a._glows.size()
	var bare_front: float = a._corners.head[0].z
	var body2 := body.duplicate()                    # (lamps painted on: "lens", each side's box)
	car.add_child(body2)
	body2.set_meta("lamp_boxes", {"lens": true, "head": AABB(Vector3(-0.7, 0.6, -2.2), Vector3(1.4, 0.2, 0.2)),
		"head_l": AABB(Vector3(-0.7, 0.6, -2.2), Vector3(0.3, 0.2, 0.2)), "head_r": AABB(Vector3(0.4, 0.6, -2.2), Vector3(0.3, 0.2, 0.2)),
		"tail": AABB(Vector3(-0.7, 0.8, 2.0), Vector3(1.4, 0.2, 0.2))})
	var b = CarLamps.fit(car, body2, true, true)
	var heads: Array = b._corners.head
	var painted: int = b._glows.size()
	var g0 := b._glows[0][0] as MeshInstance3D
	var flat: bool = (g0.material_override as StandardMaterial3D).billboard_mode == BaseMaterial3D.BILLBOARD_DISABLED \
		and g0.global_transform.basis.z.normalized().dot(Vector3(0, 0, -1)) > 0.99 and absf(g0.global_position.z - (-2.19 - 0.004)) < 0.002
	b.hazards(true)
	b._process(0.1)
	var amber := ((b._glows[0][0] as MeshInstance3D).material_override as StandardMaterial3D).albedo_color.b < 0.3
	b.hazards(false)
	var body3 := body.duplicate()                    # (lamps that glow by their own material: no glow added)
	car.add_child(body3)
	body3.set_meta("lamp_boxes", {"head": AABB(Vector3(-0.7, 0.6, -2.2), Vector3(1.4, 0.2, 0.2)), "tail": AABB(Vector3(-0.7, 0.8, 2.0), Vector3(1.4, 0.2, 0.2))})
	var c = CarLamps.fit(car, body3, true, true)
	var own_glow: int = c._glows.size()
	c.hazards(true)
	c._process(0.1)
	var blink: bool = c._blinkers.size() == 4 and ((c._blinkers[0] as MeshInstance3D).material_override as StandardMaterial3D).albedo_color.b < 0.3
	c.hazards(false)
	_check(again == a and b != a and car.get_node_or_null("CarLamps") == c and none_glow == 0 and is_equal_approx(bare_front, -2.2)
		and painted == 4 and flat and is_equal_approx(heads[0].z, -2.19) and absf(heads[0].y - 0.7) < 0.01
		and absf(heads[0].x + 0.55) < 0.01 and absf(heads[1].x - 0.55) < 0.01 and amber and own_glow == 0 and blink,
		"car lamps: fitted once per body; no lamps found: no glow (%d), the beam at the front (%.2f); painted lamps: a flat glow on each (%d, flat %s), the light at each side's lens (%s); lamps that glow: nothing added (%d); hazards blink (%s, %s)" % [
		none_glow, bare_front, painted, flat, str(heads), own_glow, amber, blink])
	car.free()


## A lamp material over both ends of a car, and one the material names don't give away (a
## parts.json "lamps" hint): split by where the triangles are (the nose, the tail; the hint's
## box), the rest left unlit; each side's lamp found round its main cluster (a third brake
## light up by the roof doesn't drag it off).
func _split() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var quad := func(x0: float, x1: float, y0: float, y1: float, z: float):
		for v in [Vector3(x0, y0, z), Vector3(x1, y0, z), Vector3(x1, y1, z + 0.05), Vector3(x0, y0, z), Vector3(x1, y1, z + 0.05), Vector3(x0, y1, z + 0.05)]:
			st.add_vertex(v)
	for z in [-2.1, 1.9]:                                 # (a lamp each side at each end, one surface)
		quad.call(-0.7, -0.4, 0.6, 0.8, z)
		quad.call(0.4, 0.7, 0.6, 0.8, z)
	quad.call(-0.2, 0.2, 1.25, 1.28, 1.6)                 # (a third brake light, by the roof)
	quad.call(-0.6, 0.6, 0.6, 0.62, 0.0)                  # (a strip of it in the middle of the car)
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.resource_name = "lights"
	mesh.surface_set_material(0, mat)
	var box := AABB(Vector3(-0.9, 0.1, -2.2), Vector3(1.8, 1.4, 4.4))
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	CarLook._split_lamps(mi, Transform3D.IDENTITY, box)
	var kinds: Dictionary = mi.mesh.get_meta("lamp_kinds", {})
	var got := {}
	var surfs := {"head": [], "tail": []}
	for i in kinds:
		got[kinds[i]] = got.get(kinds[i], 0) + 1
		if kinds[i] in ["head", "tail"]:
			surfs[kinds[i]].append([mi.mesh, i, Transform3D.IDENTITY])
	var tails: Array = CarLook._lamp_sides(surfs.tail, 0.0)
	var tail_ok: bool = tails[0].size != Vector3.ZERO and tails[0].end.y < 0.85 and tails[1].position.x > 0.35 and tails[1].end.x < 0.75
	var glass := StandardMaterial3D.new()                # (a hint: the headlamps in the glass)
	glass.resource_name = "glass_Glass"
	var mesh2 := mesh.duplicate() as ArrayMesh
	mesh2.surface_set_material(0, glass)
	var mi2 := MeshInstance3D.new()
	mi2.mesh = mesh2
	CarLook._split_lamps(mi2, Transform3D.IDENTITY, box, [{"kind": "head", "mat": "^glass_Glass$", "box": [-0.8, 0.8, 0.5, 0.9, -2.2, -1.9]}])
	var kinds2: Dictionary = mi2.mesh.get_meta("lamp_kinds", {})
	var hinted: Array = kinds2.values()
	hinted.sort()
	mi.free()
	mi2.free()
	_check(got.get("head", 0) == 1 and got.get("tail", 0) == 1 and got.get("none", 0) == 1 and tail_ok and hinted == ["head", "none"],
		"lamps split by where they are: %s, each side's tail lamp round its cluster (%s), a hint's lamps cut out of the glass (%s)" % [str(got), str(tails), str(hinted)])
