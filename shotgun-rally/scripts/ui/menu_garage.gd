extends Node3D
## Behind the home screen: the garage (the owner's ask: "a premium car garage you're standing
## in"). Your car (Profile.setup(): its model, paint, livery, wheels) parked under the light
## box in the middle of the room (GarageRoom builds it), filmed by a slow camera:
##   home   a loop of gentle moves round the car (~100 s a lap): from the hero view by the
##          back wall (the roll-up door's LED frame behind the car), round the front, low
##          along the side, up past the rear by the door and back; slowest at the hero view
##   CARS   a slow orbit (set_showroom), the car kept right of the panel; show_car() swaps or
##          repaints it as you shop
## Going from one to the other the camera starts the new path where it is round the car, so
## the move between them is short and never through the car. Both paths stay 0.4 m clear of
## the furniture and inside the room (tests/menu_garage_check.gd). The menu's panels tint the
## door's LED frame a little (set_mood): amber for MODES, warm for MAPS, cool for ONLINE.
##
## The light (Godot has no area lights): the light box's glowing underside and a soft
## spotlight straight down from it onto the car (its shadow under the car), weak lights
## under the trusses for the walls, near the door frame's foot and at the workbench (MEDIUM
## and up), glowing LED strips, a very dark ambient, AgX; one box-projected reflection probe
## for the room (the floor and the paint show the light box and the strips); SSAO from MEDIUM,
## SSR from HIGH (Graphics). LOW: the spot and two fills only, no glow. Compatibility (the
## web, Chromebooks) gets LOW's lights whatever the level (it draws a pass a light).
##
## The same calls as the old stage backdrop (MenuBackdrop, kept behind --menu_stage):
## show_car, set_showroom, the ready_to_show signal, built, car, cam. It's built the frame
## after the menu appears (the room in a few tens of ms, then the car's model) and says
## ready_to_show two frames later. Pictures: --garage_t=SECONDS holds the camera there.

signal ready_to_show

const GarageRoom = preload("res://scripts/ui/garage_room.gd")
const RallyCar = preload("res://scripts/vehicle/rally_car.gd")
const Graphics = preload("res://scripts/render/graphics.gd")
const WorldMaterials = preload("res://scripts/render/world_materials.gd")

const SPOT := GarageRoom.SPOT
const YAW := PI                          # the car's nose toward the back wall (driven in), the hero camera
## The home loop's key points (the room's coordinates, m), the hero view first; a
## centripetal Catmull-Rom spline through them (no overshoot past them)
const HOME_KEYS := [Vector3(0.0, 1.45, 5.3), Vector3(2.5, 1.05, 3.5), Vector3(3.55, 0.78, 0.4), Vector3(3.6, 1.15, -2.9),
	Vector3(2.1, 1.8, -5.55), Vector3(-1.5, 1.6, -5.65), Vector3(-3.55, 1.0, -3.4), Vector3(-3.6, 0.8, -0.2), Vector3(-2.6, 1.2, 3.3)]
const HOME_LAP := 100.0                  # s round it
const HOME_EASE := 0.45                  # the speed's swing: slowest at the hero view (x0.55), quickest opposite (x1.45)
const HOME_FOV := 50.0
const HOME_SHIFT := 0.28                 # where the car sits across the screen (-1 left .. 1 right): right of the home buttons
const ORBIT := Vector3(3.55, 1.12, 4.5)  # CARS: the orbit's half-width across, its height, its half-length along
const ORBIT_LAP := 90.0
const ORBIT_FOV := 46.0
const ORBIT_SHIFT := 0.42                # right of the garage panel
const BLEND := 1.8                       # s to go from one path to the other
## the door frame's colour per panel (set_mood)
const MOODS := {"modes": Color(1.0, 0.56, 0.2), "maps": Color(1.0, 0.8, 0.55), "online": Color(0.55, 0.74, 1.0)}

var car
var cam: Camera3D
var showroom := false
var built := false
var room                                 # GarageRoom: its props, its materials
var build_ms := 0                        # how long the room and the car took (tests)
var env: Environment
var _setup := {}
var _t := 0.0                            # the camera's clock on its path
var _phase := 0.0                        # CARS: the orbit's angle at _t = 0
var _blend := BLEND                      # s since the last switch of paths
var _from := Transform3D()
var _from_fov := HOME_FOV
var _hold := -1.0                        # --garage_t: the camera held at this time
var _spot: SpotLight3D
var _fills: Array = []                   # the trusses' lights (the first two: LOW's)
var _extras: Array = []                  # MEDIUM and up: the door frame's feet, the workbench
var _door_lights: Array = []
var _probe: ReflectionProbe
var _blob: MeshInstance3D
var _car_box := AABB()                   # the car's bounding box in the room
var _mood := Color.WHITE
var _path: PackedVector3Array            # the home loop, densely sampled
var _path_len: PackedFloat32Array        # the distance along it to each sample


