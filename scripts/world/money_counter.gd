extends Node3D
## A bill counter that actually counts your cash (the kit's MoneyCounter /
## MoneyCounterPro / CashCounter + the red CounterDisplay). The stack sits in
## the hopper and flicks through, the stacker fills up, the LCD counts bills,
## the customer display counts dollars. Big money goes through in batches and
## each counted, strapped batch lands on the pile beside the machine: more
## cash, bigger pile.

const CashArt = preload("res://scripts/art/cash_art.gd")
const PropKit = preload("res://scripts/art/prop_kit.gd")
const Rules = preload("res://scripts/sim/rules.gd")

# kit reference points (prop-local, +z = the side facing you)
const HOPPER := Vector3(0, 0.1917, 0.0149)
const HOPPER_TILT := 0.349066          # 20 deg, rising toward the back
const STACKER := Vector3(0, 0.023, 0.09)
const LCD := Vector3(-0.03, 0.1713, 0.0979)
const LED := Vector3(0, 0.049, 0.0145)
const PILE_MAX := 40                   # bricks shown on the pile (the display has the real number)
const BATCHES_MAX := 8                 # a count never takes forever

var kit := "MoneyCounter"
var display_at := Vector3(-0.24, 0, 0.02)   # the customer display beside it ("" = none)
var pile_at := Vector3(0.25, 0, 0.1)        # where counted bricks land
var with_display := true

var lcd: Label3D
var led: Label3D
var hopper: Node3D
var stacker: Node3D
var pile: Node3D
var bills: CPUParticles3D
var counting := false
var _amount := 0.0
var _t := 0.0
var _batch_t := 1.0
var _batches := 1
var _per := 0.0
var _batch_h := 0.02
var _shown_bricks := 0
var _brrt := 0.0
var _clear_t := 0.0


func _ready() -> void:
	if PropKit.has(kit):
		PropKit.place(kit, self)
	else:
		CashArt._box(self, Vector3(0.3, 0.24, 0.28), Vector3.ZERO, Color(0.08, 0.08, 0.09))
	lcd = _label("0", 40, Color(0.55, 0.8, 1.0), 0.0011)
	lcd.position = LCD + Vector3(0, 0.707, 0.707) * 0.0012
	lcd.rotation.x = -PI / 4
	add_child(lcd)
	if with_display:
		var d := Node3D.new()
		d.position = display_at
		d.rotation.y = 0.35
		add_child(d)
		if PropKit.has("CounterDisplay"):
			PropKit.place("CounterDisplay", d)
		else:
			CashArt._box(d, Vector3(0.1, 0.07, 0.07), Vector3.ZERO, Color(0.1, 0.1, 0.1))
		led = _label("$0", 36, Color(1.0, 0.18, 0.12), 0.0008)
		led.position = LED + Vector3(0, 0, 0.0015)
		d.add_child(led)
	hopper = Node3D.new()
	hopper.position = HOPPER
	hopper.rotation.x = HOPPER_TILT
	add_child(hopper)
	stacker = Node3D.new()
	stacker.position = STACKER
	add_child(stacker)
	pile = Node3D.new()
	pile.position = pile_at
	add_child(pile)
	bills = CPUParticles3D.new()
	bills.emitting = false
	bills.amount = 16
	bills.lifetime = 0.18
	var q := QuadMesh.new()
	q.size = Vector2(0.14, 0.06)
	bills.mesh = q
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.6, 0.72, 0.56)
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	bills.material_override = bm
	bills.position = STACKER + Vector3(0, 0.07, -0.02)
	bills.direction = Vector3(0, -1, 0.35)
	bills.spread = 12.0
	bills.initial_velocity_min = 0.3
	bills.initial_velocity_max = 0.5
	bills.gravity = Vector3(0, -3.0, 0)
	bills.angle_min = -8.0
	bills.angle_max = 8.0
	add_child(bills)
	# a loaded hopper at rest
	_set_stack(hopper, 0.012)


func _label(txt: String, size: int, col: Color, px: float) -> Label3D:
	var l := Label3D.new()
	l.text = txt
	l.font_size = size
	l.pixel_size = px
	l.outline_size = 0
	l.modulate = col
	l.shaded = false
	l.double_sided = false
	return l


## Run `amount` dollars through it.
func count(amount: float) -> void:
	_amount = maxf(amount, 100.0)
	var bricks := ceili(_amount / CashArt.BRICK)
	_batches = clampi(bricks, 1, BATCHES_MAX)
	_per = _amount / _batches
	var total := clampf(1.4 + 0.75 * _batches, 1.6, 7.0)
	_batch_t = total / _batches
	_batch_h = clampf(_per / CashArt.BRICK * 0.022, 0.006, 0.05)   # exaggerated: a $10K brick is 1.1 cm
	_t = 0.0
	_shown_bricks = 0
	_clear(pile)
	counting = true
	_clear_t = 0.0
	bills.emitting = true
	Sfx.play("brrt", -2.0)


func _process(delta: float) -> void:
	if not counting:
		if _clear_t > 0.0:
			_clear_t -= delta
			if _clear_t <= 0.0:           # the pile gets put away after a while
				_clear(pile)
				_clear(stacker)
				_set_stack(hopper, 0.012)
				lcd.text = "0"
				if led:
					led.text = "$0"
		return
	_t += delta
	var done := minf(_t / (_batch_t * _batches), 1.0)
	var b := mini(int(_t / _batch_t), _batches - 1)
	var in_batch := clampf((_t - b * _batch_t) / _batch_t, 0.0, 1.0)
	# hopper empties, stacker fills, batch by batch
	_set_stack(hopper, _batch_h * (1.0 - in_batch))
	_set_stack(stacker, _batch_h * in_batch)
	var counted := _amount * done
	lcd.text = str(int(counted / 100.0))
	if led:
		led.text = Rules.money(counted).replace(".00", "")
	# each finished batch lands on the pile as strapped bricks
	var want := mini(int(floor(counted / CashArt.BRICK)), PILE_MAX) if done < 1.0 else mini(ceili(_amount / CashArt.BRICK), PILE_MAX)
	while _shown_bricks < want:
		_add_brick(_shown_bricks)
		_shown_bricks += 1
	_brrt -= delta
	if _brrt <= 0.0:
		_brrt = 0.22
		Sfx.play("brrt", -7.0, randf_range(0.95, 1.1))
	if done >= 1.0:
		counting = false
		bills.emitting = false
		_set_stack(hopper, 0.0)
		lcd.text = str(int(_amount / 100.0))
		if led:
			led.text = Rules.money(_amount).replace(".00", "")
		Sfx.play("cash", -4.0)
		_clear_t = 25.0


## Bricks on the pile: two across, three deep, then up.
func _add_brick(i: int) -> void:
	var layer := i / 6
	var k := i % 6
	var p := Vector3((k % 2 - 0.5) * (CashArt.BILL.y + 0.006), layer * CashArt.BRICK_H, (k / 2 - 1) * (CashArt.BILL.x * 0.5 + 0.004))
	CashArt.brick(pile, p, PI / 2 + randf_range(-0.06, 0.06))


func _set_stack(holder: Node3D, h: float) -> void:
	var s: Node3D = holder.get_node_or_null("Stack")
	if h <= 0.0005:
		if s:
			s.visible = false
		return
	if s == null:
		s = Node3D.new()
		s.name = "Stack"
		holder.add_child(s)
		CashArt.loose(s, Vector3.ZERO, 0.01)
	s.visible = true
	s.scale = Vector3(1, h / 0.01, 1)


func _clear(n: Node3D) -> void:
	for c in n.get_children():
		c.queue_free()
