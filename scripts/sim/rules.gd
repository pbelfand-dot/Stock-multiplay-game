extends RefCounted
## Tunable game rules: money, quotas, items, heat, slots.

const START_FUND := 25_000.0          # start small: flex has to be earned
## Daily overhead (desk rent, Bloomberg, bottle service), paid per trader when
## the bell rings. It creeps up every day like lifestyle inflation does.
const OVERHEAD_PER_TRADER := 2_000.0
const OVERHEAD_GROWTH := 1.35
const DAY_SECONDS := 300.0          # 5-minute trading day (like Broke Street)
const QUOTA_GROWTH := 1.5           # target balance multiplies each day
const PVP_DAYS := 5                 # a PvP match: richest after 5 days wins

const HEAT_MAX := 100.0
const HEAT_DECAY := 0.5             # per second
const HEAT_BIG_WIN := 6.0           # SEC notices trades that return > 100%
const RAID_CHASE_SECONDS := 35.0
const JAIL_SECONDS := 20.0
const ARREST_FINE := 0.15           # of the account balance

const SIZE_STEPS := [1_000.0, 5_000.0, 10_000.0, 25_000.0, 50_000.0, 100_000.0,
	250_000.0, 500_000.0, 1_000_000.0, 5_000_000.0, 10_000_000.0, 50_000_000.0]

const ITEMS := {
	"cigar": {"name": "Victory Cigar", "price": 1_500.0, "heat": 5.0,
		"desc": "Zero trading fees for 60s. Blows a smoke cloud."},
	"powder": {"name": "Nose Candy", "price": 4_000.0, "heat": 25.0,
		"desc": "Sprint x1.6 for 40s and you see headlines 6s early."},
	"tip": {"name": "Insider Tip", "price": 6_000.0, "heat": 40.0,
		"desc": "Reveals what the NEXT headline will do. Very illegal."},
	"moneygun": {"name": "FLEX Gun", "price": 3_000.0, "heat": 0.0,
		"desc": "Hold LMB to make it rain. Cops stop to grab bills."},
	"lawyer": {"name": "Saul Goodmann", "price": 8_000.0, "heat": 0.0,
		"desc": "Your next arrest gets dismissed. It's all good, man."},
	"snitch": {"name": "SEC Snitch Line", "price": 5_000.0, "heat": 0.0,
		"desc": "PvP only: +60 heat on the richest rival.", "pvp_only": true},
}

const ITEM_DURATION := {"cigar": 60.0, "powder": 40.0, "moneygun": 10.0}

