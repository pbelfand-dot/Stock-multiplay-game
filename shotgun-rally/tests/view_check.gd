extends SceneTree
## The driver's view at any frame rate: the autopilot drives a stage (crests and
## jumps included) and several seat cameras ride along, each worked out at its own
## frame rate (144 down to 12 fps), plus one at 60 fps that gets a 0.25 s hitch
## every 5 s. The head's spring used to go unstable below ~20 fps and slam the
## view up and down 6 cm EVERY frame: "the car bounces very rapidly, and it's not
## from anything on the road". Fails if the eye reverses direction frame after
## frame (more than 1 % of frames, by over 2 mm each way) or jumps too far in one.
## Run: godot --headless --fixed-fps 120 --path . -s tests/view_check.gd

const SECS := 45.0
const MAX_FLIP_SHARE := 0.01
const MAX_JUMP := 0.03          # m in one frame (a big landing at 12 fps is ~2 cm)

var StageGen
var StageBuilder
var RallyCar
var Autopilot
var SeatCam
var st
var car
var ap
var t := 0.0
var hint := -1
var cams := []                  # [{name, fps, cam, acc, frames: [eye y], hitch}]


func _initialize() -> void:
	StageGen = load("res://scripts/stage/stage_gen.gd")
	StageBuilder = load("res://scripts/stage/stage_builder.gd")
	RallyCar = load("res://scripts/vehicle/rally_car.gd")
	Autopilot = load("res://scripts/vehicle/autopilot.gd")
	SeatCam = load("res://scripts/vehicle/seat_cam.gd")
	st = StageGen.new()
	st.generate(15)
	var b = StageBuilder.new()
	root.add_child(b)
	b.build(st)
	car = RallyCar.new()
	root.add_child(car)
	car.place(st.world_at(st.START_S - 4.0, 0.0), st.heading_at(st.START_S))
	ap = Autopilot.new(st)
	for f in [144.0, 60.0, 30.0, 20.0, 15.0, 12.0, -60.0]:
		var cam = SeatCam.new()
		root.add_child(cam)
		cam.attach(car, "driver", Vector3(-0.37, 0.6, 0.26))
		var hitch: bool = f < 0.0
		cams.append({"name": "60 fps, hitches" if hitch else "%d fps" % f, "fps": absf(f), "cam": cam, "acc": 0.0,
			"frames": [], "hitch": hitch, "next_hitch": 5.0})


func _physics_process(dt: float) -> bool:
	if t == 0.0:
		# its frames are stepped here, at the rate under test (not before now: becoming
		# ready turns the engine's own _process calls back on)
		for c in cams:
			c.cam.set_process(false)
	t += dt
	var at: Dictionary = st.locate(car.global_position, hint)
	hint = at.i
	car.set_lanes(st, at.s, at.d)
	car.inp = ap.drive(car, at.s, at.d) if t > 1.0 else {"steer": 0.0, "throttle": 0.0, "brake": 0.0, "handbrake": false}
	for c in cams:
		c.acc += dt
		var fdt: float = 1.0 / c.fps
		if c.hitch and t >= c.next_hitch:
			# a hitch: no frame for 0.25 s, then one frame that long
			if t < c.next_hitch + 0.25:
				continue
			c.next_hitch += 5.0
			c.acc = 0.0
			_frame(c, 0.25)
			continue
		while c.acc >= fdt:
			c.acc -= fdt
			_frame(c, fdt)
	if t > SECS:
		var ok := true
		for c in cams:
			var f: Array = c.frames
			var flips := 0
			var jump := 0.0
			for i in range(1, f.size()):
				var d1: float = f[i] - f[i - 1]
				jump = maxf(jump, absf(d1))
				if i >= 2:
					var d0: float = f[i - 1] - f[i - 2]
					if signf(d1) != signf(d0) and absf(d1) > 0.002 and absf(d0) > 0.002:
						flips += 1
			var share := float(flips) / maxf(f.size(), 1)
			var good := share <= MAX_FLIP_SHARE and jump <= MAX_JUMP
			ok = ok and good
			print("[view] %s  %-16s %4d frames, the eye reverses frame after frame on %d (%.1f %%), biggest jump in a frame %.1f cm" % [
				"ok  " if good else "FAIL", c.name, f.size(), flips, share * 100.0, jump * 100.0])
		print("[view] %s" % ("VIEW OK" if ok else "VIEW FAIL (reversing on <= %.0f %% of frames, <= %.0f cm in a frame)" % [MAX_FLIP_SHARE * 100.0, MAX_JUMP * 100.0]))
		quit(0 if ok else 1)
		return true
	return false


func _frame(c: Dictionary, fdt: float) -> void:
	c.cam._process(fdt)
	if t > 3.0:
		c.frames.append(c.cam._lean.y)
