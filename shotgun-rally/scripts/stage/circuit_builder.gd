extends "res://scripts/stage/loop_builder.gd"
## Builds Track Mode's circuit (CircuitGen) into the world: the track (asphalt to the white
## lines, the lines, the start/finish line, the grid boxes), the kerbs outside the white lines
## (red and white, a touch proud), the run-off (grass, gravel traps, asphalt) out to the
## barriers (armco on posts, TecPro-style tyre walls, concrete walls with debris fencing), the
## pit lane behind the pit wall (its taper in and out, the limiter lines, twenty boxes, the
## garages and the paddock behind them), the start-light gantry over the line, sector and DRS
## boards, distance boards before the big stops, grandstands, marshal posts, floodlight towers
## (lit at night: StreetLamps), the land rolling away to the ridge's hills and the forest on it.
##
## The same chunked, real-material geometry as the highway loop (LoopBuilder: its materials,
## its chunks drawn within a range of the camera, every surface a tyre can touch saying what it
## is with meta "surface"); the land is one height field (_land_y) the run-off, the ground and
## the far land all sample, so they meet without steps.

const CircuitGen = preload("res://scripts/stage/circuit_gen.gd")
const Biomes = preload("res://scripts/stage/biomes.gd")
const Graphics = preload("res://scripts/render/graphics.gd")

const CIRCUIT_STEPS := [["_environment", "Checking the weather"], ["_track", "Laying the asphalt"],
	["_kerbs", "Painting the kerbs"], ["_runoff", "Raking the gravel traps"], ["_land", "Shaping the ridge"],
	["_barriers", "Stacking the tyre walls"], ["_pits", "Opening the garages"], ["_grid_marks", "Painting the grid"],
	["_gantries", "Hanging the start lights"], ["_stands", "Building the grandstands"], ["_trackside", "Posting the marshals"], ["_pit_props", "Setting up the pit crews"],
	["_floodlights", "Raising the floodlights"], ["_forest", "Planting the ridge"], ["_finish", "Opening the circuit"]]
const LAND_REACH := 170.0            # m: the ground ribbons go this far from the track (the far land beyond)
const LAND_ROWS := [0.0, 3.0, 8.0, 16.0, 28.0, 44.0, 66.0, 95.0, 130.0, 170.0]
const FENCE_H := 3.2                 # debris fencing on the concrete walls
const PIT_SPAN_PAD := 0.0            # m round the pit lane's ends that are the pits' too (the wall leads into the taper)

var cst: CircuitGen                  # the circuit (st, typed as the parent's LoopGen)
var start_lights: Node3D             # the gantry's lights (the session lights them: set_lights)
var _light_bulbs: Array = []         # [[MeshInstance3D red, MeshInstance3D off]] x 5
var _pts_grid := {}                  # 60 m cells -> sample indices (every 3rd): the land's nearest-track lookups
var _room := [PackedFloat32Array(), PackedFloat32Array()]   # per sample: how far out the ground ribbon may go (left, right)
var stand_count := 0
var marshal_count := 0
var floodlight_count := 0


func build(stage) -> void:
	_prepare(stage)
	for step in CIRCUIT_STEPS:
		call(step[0])


func build_async(stage, report: Callable) -> void:
	_prepare(stage)
	for i in CIRCUIT_STEPS.size():
		report.call(float(i) / CIRCUIT_STEPS.size(), CIRCUIT_STEPS[i][1])
		await get_tree().process_frame
		if not is_inside_tree():
			return
		call(CIRCUIT_STEPS[i][0])
	report.call(1.0, "")


func _prepare(stage) -> void:
	st = stage
	cst = stage
	_rng.seed = hash([st.seed_used, "circuit"])
	if ResourceLoader.exists(WM_PATH):
		_wm = load(WM_PATH)
		_wm.ground_style = ""
		_wm.asphalt_style = ""
	var n: int = st._n
	for i in range(0, n, 3):
		var key := Vector2i(floori(st.pts[i].x / 60.0), floori(st.pts[i].z / 60.0))
		if not _pts_grid.has(key):
			_pts_grid[key] = []
		_pts_grid[key].append(i)
	# how far each side's ground may reach: until it would meet another part of the lap's
	for side in 2:
		_room[side].resize(n)
	for i in n:
		for side in 2:
			var sg := -1.0 if side == 0 else 1.0
			var reach := LAND_REACH
			var s := i * st.STEP
			var e := absf(_barrier_d(s, int(sg)))
			var dd := e + 6.0
			while dd < LAND_REACH:
				var p := st.point_at(s) + st.right_at(s) * sg * dd
				var near := _nearest_far(p, i, 140.0)
				if near.x >= 0.0 and near.y < dd + 4.0:
					reach = maxf(e + 2.0, (dd + near.y) * 0.5 - 4.0)
					break
				dd += 6.0
			_room[side][i] = reach
	# (eased: no ragged edge where two parts of the lap come close)
	for side in 2:
		var raw: PackedFloat32Array = _room[side].duplicate()
		for i in n:
			var m := raw[i]
			for k in range(-6, 7):
				m = minf(m, raw[posmod(i + k, n)] + absf(k) * 4.0)
			_room[side][i] = m


## The nearest track sample to p more than `apart` m round the lap from sample i: (index, distance), or (-1, INF).
func _nearest_far(p: Vector3, i: int, apart: float) -> Vector2:
	var best := Vector2(-1.0, INF)
	var cx := floori(p.x / 60.0)
	var cz := floori(p.z / 60.0)
	var n: int = st._n
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			for j in _pts_grid.get(Vector2i(cx + dx, cz + dz), []):
				var sep: int = mini(posmod(j - i, n), posmod(i - j, n))
				if sep * st.STEP < apart:
					continue
				var d := Vector2(p.x - st.pts[j].x, p.z - st.pts[j].z).length()
				if d < best.y:
					best = Vector2(j, d)
	return best


# ── materials ─────────────────────────────────────────────────────────────

const CIRCUIT_WM := {"asphalt": ["asphalt", {"uv": true, "uv_along": "x", "tint": Color(0.44, 0.45, 0.48)}],
	"pitlane": ["asphalt", {"uv": true, "uv_along": "x", "tint": Color(0.56, 0.57, 0.6)}],
	"runoff": ["asphalt", {"uv": true, "uv_along": "x", "tint": Color(0.5, 0.56, 0.62)}],
	"paint": ["road_paint", {"vertex": "colour", "tint": Color(0.85, 0.85, 0.83)}],
	# (the walls painted a light grey: the bare photo read as tan sandstone down the pit wall)
	"concrete": ["concrete", {"vertex": "colour", "tint": Color(0.74, 0.75, 0.76)}], "steel": ["steel", {"tint": Color(0.7, 0.72, 0.75)}],
	"grass": ["grass", {"uv": true}], "gravel": ["gravel", {"uv": true}], "terrain": ["terrain", {}],
	"post_lamp": ["street_lamp_head", {}], "building": ["buildings", {}], "glass": ["glass_windows", {}]}


func _mat(key: String) -> Material:
	if _mats.has(key):
		return _mats[key]
	var m: Material = null
	if _wm and CIRCUIT_WM.has(key) and _wm.has_method(CIRCUIT_WM[key][0]):
		m = _wm.call(CIRCUIT_WM[key][0], CIRCUIT_WM[key][1])
	if m == null:
		m = _fallback(key)
	_mats[key] = m
	return m


