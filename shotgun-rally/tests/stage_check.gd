extends SceneTree
## Stage generator + pacenotes: every seed makes a sane stage.
## Run: godot --headless --path . -s tests/stage_check.gd
##   * same seed -> same stage (host and co-driver build their own copy)
##   * the road never comes back near itself, length is about right
##   * there are corners of every kind, the slopes are drivable
##   * every corner gets a note, the calls are in order and use known words
##   * wooden bridges: about one a stage, the same for the same seed, on straight
##     level road (not on a corner, a crest or a jump), no puddle on one, the
##     ground dug into a gully under it, a note ("caution") for each
##   * tarmac and mixed stages (_surfaces), the tarmac ones on a mountainside
##     (_mountains), every word said has a voice clip

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
	var bridges := 0
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
		if max_slope > 0.17:
			fails += _fail("seed %d: slope %.2f" % [seed_value, max_slope])
		if str(st.bridges) != str(st2.bridges):
			fails += _fail("seed %d: bridges not deterministic" % seed_value)
		bridges += st.bridges.size()
		for b in st.bridges:
			for c in st.corners:
				if c.s1 > b.s0 and c.s0 < b.s1:
					fails += _fail("seed %d: a bridge at %.0f m is on a corner" % [seed_value, b.s0])
			for c in st.crests:
				if absf(c.s - (b.s0 + b.s1) * 0.5) < c.w * 0.5 + 10.0:
					fails += _fail("seed %d: a bridge at %.0f m is on a crest" % [seed_value, b.s0])
			for p in st.puddles:
				if p.s > b.s0 - 2.0 and p.s < b.s1 + 2.0:
					fails += _fail("seed %d: a puddle on the bridge at %.0f m" % [seed_value, b.s0])
			if absf(st.point_at(b.s1).y - st.point_at(b.s0).y) > (b.s1 - b.s0) * 0.03 or st.gully_depth((b.s0 + b.s1) * 0.5, 0.0) < 2.0:
				fails += _fail("seed %d: the bridge at %.0f m isn't level or has no gully" % [seed_value, b.s0])
		var notes: Array = Notes.build(st)
		if notes.filter(func(n): return n.kind == "bridge").size() != st.bridges.size():
			fails += _fail("seed %d: not a note for every bridge" % seed_value)
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
			print("[stage] seed 1: %.0f m, %d corners, %d crests, %d puddles, %d calls" % [
				st.length, st.corners.size(), st.crests.size(), st.puddles.size(), calls.size()])
			for k in mini(10, calls.size()):
				var line := ""
				for w in calls[k].words:
					line += String(w) + " "
				print("[stage]   %5.0f m: %s" % [calls[k].s, line])
	fails += _surfaces(words)
	if bridges < 12:
		fails += _fail("only %d bridges in 20 stages" % bridges)
	print("[stage] %d wooden bridges in 20 stages" % bridges)
	for g in ["1", "2", "3", "4", "5", "6", "hairpin"]:
		if not grades.has(g):
			fails += _fail("no %s corners in 20 stages" % g)
	var dir := DirAccess.open("res://assets/voice/fraser")
	var missing: Array = []
	for w in words:
		if not FileAccess.file_exists("res://assets/voice/fraser/%s.mp3" % w):
			missing.append(w)
	print("[stage] words used: %d, without a voice clip yet: %s" % [words.size(), missing])
	if not missing.is_empty():
		fails += _fail("words with no voice clip: %s" % [missing])
	print("[stage] %s (%d ms)" % ["STAGES OK" if fails == 0 else "STAGES FAIL", Time.get_ticks_msec() - t0])
	quit(1 if fails > 0 else 0)
	return false


