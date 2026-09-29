extends RefCounted
## The city along the highway: what makes the drive read as New York. Rows of
## brick walk-ups, warehouses and housing-project slabs behind the highway
## walls (30-145 m out from the centerline, all the way round the loop), cut
## by cross streets, with rooftop water towers, fire escapes, painted ghost
## signs and billboards. Plus the bits
## the highway builder shares: graffiti tags, the brick facade and chain-link
## materials, and "is this spot clear of the ramps?" tests.
##
## Batching: per side and 200 m of highway, one facade mesh (a small shader
## material: brick + windows from a generated 64 px texture, tinted by vertex
## color, UVs laid out per wall so windows line up with the storeys) and one
## detail mesh (roofs, cornices, tanks, fire escapes: the plain road material).
## The buildings go in the builder's Road group (no merging, long range: they
## are the skyline from the road).

const Highway = preload("res://scripts/world/highway.gd")
const RoadMesh = preload("res://scripts/world/road_mesh.gd")

const CHUNK := 200.0
const GROUND_Y := -0.25              # NeighborhoodBuilder.GROUND_Y
const CELL := 16.0                  # spatial hash cell (m) for the keep-out tests
## Rows of buildings on each side: [near d, far d, kind weights {kind: weight}]
const ROWS := [[30.0, 54.0, {"walkup": 6, "warehouse": 2, "vacant": 1}],
	[58.0, 92.0, {"walkup": 4, "apartment": 4, "warehouse": 1.5, "vacant": 0.5}],
	[97.0, 145.0, {"apartment": 4, "projects": 3, "warehouse": 1.5}]]
const BRICK := [Color(0.56, 0.26, 0.19), Color(0.46, 0.22, 0.16), Color(0.62, 0.33, 0.22), Color(0.5, 0.36, 0.26),
	Color(0.72, 0.6, 0.44), Color(0.8, 0.72, 0.55), Color(0.62, 0.6, 0.57), Color(0.38, 0.3, 0.26), Color(0.78, 0.76, 0.7)]
const WAREHOUSE := [Color(0.72, 0.62, 0.46), Color(0.62, 0.6, 0.57), Color(0.56, 0.28, 0.2), Color(0.5, 0.55, 0.47),
	Color(0.8, 0.78, 0.72)]
const PROJECTS := [Color(0.5, 0.27, 0.2), Color(0.56, 0.33, 0.25), Color(0.62, 0.42, 0.32)]
const TAR := Color(0.26, 0.26, 0.27)
const PARKED := ["TCar_Sedan_Silver", "TCar_Pickup_Red", "TCar_SUV_White", "TCar_Hatch_Blue", "TCar_Sedan_Grey", "TCar_SUV_Silver"]
const IRON := Color(0.09, 0.09, 0.1)
const GHOST_SIGNS := ["SCHAPIRO'S PICKLES · SINCE 1921", "KOSHER WINE & PICKLE WORKS", "GOLDFARB BROS. FUR STORAGE",
	"UNCLE SAL'S DISCOUNT CARPET", "EMPIRE BAGEL SUPPLY CO."]
const TAG_COLORS := [Color(0.95, 0.2, 0.55), Color(0.3, 0.85, 0.3), Color(0.2, 0.75, 0.95), Color(1.0, 0.55, 0.1),
	Color(0.98, 0.9, 0.2), Color(0.95, 0.95, 0.95), Color(0.9, 0.12, 0.12), Color(0.6, 0.3, 0.9), Color(0.75, 0.78, 0.82)]

var nb                       # the neighborhood builder
var hw: Highway
var rng := RandomNumberGenerator.new()
var infields: Array = []     # PackedVector2Array (world x/z): between a ramp and the highway
var keep_out: Array = []     # Rect2 (world x/z) nobody builds in
var _ramp_hash := {}         # Vector2i -> [[Vector2 x/z, y], ...]: every ramp sample
var _block_hash := {}        # Vector2i -> [[Vector2, r], ...]: the builder's tree blockers
var _facade_mat: ShaderMaterial
var _fence_mat: StandardMaterial3D
var _ghosts := 0


func _init(builder) -> void:
	nb = builder
	hw = builder.hw
	rng.seed = 212


# ================================================================== keep-out tests

