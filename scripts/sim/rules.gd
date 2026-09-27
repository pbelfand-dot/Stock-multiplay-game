extends RefCounted
## Tunable game rules: money, quotas, items, heat, slots.

const START_FUND := 100_000.0
const DAY_SECONDS := 300.0          # 5-minute trading day (like Broke Street)
const INTERMISSION_SECONDS := 12.0
const QUOTA_GROWTH := 1.5           # target balance multiplies each day
const PVP_DAYS := 3

const HEAT_MAX := 100.0
const HEAT_DECAY := 0.5             # per second
const HEAT_BIG_WIN := 6.0           # SEC notices trades that return > 100%
const RAID_CHASE_SECONDS := 35.0
const JAIL_SECONDS := 20.0
const ARREST_FINE := 0.15           # of the account balance

const SIZE_STEPS := [1_000.0, 5_000.0, 10_000.0, 25_000.0, 50_000.0, 100_000.0,
	250_000.0, 500_000.0, 1_000_000.0, 5_000_000.0, 10_000_000.0, 50_000_000.0]

const ITEMS := {
	"cigar": {"name": "Victory Cigar", "price": 5_000.0, "heat": 5.0,
		"desc": "Zero trading fees for 60s. Blows a smoke cloud."},
	"powder": {"name": "Nose Candy", "price": 15_000.0, "heat": 25.0,
		"desc": "Sprint x1.6 for 40s and you see headlines 6s early."},
	"tip": {"name": "Insider Tip", "price": 25_000.0, "heat": 40.0,
		"desc": "Reveals what the NEXT headline will do. Very illegal."},
	"moneygun": {"name": "FLEX Gun", "price": 10_000.0, "heat": 0.0,
		"desc": "Hold LMB to make it rain. Cops stop to grab bills."},
	"lawyer": {"name": "Saul Goodmann", "price": 30_000.0, "heat": 0.0,
		"desc": "Your next arrest gets dismissed. It's all good, man."},
	"snitch": {"name": "SEC Snitch Line", "price": 20_000.0, "heat": 0.0,
		"desc": "PvP only: +60 heat on the richest rival.", "pvp_only": true},
}

const ITEM_DURATION := {"cigar": 60.0, "powder": 40.0, "moneygun": 10.0}

## Luxury flex items: permanent, they show up on your desk / wrist. "max" caps how
## many you can own (one watch of each kind, trophies stack up).
const LUXURY := {
	"supreme": {"name": "Supreme Brick", "price": 2_500.0, "max": 6,
		"desc": "It's a brick. It says Supreme. You need it."},
	"counter": {"name": "Cash Counter", "price": 8_000.0, "max": 1,
		"desc": "Sits on your desk going brrrrt. Counts nothing. Looks rich."},
	"louie": {"name": "LOUIE BATON Bag", "price": 12_000.0, "max": 4,
		"desc": "Orange bag. Empty. Pure flex. Lines up next to your desk."},
	"roflex": {"name": "ROFLEX Datejust", "price": 35_000.0, "max": 1,
		"desc": "Gold ROFLEX on your wrist + the green box on your desk."},
	"roflex_iced": {"name": "ROFLEX Iced Out", "price": 150_000.0, "max": 1, "heat": 10.0,
		"desc": "Diamond bezel. Blinding. The SEC notices (+10 heat)."},
}


static func quota_for_day(day: int, start: float = START_FUND) -> float:
	return start * pow(QUOTA_GROWTH, day)


# ---------------- slots ----------------