func _fallback(key: String) -> Material:
	if key == "garage_bay":
		var bay := ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = BAY_SHADER
		bay.shader = sh
		var p: Dictionary = cst.pit
		bay.set_shader_parameter("width", (float(p.s_box1) - float(p.s_box0)) / float(p.boxes) * 0.82)
		return bay
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	match key:
		"kerb":
			m.albedo_color = Color(1, 1, 1)
			m.roughness = 0.55
		"pitlane", "runoff":
			m.albedo_color = Color(0.3, 0.31, 0.33) if key == "pitlane" else Color(0.28, 0.32, 0.36)
			m.albedo_texture = _noise_tex(0.06, false, 7)
			m.roughness = 0.9
			m.uv1_scale = Vector3(0.25, 0.25, 1.0)
		"grass":
			m.albedo_color = Color(0.3, 0.46, 0.2)
			m.albedo_texture = _noise_tex(0.08, false, 11, 512, 0.7)
			m.roughness = 1.0
			m.uv1_scale = Vector3(0.2, 0.2, 1.0)
		"gravel":
			m.albedo_color = Color(0.72, 0.66, 0.52)
			m.albedo_texture = _noise_tex(0.5, false, 12, 512, 0.6)
			m.normal_enabled = true
			m.normal_texture = _noise_tex(0.6, true, 13)
			m.roughness = 1.0
			m.uv1_scale = Vector3(0.5, 0.5, 1.0)
		"tecpro":
			m.roughness = 0.6                            # (the block's colour is the vertex colour: red / white / blue)
		"tyre_rubber":
			m.albedo_color = Color(0.06, 0.06, 0.065)
			m.roughness = 0.85
		"fence":
			m.albedo_color = Color(0.55, 0.57, 0.6, 0.38)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.metallic = 0.6
			m.roughness = 0.4
		"seat":
			m.roughness = 0.55                           # (seat rows: the vertex colour)
		"garage_dark":
			m.albedo_color = Color(0.05, 0.05, 0.06)
			m.roughness = 0.9
		"board":
			m.albedo_color = Color(0.95, 0.95, 0.93)
			m.roughness = 0.6
		"light_red":
			m.albedo_color = Color(1.0, 0.08, 0.04)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.05, 0.02)
			m.emission_energy_multiplier = 6.0
		"light_off":
			m.albedo_color = Color(0.12, 0.03, 0.03)
			m.roughness = 0.3
		"light_green":
			m.albedo_color = Color(0.1, 1.0, 0.25)
			m.emission_enabled = true
			m.emission = Color(0.1, 1.0, 0.25)
			m.emission_energy_multiplier = 5.0
		"marshal":
			m.albedo_color = Color(0.95, 0.45, 0.08)
			m.roughness = 0.6
		"roof":
			m.albedo_color = Color(0.82, 0.84, 0.86)
			m.metallic = 0.4
			m.roughness = 0.45
		"brand":
			m.albedo_color = Color(0.85, 0.12, 0.12)
			m.roughness = 0.5
		_:
			return super._fallback(key)
	return m


## A pit garage's open door: the room behind it drawn by the camera's ray (interior mapping: no
## geometry, a few dozen instructions a pixel on 20 small quads): a light grey back wall and sides,
## the team's colour in a band round them (the vertex colour), cabinets along the bottom, a grey
## floor, strip lights across the ceiling; darker toward the back. Lit from inside (unshaded), so
## it glows a little at night. The other faces of the door's thin box: dark. (It was a flat black
## slab: twenty black holes down the pit lane.)
const BAY_SHADER := """
shader_type spatial;
render_mode unshaded, cull_back;
uniform float width = 8.0;
uniform float height = 4.4;
uniform float depth = 12.0;
uniform float bright = 1.0;
varying vec3 wpos;
varying vec3 wnrm;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
vec3 wall(vec2 p, vec3 team) {
	vec3 c = vec3(0.5, 0.51, 0.52);
	c = mix(c, vec3(0.1, 0.105, 0.11), step(p.y, 1.05));                    // cabinets
	c = mix(c, vec3(0.16), step(abs(fract(p.x * 0.55) - 0.5), 0.012) * step(p.y, 1.05));
	c = mix(c, team, step(abs(p.y - 2.35), 0.17));                          // the team's band
	return c;
}
void fragment() {
	vec3 n = normalize(wnrm);
	vec3 col = vec3(0.025);
	if (abs(n.y) < 0.5) {
		vec3 dp1 = dFdx(wpos);
		vec3 dp2 = dFdy(wpos);
		vec2 du1 = dFdx(UV);
		vec2 du2 = dFdy(UV);
		float det = du1.x * du2.y - du2.x * du1.y;
		vec3 T = normalize((dp1 * du2.y - dp2 * du1.y) * sign(det));
		vec3 rw = normalize(wpos - CAMERA_POSITION_WORLD);
		vec3 rd = vec3(dot(rw, T), rw.y, max(dot(rw, -n), 1e-3));
		vec3 ro = vec3(clamp(UV.x, 0.0, width), clamp(UV.y, 0.0, height), 0.0);
		float tx = ((rd.x > 0.0 ? width : 0.0) - ro.x) / (rd.x + (rd.x >= 0.0 ? 1e-5 : -1e-5));
		float ty = ((rd.y > 0.0 ? height : 0.0) - ro.y) / (rd.y + (rd.y >= 0.0 ? 1e-5 : -1e-5));
		float tz = depth / rd.z;
		float t = min(tx, min(ty, tz));
		vec3 h = ro + rd * t;
		vec3 team = pow(COLOR.rgb, vec3(2.2));
		if (t == tz) {
			col = wall(vec2(h.x, h.y), team);
		} else if (t == tx) {
			col = wall(vec2(h.z, h.y), team) * 0.85;
		} else if (rd.y < 0.0) {
			col = vec3(0.3, 0.31, 0.33) + 0.12 * smoothstep(0.3, 0.0, abs(fract(h.z / 3.0) - 0.5));   // the lights in the floor
		} else {
			col = mix(vec3(0.16), vec3(4.0), step(abs(fract(h.z / 3.0) - 0.5), 0.06) * step(0.6, h.x) * step(h.x, width - 0.6));
		}
		col *= mix(1.0, 0.5, h.z / depth) * mix(0.75, 1.0, h.y / height);
	}
	ALBEDO = col * bright;
}
"""


# ── shapes on the track ───────────────────────────────────────────────────

## The barrier's d on `side` at s (signed), or the track's edge + 10 m if none.
func _barrier_d(s: float, side: int) -> float:
	var b: Dictionary = cst.barrier_at(s, side)
	if b.is_empty():
		return side * (cst.half_at(s) + 10.0)
	return float(b.d)


## In the pit straight's pit-side stretch (the pits' own ground, no run-off or barrier there).
func _pit_side(s: float, side: int) -> bool:
	if side < 0:
		return false
	var x: float = cst.around_line(s)
	return x >= float(cst.pit.s_in0) - PIT_SPAN_PAD and x <= float(cst.pit.s_out1) + PIT_SPAN_PAD


## The land's height at x, z: near the track, its own height falling away gently (drainage),
## blended into the ridge's land (CircuitGen.land_at) further out. One field for the run-off's
## outer parts, the ground ribbons and the far land.
func _land_y(x: float, z: float) -> float:
	var cx := floori(x / 60.0)
	var cz := floori(z / 60.0)
	var wsum := 0.0
	var ysum := 0.0
	var dmin := INF
	for dx in range(-4, 5):
		for dz in range(-4, 5):
			for j in _pts_grid.get(Vector2i(cx + dx, cz + dz), []):
				var p: Vector3 = st.pts[j]
				var d := Vector2(x - p.x, z - p.z).length()
				dmin = minf(dmin, d)
				var w := 1.0 / pow(d * d + 36.0, 2.0)
				ysum += w * (p.y - maxf(0.0, d - cst.half[j]) * 0.012)
				wsum += w
	var far: float = cst.land_at(x, z)
	if wsum <= 0.0:
		return far
	var near := ysum / wsum
	return lerpf(near, minf(far, near + 60.0), smoothstep(LAND_REACH, LAND_REACH + 260.0, dmin))


