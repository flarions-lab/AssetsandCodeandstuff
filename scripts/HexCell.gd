extends Area2D
class_name HexCell

## HexCell.gd
## Represents a single hexagonal tile on the board.

signal cell_clicked(cell: HexCell)

var coord: Vector2i = Vector2i.ZERO

@onready var polygon: Polygon2D = $Polygon2D
@onready var collision: CollisionPolygon2D = $CollisionPolygon2D

const HEX_SIZE := 40.0

func _ready() -> void:
	var verts = _make_hex_verts(HEX_SIZE)
	polygon.polygon = verts
	collision.polygon = verts
	input_event.connect(_on_input_event)

func _make_hex_verts(size: float) -> PackedVector2Array:
	## Pointy-top hexagon — matches HexHighlight orientation (+30° offset)
	var verts := PackedVector2Array()
	for i in 6:
		var angle_deg = 60.0 * i + 30.0
		var angle_rad = deg_to_rad(angle_deg)
		verts.append(Vector2(size * cos(angle_rad), size * sin(angle_rad)))
	return verts

func _on_input_event(_viewport, event: InputEvent, _shape_idx) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		cell_clicked.emit(self)
