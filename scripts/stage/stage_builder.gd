extends Node3D
## Turns a StageGen into the world: the gravel road (crowned, with two worn
## wheel tracks), grass ditches and rolling ground out to ~75 m, a low-poly
## forest that crowds the INSIDE of corners (so you can't see round them:
## that's what the notes are for), rocks on the inside of "don't cut" corners,
## mud puddles, the start / finish arches, and the sky and sun.
## Every surface the tyres can touch says what it is (meta "surface").

const MeshBuf = preload("res://scripts/stage/mesh_buf.gd")

const GRAVEL := Color(0.71, 0.6, 0.44)
const TRACK := Color(0.6, 0.5, 0.36)
const VERGE := Color(0.5, 0.52, 0.3)
const GRASS := Color(0.34, 0.54, 0.21)
const GRASS_FAR := Color(0.28, 0.46, 0.19)
const DIRT := Color(0.45, 0.36, 0.25)
## Road cross-section: [d, height, colour of the strip to the next point]
const ROAD_X := [[-3.1, -0.12, VERGE], [-2.8, 0.0, GRAVEL], [-1.25, 0.04, TRACK], [-0.55, 0.05, GRAVEL],
	[0.55, 0.05, TRACK], [1.25, 0.04, GRAVEL], [2.8, 0.0, VERGE], [3.1, -0.12, VERGE]]
## Ground beyond the road, each side: [d, height above the road, noise amplitude]
const GROUND_X := [[2.9, -0.2, 0.0], [4.3, -0.5, 0.0], [6.0, -0.15, 0.15], [10.0, 0.1, 0.5],
	[18.0, 0.3, 1.2], [30.0, 0.6, 2.2], [50.0, 1.0, 3.2], [78.0, 1.6, 4.5]]

const CHUNK := 160.0                # trees are grouped per this much road ...
const TREE_DRAW := 520.0            # ... and a group further away than this isn't drawn

var st
var start_clock: Label3D            # the countdown board at the start line
var tree_count := 0
var _noise := FastNoiseLite.new()
var _road_grid := {}                # 20 m cells -> [sample indices], to keep trees off the road
var _rng := RandomNumberGenerator.new()


func build(stage) -> void:
	st = stage
	_rng.seed = hash([st.seed_used, "props"])
	_noise.seed = st.seed_used
	_noise.frequency = 0.012
	for i in st.pts.size():
		var key := Vector2i(floori(st.pts[i].x / 20.0), floori(st.pts[i].z / 20.0))
		if not _road_grid.has(key):
			_road_grid[key] = []
		_road_grid[key].append(i)
	_environment()
	_road()
	_ground()
	_base()
	_forest()
	_rocks()
	_puddles()
	_arches()


# ── road ──────────────────────────────────────────────────────────────────

func _road() -> void:
	var mb := MeshBuf.new()
	var n: int = st.pts.size()
	var prev: Array = []
	for i in n:
		var s: float = i * st.STEP
		var c: Vector3 = st.pts[i]
		var r: Vector3 = st.right_at(s)
		var row: Array = []
		for x in ROAD_X:
			row.append(c + r * x[0] + Vector3.UP * x[1])
		if not prev.is_empty():
			var shade := 0.94 + 0.06 * sin(s * 0.37) * cos(s * 0.11)
			for k in ROAD_X.size() - 1:
				var col: Color = ROAD_X[k][2] * shade
				col.a = 1.0
				mb.quad(prev[k], prev[k + 1], row[k + 1], row[k], col, true)
		prev = row
	_add(mb, "gravel", "Road")
	# the start line
	var sl := MeshBuf.new()
	var s0: float = st.START_S
	var a: Vector3 = st.world_at(s0, -2.8) + Vector3.UP * 0.07
	var b: Vector3 = st.world_at(s0, 2.8) + Vector3.UP * 0.07
	var f: Vector3 = st.forward_at(s0) * 0.4
	sl.quad(a - f, b - f, b + f, a + f, Color(0.95, 0.95, 0.92))
	_add(sl, "", "StartLine")


# ── ground ────────────────────────────────────────────────────────────────

