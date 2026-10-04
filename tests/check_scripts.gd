extends SceneTree
## Compiles every script in the project; exits 1 if any fail.
## Run: godot --headless --path . -s tests/check_scripts.gd

var _done := false


func _process(_d: float) -> bool:
	if _done:
		return true
	_done = true
	var bad := 0
	var files := _collect("res://scripts") + _collect("res://tests")
	for f in files:
		var s = load(f)
		if s == null or (s is GDScript and not s.can_instantiate()):
			printerr("COMPILE FAIL: ", f)
			bad += 1
	print("checked %d scripts, %d failed" % [files.size(), bad])
	quit(1 if bad > 0 else 0)
	return false


func _collect(dir: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir + "/" + f)
	for sub in d.get_directories():
		out += _collect(dir + "/" + sub)
	return out