## A point beyond the track's edge on `side` at s, d m out from the centreline: on the land.
func _out_pt(s: float, d: float) -> Vector3:
	var p: Vector3 = st.point_at(s) + st.right_at(s) * d
	return Vector3(p.x, _land_y(p.x, p.z), p.z)


## The run-off's surface at (s, d): from the track's edge height (with its camber) easing into
## the land over the first 6 m.
func _apron_pt(s: float, d: float) -> Vector3:
	var h: float = cst.half_at(s)
	var side := signf(d)
	var edge: Vector3 = st.world_at(s, side * h)
	var p: Vector3 = st.point_at(s) + st.right_at(s) * d
	var out := absf(d) - h
	var y := edge.y - out * 0.012
	var land := _land_y(p.x, p.z)
	return Vector3(p.x, lerpf(y, land, smoothstep(2.0, 8.0, out)), p.z)


# ── the track ─────────────────────────────────────────────────────────────

func _track() -> void:
	var n: int = st._n
	var step: float = st.STEP
	for i in n:
		var s := i * step
		var rows := []
		var ds := PackedFloat32Array()
		for k in 2:
			var h: float = cst.half[i + k]
			ds = PackedFloat32Array([-h, -h * 0.5, 0.0, h * 0.5, h])
			var row := PackedVector3Array()
			for d in ds:
				row.append(st.world_at(s + k * step, d))
			rows.append(row)
		_buf(i, "asphalt").ribbon(rows[0], rows[1], s, s + step, ds, Color.WHITE)
		_body(i, "asphalt").ribbon(rows[0], rows[1], s, s + step, ds, Color.WHITE, true)
		# the white lines: track limits, 15 cm, just inside the edge; painted 1 cm up
		for side in [-1.0, 1.0]:
			_strip(i, side * (cst.half[i] - 0.17), side * (cst.half[i] - 0.02), 0.012, "paint", Color(1, 1, 1))


## A painted strip on the track between d0 and d1 (signed) at sample i, lifted `lift`.
func _strip(i: int, d0: float, d1: float, lift: float, key: String, col: Color, s_a := -1.0, s_b := -1.0) -> void:
	var s0 := i * st.STEP if s_a < 0.0 else s_a
	var s1 := s0 + st.STEP if s_b < 0.0 else s_b
	var a := PackedVector3Array([st.world_at(s0, minf(d0, d1)) + Vector3.UP * lift, st.world_at(s0, maxf(d0, d1)) + Vector3.UP * lift])
	var b := PackedVector3Array([st.world_at(s1, minf(d0, d1)) + Vector3.UP * lift, st.world_at(s1, maxf(d0, d1)) + Vector3.UP * lift])
	_buf(i, key).ribbon(a, b, s0, s1, PackedFloat32Array([minf(d0, d1), maxf(d0, d1)]), col)


# ── kerbs ─────────────────────────────────────────────────────────────────

## Each kerb: red and white stripes a metre long, from the white line out (w m), a gentle
## crown (4 cm), solid ("kerb" to the tyres); the apex and chicane ones a touch higher.
func _kerbs() -> void:
	var n: int = st._n
	for kb in cst.kerbs:
		var side := float(kb.side)
		var w := float(kb.w)
		var rise := 0.06 if str(kb.kind) in ["apex", "chicane"] else 0.04
		var s0 := float(kb.s0)
		var s1 := float(kb.s1)
		if s1 < s0:
			s1 += st.length
		var s := s0
		var stripe := 0
		while s < s1 - 0.01:
			var e := minf(s + 1.0, s1)
			var i := int(st.wrap_s(s) / st.STEP) % n
			var col := Color(0.82, 0.08, 0.06) if stripe % 2 == 0 else Color(0.95, 0.95, 0.93)
			var rows := []
			var ds := PackedFloat32Array()
			for sk in [s, e]:
				var h: float = cst.half_at(sk)
				var row := PackedVector3Array()
				ds = PackedFloat32Array()
				for f in [0.0, 0.35, 0.7, 1.0]:
					var d: float = side * (h + w * f)
					var lift: float = rise * sin(PI * clampf(f * 1.15, 0.0, 1.0)) + 0.005
					row.append(st.world_at(sk, d) + Vector3.UP * lift)
					ds.append(d)
				if side < 0.0:
					row.reverse()
					ds.reverse()
				rows.append(row)
			_buf(i, "kerb").ribbon(rows[0], rows[1], s, e, ds, col)
			_body(i, "kerb").ribbon(rows[0], rows[1], s, e, ds, Color.WHITE, true)
			s = e
			stripe += 1


# ── run-off ───────────────────────────────────────────────────────────────

## Out from the white line (or the kerb's outer edge) to the barrier: grass, a gravel trap or
## asphalt run-off, each solid with its surface. The pit straight's pit side is the pits'.
func _runoff() -> void:
	var n: int = st._n
	var step: float = st.STEP
	for i in n:
		var s := i * step
		for side in [-1, 1]:
			if _pit_side(s, side) or _pit_side(s + step, side):
				continue
			var r: Dictionary = cst.runoff_at(s + step * 0.5, side)
			var kind := str(r.get("kind", "grass"))
			var rows := []
			var ds := PackedFloat32Array()
			for k in 2:
				var sk := s + k * step
				var h: float = cst.half_at(sk)
				var inner := h + cst.kerb_w(sk, side)
				var outer := absf(_barrier_d(sk, side))
				ds = PackedFloat32Array()
				var row := PackedVector3Array()
				for f in [0.0, 0.12, 0.3, 0.55, 0.8, 1.0]:
					var d: float = side * lerpf(inner, outer, f)
					row.append(_apron_pt(sk, d))
					ds.append(d)
				if side < 0:
					row.reverse()
					ds.reverse()
				rows.append(row)
			var key := "runoff" if kind == "asphalt" else ("gravel" if kind == "gravel" else "terrain")
			if key == "terrain":
				# (the grass: the land's own material, mown a touch greener by the track)
				var ca := PackedColorArray()
				var cb := PackedColorArray()
				for q in rows[0].size():
					ca.append(_land_col(rows[0][q], 0.0).lerp(Color(0.25, 0.36, 0.14), 0.4))
					cb.append(_land_col(rows[1][q], 0.0).lerp(Color(0.25, 0.36, 0.14), 0.4))
				_buf(i, key).ribbon(rows[0], rows[1], s, s + step, ds, Color.WHITE, false, ca, cb)
			else:
				_buf(i, key).ribbon(rows[0], rows[1], s, s + step, ds, Color.WHITE)
			_body(i, "asphalt" if kind == "asphalt" else kind).ribbon(rows[0], rows[1], s, s + step, ds, Color.WHITE, true)


# ── the land ──────────────────────────────────────────────────────────────