func _ground() -> void:
	var mb := MeshBuf.new()
	var n: int = st.pts.size()
	var stride := 2                                     # every 4 m is plenty off the road
	for side in [-1.0, 1.0]:
		var prev: Array = []
		for i in range(0, n, stride):
			var s: float = i * st.STEP
			var c: Vector3 = st.pts[i]
			var r: Vector3 = st.right_at(s)
			# on the inside of a bend the ground can't reach past the bend's centre: clamp it
			var reach := 1e9
			for j in range(maxi(0, i - 12), mini(n, i + 13)):
				var k: float = st.curv[j]
				if signf(k) == side and absf(k) > 1e-4:
					reach = minf(reach, 0.85 / absf(k))
			# ... and never out over another stretch of the same road (after a bend the road
			# comes back past this spot): stop where some other road is closer than ours
			for g in GROUND_X:
				var probe: Vector3 = c + r * (g[0] * side)
				if g[0] > 4.0 and _nearest_road(probe) < g[0] - 2.5:
					reach = minf(reach, maxf(3.4, g[0] - 6.0))
					break
			var row: Array = []
			var cols: Array = []
			for g in GROUND_X:
				var d: float = minf(g[0], maxf(reach, 3.4))
				var p: Vector3 = c + r * (d * side)
				var h: float = g[1] + g[2] * _noise.get_noise_2d(p.x, p.z)
				row.append(p + Vector3.UP * h)
				var col: Color = GRASS.lerp(GRASS_FAR, clampf(d / 60.0, 0.0, 1.0))
				col = col * (0.92 + 0.12 * _noise.get_noise_2d(p.z * 3.0, p.x * 3.0))
				col.a = 1.0
				cols.append(col if d > 4.0 else GRASS * 0.85)
			if not prev.is_empty():
				for k in GROUND_X.size() - 1:
					mb.quad(prev[k], prev[k + 1], row[k + 1], row[k], cols[k], true)
			prev = row
	_add(mb, "grass", "Ground")


## A big flat field under everything: whatever the ribbons miss is still green.
func _base() -> void:
	var lo := INF
	var mn := Vector3(INF, 0, INF)
	var mx := Vector3(-INF, 0, -INF)
	for p in st.pts:
		lo = minf(lo, p.y)
		mn = Vector3(minf(mn.x, p.x), 0, minf(mn.z, p.z))
		mx = Vector3(maxf(mx.x, p.x), 0, maxf(mx.z, p.z))
	var y := lo - 1.6
	mn -= Vector3(200, 0, 200)
	mx += Vector3(200, 0, 200)
	var mb := MeshBuf.new()
	mb.quad(Vector3(mn.x, y, mn.z), Vector3(mx.x, y, mn.z), Vector3(mx.x, y, mx.z), Vector3(mn.x, y, mx.z), GRASS_FAR * 0.9)
	var body := _add(mb, "", "Base")
	var sb := StaticBody3D.new()
	sb.set_meta("surface", "grass")
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(mx.x - mn.x, 2.0, mx.z - mn.z)
	cs.shape = box
	cs.position = Vector3((mn.x + mx.x) * 0.5, y - 1.0, (mn.z + mx.z) * 0.5)
	sb.add_child(cs)
	add_child(sb)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Mesh + (if `surface` isn't "") a static body with its triangles.
func _add(mb, surface: String, node_name: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mb.mesh()
	mi.material_override = MeshBuf.material()
	add_child(mi)
	if surface != "" and not mb.faces.is_empty():
		var sb := StaticBody3D.new()
		sb.name = node_name + "Body"
		sb.set_meta("surface", surface)
		var cs := CollisionShape3D.new()
		cs.shape = mb.shape()
		sb.add_child(cs)
		add_child(sb)
	return mi


# ── forest ────────────────────────────────────────────────────────────────

func _forest() -> void:
	# trees are grouped in chunks of road (CHUNK m) so each chunk can be culled and
	# faded out by distance: thousands of trees, but only the nearby ones are drawn
	var chunks := {}                                 # chunk index -> {kind: [Transform3D]}
	var trunks := StaticBody3D.new()
	trunks.name = "Trunks"
	trunks.set_meta("surface", "grass")
	add_child(trunks)
	var n: int = st.pts.size()
	for i in range(0, n, 2):                         # every 4 m of road
		var s: float = i * st.STEP
		if s < st.START_S - 30.0:
			continue
		var c: Vector3 = st.pts[i]
		var r: Vector3 = st.right_at(s)
		var k: float = st.curv[mini(i + 4, n - 1)]
		for side in [-1.0, 1.0]:
			var inside: bool = signf(k) == side and absf(k) > 1.0 / 160.0
			# [from, to (m off the centreline), chance, how many tries]
			var slots: Array = [[5.0, 9.0, 0.95 if inside else 0.6, 1],     # the wall along the road
				[9.0, 18.0, 0.9, 2], [18.0, 40.0, 0.85, 3], [40.0, 76.0, 0.8, 3]]
			if inside:
				slots.append([4.6, 7.5, 0.8, 1])                           # thicker on the inside of bends
			for sl in slots:
				for t in sl[3]:
					if _rng.randf() > sl[2]:
						continue
					var d: float = _rng.randf_range(sl[0], sl[1])
					var along: Vector3 = st.forward_at(s) * _rng.randf_range(-2.0, 2.0)
					var p: Vector3 = c + r * (d * side) + along
					if _near_road(p, 4.4):
						continue
					p.y = _ground_height(c.y, d, p) - 0.15
					var kind: String = ["pine", "pine", "pine", "round", "birch", "bush"][_rng.randi() % 6]
					if d < 6.0 and kind == "bush":
						kind = "round"
					var sc := _rng.randf_range(0.8, 1.4)
					var xf := Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * sc), p)
					var ci := int(s / CHUNK)
					if not chunks.has(ci):
						chunks[ci] = {"pine": [], "round": [], "birch": [], "bush": []}
					chunks[ci][kind].append(xf)
					tree_count += 1
					if d < 10.0 and kind != "bush":
						var cs := CollisionShape3D.new()
						var cyl := CylinderShape3D.new()
						cyl.radius = 0.28 * sc
						cyl.height = 4.0
						cs.shape = cyl
						cs.position = p + Vector3.UP * 2.0
						trunks.add_child(cs)
	var meshes := {}
	for kind in ["pine", "round", "birch", "bush"]:
		meshes[kind] = _tree_mesh(kind)
	var mat := MeshBuf.material()
	for ci in chunks:
		for kind in chunks[ci]:
			var list: Array = chunks[ci][kind]
			if list.is_empty():
				continue
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = meshes[kind]
			mm.instance_count = list.size()
			for j in list.size():
				mm.set_instance_transform(j, list[j])
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "Trees_%d_%s" % [ci, kind]
			mmi.multimesh = mm
			mmi.material_override = mat
			mmi.visibility_range_end = TREE_DRAW
			mmi.visibility_range_end_margin = 40.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
			if kind == "bush":
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mmi)


