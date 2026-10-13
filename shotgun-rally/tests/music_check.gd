extends SceneTree
## MUSIC: the players' own songs (MusicPlayer, MusicLibrary, MusicPanel). The songs are test tones
## made here (sine waves written as WAVs into a user:// folder of the test's own, deleted at the end):
## no audio is in the repo.
##   * the playlists are the folders: HOUSE, RAP (an album folder inside it counted), the loose songs
##     MISC, ALL (every song) first; an empty folder and a folder with no songs left out
##   * names from the files (the track number, the extension, "(Official Video)" off; "Artist - Title"
##     split; "50 Cent" keeps its 50) and from tags (ID3v2.3 in UTF-16, ID3v2.4 in UTF-8, Vorbis
##     comments)
##   * a playlist picked plays its songs; NEXT goes through each once, then round again (repeat);
##     PREVIOUS back one, and a few seconds into a song the same one from the start; repeat off stops
##     at the end; shuffle plays every song once a round, never the same one twice running; pause
##     and play; a song that won't load is skipped
##   * near a song's end the next fades in over it (both heard), the old one's gone after
##   * the volume is the "Music" bus's; the co-driver's calls dip it (DUCK_DB), it comes back after
##   * on / off, the playlist, volume, shuffle and repeat saved in user://settings.cfg, and a fresh
##     start reads them back
##   * an empty music folder, and a missing one (made, with house/ and rap/ and a note): no songs,
##     nothing breaks (play, next, previous, the keys), the panel says where songs go and the path
##   * the MUSIC panel builds (its playlists and songs, the buttons work); the home screen's MUSIC
##     chip opens it; the pause menu's MUSIC opens it over the stage, ESC goes back to the pause menu
##   * the cars' radio screens show the song playing (the station's own songs while it's off)
##   * N and B are in the input map, free of the driving keys, and do next / on-off
##   * nothing goes online: the player has no RPCs
## Run: godot --headless --fixed-fps 120 --path . -s tests/music_check.gd [-- --profile=/tmp/x.cfg]
## Prints [music] lines; exits 1 on any FAIL.

const Library = preload("res://scripts/audio/music_library.gd")
const MusicPlayer = preload("res://scripts/audio/music_player.gd")
const MusicPanel = preload("res://scripts/ui/music_panel.gd")
const LoadingScreen = preload("res://scripts/ui/loading_screen.gd")
const ConfigScript = preload("res://scripts/net/config.gd")
const R := "user://music_check"
const SECS := 6.0                       # each tone's length (long enough to crossfade: > FADE * 3)

var fails := 0
var config
var m                                   # MusicPlayer
var errors := ErrorLog.new()


class ErrorLog extends Logger:
	var lines: Array = []
	var _lock := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool,
			error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		_lock.lock()
		lines.append("%s (%s:%d %s)" % [rationale if rationale != "" else code, file, line, function])
		_lock.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass

	func take() -> Array:
		_lock.lock()
		var out := lines.duplicate()
		lines.clear()
		_lock.unlock()
		return out


func _initialize() -> void:
	await process_frame                                  # (the autoloads ready: Config made the player)
	config = root.get_node("Config")
	m = config.music
	var keep := [config.music_on, config.music_playlist, config.music_volume, config.music_shuffle, config.music_repeat]
	check(m != null and m.get_parent() == config and m.name == "Music", "Config made the music player (/root/Config/Music)")
	if m == null:
		_end(keep)
		return
	_make_songs()
	_names_and_tags()
	m.root = R
	m.on = true
	m.repeat = true
	m.shuffle = false
	m.rescan()
	_playlists()
	await _playing()
	await _crossfade()
	await _shuffle()
	await _broken()
	_duck()
	_persist()
	await _empty()
	await _panel()
	await _radio()
	_keys()
	await _menus()
	_end(keep)