## Behind each barrier the ground rolls out to where the far land takes over (or to halfway
## to the next part of the lap); beyond, the far land to the horizon.
func _land() -> void:
	var n: int = st._n
	var step: float = st.STEP
	for i in range(0, n, 2):
		var s := i * step
		var s2 := s + step * 2.0
		for side in [-1, 1]:
			var si := 0 if side < 0 else 1
			var rows := []
			var cols := []
			var ds := PackedFloat32Array()
			for sk in [s, s2]:
				var j := int(st.wrap_s(sk) / step) % n
				var base := absf(_barrier_d(sk, side))
				if _pit_side(sk, side):
					base = float(cst.pit.garage_d) + 42.0
				var reach: float = maxf(base + 2.0, _room[si][j])
				var row := PackedVector3Array()
				var col := PackedColorArray()
				ds = PackedFloat32Array()
				for r in LAND_ROWS:
					var d: float = side * minf(base + r, maxf(reach, base + 2.0))
					var p := _out_pt(sk, d)
					row.append(p)
					col.append(_land_col(p, 0.0))
					ds.append(d)
				if side < 0:
					row.reverse()
					col.reverse()
					ds.reverse()
				rows.append(row)
				cols.append(col)
			_buf(i, "terrain").ribbon(rows[0], rows[1], s, s2, ds, Color.WHITE, false, cols[0], cols[1])
			_body(i, "grass").ribbon(rows[0], rows[1], s, s2, ds, Color.WHITE, true)
	_far_ground()


## The far land: a grid round the circuit out to 3.5 km, on the same height field, dropped
## under the ribbons near the track (they're drawn over it there).
func _far_ground() -> void:
	var cx := 0.0
	var cz := 0.0
	for p in st.pts:
		cx += p.x
		cz += p.z
	cx /= st.pts.size()
	cz /= st.pts.size()
	var half_size := 3600.0
	var cell := 60.0
	var nx := int(half_size * 2.0 / cell) + 1
	var hs := PackedFloat32Array()
	hs.resize(nx * nx)
	var gb := GeoBuf.new()
	for zi in nx:
		for xi in nx:
			var x := cx - half_size + xi * cell
			var z := cz - half_size + zi * cell
			var y := _land_y(x, z)
			# (under the ribbons near the track: they cover it; beyond, the field itself)
			var near := _nearest_far(Vector3(x, 0, z), -100000, 0.0)
			if near.y < LAND_REACH + 40.0:
				y -= 2.5 * (1.0 - smoothstep(LAND_REACH, LAND_REACH + 40.0, near.y))
			hs[zi * nx + xi] = y
	for zi in nx - 1:
		for xi in nx - 1:
			var x0 := cx - half_size + xi * cell
			var z0 := cz - half_size + zi * cell
			var a := Vector3(x0, hs[zi * nx + xi], z0)
			var b := Vector3(x0 + cell, hs[zi * nx + xi + 1], z0)
			var c := Vector3(x0 + cell, hs[(zi + 1) * nx + xi + 1], z0 + cell)
			var d := Vector3(x0, hs[(zi + 1) * nx + xi], z0 + cell)
			var col := _land_col(a, 0.0)
			gb.quad(a, d, c, b, Vector2(x0, z0), Vector2(x0, z0 + cell), Vector2(x0 + cell, z0 + cell), Vector2(x0 + cell, z0), col)
	var mi := MeshInstance3D.new()
	mi.name = "FarLand"
	mi.mesh = gb.mesh()
	mi.material_override = _mat("terrain")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _land_col(p: Vector3, _slope: float) -> Color:
	# (the ridge's meadows: greener low down, drier up the hills; mottled by a little noise)
	var g := clampf((p.y + 4.0) / 90.0, 0.0, 1.0)
	var n := 0.5 + 0.5 * sin(p.x * 0.013 + cos(p.z * 0.011) * 2.0)
	return Color(0.26 + 0.07 * g, 0.34 - 0.02 * g, 0.15, 1.0).lerp(Color(0.31, 0.36, 0.18), n * 0.35)


# ── barriers ──────────────────────────────────────────────────────────────

## Along each side's barrier ranges: armco (two rails on posts), a TecPro-style wall of
## red / white / blue blocks where a car would arrive fast, or a concrete wall with debris
## fencing (the pit straight). All solid ("barrier"). The pit side of the pit straight has the
## pit wall instead (built with the pits).
func _barriers() -> void:
	var n: int = st._n
	var step: float = st.STEP
	for i in n:
		var s := i * step
		for side in [-1, 1]:
			if _pit_side(s, side):
				continue
			var b: Dictionary = cst.barrier_at(s + step * 0.5, side)
			if b.is_empty():
				continue
			var kind := str(b.kind)
			var d0 := _barrier_d(s, side)
			var d1 := _barrier_d(s + step, side)
			var p0 := _out_pt(s, d0)
			var p1 := _out_pt(s + step, d1)
			match kind:
				"tyres":
					_tecpro(i, p0, p1, side, s)
				"wall":
					_wall(i, p0, p1, side, s, true)
				_:
					_armco(i, p0, p1, side, s)


func _seg_basis(p0: Vector3, p1: Vector3) -> Basis:
	var f := (p1 - p0)
	f.y = 0.0
	f = f.normalized()
	var r := f.cross(Vector3.UP).normalized()
	return Basis(r, Vector3.UP, -f)


## Armco: two W-beams (at 0.5 and 0.75 m) on a post every 4 m; solid as a 0.8 m wall.
func _armco(i: int, p0: Vector3, p1: Vector3, side: int, s: float) -> void:
	var bas := _seg_basis(p0, p1)
	var mid := (p0 + p1) * 0.5
	var seg_len := p0.distance_to(p1) + 0.02
	for hgt in [0.5, 0.78]:
		_buf(i, "steel").box(mid + Vector3.UP * hgt, Vector3(0.06, 0.3, seg_len), bas)
	if fmod(s, 4.0) < st.STEP:
		_buf(i, "steel").box(p0 + Vector3.UP * 0.45 + bas.x * side * 0.1, Vector3(0.12, 0.95, 0.12), bas)
	_body(i, "barrier").box(mid + Vector3.UP * 0.45, Vector3(0.25, 0.95, seg_len), bas, Color.WHITE, true)


## A TecPro-style wall: 1.5 m blocks, 1.1 m high, alternating red, white and blue; solid.
func _tecpro(i: int, p0: Vector3, p1: Vector3, side: int, s: float) -> void:
	var bas := _seg_basis(p0, p1)
	var mid := (p0 + p1) * 0.5 + bas.x * side * 0.5
	var seg_len := p0.distance_to(p1) + 0.02
	var k := int(st.wrap_s(s) / 2.0)
	var col: Color = [Color(0.8, 0.1, 0.08), Color(0.94, 0.94, 0.92), Color(0.1, 0.25, 0.7)][k % 3]
	_buf(i, "tecpro").box(mid + Vector3.UP * 0.55, Vector3(1.0, 1.1, seg_len - 0.06), bas, col)
	_body(i, "barrier").box(mid + Vector3.UP * 0.55, Vector3(1.0, 1.1, seg_len), bas, Color.WHITE, true)


## A concrete wall (1.1 m) and, if asked, debris fencing on top (posts every 4 m, mesh panels).
func _wall(i: int, p0: Vector3, p1: Vector3, side: int, s: float, fence: bool) -> void:
	var bas := _seg_basis(p0, p1)
	var mid := (p0 + p1) * 0.5 + bas.x * side * 0.3
	var seg_len := p0.distance_to(p1) + 0.02
	_buf(i, "concrete").box(mid + Vector3.UP * 0.55, Vector3(0.6, 1.1, seg_len), bas)
	_body(i, "barrier").box(mid + Vector3.UP * 0.55, Vector3(0.6, 1.1, seg_len), bas, Color.WHITE, true)
	if fence:
		_buf(i, "fence").box(mid + Vector3.UP * (1.1 + FENCE_H * 0.5), Vector3(0.03, FENCE_H, seg_len), bas)
		if fmod(s, 4.0) < st.STEP:
			_buf(i, "steel").box(p0 + bas.x * side * 0.3 + Vector3.UP * (1.1 + FENCE_H * 0.5), Vector3(0.1, FENCE_H, 0.1), bas)