## Career ranks (persisted by the host per player name). XP comes from green
## days: 1 XP per $1K of profit + 25 for every day the desk makes quota.
const RANKS := [
	{"name": "INTERN", "xp": 0, "unlock": "Welcome to the desk. Get coffee. Lose money."},
	{"name": "ANALYST", "xp": 60, "unlock": "KWIK LIVE studio access (phone → G)."},
	{"name": "TRADER", "xp": 180, "unlock": "ROFLEX Datejust at the FLEX SHOP."},
	{"name": "DEGEN", "xp": 450, "unlock": "x125 leverage + ROFLEX Iced Out."},
	{"name": "WHALE", "xp": 1000, "unlock": "Your name on the TV when you close big."},
	{"name": "MARKET MAKER", "xp": 2200, "unlock": "Tramp follows you back."},
	{"name": "WOLF", "xp": 5000, "unlock": "You are the Wolf of Wall Street. Chest thump."},
]
const XP_PER_1K := 1.0
const XP_QUOTA_DAY := 25.0
## What each rank gates (item/feature -> minimum rank index)
const RANK_GATES := {"studio": 1, "roflex": 2, "lev_125": 3, "roflex_iced": 3}


static func rank_of(xp: float) -> int:
	var r := 0
	for i in RANKS.size():
		if xp >= RANKS[i].xp:
			r = i
	return r


static func rank_name(xp: float) -> String:
	return RANKS[rank_of(xp)].name


## Blood pressure (Mark Hanna's lunch prescription): rises while the market is
## open; relieve it in the restroom 2-3 times a trading day or it wrecks you.
const PRESSURE_MAX := 100.0
const PRESSURE_RISE := 100.0 / 120.0       # full in ~2 min of trading
const PRESSURE_RED := 50.0                 # screen starts going red
const PRESSURE_WOBBLY := 70.0              # camera sway, slower legs
const PRESSURE_FAT_FINGER := 85.0          # orders come out the wrong size
const RELIEF_SECONDS := 4.0
const RELIEF_LINES := ["Prescription filled.", "Twice a day, minimum.", "Keep the blood flowing.",
	"Rookie numbers? Not today.", "Rhythm below the belt: restored.", "Balance restored. Differential intact."]

const SLOT_SYMBOLS := ["CHERRY", "CLOVER", "BELL", "DIAMOND", "SEVEN"]
const SLOT_WEIGHTS := [5, 4, 3, 2, 1]
const SLOT_TRIPLE_PAY := {"CHERRY": 5, "CLOVER": 8, "BELL": 12, "DIAMOND": 25, "SEVEN": 60}
const SLOT_TWO_CHERRY_PAY := 2
const SLOT_BETS := [100.0, 300.0, 1_000.0, 5_000.0, 25_000.0, 100_000.0]


static func slot_reel(rng: RandomNumberGenerator) -> int:
	var total := 0
	for w in SLOT_WEIGHTS:
		total += w
	var r := rng.randi() % total
	for i in SLOT_WEIGHTS.size():
		r -= SLOT_WEIGHTS[i]
		if r < 0:
			return i
	return 0


## Returns payout multiplier for three reel indices.
static func slot_multiplier(reels: Array) -> int:
	if reels[0] == reels[1] and reels[1] == reels[2]:
		return SLOT_TRIPLE_PAY[SLOT_SYMBOLS[reels[0]]]
	var cherries := 0
	for r in reels:
		if SLOT_SYMBOLS[r] == "CHERRY":
			cherries += 1
	if cherries == 2:
		return SLOT_TWO_CHERRY_PAY
	return 0


static func money(v: float) -> String:
	var neg := v < 0
	var a := absf(v)
	var s: String
	if a >= 1_000_000_000.0:
		s = "%.2fB" % (a / 1_000_000_000.0)
	elif a >= 1_000_000.0:
		s = "%.2fM" % (a / 1_000_000.0)
	elif a >= 10_000.0:
		s = "%.2fK" % (a / 1_000.0)
	else:
		s = _commas(int(round(a)))
	return ("-$" if neg else "$") + s


static func _commas(n: int) -> String:
	var ws := str(n)
	var out := ""
	for i in ws.length():
		out += ws[i]
		var rem := ws.length() - 1 - i
		if rem > 0 and rem % 3 == 0:
			out += ","
	return out


static func price_str(p: float) -> String:
	if p < 10.0:
		return "%.4f" % p
	var whole := int(floor(p))
	var frac := int(round((p - whole) * 100.0))
	if frac == 100:
		whole += 1
		frac = 0
	return "%s.%02d" % [_commas(whole), frac]