func _end(keep: Array) -> void:
	if m:
		m.stop()
		m.root = MusicPlayer.ROOT
		m.on = keep[0]
		m.playlist = keep[1]
		m.volume = keep[2]
		m.shuffle = keep[3]
		m.repeat = keep[4]
		m._save()
		m.rescan()
	for d in [R, R + "_tags", R + "_empty", R + "_missing"]:
		_rmdir(d)
	await _wait(0.2)                                     # (the decks let go before the quit)
	print("[music] %s" % ("MUSIC OK" if fails == 0 else "MUSIC FAIL (%d)" % fails))
	quit(1 if fails > 0 else 0)


func check(ok: bool, what: String) -> void:
	print("[music] %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		fails += 1


# ── the test tones ────────────────────────────────────────────────────────

## A sine tone as a 16-bit mono WAV (22,050 Hz).
func _wav(path: String, hz: float, secs := SECS) -> void:
	var rate := 22050
	var n := int(rate * secs)
	var pcm := PackedByteArray()
	pcm.resize(n * 2)
	for i in n:
		pcm.encode_s16(i * 2, int(sin(TAU * hz * i / rate) * 6000.0))
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer("RIFF".to_ascii_buffer())
	f.store_32(36 + pcm.size())
	f.store_buffer("WAVEfmt ".to_ascii_buffer())
	f.store_32(16)
	f.store_16(1)                                        # PCM
	f.store_16(1)                                        # mono
	f.store_32(rate)
	f.store_32(rate * 2)
	f.store_16(2)
	f.store_16(16)
	f.store_buffer("data".to_ascii_buffer())
	f.store_32(pcm.size())
	f.store_buffer(pcm)
	f.close()


func _make_songs() -> void:
	_rmdir(R)
	_wav(R + "/house/01 - DJ Sine - Deep A.wav", 220.0)
	_wav(R + "/house/02. Warehouse Tone.wav", 277.0)
	_wav(R + "/house/03 Low End (Official Video).wav", 330.0)
	_wav(R + "/rap/50 Cent - In Da Tone.wav", 392.0)
	_wav(R + "/rap/album/1-01 Boom Bap Sine.wav", 440.0)
	_wav(R + "/loose tone.wav", 494.0, 2.0)
	_wav(R + "/broken/b fine.wav", 523.0)
	var junk := FileAccess.open(R + "/broken/a broken.ogg", FileAccess.WRITE)   # (not a song: skipped)
	for i in 400:
		junk.store_32(0xDEADBEEF ^ i)
	junk.close()
	_bytes(R + "/rap/apple tune.m4a", PackedByteArray([0, 0, 0, 0x20]) + "ftypM4A ".to_ascii_buffer())   # (a kind it can't play)
	DirAccess.make_dir_recursive_absolute(R + "/empty")
	var note := FileAccess.open(R + "/notes/readme.txt", FileAccess.WRITE) if DirAccess.make_dir_recursive_absolute(R + "/notes") == OK else null
	if note:
		note.store_string("not a song")
		note.close()


func _rmdir(dir: String) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	for sub in d.get_directories():
		_rmdir(dir.path_join(sub))
	DirAccess.remove_absolute(dir)


# ── names and tags ────────────────────────────────────────────────────────

func _names_and_tags() -> void:
	var cases := [["01 - DJ Sine - Deep A.wav", "DJ Sine", "Deep A"], ["02. Warehouse Tone.mp3", "", "Warehouse Tone"],
		["03 Low End (Official Video).ogg", "", "Low End"], ["50 Cent - In Da Club.mp3", "50 Cent", "In Da Club"],
		["21 Savage - Bank Account.mp3", "21 Savage", "Bank Account"], ["1-01 Boom Bap Sine.wav", "", "Boom Bap Sine"],
		["Some_Song_Name [Lyrics].mp3", "", "Some Song Name"], ["7.mp3", "", "7"]]
	var bad: Array = []
	for c in cases:
		var n: Dictionary = Library.name_from_file(c[0])
		if n.artist != c[1] or n.title != c[2]:
			bad.append("%s -> %s / %s" % [c[0], n.artist, n.title])
	check(bad.is_empty(), "names from the files: the number, extension and junk off, 'Artist - Title' split, 50 Cent keeps its 50%s"
		% ("" if bad.is_empty() else ": " + ", ".join(bad)))
	# ID3v2.3: the title in UTF-16 (with a byte-order mark), the artist in Latin-1; then not-a-song bytes
	var t := R + "_tags"
	DirAccess.make_dir_recursive_absolute(t)
	var title := "Tagged Title é"
	var tit := PackedByteArray([1, 0xFF, 0xFE])
	for ch in title:
		tit.append(ch.unicode_at(0) & 0xFF)
		tit.append(ch.unicode_at(0) >> 8)
	tit.append_array(PackedByteArray([0, 0]))
	var art := PackedByteArray([0]) + "Tag Artist".to_ascii_buffer()
	var frames := _frame3("TIT2", tit) + _frame3("TPE1", art) + PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
	var tag := PackedByteArray([0x49, 0x44, 0x33, 3, 0, 0]) + _syncsafe(frames.size()) + frames
	_bytes(t + "/01 - file name.mp3", tag + PackedByteArray([0xFF, 0xFB, 0x90, 0x00]))
	var tr: Dictionary = Library.track(t + "/01 - file name.mp3")
	check(tr.title == title and tr.artist == "Tag Artist", "ID3v2.3 tags read (UTF-16 title, Latin-1 artist): %s / %s" % [tr.artist, tr.title])
	# ID3v2.4, UTF-8, syncsafe frame sizes
	var t8 := PackedByteArray([3]) + "Ünïcode Song".to_utf8_buffer()
	var frames4 := _frame4("TIT2", t8) + _frame4("TPE1", PackedByteArray([3]) + "DJ Four".to_utf8_buffer())
	_bytes(t + "/v24.mp3", PackedByteArray([0x49, 0x44, 0x33, 4, 0, 0]) + _syncsafe(frames4.size()) + frames4 + PackedByteArray([0xFF, 0xFB]))
	var tr4: Dictionary = Library.track(t + "/v24.mp3")
	check(tr4.title == "Ünïcode Song" and tr4.artist == "DJ Four", "ID3v2.4 tags read (UTF-8): %s / %s" % [tr4.artist, tr4.title])
	# an Ogg Vorbis file's comments: page 0 the identification header, page 1 the comments
	var ident := PackedByteArray([1]) + "vorbis".to_ascii_buffer() + PackedByteArray([0, 0, 0, 0, 1, 0x44, 0xAC, 0, 0])
	var com := PackedByteArray([3]) + "vorbis".to_ascii_buffer()
	com += _le32(4) + "test".to_ascii_buffer() + _le32(2)
	for kv in ["TITLE=Vorbis Song", "ARTIST=Ogg Crew"]:
		com += _le32(kv.to_utf8_buffer().size()) + kv.to_utf8_buffer()
	_bytes(t + "/song.ogg", _ogg_page(ident, 0) + _ogg_page(com, 1))
	var tro: Dictionary = Library.track(t + "/song.ogg")
	check(tro.title == "Vorbis Song" and tro.artist == "Ogg Crew", "Vorbis comment tags read: %s / %s" % [tro.artist, tro.title])


func _frame3(id: String, body: PackedByteArray) -> PackedByteArray:
	var s := body.size()
	return id.to_ascii_buffer() + PackedByteArray([s >> 24 & 0xFF, s >> 16 & 0xFF, s >> 8 & 0xFF, s & 0xFF, 0, 0]) + body


func _frame4(id: String, body: PackedByteArray) -> PackedByteArray:
	return id.to_ascii_buffer() + _syncsafe(body.size()) + PackedByteArray([0, 0]) + body


func _syncsafe(n: int) -> PackedByteArray:
	return PackedByteArray([n >> 21 & 0x7F, n >> 14 & 0x7F, n >> 7 & 0x7F, n & 0x7F])


func _le32(n: int) -> PackedByteArray:
	return PackedByteArray([n & 0xFF, n >> 8 & 0xFF, n >> 16 & 0xFF, n >> 24 & 0xFF])


func _ogg_page(packet: PackedByteArray, seq: int) -> PackedByteArray:
	var segs := PackedByteArray()
	var left := packet.size()
	while left >= 255:
		segs.append(255)
		left -= 255
	segs.append(left)
	var head := "OggS".to_ascii_buffer() + PackedByteArray([0, 2 if seq == 0 else 0])
	head += PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0]) + _le32(1) + _le32(seq) + _le32(0)
	head.append(segs.size())
	return head + segs + packet