func _ready() -> void:
	add_to_group("graphics")
	cam = Camera3D.new()
	cam.fov = HOME_FOV
	cam.near = 0.05
	cam.far = 60.0
	add_child(cam)
	cam.current = true
	var cfg := get_node_or_null("/root/Config")
	if cfg and cfg.flag("garage_t"):
		_hold = float(cfg.arg("garage_t"))
	_sample_path()
	cam.global_transform = _home_xf(0.0)
	_build.call_deferred()


func _build() -> void:
	var t0 := Time.get_ticks_msec()
	WorldMaterials.night_amount = 0.0                 # (indoors: no night from the last stage on the car's lamps)
	WorldMaterials.night = false
	room = GarageRoom.new()
	add_child(room.build())
	_environment()
	_lights()
	car = RallyCar.new()
	car.name = "MenuCar"
	car.setup = _setup
	add_child(car)
	car.set_outside(true)
	_blob = _contact_shadow()
	add_child(_blob)
	_park()
	_graphics_changed()
	build_ms = Time.get_ticks_msec() - t0
	_t = _hold if _hold >= 0.0 else 0.0
	cam.global_transform = _home_xf(_t) if not showroom else _orbit_xf(_t)
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_inside_tree():
		return
	built = true
	ready_to_show.emit()


## The car the garage shows (the CARS panel calls this as you browse and paint): a
## Catalog.setup. Another body is swapped in, the same one repainted; either way it's
## parked on the spot again.
func show_car(setup: Dictionary) -> void:
	_setup = setup
	if car == null:
		return
	car.apply_setup(setup)
	_park()


## CARS open: the showroom orbit; closed: back to the home loop. Either starts where the
## camera is round the car.
func set_showroom(on: bool) -> void:
	if showroom == on:
		return
	showroom = on
	_from = cam.global_transform
	_from_fov = cam.fov
	_blend = 0.0
	var at := cam.global_position - SPOT
	if on:
		_phase = atan2(at.x / ORBIT.x, at.z / ORBIT.z)
		_t = 0.0
	else:
		_t = _home_time_near(cam.global_position)


## A panel's mood on the door's LED frame ("" or another panel: plain white).
func set_mood(panel: String) -> void:
	var col: Color = MOODS.get(panel, Color.WHITE)
	if col == _mood or room == null:
		return
	_mood = col
	var led: StandardMaterial3D = room.mats.led_door
	var want := Color(GarageRoom.LED.r * col.r, GarageRoom.LED.g * col.g, GarageRoom.LED.b * col.b)
	var tw := create_tween().set_parallel()
	tw.tween_property(led, "emission", want, 0.8)
	tw.tween_property(led, "albedo_color", want, 0.8)
	for l in _door_lights:
		tw.tween_property(l, "light_color", want, 0.8)


## The furniture's bounding boxes ([{name, box}], the room's coordinates) and the car's.
func obstacles() -> Array:
	var out: Array = room.props.duplicate() if room else []
	out.append({"name": "car", "box": _car_box})
	return out


func car_box() -> AABB:
	return _car_box


# ── the car ───────────────────────────────────────────────────────────────

## On the spot, nose to the back wall, held still at its rest pose; its contact shadow and
## the box the camera keeps clear of.
func _park() -> void:
	car.place(SPOT, YAW)
	car.park_still()
	car.set_outside(true)
	_car_box = _measure_car()
	if _blob:
		var c := _car_box.get_center()
		_blob.position = Vector3(c.x, 0.004, c.z)
		_blob.scale = Vector3(_car_box.size.x * 1.25, 1.0, _car_box.size.z * 1.12)


## The car's model's bounding box in the room (its body's, its wheels').
func _measure_car() -> AABB:
	var box := AABB()
	var first := true
	var model: Node3D = car.body_model if car.body_model else car
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		if not (mi as MeshInstance3D).is_visible_in_tree() or (mi as MeshInstance3D).mesh == null:
			continue
		var b: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
		box = b if first else box.merge(b)
		first = false
	if first:                                        # (no model: the physics' body box)
		box = AABB(SPOT + Vector3(-0.9, 0.0, -2.2), Vector3(1.8, 1.4, 4.4))
	return box


## A soft dark patch on the floor under the car (the light box can't reach under it): a
## blend, not a multiply, so it's the same on Compatibility.
func _contact_shadow() -> MeshInstance3D:
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.62))
	g.set_color(1, Color(0, 0, 0, 0.0))
	g.add_point(0.55, Color(0, 0, 0, 0.42))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 128
	gt.height = 128
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color.WHITE
	m.albedo_texture = gt
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var q := PlaneMesh.new()
	q.size = Vector2.ONE
	var mi := MeshInstance3D.new()
	mi.name = "ContactShadow"
	mi.mesh = q
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


