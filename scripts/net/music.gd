extends Node
## Soundtrack player (autoload "Music"). Two players crossfade between tracks
## on their own "Music" bus. What plays is decided elsewhere: the main menu
## sets a bed track, and in a match the MusicDirector (scripts/ui) picks a bed
## from what you're doing and fires short event overrides (liquidated, big
## win, raid...). Beds resume where they left off, like a radio.

signal now_playing(id: String)

const TRACKS := {
	"vyzee": {"title": "UP UP UP (WE CAN GO LOCO)", "artist": "VYZEE", "file": "vyzee_up_up_up"},
	"queen_st": {"title": "Queen St (Instrumental)", "artist": "twentythree", "file": "queen_st"},
	"stay_schemin": {"title": "Stay Schemin (Instrumental)", "artist": "Rick Ross", "file": "stay_schemin"},
	"type_a": {"title": "Type A", "artist": "Nino Breeze, Rick Ross, Moneybagg Yo", "file": "type_a"},
	"intoxicated": {"title": "Intoxicated", "artist": "Martin Solveig & GTA", "file": "intoxicated"},
	"lelo": {"title": "No Contempt (Instrumental)", "artist": "Lelo", "file": "lelo_no_contempt"},
	"blue_bands": {"title": "Blue Bands", "artist": "", "file": "blue_bands"},
	"stout_street": {"title": "12 Stout Street", "artist": "", "file": "stout_street"},
}
const FADE := 1.6
const BED_DB := -7.0

var current := ""                 # track id playing (or fading in)
var _bed := ""
var _event := ""
var _event_t := 0.0
var _event_prio := 0
var _streams := {}
var _resume := {}                 # id -> seconds into the track when it was faded out
var _a: AudioStreamPlayer
var _b: AudioStreamPlayer
var _bus := 0
var _closing := false             # quitting: nothing new may start (a playing stream leaks at exit)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_bus = AudioServer.bus_count
	AudioServer.add_bus(_bus)
	AudioServer.set_bus_name(_bus, "Music")
	AudioServer.set_bus_send(_bus, "Master")
	set_volume(Config.music_volume)
	_a = _player()
	_b = _player()


func _player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = "Music"
	p.volume_db = -80.0
	add_child(p)
	return p


func _stream(id: String) -> AudioStream:
	if not _streams.has(id):
		var s = load("res://assets/music/%s.ogg" % TRACKS[id].file)
		if s is AudioStreamOggVorbis:
			s = s.duplicate()
			s.loop = true
		_streams[id] = s
	return _streams[id]


## 0..1 slider value -> bus volume. 0 mutes.
func set_volume(v: float) -> void:
	AudioServer.set_bus_volume_db(_bus, linear_to_db(maxf(v, 0.0001)))
	AudioServer.set_bus_mute(_bus, v <= 0.01)


## "Music [----o---]" row for the main menu and the pause menu. Saves as you drag.
func volume_row(label: Label) -> HBoxContainer:
	var row := HBoxContainer.new()
	label.custom_minimum_size.x = 70
	row.add_child(label)
	var sl := HSlider.new()
	sl.min_value = 0.0
	sl.max_value = 1.0
	sl.step = 0.05
	sl.value = Config.music_volume
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.value_changed.connect(func(val: float) -> void:
		Config.music_volume = val
		set_volume(val)
		Config.save_settings())
	row.add_child(sl)
	return row


## The background track for where you are / what you're doing.
func set_bed(id: String) -> void:
	_bed = id


## A short override that wins over the bed for `hold` seconds. A lower
## priority event can't cut off a higher one that's still going.
func event(id: String, hold: float, prio: int = 1) -> void:
	if _event_t > 0.0 and prio < _event_prio:
		return
	_event = id
	_event_t = hold
	_event_prio = prio
	_resume.erase(id)             # events always start from the top


func clear_event(id: String = "") -> void:
	if id == "" or _event == id:
		_event_t = 0.0


func _process(delta: float) -> void:
	if _closing:
		return
	if _event_t > 0.0:
		_event_t -= delta
	var want := _event if _event_t > 0.0 else _bed
	if want != current:
		_switch(want)


func _switch(id: String) -> void:
	# fade the active player out (remember where it was), then swap players
	if current != "" and _a.playing:
		_resume[current] = _a.get_playback_position()
		_fade(_a, -60.0, true)
	var tmp := _a
	_a = _b
	_b = tmp
	current = id
	if id == "" or not TRACKS.has(id):
		return
	var s := _stream(id)
	if s == null:
		return
	_a.stream = s
	_a.volume_db = -40.0
	_a.play(_resume.get(id, 0.0))
	_fade(_a, BED_DB, false)
	now_playing.emit(id)


func _fade(p: AudioStreamPlayer, db: float, then_stop: bool) -> void:
	var old: Tween = p.get_meta("tw") if p.has_meta("tw") else null
	if old and old.is_valid():
		old.kill()
	var t := create_tween()
	t.tween_property(p, "volume_db", db, FADE)
	if then_stop:
		t.tween_callback(p.stop)
	p.set_meta("tw", t)


func title_of(id: String) -> String:
	var t: Dictionary = TRACKS.get(id, {})
	if t.is_empty():
		return ""
	return t.title if t.artist == "" else "%s — %s" % [t.artist, t.title]


## Called by Sfx.quit_game so the streams are released before quitting.
func stop_all() -> void:
	_closing = true
	for p in [_a, _b]:
		p.stop()
		p.stream = null
	_streams.clear()
	current = ""
	_bed = ""
	_event_t = 0.0