func _bytes(path: String, b: PackedByteArray) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(b)
	f.close()


# ── the playlists ─────────────────────────────────────────────────────────

func _playlists() -> void:
	var keys: Array = m.playlists.map(func(p): return p.key)
	var counts := {}
	for p in m.playlists:
		counts[p.key] = p.tracks.size()
	check(keys == [Library.ALL, "broken", "house", "rap", Library.MISC],
		"the playlists are the folders, ALL first, MISC (the loose songs) last, the empty folder and the one without songs left out: %s" % [keys])
	check(counts.get("house") == 3 and counts.get("rap") == 2 and counts.get(Library.MISC) == 1 and counts.get(Library.ALL) == 8,
		"their songs: HOUSE 3, RAP 2 (its album folder too), MISC 1, ALL every one (8): %s" % [counts])
	var names: Array = m.playlists.map(func(p): return p.name)
	check(names == ["ALL", "BROKEN", "HOUSE", "RAP", "MISC"], "their names: %s" % [names])
	check(m.skipped == 1, "an M4A (which Godot can't play) left out and counted, to say so (%d)" % m.skipped)
	var rap: Array = []
	for p in m.playlists:
		if p.key == "rap":
			rap = p.tracks.map(func(t): return "%s / %s" % [t.artist, t.title])
	check(rap == ["50 Cent / In Da Tone", " / Boom Bap Sine"], "the songs' names: %s" % [rap])