# ── the pits ──────────────────────────────────────────────────────────────

## The pit lane (its taper in from the track's right edge, the fast lane and the working
## lane, the taper out), the grass gores either side of the tapers, the pit wall between the
## lane and the track, the white lines, the limiter lines, the boxes, the garages and the
## paddock behind them.
func _pits() -> void:
	var p: Dictionary = cst.pit
	var s_in0 := float(p.s_in0)
	var s_out1 := float(p.s_out1)
	var step: float = st.STEP
	var s := s_in0 - PIT_SPAN_PAD
	while s < s_out1 + PIT_SPAN_PAD - 0.01:
		var sw: float = st.wrap_s(s)
		var i := int(sw / step) % st._n
		var rows := []
		var gore := []
		var paddock := []
		var ds := PackedFloat32Array()
		var dg := PackedFloat32Array()
		var dp := PackedFloat32Array()
		for k in 2:
			var sk := sw + k * step
			var h: float = cst.half_at(sk)
			var a: float = cst.pit_inner_d(sk)
			var b: float = cst.pit_outer_d(sk)
			var garage := float(p.garage_d)
			if a == INF:
				a = h + 2.0
				b = h + 2.0
			ds = PackedFloat32Array([a, (a + b) * 0.5, b])
			var row := PackedVector3Array()
			for d in ds:
				row.append(st.world_at(sk, d))
			rows.append(row)
			# between the track's edge and the lane (the apron / the taper's gore)
			dg = PackedFloat32Array([h, maxf(h, a)])
			gore.append(PackedVector3Array([st.world_at(sk, h), st.world_at(sk, maxf(h + 0.01, a))]))
			# behind the lane: the paddock, out to the ground's start
			dp = PackedFloat32Array([maxf(b, h + 2.0), garage + 42.0])
			paddock.append(PackedVector3Array([st.world_at(sk, dp[0]), st.world_at(sk, dp[1])]))
		var in_lane: bool = cst.pit_inner_d(sw) != INF
		if in_lane:
			_buf(i, "pitlane").ribbon(rows[0], rows[1], sw, sw + step, ds, Color.WHITE)
			_body(i, "asphalt").ribbon(rows[0], rows[1], sw, sw + step, ds, Color.WHITE, true)
		var x: float = cst.around_line(sw)
		var walled := x >= float(p.s_in1) and x <= float(p.s_out0)
		_buf(i, "pitlane" if walled else "terrain").ribbon(gore[0], gore[1], sw, sw + step, dg, Color.WHITE if walled else Color(0.27, 0.36, 0.15))
		_body(i, "asphalt" if walled else "grass").ribbon(gore[0], gore[1], sw, sw + step, dg, Color.WHITE, true)
		_buf(i, "pitlane").ribbon(paddock[0], paddock[1], sw, sw + step, dp, Color(0.92, 0.92, 0.92))
		_body(i, "asphalt").ribbon(paddock[0], paddock[1], sw, sw + step, dp, Color.WHITE, true)
		if in_lane:
			# the lane's lines: its edge by the wall (or the track: the taper's solid line), its far edge
			var a2: float = cst.pit_inner_d(sw)
			_strip(i, a2 + 0.05, a2 + 0.25, 0.012, "paint", Color(1, 1, 1), sw, sw + step)
			if walled:
				var fast := float(p.fast_d)
				if int(sw / 6.0) % 2 == 0:                   # (the fast lane's edge: dashed)
					_strip(i, fast + 1.5, fast + 1.65, 0.012, "paint", Color(1, 1, 1), sw, sw + step)
		if walled:
			_wall(i, st.world_at(sw, float(p.wall_d)), st.world_at(sw + step, float(p.wall_d)), -1, sw, true)
		s += step
	# the limiter lines across the lane, yellow; PIT ENTRY / PIT EXIT lines across the taper
	for ls in [float(p.s_lim0), float(p.s_lim1)]:
		var sw2: float = st.wrap_s(ls)
		_strip(int(sw2 / step) % st._n, cst.pit_inner_d(sw2), cst.pit_outer_d(sw2), 0.014, "paint", Color(1.0, 0.82, 0.1), sw2, sw2 + 0.6)
	# the boxes: a yellow outline each, its number on the garage wall behind
	for k in int(p.boxes):
		var sd: Vector2 = cst.box_sd(k)
		var span := (float(p.s_box1) - float(p.s_box0)) / float(p.boxes)
		var i2 := int(sd.x / step) % st._n
		for dd in [sd.y - 2.4, sd.y + 2.4]:
			_strip(i2, dd - 0.08, dd + 0.08, 0.013, "paint", Color(1.0, 0.82, 0.1), sd.x - span * 0.42, sd.x + span * 0.42)
		_strip(i2, sd.y - 2.4, sd.y + 2.4, 0.013, "paint", Color(1.0, 0.82, 0.1), sd.x + span * 0.42 - 0.16, sd.x + span * 0.42)
	_garages()


## The garage block: twenty bays along the lane (a dark opening each, its number over it), a
## glazed hospitality floor above, the roof, a control tower at the line.
func _garages() -> void:
	var p: Dictionary = cst.pit
	var s0 := float(p.s_box0) - 12.0
	var s1 := float(p.s_box1) + 12.0
	var d0 := float(p.garage_d) + 0.5
	var depth := 16.0
	var step: float = st.STEP
	var s := s0
	while s < s1 - 0.01:
		var e := minf(s + 4.0, s1)
		var sw: float = st.wrap_s(s)
		var ew: float = sw + (e - s)
		var i := int(sw / step) % st._n
		var a: Vector3 = st.world_at(sw, d0)
		var b: Vector3 = st.world_at(ew, d0)
		var bas := _seg_basis(a, b)
		var mid := (a + b) * 0.5 + bas.x * depth * 0.5
		var seg_len := a.distance_to(b) + 0.02
		_buf(i, "building").box(mid + Vector3.UP * 3.0, Vector3(depth, 6.0, seg_len), bas, Color(0.9, 0.9, 0.92))
		_body(i, "barrier").box(mid + Vector3.UP * 3.0, Vector3(depth, 6.0, seg_len), bas, Color.WHITE, true)
		_buf(i, "glass").box(mid + Vector3.UP * 7.6 - bas.x * (depth * 0.5 - 0.3), Vector3(0.2, 3.0, seg_len), bas)
		_buf(i, "building").box(mid + Vector3.UP * 7.6 + bas.x * 1.0, Vector3(depth - 2.0, 3.2, seg_len), bas, Color(0.86, 0.86, 0.88))
		_buf(i, "roof").box(mid + Vector3.UP * 9.35 - bas.x * 1.0, Vector3(depth + 2.0, 0.3, seg_len), bas)
		s = e
	# each bay's opening (dark) and number
	for k in int(p.boxes):
		var sd: Vector2 = cst.box_sd(k)
		var i2 := int(sd.x / step) % st._n
		var span := (float(p.s_box1) - float(p.s_box0)) / float(p.boxes)
		var a2: Vector3 = st.world_at(sd.x, d0 - 0.02)
		var bas2 := _seg_basis(st.world_at(sd.x - 1.0, d0), st.world_at(sd.x + 1.0, d0))
		var team := Color.from_hsv(fposmod(k * 0.137 + 0.03, 1.0), 0.75, 0.85)       # (each bay its team's colour)
		_buf(i2, "garage_bay").box(a2 + Vector3.UP * 2.3, Vector3(0.1, 4.4, span * 0.82), bas2, team)
		var lbl := Label3D.new()
		lbl.text = str(k + 1)
		lbl.font_size = 96
		lbl.pixel_size = 0.01
		lbl.modulate = Color(0.95, 0.95, 0.93)
		lbl.outline_size = 0
		add_child(lbl)
		lbl.global_transform = Transform3D(bas2 * Basis(Vector3.UP, -PI * 0.5), a2 - bas2.x * 0.06 + Vector3.UP * 5.1)
	# the control tower at the line, behind the garages
	var t: Vector3 = st.world_at(0.0, d0 + depth + 6.0)
	var tb := _seg_basis(st.world_at(-1.0, d0), st.world_at(1.0, d0))
	var ti := 0
	_buf(ti, "building").box(t + Vector3.UP * 9.0, Vector3(10.0, 18.0, 10.0), tb, Color(0.92, 0.92, 0.94))
	_buf(ti, "glass").box(t + Vector3.UP * 16.0, Vector3(10.4, 3.5, 10.4), tb)
	_buf(ti, "roof").box(t + Vector3.UP * 18.2, Vector3(12.0, 0.4, 12.0), tb)
	var title := Label3D.new()
	title.text = str(cst.touge_name())
	title.font_size = 160
	title.pixel_size = 0.02
	title.modulate = Color(0.9, 0.15, 0.12)
	add_child(title)
	title.global_transform = Transform3D(tb * Basis(Vector3.UP, -PI * 0.5), st.world_at(float(p.s_box0) + 60.0, d0 - 0.2) + Vector3.UP * 10.6)


