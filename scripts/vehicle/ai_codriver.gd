extends Node
## The AI co-driver: reads the calls in the "Fraser" voice when nobody's in
## the passenger seat. Same job a human co-driver does: count the start, call
## each group of notes early enough that the driver hears all of it before the
## first corner (by TIME, not distance: faster = earlier), say "finish".
## Clips are strung together word by word (assets/voice/fraser/<word>.mp3);
## a word with no clip yet is skipped.

const VOICE_DIR := "res://assets/voice/fraser/"
const GAP := 0.03               # silence between words (s)
const LEAD := 2.6               # seconds of warning before the first corner of a call

var calls: Array = []           # from Pacenotes.calls()
var next_call := 0
var enabled := true
var said: Array = []            # log of [car_s, call_s, words] for the tests
var _clips := {}                # word -> AudioStream
var _queue: Array = []          # words still to say
var _player: AudioStreamPlayer
var _wait := 0.0


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.volume_db = 2.0
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


func has_word(w: String) -> bool:
	return _clips.has(w)


## Say these words now (after whatever's being said).
func say(words: Array) -> void:
	for w in words:
		if _clips.has(w):
			_queue.append(w)


## Seconds it takes to say these words.
func duration(words: Array) -> float:
	var t := 0.0
	for w in words:
		if _clips.has(w):
			t += _clips[w].get_length() + GAP
	return t


## Every physics tick: where the car is and how fast it's going.
func update(car_s: float, speed: float, dt: float) -> void:
	if enabled:
		# skip calls already behind us (a reset, a spin)
		while next_call < calls.size() and calls[next_call].s < car_s - 5.0:
			next_call += 1
		if next_call < calls.size():
			var c: Dictionary = calls[next_call]
			# talking time: this call plus whatever's still queued (capped: a backlog
			# shouldn't make it read the whole stage at once)
			var talk := minf(duration(c.words) + duration(_queue), 5.0)
			var lead: float = maxf(45.0, speed * (LEAD + 0.8 * Config.call_early)) + speed * talk
			if car_s >= c.s - lead:
				say(c.words)
				said.append([car_s, c.s, c.words])
				next_call += 1
	_pump(dt)


func _pump(dt: float) -> void:
	if _player.playing:
		return
	_wait -= dt
	if _wait > 0.0 or _queue.is_empty():
		return
	_player.stream = _clips[_queue.pop_front()]
	_player.play()
	_wait = GAP


func busy() -> bool:
	return _player.playing or not _queue.is_empty()