## Luxury flex items: permanent, they show up on your desk / wrist. "max" caps how
## many you can own (one watch of each kind, trophies stack up).
## "store" = which street boutique sells it (the office FLEX SHOP sells all).
## "bag" = the desk-trophy prop for handbags. Brands: docs/BRANDS.md (parodies).
const LUXURY := {
	"supreme": {"name": "SUPRÉMO Brick", "price": 6_000.0, "max": 6, "store": "flex",
		"desc": "It's a brick. It says SUPRÉMO. You need it.", "perk": {}, "perk_txt": "Does nothing. That's the point."},
	"counter": {"name": "Cash Counter", "price": 25_000.0, "max": 1, "store": "flex",
		"desc": "Sits on your desk going brrrrt. Press E on it to count a stack.", "perk": {}, "perk_txt": ""},
	"guccero_bag": {"name": "GUCCERO Marmont Bag", "price": 45_000.0, "max": 3, "store": "guccero", "bag": "Bag_Guccero",
		"desc": "Black leather, green-red web stripe. Very Milan. Very mid-cap.", "perk": {"contract_pay": 1.15}, "perk_txt": "Tony respects the bag: contracts pay +15%."},
	"prava_bag": {"name": "PRAVA Nylon Tote", "price": 32_000.0, "max": 3, "store": "prava", "bag": "Bag_Prava",
		"desc": "Minimal. Black. Silver triangle. Costs more than it should.", "perk": {"bp": 0.85}, "perk_txt": "Minimalism calms you: blood pressure rises 15% slower."},
	"louie": {"name": "LOUIS VALMONT Keepall", "price": 60_000.0, "max": 4, "store": "valmont", "bag": "LouieBag",
		"desc": "Tan leather, VM monogram. Empty. Pure flex. Lines up next to your desk.", "perk": {"fee": 0.85}, "perk_txt": "Your broker sees the bag: trading fees -15%."},
	"diorelle_bag": {"name": "DIORÉLLE Saddle Bag", "price": 80_000.0, "max": 3, "store": "diorelle", "bag": "Bag_Diorelle",
		"desc": "Cream couture from Paris. Your desk has never been this classy.", "perk": {"overhead": 0.85}, "perk_txt": "Sponsors cover some of your tab: overhead -15%."},
	"chavel_bag": {"name": "CHAVÉL Quilted Flap", "price": 120_000.0, "max": 3, "store": "chavel", "bag": "Bag_Chavel",
		"desc": "Black quilted leather, gold chain. The old-money flex.", "perk": {"xp": 1.15}, "perk_txt": "Old money teaches you things: +15% XP."},
	"roflex": {"name": "Crownwell Datejust", "price": 250_000.0, "max": 1, "store": "crownwell",
		"desc": "Gold Crownwell Genève on your wrist + the green box on your desk.", "perk": {"heat_decay": 1.3}, "perk_txt": "Cops respect the watch: heat cools 30% faster."},
	"roflex_iced": {"name": "Crownwell Iced Out", "price": 1_500_000.0, "max": 1, "heat": 10.0, "store": "crownwell",
		"desc": "Diamond bezel. Blinding. The SEC notices (+10 heat).", "perk": {"xp": 1.25, "early_news": 2.0}, "perk_txt": "People tell you things: headlines 2s early, +25% XP."},
	# BIG IRON (the gun store): flex you carry. Q draws / swaps / holsters, click
	# fires. rate = seconds between shots, auto = hold to fire, rifle = two hands.
	"pistol": {"name": "G19 Compact", "price": 12_000.0, "max": 1, "store": "iron", "gun": "Gun_Pistol",
		"rate": 0.2, "auto": false, "rifle": false, "big": false, "pellets": 1, "kick": 0.03,
		"desc": "Polymer 9mm. Everybody's first. Fits in the suit.", "perk": {}, "perk_txt": ""},
	"shotgun": {"name": "Pump Shotgun", "price": 22_000.0, "max": 1, "store": "iron", "gun": "Gun_Shotgun",
		"rate": 0.85, "auto": false, "rifle": true, "big": true, "pellets": 8, "kick": 0.09,
		"desc": "12 gauge. Home defense for your Keepall collection.", "perk": {}, "perk_txt": ""},
	"smg": {"name": "Micro SMG", "price": 38_000.0, "max": 1, "store": "iron", "gun": "Gun_SMG",
		"rate": 0.075, "auto": true, "rifle": false, "big": false, "pellets": 1, "kick": 0.012,
		"desc": "Full auto. There is no reason to own this. Buy it.", "perk": {}, "perk_txt": ""},
	"ak": {"name": "AK-47", "price": 55_000.0, "max": 1, "store": "iron", "gun": "Gun_Rifle",
		"rate": 0.11, "auto": true, "rifle": true, "big": true, "pellets": 1, "kick": 0.02,
		"desc": "Wood furniture, curved mag. Every crypto bro's profile picture.", "perk": {}, "perk_txt": ""},
	"deagle": {"name": "Gold Desert Eagle", "price": 90_000.0, "max": 1, "store": "iron", "gun": "Gun_Deagle", "heat": 5.0,
		"rate": 0.45, "auto": false, "rifle": false, "big": true, "pellets": 1, "kick": 0.08,
		"desc": ".50 AE, gold plated, weighs as much as your ego (+5 heat).", "perk": {}, "perk_txt": ""},
	"ak_gold": {"name": "Solid Gold AK", "price": 750_000.0, "max": 1, "store": "iron", "gun": "Gun_RifleGold", "heat": 10.0,
		"rate": 0.11, "auto": true, "rifle": true, "big": true, "pellets": 1, "kick": 0.02,
		"desc": "Gold receiver, black furniture. You're the plug now (+10 heat).", "perk": {}, "perk_txt": ""},
}
## Cars (BEMZE dealership, off the highway). You drive to work every day.
## top = top speed (m/s), zero60 = 0-60 mph seconds, grip = how hard it can
## corner before it slides (1.0 = a good sports car), mass = how much a crash
## shoves it around (tonnes). Game speeds: highway traffic cruises ~29 m/s.
## brand = the maker whose dealership sells it (BEMZE if missing); awd = four-wheel
## drive (the tail doesn't step out under power); ev = electric (car.gd: a quiet
## motor whine instead of the engine, no gear shifts).
const CARS := {
	"beater": {"name": "Used TOROLA Corona", "price": 8_000.0, "model": "TCar_Sedan_Silver", "top": 50.0, "zero60": 7.8, "grip": 0.75, "mass": 1.4,
		"paint": Color(0.7, 0.72, 0.75), "desc": "Pre-owned. 180K miles, one hubcap, check-engine light. It gets you there."},
	"bz_540i": {"name": "BEMZE 540i", "price": 65_000.0, "model": "Bemze_540i", "top": 58.0, "zero60": 4.6, "grip": 0.85, "mass": 1.8,
		"paint": Color(0.1, 0.12, 0.16), "desc": "The executive car. Quiet, fast, looks like money."},
	"bz_m2": {"name": "BEMZE M2", "price": 78_000.0, "model": "RC_M2", "top": 63.0, "zero60": 4.0, "grip": 1.05, "mass": 1.7,
		"paint": Color(0.1, 0.35, 0.75), "desc": "Short, wide, angry. The best cut-up car per dollar."},
	"bz_m3": {"name": "BEMZE M3 Competition", "price": 95_000.0, "model": "RC_M3", "top": 69.0, "zero60": 3.5, "grip": 1.0, "mass": 1.75,
		"paint": Color(0.2, 0.5, 0.2), "desc": "Four doors, 503 hp, zero chill."},
	"bz_m3t": {"name": "BEMZE M3 Touring", "price": 98_000.0, "model": "RC_M3T", "top": 68.0, "zero60": 3.6, "grip": 1.0, "mass": 1.86,
		"paint": Color(0.16, 0.3, 0.52), "desc": "The M3 with a dog box. 503 hp, room for the golf clubs, still zero chill."},
	"bz_m4": {"name": "BEMZE M4 Competition", "price": 105_000.0, "model": "RC_M4", "top": 69.0, "zero60": 3.4, "grip": 1.0, "mass": 1.72,
		"paint": Color(0.85, 0.55, 0.1), "desc": "The coupe. Carbon roof. The grille is a personality."},
	"bz_m5": {"name": "BEMZE M5", "price": 140_000.0, "model": "RC_M5", "top": 74.0, "zero60": 3.3, "grip": 0.92, "mass": 2.4,
		"paint": Color(0.35, 0.36, 0.38), "desc": "717 hp hybrid super-sedan. Heavy. Doesn't care."},
	"bz_m8": {"name": "BEMZE M8 Competition", "price": 165_000.0, "model": "RC_M8", "top": 76.0, "zero60": 3.0, "grip": 0.95, "mass": 1.9,
		"paint": Color(0.55, 0.05, 0.08), "desc": "The flagship GT. Fastest thing on the lot."},
	# the other makers (brand = which dealership sells it: docs/BRANDS.md parodies)
	"mb_g63": {"name": "MERCEDEZ BANZ G63", "brand": "mercedez", "price": 185_000.0, "model": "RC_G63", "awd": true, "top": 62.0, "zero60": 4.3, "grip": 0.78, "mass": 2.56,
		"paint": Color(0.3, 0.32, 0.25), "desc": "A brick with a twin-turbo V8. Tall, heavy, turns like a bank vault. Nobody cares."},
	"mb_gronos": {"name": "MANSORRY GRONOS", "brand": "mercedez", "price": 420_000.0, "model": "RC_GRONOS", "awd": true, "top": 69.0, "zero60": 3.8, "grip": 0.8, "mass": 2.75,
		"paint": Color(0.55, 0.22, 0.1), "desc": "A MERCEDEZ BANZ G the tuner got to: forged carbon, a widebody, 850 hp. Subtle as a brick through a window."},
	"po_911ts": {"name": "PORSHA 911 Turbo S", "brand": "porsha", "price": 230_000.0, "model": "RC_911TS", "awd": true, "top": 91.0, "zero60": 2.5, "grip": 1.12, "mass": 1.64,
		"paint": Color(0.55, 0.56, 0.58), "desc": "640 hp, four-wheel drive, launch control. 0-60 before you finish the word \"launch\"."},
	"po_gt3rs": {"name": "PORSHA 911 GT3 RS", "brand": "porsha", "price": 245_000.0, "model": "RC_GT3RS", "top": 82.0, "zero60": 3.1, "grip": 1.25, "mass": 1.45,
		"paint": Color(0.2, 0.55, 0.3), "desc": "A race car with number plates. 9000 rpm, a wing like a door, the most grip on the road."},
	"au_rs6": {"name": "AUDY RS6 Avant", "brand": "audy", "price": 125_000.0, "model": "RC_RS6", "awd": true, "top": 78.0, "zero60": 3.4, "grip": 0.95, "mass": 2.08,
		"paint": Color(0.45, 0.46, 0.46), "desc": "A 591 hp twin-turbo V8 station wagon. The dog rides in the back at 174 mph."},
	"au_r8": {"name": "AUDY R8 4.2", "brand": "audy", "price": 95_000.0, "model": "RC_R8", "awd": true, "top": 84.0, "zero60": 4.3, "grip": 0.98, "mass": 1.56,
		"paint": Color(0.7, 0.7, 0.72), "desc": "Used, 2007. Mid-engine V8 behind your head, real needles on the dash. The supercar you can afford."},
	"au_etrongt": {"name": "AUDY RS e-tron GT", "brand": "audy", "price": 150_000.0, "model": "RC_ETRONGT", "awd": true, "ev": true, "top": 69.0, "zero60": 3.0, "grip": 1.0, "mass": 2.35,
		"paint": Color(0.16, 0.26, 0.22), "desc": "Electric. 637 hp the instant you touch it, no noise, no gears, no excuses."},
	# not for sale: highway patrol (as fast as anything you can buy: you lose it in traffic, see PURSUIT_BOOST)
	"taxi": {"name": "Yellow Cab", "price": 0.0, "model": "TCar_Taxi", "top": 42.0, "zero60": 8.0, "grip": 0.8, "mass": 1.5,
		"paint": Color(1.0, 0.78, 0.05), "desc": ""},
	"cop": {"name": "Highway Patrol", "price": 0.0, "model": "Cop_Interceptor", "top": 95.0, "zero60": 2.8, "grip": 1.1, "mass": 2.0,
		"paint": Color(0.95, 0.95, 0.95), "desc": ""},
}
## The commute: every morning you wake up at home and drive in; the opening
## bell rings COMMUTE_S later. Some mornings the alarm doesn't go off (more
## often after a high-blood-pressure day): you sleep through LATE_SLEEP of it.
const COMMUTE_S := 165.0       # the 1.8 km drive in takes ~105 s in the sedan, ~70 s cutting up in an M car
const LATE_CHANCE := 0.25
const LATE_BP_BONUS := 0.2         # blood pressure over 60 at the closing bell
const LATE_SLEEP := 75.0        # overslept: ~90 s left for a ~105 s drive. Cut up or be late
## Highway patrol: hold PURSUIT_MPH for a few seconds and a patrol car may
## clock you; lose it (PURSUIT_LOST_M away for PURSUIT_LOST_S) or get pulled over.
const PURSUIT_MPH := 110.0
const PURSUIT_LOST_M := 230.0
const PURSUIT_LOST_S := 6.0
const PURSUIT_BUST_S := 2.5
## The patrol car tops out with the fastest thing you can buy; far behind it
## gets up to PURSUIT_BOOST more power and top speed (none within
## PURSUIT_BOOST_NEAR m, all of it from PURSUIT_BOOST_FAR m) so it can close
## the gap. Traffic still slows it down: that's how you lose it.
const PURSUIT_BOOST := 0.3
const PURSUIT_BOOST_NEAR := 25.0
const PURSUIT_BOOST_FAR := 200.0
const SPEEDING_TICKET := 2_500.0
## A save stores the chosen ride as (index in CAR_ORDER) + 1: only ever append here.
const CAR_ORDER := ["beater", "bz_540i", "bz_m2", "bz_m3", "bz_m4", "bz_m5", "bz_m8", "bz_m3t", "mb_g63", "po_gt3rs", "mb_gronos", "po_911ts", "au_rs6", "au_r8", "au_etrongt"]
## The order the showroom and the phone list them in.
const SHOW_ORDER := ["beater", "bz_540i", "bz_m2", "bz_m3", "bz_m3t", "bz_m4", "bz_m5", "bz_m8", "mb_g63", "mb_gronos", "po_911ts", "po_gt3rs", "au_r8", "au_rs6", "au_etrongt"]
## Factory paint at the dealership (a respray later costs RESPRAY).
const PAINTS := [
	["Alpine White", Color(0.93, 0.93, 0.92)], ["Black Sapphire", Color(0.05, 0.05, 0.07)],
	["Brooklyn Grey", Color(0.52, 0.54, 0.56)], ["Isle Green", Color(0.1, 0.36, 0.26)],
	["Sao Paulo Yellow", Color(0.95, 0.75, 0.1)], ["Portimao Blue", Color(0.1, 0.32, 0.72)],
	["Toronto Red", Color(0.65, 0.06, 0.08)], ["Frozen Deep Grey", Color(0.24, 0.25, 0.27)],
	["Sunset Orange", Color(0.95, 0.42, 0.08)], ["Dravit Grey", Color(0.38, 0.38, 0.34)],
]
const RESPRAY := 2_500.0
## No car yet: the cab stand. It costs, and in rush hour it crawls.
const CAB_FARE := 300.0
const CAB_RIDE_S := 45.0

