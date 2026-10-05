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
##   reset car     R (+5 s)               Y
##   ready / next  enter                  start
##   pause         esc                    back

const STICK_DEADZONE := 0.12


func _ready() -> void:
	_action("steer_left", [KEY_A, KEY_LEFT], [], [[JOY_AXIS_LEFT_X, -1.0]])
	_action("steer_right", [KEY_D, KEY_RIGHT], [], [[JOY_AXIS_LEFT_X, 1.0]])
	_action("throttle", [KEY_W, KEY_UP], [], [[JOY_AXIS_TRIGGER_RIGHT, 1.0]])
	_action("brake", [KEY_S, KEY_DOWN], [], [[JOY_AXIS_TRIGGER_LEFT, 1.0]])
	_action("handbrake", [KEY_SPACE], [JOY_BUTTON_B, JOY_BUTTON_X], [])
	_action("read_notes", [KEY_Q], [], [[JOY_AXIS_TRIGGER_LEFT, 1.0]], [MOUSE_BUTTON_RIGHT])
	_action("wipers", [KEY_F], [JOY_BUTTON_A], [])
	_action("reset_car", [KEY_R], [JOY_BUTTON_Y], [])
	_action("ready", [KEY_ENTER, KEY_KP_ENTER], [JOY_BUTTON_START], [])
	_action("pause", [KEY_ESCAPE], [JOY_BUTTON_BACK], [])
	_action("camera", [KEY_C], [JOY_BUTTON_RIGHT_STICK], [])


func _action(name: String, keys: Array, buttons: Array, axes: Array, mouse := []) -> void:
	if InputMap.has_action(name):
		InputMap.erase_action(name)
	InputMap.add_action(name, 0.2)
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
