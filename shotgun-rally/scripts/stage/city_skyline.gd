extends RefCounted
## The city's far tier on the LAKESHORE LOOP: the owner's 31-building pack (tools/skyline.py
## made each a light silhouette with no textures: data/environment_assets.json, kind
## "skyline") behind the front rows (LoopBuilder._city: the 22-building pack, to 190 m from
## the road's middle) out to the city's edge, where the drawn towers stood: the skyline is
## real buildings now. Static, one call from LoopBuilder._city:
##
##   CitySkyline.build(builder, towers, tower_cols, real, night, streets) -> int: the buildings placed
##     towers, tower_cols: the drawn towers' transforms and colours (the ones beyond the front
##       rows are taken out of the lists: these stand in for them)
##     real: the front rows ([id, Transform3D, radius]); night: 0 (day) .. 1 (lit windows)
##     streets: the streets' footprints (CityStreets.plan's "foot": none built on them; the
##       far tier's own are added to it)
##
## Each building:
##   * stands on the ground as drawn (the land's own triangles under its footprint): where it's
##     flat to within 0.8 m, its foot 0.1 m under the lowest of it
##   * is in the city (its footprint on the city's grey ground, none in the water), 40 m and
##     more from the road (any part of the loop) and its ramps, clear of every other building
##     and of the streets (STREET m from their pavements)
##   * has its long side to the road, like the front rows (a square one any way round)
## Each stretch of the city (a district: 1 km of road, both sides) is built from a few of the
## designs (2 towers, 3 mid-rises, a low block), mixed: the taller likelier further out and in
## the middle of town, now and then a tower anywhere, gaps between the blocks. Drawn per design
## and district: a MultiMesh of the full silhouettes while the district's middle is within
## NEAR, of the light ones (LOD1, a fifth of the triangles) to MID, of the lightest (LOD2, a
## few hundred triangles) from there out to RANGE (times the graphics level's view distance);
## the low blocks (hidden behind the front rows from the road) start at the light ones. No
## shadows (they're 200 m off and more: past the sun's shadow map).
## Their windows come from a shader (material()). The same buildings every time (their own
## dice: the builder's aren't touched). The node (CitySkyline) keeps what it placed in its meta
## "buildings" ([[id, Transform3D]]) for the tests.

const EnvAssets = preload("res://scripts/stage/env_assets.gd")
const Graphics = preload("res://scripts/render/graphics.gd")

const FROM := 200.0                  # m from the road's middle: the far tier from here (the front rows to 190 m)
const TO := 645.0                    # ... to here (the city: 650 m round its middle)
const DROP_TOWERS := 190.0           # the drawn towers this far off and more give way to it
const ROAD_CLEAR := 40.0             # m: no footprint nearer the road's centreline (or a ramp's) than this
const STREET := 6.0                  # m at least between two footprints
const FLAT := 0.8                    # m: the most the ground may rise and fall under a footprint
const SINK := 0.1                    # m: the foot under the lowest ground there
const DISTRICT := 1000.0             # m of road: a district's stretch
const NEAR := 650.0                  # m (to a district's middle): the full silhouettes this near, the light ones beyond
const MID := 1800.0                  # m: the lightest ones beyond this
const RANGE := 4000.0                # m: drawn this far (x Graphics.view_distance())
const LOW := 40.0                    # m: a design lower than this is a low block (drawn light from the nearest)
const NAME := "CitySkyline"

## Facade colours (sRGB): concrete, sandstone, render, brick, a glass tower's grey-blue and
## green-grey, dark stone.
const WALLS := [Color(0.62, 0.6, 0.56), Color(0.68, 0.62, 0.52), Color(0.74, 0.72, 0.68), Color(0.52, 0.51, 0.49),
	Color(0.6, 0.5, 0.4), Color(0.52, 0.37, 0.3), Color(0.4, 0.44, 0.49), Color(0.66, 0.64, 0.58),
	Color(0.46, 0.43, 0.4), Color(0.32, 0.36, 0.41), Color(0.36, 0.41, 0.4), Color(0.28, 0.28, 0.3)]

static var _shader: Shader = null