## Q cycles through the guns you own in this order.
const GUN_ORDER := ["pistol", "shotgun", "smg", "ak", "deagle", "ak_gold"]
const SHOT_HEAT := 3.5              # every shot outside the range
const SHOTS_CALLED_IN := 12.0       # the first shot after a quiet spell: somebody called it in
const SHOTS_QUIET := 10.0
const BOUTIQUES := ["guccero", "valmont", "prava", "crownwell", "diorelle", "chavel", "iron"]
const BOUTIQUE_NAMES := {"guccero": "GUCCERO", "valmont": "LOUIS VALMONT", "prava": "PRAVA MILANO",
	"crownwell": "CROWNWELL GENÈVE", "diorelle": "DIORÉLLE PARIS", "chavel": "CHAVÉL", "flex": "FLEX SHOP",
	"iron": "BIG IRON"}
## Office upgrades (FLEX SHOP counter in the office): bought once, kept
## forever (saved with your career like flex), and they change how you play.
## "prop" = what shows up on your desk.
const UPGRADES := {
	"up_standing": {"name": "Standing Desk Mat", "price": 20_000.0, "prop": "StandingMat", "perk": {"bp": 0.8},
		"desc": "Blood pressure rises 20% slower. Your chiropractor approves."},
	"up_rolodex": {"name": "Tony's Rolodex", "price": 35_000.0, "prop": "Rolodex", "perk": {"contracts": 1},
		"desc": "One more contract from Tony every morning."},
	"up_scanner": {"name": "Police Scanner", "price": 40_000.0, "prop": "PoliceScanner", "perk": {"heat_decay": 1.25, "raid_warn": 1},
		"desc": "Heat cools 25% faster, and you hear it when the cops start asking about you."},
	"up_intern": {"name": "Unpaid Intern", "price": 60_000.0, "prop": "Mug", "perk": {"overhead": 0.8},
		"desc": "Fetches coffee, cuts your overhead 20%. Doesn't get paid (it's \"experience\")."},
	"up_bloomberg": {"name": "Bloomberg Terminal", "price": 90_000.0, "prop": "BloombergTerminal", "perk": {"early_news": 3.0},
		"desc": "Every headline hits your screen 3 seconds before the TV."},
	"up_prime": {"name": "Prime Broker Account", "price": 150_000.0, "prop": "PrimeCard", "perk": {"fee": 0.6, "spread": 0.7},
		"desc": "Fees -40%, spreads -30%. Real-money pricing."},
}

