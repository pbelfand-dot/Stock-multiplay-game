extends RefCounted
## The players' own music, read from a folder on their own machine (never in the game: the repo
## and its downloads are public, so no song is ever committed or bundled). Static helpers; the
## player is MusicPlayer (scripts/audio/music_player.gd).
##
##   user://music/            (Mac: ~/Library/Application Support/Godot/app_userdata/SHOTGUN RALLY/music,
##                             Windows: %APPDATA%\Godot\app_userdata\SHOTGUN RALLY\music)
##     house/   a playlist: every MP3 / OGG / WAV in it, and in folders inside it (an album)
##     rap/     another
##     *.mp3    loose files: the MISC playlist
## ALL (every song in every playlist) comes first when there's more than one playlist.
##
## A song's name comes from its tags (ID3v2 in an MP3, Vorbis comments in an OGG) or else from
## its file name: the track number, the extension and YouTube-style junk ("(Official Video)")
## taken off, "Artist - Title" split in two.

const EXTS := ["mp3", "ogg", "wav"]
const OTHER_AUDIO := ["m4a", "aac", "flac", "opus", "wma", "aif", "aiff", "alac"]   # (Godot can't play them: counted, to say so)
const ALL := "*"                    # the playlist keys that can't be a folder's name
const MISC := "."
const DEPTH := 4                    # folders inside a playlist's folder still looked into
const TAG_BYTES := 65536            # read this much of a file for its tags
const MAX_BYTES := 300 * 1024 * 1024   # a file bigger than this isn't loaded (it'd sit in memory whole)
const README := "PUT YOUR SONGS HERE.txt"

static var _cache := {}             # path -> [modified time, {title, artist}]: a rescan only reads new files
static var skipped := 0             # the last scan's audio files that can't be played (M4A, FLAC ...)


## The playlists in `root` (a user:// folder), ALL first, MISC last:
## [{key, name, tracks: [{path, file, title, artist}]}]. Empty folders are left out.
static func scan(root: String) -> Array:
	var out: Array = []
	skipped = 0
	var d := DirAccess.open(root)
	if d == null:
		return out
	var loose := _songs_in(root, 0, false)
	var dirs: Array = Array(d.get_directories())
	dirs.sort_custom(func(a: String, b: String): return a.naturalnocasecmp_to(b) < 0)
	for sub in dirs:
		if sub.begins_with("."):
			continue
		var tracks := _songs_in(root.path_join(sub), 1, true)
		if not tracks.is_empty():
			out.append({"key": sub, "name": sub.to_upper(), "tracks": tracks})
	if not loose.is_empty():
		out.append({"key": MISC, "name": "MISC", "tracks": loose})
	if out.size() > 1:
		var every: Array = []
		for p in out:
			every.append_array(p.tracks)
		out.push_front({"key": ALL, "name": "ALL", "tracks": every})
	return out


## The songs in a folder (and, `deep`, the folders inside it), in name order.
static func _songs_in(dir: String, depth: int, deep: bool) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	var files: Array = Array(d.get_files())
	files.sort_custom(func(a: String, b: String): return a.naturalnocasecmp_to(b) < 0)
	for f in files:
		if f.begins_with("."):
			continue
		var ext: String = str(f).get_extension().to_lower()
		if ext in EXTS:
			out.append(track(dir.path_join(f)))
		elif ext in OTHER_AUDIO:
			skipped += 1
	if deep and depth < DEPTH:
		var dirs: Array = Array(d.get_directories())
		dirs.sort_custom(func(a: String, b: String): return a.naturalnocasecmp_to(b) < 0)
		for sub in dirs:
			if not sub.begins_with("."):
				out.append_array(_songs_in(dir.path_join(sub), depth + 1, true))
	return out


## One song: its path and the name to show (its tags, else its file name).
static func track(path: String) -> Dictionary:
	var t := {"path": path, "file": path.get_file()}
	var named := name_from_file(path.get_file())
	var tags := _tags_cached(path)
	t["title"] = str(tags.get("title", "")) if str(tags.get("title", "")) != "" else named.title
	t["artist"] = str(tags.get("artist", "")) if str(tags.get("title", "")) != "" else named.artist
	return t


