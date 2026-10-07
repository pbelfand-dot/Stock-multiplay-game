extends Node3D
## The co-driver's MAP BOARD: a wooden board with brass clips and a moving
## map on it, and a stopwatch clipped on top. It shows ONLY the road ahead and
## where the car is: no grades, no "4 LEFT", no warnings. Reading the bends and
## turning them into calls is the co-driver's job (and the fun of the seat).
##
## The map is heading-up, like a GPS: the car marker stays put near the bottom
## and the road turns around it as the car turns. ~280 m of road ahead, a bit
## behind, the start and finish lines when they're near, bridges (the map
## symbol: the road drawn as planks with a rail each side), the asphalt in grey
## (gravel is yellow: you see a surface change coming) and ice in pale blue.
##
## Drawn into a SubViewport (2D) shown on a quad: board-local units are metres,
## the map faces +Z (toward the co-driver's eyes).

const MAP_PX := Vector2i(300, 420)
const MAP_M := Vector2(0.21, 0.294)
const SCALE := 1.15                  # pixels per metre of road
const CAR_AT := Vector2(150, 345)    # where the car sits on the map
const AHEAD := 300.0                 # metres of road drawn ahead ...
const BEHIND := 45.0                 # ... and behind

var st                               # StageGen
var car                              # the car (its interpolated transform drives the map)
var car_s := 0.0                     # where the car is on the road (set by the game)
var clock_text := "0:00.0"           # the stopwatch
var clock_red := false               # countdown in red
var _vp: SubViewport
var _map: Control
var _font: Font


func setup(stage, the_car) -> void:
	st = stage
	car = the_car
	_font = load("res://assets/fonts/Oswald-Bold.woff2")
	_board()
	_vp = SubViewport.new()
	_vp.size = MAP_PX
	_vp.transparent_bg = false
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	_map = Control.new()
	_map.size = Vector2(MAP_PX)
	_map.draw.connect(_draw_map)
	_vp.add_child(_map)
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = MAP_M
	q.mesh = qm
	var m := StandardMaterial3D.new()
	m.albedo_texture = _vp.get_texture()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	q.material_override = m
	q.position = Vector3(0, -0.01, 0.012)
	add_child(q)


func _board() -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.52, 0.34, 0.18)
	wood.roughness = 0.8
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.8, 0.64, 0.25)
	brass.metallic = 0.6
	brass.roughness = 0.35
	var b := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.27, 0.38, 0.02)
	b.mesh = bm
	b.material_override = wood
	add_child(b)
	for y in [0.165, -0.185]:
		var r := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.014
		cm.bottom_radius = 0.014
		cm.height = 0.25
		cm.radial_segments = 8
		cm.rings = 1
		r.mesh = cm
		r.material_override = brass
		r.rotation.z = PI / 2.0
		r.position = Vector3(0, y, 0.02)
		add_child(r)
	var w := MeshInstance3D.new()                    # the stopwatch on top
	var wm := BoxMesh.new()
	wm.size = Vector3(0.09, 0.04, 0.025)
	w.mesh = wm
	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = Color(0.12, 0.12, 0.13)
	w.material_override = wmat
	w.position = Vector3(0.0, 0.205, 0.02)
	add_child(w)


func _process(_dt: float) -> void:
	if _map:
		_map.queue_redraw()


## Map pixel of a world point, heading-up around the car.
func _to_map(p: Vector3, origin: Vector3, fwd: Vector3, right: Vector3) -> Vector2:
	var d := p - origin
	return CAR_AT + Vector2(d.dot(right), -d.dot(fwd)) * SCALE


## The road from a to b (m) as a line on the map, if any of it is there.
func _draw_stretch(a: float, b: float, col: Color, w: float, origin: Vector3, fwd: Vector3, right: Vector3) -> void:
	if b - a < 1.0:
		return
	var line := PackedVector2Array()
	var s := a
	while s < b:
		line.append(_to_map(st.point_at(s), origin, fwd, right))
		s += st.STEP
	line.append(_to_map(st.point_at(b), origin, fwd, right))
	_map.draw_polyline(line, col, w)