## Perk keys: multipliers (fee, spread, bp, heat_decay, overhead, contract_pay,
## xp), adds (contracts, raid_warn) and early_news (seconds, best one wins).
const PERK_MULTS := ["fee", "spread", "bp", "heat_decay", "overhead", "contract_pay", "xp"]
const PERK_ADDS := ["contracts", "raid_warn"]


## Everything a trader's rank, flex and upgrades give them, combined.
static func perks_for(rank: int, own: Dictionary) -> Dictionary:
	var out := {"early_news": 0.0}
	for k in PERK_MULTS:
		out[k] = 1.0
	for k in PERK_ADDS:
		out[k] = 0
	var srcs: Array = []
	for r in mini(rank + 1, RANKS.size()):
		srcs.append(RANKS[r].get("perk", {}))
	for key in own:
		if int(own[key]) <= 0:
			continue
		if LUXURY.has(key):
			srcs.append(LUXURY[key].get("perk", {}))
		elif UPGRADES.has(key):
			srcs.append(UPGRADES[key].perk)
	for p in srcs:
		for k in p:
			if k in PERK_MULTS:
				out[k] *= float(p[k])
			elif k in PERK_ADDS:
				out[k] += int(p[k])
			elif k == "early_news":
				out[k] = maxf(out[k], float(p[k]))
	return out