## Ramp samples and the infields (the land a ramp encloses with the highway).
## Call before anything asks ramp_near / in_infield.
func prep() -> void:
	for nm in hw.ramp_names():
		var p = hw.paths[nm]
		for q in p.pts:
			var k := Vector2i(floori(q.x / CELL), floori(q.z / CELL))
			if not _ramp_hash.has(k):
				_ramp_hash[k] = []
			_ramp_hash[k].append([Vector2(q.x, q.z), q.y])
		# the side the ramp meets the highway on (an on-ramp's flyover crosses over first)
		var s_end: Vector2 = hw.locate(p.pts[p.pts.size() - 1] if nm.ends_with("_on") else p.pts[0])
		var side := signf(s_end.y)
		var poly := PackedVector2Array()
		var s_lo := INF
		var s_hi := -INF
		for q in p.pts:
			var l: Vector2 = hw.locate(q)
			if signf(l.y) == side and absf(l.y) > 1.0:
				poly.append(Vector2(q.x, q.z))
				s_lo = minf(s_lo, l.x)
				s_hi = maxf(s_hi, l.x)
		if poly.size() < 3:
			continue
		# close it along the centerline, from the end nearest the last point back
		var last: Vector2 = hw.locate(Vector3(poly[poly.size() - 1].x, 0, poly[poly.size() - 1].y))
		var first: Vector2 = hw.locate(Vector3(poly[0].x, 0, poly[0].y))
		for sc in [last.x, first.x]:
			var c := hw.point(sc, 0.0)
			poly.append(Vector2(c.x, c.z))
		infields.append(poly)


## Is there a ramp within r (plan distance) of p? Ramp samples higher than
## max_y (a flyover deck) don't count.
func ramp_near(p: Vector3, r: float, max_y := INF) -> bool:
	var q := Vector2(p.x, p.z)
	var n := int(ceil(r / CELL))
	var k0 := Vector2i(floori(q.x / CELL), floori(q.y / CELL))
	for i in range(-n, n + 1):
		for j in range(-n, n + 1):
			for e in _ramp_hash.get(k0 + Vector2i(i, j), []):
				if e[1] <= max_y and q.distance_to(e[0]) < r:
					return true
	return false


func in_infield(p: Vector3) -> bool:
	var q := Vector2(p.x, p.z)
	for poly in infields:
		if Geometry2D.is_point_in_polygon(q, poly):
			return true
	return false


func _hash_blockers() -> void:
	_block_hash.clear()
	for bl in nb._tree_blockers:
		var r: float = bl[1]
		if r > 100.0:            # the tunnel hills: buildings check the portal stations instead
			continue
		var c: Vector2 = bl[0]
		var rr := r + 4.0
		for i in range(floori((c.x - rr) / CELL), floori((c.x + rr) / CELL) + 1):
			for j in range(floori((c.y - rr) / CELL), floori((c.y + rr) / CELL) + 1):
				var k := Vector2i(i, j)
				if not _block_hash.has(k):
					_block_hash[k] = []
				_block_hash[k].append(bl)


## Can something stand at world point p (with `margin` to spare)?
func clear_at(p: Vector3, margin := 2.0) -> bool:
	var q := Vector2(p.x, p.z)
	for bl in _block_hash.get(Vector2i(floori(q.x / CELL), floori(q.y / CELL)), []):
		if q.distance_to(bl[0]) < bl[1] + margin:
			return false
	for r in keep_out:
		if (r as Rect2).has_point(q):
			return false
	if ramp_near(p, 11.0 + margin):
		return false
	return not in_infield(p)


## Is the (s, d) footprint free? Samples every ~5 m, 1.5 m beyond its edges.
func _free(s0: float, s1: float, dn: float, df: float, side: int) -> bool:
	if s0 < hw.s_portal_w + 8.0 or s1 > hw.s_portal_e - 8.0:
		return false
	var ns := maxi(int(ceil((s1 - s0 + 3.0) / 5.0)), 1)
	var nd := maxi(int(ceil((df - dn + 3.0) / 5.0)), 1)
	for i in ns + 1:
		for j in nd + 1:
			var s := lerpf(s0 - 1.5, s1 + 1.5, float(i) / ns)
			var d := lerpf(dn - 1.5, df + 1.5, float(j) / nd)
			if not clear_at(hw.point(s, side * d), 0.5):
				return false
	return true


# ================================================================== materials