## Tarmac and mixed stages (10 seeds each, the tarmac ones with snow and ice):
## the same seed makes the same sections and patches; an ordinary stage is all
## gravel with nothing on it; asphalt has no jumps, wooden bridges or mud
## puddles; a mixed stage's joins are on straight road, each called, the one onto
## asphalt with gravel dragged across it; what lies on the asphalt is only on
## asphalt, ice never in a slow corner, each called (and a dirty corner inside
## says "don't cut").
func _surfaces(words: Dictionary) -> int:
	var fails := 0
	var counts := {"join": 0, "cut": 0, "ice": 0, "snow": 0}
	for seed_value in range(1, 11):
		var plain = StageGen.new()
		plain.generate(seed_value)
		if plain.sections.size() != 1 or plain.sections[0].surface != "gravel" or not plain.patches.is_empty() or not plain.joins.is_empty():
			fails += _fail("seed %d: an ordinary stage isn't plain gravel" % seed_value)
		for gen in [{"surface": "tarmac", "ice": true}, {"surface": "mixed"}]:
			var st = StageGen.new()
			st.opts = gen
			st.generate(seed_value)
			var st2 = StageGen.new()
			st2.opts = gen
			st2.generate(seed_value)
			var tag := "seed %d %s" % [seed_value, gen.surface]
			if str(st.sections) != str(st2.sections) or str(st.patches) != str(st2.patches):
				fails += _fail("%s: sections / patches not deterministic" % tag)
			if gen.surface == "tarmac" and (st.sections.size() != 1 or st.sections[0].surface != "asphalt"):
				fails += _fail("%s: not all asphalt" % tag)
			if gen.surface == "mixed":
				if st.sections.size() < 2:
					fails += _fail("%s: only one section" % tag)
				for k in range(1, st.sections.size()):
					if st.sections[k].surface == st.sections[k - 1].surface or st.sections[k].s0 != st.sections[k - 1].s1:
						fails += _fail("%s: sections don't alternate end to end" % tag)
			var notes: Array = Notes.build(st)
			for j in st.joins:
				for x in range(int((j.s - 10.0) / st.STEP), int((j.s + 10.0) / st.STEP)):
					if absf(st.curv[x]) > 1.0 / 150.0:
						fails += _fail("%s: the join at %.0f m isn't on a straight" % [tag, j.s])
						break
				if notes.filter(func(n): return n.kind == "surface" and n.s_end == j.s).size() != 1:
					fails += _fail("%s: the join at %.0f m isn't called" % [tag, j.s])
				if j.to == "asphalt" and st.patch_at(j.s + 10.0, 0.0, "join").is_empty():
					fails += _fail("%s: no gravel dragged onto the asphalt after the join at %.0f m" % [tag, j.s])
			for c in st.crests:
				if c.jump and not st.all_gravel(c.s + c.x0, c.s + c.x0 + c.prof.size()):
					fails += _fail("%s: a jump on the asphalt at %.0f m" % [tag, c.s])
			for b in st.bridges:
				if not st.all_gravel(b.s0, b.s1):
					fails += _fail("%s: a wooden bridge on the asphalt at %.0f m" % [tag, b.s0])
			for p in st.puddles:
				if not st.all_gravel(p.s - p.r, p.s + p.r):
					fails += _fail("%s: a mud puddle on the asphalt at %.0f m" % [tag, p.s])
			for p in st.patches:
				counts[p.kind] += 1
				if st.surface_at(p.s0) != "asphalt" or st.surface_at(p.s1) != "asphalt":
					fails += _fail("%s: a %s patch off the asphalt at %.0f m" % [tag, p.kind, p.s0])
				if p.kind == "ice":
					if st._slow_corner(p.s0 - 5.0, p.s1):
						fails += _fail("%s: ice in a slow corner at %.0f m" % [tag, p.s0])
					if notes.filter(func(n): return n.kind == "ice" and n.s_end == p.s1).size() != 1:
						fails += _fail("%s: the ice at %.0f m isn't called" % [tag, p.s0])
			for c in st.corners:
				if "dont-cut" in c.mods and st.patch_at((c.s0 + c.s1) * 0.5, 2.0 * c.dir, "cut").is_empty():
					fails += _fail("%s: \"don't cut\" at %.0f m with no gravel on the inside" % [tag, c.s0])
			for c in Notes.calls(notes):
				for w in c.words:
					words[w] = true
	fails += _mountains()
	print("[stage] tarmac / mixed: %d joins, %d dirty corners (don't cut), %d ice patches, %d snowy edges in 20 stages" % [
		counts.join, counts.cut, counts.ice, counts.snow])
	for k in counts:
		if counts[k] < 3:
			fails += _fail("only %d %s patches" % [counts[k], k])
	return fails