# ── playing ───────────────────────────────────────────────────────────────

func _playing() -> void:
	m.shuffle = false
	m.repeat = true
	m.select("house")
	var titles: Array = m.tracks().map(func(t): return t.title)
	await _until(_settled, 5.0)
	check(m.playing() and m.current.title == titles[0] and m.picked().key == "house",
		"HOUSE picked: its first song plays (%s)" % m.current.get("title", "nothing"))
	var bus := AudioServer.get_bus_index("Music")
	check(bus > 0 and AudioServer.get_bus_send(bus) == "Master" and m._players[m._cur].bus == "Music" and m._players[m._cur].playing,
		"on its own bus, Music, into the master")
	var seen: Array = [m.current.title]
	for k in 3:
		m.next()
		await _until(func(): return m.current.title != seen[seen.size() - 1], 5.0)
		seen.append(m.current.title)
	check(seen == titles + [titles[0]], "NEXT goes through each song once, then round again (repeat): %s" % [seen])
	m.prev()
	await _until(func(): return m.current.title == titles[2], 5.0)
	check(m.current.title == titles[2], "PREVIOUS: back one (%s)" % m.current.title)
	m._players[m._cur].seek(4.0)
	await _wait(0.1)
	m.prev()
	await _wait(0.3)
	check(m.current.title == titles[2] and m.position() < 2.0, "PREVIOUS a few seconds in: the same song from the start (at %.1f s)" % m.position())
	m.pause()
	var at: float = m.position()
	await _wait(0.4)
	check(m.paused and m._players[m._cur].stream_paused and absf(m.position() - at) < 0.05 and m.now_title() == "",
		"PAUSE holds the song where it was (the radio screens show the station's own)")
	m.toggle_pause()
	await _wait(0.4)
	check(not m.paused and m.position() > at + 0.15 and m.now_title() == titles[2], "PLAY carries on (%.2f -> %.2f s)" % [at, m.position()])
	m.set_repeat(false)
	m.play_track(2)
	await _until(func(): return m.current.title == titles[2], 5.0)
	m.next()
	await _wait(0.4)
	check(m.current.is_empty() and not m.playing(), "repeat off: past the last song it stops")
	m.start()
	await _until(_settled, 5.0)
	check(m.current.get("title", "") == titles[0], "PLAY after that: the playlist from the top (%s)" % m.current.get("title", "nothing"))
	m.set_repeat(true)
	m.set_enabled(false)
	await _wait(0.2)
	check(not m.on and m.current.is_empty() and not m._players[0].playing and not m._players[1].playing, "MUSIC OFF: silence")
	m.next()
	m.start()
	await _wait(0.3)
	check(m.current.is_empty(), "... and NEXT / PLAY don't start it while it's off")
	m.set_enabled(true)
	await _until(_settled, 5.0)
	check(m.playing(), "MUSIC ON: it plays again (%s)" % m.current.get("title", "nothing"))


