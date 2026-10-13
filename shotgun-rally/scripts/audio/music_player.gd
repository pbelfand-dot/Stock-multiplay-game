extends Node
## The music player: the players' own songs, from the music folder on their own machine
## (MusicLibrary: user://music, each folder in it a playlist). Nothing of it is in the game: the
## repo and the downloads are public. Config makes it (Config.music, the node /root/Config/Music),
## so it's there from the menu through every stage, and in the tests.
##   * the playlists are the folders (ALL, HOUSE, RAP ..., MISC); play / pause, next / previous
##     (PREVIOUS a few seconds into a song starts it again), shuffle, repeat the playlist
##   * its own bus, "Music" (into the master), and its own volume; off is off. The playlist, the
##     volume, shuffle, repeat and on / off are saved with the settings (Config, user://settings.cfg)
##   * a crossfade between songs (FADE; a skip, FADE_SKIP), each song read off the main thread
##   * under the co-driver's calls the music dips DUCK_DB (AICoDriver.busy(): the pace notes stay
##     clear), the engine and the effects as they were
##   * a "now playing" card, bottom right, when a song starts (the menus and the stages alike)
##   * keys (Controls): N the next song (SHIFT+N the one before), B music on / off
##   * local to each machine: nothing goes over the network (online, everyone hears their own)
## It doesn't start by itself in pictures and videos (--screenshot, --menu_shot, --showcase,
## --write-movie), in the 2-player smoke tests, or headless (tests start it themselves).

signal changed                       # what's playing, the playlists or a setting: the panel redraws
signal track_started(track: Dictionary)

const Library = preload("res://scripts/audio/music_library.gd")
const UI = preload("res://scripts/ui/ui_kit.gd")
const ROOT := "user://music"
const BUS := "Music"
const FADE := 1.6                    # s: one song into the next
const FADE_SKIP := 0.6               # s: a skip (N, NEXT, a playlist picked)
const FADE_START := 0.25             # s: out of silence (no click)
const RESTART_AFTER := 3.0           # s: PREVIOUS this far into a song starts it again
const DUCK_DB := -14.0               # under the co-driver's calls
const DUCK_ATTACK := 0.15            # s to dip ...
const DUCK_HOLD := 0.35              # ... s after the last word (the gap to the next call) ...
const DUCK_RELEASE := 0.9            # ... and s back up
const VOICE_GROUP := "codriver_voice"
const TOAST_S := 4.0

var root := ROOT                     # (tests: a folder of their own)
var config                           # Config: where the settings live (null: not saved)
var on := true                       # music on (Config.music_on)
var volume := 0.5                    # the Music bus, 0..1 (Config.music_volume)
var shuffle := true
var repeat := true                   # the playlist starts again at its end (off: it stops)
var playlist := ""                   # the playlist picked (its key: the folder's name, ALL or MISC)
var playlists: Array = []            # Library.scan
var order: Array = []                # the playlist's songs (their indices) in the order they play
var at := -1                         # where in `order`
var current := {}                    # the song playing or paused ({} none)
var paused := false
var failed := 0                      # songs in a row that wouldn't load
var last_error := ""
var duck_db := 0.0
var toasts := true                   # the "now playing" card
var rng := RandomNumberGenerator.new()
var _players: Array = []             # two AudioStreamPlayers: one fades out as the other fades in
var _cur := 0                        # the one playing
var _gain := [0.0, 0.0]              # each one's fade, 0..1 (heard as sin(gain * PI / 2): equal power)
var _fade_to := [0.0, 0.0]
var _fade_rate := [1.0, 1.0]
var _jobs := {}                      # a load on a worker: task id -> {req, box, track, fade}
var _request := 0                    # the newest load asked for (an older one done late is dropped)
var _advancing := false              # the next song's on its way (this one's ending)
var _quiet_t := 99.0                 # s since the co-driver last spoke
var _bus_db := INF
var _toast: PanelContainer
var _toast_head: Label
var _toast_title: Label
var _toast_sub: Label
var _toast_tw: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS         # (a replay pauses the tree: the music plays on)
	rng.randomize()
	if config == null:
		config = get_node_or_null("/root/Config")
	if config:
		on = bool(config.music_on)
		volume = clampf(float(config.music_volume), 0.0, 1.0)
		shuffle = bool(config.music_shuffle)
		repeat = bool(config.music_repeat)
		playlist = str(config.music_playlist)
	_make_bus()
	for k in 2:
		var p := AudioStreamPlayer.new()
		p.name = "Deck%d" % k
		p.bus = BUS
		p.volume_db = -80.0
		p.finished.connect(_on_finished.bind(k))
		add_child(p)
		_players.append(p)
	toasts = not _picture_run()
	if available():
		Library.ensure_folder(root)
		rescan()
		if on and _autostart():
			start.call_deferred()


