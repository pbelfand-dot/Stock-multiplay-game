extends Node3D
## TOUGE TIME ATTACK's GHOST: your best run on this pass (same seed, direction and
## rules) drives with you, a see-through car you can't hit, as in Initial D Arcade's
## and Forza's time attacks. The run is recorded every SAMPLE s of the clock (where
## the car is and how it's turned); a new record saves it beside the profile
## (ghost_<key>.bin), and the next run plays it back at the same clock.

const SAMPLE := 0.1                  # s between samples
const STRIDE := 8                    # floats a sample: t, position xyz, rotation quaternion xyzw
const ALPHA := 0.55                  # how see-through it is (0 solid .. 1 gone)
const NEAR := 4.0                    # m: closer than this it's gone (it starts where you do: not in the cockpit)
const FAR := 12.0                    # m: from here on it's ALPHA
const PARTS := "res://assets/models/car_parts/"
const MODELS := "res://assets/models/cars/"

var key := ""
var rec := PackedFloat32Array()      # this run
var best := PackedFloat32Array()     # the best run's (empty: none yet)
var best_model := ""                 # the car it was driven in ("" the shared rally body)
var _next_t := 0.0
var _body: Node3D
var _geoms: Array = []


## For the pass's key (Modes.best_key): load its ghost, if there's one.
func setup(key_: String) -> void:
	key = key_
	var f := FileAccess.open(file_for(key), FileAccess.READ)
	if f == null:
		return
	var d = f.get_var()
	if d is Dictionary and d.get("data") is PackedFloat32Array and (d.data as PackedFloat32Array).size() >= STRIDE * 2:
		best = d.data
		best_model = str(d.get("model", ""))
		_build_body()


## Where a pass's ghost is kept: beside the profile.
static func file_for(k: String) -> String:
	var Profile = load("res://scripts/game/profile.gd")
	return Profile.path().get_base_dir().path_join("ghost_%s.bin" % k.md5_text().substr(0, 16))


## One tick of the run: record the car (every SAMPLE s) and move the ghost to the clock.
## car_xf: the ground under the car's middle, turned with it (a model's origin).
func tick(clock: float, car_xf: Transform3D) -> void:
	if clock >= _next_t:
		var q := car_xf.basis.get_rotation_quaternion()
		rec.append_array([clock, car_xf.origin.x, car_xf.origin.y, car_xf.origin.z, q.x, q.y, q.z, q.w])
		_next_t = clock + SAMPLE
	if _body:
		var at = sample(best, clock)
		var gap: float = (at as Transform3D).origin.distance_to(car_xf.origin) if at != null else 0.0
		_body.visible = at != null and gap > NEAR
		if _body.visible:
			_body.global_transform = at
			var a := lerpf(0.95, ALPHA, clampf((gap - NEAR) / (FAR - NEAR), 0.0, 1.0))
			for g in _geoms:
				(g as GeometryInstance3D).transparency = a


## The ghost's transform at clock t (interpolated), or null past its finish.
static func sample(data: PackedFloat32Array, t: float):
	var n := data.size() / STRIDE
	if n < 2 or t > data[(n - 1) * STRIDE]:
		return null
	var lo := 0
	var hi := n - 1
	while hi - lo > 1:                                   # (the samples are in clock order)
		var mid := (lo + hi) / 2
		if data[mid * STRIDE] <= t:
			lo = mid
		else:
			hi = mid
	var a := lo * STRIDE
	var b := hi * STRIDE
	var u := clampf((t - data[a]) / maxf(data[b] - data[a], 1e-6), 0.0, 1.0)
	var pa := Vector3(data[a + 1], data[a + 2], data[a + 3])
	var pb := Vector3(data[b + 1], data[b + 2], data[b + 3])
	var qa := Quaternion(data[a + 4], data[a + 5], data[a + 6], data[a + 7])
	var qb := Quaternion(data[b + 4], data[b + 5], data[b + 6], data[b + 7])
	return Transform3D(Basis(qa.slerp(qb, u)), pa.lerp(pb, u))


## The run's a new record: keep it as the pass's ghost (model: the car it was driven in).
func save_record(model: String) -> void:
	if rec.size() < STRIDE * 2:
		return
	var f := FileAccess.open(file_for(key), FileAccess.WRITE)
	if f:
		f.store_var({"model": model, "data": rec})


## The see-through car: the best run's own model, or the shared rally body.
func _build_body() -> void:
	_body = Node3D.new()
	_body.name = "GhostCar"
	_body.visible = false
	add_child(_body)
	var path := MODELS + best_model + "/" + best_model + ".glb"
	if best_model != "" and ResourceLoader.exists(path):
		var m: Node3D = (load(path) as PackedScene).instantiate()
		_body.add_child(m)
	elif ResourceLoader.exists(PARTS + "body.res"):
		var mi := MeshInstance3D.new()
		mi.mesh = load(PARTS + "body.res")
		var holder := Node3D.new()
		holder.rotation.y = -PI / 2.0                    # (as RallyCar's shared body: nose down -X, 1.95 m a unit)
		holder.scale = Vector3.ONE * 1.95
		holder.position.y = 0.205 + 0.56                 # (its tyres on the ground: RallyCar.MODEL_GROUND)
		holder.add_child(mi)
		_body.add_child(holder)
	_fade(_body)


func _fade(n: Node) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).transparency = ALPHA
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_geoms.append(n)
	for c in n.get_children():
		_fade(c)