## Co-op fund milestones: the first time the fund gets there, everyone gets XP.
const MILESTONES := [100_000.0, 250_000.0, 1_000_000.0, 5_000_000.0, 25_000_000.0, 100_000_000.0]
const MILESTONE_XP := [25.0, 40.0, 75.0, 150.0, 300.0, 600.0]

## Cash on hand: the ATM steps, and what the cops keep as evidence when they
## catch you with it.
const ATM_STEPS := [1_000.0, 5_000.0, 10_000.0, 25_000.0, 50_000.0, 100_000.0, 250_000.0, 1_000_000.0]
const CASH_SEIZED := 0.5

const PAWN_RATE := 0.5          # pawn shop pays half what you paid
const HOTDOG_PRICE := 20.0
const HOTDOG_RELIEF := 35.0     # blood pressure points


## What the desk pays at the end of `day` (all traders together).
static func overhead_for_day(day: int, traders: int) -> float:
	return OVERHEAD_PER_TRADER * maxi(traders, 1) * pow(OVERHEAD_GROWTH, maxi(day - 1, 0))


static func quota_for_day(day: int, start: float = START_FUND) -> float:
	return start * pow(QUOTA_GROWTH, day)


# ---------------- slots ----------------

## Career ranks (persisted by the host per player name). XP comes from green
## days: 1 XP per $1K of profit + 25 for every day the desk makes quota.
const RANKS := [
	{"name": "INTERN", "xp": 0, "unlock": "Welcome to the desk. Get coffee. Lose money.", "perk": {}},
	{"name": "ANALYST", "xp": 60, "unlock": "KWIK LIVE studio access (phone → G) + a 4th contract from Tony every day.",
		"perk": {"contracts": 1}},
	{"name": "TRADER", "xp": 180, "unlock": "Crownwell Datejust (Crownwell Genève) + trading fees -15%.",
		"perk": {"fee": 0.85}},
	{"name": "DEGEN", "xp": 450, "unlock": "x125 leverage + Crownwell Iced Out + contracts pay 1.5x.",
		"perk": {"contract_pay": 1.5}},
	{"name": "WHALE", "xp": 1000, "unlock": "Your name on the TV when you close big + your overhead -25%.",
		"perk": {"overhead": 0.75}},
	{"name": "MARKET MAKER", "xp": 2200, "unlock": "Tramp follows you back + spreads cut in half.",
		"perk": {"spread": 0.5}},
	{"name": "WOLF", "xp": 5000, "unlock": "You are the Wolf of Wall Street. Every headline hits you 3s early.",
		"perk": {"early_news": 3.0}},
]
const XP_PER_1K := 1.0
const XP_QUOTA_DAY := 25.0
## What each rank gates (item/feature -> minimum rank index)
const RANK_GATES := {"studio": 1, "roflex": 2, "lev_125": 3, "roflex_iced": 3, "deagle": 2, "ak_gold": 4}


