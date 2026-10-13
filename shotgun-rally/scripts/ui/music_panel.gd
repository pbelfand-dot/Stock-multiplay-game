extends PanelContainer
## MUSIC: your own songs (MusicPlayer, Config.music), from the music folder on this computer, each
## folder in it a playlist. Pick the playlist (ALL, HOUSE, RAP ..., MISC), see what's playing and how
## far in, PREVIOUS / PLAY-PAUSE / NEXT, shuffle, repeat, music on / off, its volume, a song from
## the list, and OPEN MUSIC FOLDER (Finder / Explorer). No songs yet: a line on where they go, and
## the folder's path. Opened from the home screen (the MUSIC chip, top right) and the pause menu.
## Everything's saved as it changes (Config, user://settings.cfg); nothing here goes online.

signal back

const UI = preload("res://scripts/ui/ui_kit.gd")
const STYLE := "night"

var music                            # MusicPlayer
var _body: VBoxContainer             # what's below the title: the player, or the empty folder's note
var _lists_key := ""                 # the playlists and the pick the lists were built for
var _playlist_box: VBoxContainer
var _song_box: VBoxContainer
var _song_btns: Array = []
var _now_head: Label
var _now_title: Label
var _now_artist: Label
var _bar_back: Panel
var _bar_fill: Panel
var _time: Label
var _play: Button
var _shuffle: Button
var _repeat: Button
var _on: Button
var _vol: HSlider
var _back_btn: Button
var _skipped: Label                  # "3 files can't be played here (M4A, FLAC ...)"


func _ready() -> void:
	add_theme_stylebox_override("panel", UI.panel_skin(STYLE))
	custom_minimum_size = Vector2(1000, 0)
	music = get_node("/root/Config").music
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	v.add_child(top)
	var title := UI.label("MUSIC", 34, UI.CREAM, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	if music.available():
		top.add_child(UI.button("REFRESH", _on_refresh, 17, 0, STYLE))
		top.add_child(UI.button("OPEN MUSIC FOLDER", func(): music.open_folder(), 17, 0, STYLE))
	v.add_child(_note("Your own songs, from the music folder on this computer: a playlist per folder. Nothing is sent online.", 940, 15))
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 6)
	v.add_child(_body)
	_skipped = UI.label("", 15, Color(1.0, 0.7, 0.4))
	_skipped.name = "SkippedNote"
	v.add_child(_skipped)
	v.add_child(UI.gap(2))
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 18)
	v.add_child(foot)
	_back_btn = UI.button("BACK", func(): back.emit(), 20, 140, STYLE)
	_back_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(_back_btn)
	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", 0)
	foot.add_child(lines)
	lines.add_child(UI.label("KEYS  ·  N  the next song  (SHIFT+N  the one before)   ·   B  music on / off", 15, UI.DIM))
	if music.available():
		var path := _note("FOLDER  ·  " + music.folder_path(), 780, 13)
		path.name = "FolderPath"
		lines.add_child(path)
	if music.available():
		music.rescan()                               # (songs dropped in since: they're there)
		music.changed.connect(_refresh)
	_lists_key = _key()
	_rebuild()
	_update_now()
	if _play:
		_play.grab_focus.call_deferred()
	elif not music.available():
		_back_btn.grab_focus.call_deferred()


func _on_refresh() -> void:
	music.rescan()
	_refresh()


## What the lists show: the playlists, their songs, the pick (rebuilt only when that changes, so
## the focus stays put while a song plays on).
func _key() -> String:
	var parts: Array = [music.available(), music.picked().get("key", "")]
	for p in music.playlists:
		parts.append("%s:%d" % [p.key, p.tracks.size()])
	return "|".join(parts)


func _refresh() -> void:
	if not is_inside_tree():
		return
	var k := _key()
	if k != _lists_key:
		_lists_key = k
		_rebuild.call_deferred()                     # (not inside the press of a button it frees)
		_update_now.call_deferred()
	else:
		_update_now()


