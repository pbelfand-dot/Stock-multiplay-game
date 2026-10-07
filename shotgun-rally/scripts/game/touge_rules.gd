extends RefCounted
## TOUGE: splits and drift points. Pure logic (the tests drive it).
##
## SPLITS: the clock at every SPLIT_EVERY m past the start, compared with your best
## run on this pass (same seed, direction and rules): "-1.4" green, "+0.6" red.
##
## DRIFT: sliding pays. While the car's going over MIN_SPEED with its body more
## than MIN_ANGLE off the way it's travelling (and less than MAX_ANGLE: that's a
## spin), points flow: (angle past MIN_ANGLE) x km/h x RATE a second, times the
## chain's multiplier, which grows the longer the chain goes on (x1 to x4). A
## chain survives CHAIN_GAP s of straight driving between slides; then it's
## banked. Hitting something or dropping a wheel off the road loses the chain.

const SPLIT_EVERY := 1000.0
const MIN_SPEED := 30.0 / 3.6
const MIN_ANGLE := 10.0
const MAX_ANGLE := 100.0
const RATE := 0.05
const CHAIN_GAP := 1.2
const MAX_MULT := 4.0

# splits
var splits: Array = []               # the clock at each split this run
var best_splits: Array = []          # the best run's (empty: none yet)
var last_split_delta := INF          # this split minus the best's (INF: no best to compare)
var last_split_at := -1.0            # the clock when the last split was taken

# drift
var score := 0                       # banked
var chain := 0.0                     # the chain's points, not banked
var chain_time := 0.0                # s the chain's been going (the multiplier)
var since_slide := 0.0
var drifting := false
var angle := 0.0                     # the drift angle now (deg)
var best_chain := 0
var chains := 0
var lost := 0


## The clock passing s: a split when it crosses the next one.
func split_check(s: float, start_s: float, clock: float) -> bool:
	var due := (splits.size() + 1) * SPLIT_EVERY + start_s
	if s < due:
		return false
	splits.append(clock)
	var k := splits.size() - 1
	last_split_delta = clock - float(best_splits[k]) if k < best_splits.size() else INF
	last_split_at = clock
	return true


## One tick of drifting: the car's horizontal velocity and its forward direction,
## whether it's on the road.
func drift_update(dt: float, vel: Vector3, forward: Vector3, on_road: bool) -> void:
	var flat := Vector3(vel.x, 0.0, vel.z)
	var fwd := Vector3(forward.x, 0.0, forward.z).normalized()
	var speed := flat.length()
	angle = rad_to_deg(fwd.angle_to(flat.normalized())) if speed > 1.0 else 0.0
	drifting = speed > MIN_SPEED and angle > MIN_ANGLE and angle < MAX_ANGLE
	if chain > 0.0 and not on_road:
		lose()
		return
	if drifting:
		since_slide = 0.0
		chain_time += dt
		chain += (angle - MIN_ANGLE) * speed * 3.6 * RATE * dt * multiplier()
	else:
		since_slide += dt
		if chain > 0.0 and since_slide > CHAIN_GAP:
			bank()


func multiplier() -> float:
	return clampf(1.0 + chain_time / 4.0, 1.0, MAX_MULT)


func bank() -> void:
	if chain > 0.0:
		var pts := int(round(chain))
		score += pts
		best_chain = maxi(best_chain, pts)
		chains += 1
	chain = 0.0
	chain_time = 0.0


## A hit, or off the road: the chain's gone.
func lose() -> void:
	if chain > 0.0:
		lost += 1
	chain = 0.0
	chain_time = 0.0


func finish() -> int:
	bank()
	return score


func total() -> int:
	return score + int(round(chain))