func _crossfade() -> void:
	m.set_shuffle(false)
	m.play_track(0)
	await _until(func(): return m.playing() and m.current.title == m.tracks()[0].title, 5.0)
	var first: String = m.current.title
	var deck: int = m._cur
	m._players[deck].seek(SECS - m.FADE - 0.3)
	var both := false
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 3000:
		await process_frame
		if m._cur != deck and m._gain[deck] > 0.05 and m._gain[m._cur] > 0.05:
			both = true
			break
	check(both and m.current.title != first, "near the end the next song fades in over it: both heard for a while (%s into %s)" % [first, m.current.get("title", "")])
	await _wait(m.FADE + 0.4)
	check(not m._players[deck].playing and m._players[deck].stream == null and m._gain[m._cur] >= 1.0,
		"after the crossfade the old song's gone and the new one's full up")


func _shuffle() -> void:
	m.select(Library.ALL)
	m.set_shuffle(true)
	m.rng.seed = 7
	var n: int = m.tracks().size()
	var good := true
	var twice := false
	for r in 4:
		m._build_order()
		var seen := {}
		for i in m.order:
			seen[i] = true
		good = good and seen.size() == n
	# the round's end into the next: never the same song twice running (by stepping the order itself)
	m._build_order()
	m.at = -1
	var prev_i = -1
	var steps := 0
	for k in n * 5:
		m.at += 1
		if m.at >= m.order.size():
			var l = m.order[m.order.size() - 1]
			m._build_order()
			if m.order.size() > 1 and m.order[0] == l:
				m.order[0] = m.order[1]
				m.order[1] = l
			m.at = 0
		var i = m.order[m.at]
		twice = twice or i == prev_i
		prev_i = i
		steps += 1
	var orders := {}
	for k in 6:
		m._build_order()
		orders[str(m.order)] = true
	check(good and not twice and orders.size() > 1, "shuffle: every song once a round (%d), never the same one twice running over %d songs, a new order each round" % [n, steps])
	m.select("house")
	await _until(_settled, 5.0)
	var heard := {}
	heard[m.current.path] = true
	for k in 2:
		var was: String = m.current.path
		m.next()
		await _until(func(): return m.current.get("path", "") != was, 5.0)
		heard[m.current.path] = true
	check(heard.size() == 3, "shuffled, NEXT through HOUSE plays all three songs once (%d)" % heard.size())
	m.set_shuffle(false)


func _broken() -> void:
	m.select("broken")
	await _until(_settled, 6.0)
	check(m.current.get("title", "") == "b fine" and m.failed == 0 and m.last_error.contains("a broken.ogg"),
		"a file that won't play is skipped: the next one plays (%s; %s)" % [m.current.get("title", "nothing"), m.last_error])


## The co-driver's calls dip the music (an AICoDriver saying words), it comes back after.
func _duck() -> void:
	var ai: Node = load("res://scripts/vehicle/ai_codriver.gd").new()
	root.add_child(ai)
	m.set_volume(0.8)
	m._process(0.02)
	var full := AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music"))
	check(absf(full - linear_to_db(0.8)) < 0.2, "the volume is the Music bus's (%.1f dB at 0.8)" % full)
	var words: Array = []
	for w in ["left", "four", "over", "crest"]:
		if ai.has_word(w):
			words.append(w)
	ai.say(words)
	check(ai.is_in_group(m.VOICE_GROUP) and ai.busy(), "the AI co-driver is heard as the voice (%d words queued)" % words.size())
	for k in 30:
		m._process(1.0 / 60.0)
	var low := AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music"))
	check(absf(low - (full + m.DUCK_DB)) < 0.5, "while it calls, the music dips %.0f dB (%.1f -> %.1f dB)" % [m.DUCK_DB, full, low])
	ai.hush()
	for k in 30:
		m._process(1.0 / 60.0)
	var held := AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music"))
	for k in 120:
		m._process(1.0 / 60.0)
	var back := AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music"))
	check(held < full - 3.0 and absf(back - full) < 0.2, "after the call it comes back up gently (%.1f dB half a second on, %.1f dB later)" % [held, back])
	ai.queue_free()