func _rebuild() -> void:
	var f: Control = get_viewport().gui_get_focus_owner() if get_viewport() else null
	var had: String = str(f.get_meta("pick")) if f and f.has_meta("pick") else ""
	for c in _body.get_children():
		c.queue_free()
		_body.remove_child(c)
	_play = null
	_song_btns.clear()
	if not music.available():
		_body.add_child(UI.label("Your own music plays in the download version.", 26, UI.YELLOW, true))
		_body.add_child(_note("A browser can't read a folder on your computer. Get SHOTGUN RALLY for Windows, Mac or "
			+ "Linux from the download page, then put your songs in its music folder.", 900, 17))
		return
	if music.playlists.is_empty():
		_empty()
		return
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 30)
	_body.add_child(cols)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(290, 0)
	left.add_theme_constant_override("separation", 6)
	cols.add_child(left)
	left.add_child(UI.label("PLAYLISTS", 20, UI.YELLOW, true))
	var pscroll := ScrollContainer.new()
	pscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pscroll.follow_focus = true
	pscroll.custom_minimum_size = Vector2(290, 300)
	left.add_child(pscroll)
	_playlist_box = VBoxContainer.new()
	_playlist_box.add_theme_constant_override("separation", 6)
	_playlist_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pscroll.add_child(_playlist_box)
	var picked: String = music.picked().get("key", "")
	for p in music.playlists:
		var b := UI.button("%s   ·   %d" % [p.name, p.tracks.size()], music.select.bind(p.key), 20, 270, STYLE)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		b.set_meta("pick", "list:" + p.key)
		if p.key == picked:
			UI.mark(b)
		_playlist_box.add_child(b)
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(640, 0)
	right.add_theme_constant_override("separation", 4)
	cols.add_child(right)
	_now_head = UI.label("NOW PLAYING", 20, UI.YELLOW, true)
	right.add_child(_now_head)
	_now_title = UI.label("", 30, UI.CREAM, true)
	_now_title.clip_text = true
	_now_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_now_title.custom_minimum_size = Vector2(620, 0)
	right.add_child(_now_title)
	_now_artist = UI.label("", 18, UI.DIM)
	_now_artist.clip_text = true
	_now_artist.custom_minimum_size = Vector2(620, 0)
	right.add_child(_now_artist)
	var bar_row := HBoxContainer.new()
	bar_row.add_theme_constant_override("separation", 12)
	right.add_child(bar_row)
	_bar_back = Panel.new()
	_bar_back.add_theme_stylebox_override("panel", UI.box(Color(1, 1, 1, 0.12), 4, 0))
	_bar_back.custom_minimum_size = Vector2(480, 10)
	_bar_back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar_row.add_child(_bar_back)
	_bar_fill = Panel.new()
	_bar_fill.add_theme_stylebox_override("panel", UI.box(UI.YELLOW, 4, 0))
	_bar_fill.size = Vector2(0, 10)
	_bar_back.add_child(_bar_fill)
	_time = UI.label("", 17, UI.CREAM)
	bar_row.add_child(_time)
	var ctl := HBoxContainer.new()
	ctl.add_theme_constant_override("separation", 10)
	right.add_child(ctl)
	var prev := UI.button("PREVIOUS", func(): music.prev(), 20, 150, STYLE)
	ctl.add_child(prev)
	_play = UI.button("PLAY", func(): music.toggle_pause(), 20, 150, STYLE)
	_play.name = "PlayPause"
	ctl.add_child(_play)
	var nxt := UI.button("NEXT", func(): music.next(), 20, 150, STYLE)
	ctl.add_child(nxt)
	var sw := HBoxContainer.new()
	sw.add_theme_constant_override("separation", 22)
	right.add_child(sw)
	_shuffle = _switch(sw, "SHUFFLE", func(on): music.set_shuffle(on))
	_repeat = _switch(sw, "REPEAT", func(on): music.set_repeat(on))
	_on = _switch(sw, "MUSIC", func(on): music.set_enabled(on))
	var vrow := HBoxContainer.new()
	vrow.add_theme_constant_override("separation", 12)
	right.add_child(vrow)
	vrow.add_child(UI.label("VOLUME", 18, UI.CREAM))
	_vol = HSlider.new()
	_vol.min_value = 0.0
	_vol.max_value = 1.0
	_vol.step = 0.01
	_vol.value = music.volume
	_vol.custom_minimum_size = Vector2(300, 24)
	_vol.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_vol.focus_mode = Control.FOCUS_ALL
	_vol.scrollable = false                          # (the wheel scrolls the song list, not the volume it passes)
	_vol.value_changed.connect(func(x: float): music.set_volume(x))
	vrow.add_child(_vol)
	right.add_child(UI.label("SONGS  ·  " + str(music.picked().get("name", "")), 18, UI.YELLOW, true))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.custom_minimum_size = Vector2(640, 130)
	right.add_child(scroll)
	_song_box = VBoxContainer.new()
	_song_box.add_theme_constant_override("separation", 0)
	_song_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_song_box)
	var tr: Array = music.tracks()
	for i in tr.size():
		var t: Dictionary = tr[i]
		var b := Button.new()
		b.text = ("%s  ·  %s" % [t.title, t.artist]) if str(t.artist) != "" else str(t.title)
		b.flat = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.custom_minimum_size = Vector2(610, 28)
		b.add_theme_font_override("font", UI.med())
		b.add_theme_font_size_override("font_size", 17)
		b.add_theme_color_override("font_color", UI.CREAM)
		b.add_theme_color_override("font_hover_color", UI.YELLOW)
		b.add_theme_color_override("font_focus_color", UI.YELLOW)
		b.set_meta("path", t.path)
		b.set_meta("pick", "song:" + str(t.path))
		b.pressed.connect(music.play_track.bind(i))
		_song_box.add_child(b)
		_song_btns.append(b)
	if had != "":                                   # (the focus back on what it was on)
		for b in _playlist_box.get_children() + _song_btns:
			if str(b.get_meta("pick", "")) == had:
				b.grab_focus.call_deferred()