## Brick with windows: a 64 px tile = 2 bays x 2 storeys (four window kinds:
## dark sash, a pulled blind, sky reflection, an AC unit in the window). Alpha
## marks the brick (tinted by the vertex color); glass, frames and limestone
## sills keep their own color.
func facade_mat() -> ShaderMaterial:
	if _facade_mat:
		return _facade_mat
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var r := RandomNumberGenerator.new()
	r.seed = 9
	var shade := {}
	for y in n:
		for x in n:
			var cx := x % 32
			var cy := y % 32
			var cell := int(x / 32) + 2 * int(y / 32)
			var course := int(y / 4)
			var bx := int((x + (4 if course % 2 else 0)) / 8)
			var key := Vector2i(bx, course)
			if not shade.has(key):
				shade[key] = 0.86 + r.randf() * 0.14
			var v: float = shade[key]
			var c := Color(v, v, v, 1.0)
			if y % 4 == 3 or (x + (4 if course % 2 else 0)) % 8 == 7:
				c = Color(0.7, 0.7, 0.68, 1.0)                  # mortar
			var in_x := cx >= 9 and cx <= 22
			if in_x and (cy == 6 or cy == 25) or (cx >= 8 and cx <= 23 and (cy == 6 or cy == 25)):
				c = Color(0.78, 0.76, 0.7, 0.0)                 # limestone lintel / sill
			elif in_x and cy >= 7 and cy <= 24:
				if cx == 9 or cx == 22 or cy == 7 or cy == 24 or cy == 16:
					c = Color(0.82, 0.8, 0.76, 0.0) if cell != 2 else Color(0.12, 0.12, 0.12, 0.0)   # sash frames
				else:
					var g := Color(0.1, 0.12, 0.16, 0.0)        # dark glass
					match cell:
						1:
							if cy < 14:
								g = Color(0.74, 0.7, 0.58, 0.0)     # a blind half down
						2:
							g = Color(0.34, 0.44, 0.56, 0.0).darkened((cy - 7) * 0.035)   # the sky in it
						3:
							if cy >= 18 and cx >= 11 and cx <= 20:
								g = Color(0.72, 0.72, 0.7, 0.0) if cy != 18 else Color(0.5, 0.5, 0.5, 0.0)   # AC unit
					c = g
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	var sh := Shader.new()
	sh.code = """shader_type spatial;
uniform sampler2D tex : filter_linear_mipmap_anisotropic, repeat_enable;
void fragment() {
	vec4 t = texture(tex, UV);
	ALBEDO = mix(t.rgb, t.rgb * COLOR.rgb, t.a);
	ROUGHNESS = mix(0.35, 0.95, t.a);
	SPECULAR = mix(0.6, 0.3, t.a);
}
"""
	_facade_mat = ShaderMaterial.new()
	_facade_mat.shader = sh
	_facade_mat.set_shader_parameter("tex", ImageTexture.create_from_image(img))
	return _facade_mat


## Chain-link: a diamond wire mesh, alpha-scissored, world-projected (fences
## run along the highway, so the x/y projection is the one that shows).
func fence_mat() -> StandardMaterial3D:
	if _fence_mat:
		return _fence_mat
	var n := 32
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var a := (x + y) % 16 < 2 or ((x - y) % 16 + 16) % 16 < 2
			img.set_pixel(x, y, Color(0.66, 0.68, 0.68, 1.0) if a else Color(0.5, 0.5, 0.5, 0.0))
	img.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.3
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE / 0.6
	m.roughness = 0.6
	m.metallic = 0.4
	_fence_mat = m
	return m


# ================================================================== graffiti

## Spray-painted tags on a wall: `count` pieces spread along [0, length] from
## `o` along unit `t`, painted on the face whose outward normal is `n`, between
## heights y0..y1 above o. Blocky letters: a black outline, a fill color, now and
## then a silver/white throw-up bubble behind. All vertex-colored quads on m.
static func graffiti(m, o: Vector3, t: Vector3, n: Vector3, length: float, y0: float, y1: float, count: int,
		r: RandomNumberGenerator) -> void:
	var up := Vector3.UP
	var rect := func(u0: float, v0: float, u1: float, v1: float, eps: float, col: Color) -> void:
		var a: Vector3 = o + t * u0 + up * v0 + n * eps
		var b: Vector3 = o + t * u1 + up * v0 + n * eps
		var c: Vector3 = o + t * u1 + up * v1 + n * eps
		var d: Vector3 = o + t * u0 + up * v1 + n * eps
		m.quad(a, b, c, d, col, n)
	for k in count:
		var w := r.randf_range(2.0, 5.0)
		if w > length:
			w = length
		var u := r.randf_range(0.0, maxf(length - w, 0.0))
		var h := minf(r.randf_range(0.8, 1.6), y1 - y0)
		if h < 0.4:
			return
		var v := r.randf_range(y0, maxf(y1 - h, y0))
		var fill: Color = TAG_COLORS[r.randi() % TAG_COLORS.size()]
		var edge: Color = Color(0.05, 0.05, 0.06) if r.randf() < 0.7 else TAG_COLORS[r.randi() % TAG_COLORS.size()].darkened(0.5)
		if r.randf() < 0.35:     # a throw-up: bubble letters on a silver or white blob
			var blob := Color(0.8, 0.82, 0.85) if r.randf() < 0.5 else Color(0.95, 0.95, 0.93)
			rect.call(u - 0.15, v - 0.15, u + w + 0.15, v + h + 0.15, 0.03, edge)
			rect.call(u - 0.05, v - 0.05, u + w + 0.05, v + h + 0.05, 0.035, blob)
		var nl := maxi(int(w / 0.75), 2)
		var lw := w / nl
		for i in nl:
			var lu := u + i * lw + lw * 0.1
			var lu1 := lu + lw * 0.8
			var dv := r.randf_range(-0.12, 0.12)
			var lv := v + dv
			var lv1 := v + h * r.randf_range(0.8, 1.0) + dv
			var strokes := [[0.0, 0.0, 0.3, 1.0], [0.0, 0.75, 1.0, 1.0]]   # u0 v0 u1 v1 in the letter's box
			match r.randi() % 4:
				0: strokes = [[0.0, 0.0, 0.3, 1.0], [0.7, 0.0, 1.0, 1.0], [0.0, 0.4, 1.0, 0.6]]
				1: strokes = [[0.0, 0.0, 1.0, 0.25], [0.0, 0.75, 1.0, 1.0], [0.0, 0.0, 0.3, 1.0]]
				2: strokes = [[0.0, 0.75, 1.0, 1.0], [0.35, 0.0, 0.65, 1.0]]
				3: strokes = [[0.0, 0.0, 0.3, 1.0], [0.7, 0.0, 1.0, 1.0], [0.0, 0.0, 1.0, 0.25], [0.0, 0.75, 1.0, 1.0]]
			for sk in strokes:
				var a0 := lerpf(lu, lu1, sk[0])
				var a1 := lerpf(lu, lu1, sk[2])
				var b0 := lerpf(lv, lv1, sk[1])
				var b1 := lerpf(lv, lv1, sk[3])
				rect.call(a0 - 0.07, b0 - 0.07, a1 + 0.07, b1 + 0.07, 0.04, edge)
			for sk in strokes:
				rect.call(lerpf(lu, lu1, sk[0]), lerpf(lv, lv1, sk[1]), lerpf(lu, lu1, sk[2]), lerpf(lv, lv1, sk[3]), 0.045, fill)
		if r.randf() < 0.5:      # a scribbled tag underneath
			var tu := u + r.randf_range(0.0, w * 0.5)
			var tv := maxf(v - 0.35, y0)
			rect.call(tu, tv, tu + r.randf_range(0.8, 1.8), tv + 0.08, 0.05, Color(0.05, 0.05, 0.06))