func _exit_tree() -> void:
	for id in _jobs:                                # (a song still loading: let it finish first)
		WorkerThreadPool.wait_for_task_completion(id)
	_jobs.clear()
	for k in _players.size():                       # (the songs let go of: nothing held at exit)
		_stop_deck(k)


## The music's own bus (into the master), made once.
func _make_bus() -> void:
	if AudioServer.get_bus_index(BUS) == -1:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, BUS)
		AudioServer.set_bus_send(i, "Master")


## Your own music needs a folder on your computer: the download, not the browser.
func available() -> bool:
	return not OS.has_feature("web")


## The music folder as the computer names it (for the panel, and the file manager).
func folder_path() -> String:
	return ProjectSettings.globalize_path(root)


## Open the music folder in Finder / Explorer (made first if it isn't there).
func open_folder() -> void:
	Library.ensure_folder(root)
	OS.shell_show_in_file_manager(folder_path(), true)


func _picture_run() -> bool:
	var c = config
	return c != null and (c.flag("screenshot") or c.flag("menu_shot") or c.flag("showcase")) \
		or "--write-movie" in OS.get_cmdline_args()


func _autostart() -> bool:
	return not _picture_run() and DisplayServer.get_name() != "headless" and not (config != null and config.flag("smoke"))


# ── the playlists ─────────────────────────────────────────────────────────

## Look in the music folder again (new songs, new folders). The song playing plays on.
func rescan() -> void:
	if not available():
		playlists = []
		return
	var tr_before := tracks()
	playlists = Library.scan(root)
	var tr := tracks()
	if tr.size() != tr_before.size() or order.size() != tr.size():
		_build_order(_index_of(current))
	changed.emit()


## The playlist picked, or (its folder gone) ALL / the first there is: {} if there's no music.
func picked() -> Dictionary:
	for p in playlists:
		if p.key == playlist:
			return p
	return playlists[0] if not playlists.is_empty() else {}


func tracks() -> Array:
	return picked().get("tracks", [])


func song_count() -> int:
	var n := 0
	for p in playlists:
		if p.key != Library.ALL:
			n += p.tracks.size()
	return n


## Play this playlist (its key), from its first song (shuffled: a random one). The one already
## playing picked again plays on.
func select(key: String) -> void:
	if playing() and key == str(picked().get("key", "")) and key == playlist:
		return
	playlist = key
	_save()
	_build_order()
	if on and not tracks().is_empty():
		at = -1
		_step(1, FADE_SKIP)
	changed.emit()


## Play this song of the playlist now (its index in tracks()); the rest follow it.
func play_track(i: int) -> void:
	if i < 0 or i >= tracks().size():
		return
	if not on:
		on = true
		_save()
	_build_order(i)
	at -= 1                                         # (the step lands on it)
	_step(1, FADE_SKIP)


## The play order: every song once, as they're named or shuffled (`first`, a song's index, first
## then); `at` on `first` (-1: before the start).
func _build_order(first := -1) -> void:
	var n := tracks().size()
	order = range(n)
	if shuffle:
		for k in range(n - 1, 0, -1):               # (Fisher-Yates)
			var j := rng.randi_range(0, k)
			var t = order[k]
			order[k] = order[j]
			order[j] = t
		if first >= 0 and first < n:
			order.erase(first)
			order.push_front(first)
	at = order.find(first) if first >= 0 and first < n else -1