static func is_gun(key: String) -> bool:
	return LUXURY.has(key) and LUXURY[key].has("gun")


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


# ---- neighborhood (houses) ----
## Magnolia Heights listings (scripts/world/neighborhood_builder.gd places them,
## Match._req_buy_house sells them). Starter homes: a real goal next to the flex
## (a Crownwell is $250K). One owner per house; bought ones are saved with your
## career as owned["house_<id>"]. The spawn by each bed comes from
## assets/props/houses_layout.json (the Blender interiors).
const HOUSES := {
	"tin_a": {"name": "The Tin Roof", "address": "404 Pecan St", "price": 185_000.0,
		"desc": "Two rooms and a porch up on brick piers. Rusty roof, loud window unit, zero HOA. Every mogul starts somewhere."},
	"shotgun_a": {"name": "The Shotgun", "address": "102 Magnolia St", "price": 240_000.0,
		"desc": "Screened porch, ceiling fan, red steps. Front door to back door in one straight line. The floors talk."},
	"ranch_a": {"name": "Starter Ranch", "address": "105 Magnolia St", "price": 320_000.0,
		"desc": "Picture window, brick stoop, white shutters. The house your parents said to buy instead of options."},
	"bungalow_a": {"name": "Craftsman Bungalow", "address": "401 Pecan St", "price": 395_000.0,
		"desc": "Covered porch, wide eaves, good bones, big pine out front. Needs love. Has a laundry room."},
	"ranch_b": {"name": "Corner-Lot Ranch", "address": "113 Magnolia St", "price": 460_000.0,
		"desc": "The corner lot. Updated kitchen, steel fridge, king bed. The whole block will know you made it."},
	"bungalow_b": {"name": "Renovated Bungalow", "address": "410 Pecan St", "price": 620_000.0,
		"desc": "Gut-renovated on a double lot: kitchen island, stainless, a TV you can see from the highway. Top of the block."},
}
# ---- /neighborhood (houses) ----
