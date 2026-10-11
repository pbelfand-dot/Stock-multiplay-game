extends Node
## The input map (autoload "Controls"), set up in code so keyboard and
## controller live side by side. Each seat only reads its own actions, so the
## same button can mean different things in the two seats.
##
##   DRIVER        keyboard               controller
##   steer         A / D, arrows          left stick
##   throttle      W / up                 right trigger
##   brake/reverse S / down               left trigger
##   handbrake     space                  B / X
##   CO-DRIVER
##   read notes    hold right mouse / Q   hold left trigger
##   wipers        F                      A
##   BOTH
##   look around   mouse                  right stick
##   camera        C (driver: chase cam)  right stick click
##   flash lights  H (cut up: challenge   left shoulder
##                 the rival ahead)
##   dome light    L                      d-pad up
##   screen page   M (the centre screen:  d-pad right
##                 map / driving data)
##   reset car     R (+5 s)               Y
##   ready / next  enter                  start
##   pause         esc                    back
##   replay        V (the results, the    X
##                 pause menu)
## In a replay (replay.gd; docs/replay.md has the whole list): space / A play, left and right
## (d-pad) step 5 s or held rewind and fast-forward, up and down (d-pad) the speed, home / end
## (start) the ends, tab / Y the next car, C / X the next camera, P / R3 place a camera, G the
## director, H / L3 the bar, backspace / B (or esc / back) out; the free cam flies on WASD,
## Q / E (LB / RB) down and up, shift / RT fast, ctrl / LT slow, the right mouse button held
## (right stick) to look.

const STICK_DEADZONE := 0.12
## The steering stick's deadzone: small, so a little stick is a little steering (at 0.2 the
## first fifth of the stick did nothing: the video study). The other actions keep 0.2.
const STEER_DEADZONE := 0.07


func _ready() -> void:
	_action("steer_left", [KEY_A, KEY_LEFT], [], [[JOY_AXIS_LEFT_X, -1.0]], [], STEER_DEADZONE)
	_action("steer_right", [KEY_D, KEY_RIGHT], [], [[JOY_AXIS_LEFT_X, 1.0]], [], STEER_DEADZONE)
	_action("throttle", [KEY_W, KEY_UP], [], [[JOY_AXIS_TRIGGER_RIGHT, 1.0]])
	_action("brake", [KEY_S, KEY_DOWN], [], [[JOY_AXIS_TRIGGER_LEFT, 1.0]])
	_action("handbrake", [KEY_SPACE], [JOY_BUTTON_B, JOY_BUTTON_X], [])
	_action("read_notes", [KEY_Q], [], [[JOY_AXIS_TRIGGER_LEFT, 1.0]], [MOUSE_BUTTON_RIGHT])
	_action("wipers", [KEY_F], [JOY_BUTTON_A], [])
	_action("reset_car", [KEY_R], [JOY_BUTTON_Y], [])
	_action("ready", [KEY_ENTER, KEY_KP_ENTER], [JOY_BUTTON_START], [])
	_action("pause", [KEY_ESCAPE], [JOY_BUTTON_BACK], [])
	_action("camera", [KEY_C], [JOY_BUTTON_RIGHT_STICK], [])
	_action("flash", [KEY_H], [JOY_BUTTON_LEFT_SHOULDER], [])
	_action("dome_light", [KEY_L], [JOY_BUTTON_DPAD_UP], [])
	_action("screen_page", [KEY_M], [JOY_BUTTON_DPAD_RIGHT], [])
	_action("pit_limiter", [KEY_P], [JOY_BUTTON_DPAD_DOWN], [])
	# the replay (replay.gd): opened from the results or the pause menu, its own keys while it's on
	_action("replay", [KEY_V], [JOY_BUTTON_X], [])
	_action("replay_play", [KEY_SPACE], [JOY_BUTTON_A], [])
	_action("replay_exit", [KEY_BACKSPACE], [JOY_BUTTON_B], [])
	_action("replay_back", [KEY_LEFT], [JOY_BUTTON_DPAD_LEFT], [])
	_action("replay_fwd", [KEY_RIGHT], [JOY_BUTTON_DPAD_RIGHT], [])
	_action("replay_faster", [KEY_UP, KEY_EQUAL, KEY_KP_ADD], [JOY_BUTTON_DPAD_UP], [])
	_action("replay_slower", [KEY_DOWN, KEY_MINUS, KEY_KP_SUBTRACT], [JOY_BUTTON_DPAD_DOWN], [])
	_action("replay_start", [KEY_HOME], [JOY_BUTTON_START], [])
	_action("replay_end", [KEY_END], [], [])
	_action("replay_car_next", [KEY_TAB, KEY_PAGEDOWN], [JOY_BUTTON_Y], [])
	_action("replay_car_prev", [KEY_PAGEUP], [], [])
	_action("replay_cam_next", [KEY_C], [JOY_BUTTON_X], [])
	_action("replay_cam_prev", [KEY_X], [], [])
	_action("replay_hud", [KEY_H], [JOY_BUTTON_LEFT_STICK], [])
	_action("replay_place", [KEY_P], [JOY_BUTTON_RIGHT_STICK], [])
	_action("replay_director", [KEY_G], [], [])
	_action("replay_clear", [KEY_DELETE], [], [])
	_action("replay_look", [], [], [], [MOUSE_BUTTON_RIGHT])
	_action("replay_fly_forward", [KEY_W], [], [[JOY_AXIS_LEFT_Y, -1.0]], [], STICK_DEADZONE)
	_action("replay_fly_back", [KEY_S], [], [[JOY_AXIS_LEFT_Y, 1.0]], [], STICK_DEADZONE)
	_action("replay_fly_left", [KEY_A], [], [[JOY_AXIS_LEFT_X, -1.0]], [], STICK_DEADZONE)
	_action("replay_fly_right", [KEY_D], [], [[JOY_AXIS_LEFT_X, 1.0]], [], STICK_DEADZONE)
	_action("replay_fly_up", [KEY_E], [JOY_BUTTON_RIGHT_SHOULDER], [])
	_action("replay_fly_down", [KEY_Q], [JOY_BUTTON_LEFT_SHOULDER], [])
	_action("replay_fly_fast", [KEY_SHIFT], [], [[JOY_AXIS_TRIGGER_RIGHT, 1.0]], [], 0.1)
	_action("replay_fly_slow", [KEY_CTRL], [], [[JOY_AXIS_TRIGGER_LEFT, 1.0]], [], 0.1)


func _action(name: String, keys: Array, buttons: Array, axes: Array, mouse := [], deadzone := 0.2) -> void:
	if InputMap.has_action(name):
		InputMap.erase_action(name)
	InputMap.add_action(name, deadzone)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(name, e)
	for b in buttons:
		var e := InputEventJoypadButton.new()
		e.button_index = b
		InputMap.action_add_event(name, e)
	for ax in axes:
		var e := InputEventJoypadMotion.new()
		e.axis = ax[0]
		e.axis_value = ax[1]
		InputMap.action_add_event(name, e)
	for m in mouse:
		var e := InputEventMouseButton.new()
		e.button_index = m
		InputMap.action_add_event(name, e)


## Right stick look (radians per second worth of deflection), deadzoned.
func look_stick() -> Vector2:
	var v := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	if v.length() < STICK_DEADZONE:
		return Vector2.ZERO
	return v * ((v.length() - STICK_DEADZONE) / (1.0 - STICK_DEADZONE) / v.length())


## True if a controller is plugged in (the hints show its buttons).
func has_pad() -> bool:
	return Input.get_connected_joypads().size() > 0