func _index_of(track: Dictionary) -> int:
	if track.is_empty():
		return -1
	var tr := tracks()
	for i in tr.size():
		if tr[i].path == track.path:
			return i
	return -1


# ── the controls ──────────────────────────────────────────────────────────

## Music on: play the playlist (or carry on with the song that was playing).
func start() -> void:
	if not on or tracks().is_empty():
		return
	if not current.is_empty():
		if paused:
			resume()
		return
	if order.size() != tracks().size():
		_build_order()
	if at >= order.size() - 1 and not repeat:
		at = -1                                     # (the playlist played out: from the top)
	at = clampi(at, -1, order.size() - 1)
	_step(1, FADE_START)


## PLAY / PAUSE.
func toggle_pause() -> void:
	if current.is_empty():
		if not on:
			set_enabled(true)
		else:
			start()
	elif paused:
		resume()
	else:
		pause()


func pause() -> void:
	if current.is_empty() or paused:
		return
	paused = true
	for k in 2:
		if k != _cur:
			_stop_deck(k)                           # (a song fading out: gone)
	_players[_cur].stream_paused = true
	changed.emit()


func resume() -> void:
	if current.is_empty() or not paused:
		return
	paused = false
	_players[_cur].stream_paused = false
	changed.emit()


func next() -> void:
	if on:
		_step(1, FADE_SKIP)


## PREVIOUS: a few seconds in, this song from the start; else the one before.
func prev() -> void:
	if not on or tracks().is_empty():
		return
	if not current.is_empty() and position() > RESTART_AFTER:
		_players[_cur].seek(0.0)
		changed.emit()
		return
	_step(-1, FADE_SKIP)


## Music on / off (saved). Off: silence, nothing loaded; on: the playlist plays.
func set_enabled(v: bool) -> void:
	if v == on:
		return
	on = v
	_save()
	if on:
		start()
	else:
		stop()
	changed.emit()


func set_volume(v: float) -> void:
	volume = clampf(v, 0.0, 1.0)
	_save()


## Shuffle on / off: the songs after this one in the new order (this one plays on).
func set_shuffle(v: bool) -> void:
	shuffle = v
	_save()
	_build_order(_index_of(current))
	changed.emit()


func set_repeat(v: bool) -> void:
	repeat = v
	_save()
	changed.emit()


## Silence: both decks stopped, nothing playing.
func stop() -> void:
	_request += 1                                   # (a song loading: dropped when it's ready)
	for k in 2:
		_stop_deck(k)
	current = {}
	paused = false
	_advancing = false
	changed.emit()


func _save() -> void:
	if config == null:
		return
	config.music_on = on
	config.music_volume = volume
	config.music_shuffle = shuffle
	config.music_repeat = repeat
	config.music_playlist = playlist
	config.save()


## The song `dir` steps along the order (its end: round again, reshuffled, when repeating; else
## stop), loaded on a worker; it fades in over `fade` s once it's read.
func _step(dir: int, fade: float) -> void:
	var tr := tracks()
	if tr.is_empty():
		stop()
		return
	if order.size() != tr.size():
		_build_order(_index_of(current))
	at += dir
	if at >= order.size():
		if not repeat:
			at = order.size() - 1
			stop()
			return
		var last = order[order.size() - 1]
		_build_order()
		if shuffle and order.size() > 1 and order[0] == last:   # (never the same song twice running)
			order[0] = order[1]
			order[1] = last
		at = 0
	elif at < 0:
		at = order.size() - 1 if repeat else 0
	_load(tr[order[at]], fade)


func _load(track: Dictionary, fade: float) -> void:
	_request += 1
	_advancing = true
	var box := [null]
	var path: String = track.path
	var id := WorkerThreadPool.add_task(func(): box[0] = Library.load_stream(path), false, "music: load a song")
	_jobs[id] = {"req": _request, "box": box, "track": track, "fade": fade}