## The settings saved, and read back by a fresh start.
func _persist() -> void:
	m.select("rap")
	m.set_volume(0.3)
	m.set_shuffle(false)
	m.set_repeat(false)
	m.set_enabled(false)
	var cf := ConfigFile.new()
	var ok := cf.load(ConfigScript.PATH) == OK
	check(ok and cf.get_value("music", "playlist", "") == "rap" and is_equal_approx(float(cf.get_value("music", "volume", 0.0)), 0.3)
		and cf.get_value("music", "shuffle", true) == false and cf.get_value("music", "repeat", true) == false
		and cf.get_value("music", "on", true) == false, "the playlist, volume, shuffle, repeat and on / off saved in user://settings.cfg")
	var fresh: Node = ConfigScript.new()                 # (another start: it reads the file)
	fresh.name = "FreshConfig"
	root.add_child(fresh)
	var fm = fresh.music
	check(fm != null and fm.playlist == "rap" and is_equal_approx(fm.volume, 0.3) and not fm.shuffle and not fm.repeat and not fm.on,
		"a fresh start reads them back (%s, %.2f, shuffle %s, repeat %s, on %s)" % [fm.playlist, fm.volume, fm.shuffle, fm.repeat, fm.on] if fm else "a fresh start made no player")
	fresh.free()
	m.set_enabled(true)
	m.set_repeat(true)
	m.set_volume(0.5)


## An empty music folder and a missing one: nothing to play, nothing breaks.
func _empty() -> void:
	DirAccess.make_dir_recursive_absolute(R + "_empty")
	m.root = R + "_empty"
	m.rescan()
	m.next()
	m.prev()
	m.start()
	m.toggle_pause()
	m.key_next()
	m.key_next(true)
	m.key_toggle()
	m.key_toggle()
	m.select("house")
	await _wait(0.3)
	check(m.playlists.is_empty() and m.current.is_empty() and m.song_count() == 0 and m.on,
		"an empty music folder: no playlists; play, next, previous, the keys, a playlist that isn't there: nothing breaks")
	var p: Control = MusicPanel.new()
	root.add_child(p)
	await _frames(3)
	var note: Label = p.find_child("EmptyNote", true, false)
	var texts: Array = p.find_children("*", "Label", true, false).map(func(l): return l.text)
	check(note != null and note.text.contains("music/house") and note.text.contains("music/rap")
		and texts.has(ProjectSettings.globalize_path(R + "_empty")), "the panel says where the songs go (music/house, music/rap) and the folder's path")
	p.queue_free()
	await _frames(2)
	m.root = R + "_missing"
	_rmdir(m.root)
	m.rescan()
	check(m.playlists.is_empty(), "a missing music folder: no playlists")
	Library.ensure_folder(m.root)
	check(DirAccess.dir_exists_absolute(m.root + "/house") and DirAccess.dir_exists_absolute(m.root + "/rap")
		and FileAccess.file_exists(m.root + "/" + Library.README), "... made when it's needed, with house/, rap/ and a note on what goes where")
	m.rescan()
	check(m.playlists.is_empty(), "... and its empty house/ and rap/ aren't playlists yet")
	m.root = R
	m.rescan()