## "03 - Artist - Title (Official Video).mp3" -> {artist: "Artist", title: "Title"}.
## A leading track number goes when punctuation follows it ("01. ", "1 - ", "01_"), it's a disc-
## track pair ("1-02 ") or it's zero-padded ("01 "): "50 Cent - In Da Club" keeps its 50.
static func name_from_file(file: String) -> Dictionary:
	var t := file.get_basename().replace("_", " ").strip_edges()
	for pat in ["^\\d{1,2}-\\d{1,3}\\s+", "^\\d{1,3}\\s*[.)\\]-]\\s*", "^0\\d\\s+"]:
		var re := RegEx.create_from_string(pat)
		var cut := re.sub(t, "")
		if cut != t and cut.strip_edges() != "":
			t = cut
			break
	var junk := RegEx.create_from_string("(?i)\\s*[(\\[][^)\\]]*(official|audio|video|lyrics?|visuali[sz]er|\\bhq\\b|\\bhd\\b|4k)[^)\\]]*[)\\]]")
	t = junk.sub(t, "", true)
	t = RegEx.create_from_string("\\s+").sub(t, " ", true).strip_edges()
	var artist := ""
	var dash := t.find(" - ")
	if dash > 0 and dash < t.length() - 3:
		artist = t.substr(0, dash).strip_edges()
		t = t.substr(dash + 3).strip_edges()
	if t == "":
		t = file.get_basename()
	return {"title": t, "artist": artist}


static func _tags_cached(path: String) -> Dictionary:
	var mt := FileAccess.get_modified_time(path)
	if _cache.has(path) and int(_cache[path][0]) == mt:
		return _cache[path][1]
	var tags := read_tags(path)
	_cache[path] = [mt, tags]
	return tags