# ── the light ─────────────────────────────────────────────────────────────

func _environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.0, 0.0, 0.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.62, 0.66)
	env.ambient_light_energy = 0.1
	env.reflected_light_source = Environment.REFLECTION_SOURCE_BG
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.tonemap_agx_white = 12.0
	env.tonemap_agx_contrast = 1.15
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	add_child(we)


func _lights() -> void:
	# the key: straight down from the light box onto the car, wide and soft
	_spot = SpotLight3D.new()
	_spot.name = "LightBox"
	_spot.position = Vector3(SPOT.x, 3.55, SPOT.z)
	_spot.rotation.x = -PI * 0.5
	_spot.light_color = GarageRoom.BOX_GLOW
	_spot.light_energy = 9.0
	_spot.spot_range = 7.5
	_spot.spot_angle = 52.0
	_spot.spot_angle_attenuation = 0.7
	_spot.spot_attenuation = 1.2
	_spot.shadow_bias = 0.04
	_spot.shadow_normal_bias = 1.0
	add_child(_spot)
	# the trusses' fixtures lighting the walls: two (LOW), four from MEDIUM
	for at in [Vector3(-3.4, 3.35, -1.5), Vector3(3.4, 3.35, -1.5), Vector3(-3.4, 3.35, 3.5), Vector3(3.4, 3.35, 3.5),
			Vector3(-3.4, 3.35, -5.0), Vector3(3.4, 3.35, -5.0)]:
		var o := OmniLight3D.new()
		o.position = at
		o.light_color = GarageRoom.LED
		o.omni_range = 6.5
		o.omni_attenuation = 1.4
		o.light_energy = 0.9
		o.light_specular = 0.3
		add_child(o)
		_fills.append(o)
	# the door frame's feet (a glow on the floor), the workbench's frame
	for at in [Vector3(-3.89, 0.3, -6.75), Vector3(3.89, 0.3, -6.75)]:
		var d := OmniLight3D.new()
		d.position = at
		d.light_color = GarageRoom.LED
		d.omni_range = 2.6
		d.light_energy = 0.7
		d.light_specular = 0.0
		add_child(d)
		_extras.append(d)
		_door_lights.append(d)
	var bench := OmniLight3D.new()
	bench.position = Vector3(0.0, 1.6, 6.3)
	bench.light_color = GarageRoom.LED
	bench.omni_range = 3.4
	bench.light_energy = 0.8
	bench.light_specular = 0.2
	add_child(bench)
	_extras.append(bench)


## The level's lights and effects (Graphics calls this when the settings change).
func _graphics_changed() -> void:
	if env == null:
		return
	Graphics.apply_environment(env)
	Graphics.apply_viewport(get_viewport())
	var f := Graphics.forward()
	var low := Graphics.level() == "low" or not f
	env.fog_enabled = false
	env.glow_enabled = Graphics.level() != "low" and not Graphics.headless()
	env.glow_intensity = 0.6
	env.glow_strength = 1.0
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.ssao_radius = 0.8
	env.ssao_intensity = 1.8
	env.ssr_max_steps = 48
	env.ssr_depth_tolerance = 0.2
	env.sdfgi_read_sky_light = false
	for k in _fills.size():
		(_fills[k] as Light3D).visible = k < (2 if low else 6)
		# (LOW's two stand in for all six: a little stronger)
		(_fills[k] as Light3D).light_energy = 1.4 if low else 0.9
	for l in _extras:
		(l as Light3D).visible = not low
	_spot.shadow_enabled = not Graphics.headless() and not (OS.has_feature("web") and Graphics.level() == "low")
	_spot.light_size = 0.6 if f and not low else 0.0           # (soft shadows: Forward+)
	_spot.shadow_blur = 1.5
	if _probe == null and not Graphics.headless():
		_probe = ReflectionProbe.new()
		_probe.name = "RoomReflections"
		_probe.position = Vector3(0.0, GarageRoom.HEIGHT * 0.5, 0.0)
		_probe.size = Vector3(GarageRoom.HALF_W * 2.0, GarageRoom.HEIGHT, GarageRoom.HALF_D * 2.0)
		_probe.box_projection = true
		_probe.interior = true
		_probe.update_mode = ReflectionProbe.UPDATE_ONCE
		_probe.cull_mask = GarageRoom.LAYER                   # (the room only: not the car, which changes)
		_probe.ambient_mode = ReflectionProbe.AMBIENT_ENVIRONMENT
		_probe.max_distance = 20.0
		add_child(_probe)


# ── the camera ────────────────────────────────────────────────────────────