# ── the grid ──────────────────────────────────────────────────────────────

## The start/finish line (white, a chequered band beside it), the grid boxes (a white line
## across each place's front, its sides' corners), the pole's box a touch wider.
func _grid_marks() -> void:
	var step: float = st.STEP
	var h: float = cst.half_at(0.0)
	_strip(0, -h, h, 0.013, "paint", Color(1, 1, 1), 0.0, 0.8)
	# the chequered band just before the line
	var cells := int(h * 2.0 / 0.8)
	for c in cells:
		for r in 2:
			if (c + r) % 2 == 0:
				var d0 := -h + c * 0.8
				_strip(0, d0, d0 + 0.8, 0.014, "paint", Color(0.05, 0.05, 0.05), -1.6 + r * 0.8, -0.8 + r * 0.8)
	for g in cst.grid:
		var gs := float(g.s)
		var gd := float(g.d)
		var i := int(gs / step) % st._n
		_strip(i, gd - 1.3, gd + 1.3, 0.013, "paint", Color(1, 1, 1), gs + 0.6, gs + 0.8)
		for sd in [-1.3, 1.3]:
			_strip(i, gd + sd - 0.08, gd + sd + 0.08, 0.013, "paint", Color(1, 1, 1), gs - 0.2, gs + 0.8)


# ── gantries and boards ───────────────────────────────────────────────────

## The start-light gantry over the line (two posts outside the walls, a beam, five pairs of
## red lights; the session lights them), and a DRS / sector board at each line.
func _gantries() -> void:
	var s := 6.0
	var h: float = cst.half_at(s)
	var a: Vector3 = st.world_at(s, -h - 6.0)
	var b: Vector3 = st.world_at(s, h + 3.5)
	var bas := _seg_basis(st.world_at(s - 1.0, 0.0), st.world_at(s + 1.0, 0.0))
	var i := int(s / st.STEP)
	for p in [a, b]:
		_buf(i, "steel").box(p + Vector3.UP * 4.0, Vector3(0.5, 8.0, 0.5), bas)
	var mid := (a + b) * 0.5
	var span := a.distance_to(b)
	_buf(i, "steel").box(mid + Vector3.UP * 7.6, Vector3(span, 0.6, 0.5), bas * Basis(Vector3.UP, 0.0))
	start_lights = Node3D.new()
	start_lights.name = "StartLights"
	add_child(start_lights)
	start_lights.global_transform = Transform3D(bas, st.world_at(s, 0.0) + Vector3.UP * 6.6)
	var housing := BoxMesh.new()
	housing.size = Vector3(0.9, 1.6, 0.4)
	var bulb := SphereMesh.new()
	bulb.radius = 0.18
	bulb.height = 0.36
	for k in 5:
		var x := (k - 2.0) * 1.1
		var hmi := MeshInstance3D.new()
		hmi.mesh = housing
		hmi.material_override = _mat("garage_dark")
		hmi.position = Vector3(x, 0.0, 0.0)
		start_lights.add_child(hmi)
		var pair := []
		for row in 2:
			var on := MeshInstance3D.new()
			on.mesh = bulb
			on.material_override = _mat("light_red")
			on.position = Vector3(x, 0.35 - row * 0.6, 0.22)
			on.visible = false
			start_lights.add_child(on)
			var off := MeshInstance3D.new()
			off.mesh = bulb
			off.material_override = _mat("light_off")
			off.position = Vector3(x, 0.35 - row * 0.6, 0.21)
			start_lights.add_child(off)
			pair.append([on, off])
		_light_bulbs.append(pair)
	_boards_at(cst.sectors[0], -1, "SECTOR 2")
	_boards_at(cst.sectors[1], -1, "SECTOR 3")
	for z in cst.drs:
		_boards_at(float(z.detect), -1, "DRS DETECTION")
		_boards_at(float(z.s0), -1, "DRS")


## Light `count` of the five pairs (0: all out); green: the five out and the go (the race's).
func set_lights(count: int) -> void:
	for k in _light_bulbs.size():
		for pair in _light_bulbs[k]:
			pair[0].visible = k < count
			pair[1].visible = k >= count


## A board beside the track at s (side), on two legs, its text facing the cars coming.
func _boards_at(s: float, side: int, text: String) -> void:
	var d := _barrier_d(s, side) + side * 1.5
	var p := _out_pt(s, d)
	var bas := _seg_basis(st.world_at(s - 1.0, 0.0), st.world_at(s + 1.0, 0.0))
	var i := int(st.wrap_s(s) / st.STEP) % st._n
	_buf(i, "board").box(p + Vector3.UP * 2.2, Vector3(2.4, 1.0, 0.1), bas)
	for x in [-0.9, 0.9]:
		_buf(i, "steel").box(p + bas.x * x + Vector3.UP * 0.9, Vector3(0.08, 1.8, 0.08), bas)
	var lbl := Label3D.new()
	lbl.text = text
	lbl.font_size = 48 if text.length() > 8 else 72
	lbl.pixel_size = 0.01
	lbl.modulate = Color(0.08, 0.08, 0.1)
	lbl.outline_size = 0
	add_child(lbl)
	lbl.global_transform = Transform3D(bas, p + Vector3.UP * 2.2 + bas.z * 0.06)


# ── grandstands ───────────────────────────────────────────────────────────

