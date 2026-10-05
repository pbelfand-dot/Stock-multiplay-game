extends RefCounted
## The stage's pacenotes: what the AI co-driver says. (A human co-driver gets
## no notes, only the map: reading the road is their job.) Built from the generator's corners / crests / puddles, in
## the order you meet them. Same rules as the driver-test-app pacenote engine
## (rally/pacenotes.js): grades 6 (nearly flat) .. 1 (very slow), "into" / "and"
## when corners run together, otherwise the distance to the next note, and
## notes close together are read out as one call.
##
## A note: {kind: "corner" | "crest" | "jump" | "water" | "finish", s, s_end,
##   dir (-1 left / +1 right), grade, grade2, shape ("" | "hairpin" | "square"),
##   mods [...], caution, link ("" | "into" | "and"), dist (m, 0 = none)}
## Words are voice clip names (assets/voice/fraser/<word>.mp3).

const NICE_DISTANCES := [30, 40, 50, 60, 70, 80, 100, 120, 150, 200, 250, 300, 350,
	400, 450, 500, 600, 700, 800, 900, 1000]
const INTO_GAP := 15.0          # corners closer than this: "into"
const AND_GAP := 40.0           # ... closer than this: "and"
const MAX_CALLED_GAP := 1000.0  # longer straights aren't called as a distance
const LINK_GAP := 45.0          # notes closer than this are read out together (they run into each other)
const MAX_PER_CALL := 3         # ... at most this many: more is too much to remember
const CAUTION_STRAIGHT := 180.0 # a slow corner after this much straight gets "caution"


static func build(st) -> Array:
	var out: Array = []
	for c in st.corners:
		out.append({"kind": "corner", "s": c.s0, "s_end": c.s1, "dir": c.dir, "grade": c.grade,
			"grade2": c.get("grade2", 0), "shape": c.shape, "mods": c.mods.duplicate(), "caution": false})
	for cr in st.crests:
		out.append({"kind": "jump" if cr.jump else "crest", "s": cr.s - cr.w * 0.5, "s_end": cr.s})
	var last_water := -1000.0
	for p in st.puddles:
		if p.s - last_water > 30.0:              # a pair of puddles is one note
			out.append({"kind": "water", "s": p.s - p.r, "s_end": p.s + p.r})
			last_water = p.s
	out.append({"kind": "finish", "s": st.finish_s, "s_end": st.finish_s})
	out.sort_custom(func(a, b): return a.s < b.s)
	# links and distances
	for i in out.size():
		var n: Dictionary = out[i]
		n["link"] = ""
		n["dist"] = 0
		if i + 1 >= out.size():
			continue
		var nx: Dictionary = out[i + 1]
		var gap: float = nx.s - n.s_end
		if n.kind == "corner" and nx.kind == "corner" and gap < INTO_GAP:
			n.link = "into"
		elif gap < AND_GAP:
			# corner -> corner: "and"; a crest / splash right there needs no joining word
			n.link = "and" if n.kind == "corner" and nx.kind == "corner" else ""
		elif gap <= MAX_CALLED_GAP:
			n.dist = nice_distance(gap)
	# caution: a slow corner at the end of a long straight
	for i in out.size():
		var n: Dictionary = out[i]
		if n.kind != "corner" or not (n.grade <= 2 or n.shape != ""):
			continue
		var prev_end: float = out[i - 1].s_end if i > 0 else 0.0
		if n.s - prev_end >= CAUTION_STRAIGHT:
			n.caution = true
	return out


## The called distance for a gap: the biggest nice number that doesn't overshoot it by much.
static func nice_distance(gap: float) -> int:
	var best: int = NICE_DISTANCES[0]
	for d in NICE_DISTANCES:
		if d <= gap * 1.08:
			best = d
	return best


## The words of one note (without its link / distance).
static func words(n: Dictionary) -> Array:
	match n.kind:
		"crest":
			return ["over-crest"]
		"jump":
			return ["jump"]
		"water":
			return ["water"]
		"finish":
			return ["finish"]
	var w: Array = []
	if n.caution:
		w.append("caution")
	w.append(n.shape if n.shape != "" else str(n.grade))
	w.append("left" if n.dir < 0 else "right")
	for m in n.mods:
		match m:
			"tightens":
				w.append("tightens")
				if n.grade2 > 0:
					w.append(str(n.grade2))
			_:
				w.append(m)
	return w


## The words after a note: "into" / "and" / a distance / nothing.
static func link_words(n: Dictionary) -> Array:
	if n.link != "":
		return [n.link]
	if n.dist > 0:
		return [str(n.dist)]
	return []


## Calls: notes read out together. [{first, last, s, s_end, words}] where s is
## where the first note starts and s_end where the last one ends.
static func calls(notes: Array) -> Array:
	var out: Array = []
	var i := 0
	while i < notes.size():
		var j := i
		while j + 1 < notes.size() and j - i + 1 < MAX_PER_CALL \
				and notes[j + 1].s - notes[j].s_end < LINK_GAP:
			j += 1
		var w: Array = []
		for k in range(i, j + 1):
			w += words(notes[k])
			w += link_words(notes[k])
		if not w.is_empty() and w[-1] == "and":
			w.pop_back()                     # the next call follows right away: no dangling "and"
		out.append({"first": i, "last": j, "s": notes[i].s, "s_end": notes[j].s_end, "words": w})
		i = j + 1
	return out


## Human-readable text of a note, for logs.
static func text(n: Dictionary) -> String:
	var parts: Array = []
	for w in words(n) + link_words(n):
		parts.append(String(w).replace("-", " ").to_upper().replace("DONT", "DON'T"))
	return " ".join(parts)