## The MUSIC panel with songs: its playlists, its songs, the buttons.
func _panel() -> void:
	m.shuffle = false
	m.select("house")
	await _until(_settled, 5.0)
	var p: Control = MusicPanel.new()
	root.add_child(p)
	await _frames(3)
	var lists: Array = p._playlist_box.get_children()
	check(lists.size() == m.playlists.size() and p._song_btns.size() == 3, "the MUSIC panel: a button a playlist (%d), HOUSE's songs listed (%d)"
		% [lists.size(), p._song_btns.size()])
	var sk: Label = p.find_child("SkippedNote", true, false)
	check(sk != null and sk.visible and sk.text.begins_with("1 file here can't be played"), "it says a file can't be played (%s)" % (sk.text if sk else "none"))
	check(p._now_title.text == m.current.title and p._play.text == "PAUSE", "it shows the song playing (%s) and PAUSE" % p._now_title.text)
	for b in lists:
		if str(b.get_meta("pick")) == "list:rap":
			b.pressed.emit()
	await _until(func(): return m.picked().key == "rap" and m.playing() and m.current.path.contains("/rap/"), 5.0)
	await _frames(3)
	check(m.picked().key == "rap" and p._song_btns.size() == 2 and m.current.path.contains("/rap/"),
		"clicking RAP plays it, its songs listed (%d)" % p._song_btns.size())
	var playing_now: String = m.current.path
	m.select("rap")
	await _wait(0.3)
	check(m.current.path == playing_now and m._jobs.is_empty(), "clicking RAP again: the song playing plays on")
	var was: String = m.current.path
	for b in p.find_children("*", "Button", true, false):
		if b.text == "NEXT":
			b.pressed.emit()
	await _until(func(): return m.current.get("path", "") != was, 5.0)
	check(m.current.get("path", "") != was, "NEXT plays the next song")
	p._song_btns[0].pressed.emit()
	await _until(func(): return m.current.get("path", "") == p._song_btns[0].get_meta("path"), 5.0)
	check(m.current.get("path", "") == p._song_btns[0].get_meta("path"), "a song clicked in the list plays")
	p._play.pressed.emit()
	await _frames(2)
	check(m.paused and p._play.text == "PLAY", "PAUSE pauses (the button says PLAY)")
	p._play.pressed.emit()
	await _frames(2)
	check(not m.paused and p._play.text == "PAUSE", "PLAY plays")
	p._on.toggled.emit(false)
	await _frames(2)
	check(not m.on and m.current.is_empty() and p._now_head.text == "MUSIC OFF", "MUSIC: OFF from the panel")
	p._on.toggled.emit(true)
	await _until(_settled, 5.0)
	check(m.on and m.playing(), "... and ON")
	p._vol.value = 0.25
	check(is_equal_approx(m.volume, 0.25) and is_equal_approx(config.music_volume, 0.25), "its VOLUME slider sets the music's volume (saved)")
	m.set_volume(0.5)
	p.queue_free()
	await _frames(2)


## The cars' centre screens: the radio strip shows the song playing (the station's own when it's off).
func _radio() -> void:
	var page: Control = load("res://scripts/vehicle/dash_page.gd").new()
	root.add_child(page)
	m.set_shuffle(false)
	m.select("house")
	m.play_track(1)
	await _until(func(): return _settled() and m.current.title == m.tracks()[1].title, 5.0)
	var on_air: Array = page.radio_song(300.0)
	check(on_air[0] == str(m.tracks()[1].title).to_upper() and float(on_air[1]) >= 0.0 and float(on_air[1]) <= 1.0,
		"the cars' radio screens show the song playing: %s (%.0f %% in)" % [on_air[0], float(on_air[1]) * 100.0])
	m.set_enabled(false)
	var off_air: Array = page.radio_song(300.0)
	check(off_air[0] == "GRAVEL & GOLD", "music off: the station's own songs again (%s)" % off_air[0])
	m.set_enabled(true)
	page.queue_free()