# ================================================================== the city

## Blocks of buildings on both sides, cross streets between them. Call after
## everything else that registers tree blockers (ramps, roads, the hood, the
## dealership lot), before the trees.
func build_city() -> void:
	_hash_blockers()
	keep_out.append(nb.hood_rect.grow(12.0))
	keep_out.append(hw.dealership_rect.grow(10.0))
	for dl in hw.loop_dealers():                       # the dealerships round the loop (highway.gd LOOP_DEALERS)
		var lr: Rect2 = dl.rect                          # (+ open ground before them: you see the lot coming)
		keep_out.append(Rect2(lr.position.x - 25.0, lr.position.y - 25.0, lr.size.x + 25.0 + 90.0, lr.size.y + 50.0))
	keep_out.append(Rect2(-140, 120, 265, 230))       # the downtown tower field (StreetBuilder._skyline)
	var chunks := {}                                   # Vector2i(side, bin) -> [facade RoadMesh, detail RoadMesh]
	var mk := func(side: int, s: float) -> Array:
		var key := Vector2i(side, int(s / CHUNK))
		if not chunks.has(key):
			var f := RoadMesh.new()
			f.uvs = true
			chunks[key] = [f, RoadMesh.new()]
		return chunks[key]
	for side in [1, -1]:
		# the street grid: blocks 50-110 m long, 16 m cross streets
		var s := hw.s_portal_w + 10.0
		var blocks: Array = []
		while s < hw.s_portal_e - 20.0:
			var bl := rng.randf_range(50.0, 110.0)
			blocks.append([s, minf(s + bl, hw.s_portal_e - 10.0)])
			s += bl + 16.0
		for b in blocks:
			for row in ROWS:
				_fill(b[0], b[1], row, side, mk)
			var cs: float = b[1] + 8.0
			if cs < hw.s_portal_e - 12.0:
				var parts: Array = mk.call(side, cs)
				_cross_street(parts[1], cs, side)
	for key in chunks:
		var parts: Array = chunks[key]
		var tag := "%s%d" % ["S" if key.x > 0 else "N", key.y]
		if not parts[0].empty():
			parts[0].instance(nb.g_road, facade_mat(), "City_" + tag, 1500.0)
		if not parts[1].empty():     # roofs, tanks, fire escapes: too small to be worth their shadows
			parts[1].instance(nb.g_road, nb.road_mat, "CityDetail_" + tag, 1200.0).cast_shadow = \
					GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _pick(weights: Dictionary) -> String:
	var tot := 0.0
	for k in weights:
		tot += weights[k]
	var x := rng.randf() * tot
	for k in weights:
		x -= weights[k]
		if x <= 0.0:
			return k
	return weights.keys()[0]