## A song's read: fade it in, the old one out. One that won't load is skipped (all of them: stop).
func _begin(track: Dictionary, stream: AudioStream, fade: float) -> void:
	if stream == null:
		failed += 1
		last_error = "Couldn't play %s (MP3, OGG Vorbis or WAV only)" % track.get("file", "?")
		push_warning("[music] " + last_error)
		if failed >= tracks().size():
			stop()
			_show_toast("MUSIC", "None of these songs would play", "MP3, OGG (Vorbis) or WAV files")
			return
		_step(1, fade)
		return
	failed = 0
	var silent: bool = current.is_empty() or paused
	var old := _cur
	_cur = 1 - _cur
	_stop_deck(_cur)
	var p: AudioStreamPlayer = _players[_cur]
	p.stream = stream
	_gain[_cur] = 0.0
	p.volume_db = -80.0
	_fade(_cur, 1.0, FADE_START if silent else fade)
	if silent:
		_stop_deck(old)
	else:
		_fade(old, 0.0, fade)
	p.play()
	paused = false
	current = track
	_advancing = false
	_show_toast("NOW PLAYING  ·  " + str(picked().get("name", "")), str(track.title), str(track.get("artist", "")))
	track_started.emit(track)
	changed.emit()


func _fade(k: int, to: float, secs: float) -> void:
	_fade_to[k] = to
	_fade_rate[k] = 1.0 / maxf(secs, 0.01)


func _stop_deck(k: int) -> void:
	var p: AudioStreamPlayer = _players[k]
	p.stop()
	p.stream_paused = false
	p.stream = null
	_gain[k] = 0.0
	_fade_to[k] = 0.0
	p.volume_db = -80.0


func _on_finished(k: int) -> void:
	if k == _cur and not current.is_empty() and not _advancing:
		_step(1, FADE_START)                         # (a song too short to crossfade, or its length unknown)


## Seconds into the song, and its length.
func position() -> float:
	if current.is_empty() or _players.is_empty():
		return 0.0
	return _players[_cur].get_playback_position()


func length() -> float:
	var s: AudioStream = _players[_cur].stream if not _players.is_empty() else null
	return s.get_length() if s else 0.0


## 0..1 of the way through the song.
func progress() -> float:
	var n := length()
	return clampf(position() / n, 0.0, 1.0) if n > 0.0 else 0.0


## The song's name while one's playing (not paused, not off), else "": the cars' radio screens.
func now_title() -> String:
	if current.is_empty() or paused or not on:
		return ""
	return str(current.title)


func now_artist() -> String:
	return "" if now_title() == "" else str(current.get("artist", ""))


func playing() -> bool:
	return not current.is_empty() and not paused


# ── every frame: loads done, fades, the end of a song, the duck, the bus ──

func _process(dt: float) -> void:
	for id in _jobs.keys():
		if WorkerThreadPool.is_task_completed(id):
			WorkerThreadPool.wait_for_task_completion(id)
			var job: Dictionary = _jobs[id]
			_jobs.erase(id)
			if int(job.req) == _request and on:
				_begin(job.track, job.box[0], float(job.fade))
	for k in 2:
		if _gain[k] != _fade_to[k]:
			_gain[k] = move_toward(_gain[k], _fade_to[k], _fade_rate[k] * dt)
			_players[k].volume_db = linear_to_db(maxf(sin(_gain[k] * PI * 0.5), 0.0001))
			if _gain[k] <= 0.0 and _fade_to[k] <= 0.0 and k != _cur:
				_stop_deck(k)
	if not current.is_empty() and not paused and not _advancing:
		var p: AudioStreamPlayer = _players[_cur]
		var n := length()
		if p.playing and n > FADE * 3.0 and n - p.get_playback_position() <= FADE:
			_step(1, FADE)                           # (near the end: the next one fades in over it)
	duck(_voice_busy(), dt)
	var db := linear_to_db(maxf(volume, 0.0001)) + duck_db
	if absf(db - _bus_db) > 0.05:
		_bus_db = db
		var i := AudioServer.get_bus_index(BUS)
		if i >= 0:
			AudioServer.set_bus_volume_db(i, db)


## The co-driver talking (any AICoDriver in VOICE_GROUP saying a call, the countdown, "wipers").
func _voice_busy() -> bool:
	if not is_inside_tree():
		return false
	for v in get_tree().get_nodes_in_group(VOICE_GROUP):
		if v.has_method("busy") and v.busy():
			return true
	return false


