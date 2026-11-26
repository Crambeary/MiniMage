extends Control

## E (Light pool): the menu exists only inside one torch pool. A knight waits outside it, in the dark.

const Art = preload("res://assets/scenes/ui/prototype/menu_prototype_art.gd")

var _pool: Sprite2D
var _knight: AnimatedSprite2D
var _mage: AnimatedSprite2D
var _title: Label
var _caption: Label
var _button: Button
var _time := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(Art.fill(Color(0.01, 0.01, 0.02)))
	_knight = Art.animated(Art.KNIGHT, Vector2i(64, 64), 4, 4.0)
	_knight.scale = Vector2(4, 4)
	_knight.modulate = Color(0.16, 0.14, 0.22)
	add_child(_knight)
	_pool = Art.glow(8.5, Color(1.0, 0.62, 0.28, 0.85))
	add_child(_pool)
	_mage = Art.animated(Art.RAISE, Vector2i(32, 32), 8, 8.0)
	_mage.scale = Vector2(3, 3)
	add_child(_mage)
	_caption = Art.title_label("stay in the light", 14)
	_caption.modulate = Color(0.35, 0.18, 0.08)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.size = Vector2(220, 20)
	add_child(_caption)
	_title = Art.title_label("Mini Mage", 36)
	_title.modulate = Color(0.12, 0.07, 0.05)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.size = Vector2(260, 44)
	add_child(_title)
	_button = Art.start_button()
	add_child(_button)
	resized.connect(_layout)
	_layout()


func _process(delta: float) -> void:
	_time += delta
	if _pool:
		var breathe := 8.2 + sin(_time * 1.4) * 0.35
		_pool.scale = Vector2(breathe, breathe)


func _layout() -> void:
	if size.x < 8.0:
		return
	var pool_at := Vector2(size.x * 0.4, size.y * 0.46)
	_pool.position = pool_at
	_caption.position = pool_at + Vector2(-110, -58)
	_title.position = pool_at + Vector2(-130, -34)
	_button.position = pool_at + Vector2(-70, 16)
	_mage.position = pool_at + Vector2(-158, 20)
	_knight.position = Vector2(size.x * 0.84, size.y * 0.62)
