extends SceneTree
## Stage generator + pacenotes: every seed makes a sane stage.
## Run: godot --headless --path . -s tests/stage_check.gd
##   * same seed -> same stage (host and co-driver build their own copy)
##   * the road never comes back near itself, length is about right
##   * there are corners of every kind, the slopes are drivable
##   * every corner gets a note, the calls are in order and use known words

const StageGen = preload("res://scripts/stage/stage_gen.gd")
const Notes = preload("res://scripts/stage/pacenotes.gd")

var _done := false


func _process(_d: float) -> bool:
	if _done:
		return true
	_done = true
	var fails := 0
	var words := {}
	var grades := {}
	var t0 := Time.get_ticks_msec()
	for seed_value in range(1, 21):
		var st = StageGen.new()
		st.generate(seed_value)
		var st2 = StageGen.new()
		st2.generate(seed_value)
		if st.pts.size() != st2.pts.size() or st.pts[st.pts.size() / 2] != st2.pts[st2.pts.size() / 2]:
			fails += _fail("seed %d: not deterministic" % seed_value)
		if st.length < 2000.0 or st.length > 3400.0:
			fails += _fail("seed %d: length %.0f m" % [seed_value, st.length])
		if not st._clear_of_itself():
			fails += _fail("seed %d: road crosses itself" % seed_value)
		var max_slope := 0.0
		for i in range(1, st.pts.size()):
			max_slope = maxf(max_slope, absf(st.pts[i].y - st.pts[i - 1].y) / st.STEP)
		if max_slope > 0.45:
			fails += _fail("seed %d: slope %.2f" % [seed_value, max_slope])
		var notes: Array = Notes.build(st)
		var corner_notes := 0
		for n in notes:
			if n.kind == "corner":
				corner_notes += 1
				grades[n.shape if n.shape != "" else str(n.grade)] = true
				if n.grade2 > 0:
					grades[str(n.grade2)] = true
		if corner_notes != st.corners.size() or corner_notes < 12:
			fails += _fail("seed %d: %d corner notes for %d corners" % [seed_value, corner_notes, st.corners.size()])
		var calls: Array = Notes.calls(notes)
		var last_s := -1.0
		for c in calls:
			if c.s < last_s:
				fails += _fail("seed %d: calls out of order" % seed_value)
			last_s = c.s
			for w in c.words:
				words[w] = true
		# locate() round trip
		var probe: Vector3 = st.world_at(800.0, 1.5)
		var back: Dictionary = st.locate(probe)
		if absf(back.s - 800.0) > 0.5 or absf(back.d - 1.5) > 0.2:
			fails += _fail("seed %d: locate %s" % [seed_value, back])
		if seed_value == 1:
			print("[stage] seed 1: %.0f m, %d corners, %d crests, %d puddles, %d rocks, %d calls" % [
				st.length, st.corners.size(), st.crests.size(), st.puddles.size(), st.rocks.size(), calls.size()])
			for k in mini(10, calls.size()):
				var line := ""
				for w in calls[k].words:
					line += String(w) + " "
				print("[stage]   %5.0f m: %s" % [calls[k].s, line])
	for g in ["1", "2", "3", "4", "5", "6", "hairpin"]:
		if not grades.has(g):
			fails += _fail("no %s corners in 20 stages" % g)
	var dir := DirAccess.open("res://assets/voice/fraser")
	var missing: Array = []
	for w in words:
		if not FileAccess.file_exists("res://assets/voice/fraser/%s.mp3" % w):
			missing.append(w)
	print("[stage] words used: %d, without a voice clip yet: %s" % [words.size(), missing])
	print("[stage] %s (%d ms)" % ["STAGES OK" if fails == 0 else "STAGES FAIL", Time.get_ticks_msec() - t0])
	quit(1 if fails > 0 else 0)
	return false


func _fail(msg: String) -> int:
	print("[stage] FAIL ", msg)
	return 1