## One row of one block: buildings side by side from s0 to s1.
func _fill(s0: float, s1: float, row: Array, side: int, mk: Callable) -> void:
	var s := s0
	while s < s1 - 6.0:
		var kind := _pick(row[2])
		var w := 0.0
		var depth := 0.0
		var storeys := 0
		match kind:
			"walkup":
				w = rng.randf_range(7.6, 12.5)
				depth = rng.randf_range(14.0, 18.0)
				storeys = [3, 4, 4, 5, 5, 6][rng.randi() % 6]
			"apartment":
				w = rng.randf_range(18.0, 32.0)
				depth = rng.randf_range(18.0, 24.0)
				storeys = rng.randi_range(6, 9)
			"projects":
				w = rng.randf_range(18.0, 42.0)
				depth = rng.randf_range(14.0, 18.0)
				storeys = rng.randi_range(12, 18)
			"warehouse":
				w = rng.randf_range(24.0, 55.0)
				depth = rng.randf_range(20.0, 30.0)
				storeys = rng.randi_range(2, 4)
			_:
				w = rng.randf_range(8.0, 20.0)          # a vacant lot
		w = minf(w, s1 - s)
		if w < 6.0:
			break
		var dn: float = row[0] + (0.0 if kind == "walkup" else rng.randf_range(0.0, 3.0))
		var df := minf(dn + depth, row[1])
		if kind != "vacant" and _free(s, s + w, dn, df, side):
			var parts: Array = mk.call(side, s + w / 2.0)
			_building(parts[0], parts[1], kind, s, s + w, dn, df, side, storeys)
			var c := hw.point(s + w / 2.0, side * (dn + df) / 2.0)
			nb._tree_blockers.append([Vector2(c.x, c.z), maxf(w, df - dn) * 0.6 + 2.0])
		s += w + (0.0 if kind == "walkup" and rng.randf() < 0.8 else rng.randf_range(1.0, 4.0))