func _ground_height(road_y: float, d: float, p: Vector3) -> float:
	var h := 0.0
	for g in range(GROUND_X.size() - 1):
		var a: Array = GROUND_X[g]
		var b: Array = GROUND_X[g + 1]
		if d >= a[0] and d <= b[0]:
			var u: float = (d - a[0]) / (b[0] - a[0])
			var ha: float = a[1] + a[2] * _noise.get_noise_2d(p.x, p.z)
			var hb: float = b[1] + b[2] * _noise.get_noise_2d(p.x, p.z)
			h = lerpf(ha, hb, u)
			break
	if d > GROUND_X[-1][0]:
		h = GROUND_X[-1][1]
	return road_y + h


## Distance (flat) from p to the nearest centerline sample, up to ~40 m (INF if none near).
func _nearest_road(p: Vector3) -> float:
	var best := INF
	var c := Vector2i(floori(p.x / 20.0), floori(p.z / 20.0))
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			for i in _road_grid.get(c + Vector2i(dx, dz), []):
				var q: Vector3 = st.pts[i]
				best = minf(best, Vector2(p.x - q.x, p.z - q.z).length())
	return best


func _near_road(p: Vector3, dist: float) -> bool:
	var c := Vector2i(floori(p.x / 20.0), floori(p.z / 20.0))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for i in _road_grid.get(c + Vector2i(dx, dz), []):
				var q: Vector3 = st.pts[i]
				if Vector2(p.x - q.x, p.z - q.z).length() < dist:
					return true
	return false


## Low-poly tree meshes (origin at the foot of the trunk).
func _tree_mesh(kind: String) -> ArrayMesh:
	var mb := MeshBuf.new()
	var bark := Color(0.38, 0.27, 0.18)
	match kind:
		"pine":
			_cyl(mb, Vector3.ZERO, 0.22, 1.6, 5, bark)
			var greens := [Color(0.16, 0.36, 0.2), Color(0.19, 0.42, 0.22), Color(0.22, 0.47, 0.24)]
			for t in 3:
				_cone(mb, Vector3(0, 1.2 + t * 1.5, 0), 1.9 - t * 0.45, 2.6, 7, greens[t])
		"round":
			_cyl(mb, Vector3.ZERO, 0.24, 2.2, 5, bark)
			_blob(mb, Vector3(0, 3.6, 0), Vector3(2.0, 1.8, 2.0), Color(0.3, 0.55, 0.22))
			_blob(mb, Vector3(0.6, 4.5, 0.3), Vector3(1.3, 1.2, 1.3), Color(0.35, 0.6, 0.25))
		"birch":
			_cyl(mb, Vector3.ZERO, 0.16, 3.4, 5, Color(0.9, 0.88, 0.82))
			_blob(mb, Vector3(0, 4.3, 0), Vector3(1.3, 1.6, 1.3), Color(0.45, 0.66, 0.28))
		"bush":
			_blob(mb, Vector3(0, 0.55, 0), Vector3(1.2, 0.8, 1.2), Color(0.26, 0.5, 0.2))
	return mb.mesh()


