extends Node
class_name DiceRoller

## DiceRoller.gd
## Rolls two custom dice to determine total movement points for the turn.
##
## Die A: two faces — 1 and 2  (equal probability)
## Die B: two faces — 2 and 3  (equal probability)
## Total = Die A + Die B  →  possible results: 3, 4, or 5
##
## The total is a pool of movement points spent freely:
##   - Moving any one piece one hex = 1 point
##   - Rotating a piece = 1 point
##   - Move as many different pieces as you like while points remain

signal dice_result(die_a: int, die_b: int, total: int)
signal roll_started()

@export var animate_roll: bool = true
@export var roll_duration: float = 0.8

var _is_rolling: bool = false

func roll() -> void:
	if _is_rolling:
		return
	_is_rolling = true
	roll_started.emit()
	if animate_roll:
		await _animate_roll()
	else:
		_emit_result()

func _animate_roll() -> void:
	var elapsed := 0.0
	var interval := 0.08
	while elapsed < roll_duration:
		await get_tree().create_timer(interval).timeout
		elapsed += interval
		interval = min(interval * 1.15, 0.25)  # Gradual slowdown
	_emit_result()

func _emit_result() -> void:
	var die_a: int = _roll_die_a()
	var die_b: int = _roll_die_b()
	_is_rolling = false
	dice_result.emit(die_a, die_b, die_a + die_b)

## Die A: equal chance of 1 or 2
static func _roll_die_a() -> int:
	return randi_range(1, 2)

## Die B: equal chance of 2 or 3
static func _roll_die_b() -> int:
	return randi_range(2, 3)