## A building between stations s0..s1 and offsets dn..df (near face toward the highway).
func _building(fm, dm, kind: String, s0: float, s1: float, dn: float, df: float, side: int, storeys: int) -> void:
	var st := 3.1
	var bay := rng.randf_range(2.9, 3.5)
	var col: Color = BRICK[rng.randi() % BRICK.size()]
	match kind:
		"warehouse":
			st = rng.randf_range(4.2, 4.8)
			bay = rng.randf_range(4.6, 5.6)
			col = WAREHOUSE[rng.randi() % WAREHOUSE.size()]
		"projects":
			st = 2.8
			bay = rng.randf_range(3.0, 3.4)
			col = PROJECTS[rng.randi() % PROJECTS.size()]
	col = col.darkened(rng.randf_range(0.0, 0.1))
	var y0: float = GROUND_Y - 0.3
	var H := storeys * st
	var top := H + 0.6                                 # a parapet's worth of brick over the top floor
	var c := [hw.point(s0, side * dn, 0), hw.point(s1, side * dn, 0), hw.point(s1, side * df, 0), hw.point(s0, side * df, 0)]
	var ctr: Vector3 = (c[0] + c[1] + c[2] + c[3]) / 4.0
	var uoff := float(rng.randi() % 2) * 0.5
	for i in 4:
		var a: Vector3 = c[i]
		var b: Vector3 = c[(i + 1) % 4]
		var out := (a + b) / 2.0 - ctr
		out.y = 0.0
		var L := a.distance_to(b)
		var nbays := maxi(int(L / bay), 1)
		var u0 := uoff - (L - nbays * bay) / 2.0 / (2.0 * bay)
		var u1 := u0 + L / (2.0 * bay)
		var v0 := -y0 / (2.0 * st)
		var v1 := -top / (2.0 * st)
		fm.quad_uv(Vector3(a.x, y0, a.z), Vector3(b.x, y0, b.z), Vector3(b.x, top, b.z), Vector3(a.x, top, a.z),
				Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1), col, out, true)
	# roof, with a cornice on the walk-ups and apartments, a coping on the rest
	var roof := TAR.darkened(rng.randf_range(0.0, 0.25))
	if rng.randf() < 0.25:
		roof = Color(0.62, 0.62, 0.6)                  # silver roof paint
	dm.quad(c[0] + Vector3(0, top, 0), c[1] + Vector3(0, top, 0), c[2] + Vector3(0, top, 0), c[3] + Vector3(0, top, 0), roof, Vector3.UP)
	var corn := kind == "walkup" or kind == "apartment"
	var ccol: Color = [Color(0.25, 0.24, 0.23), Color(0.82, 0.8, 0.74), col.darkened(0.35), Color(0.45, 0.32, 0.22)][rng.randi() % 4]
	for i in 4:
		var a: Vector3 = c[i]
		var b: Vector3 = c[(i + 1) % 4]
		var out := ((a + b) / 2.0 - ctr)
		out.y = 0.0
		out = out.normalized()
		var along := (b - a).normalized()
		var p := 0.4 if corn else 0.08
		var hh := 0.5 if corn else 0.12
		var a2 := a + out * p - along * p
		var b2 := b + out * p + along * p
		var yt := top + (0.05 if corn else 0.08)
		dm.quad(a2 + Vector3(0, yt - hh, 0), b2 + Vector3(0, yt - hh, 0), b2 + Vector3(0, yt, 0), a2 + Vector3(0, yt, 0),
				ccol if corn else col.lightened(0.2), out)
		dm.quad(a + Vector3(0, yt - hh, 0), b + Vector3(0, yt - hh, 0), b2 + Vector3(0, yt - hh, 0), a2 + Vector3(0, yt - hh, 0),
				ccol.darkened(0.3), Vector3.DOWN)
		dm.quad(a + Vector3(0, yt, 0), b + Vector3(0, yt, 0), b2 + Vector3(0, yt, 0), a2 + Vector3(0, yt, 0),
				ccol.lightened(0.1) if corn else col.lightened(0.25), Vector3.UP)
	var fwd := hw.tangent((s0 + s1) / 2.0)
	var right := hw.right((s0 + s1) / 2.0) * side      # away from the highway
	var roof_at := func(fs: float, fd: float) -> Vector3:     # fractions of the footprint
		return c[0].lerp(c[1], fs).lerp(c[3].lerp(c[2], fs), fd) + Vector3(0, top, 0)
	# the stair bulkhead, a vent or two
	dm.obox(roof_at.call(rng.randf_range(0.2, 0.8), rng.randf_range(0.5, 0.8)), fwd, Vector3(2.6, 2.6, 3.2), col.darkened(0.25))
	for k in rng.randi_range(0, 2):
		dm.obox(roof_at.call(rng.randf_range(0.15, 0.85), rng.randf_range(0.15, 0.85)), fwd, Vector3(1.2, 0.9, 1.6),
				Color(0.6, 0.6, 0.6).darkened(rng.randf_range(0.0, 0.3)))
	if kind == "projects":     # the elevator penthouse
		dm.obox(roof_at.call(0.5, 0.5), fwd, Vector3(4.0, 3.5, 6.0), col.darkened(0.15))
	# the water tower
	var wt_odds := {"walkup": 0.35, "apartment": 0.7, "warehouse": 0.45, "projects": 0.0}
	if rng.randf() < wt_odds.get(kind, 0.0) and storeys >= 3:
		var big := kind != "walkup"
		_water_tower(dm, roof_at.call(rng.randf_range(0.3, 0.7), rng.randf_range(0.3, 0.7)), 2.4 if big else 1.8, 3.8 if big else 3.0)
	# fire escapes down the face toward the highway
	var face_bays := int(c[0].distance_to(c[1]) / bay)
	if (kind == "walkup" or kind == "apartment") and face_bays >= 2 and rng.randf() < 0.6:
		var nfe := 1 if kind == "walkup" else rng.randi_range(1, 2)
		for k in nfe:
			var b0 := rng.randi_range(0, face_bays - 2)
			var margin: float = (c[0].distance_to(c[1]) - face_bays * bay) / 2.0
			var along: Vector3 = (c[1] - c[0]).normalized()
			var p0: Vector3 = c[0] + along * (margin + b0 * bay)
			_fire_escape(dm, p0, along, -right, bay * 2.0, st, storeys)
	# a painted ghost sign on a warehouse wall that faces the traffic
	if kind == "warehouse" and _ghosts < GHOST_SIGNS.size() and storeys >= 3 and c[0].distance_to(c[1]) > 28.0 and rng.randf() < 0.6:
		var at: Vector3 = (c[0] + c[1]) / 2.0 + Vector3(0, H - st * 0.9, 0) - right * 0.06
		var l: Label3D = nb.fit_label(GHOST_SIGNS[_ghosts], at, st * 0.55, c[0].distance_to(c[1]) * 0.8,
				Color(0.93, 0.91, 0.84, 0.72), nb.yaw_of(-right), nb.g_dyn, 900.0)
		l.double_sided = false
		_ghosts += 1


