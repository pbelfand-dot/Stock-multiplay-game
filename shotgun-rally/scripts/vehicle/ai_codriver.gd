extends Node
## The AI co-driver: reads the calls in the "Fraser" voice when nobody's in
## the passenger seat. Same job a human co-driver does: count the start, call
## each corner from WHERE THE CAR IS, say "finish".
##   * a call starts when the car is LEAD seconds (plus the time it takes to say
##     it) from its first corner, at the speed the car is doing now: faster =
##     earlier, slowed down = later, stopped = only once it's close
##   * one call at a time, like a real co-driver: the next one waits until the
##     last one's been said and its corner is about to arrive, so you never hear
##     three corners ahead of where you are
##   * a call whose corners are already behind the car is dropped, even halfway
##     through saying it (a reset, a spin, a slow corner)
##   * a reset (the car jumps along the road) starts over from the new spot
## Clips are strung together word by word (assets/voice/fraser/<word>.mp3);
## a word with no clip yet is skipped. The speaking time is counted from the
## clip lengths, not the audio player, so it times the same with no sound card.

const VOICE_DIR := "res://assets/voice/fraser/"
const GAP := 0.03               # silence between words (s)
const LEAD := 1.8               # seconds between the end of a call and its first corner
const MIN_LEAD := 35.0          # m: slow or stopped, a call still comes this far out
const NEXT_WHEN := 1.5          # s: the next call waits until the last one's first corner is this close
const JUMP := 25.0              # m: the car moved this far in one tick = it was put back on the road

var calls: Array = []           # from Pacenotes.calls()
var next_call := 0
var enabled := true
var said: Array = []            # log of [car_s, call_s, words, speed] for the tests
var dropped := 0                # calls (or the rest of them) dropped because the car was past them
var _clips := {}                # word -> AudioStream
var _queue: Array = []          # [word, call index or -1] still to say
var _player: AudioStreamPlayer
var _talk_left := 0.0           # s until the word being said is over
var _car_s := 0.0
var _last_s := -INF


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.volume_db = 2.0
	_player.bus = "Voice"
	add_child(_player)
	# list_directory (not DirAccess) also works in exported builds, where the mp3s are imported
	for f in ResourceLoader.list_directory(VOICE_DIR):
		if f.ends_with(".mp3"):
			_clips[f.get_basename()] = load(VOICE_DIR + f)


func setup(stage_calls: Array) -> void:
	calls = stage_calls
	next_call = 0
	_queue.clear()
	said.clear()
	dropped = 0
	_last_s = -INF


func has_word(w: String) -> bool:
	return _clips.has(w)


## Say these words now (after whatever's being said): the countdown, "wipers"...
func say(words: Array, call_index := -1) -> void:
	for w in words:
		if _clips.has(w):
			_queue.append([w, call_index])


## Seconds it takes to say these words.
func duration(words: Array) -> float:
	var t := 0.0
	for w in words:
		if _clips.has(w):
			t += _clips[w].get_length() + GAP
	return t


## Every physics tick: where the car is along the stage (m) and how fast it's going.
func update(car_s: float, speed: float, dt: float) -> void:
	_car_s = car_s
	if enabled and car_s > -999.0:
		if absf(car_s - _last_s) > JUMP and _last_s > -INF:
			_resync(car_s)
		_last_s = car_s
		# calls whose corners are all behind the car: too late to be any use
		while next_call < calls.size() and calls[next_call].s_end < car_s:
			if Config.flag("aitrace"):
				print("[ai]   at %5.0f m: skipped call %d (ends %5.0f m) %s" % [car_s, next_call, calls[next_call].s_end, " ".join(calls[next_call].words)])
			next_call += 1
			dropped += 1
		if next_call < calls.size() and _ready_for_next(car_s, speed):
			var c: Dictionary = calls[next_call]
			var v := maxf(speed, 0.0)
			var lead: float = maxf(MIN_LEAD, v * (LEAD + 0.6 * Config.call_early + duration(c.words)))
			if c.s - car_s <= lead:
				say(c.words, next_call)
				said.append([car_s, c.s, c.words, v])
				if Config.flag("aitrace"):
					print("[ai]   at %5.0f m, %4.0f km/h: call %d (%5.0f..%5.0f m, %.1f s out) %s" % [car_s, v * 3.6, next_call, c.s, c.s_end, (c.s - car_s) / maxf(v, 1.0), " ".join(c.words)])
				next_call += 1
	_pump(dt)


## One call at a time: nothing still being said, and the last call's first corner
## is close (or behind us).
func _ready_for_next(car_s: float, speed: float) -> bool:
	for q in _queue:
		if q[1] >= 0:
			return false
	if next_call == 0:
		return true
	var prev: Dictionary = calls[next_call - 1]
	return prev.s - car_s <= maxf(speed * NEXT_WHEN, 20.0)


## The car was put back on the road somewhere else: forget what was queued for the
## old spot and carry on from the next call ahead of the new one.
func _resync(car_s: float) -> void:
	_queue = _queue.filter(func(q): return q[1] < 0)
	next_call = 0
	while next_call < calls.size() and calls[next_call].s < car_s:
		next_call += 1


func _pump(dt: float) -> void:
	_talk_left -= dt
	if _talk_left > 0.0:
		return
	while not _queue.is_empty():
		var q: Array = _queue.pop_front()
		var idx: int = q[1]
		if idx >= 0 and calls[idx].s_end < _car_s:
			# the car is already past these corners: drop the rest of this call
			_queue = _queue.filter(func(e): return e[1] != idx)
			dropped += 1
			if Config.flag("aitrace"):
				print("[ai]   at %5.0f m: dropped the rest of call %d (ends %5.0f m)" % [_car_s, idx, calls[idx].s_end])
			continue
		_player.stream = _clips[q[0]]
		_player.play()
		_talk_left = _clips[q[0]].get_length() + GAP
		if Config.flag("aitrace"):
			print("[ai]     at %5.0f m: says '%s' (%.2f s)" % [_car_s, q[0], _talk_left])
		return


## Stop talking and forget the queue (the countdown starts: it has to be on time).
func hush() -> void:
	_queue.clear()
	_talk_left = 0.0
	_player.stop()


func busy() -> bool:
	return _talk_left > 0.0 or not _queue.is_empty()