func _draw_map() -> void:
	var w := float(MAP_PX.x)
	var h := float(MAP_PX.y)
	_map.draw_rect(Rect2(0, 0, w, h), Color(0.95, 0.92, 0.82))
	# faint grid, so turning reads as turning
	if st == null or car == null:
		return
	var xf: Transform3D = car.get_global_transform_interpolated()
	var fwd := -xf.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var origin := xf.origin
	var grid := Color(0.86, 0.82, 0.7)
	for k in range(-6, 7):
		for line in [[Vector3(k * 50.0, 0, -300), Vector3(k * 50.0, 0, 300)], [Vector3(-300, 0, k * 50.0), Vector3(300, 0, k * 50.0)]]:
			# grid fixed to the world (snapped to 50 m) so it slides and turns under the car
			var base := Vector3(snappedf(origin.x, 50.0), 0, snappedf(origin.z, 50.0))
			_map.draw_line(_to_map(base + line[0], origin, fwd, right), _to_map(base + line[1], origin, fwd, right), grid, 1.0)
	# a loop (cut up's highway): the road round the car, s taken round the loop
	if st.has_method("wrap_s"):
		_draw_stretch(car_s - BEHIND, car_s, Color(0.55, 0.5, 0.42, 0.6), 7.0, origin, fwd, right)
		_draw_stretch(car_s, car_s + AHEAD, Color(0.18, 0.15, 0.12), 9.0, origin, fwd, right)
		_draw_stretch(car_s, car_s + AHEAD, Color(0.55, 0.56, 0.6), 4.0, origin, fwd, right)
	else:
		# the road: behind (faded) and ahead
		var i0 := maxi(0, int((car_s - BEHIND) / st.STEP))
		var i1 := mini(st.pts.size() - 1, int((car_s + AHEAD) / st.STEP))
		var now_i := clampi(int(car_s / st.STEP), i0, i1)
		var behind := PackedVector2Array()
		var ahead := PackedVector2Array()
		for i in range(i0, i1 + 1):
			var px := _to_map(st.pts[i], origin, fwd, right)
			if i <= now_i:
				behind.append(px)
			if i >= now_i:
				ahead.append(px)
		if behind.size() > 1:
			_map.draw_polyline(behind, Color(0.55, 0.5, 0.42, 0.6), 7.0)
		if ahead.size() > 1:
			_map.draw_polyline(ahead, Color(0.18, 0.15, 0.12), 9.0)
			_map.draw_polyline(ahead, Color(0.98, 0.84, 0.32), 4.0)
		# the asphalt sections in grey (the gravel stays yellow), ice in pale blue
		for sec in st.sections:
			if sec.surface == "asphalt":
				_draw_stretch(maxf(sec.s0, car_s), minf(sec.s1, car_s + AHEAD), Color(0.55, 0.56, 0.6), 4.0, origin, fwd, right)
		for p in st.patches:
			if p.kind == "ice":
				_draw_stretch(maxf(p.s0, car_s), minf(p.s1, car_s + AHEAD), Color(0.55, 0.85, 1.0), 7.0, origin, fwd, right)
		# bridges: the map's symbol (planks between two rails)
		for b in st.bridges:
			if b.s1 < car_s - BEHIND or b.s0 > car_s + AHEAD:
				continue
			var ia := maxi(int(b.s0 / st.STEP), i0)
			var ib := mini(int(b.s1 / st.STEP), i1)
			if ib <= ia:
				continue
			for side in [-1.0, 1.0]:
				var rail := PackedVector2Array()
				for i in range(ia, ib + 1):
					rail.append(_to_map(st.world_at(i * st.STEP, side * 7.0), origin, fwd, right))
				_map.draw_polyline(rail, Color(0.18, 0.15, 0.12), 2.0)
			for i in range(ia, ib + 1):
				var a := _to_map(st.world_at(i * st.STEP, -4.5), origin, fwd, right)
				var c := _to_map(st.world_at(i * st.STEP, 4.5), origin, fwd, right)
				_map.draw_line(a, c, Color(0.45, 0.3, 0.16), 2.0)
		# start and finish lines when they're on the map
		for mark in [[st.START_S, Color(0.85, 0.12, 0.1)], [st.finish_s, Color(0.1, 0.1, 0.1)]]:
			var s: float = mark[0]
			if s >= car_s - BEHIND and s <= car_s + AHEAD:
				var a := _to_map(st.world_at(s, -6.0), origin, fwd, right)
				var b := _to_map(st.world_at(s, 6.0), origin, fwd, right)
				_map.draw_line(a, b, mark[1], 5.0)
	# the car
	var tri := PackedVector2Array([CAR_AT + Vector2(0, -13), CAR_AT + Vector2(9, 9), CAR_AT + Vector2(-9, 9)])
	_map.draw_colored_polygon(tri, Color(0.85, 0.12, 0.1))
	_map.draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]), Color(0.2, 0.05, 0.05), 2.0)
	# stopwatch band
	_map.draw_rect(Rect2(0, 0, w, 54), Color(0.1, 0.1, 0.11))
	var t := clock_text
	var size := 36
	var tw := _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	_map.draw_string(_font, Vector2((w - tw) * 0.5, 40), t, HORIZONTAL_ALIGNMENT_LEFT, -1, size,
		Color(1.0, 0.25, 0.2) if clock_red else Color(0.95, 0.9, 0.5))
	# how far through the stage, down the side
	var p := clampf(car_s / maxf(st.finish_s, 1.0), 0.0, 1.0)
	_map.draw_rect(Rect2(w - 7, 58, 4, h - 64), Color(0.8, 0.76, 0.66))
	_map.draw_rect(Rect2(w - 7, 58 + (h - 64) * (1.0 - p), 4, (h - 64) * p), Color(0.85, 0.1, 0.1))
