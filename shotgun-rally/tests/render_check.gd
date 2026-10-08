extends SceneTree
## The look's code (scripts/render/), headless (no pictures: those need a screen):
##   * every graphics level has every setting, the draw distance grows with the level
##   * the material library hands out a material for every surface, every mood has its
##     sky, sun and environment, and the skies' and textures' files are there
##   * the lamp finder: lamp names in, look-alikes out; front / back / both / neither by place
##   * the card trees: each kind builds, a sensible size and triangle count
##   * smooth normals: averaged on rolling ground, kept across a sharp fold
##   * a stage builds with all of it (its sky, its sun with shadows, its road's material)
## Run: godot --headless --path . -s tests/render_check.gd   (prints [render] lines; exit 1 on a FAIL)

const Graphics = preload("res://scripts/render/graphics.gd")
const WorldMaterials = preload("res://scripts/render/world_materials.gd")
const CarLook = preload("res://scripts/render/car_look.gd")
const Foliage = preload("res://scripts/render/foliage.gd")
const MeshBuf = preload("res://scripts/stage/mesh_buf.gd")

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
	var yes := ["Taillight", "BrakeLight", "HeadlightGlass", "red_glass", "LEds", "Rear lights", "m8f92_headlight", "HGLOW"]
	var no := ["Reverselight", "Signal.L", "Details_AT", "glass_Windows", "Brake Disc", "INT_Mat_Steer_Fabric", "paint", "FrontMarkerLight",
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
