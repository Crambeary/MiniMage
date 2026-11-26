extends Control

## A (Approach): open hall. The mage stands on a floor; the title is a corner caption and Start Game is a top-right action.

const Art = preload("res://assets/scenes/ui/prototype/menu_prototype_art.gd")

var _mage: AnimatedSprite2D
var _button: Button


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(Art.fill(Color(0.05, 0.045, 0.09)))
	var floor := Art.tiled(Art.CASTLE, Rect2i(0, 176, 48, 32))
	floor.anchor_left = 0.0
	floor.anchor_right = 1.0
	floor.anchor_top = 1.0
	floor.anchor_bottom = 1.0
	floor.offset_top = -168.0
	floor.offset_bottom = 0.0
	floor.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(floor)
	var caption := Art.title_label("the castle", 14)
	caption.modulate = Color(0.72, 0.66, 0.55)
	caption.position = Vector2(36, 28)
	add_child(caption)
	var title := Art.title_label("Mini Mage", 42)
	title.position = Vector2(36, 48)
	add_child(title)
	_button = Art.start_button()
	add_child(_button)
	_mage = Art.animated(Art.MAGE, Vector2i(32, 32), 8, 6.0)
	_mage.scale = Vector2(5, 5)
	add_child(_mage)
	resized.connect(_layout)
	_layout()


func _layout() -> void:
	if size.x < 8.0:
		return
	_button.position = Vector2(36.0, 108.0)
	_mage.position = Vector2(roundf(size.x * 0.68), size.y - 168.0)