func _cyl(mb, base: Vector3, r: float, h: float, seg: int, col: Color) -> void:
	for k in seg:
		var a0 := TAU * k / seg
		var a1 := TAU * (k + 1) / seg
		var p0 := base + Vector3(cos(a0) * r, 0, sin(a0) * r)
		var p1 := base + Vector3(cos(a1) * r, 0, sin(a1) * r)
		mb.tri_raw(p0, p1, p1 + Vector3.UP * h, col)
		mb.tri_raw(p0, p1 + Vector3.UP * h, p0 + Vector3.UP * h, col)


func _cone(mb, base: Vector3, r: float, h: float, seg: int, col: Color) -> void:
	var top := base + Vector3.UP * h
	for k in seg:
		var a0 := TAU * k / seg
		var a1 := TAU * (k + 1) / seg
		var p0 := base + Vector3(cos(a0) * r, 0, sin(a0) * r)
		var p1 := base + Vector3(cos(a1) * r, 0, sin(a1) * r)
		mb.tri_raw(p0, p1, top, col * (0.9 + 0.15 * (k % 2)))
		mb.tri_raw(p1, p0, base, col * 0.75)


## A squashed octahedron-ish ball (8 faces + a belt: chunky low poly).
func _blob(mb, c: Vector3, sz: Vector3, col: Color) -> void:
	var seg := 6
	var top := c + Vector3(0, sz.y, 0)
	var bot := c - Vector3(0, sz.y * 0.8, 0)
	var ring_hi: Array = []
	var ring_lo: Array = []
	for k in seg:
		var a := TAU * k / seg
		ring_hi.append(c + Vector3(cos(a) * sz.x * 0.8, sz.y * 0.35, sin(a) * sz.z * 0.8))
		ring_lo.append(c + Vector3(cos(a + 0.5) * sz.x, -sz.y * 0.2, sin(a + 0.5) * sz.z))
	for k in seg:
		var k1 := (k + 1) % seg
		var shade := 0.92 + 0.14 * float(k % 3) / 2.0
		mb.tri_raw(ring_hi[k], ring_hi[k1], top, col * (shade + 0.08))
		mb.tri_raw(ring_lo[k], ring_hi[k1], ring_hi[k], col * shade)
		mb.tri_raw(ring_lo[k], ring_lo[k1], ring_hi[k1], col * (shade - 0.06))
		mb.tri_raw(ring_lo[k1], ring_lo[k], bot, col * 0.7)


# ── rocks, puddles, arches ────────────────────────────────────────────────

func _rocks() -> void:
	var body := StaticBody3D.new()
	body.name = "Rocks"
	body.set_meta("surface", "gravel")
	add_child(body)
	var mb := MeshBuf.new()
	for rk in st.rocks:
		var p: Vector3 = st.world_at(rk.s, rk.d)
		var r: float = rk.r
		_blob(mb, p + Vector3.UP * r * 0.35, Vector3(r, r * 0.75, r * 0.9), Color(0.55, 0.54, 0.5))
		var cs := CollisionShape3D.new()
		var sph := SphereShape3D.new()
		sph.radius = r * 0.85
		cs.shape = sph
		cs.position = p + Vector3.UP * r * 0.3
		body.add_child(cs)
	if not mb.is_empty():
		var mi := MeshInstance3D.new()
		mi.name = "RockMesh"
		mi.mesh = mb.mesh()
		mi.material_override = MeshBuf.material()
		add_child(mi)


func _puddles() -> void:
	var mb := MeshBuf.new()
	for pd in st.puddles:
		var c: Vector3 = st.world_at(pd.s, pd.d) + Vector3.UP * 0.075
		var f: Vector3 = st.forward_at(pd.s)
		var r: Vector3 = st.right_at(pd.s)
		var seg := 9
		for k in seg:
			var a0 := TAU * k / seg
			var a1 := TAU * (k + 1) / seg
			var p0: Vector3 = c + f * cos(a0) * pd.r * 1.3 + r * sin(a0) * pd.r * 0.8
			var p1: Vector3 = c + f * cos(a1) * pd.r * 1.3 + r * sin(a1) * pd.r * 0.8
			mb.tri(c, p0, p1, Color(0.3, 0.22, 0.14))
	var mi := MeshInstance3D.new()
	mi.name = "Puddles"
	mi.mesh = mb.mesh()
	var m := MeshBuf.material()
	m.roughness = 0.15
	m.metallic_specular = 0.8
	mi.material_override = m
	add_child(mi)


