extends SceneTree
## The garage, the money and story mode, without driving (a throwaway save):
##   * stage credits: more for a longer stage, for beating the pace, for a clean
##     run, x1.5 in story mode; never negative
##   * buying: not with too little money; then it's yours and the money's gone;
##     not twice; upgrades step up to 3 and change the car's numbers
##   * the car setup: the paint you chose, its own livery free, the drive split
##   * the championship: rally 2 opens when rally 1 is finished; the standings
##     put a quick crew first and a slow one last; prizes by position
##   * the free cars: the rally car and the STROMER 4 owned from the start (an older save gets them)
##   * the save survives a reload
## Run: godot --headless --path . -s tests/story_check.gd -- --profile=/tmp/some.cfg (a save it may wipe)
## Prints [story] lines; exits 1 on any FAIL.

const Profile = preload("res://scripts/game/profile.gd")
const Catalog = preload("res://scripts/game/catalog.gd")
const Championship = preload("res://scripts/game/championship.gd")

var fails := 0


func _initialize() -> void:
	Profile.reset()
	# credits
	var slow := Profile.stage_credits({"total": 300.0, "penalties": 10.0}, 2600.0)
	var quick := Profile.stage_credits({"total": 130.0, "penalties": 0.0}, 2600.0)
	var story := Profile.stage_credits({"total": 130.0, "penalties": 0.0}, 2600.0, true)
	var longer := Profile.stage_credits({"total": 300.0, "penalties": 10.0}, 3600.0)
	fails += _check(slow.total > 0 and slow.pace == 0 and slow.clean == 0, "a slow stage with a penalty still pays %d" % slow.total)
	fails += _check(quick.total > slow.total and quick.pace > 0 and quick.clean > 0, "a quick clean one pays more: %d" % quick.total)
	fails += _check(story.total == int(quick.total * 1.5), "story mode pays x1.5: %d" % story.total)
	fails += _check(longer.total > slow.total, "a longer stage pays more: %d" % longer.total)
	# the free cars: the rally car and the STROMER 4 are yours from the start
	fails += _check("kestrel" in Profile.owned.cars and "stromer" in Profile.owned.cars, "a new save owns the rally car and the STROMER 4")
	Profile.select_car("stromer")
	fails += _check(Profile.car == "stromer", "the STROMER 4 can be driven without buying it")
	Profile.select_car("kestrel")
	# buying
	var comet := Catalog.car("comet")
	fails += _check(not Profile.buy("cars", "comet", comet.price) and Profile.credits == 0, "can't buy the Comet with 0 CR")
	Profile.earn(20000)
	fails += _check(Profile.buy("cars", "comet", comet.price) and Profile.credits == 20000 - comet.price, "bought the Comet: %d CR left" % Profile.credits)
	fails += _check(not Profile.buy("cars", "comet", comet.price), "can't buy it twice")
	Profile.select_car("comet")
	var before := Profile.setup()
	fails += _check(before.livery == "comet" and before.wheels == "gold" and Profile.owns("liveries", "comet"), "it comes in its own livery (free) and gold wheels")
	fails += _check(not Profile.upgrade("comet", "engine") or Profile.level("comet", "engine") < 3, "upgrades need the money too")
	Profile.earn(20000)
	for k in 3:
		Profile.upgrade("comet", "engine")
	fails += _check(Profile.level("comet", "engine") == 3 and not Profile.upgrade("comet", "engine"), "the engine upgrades three steps, no more")
	var after := Profile.setup()
	fails += _check(is_equal_approx(after.power, comet.power * 1.12), "and it's 12 %% stronger (%.3f)" % after.power)
	Profile.set_paint("comet", "number", 42)
	Profile.set_paint("comet", "colours", [Color.BLACK, Color.WHITE, Color.RED, Color.GOLD])
	var painted := Profile.setup()
	fails += _check(painted.number == 42 and painted.colours[0] == Color.BLACK, "paint and number stick")
	fails += _check(is_equal_approx(Catalog.setup("martello").drive_front, 0.15), "the Martello sends most of its power to the back")
	# the championship
	var rallies := Championship.RALLIES
	fails += _check(Profile.rally_open(0, rallies) and not Profile.rally_open(1, rallies), "only the first rally is open")
	var lengths := [2000.0, 2000.0, 2000.0]
	var fast: Array = []
	var crawl: Array = []
	for j in 3:
		fast.append(Championship.rival_time(0, j, 0, lengths[j]) * 0.95)
		crawl.append(Championship.rival_time(0, j, 4, lengths[j]) * 1.2)
	var win := Championship.position(Championship.standings(0, fast, lengths))
	var last := Championship.position(Championship.standings(0, crawl, lengths))
	fails += _check(win == 1 and last == 6, "standings: quicker than everyone is 1st, slower than everyone 6th (%d, %d)" % [win, last])
	fails += _check(Championship.reward(0, 1) > Championship.reward(0, 2) and Championship.reward(0, 6) > 0, "prizes by position")
	Profile.finish_rally("pine", 2, 400.0)
	fails += _check(Profile.rally_open(1, rallies) and not Profile.rally_open(2, rallies), "finishing it opens the second")
	Profile.finish_rally("pine", 1, 390.0)
	fails += _check(Profile.rally_record("pine").best_pos == 1 and is_equal_approx(Profile.rally_record("pine").best_total, 390.0), "the best result is kept")
	var o := Championship.stage_opts(3, 1)
	fails += _check(o.mode == "story" and o.gen.puddles > 1.0 and o.mood == "overcast" and o.seed == 4401, "a Mud & Mist stage brings its puddles, fog and seed")
	# the save survives a reload (Profile reads the file named by --profile, else user://profile.cfg:
	# this test saved into that one, so read it back from there)
	var keep := Profile.credits
	Profile._loaded = false
	Profile.credits = -1
	Profile.ensure_loaded()
	fails += _check(Profile.credits == keep and Profile.car == "comet" and "comet" in Profile.owned.cars, "it all reloads from the save")
	# a save from before the STROMER 4 was free gets it on load
	var cf := ConfigFile.new()
	cf.load(Profile.path())
	cf.set_value("garage", "owned", {"cars": ["kestrel", "comet"], "liveries": [], "wheels": ["silver"]})
	cf.save(Profile.path())
	Profile._loaded = false
	Profile.ensure_loaded()
	fails += _check("stromer" in Profile.owned.cars and "comet" in Profile.owned.cars, "an older save gets the STROMER 4 too (and keeps what it had)")
	print("[story] %s" % ("STORY OK" if fails == 0 else "STORY FAIL"))
	quit(1 if fails > 0 else 0)


func _check(ok: bool, msg: String) -> int:
	print("[story] %s %s" % ["ok  " if ok else "FAIL", msg])
	return 0 if ok else 1