## {title, artist} from the file's tags (ID3v2 in an MP3, Vorbis comments in an OGG); {} if none.
static func read_tags(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var head := f.get_buffer(mini(TAG_BYTES, f.get_length()))
	f.close()
	if head.size() >= 10 and head[0] == 0x49 and head[1] == 0x44 and head[2] == 0x33:   # "ID3"
		return _id3(head)
	if head.size() >= 4 and head.slice(0, 4).get_string_from_ascii() == "OggS":
		return _vorbis(head)
	return {}


## ID3v2.2 / 2.3 / 2.4: the title (TIT2 / TT2) and artist (TPE1 / TP1) frames.
static func _id3(b: PackedByteArray) -> Dictionary:
	var ver := b[3]
	var flags := b[5]
	var end := mini(10 + _syncsafe(b, 6), b.size())
	var p := 10
	if flags & 0x40 and ver >= 3:                    # an extended header: skip it
		p += _syncsafe(b, 10) if ver == 4 else (_u32be(b, 10) + 4)
	var id_len := 3 if ver == 2 else 4
	var head_len := 6 if ver == 2 else 10
	var want := {"TIT2": "title", "TT2": "title", "TPE1": "artist", "TP1": "artist"}
	var out := {}
	while p + head_len <= end and out.size() < 2:
		var id := b.slice(p, p + id_len).get_string_from_ascii()
		if id == "" or b[p] == 0:
			break                                    # the padding
		var size := 0
		if ver == 2:
			size = (b[p + 3] << 16) | (b[p + 4] << 8) | b[p + 5]
		elif ver == 4:
			size = _syncsafe(b, p + 4)
		else:
			size = _u32be(b, p + 4)
		var body := p + head_len
		if size <= 0 or body + size > b.size():
			break
		if want.has(id):
			var text := _id3_text(b.slice(body, body + size))
			if text != "":
				out[want[id]] = text
		p = body + size
	return out


## A text frame's words: its first byte says how they're written (Latin-1, UTF-16 with a byte-order
## mark, UTF-16 big-endian, UTF-8). Several values (2.4): the first.
static func _id3_text(b: PackedByteArray) -> String:
	if b.size() < 2:
		return ""
	var enc := b[0]
	var s := ""
	var body := b.slice(1)
	match enc:
		0:
			for c in body:
				if c == 0:
					break
				s += char(c)
		1, 2:
			var little := false
			var i := 0
			if enc == 1 and body.size() >= 2:
				if body[0] == 0xFF and body[1] == 0xFE:
					little = true
					i = 2
				elif body[0] == 0xFE and body[1] == 0xFF:
					i = 2
			var units := PackedInt32Array()
			while i + 1 < body.size():
				var u: int = (body[i + 1] << 8 | body[i]) if little else (body[i] << 8 | body[i + 1])
				if u == 0:
					break
				units.append(u)
				i += 2
			var k := 0
			while k < units.size():
				var u := units[k]
				if u >= 0xD800 and u < 0xDC00 and k + 1 < units.size():   # a surrogate pair
					s += char(0x10000 + ((u - 0xD800) << 10) + (units[k + 1] - 0xDC00))
					k += 2
					continue
				s += char(u)
				k += 1
		3:
			var stop := body.find(0)
			s = (body.slice(0, stop) if stop >= 0 else body).get_string_from_utf8()
	return s.strip_edges()


## An Ogg Vorbis file's comment header (TITLE=, ARTIST=): the second packet, gathered from the
## pages after the first (the first page holds only the identification header).
static func _vorbis(b: PackedByteArray) -> Dictionary:
	var data := PackedByteArray()
	var p := 0
	var page := 0
	while p + 27 <= b.size():
		if b.slice(p, p + 4).get_string_from_ascii() != "OggS":
			break
		var segs := b[p + 26]
		var body := p + 27 + segs
		var body_len := 0
		for k in segs:
			if p + 27 + k < b.size():
				body_len += b[p + 27 + k]
		if page > 0:
			data.append_array(b.slice(body, mini(body + body_len, b.size())))
		p = body + body_len
		page += 1
	if data.size() < 15 or data[0] != 3 or data.slice(1, 7).get_string_from_ascii() != "vorbis":
		return {}
	var q := 7
	var vendor := _u32le(data, q)
	q += 4 + vendor
	if q + 4 > data.size():
		return {}
	var count := _u32le(data, q)
	q += 4
	var out := {}
	for k in mini(count, 200):
		if q + 4 > data.size():
			break
		var n := _u32le(data, q)
		q += 4
		if n < 0 or q + n > data.size():
			break
		var c := data.slice(q, q + n).get_string_from_utf8()
		q += n
		var eq := c.find("=")
		if eq > 0:
			var key := c.substr(0, eq).to_upper()
			if key == "TITLE" and not out.has("title"):
				out["title"] = c.substr(eq + 1).strip_edges()
			elif key == "ARTIST" and not out.has("artist"):
				out["artist"] = c.substr(eq + 1).strip_edges()
	return out


static func _syncsafe(b: PackedByteArray, i: int) -> int:
	if i + 4 > b.size():
		return 0
	return ((b[i] & 0x7F) << 21) | ((b[i + 1] & 0x7F) << 14) | ((b[i + 2] & 0x7F) << 7) | (b[i + 3] & 0x7F)


static func _u32be(b: PackedByteArray, i: int) -> int:
	if i + 4 > b.size():
		return 0
	return (b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3]


static func _u32le(b: PackedByteArray, i: int) -> int:
	if i + 4 > b.size():
		return 0
	return b[i] | (b[i + 1] << 8) | (b[i + 2] << 16) | (b[i + 3] << 24)


## The song as a stream to play, read from the file now (Godot 4.7's load_from_file for each kind:
## no import, straight off the disk); null if it can't be played. Safe off the main thread (the
## player loads songs on a worker so a track change never stutters the game).
static func load_stream(path: String) -> AudioStream:
	if not FileAccess.file_exists(path) or FileAccess.get_size(path) > MAX_BYTES or FileAccess.get_size(path) < 16:
		return null
	var s: AudioStream = null
	match path.get_extension().to_lower():
		"mp3":
			s = AudioStreamMP3.load_from_file(path)
			if s:
				(s as AudioStreamMP3).loop = false
		"ogg":
			s = AudioStreamOggVorbis.load_from_file(path)
			if s:
				(s as AudioStreamOggVorbis).loop = false
		"wav":
			s = AudioStreamWAV.load_from_file(path)
			if s:
				(s as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_DISABLED
	if s != null and s.get_length() <= 0.0:
		return null                                  # (not really a song: no length)
	return s


## Make the music folder (and, the first time, house/ and rap/, a folder for each mode's AUTO playlist
## (garage/ street/ cutup/ touge/ rally/ gt/ formula/) and a note on what goes where).
static func ensure_folder(root: String) -> void:
	if DirAccess.dir_exists_absolute(root):
		return
	DirAccess.make_dir_recursive_absolute(root)
	for sub in ["house", "rap", "garage", "street", "cutup", "touge", "rally", "gt", "formula"]:
		DirAccess.make_dir_recursive_absolute(root.path_join(sub))
	var f := FileAccess.open(root.path_join(README), FileAccess.WRITE)
	if f:
		f.store_string("SHOTGUN RALLY plays your own music from this folder.\n\n"
			+ "Each folder in here is a playlist: put house tracks in house/, rap in rap/, or make your own\n"
			+ "folders (chill/, drift/ ...). MP3, OGG (Vorbis) and WAV files (M4A, AAC and FLAC won't play:\n"
			+ "convert them to MP3 first). Songs left loose in this folder are the MISC playlist; ALL plays\n"
			+ "everything.\n\n"
			+ "AUTO (the first pick) plays the folder named for what you're playing: garage/ in the menus,\n"
			+ "street/ (online touge races), cutup/, touge/, rally/, gt/ and formula/ on the road; a mode with\n"
			+ "no songs of its own plays a close one (street, touge and cut up share; GT and Formula share), else ALL.\n\n"
			+ "Pick the playlist in the game's MUSIC (the chip top right of the home screen, or the pause menu).\n"
			+ "Keys: N the next song (SHIFT+N the one before), B music on / off.\n\n"
			+ "Your songs stay on this computer: nothing is uploaded or sent to the others online.\n")
		f.close()