static func build(b, towers: Array, tower_cols: Array, real: Array, night: float, streets := {}) -> int:
	var ids: Array = EnvAssets.ids("skyline") if EnvAssets.available() else []
	if ids.is_empty() or "--no_skyline" in OS.get_cmdline_user_args():   # (--no_skyline: the city as it was, for a comparison)
		return 0
	var designs := []                                       # [id, info, [its levels' meshes: full, light, lightest]]
	for id in ids:
		var m: Mesh = EnvAssets.mesh(id)
		if m != null:
			designs.append([id, EnvAssets.info(id), [m, EnvAssets.mesh(id, "LOD1"), EnvAssets.mesh(id, "LOD2")]])
	if designs.is_empty():
		return 0
	var st = b.st
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([st.seed_used, "skyline"])
	var ground := _ground(b)
	var ramps := _ramp_grid(st)
	# what's already standing: the front rows and the drawn towers nearer than DROP_TOWERS
	# (those further out go: the far tier stands in for them)
	var foot: Dictionary = streets if not streets.is_empty() else {}   # 100 m cells -> [footprints] (the streets', CityStreets.plan, to start with)
	for r in real:
		var sz: Array = EnvAssets.info(str(r[0])).get("size", [30.0, 30.0, 30.0])
		_add(foot, _rect(r[1], float(sz[0]), float(sz[2])))
	for k in range(towers.size() - 1, -1, -1):
		var xf: Transform3D = towers[k]
		if b._road_dist(xf.origin.x, xf.origin.z) >= DROP_TOWERS:
			towers.remove_at(k)
			tower_cols.remove_at(k)
		else:
			_add(foot, _rect(Transform3D(xf.basis.orthonormalized(), xf.origin), xf.basis.x.length(), xf.basis.z.length()))
	var tall := designs.filter(func(d): return float(d[1]["size"][1]) >= 80.0)
	var mid := designs.filter(func(d): return float(d[1]["size"][1]) >= LOW and float(d[1]["size"][1]) < 80.0)
	var low := designs.filter(func(d): return float(d[1]["size"][1]) < LOW)
	var groups := {}                                        # "district/id" -> {design, xfs, cols, custom}
	var placed := 0
	var record: Array = []                                  # [[id, Transform3D]] (the node's meta "buildings": the tests')
	for z in st.zones:
		if z.kind != "city":
			continue
		var z0: float = z.s0
		var z1: float = z.s1
		var s := z0 + 30.0
		while s < z1 - 30.0:
			var district := int(s / DISTRICT)
			var palette := _palette(st, district, tall, mid, low)
			var centre := 1.0 - absf((s - z0) / maxf(z1 - z0, 1.0) - 0.5) * 2.0   # (taller in the middle of town)
			for side in [1.0, -1.0]:
				var d := FROM + rng.randf_range(0.0, 30.0)
				while d < TO:
					var far := (d - FROM) / (TO - FROM)
					var want := 22.0 + far * 80.0 * (0.35 + centre) + rng.randf_range(-20.0, 45.0)
					if d > 300.0 and rng.randf() < 0.12:
						want = 140.0                                                    # (now and then a tower anywhere)
					var dz: Array = _pick(palette, want, rng)
					var sz: Array = dz[1]["size"]
					var along: bool = float(sz[0]) >= float(sz[2])                     # (its x the longer: along the road)
					var across: float = float(sz[2]) if along else float(sz[0])
					var mid_d: float = d + across * 0.5
					d += across + STREET + rng.randf_range(16.0, 45.0)
					var p: Vector3 = st.world_at(s + rng.randf_range(-8.0, 8.0), mid_d * side)
					var turn := (PI * 0.5 if along else 0.0) + PI * float(rng.randi() % 2)
					if maxf(float(sz[0]), float(sz[2])) < 1.3 * minf(float(sz[0]), float(sz[2])):
						turn = PI * 0.5 * float(rng.randi() % 4)                         # (a square one any way round)
					var bas := Basis(Vector3.UP, -st.heading_at(s) + turn)
					var xf := Transform3D(bas, Vector3(p.x, 0.0, p.z))
					var r := _rect(xf, float(sz[0]), float(sz[2]))
					var y = _stand(st, b, ground, ramps, foot, r)
					if y == null:
						continue
					xf.origin.y = float(y)
					_add(foot, r)
					var key := "%d/%s" % [district, dz[0]]
					if not groups.has(key):
						groups[key] = {"design": dz, "xfs": [], "cols": [], "custom": []}
					var g: Dictionary = groups[key]
					g.xfs.append(xf)
					g.cols.append((WALLS[rng.randi() % WALLS.size()] as Color).srgb_to_linear() * rng.randf_range(0.9, 1.08))
					# (the shader's: its floor height and window bay / 10 m, a seed, its main roof's height / 200 m)
					g.custom.append(Color(float(dz[1].get("floor", 2.8)) / 10.0, float(dz[1].get("bay", 2.6)) / 10.0,
						rng.randf(), float(dz[1].get("roof", sz[1])) / 200.0))
					placed += 1
					record.append([dz[0], xf])
			s += rng.randf_range(85.0, 120.0)
	# drawn: per design and district, the full silhouettes near, the light ones beyond, the
	# lightest furthest (a level missing: the one before it goes on further)
	var root := Node3D.new()
	root.name = NAME
	root.set_meta("count", placed)
	root.set_meta("buildings", record)                       # (a MultiMesh's transforms can't be read back headless)
	b.add_child(root)
	var mat := material(night)
	var reach := RANGE * Graphics.view_distance()
	for key in groups:
		var g: Dictionary = groups[key]
		var levels := []                                    # [mesh, level, from]
		for k in 3:
			if g.design[2][k] != null:
				levels.append([g.design[2][k], k, [0.0, NEAR, MID][k]])
		if float(g.design[1]["size"][1]) < LOW and levels.size() > 1:
			levels.pop_front()                              # (a low block: from the light one)
			levels[0][2] = 0.0
		for k in levels.size():
			var end: float = levels[k + 1][2] if k + 1 < levels.size() else reach
			_multimesh(root, g, levels[k][0], "Far_%s_%d" % [key.replace("/", "_"), levels[k][1]], mat, levels[k][2], end, k)
	return placed