## A wooden rooftop water tank on a steel stand: staves, hoops, a witch's-hat roof.
func _water_tower(m, base: Vector3, r: float, h: float) -> void:
	var legs := 2.6
	for q in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		var lp := base + Vector3(q.x, 0, q.y) * r * 0.62
		m.obox(lp, Vector3.FORWARD, Vector3(0.2, legs + 0.2, 0.2), IRON)
	var n := 8
	var wood: Color = [Color(0.48, 0.36, 0.25), Color(0.44, 0.39, 0.33), Color(0.36, 0.27, 0.2)][rng.randi() % 3]
	var y0 := base.y + legs
	# vertical bands: wood, a hoop, wood, a hoop, wood
	var bands := [[0.0, 0.46, wood], [0.46, 0.5, IRON], [0.5, 1.0, wood]]
	for k in n:
		var a0 := TAU * k / n
		var a1 := TAU * (k + 1) / n
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var stave: Color = wood.darkened(0.06 * (k % 3))
		for bd in bands:
			var rr: float = r + (0.04 if bd[2] == IRON else 0.0)
			var ya: float = y0 + h * bd[0]
			var yb: float = y0 + h * bd[1]
			var cc: Color = bd[2] if bd[2] == IRON else stave
			m.quad(Vector3(base.x, ya, base.z) + d0 * rr, Vector3(base.x, ya, base.z) + d1 * rr,
					Vector3(base.x, yb, base.z) + d1 * rr, Vector3(base.x, yb, base.z) + d0 * rr, cc, d0 + d1)
		# the conical roof
		var rim := Vector3(base.x, y0 + h, base.z)
		m.tri(rim + d0 * (r + 0.15), rim + d1 * (r + 0.15), rim + Vector3(0, r * 0.75, 0), Color(0.24, 0.21, 0.18),
				(d0 + d1).normalized() + Vector3(0, 1.2, 0))
	m.obox(Vector3(base.x, y0 + h + r * 0.75 - 0.05, base.z), Vector3.FORWARD, Vector3(0.12, 0.45, 0.12), IRON)


## Black iron fire escape: a landing per floor (from the second), railings, and
## the stairs zig-zagging between them. p0 = the face's ground point at its left end.
func _fire_escape(m, p0: Vector3, along: Vector3, out: Vector3, w: float, st: float, storeys: int) -> void:
	for f in range(1, storeys):
		var y := f * st + 0.05
		var a := p0 + Vector3(0, y, 0) + out * 0.02
		var b := a + along * w
		var ao := a + out * 1.1
		var bo := b + out * 1.1
		m.quad(a, b, bo, ao, IRON, Vector3.UP)
		m.quad(ao - Vector3(0, 0.08, 0), bo - Vector3(0, 0.08, 0), bo, ao, IRON, out)
		# the railing: a rail on top, a kick plate at the foot (one strip each), the corner posts
		for rh in [[0.88, 0.95], [0.0, 0.18]]:
			m.quad(ao + Vector3(0, rh[0], 0), bo + Vector3(0, rh[0], 0), bo + Vector3(0, rh[1], 0), ao + Vector3(0, rh[1], 0), IRON, out)
			m.quad(ao + Vector3(0, rh[0], 0), bo + Vector3(0, rh[0], 0), bo + Vector3(0, rh[1], 0), ao + Vector3(0, rh[1], 0), IRON, -out)
		for q in [ao, bo]:
			m.quad(q - along * 0.03, q + along * 0.03, q + along * 0.03 + Vector3(0, 0.95, 0), q - along * 0.03 + Vector3(0, 0.95, 0), IRON, out)
		# stairs up to the next landing, alternating direction
		if f < storeys - 1:
			var go_right := f % 2 == 1
			var s0 := (a if go_right else b) + out * 0.8
			var s1 := (b if go_right else a) + out * 0.8 + Vector3(0, st, 0)
			s0 = s0.lerp(s1, 0.08)
			s1 = s1.lerp(s0, 0.08)
			var wv := out * 0.3
			m.quad(s0 - wv, s1 - wv, s1 + wv, s0 + wv, IRON.lightened(0.05), out + Vector3.UP)
	# the drop ladder under the lowest landing
	var lp := p0 + along * (w * 0.8) + out * 0.9
	m.quad(lp + Vector3(0, 1.4, 0), lp + along * 0.5 + Vector3(0, 1.4, 0), lp + along * 0.5 + Vector3(0, st, 0), lp + Vector3(0, st, 0),
			IRON, out)