## Stepped stands behind the barrier: rows of seats (coloured blocks), a back wall, a roof
## on the pit-straight's.
func _stands() -> void:
	for sd in cst.stands:
		var side := int(sd.side)
		var s0 := float(sd.s0)
		var s1 := float(sd.s1)
		if s1 < s0:
			s1 += st.length
		var rows := int(sd.rows)
		var s := s0
		while s < s1 - 0.01:
			var e := minf(s + 8.0, s1)
			var sw: float = st.wrap_s(s)
			var i := int(sw / st.STEP) % st._n
			var d := _barrier_d(sw, side) + side * 4.0
			var a := _out_pt(sw, d)
			var b := _out_pt(sw + (e - s), _barrier_d(sw + (e - s), side) + side * 4.0)
			var bas := _seg_basis(a, b)
			if side < 0:
				bas = Basis(-bas.x, bas.y, -bas.z)
			var seg_len := a.distance_to(b) + 0.05
			for r in rows:
				var c := Color(0.12, 0.3, 0.75) if (r + int(s / 8.0)) % 5 != 0 else Color(0.9, 0.85, 0.2)
				var at := (a + b) * 0.5 + bas.x * (0.9 * r + 0.45) + Vector3.UP * (0.45 * r + 0.6)
				_buf(i, "seat").box(at, Vector3(0.9, 0.5, seg_len), bas, c)
				_buf(i, "concrete").box(at - Vector3.UP * 0.45 + bas.x * 0.0, Vector3(0.9, 0.4, seg_len), bas)
			var back := (a + b) * 0.5 + bas.x * (0.9 * rows + 0.3) + Vector3.UP * (0.45 * rows * 0.5 + 1.2)
			_buf(i, "concrete").box(back, Vector3(0.6, 0.45 * rows + 2.4, seg_len), bas)
			if rows >= 12:
				_buf(i, "roof").box((a + b) * 0.5 + bas.x * (0.45 * rows) + Vector3.UP * (0.45 * rows + 3.6), Vector3(0.9 * rows + 2.0, 0.25, seg_len), bas)
			s = e
		stand_count += 1


# ── trackside ─────────────────────────────────────────────────────────────

## Marshal posts (an orange-roofed hut with its light panel, behind the barrier) and the
## distance boards before the big stops.
func _trackside() -> void:
	for m in cst.marshals:
		var s := float(m.s)
		var side := int(m.side)
		if _pit_side(s, side):
			continue
		var d := _barrier_d(s, side) + side * 2.0
		var p := _out_pt(s, d)
		var bas := _seg_basis(st.world_at(s - 1.0, 0.0), st.world_at(s + 1.0, 0.0))
		var i := int(st.wrap_s(s) / st.STEP) % st._n
		if _prop_mesh("marshal_hut") != null:
			# the library's observation hut, its open side to the track, a flag pole beside it
			_prop("marshal_hut", Transform3D(bas * Basis(Vector3.UP, PI * 0.5 * side), p))
			_prop("pit_flag_pole", Transform3D(bas, p + bas.z * 2.0 - bas.x * side * 0.9))
		else:
			_buf(i, "board").box(p + Vector3.UP * 1.1, Vector3(1.8, 2.2, 1.8), bas)
			_buf(i, "marshal").box(p + Vector3.UP * 2.3, Vector3(2.2, 0.2, 2.2), bas)
			_buf(i, "garage_dark").box(p + Vector3.UP * 1.5 - bas.x * side * 0.92, Vector3(0.05, 0.8, 1.2), bas)
		marshal_count += 1
	for bd in cst.boards:
		var s := float(bd.s)
		var side := int(bd.side)
		var d := _barrier_d(s, side) - side * 0.5
		if absf(d) < cst.half_at(s) + 4.0:
			d = side * (cst.half_at(s) + 4.0)
		var p := _out_pt(s, d)
		var bas := _seg_basis(st.world_at(s - 1.0, 0.0), st.world_at(s + 1.0, 0.0))
		var i := int(st.wrap_s(s) / st.STEP) % st._n
		_buf(i, "board").box(p + Vector3.UP * 1.0, Vector3(1.2, 1.2, 0.08), bas)
		_buf(i, "steel").box(p + Vector3.UP * 0.2, Vector3(0.06, 0.4, 0.06), bas)
		var lbl := Label3D.new()
		lbl.text = str(int(bd.m))
		lbl.font_size = 96
		lbl.pixel_size = 0.008
		lbl.modulate = Color(0.05, 0.05, 0.06)
		lbl.outline_size = 0
		add_child(lbl)
		lbl.global_transform = Transform3D(bas, p + Vector3.UP * 1.0 + bas.z * 0.05)


# ── the pit crews' kit (the library's track props) ────────────────────────

var _props := {}                     # asset id -> [Transform3D]: drawn as one MultiMesh each (_pit_props)


func _prop_mesh(id: String) -> Mesh:
	if not EnvAssets.available() or EnvAssets.info(id).is_empty():
		return null
	return EnvAssets.mesh(id)


func _prop(id: String, xf: Transform3D) -> void:
	if not _props.has(id):
		_props[id] = []
	_props[id].append(xf)


## The pits dressed: between each pair of boxes the team's tyres in their blankets, a warmer rack
## and a wheel gun; a jack waiting at each end of its box; an air-jack rig, a fuel rig and a helmet
## rack every other box; a monitor stand on the pit wall opposite each box; the signal lights at
## the lane's ends; tyre walls on the noses of the pit entry and exit (solid); a row of team garages
## in the paddock behind. The marshal posts' huts and flags come from _trackside. Nothing in a box
## or the fast lane (the cars' way in and out). Then every prop is drawn (one MultiMesh a kind).
func _pit_props() -> void:
	if _prop_mesh("pit_tyre_blankets") != null:
		var p: Dictionary = cst.pit
		var span := (float(p.s_box1) - float(p.s_box0)) / float(p.boxes)
		var wall := float(p.wall_d)
		var garage := float(p.garage_d)
		for k in int(p.boxes):
			var sd: Vector2 = cst.box_sd(k)
			var bas := _seg_basis(st.world_at(sd.x - 1.0, sd.y), st.world_at(sd.x + 1.0, sd.y))
			var across := bas * Basis(Vector3.UP, PI * 0.5)          # (a long thing laid across the lane's way)
			var gs: float = sd.x + span * 0.5                       # the gap after this box
			_prop("pit_tyre_blankets", Transform3D(bas, st.world_at(gs, garage - 0.6)))
			_prop("pit_tyre_blankets", Transform3D(bas * Basis(Vector3.UP, 0.7), st.world_at(gs, garage - 1.45)))
			_prop("pit_warmer_rack", Transform3D(across, st.world_at(gs, sd.y - 0.3)))
			_prop("pit_wheel_gun", Transform3D(bas * Basis(Vector3.UP, 1.1 + k), st.world_at(gs, sd.y - 1.8)))
			_prop("pit_jack_front", Transform3D(across, st.world_at(sd.x + span * 0.42 - 0.5, garage - 0.9)))
			_prop("pit_jack_rear", Transform3D(across, st.world_at(sd.x - span * 0.42 + 0.6, garage - 1.0)))
			if k % 2 == 0:
				_prop("pit_air_jack", Transform3D(bas, st.world_at(gs - 0.1, sd.y + 1.1)))
				_prop("pit_helmet_rack", Transform3D(bas * Basis(Vector3.UP, -PI * 0.5), st.world_at(sd.x - span * 0.42 - 0.3, garage - 0.4)))
			else:
				_prop("pit_fuel_rig", Transform3D(across, st.world_at(gs, garage - 2.6)))
			# the team's stand on the pit wall (its lane side), along the wall
			_prop("pit_wall_stand", Transform3D(across, st.world_at(sd.x, wall + 0.75)))
		# the signal lights where the lane starts and ends (by the wall), the tyre walls on the noses
		for ls in [float(p.s_lim0) - 4.0, float(p.s_lim1) + 4.0]:
			_prop("pit_signal_lights", Transform3D(_seg_basis(st.world_at(ls - 1.0, 0.0), st.world_at(ls + 1.0, 0.0)), st.world_at(ls, wall + 0.4)))
		for nose in [[float(p.s_in1), -1.0], [float(p.s_out0), 1.0]]:
			var ns := float(nose[0]) + float(nose[1]) * 1.5
			var nd := (cst.half_at(ns) + float(p.lane_d0)) * 0.5
			var nb := _seg_basis(st.world_at(ns - 1.0, 0.0), st.world_at(ns + 1.0, 0.0))
			var at: Vector3 = st.world_at(ns, nd)
			_prop("tyre_wall_straight", Transform3D(nb, at))
			_prop("tyre_wall_straight", Transform3D(nb, at + Vector3.UP * 0.6))
			var i := int(st.wrap_s(ns) / st.STEP) % st._n
			_body(i, "barrier").box(at + Vector3.UP * 0.6, Vector3(3.6, 1.2, 0.6), nb, Color.WHITE, true)
		# the team garages in the paddock behind the garage block, facing it
		var ps := float(p.s_box0) + 6.0
		while ps < float(p.s_box1) - 6.0:
			var pb := _seg_basis(st.world_at(ps - 1.0, 0.0), st.world_at(ps + 1.0, 0.0))
			_prop("pit_garage_double", Transform3D(pb * Basis(Vector3.UP, PI), st.world_at(ps, garage + 0.5 + 16.0 + 9.0)))
			ps += 28.0
	for id in _props:
		var m: Mesh = EnvAssets.mesh(id)
		if m == null:
			continue
		var list: Array = _props[id]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = m
		mm.instance_count = list.size()
		for j in list.size():
			mm.set_instance_transform(j, list[j])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Props_%s" % id
		mmi.multimesh = mm
		var big: bool = id in ["pit_garage_double", "marshal_hut", "tyre_wall_straight"]
		# (a MultiMesh's range is to its bounds' middle: the pits' kit is all in one place, but the
		# marshal posts are round the whole lap: theirs has no range, ~14k triangles for all of them)
		if not id in ["marshal_hut", "pit_flag_pole"]:
			mmi.visibility_range_end = (700.0 if big else 220.0) * (0.5 if Graphics.level() == "low" else 1.0)
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if big else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
	_props.clear()


