extends Control

## D (Spell circle): a ring of magic light. The casting mage and the title sit inside it.

const Art = preload("res://assets/scenes/ui/prototype/menu_prototype_art.gd")

const ORB_COUNT := 12
const RADIUS := 168.0

var _ring: Node2D
var _mage: AnimatedSprite2D
var _title: Label
var _caption: Label
var _button: Button
var _spin := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(Art.fill(Color(0.03, 0.025, 0.07)))
	_ring = Node2D.new()
	add_child(_ring)
	for index in ORB_COUNT:
		var tint := Color(0.45, 0.62, 1.0, 0.55) if index % 2 == 0 else Color(0.75, 0.45, 1.0, 0.4)
		var orb := Art.glow(2.4 if index % 2 == 0 else 1.5, tint)
		var angle := TAU * float(index) / float(ORB_COUNT)
		orb.position = Vector2(cos(angle), sin(angle)) * RADIUS
		_ring.add_child(orb)
	_mage = Art.animated(Art.RAISE, Vector2i(32, 32), 8, 8.0)
	_mage.scale = Vector2(4, 4)
	add_child(_mage)
	_caption = Art.title_label("a quiet spell", 14)
	_caption.modulate = Color(0.7, 0.78, 1.0)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.size = Vector2(240, 22)
	add_child(_caption)
	_title = Art.title_label("Mini Mage", 40)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.size = Vector2(280, 48)
	add_child(_title)
	_button = Art.start_button()
	add_child(_button)
	resized.connect(_layout)
	_layout()


func _process(delta: float) -> void:
	_spin += delta * 0.35
	if _ring:
		_ring.rotation = _spin


func _layout() -> void:
	if size.x < 8.0:
		return
	var center := Vector2(size.x * 0.5, size.y * 0.42)
	_ring.position = center
	_mage.position = center + Vector2(0, 36)
	_caption.position = center + Vector2(-120, -92)
	_title.position = center + Vector2(-140, -68)
	_button.position = center + Vector2(-70, 92)