## No songs yet: where they go, and the folder.
func _empty() -> void:
	_body.add_child(UI.gap(6))
	_body.add_child(UI.label("NO SONGS YET", 30, UI.YELLOW, true))
	var how := _note("Put your songs in your music folder, one folder per playlist: music/house, music/rap, and so on "
		+ "(MP3, OGG or WAV; songs loose in music/ are the MISC playlist). Then press REFRESH, or just come back here.", 900, 19)
	how.add_theme_color_override("font_color", UI.CREAM)
	how.name = "EmptyNote"
	_body.add_child(how)
	var path := _note(music.folder_path(), 900, 17)
	path.add_theme_color_override("font_color", UI.YELLOW)
	_body.add_child(path)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_body.add_child(row)
	var open := UI.button("OPEN MUSIC FOLDER", func(): music.open_folder(), 22, 300, STYLE)
	row.add_child(open)
	row.add_child(UI.button("REFRESH", _on_refresh, 22, 160, STYLE))
	open.grab_focus.call_deferred()


## What's playing, how far in, the buttons' words: every change, and every frame for the clock.
func _update_now() -> void:
	var n: int = music.skipped
	_skipped.text = ("%d %s here can't be played (M4A, FLAC, OPUS ...): convert %s to MP3 or OGG." % [n,
		"file" if n == 1 else "files", "it" if n == 1 else "them"]) if n > 0 else ""
	_skipped.visible = n > 0
	if _now_title == null or not is_instance_valid(_now_title):
		return
	var cur: Dictionary = music.current
	if not music.on:
		_now_head.text = "MUSIC OFF"
		_now_title.text = "Turn MUSIC on (or press B)"
		_now_artist.text = ""
	elif cur.is_empty():
		_now_head.text = "NOW PLAYING"
		_now_title.text = "Nothing yet: press PLAY, or pick a song"
		_now_artist.text = ""
	else:
		_now_head.text = ("PAUSED  ·  " if music.paused else "NOW PLAYING  ·  ") + str(music.picked().get("name", ""))
		_now_title.text = str(cur.title)
		_now_artist.text = str(cur.get("artist", ""))
	_play.text = "PLAY" if cur.is_empty() or music.paused or not music.on else "PAUSE"
	_set_switch(_shuffle, music.shuffle)
	_set_switch(_repeat, music.repeat)
	_set_switch(_on, music.on)
	if not is_equal_approx(_vol.value, music.volume):
		_vol.set_value_no_signal(music.volume)
	var playing_path := str(cur.get("path", ""))
	for b in _song_btns:
		var now: bool = str(b.get_meta("path")) == playing_path
		b.add_theme_color_override("font_color", UI.YELLOW if now else UI.CREAM)
	_clock()


func _clock() -> void:
	if _bar_fill == null or not is_instance_valid(_bar_fill):
		return
	_bar_fill.size = Vector2(_bar_back.size.x * music.progress(), _bar_back.size.y)
	_time.text = "%s / %s" % [_mmss(music.position()), _mmss(music.length())] if not music.current.is_empty() else ""


func _process(_dt: float) -> void:
	_clock()
	if _play and is_instance_valid(_play):
		var want := "PLAY" if music.current.is_empty() or music.paused or not music.on else "PAUSE"
		if _play.text != want:
			_update_now()


## A switch with its name before it: an ON / OFF button; apply(on) when it's flipped.
func _switch(row: HBoxContainer, title: String, apply: Callable) -> Button:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.add_child(UI.label(title, 18, UI.CREAM))
	var b := UI.button("ON", func(): pass, 16, 72, STYLE)
	b.toggle_mode = true
	b.name = title.capitalize()
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.toggled.connect(func(now: bool):
		b.text = "ON" if now else "OFF"
		apply.call(now))
	box.add_child(b)
	row.add_child(box)
	return b


func _set_switch(b: Button, v: bool) -> void:
	if b and b.button_pressed != v:
		b.set_pressed_no_signal(v)
	if b:
		b.text = "ON" if v else "OFF"


static func _mmss(t: float) -> String:
	var s := maxi(int(t), 0)
	return "%d:%02d" % [s / 60, s % 60]


func _note(text: String, width := 300.0, size := 14) -> Label:
	var l := UI.label(text, size, UI.DIM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(width, 0)
	return l