func _process(dt: float) -> void:
	if not built:
		return
	_t = _hold if _hold >= 0.0 else _t + dt
	_blend += dt
	var want: Transform3D = _orbit_xf(_t) if showroom else _home_xf(_t)
	var fov := ORBIT_FOV if showroom else HOME_FOV
	if _blend < BLEND:
		var k := smoothstep(0.0, 1.0, _blend / BLEND)
		var q := _from.basis.get_rotation_quaternion().slerp(want.basis.get_rotation_quaternion(), k)
		want = Transform3D(Basis(q), _from.origin.lerp(want.origin, k))
		fov = lerpf(_from_fov, fov, k)
	cam.global_transform = want
	cam.fov = fov


## Where the home loop's camera is at time t, looking at the car.
func home_pos(t: float) -> Vector3:
	var u := fposmod(t / HOME_LAP, 1.0)
	u = fposmod(u - HOME_EASE * sin(TAU * u) / TAU, 1.0)            # (slowest at the hero view)
	var s := u * _path_len[_path_len.size() - 1]
	var lo := 0
	var hi := _path_len.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if _path_len[mid] <= s:
			lo = mid
		else:
			hi = mid
	var f := (s - _path_len[lo]) / maxf(_path_len[hi] - _path_len[lo], 1e-5)
	return _path[lo].lerp(_path[hi % _path.size()], f)


## Where the CARS orbit's camera is at time t.
func orbit_pos(t: float) -> Vector3:
	var a := _phase + TAU * t / ORBIT_LAP
	return SPOT + Vector3(sin(a) * ORBIT.x, ORBIT.y + 0.1 * sin(TAU * t / 23.0), cos(a) * ORBIT.z)


func _home_xf(t: float) -> Transform3D:
	return _framing(home_pos(t), HOME_SHIFT, HOME_FOV)


func _orbit_xf(t: float) -> Transform3D:
	return _framing(orbit_pos(t), ORBIT_SHIFT, ORBIT_FOV)


## A camera at p looking at the car, turned so the car sits `shift` of the way across the
## screen from the middle (+: to the right), whatever the screen's shape.
func _framing(p: Vector3, shift: float, fov: float) -> Transform3D:
	var box := _car_box if _car_box.size != Vector3.ZERO else AABB(SPOT + Vector3(-0.9, 0.0, -2.2), Vector3(1.8, 1.4, 4.4))
	var target := box.get_center()
	target.y = box.position.y + box.size.y * 0.42
	var aspect := 16.0 / 9.0
	var vp := get_viewport()
	if vp:
		var sz := vp.get_visible_rect().size
		if sz.y > 0.0:
			aspect = sz.x / sz.y
	var turn := atan(shift * tan(deg_to_rad(fov) * 0.5) * aspect)
	var xf := Transform3D(Basis(), p).looking_at(target, Vector3.UP)
	return Transform3D(Basis(Vector3.UP, turn) * xf.basis, p)


## The home loop sampled densely (and the distance along it): a centripetal Catmull-Rom
## spline through HOME_KEYS, closed.
func _sample_path() -> void:
	_path = PackedVector3Array()
	_path_len = PackedFloat32Array()
	var n := HOME_KEYS.size()
	for i in n:
		for s in 48:
			_path.append(_catmull(HOME_KEYS[(i - 1 + n) % n], HOME_KEYS[i], HOME_KEYS[(i + 1) % n], HOME_KEYS[(i + 2) % n], s / 48.0))
	_path.append(_path[0])
	var d := 0.0
	_path_len.append(0.0)
	for i in range(1, _path.size()):
		d += _path[i].distance_to(_path[i - 1])
		_path_len.append(d)


static func _catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, u: float) -> Vector3:
	var t1 := sqrt(maxf(p0.distance_to(p1), 1e-4))
	var t2 := t1 + sqrt(maxf(p1.distance_to(p2), 1e-4))
	var t3 := t2 + sqrt(maxf(p2.distance_to(p3), 1e-4))
	var t := lerpf(t1, t2, u)
	var a1 := p0 * ((t1 - t) / t1) + p1 * (t / t1)
	var a2 := p1 * ((t2 - t) / (t2 - t1)) + p2 * ((t - t1) / (t2 - t1))
	var a3 := p2 * ((t3 - t) / (t3 - t2)) + p3 * ((t - t2) / (t3 - t2))
	var b1 := a1 * ((t2 - t) / t2) + a2 * (t / t2)
	var b2 := a2 * ((t3 - t) / (t3 - t1)) + a3 * ((t - t1) / (t3 - t1))
	return b1 * ((t2 - t) / (t2 - t1)) + b2 * ((t - t1) / (t2 - t1))


## The home loop's time whose camera is nearest p (coming back from CARS: it carries on from there).
func _home_time_near(p: Vector3) -> float:
	var best := 0.0
	var best_d := INF
	for k in 400:
		var t := HOME_LAP * k / 400.0
		var d := home_pos(t).distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = t
	return best