## Mountain (tarmac) stages, 10 seeds: a mountain at all (the road climbs and
## drops 30 m or more), the mountainside meets the road (never more than 3.5 m
## off it, so no canyons or dykes), more hairpins than a forest stage, villages
## on the asphalt clear of the start, the finish and the joins, towns (no hairpin
## in one, no village in one); and a gravel or mixed stage is no mountain (its
## ground is flat as before, no towns).
func _mountains() -> int:
	var fails := 0
	var hairpins := {"tarmac": 0, "gravel": 0}
	var villages := 0
	var towns := 0
	for seed_value in range(1, 11):
		var st = StageGen.new()
		st.opts = {"surface": "tarmac"}
		st.generate(seed_value)
		var flat = StageGen.new()
		flat.opts = {"surface": "mixed"}
		flat.generate(seed_value)
		if not st.mountain or flat.mountain or flat.terrain_at(100.0, 100.0) != 0.0:
			fails += _fail("seed %d: only the tarmac stage is a mountain" % seed_value)
		var lo := INF
		var hi := -INF
		var off := 0.0
		for i in st.pts.size():
			var p: Vector3 = st.pts[i]
			lo = minf(lo, p.y)
			hi = maxf(hi, p.y)
			if i * st.STEP > st.START_S and i * st.STEP < st.finish_s + 60.0:     # (from the start line to where you stop)
				off = maxf(off, absf(p.y - st.terrain_at(p.x, p.z)))
		if hi - lo < 30.0:
			fails += _fail("seed %d: a mountain stage only climbs %.0f m" % [seed_value, hi - lo])
		if off > 3.5:
			fails += _fail("seed %d: the road is %.1f m off the mountainside" % [seed_value, off])
		for c in st.corners:
			if c.shape == "hairpin":
				hairpins.tarmac += 1
		var plain = StageGen.new()
		plain.generate(seed_value)
		for c in plain.corners:
			if c.shape == "hairpin":
				hairpins.gravel += 1
		if not flat.towns.is_empty():
			fails += _fail("seed %d: a town on a stage that isn't a mountain one" % seed_value)
		for t in st.towns:
			towns += 1
			if not st._gentle(t.s0, t.s1, 1.0 / 18.0):
				fails += _fail("seed %d: a hairpin in the town at %.0f m" % [seed_value, t.s0])
			if t.s0 < st.START_S + 200.0 or t.s1 > st.finish_s - 200.0:
				fails += _fail("seed %d: a town by the start or finish at %.0f m" % [seed_value, t.s0])
			for v in st.villages:
				if v.s1 > t.s0 - 100.0 and v.s0 < t.s1 + 100.0:
					fails += _fail("seed %d: a village in the town at %.0f m" % [seed_value, t.s0])
		for v in st.villages + flat.villages:
			villages += 1
			var host = st if st.villages.has(v) else flat
			if host.surface_at(v.s0 - 20.0) != "asphalt" or host.surface_at(v.s1 + 20.0) != "asphalt":
				fails += _fail("seed %d: a village off the asphalt at %.0f m" % [seed_value, v.s0])
			if v.s0 < host.START_S + 200.0 or v.s1 > host.finish_s - 200.0:
				fails += _fail("seed %d: a village by the start or finish at %.0f m" % [seed_value, v.s0])
			for j in host.joins:
				if j.s > v.s0 - 60.0 and j.s < v.s1 + 60.0:
					fails += _fail("seed %d: a village on a join at %.0f m" % [seed_value, v.s0])
	print("[stage] mountains: %d hairpins in 10 tarmac stages (%d on the same seeds in gravel), %d villages, %d towns" % [
		hairpins.tarmac, hairpins.gravel, villages, towns])
	if towns < 4:
		fails += _fail("only %d towns" % towns)
	if hairpins.tarmac < hairpins.gravel * 1.3 or hairpins.tarmac < 35:
		fails += _fail("not enough hairpins on the mountain stages")
	if villages < 8:
		fails += _fail("only %d villages" % villages)
	return fails


func _fail(msg: String) -> int:
	print("[stage] FAIL ", msg)
	return 1
