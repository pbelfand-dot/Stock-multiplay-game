extends Node
## Keeps the game up to date (autoload "Updater", the FIRST autoload).
##   * every build from main publishes, next to the download zips, an update
##     pack (ShotgunRally.pck: the whole game's content) and version.json
##     ({build, base, sha256, size, notes}). CI writes the build number into the
##     exported game (application/config/version) and its "base"
##     (application/config/update_base): a fingerprint of what a pack can't
##     change (the engine version, project.godot: autoloads, inputs, physics
##     settings..., and this script, which is already running when a pack loads)
##   * at start (here, before the other autoloads load) a downloaded pack that's
##     newer than this build and made for the same base is loaded over the
##     game's own files, so the rest of the game starts as the new version. If
##     it didn't make it to the menu last time, it's dropped and the game starts
##     as it was installed
##   * at the menu: check version.json; newer -> download the pack in the
##     background, check its size and SHA-256, then RESTART TO UPDATE (or it
##     applies by itself next launch). A newer build on another base needs the
##     new download: the button opens the download page
##   * while the GitHub repo is private the check can't reach the files: the
##     button opens the download page instead (works with no change once it's public)

signal status_changed(text: String, action: String)   # action: "" | "restart" | "download_page"

const URL := "https://github.com/pbelfand-dot/Stock-multiplay-game/releases/download/shotgun-latest/"
const PAGE := "https://github.com/pbelfand-dot/Stock-multiplay-game/releases/tag/shotgun-latest"
const DIR := "user://update/"

var base_build := 0             # the build this copy was exported as (0 = not an export: editor, tests)
var current_build := 0          # ... or the update pack applied over it
var base := ""                  # what packs this copy can take (see above)
var status := ""
var action := ""
var _http: HTTPRequest
var _remote := {}
var _checked := false
var _downloading := false


func _init() -> void:
	base_build = int(str(ProjectSettings.get_setting("application/config/version", "0")))
	base = str(ProjectSettings.get_setting("application/config/update_base", ""))
	current_build = base_build
	_apply_pending()


## A downloaded pack newer than this build: load it over the game's files now,
## before the other autoloads and the main scene load.
func _apply_pending() -> void:
	if base_build == 0:
		return
	var vf := DIR + "version.json"
	var pck := DIR + "ShotgunRally.pck"
	if not FileAccess.file_exists(vf) or not FileAccess.file_exists(pck):
		return
	var v = JSON.parse_string(FileAccess.get_file_as_string(vf))
	if typeof(v) != TYPE_DICTIONARY:
		_clear()
		return
	var b := int(v.get("build", 0))
	if b <= base_build or str(v.get("base", "")) != base:
		_clear()                                     # older than this copy, or made for another base
		return
	if FileAccess.file_exists(DIR + "trying"):
		_clear()                                     # it didn't reach the menu last time: start as installed
		return
	var f := FileAccess.open(DIR + "trying", FileAccess.WRITE)
	if f:
		f.store_string(str(b))
		f.close()
	if ProjectSettings.load_resource_pack(pck, true):
		current_build = b
		print("[update] running build %d (installed: %d)" % [b, base_build])
	else:
		_clear()


## The menu is up: whatever started, started fine.
func boot_ok() -> void:
	_remove(DIR + "trying")


## Look for a newer build (once a session). Status comes through status_changed.
func check() -> void:
	if _checked:
		status_changed.emit(status, action)
		return
	_checked = true
	if base_build == 0 and not Config.flag("update_url"):
		_post("Development copy: no updates", "")
		return
	_post("Checking for updates...", "")
	_http = HTTPRequest.new()
	_http.timeout = 15.0
	add_child(_http)
	_http.request_completed.connect(_on_version, CONNECT_ONE_SHOT)
	if _http.request(_url() + "version.json") != OK:
		_cant_check()


func _on_version(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_cant_check()
		return
	var v = JSON.parse_string(body.get_string_from_utf8())
	if typeof(v) != TYPE_DICTIONARY or not v.has("build"):
		_cant_check()
		return
	_remote = v
	var b := int(v.build)
	if b <= current_build:
		_post("Up to date  ·  build %d" % current_build, "")
	elif str(v.get("base", "")) != base:
		_post("New version (build %d) needs a fresh download" % b, "download_page")
	elif _ready_on_disk(b):
		_post("Update ready (build %d)" % b, "restart")
	else:
		_download(b)


func _download(b: int) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	_http.download_file = DIR + "ShotgunRally.pck.part"
	_http.request_completed.connect(_on_pack, CONNECT_ONE_SHOT)
	if _http.request(_url() + "ShotgunRally.pck") != OK:
		_cant_check()
		return
	_downloading = true
	_post("Downloading update (build %d)..." % b, "")


func _process(_dt: float) -> void:
	if _downloading and _http:
		var total := _http.get_body_size()
		if total > 0:
			_post("Downloading update (build %d)... %d%%" % [int(_remote.build), 100 * _http.get_downloaded_bytes() / total], "")


func _on_pack(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	_downloading = false
	var part := DIR + "ShotgunRally.pck.part"
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or not _verify(part):
		_remove(part)
		_post("Update download failed: try again next time", "download_page")
		return
	_remove(DIR + "ShotgunRally.pck")
	DirAccess.rename_absolute(ProjectSettings.globalize_path(part), ProjectSettings.globalize_path(DIR + "ShotgunRally.pck"))
	var f := FileAccess.open(DIR + "version.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(_remote))
	f.close()
	_remove(DIR + "trying")
	_post("Update ready (build %d)" % int(_remote.build), "restart")


## Size and SHA-256 match what version.json says.
func _verify(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	if _remote.has("size") and f.get_length() != int(_remote.size):
		return false
	if not _remote.has("sha256"):
		return true
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	while f.get_position() < f.get_length():
		ctx.update(f.get_buffer(1 << 20))
	return ctx.finish().hex_encode() == str(_remote.sha256).to_lower()


func _ready_on_disk(b: int) -> bool:
	if not FileAccess.file_exists(DIR + "ShotgunRally.pck"):
		return false
	var v = JSON.parse_string(FileAccess.get_file_as_string(DIR + "version.json")) if FileAccess.file_exists(DIR + "version.json") else null
	return typeof(v) == TYPE_DICTIONARY and int(v.get("build", 0)) == b


## Where the files are (tests point it at a local server: --update_url=http://...).
func _url() -> String:
	return Config.arg("update_url", URL)


func _cant_check() -> void:
	_post("Can't check for updates here (the download page is private, or you're offline)", "download_page")


## Start again as the new version.
func restart() -> void:
	OS.set_restart_on_exit(true, OS.get_cmdline_args())   # Godot starts the game again as it quits
	get_tree().quit()


func open_download_page() -> void:
	OS.shell_open(PAGE)


func _post(text: String, act: String) -> void:
	if text != status and not text.contains("%"):
		print("[update] ", text)
	status = text
	action = act
	status_changed.emit(text, act)


func _clear() -> void:
	for n in ["ShotgunRally.pck", "version.json", "trying"]:
		_remove(DIR + n)


func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
