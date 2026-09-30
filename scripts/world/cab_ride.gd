extends Node
## A real cab ride: a yellow cab pulls up where you are (downtown by the taxi
## stand, Magnolia St, in front of your house, a dealership's lot), you get in the
## back, and the cabbie drives you there on the real roads: the streets, the
## roundabout, the highway, in traffic (CabRoutes plans the path, the same
## AiDriver the cops use drives it). The chase camera follows the cab.
##   SPACE  skip the ride (in rush hour the clock still runs: a blackout for the rest of it)
##   E      "right here's fine": the cab pulls over and lets you out
## Everyone else sees the cab (World streams it like your car) and you in the back.
## If the cab gets stuck for good, the driver "knows a shortcut" (the old fade).

const Rules = preload("res://scripts/sim/rules.gd")
const CabRoutes = preload("res://scripts/vehicle/cab_routes.gd")
const AiDriver = preload("res://scripts/vehicle/ai_driver.gd")
const Brands = preload("res://scripts/sim/brands.gd")

const NAMES := {"downtown": "downtown (BAGHOLDER CAPITAL)", "hood": "Magnolia Heights", "home": "home", "dealer": "BEMZE Motors"}
const CITY_SPEED := 13.0        # m/s on the streets (~30 mph)
const HWY_SPEED := 31.0         # on the highway (~70 mph)
const STUCK_S := 14.0

var world
var cab                          # the Car
var ai
var dest := ""
var path := PackedVector3Array()
var active := false
var rush := false
var _stuck := 0.0
var _last_pi := 0
var _stopping := false
var skipped := false             # the last ride was skipped (SPACE / stuck), not driven all the way
var driven := 0.0                # how far the cab has driven this ride (m)
var _hint: Label


func setup(w) -> void:
	world = w


## Where we are, as a cab place ("" = somewhere a cab can't get to).
func where_am_i() -> String:
	var p = world.local_player
	if p == null:
		return ""
	var at: Vector3 = p.global_position
	var hb = world.builder.hood
	if hb.in_hood(at):
		var home: Dictionary = world.home_of(Net.my_id())
		if not home.is_empty() and Vector2(at.x - home.drive.x, at.z - home.drive.z).length() < 30.0:
			return "home"
		return "hood"
	for br in hb.hw.dealers:
		if at.distance_to(hb.hw.dealers[br].lot) < 75.0:
			return "dealer" if br == "bemze" else br
	if at.z < 330.0 and at.x < 200.0:     # the office, the studio, the street
		return "downtown"
	return ""


## What the cabbie calls a place (the loop dealerships: their Brands name).
static func place_name(dest: String) -> String:
	if Brands.BRANDS.has(dest):
		return str(Brands.BRANDS[dest].motors)
	return str(NAMES.get(dest, dest))


## The cab's path from here to `to` ([] = no cab from here).
func plan(to: String) -> PackedVector3Array:
	var from := where_am_i()
	if from == "":
		return PackedVector3Array()
	return CabRoutes.plan(world.builder.hood.hw, from, to, world.home_of(Net.my_id()))


## Call the cab. False if no cab can do this trip (HoodController falls back to the old ride).
func start(to: String, is_rush: bool) -> bool:
	if active:
		return false
	var p = world.local_player
	if p == null or p.driving != null:
		return false
	path = plan(to)
	if path.size() < 4:
		return false
	dest = to
	rush = is_rush
	active = true
	_stopping = false
	skipped = false
	driven = 0.0
	_stuck = 0.0
	_last_pi = 0
	var fwd: Vector3 = (path[3] - path[0]).normalized()
	cab = world.spawn_cab(Net.my_id(), path[0] + Vector3(0, 0.3, 0), atan2(-fwd.x, -fwd.z))
	cab.simulate = true
	ai = AiDriver.new()
	ai.mode = "path"
	ai.path = path
	ai.cruise = CITY_SPEED
	cab.add_child(ai)
	p.board_cab(cab)
	world.hud.show_toast("Cab to %s. [SPACE] skip the ride   [E] let me out here" % place_name(to), Color(1.0, 0.85, 0.3))
	_show_hint(true)
	return true


