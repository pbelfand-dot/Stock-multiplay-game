extends RefCounted
## Save slots for runs (the fund, the day you're on, everyone's items/stats).
## Local-first, and synced for free through iCloud Drive when the Mac has it:
## saves go to ~/Library/Mobile Documents/com~apple~CloudDocs/BAGHOLDERS Saves
## (so the same run continues on another Mac), otherwise user://saves.
## Careers (XP, rank) and owned flex already persist separately (careers.cfg).
##
## A save is written by the HOST at every closing bell. Players are matched by
## name when they rejoin (peer ids change every session).

const VERSION := 1
const LOCAL_DIR := "user://saves"
const ICLOUD_SUB := "Library/Mobile Documents/com~apple~CloudDocs"

static var dir_override := ""      # tests


## Where saves live right now, and whether that's iCloud.
static func dir() -> String:
	if dir_override != "":
		return dir_override
	if Config.cloud_saves:
		var cloud := icloud_dir()
		if cloud != "":
			return cloud
	return LOCAL_DIR


static func icloud_dir() -> String:
	if OS.get_name() != "macOS":
		return ""
	var home := OS.get_environment("HOME")
	var docs := home.path_join(ICLOUD_SUB)
	if home == "" or not DirAccess.dir_exists_absolute(docs):
		return ""
	return docs.path_join("BAGHOLDERS Saves")


static func in_cloud() -> bool:
	return dir() != LOCAL_DIR and dir() == icloud_dir()


static func _path(slot: String) -> String:
	return dir().path_join(slot + ".json")


## A new slot name for a fresh run: "coop-20260928-0340".
static func new_slot(mode: String) -> String:
	var t := Time.get_datetime_dict_from_system()
	return "%s-%04d%02d%02d-%02d%02d%02d" % [mode, t.year, t.month, t.day, t.hour, t.minute, t.second]


static func write(slot: String, data: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(dir())
	data["v"] = VERSION
	data["slot"] = slot
	data["updated"] = int(Time.get_unix_time_from_system())
	var tmp := _path(slot) + ".tmp"            # write-then-rename: a crash never leaves half a save
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	return DirAccess.rename_absolute(tmp, _path(slot)) == OK


static func read(slot: String) -> Dictionary:
	var f := FileAccess.open(_path(slot), FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


static func remove(slot: String) -> void:
	DirAccess.remove_absolute(_path(slot))


## All saves, newest first: [{slot, mode, day, balance, updated, over, players}]
static func list() -> Array:
	var out: Array = []
	var d := DirAccess.open(dir())
	if d == null:
		return out
	for fname in d.get_files():
		if not fname.ends_with(".json"):
			continue
		var s := read(fname.get_basename())
		if not s.is_empty():
			out.append(s)
	out.sort_custom(func(a, b): return int(a.get("updated", 0)) > int(b.get("updated", 0)))
	return out


## Only the trader who started a run (the host, by name) can load it.
## Saves from before owners existed are anyone's.
static func owned_by(s: Dictionary, who: String) -> bool:
	var o := str(s.get("owner", ""))
	return o == "" or o.to_lower() == who.strip_edges().to_lower()


## The newest run `who` can still continue (not busted / finished, theirs).
static func latest_open(who: String = "") -> Dictionary:
	for s in list():
		if not s.get("over", false) and (who == "" or owned_by(s, who)):
			return s
	return {}


## "Co-op · day 3 · $41.2K · 2 traders · Sep 28 03:40"
static func describe(s: Dictionary) -> String:
	var t := Time.get_datetime_dict_from_unix_time(int(s.get("updated", 0)))
	var months := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	var who := ", ".join(s.get("names", []))
	return "%s · day %d · %s%s · %s %d %02d:%02d" % [
			"Co-op" if s.get("mode", "coop") == "coop" else "PvP", int(s.get("day", 0)),
			_money(float(s.get("balance", 0.0))), (" · " + who) if who != "" else "",
			months[clampi(int(t.month) - 1, 0, 11)], int(t.day), int(t.hour), int(t.minute)]


static func _money(v: float) -> String:
	if absf(v) >= 1_000_000.0:
		return "$%.2fM" % (v / 1_000_000.0)
	return "$%.1fK" % (v / 1000.0)