func _arches() -> void:
	_arch(st.START_S + 2.0, "START", Color(0.85, 0.15, 0.12))
	_arch(st.finish_s, "FINISH", Color(0.1, 0.35, 0.8))
	_sign(st.finish_s - 100.0, 3.8, "FLYING FINISH 100", Color(0.95, 0.8, 0.1))
	_sign(st.finish_s + 70.0, 3.8, "STOP", Color(0.85, 0.12, 0.1))
	# the start clock: on the co-driver's side, where they can read it
	var p: Vector3 = st.world_at(st.START_S + 2.5, 3.9)
	var post := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.12, 1.6, 0.12)
	post.mesh = bm
	post.position = p + Vector3.UP * 0.8
	add_child(post)
	var board := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(1.1, 0.7, 0.08)
	board.mesh = bb
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.08, 0.08, 0.09)
	board.material_override = bmat
	board.position = p + Vector3.UP * 1.85
	board.rotation.y = -st.heading_at(st.START_S)        # faces the car waiting at the line
	add_child(board)
	start_clock = Label3D.new()
	start_clock.text = "--"
	start_clock.font_size = 96
	start_clock.pixel_size = 0.005
	start_clock.modulate = Color(1.0, 0.3, 0.2)
	start_clock.outline_size = 0
	start_clock.position = board.position - st.forward_at(st.START_S) * 0.05
	start_clock.rotation.y = board.rotation.y
	add_child(start_clock)


func _arch(s: float, text: String, col: Color) -> void:
	var f: Vector3 = st.forward_at(s)
	var yaw: float = st.heading_at(s)
	for side in [-1.0, 1.0]:
		var pole := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(0.25, 4.6, 0.25)
		pole.mesh = pm
		pole.position = st.world_at(s, side * 3.6) + Vector3.UP * 2.3
		add_child(pole)
	var banner := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(7.6, 0.9, 0.15)
	banner.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	banner.material_override = mat
	banner.position = st.world_at(s, 0.0) + Vector3.UP * 4.4
	banner.rotation.y = -yaw
	add_child(banner)
	for face in [1.0, -1.0]:
		var lab := Label3D.new()
		lab.text = text
		lab.font_size = 110
		lab.pixel_size = 0.006
		lab.modulate = Color.WHITE
		lab.outline_size = 0
		lab.position = banner.position - f * 0.09 * face
		lab.rotation.y = -yaw + (0.0 if face > 0.0 else PI)
		add_child(lab)


func _sign(s: float, d: float, text: String, col: Color) -> void:
	var p: Vector3 = st.world_at(s, d)
	var post := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.1, 1.8, 0.1)
	post.mesh = pm
	post.position = p + Vector3.UP * 0.9
	add_child(post)
	var board := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.8, 0.6, 0.06)
	board.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	board.material_override = mat
	board.position = p + Vector3.UP * 2.0
	board.rotation.y = -st.heading_at(s)
	add_child(board)
	var lab := Label3D.new()
	lab.text = text
	lab.font_size = 48
	lab.pixel_size = 0.006
	lab.modulate = Color(0.05, 0.05, 0.05)
	lab.outline_size = 0
	lab.position = board.position - st.forward_at(s) * 0.04
	lab.rotation.y = -st.heading_at(s)
	add_child(lab)


# ── sky ───────────────────────────────────────────────────────────────────

func _environment() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.32, 0.55, 0.85)
	sm.sky_horizon_color = Color(0.72, 0.82, 0.9)
	sm.ground_horizon_color = Color(0.6, 0.7, 0.62)
	sm.ground_bottom_color = Color(0.25, 0.35, 0.22)
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.4     # the rest is a neutral grey: the cabin isn't blue
	env.ambient_light_color = Color(0.62, 0.62, 0.6)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.95
	env.fog_enabled = true
	env.fog_light_color = Color(0.72, 0.8, 0.86)
	env.fog_density = 0.0045
	env.fog_sky_affect = 0.15
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-52.0), deg_to_rad(35.0), 0.0)
	sun.light_energy = 1.0
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 70.0
	add_child(sun)