## A side street running away from the highway between two blocks: asphalt
## with sidewalks, from the right-of-way fence out past the last row, and a
## car or two parked at the curb near the highway end (plenty of them cabs).
func _cross_street(m, s: float, side: int) -> void:
	var y: float = GROUND_Y + 0.03
	var d := 25.0
	while d < 150.0:
		var d1 := d + 10.0
		var mid := hw.point(s, side * (d + 5.0))
		if clear_at(mid, 0.0):
			if d < 60.0 and rng.randf() < 0.55:
				var curb := -4.2 if rng.randf() < 0.5 else 4.2
				var model: String = "TCar_Taxi" if rng.randf() < 0.45 else PARKED[rng.randi() % PARKED.size()]
				var at := hw.point(s + curb, side * (d + 5.0), y)
				var along := hw.right(s) * side * (1.0 if curb > 0.0 else -1.0)      # right-hand parking
				nb.parked_car(model, at, nb.yaw_of(along))
				nb.solid(Vector3(2.0, 1.6, 4.8), at + Vector3(0, 0.8, 0), nb.yaw_of(along))
			for st in [[-8.0, -5.5, Color(0.5, 0.49, 0.47), 0.1], [-5.5, 5.5, Color(0.23, 0.23, 0.24), 0.0],
					[5.5, 8.0, Color(0.5, 0.49, 0.47), 0.1]]:
				var yy: float = y + st[3]
				m.quad(hw.point(s + st[0], side * d, yy), hw.point(s + st[1], side * d, yy), hw.point(s + st[1], side * d1, yy),
						hw.point(s + st[0], side * d1, yy), st[2], Vector3.UP)
			# a faded center line
			m.quad(hw.point(s - 0.08, side * d, y + 0.01), hw.point(s + 0.08, side * d, y + 0.01),
					hw.point(s + 0.08, side * (d1 - 4.0), y + 0.01), hw.point(s - 0.08, side * (d1 - 4.0), y + 0.01),
					Color(0.7, 0.6, 0.25), Vector3.UP)
		d = d1


# ================================================================== billboards

## A monopole billboard behind the wall at station s on `side`, angled to face
## the traffic heading `facing` (+1 eastbound). lines: [[text, cap height, color], ...]
func billboard(s: float, side: int, facing: int, bg: Color, lines: Array) -> void:
	var d := side * 28.0
	var tries := 0
	while tries < 8 and not (clear_at(hw.point(s, d), 3.0) and not ramp_near(hw.point(s, d), 20.0)):
		s += 12.0 * facing * -1.0
		tries += 1
	if tries >= 8:
		return
	var m := RoadMesh.new()
	var p := hw.point(s, d, GROUND_Y)
	var t := hw.tangent(s)
	var toward := -hw.right(s) * side                          # from the pole toward the highway
	var n := (-t * facing * 0.82 + toward * 0.57).normalized()  # the face's normal
	var r := (-n).cross(Vector3.UP).normalized()               # the reader's right
	var W := 13.0
	var Hh := 4.8
	var y0 := 10.0
	var steel := Color(0.35, 0.36, 0.37)
	m.obox(p, t, Vector3(0.9, y0 + 0.5, 0.9), steel, true)
	var c := p + Vector3(0, y0, 0)
	# the back frame and the catwalk
	m.obox(c - n * 0.35 - Vector3(0, 0.3, 0), r, Vector3(0.6, Hh + 0.6, W + 0.4), Color(0.28, 0.29, 0.3))
	m.obox(c + n * 0.5 - Vector3(0, 0.35, 0), r, Vector3(1.0, 0.1, W), steel)
	var face := func(u0: float, v0: float, u1: float, v1: float, eps: float, col: Color) -> void:
		m.quad(c + r * u0 + Vector3(0, v0, 0) + n * eps, c + r * u1 + Vector3(0, v0, 0) + n * eps,
				c + r * u1 + Vector3(0, v1, 0) + n * eps, c + r * u0 + Vector3(0, v1, 0) + n * eps, col, n)
	face.call(-W / 2 - 0.2, -0.2, W / 2 + 0.2, Hh + 0.2, 0.0, Color(0.92, 0.92, 0.9))
	face.call(-W / 2, 0.0, W / 2, Hh, 0.02, bg)
	face.call(-W / 2, 0.0, W / 2, 0.35, 0.03, bg.darkened(0.35))
	for k in 4:          # the lamps along the catwalk
		var lp := c + r * lerpf(-W / 2 + 1.5, W / 2 - 1.5, k / 3.0) + n * 0.9 - Vector3(0, 0.2, 0)
		m.bar(lp, lp + n * 0.4 + Vector3(0, 0.4, 0), 0.08, 0.08, steel)
	# (its own draw: in the far group's merge every billboard would land in one batch, the vertices
	# being world space, and that batch's range is measured from the middle of the map)
	m.instance(nb.g_far, nb.road_mat, "Billboard", 1200.0).set_meta("no_batch", true)
	# the copy, top to bottom
	var tot := 0.0
	for ln in lines:
		tot += float(ln[1]) * 1.45
	var y := Hh / 2.0 + tot / 2.0
	for ln in lines:
		var ch := float(ln[1])
		y -= ch * 1.45 / 2.0
		var l: Label3D = nb.fit_label(ln[0], c + Vector3(0, y, 0) + n * 0.06, ch, W - 1.0, ln[2], nb.yaw_of(n), nb.g_dyn, 900.0)
		l.double_sided = false
		y -= ch * 1.45 / 2.0
	nb._tree_blockers.append([Vector2(p.x, p.z), 8.0])