## N and B: in the input map, not on any other key, and they work.
func _keys() -> void:
	var taken := {}
	for a in InputMap.get_actions():
		if str(a).begins_with("music_") or str(a).begins_with("replay_") or str(a).begins_with("ui_"):
			continue
		for e in InputMap.action_get_events(a):
			if e is InputEventKey:
				taken[(e as InputEventKey).physical_keycode] = a
	var n_ok := InputMap.has_action("music_next") and InputMap.action_get_events("music_next").any(func(e): return e is InputEventKey and e.physical_keycode == KEY_N)
	var b_ok := InputMap.has_action("music_toggle") and InputMap.action_get_events("music_toggle").any(func(e): return e is InputEventKey and e.physical_keycode == KEY_B)
	check(n_ok and b_ok and not taken.has(KEY_N) and not taken.has(KEY_B), "N (next song) and B (music on / off) in the input map, on keys nothing else uses")
	m.key_toggle()
	check(not m.on, "B turns the music off")
	m.key_toggle()
	check(m.on, "... and on")
	var rpc = m.get_script().get_rpc_config()
	check(rpc == null or (rpc is Dictionary and rpc.is_empty()), "nothing goes online: the player has no RPCs (each machine plays its own)")
	m.stop()


## The home screen's MUSIC chip opens the panel; on a stage the pause menu's MUSIC opens it over
## the stage, ESC back to the pause menu (its MUSIC in focus), ESC again resumes.
func _menus() -> void:
	OS.add_logger(errors)
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _until(func(): return main.menu != null and main.menu.backdrop.built, 120.0)
	var menu = main.menu
	var chip: Button = menu.find_child("MusicChip", true, false) if menu else null
	check(chip != null and chip.text.begins_with("MUSIC"), "the home screen has a MUSIC chip, top right (%s)" % (chip.text if chip else "none"))
	if chip:
		errors.take()
		chip.pressed.emit()
		await _frames(6)
		check(menu._open != null and menu._open.get_script() == MusicPanel and not menu._home.visible, "the MUSIC chip opens the MUSIC panel")
		await _esc()
		await _frames(4)
		check(menu._open == null and menu._home.visible, "ESC: back to the home buttons")
		_no_errors("the home screen")
	root.get_node("Net").solo()
	var o: Dictionary = main.quick_opts(7)
	o["length"] = 900.0
	main.load_stage(7, 1, o)
	await _until(func(): return main.game != null and main.game.built and _count(LoadingScreen) == 0, 300.0)
	var g = main.game
	check(g != null and g.built, "a stage loaded")
	if g == null or not g.built:
		OS.remove_logger(errors)
		return
	errors.take()
	await _esc()
	check(g._pause.visible and g._pause_music != null and g._pause_music.is_visible_in_tree(), "ESC on a stage: the pause menu has MUSIC")
	g._pause_music.pressed.emit()
	await _frames(4)
	var p: Control = null
	if g._settings:
		for c in g._settings.get_children():
			if c.get_script() == MusicPanel:
				p = c
	check(p != null and not g._pause.visible and g.paused(), "MUSIC opens the panel over the stage, still paused")
	await _esc()
	await _frames(3)
	check(g._settings == null and g._pause.visible and root.gui_get_focus_owner() == g._pause_music,
		"ESC: back to the pause menu, its MUSIC in focus")
	await _esc()
	check(not g._pause.visible and not g.paused(), "ESC again resumes")
	_no_errors("the pause menu")
	main.queue_free()
	await _frames(3)
	OS.remove_logger(errors)


func _no_errors(tag: String) -> void:
	var e := errors.take()
	check(e.is_empty(), "%s: no errors%s" % [tag, "" if e.is_empty() else ": " + " | ".join(e.slice(0, 3))])


func _count(script: Script) -> int:
	var n := 0
	for c in root.find_children("*", "", true, false):
		if c.get_script() == script and not c.is_queued_for_deletion():
			n += 1
	return n


func _esc() -> void:
	for down in [true, false]:
		var k := InputEventKey.new()
		k.keycode = KEY_ESCAPE
		k.physical_keycode = KEY_ESCAPE
		k.pressed = down
		Input.parse_input_event(k)
		if DisplayServer.get_name() == "headless":
			root.push_input(k)
		await _frames(2)


## A song asked for has loaded and is playing (none still on its way).
func _settled() -> bool:
	return m._jobs.is_empty() and not m._advancing and m.playing()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


## Real seconds (the songs play in real time; the frames here run as fast as they can).
func _wait(secs: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < secs * 1000.0:
		await process_frame


func _until(cond: Callable, limit: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call():
		if Time.get_ticks_msec() - t0 > limit * 1000.0:
			return false
		await process_frame
	return true
