extends Control

## F (Firefly path): motes lead from the mage, low and left, up to the title. The button is a step on that path.

const Art = preload("res://assets/scenes/ui/prototype/menu_prototype_art.gd")

const MOTE_COUNT := 14

var _motes: Array[Sprite2D] = []
var _mage: AnimatedSprite2D
var _title: Label
var _button: Button
var _time := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(Art.fill(Color(0.02, 0.03, 0.06)))
	for index in MOTE_COUNT:
		var warm := index % 3 != 0
		var tint := Color(1.0, 0.72, 0.35, 0.8) if warm else Color(0.55, 0.75, 1.0, 0.75)
		var mote := Art.glow(0.7 if warm else 0.95, tint)
		add_child(mote)
		_motes.append(mote)
	_mage = Art.animated(Art.MAGE, Vector2i(32, 32), 8, 6.0)
	_mage.scale = Vector2(4, 4)
	add_child(_mage)
	_title = Art.title_label("Mini Mage", 36)
	add_child(_title)
	_button = Art.start_button()
	add_child(_button)
	resized.connect(_layout)
	_layout()


func _process(delta: float) -> void:
	_time += delta
	if size.x < 8.0:
		return
	for index in _motes.size():
		var spot := _spot(float(index) / float(MOTE_COUNT - 1))
		var bob := sin(_time * 1.6 + float(index)) * 6.0
		_motes[index].position = spot + Vector2(0, bob)


func _layout() -> void:
	if size.x < 8.0:
		return
	_mage.position = _spot(0.0) + Vector2(-36, 8)
	var title_at := _spot(1.0)
	_title.position = title_at + Vector2(-20, -28)
	var step := _spot(0.48)
	_button.position = step + Vector2(36, 16)
	for index in _motes.size():
		_motes[index].position = _spot(float(index) / float(MOTE_COUNT - 1))


func _spot(t: float) -> Vector2:
	var start := Vector2(size.x * 0.24, size.y * 0.74)
	var finish := Vector2(size.x * 0.58, size.y * 0.2)
	var point := start.lerp(finish, t)
	point.x += sin(t * PI) * 70.0
	return point