static func _multimesh(root: Node3D, g: Dictionary, mesh: Mesh, nm: String, mat: Material, begin: float, end: float, nth: int) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = g.xfs.size()
	for k in g.xfs.size():
		mm.set_instance_transform(k, g.xfs[k])
		mm.set_instance_color(k, g.cols[k])
		mm.set_instance_custom_data(k, g.custom[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = nm
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_begin = begin
	mmi.visibility_range_end = end
	mmi.visibility_range_begin_margin = 50.0 if begin > 0.0 else 0.0
	mmi.visibility_range_end_margin = 50.0 if end <= MID else 200.0
	mmi.set_meta("design", g.design[0])
	mmi.set_meta("lod", nth)                                # (0: the nearest it's drawn at)
	root.add_child(mmi)


## The few designs a district's built from (its own dice): two towers, three mid-rises, a
## low block.
static func _palette(st, district: int, tall: Array, mid: Array, low: Array) -> Array:
	var r := RandomNumberGenerator.new()
	r.seed = hash([st.seed_used, "district", district])
	var out := []
	for e in [[tall, 2], [mid, 3], [low, 1]]:
		var pool: Array = (e[0] as Array).duplicate()
		for k in mini(int(e[1]), pool.size()):
			out.append(pool.pop_at(r.randi() % pool.size()))
	return out


## A design for a slot that wants a building about `want` m tall: the nearer a design's
## height to that, the likelier.
static func _pick(palette: Array, want: float, rng: RandomNumberGenerator) -> Array:
	var weights := []
	var total := 0.0
	for dz in palette:
		var w := exp(-pow((float(dz[1]["size"][1]) - want) / 40.0, 2.0)) + 0.02
		weights.append(w)
		total += w
	var x := rng.randf() * total
	for k in palette.size():
		x -= float(weights[k])
		if x <= 0.0:
			return palette[k]
	return palette[palette.size() - 1]


## Can a building stand on footprint r? Its foot's height if so (the lowest ground under it,
## less SINK), else null: off the city's ground, in the water, on a slope, near a road or a
## ramp, or on another building.
static func _stand(st, b, ground: TriangleMesh, ramps: Dictionary, foot: Dictionary, r: Dictionary):
	var c: Vector2 = r.c
	var half: float = Vector2(r.hx, r.hz).length()
	var lo := INF
	var hi := -INF
	for p in _samples(r):
		if not st.in_city(p.x, p.y):
			return null
		var y := ground_at(ground, p.x, p.y)
		if y < 1.5:                                         # (the lake, or no land drawn there)
			return null
		lo = minf(lo, y)
		hi = maxf(hi, y)
	if hi - lo > FLAT:
		return null
	if b._road_dist(c.x, c.y) < ROAD_CLEAR + half:
		return null
	var cell := Vector2i(floori(c.x / 100.0), floori(c.y / 100.0))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for q in ramps.get(cell + Vector2i(dx, dz), []):
				if c.distance_to(q) < ROAD_CLEAR + half:
					return null
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			for o in foot.get(cell + Vector2i(dx, dz), []):
				if overlap(r, o, STREET):
					return null
	return lo - SINK


## The ground's height at (x, z) as drawn (the topmost land triangle there), or -INF.
static func ground_at(tm: TriangleMesh, x: float, z: float) -> float:
	var hit: Dictionary = tm.intersect_ray(Vector3(x, 2000.0, z), Vector3.DOWN)
	return float((hit.position as Vector3).y) if not hit.is_empty() else -INF


## The land round the city as it will be drawn, for a ray straight down: the ribbons along the
## road (still the builder's buffers: its chunks are made into nodes at the end) and the far
## land's tiles under and beyond them, those reaching into the city's box.
static func _ground(b) -> TriangleMesh:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for c in b.st.city:
		lo = Vector2(minf(lo.x, c.x - c.r), minf(lo.y, c.z - c.r))
		hi = Vector2(maxf(hi.x, c.x + c.r), maxf(hi.y, c.z + c.r))
	var box := Rect2(lo, hi - lo).grow(100.0)
	var faces := PackedVector3Array()
	for c in b._chunks:
		var gb = b._chunks[c].get("terrain")
		if gb == null or gb.is_empty():
			continue
		var p0: Vector3 = gb.verts[0]
		if box.grow(700.0).has_point(Vector2(p0.x, p0.z)):  # (a chunk: 200 m of road and 330 m each side)
			faces.append_array(gb.verts)
	for n in b.get_children():
		if n is MeshInstance3D and String(n.name).begins_with("Land"):
			var ab: AABB = (n as MeshInstance3D).get_aabb()
			if box.intersects(Rect2(ab.position.x, ab.position.z, ab.size.x, ab.size.z)):
				faces.append_array((n as MeshInstance3D).mesh.get_faces())
	var tm := TriangleMesh.new()
	tm.create_from_faces(faces)
	return tm


## The ramps' roads, their points in 100 m cells.
static func _ramp_grid(st) -> Dictionary:
	var out := {}
	for r in st.ramps:
		for p in st.ramp_path(r).pts:
			var key := Vector2i(floori(p.x / 100.0), floori(p.z / 100.0))
			if not out.has(key):
				out[key] = []
			out[key].append(Vector2(p.x, p.z))
	return out


## A footprint on the ground: a rectangle (its middle c, its sides' directions ax, az, half
## sizes hx, hz) from a building's transform and its size along its own x and z.
static func _rect(xf: Transform3D, sx: float, sz: float) -> Dictionary:
	var ax := Vector2(xf.basis.x.x, xf.basis.x.z).normalized()
	var az := Vector2(xf.basis.z.x, xf.basis.z.z).normalized()
	return {"c": Vector2(xf.origin.x, xf.origin.z), "ax": ax, "az": az, "hx": sx * 0.5, "hz": sz * 0.5}


static func _add(foot: Dictionary, r: Dictionary) -> void:
	var key := Vector2i(floori(r.c.x / 100.0), floori(r.c.y / 100.0))
	if not foot.has(key):
		foot[key] = []
	foot[key].append(r)


## Where to read the ground under a footprint: its middle, corners and sides' middles.
static func _samples(r: Dictionary) -> Array:
	var out := []
	for u in [-1.0, 0.0, 1.0]:
		for v in [-1.0, 0.0, 1.0]:
			out.append(r.c + r.ax * r.hx * u * 0.98 + r.az * r.hz * v * 0.98)
	return out


## Do two footprints come within `gap` m of each other (or overlap)? (Separating axes: the
## four sides' directions.)
static func overlap(a: Dictionary, b: Dictionary, gap := 0.0) -> bool:
	var d: Vector2 = b.c - a.c
	for ax in [a.ax, a.az, b.ax, b.az]:
		var ra: float = a.hx * absf(ax.dot(a.ax)) + a.hz * absf(ax.dot(a.az))
		var rb: float = b.hx * absf(ax.dot(b.ax)) + b.hz * absf(ax.dot(b.az))
		if absf(d.dot(ax)) > ra + rb + gap:
			return false
	return true


## The far tier's material: the instance's facade colour; on each wall windows in a grid from
## where the pixel is on the building (its own space, in metres: the floor height and window
## bay measured on the full model come in the instance's custom data). The glass dark and
## bluish by day with the sky in it at a glancing angle, a few blinds drawn; at night (night
## 0..1: WorldMaterials.night_amount) a share of the windows lit, warm or cold-white. The
## roofs and the rooftop plant (above the main roof) plain. Far off, where a floor is a
## pixel or two, the grid fades to its average by day (no shimmer); at night each lit window's
## whole cell glows instead (points of light). Each building its own share lit (a few nearly
## dark) and its own mix of warm and cold. Forward+ and Compatibility.
static func material(night: float) -> ShaderMaterial:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = """
shader_type spatial;
render_mode cull_back;
uniform float night = 0.0;
varying vec3 opos;
varying vec3 onrm;
varying vec4 style;
void vertex() {
	opos = VERTEX;
	onrm = NORMAL;
	style = INSTANCE_CUSTOM;
}
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void fragment() {
	float storey = max(style.x * 10.0, 2.2);
	float bay = max(style.y * 10.0, 1.2);
	float seed = style.z;
	float top = style.w * 200.0;                                        // (the main roof: the plant above it has none)
	vec3 n = normalize(onrm);
	float facade = step(abs(n.y), 0.45);                               // (a wall: windows)
	vec2 t = normalize(vec2(-n.z, n.x) + vec2(0.0001, 0.0));
	vec2 cell = vec2(dot(opos.xz, t) / bay, opos.y / storey);
	vec2 id = floor(cell);
	vec2 f = fract(cell);
	// the window in its cell: wider or narrower, taller or squatter, by the building
	float wx = mix(0.1, 0.3, fract(seed * 13.7));
	float wy0 = mix(0.16, 0.3, fract(seed * 7.3));
	float wy1 = mix(0.8, 0.92, fract(seed * 3.1));
	float rows = step(4.0, opos.y) * step(opos.y, top - 1.6);       // (none on the shop floor or the parapet)
	float win = step(wx, f.x) * step(f.x, 1.0 - wx) * step(wy0, f.y) * step(f.y, wy1);
	float cover = (1.0 - 2.0 * wx) * (wy1 - wy0);
	vec2 fw = fwidth(cell);
	float fade = smoothstep(0.22, 0.65, max(fw.x, fw.y));
	float glass = facade * rows * mix(win, cover, fade);
	float rnd = hash(id + seed * 37.0);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	vec3 pane = mix(vec3(0.022, 0.032, 0.048), vec3(0.06, 0.08, 0.11), rnd);
	pane = mix(pane, vec3(0.3, 0.38, 0.48) * (1.0 - 0.85 * night), 0.06 + 0.34 * fres);   // (the sky in it)
	vec3 wall = COLOR.rgb * mix(0.8, 1.0, smoothstep(0.0, 24.0, opos.y));
	pane = mix(pane, wall * 0.7, step(0.88, rnd) * (1.0 - fade));     // (blinds drawn)
	float roof = step(0.55, n.y);
	vec3 base = wall * mix(1.0, 0.6, roof) * mix(1.0, 0.82, step(top + 0.3, opos.y));   // (the plant on the roof a shade darker)
	ALBEDO = mix(base, pane, glass);
	ROUGHNESS = mix(0.88, 0.26, glass);
	METALLIC = 0.0;
	SPECULAR = mix(0.3, 0.5, glass);
	// at night a share of the windows lit (by building), warm or cold-white; far off, a lit
	// window's whole cell, dimmer (points of light, not a glowing wall)
	float share = (seed < 0.12 ? 0.05 : mix(0.16, 0.48, fract(seed * 5.9))) * night;   // (a few nearly dark)
	float lit = step(1.0 - share, hash(id * 1.31 + seed * 11.0)) * (0.45 + 0.8 * hash(id * 2.7 + seed));
	float cool = mix(0.1, 0.6, fract(seed * 3.77));                     // (its own share of cold-white rooms)
	vec3 tone = mix(vec3(1.0, 0.72, 0.42), vec3(0.66, 0.76, 1.0), step(1.0 - cool, hash(id * 3.1 + seed)));
	EMISSION = facade * rows * lit * tone * mix(win, 0.5, fade) * night * 1.1;
}
"""
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("night", night)
	return m