func _physics_process(dt: float) -> void:
	if not active:
		return
	if cab == null or not is_instance_valid(cab) or world.local_player == null:
		_end(false)
		return
	world.send_cab(cab)
	driven += absf(cab.speed) * dt
	# city streets vs the highway
	var hw = world.builder.hood.hw
	var loc: Vector2 = hw.locate(cab.global_position)
	var on_hwy: bool = absf(loc.y) < 22.0 and loc.x > 20.0 and loc.x < hw.length - 20.0
	ai.cruise = HWY_SPEED if on_hwy else CITY_SPEED
	if _stopping:
		ai.done = true
		if absf(cab.speed) < 0.8:
			_end(true)
		return
	if ai.done and absf(cab.speed) < 0.8:
		_end(true)
		return
	# stuck (a pileup, a wall): after a while the driver takes a shortcut
	if ai._pi != _last_pi:
		_last_pi = ai._pi
		_stuck = 0.0
	else:
		_stuck += dt
		if _stuck > STUCK_S:
			world.hud.show_toast("\"I know a shortcut.\"", Color(1.0, 0.85, 0.3))
			skip()


func _unhandled_input(event: InputEvent) -> void:
	if not active or world.hud.is_modal_open():
		return
	if event.is_action_pressed("jump"):
		skip()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact"):
		if not _stopping:
			_stopping = true
			world.hud.show_toast("\"Right here's fine.\" The cab pulls over.", Color(1.0, 0.85, 0.3))
		get_viewport().set_input_as_handled()


## Fast-forward: straight to the drop-off (in rush hour the minutes still pass).
func skip() -> void:
	if not active:
		return
	skipped = true
	var left := 0.0
	for i in range(maxi(ai._pi, 0), path.size() - 1):
		left += path[i].distance_to(path[i + 1])
	var end_at: Vector3 = path[path.size() - 1]
	var back: Vector3 = path[maxi(path.size() - 4, 0)]
	var fwd := (end_at - back).normalized()
	cab.global_position = end_at + Vector3(0, 0.3, 0)
	cab.rotation = Vector3(0, atan2(-fwd.x, -fwd.z), 0)
	cab.velocity = Vector3.ZERO
	if rush:
		world.hud.blackout(clampf(left / 16.0, 3.0, 90.0), "In a cab. Bumper to bumper.\nThe meter says $%d." % int(Rules.CAB_FARE))
	_end(true)


func _end(arrived: bool) -> void:
	active = false
	_show_hint(false)
	var p = world.local_player
	if p != null and p.riding != null:
		var c = p.riding
		# out on the curb side (the cab's right), facing the way it was going
		var at: Vector3 = c.to_global(Vector3(1.9, 0.2, 0.6)) if is_instance_valid(c) else p.global_position
		p.leave_cab(at, c.global_rotation.y if is_instance_valid(c) else p.rotation.y)
	if arrived:
		world.hud.show_toast(_arrival_line(), Color(0.95, 0.9, 0.6))
	if ai and is_instance_valid(ai):
		ai.queue_free()
	ai = null
	world.remove_cab(Net.my_id())
	cab = null


func _arrival_line() -> String:
	match dest:
		"downtown":
			return "Downtown. The BAGHOLDER CAPITAL lobby is right here. Tip your driver (you didn't)."
		"hood":
			return "Magnolia Heights. Starter homes, cheap-ish. Look for the FOR SALE signs."
		"home":
			return "Home sweet home."
		"dealer":
			return "BEMZE Motors. Sales is inside, at the desk."
	if Brands.BRANDS.has(dest):
		return "%s. Sales is inside, at the desk." % place_name(dest)
	return "Here you go."


func _show_hint(on: bool) -> void:
	if _hint == null:
		_hint = Label.new()
		_hint.add_theme_font_size_override("font_size", 22)
		_hint.add_theme_color_override("font_outline_color", Color.BLACK)
		_hint.add_theme_constant_override("outline_size", 8)
		_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
		_hint.position.y -= 200
		_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		world.hud.root.add_child(_hint)
	_hint.visible = on
	_hint.text = "IN A CAB TO %s   ·   [SPACE] skip   ·   [E] let me out here" % place_name(dest).to_upper()
