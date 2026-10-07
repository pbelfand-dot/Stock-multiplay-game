extends RefCounted
## CUTTING UP: the score. Pure logic (no nodes), so the tests can drive it.
##
## A NEAR MISS is passing a traffic car close and fast: the moment the player's
## nose goes past the other car's (in road distance, s), the sideways gap between
## the two bodies is under `near` m, the player is doing at least MIN_SPEED and
## at least MIN_CLOSING faster than the car. It's worth more the closer and the
## faster: BASE x (closeness 1..3) x (speed 1..2), times the COMBO. Each near miss
## adds one to the combo; COMBO_TIME s without one and the combo is banked (its
## points join the score). A CRASH (hitting a traffic car or the barrier hard)
## throws the unbanked points away and costs CRASH_PENALTY.
## Speed itself pays a trickle (SPEED_RATE a second past FAST), into the combo's pot.

const MIN_SPEED := 80.0 / 3.6        # m/s: slower than this, passing isn't cutting up
const MIN_CLOSING := 10.0 / 3.6      # m/s faster than the car being passed
const BASE := 100
const COMBO_TIME := 4.0              # s to find the next near miss before the combo is banked
const FAST := 140.0 / 3.6            # m/s: faster than this, the speed trickle
const SPEED_RATE := 20.0             # points a second at FAST (more above it)
const CRASH_PENALTY := 500
const PLAYER_HALF_W := 0.95          # the player's car, half its width (m)

var near := 1.2                      # how close counts (m of gap between the bodies): the difficulty's
var score := 0                       # banked
var pot := 0.0                       # the combo's points, not banked yet
var combo := 0
var best_combo := 0
var near_misses := 0
var crashes := 0
var since_near := 0.0
var last_event := ""                 # "near" / "banked" / "crash" (the HUD flashes it)
var last_points := 0
var _rel := {}                       # car id -> the player's s minus the car's last tick


## One tick. me: {s, d, v (m/s along the road)}; cars: [{id, s, d, v, half_len, half_w}].
## Returns the near misses this tick (each {id, gap, points}).
func update(dt: float, me: Dictionary, cars: Array) -> Array:
	var got: Array = []
	since_near += dt
	if combo > 0 and since_near > COMBO_TIME:
		_bank()
	if float(me.v) > FAST:
		pot += SPEED_RATE * dt * float(me.v) / FAST * maxf(combo, 1)
	var seen := {}
	for c in cars:
		var rel: float = float(me.s) - float(c.s)          # > 0: the player's ahead of the car's middle
		seen[c.id] = true
		var was: float = _rel.get(c.id, rel)
		_rel[c.id] = rel
		# nose past the car's nose: from behind its front to ahead of it, this tick
		var nose: float = float(c.half_len)
		if not (was < nose and rel >= nose):
			continue
		if float(me.v) < MIN_SPEED or float(me.v) - float(c.v) < MIN_CLOSING:
			continue
		var gap: float = absf(float(me.d) - float(c.d)) - PLAYER_HALF_W - float(c.half_w)
		if gap < 0.0 or gap > near:
			continue                                        # (touching is a crash, the physics' business)
		var close := lerpf(3.0, 1.0, clampf(gap / near, 0.0, 1.0))
		var quick := clampf(float(me.v) / MIN_SPEED, 1.0, 2.0)
		combo += 1
		best_combo = maxi(best_combo, combo)
		near_misses += 1
		since_near = 0.0
		var pts := int(round(BASE * close * quick)) * combo
		pot += pts
		last_event = "near"
		last_points = pts
		got.append({"id": c.id, "gap": gap, "points": pts})
	for id in _rel.keys():                                  # cars gone from the pool
		if not seen.has(id):
			_rel.erase(id)
	return got


## A crash: the unbanked pot's gone, the combo too, and a penalty.
func crash() -> void:
	crashes += 1
	pot = 0.0
	combo = 0
	score = maxi(score - CRASH_PENALTY, 0)
	last_event = "crash"
	last_points = -CRASH_PENALTY


## The run's over: bank what's in the pot.
func finish() -> int:
	_bank()
	return score


func _bank() -> void:
	if pot > 0.0:
		score += int(round(pot))
		last_event = "banked"
		last_points = int(round(pot))
	pot = 0.0
	combo = 0


func total() -> int:
	return score + int(round(pot))


## Points from outside the near misses (a rival beaten): straight into the score.
func bonus(points: int) -> void:
	score += points
	last_event = "bonus"
	last_points = points