## The duck: down DUCK_DB quickly while the co-driver talks, held through the gaps between calls,
## then back up slowly.
func duck(talking: bool, dt: float) -> void:
	_quiet_t = 0.0 if talking else _quiet_t + dt
	var target := DUCK_DB if _quiet_t < DUCK_HOLD else 0.0
	var secs := DUCK_ATTACK if target < duck_db else DUCK_RELEASE
	duck_db = move_toward(duck_db, target, absf(DUCK_DB) / secs * dt)


# ── the keys ──────────────────────────────────────────────────────────────

func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey) or not e.is_pressed() or e.is_echo() or not available():
		return
	var scene := get_tree().current_scene
	if scene and scene.scene_file_path.ends_with("physics_lab.tscn"):
		return                                       # (the lab's own keys: B and N launch the car)
	if InputMap.has_action("music_next") and e.is_action_pressed("music_next"):
		get_viewport().set_input_as_handled()
		key_next((e as InputEventKey).shift_pressed)
	elif InputMap.has_action("music_toggle") and e.is_action_pressed("music_toggle"):
		get_viewport().set_input_as_handled()
		key_toggle()


## N (SHIFT+N: back one). With no music, the card says where the songs go.
func key_next(back := false) -> void:
	if song_count() == 0:
		_show_toast("MUSIC", "No songs yet", "Put MP3s in music/house, music/rap ... (MUSIC, top right of the home screen)")
	elif not on:
		_show_toast("MUSIC", "Music is off", "B turns it on")
	elif back:
		prev()
	else:
		next()


## B: music on / off.
func key_toggle() -> void:
	set_enabled(not on)
	if not on:
		_show_toast("MUSIC", "Music off", "B turns it back on")
	elif song_count() == 0:
		_show_toast("MUSIC", "Music on: no songs yet", "Put MP3s in music/house, music/rap ... (MUSIC, top right of the home screen)")


# ── the "now playing" card ────────────────────────────────────────────────

func _show_toast(head: String, title: String, sub := "") -> void:
	if not toasts or not is_inside_tree():
		return
	if _toast == null:
		_build_toast()
	_toast_head.text = head
	_toast_title.text = title
	_toast_sub.text = sub
	_toast_sub.visible = sub != ""
	if _toast_tw:
		_toast_tw.kill()
	_toast.visible = true
	_toast_tw = create_tween()
	_toast_tw.tween_property(_toast, "modulate:a", 1.0, 0.25).from(0.0)
	_toast_tw.tween_interval(TOAST_S)
	_toast_tw.tween_property(_toast, "modulate:a", 0.0, 0.6)
	_toast_tw.tween_callback(_toast.hide)


func toast_text() -> String:
	return "" if _toast == null or not _toast.visible else "%s | %s | %s" % [_toast_head.text, _toast_title.text, _toast_sub.text]


## Bottom right, over everything (menus, the stage's HUD): a yellow bar, NOW PLAYING · the
## playlist, the song, its artist.
func _build_toast() -> void:
	var layer := CanvasLayer.new()
	layer.name = "NowPlaying"
	layer.layer = 100
	add_child(layer)
	_toast = PanelContainer.new()
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.add_theme_stylebox_override("panel", UI.box(Color(0.04, 0.05, 0.06, 0.86), 10, 14))
	_toast.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_toast.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_toast.offset_right = -28
	_toast.offset_bottom = -76                     # (above the home screen's line of keys)
	layer.add_child(_toast)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.add_child(row)
	var bar := ColorRect.new()
	bar.color = UI.YELLOW
	bar.custom_minimum_size = Vector2(6, 0)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(bar)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	_toast_head = UI.label("", 14, UI.YELLOW, true)
	_toast_title = UI.label("", 24, UI.CREAM, true)
	_toast_sub = UI.label("", 15, UI.DIM)
	for l in [_toast_head, _toast_title, _toast_sub]:
		l.clip_text = true
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.custom_minimum_size = Vector2(340, 0)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(l)
	_toast.visible = false