# ── floodlights ───────────────────────────────────────────────────────────

## Floodlight towers every 120 m behind the barriers, alternating sides: an 18 m mast, a bank
## of lamps leaning over the track (lit at night and dusk: StreetLamps' pools on the asphalt).
func _floodlights() -> void:
	var lit: bool = _wm != null and _wm.night_amount >= 0.05
	var mast := GeoBuf.new()
	var heads := GeoBuf.new()
	mast.box(Vector3(0, 9.0, 0), Vector3(0.45, 18.0, 0.45))
	mast.box(Vector3(-1.2, 18.0, 0), Vector3(2.6, 0.3, 0.3))
	if lit:
		heads.box(Vector3(-2.2, 17.85, 0), Vector3(0.6, 0.25, 1.8))
	else:
		mast.box(Vector3(-2.2, 17.95, 0), Vector3(0.6, 0.2, 1.8))
	var mesh := _mesh2(mast, "steel", heads, "post_lamp")
	var per_chunk := {}
	lamp_heads.clear()
	for l in cst.lights:
		var s := float(l.s)
		var side := int(l.side)
		if _pit_side(s, side):
			continue
		var d := _barrier_d(s, side) + side * 3.0
		var p := _out_pt(s, d)
		var bas := _seg_basis(st.world_at(s - 1.0, 0.0), st.world_at(s + 1.0, 0.0))
		if side < 0:
			bas = Basis(-bas.x, bas.y, -bas.z)
		var xf := Transform3D(bas, p)
		var c := int(int(st.wrap_s(s) / st.STEP) / CH)
		if not per_chunk.has(c):
			per_chunk[c] = []
		per_chunk[c].append(xf)
		var head: Vector3 = xf * Vector3(-2.2, 17.85, 0)
		var g: Vector3 = st.world_at(s, side * cst.half_at(s) * 0.4)       # (the pool on the track by it)
		lamp_heads.append({"s": s, "head": head, "ground": g, "up": st.up_at(s), "radius": 34.0})
		floodlight_count += 1
	for c in per_chunk:
		_multimesh(mesh, per_chunk[c], "Floodlights%03d" % c, ROAD_RANGE)
	if lit:
		street_lamps = _wm.street_lights(self, lamp_heads)


# ── the forest ────────────────────────────────────────────────────────────

## The ridge's trees: the library's species (the biome: temperate broadleaf), clumped by
## noise, clear of the track by at least 30 m past its barriers, none in the paddock; LOD0 /
## LOD1 / the far card by distance, as on the stages. LOW (or no library): drawn trees.
func _forest() -> void:
	var biome := Biomes.for_stage(st)
	var species: Array = (biome.get("trees", []) as Array) + (biome.get("broad", []) as Array)
	var use_lib: bool = Graphics.level() != "low" and EnvAssets.available() and not species.is_empty()
	var noise := FastNoiseLite.new()
	noise.seed = 31
	noise.frequency = 1.0 / 160.0
	var cx := 0.0
	var cz := 0.0
	for q in st.pts:
		cx += q.x
		cz += q.z
	cx /= st.pts.size()
	cz /= st.pts.size()
	var lists := {}                                  # species -> transforms
	var spacing := 14.0
	var half_size := 1500.0
	var z := cz - half_size
	while z < cz + half_size:
		var x := cx - half_size
		while x < cx + half_size:
			var jx := x + _rng.randf_range(-5.0, 5.0)
			var jz := z + _rng.randf_range(-5.0, 5.0)
			x += spacing
			if noise.get_noise_2d(jx, jz) < 0.02:
				continue
			var near := _nearest_far(Vector3(jx, 0, jz), -100000, 0.0)
			if near.x < 0.0:
				continue
			var j := int(near.x)
			var sj := j * st.STEP
			var side := 1 if (Vector3(jx, 0, jz) - st.pts[j]).dot(st.right_at(sj)) > 0.0 else -1
			var clear := absf(_barrier_d(sj, side)) + 30.0
			if _pit_side(sj, side):
				clear = float(cst.pit.garage_d) + 70.0
			if near.y < clear:
				continue
			var sp := Biomes.pick(species, _rng) if use_lib else ""
			var y := _land_y(jx, jz)
			var sc := _rng.randf_range(0.8, 1.25)
			var xf := Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(sc, sc, sc)), Vector3(jx, y - 0.15, jz))
			if not lists.has(sp):
				lists[sp] = []
			lists[sp].append(xf)
		z += spacing
	var tint: Color = Biomes.colour(biome.get("foliage_tint"), Color.WHITE)
	for sp in lists:
		tree_count += lists[sp].size()
		if sp == "":
			_multimesh(_tree_mesh(_rng.randf() < 0.5), lists[sp], "TreesDrawn", 1500.0)
			continue
		var tt: Color = tint
		_lib_trees(sp, lists[sp], tt)


func _lib_trees(sp: String, list: Array, tint: Color) -> void:
	for lv in [["LOD1", 0.0, 140.0], ["BB", 140.0, 1500.0]]:
		var m: Mesh = EnvAssets.mesh(sp, lv[0], tint)
		if m == null:
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = m
		mm.instance_count = list.size()
		for j in list.size():
			mm.set_instance_transform(j, list[j])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Trees_%s_%s" % [sp, lv[0]]
		mmi.multimesh = mm
		mmi.set_meta("xforms", list)
		mmi.visibility_range_begin = lv[1]
		mmi.visibility_range_end = lv[2]
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if lv[0] == "LOD1" else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
