extends Control

## C (Watch): split screen. A knight holds the left half. The title and Start Game are a quiet column on the right.

const Art = preload("res://assets/scenes/ui/prototype/menu_prototype_art.gd")

var _knight: AnimatedSprite2D
var _torch: AnimatedSprite2D
var _column: Control


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(Art.fill(Color(0.04, 0.035, 0.07)))
	var alcove := ColorRect.new()
	alcove.color = Color(0.02, 0.018, 0.035)
	alcove.anchor_right = 0.46
	alcove.anchor_bottom = 1.0
	alcove.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(alcove)
	_torch = _torch_sprite()
	add_child(_torch)
	_knight = Art.animated(Art.KNIGHT, Vector2i(64, 64), 4, 5.0)
	_knight.scale = Vector2(5, 5)
	add_child(_knight)
	_column = Control.new()
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_column)
	var title := Art.title_label("Mini Mage", 36)
	title.position = Vector2(0, 0)
	_column.add_child(title)
	var note := Art.title_label("someone is watching", 14)
	note.modulate = Color(0.78, 0.62, 0.5)
	note.position = Vector2(0, 46)
	_column.add_child(note)
	var button := Art.start_button()
	button.position = Vector2(0, 88)
	_column.add_child(button)
	resized.connect(_layout)
	_layout()


func _layout() -> void:
	if size.x < 8.0:
		return
	var split := size.x * 0.46
	_knight.position = Vector2(roundf(split * 0.55), roundf(size.y * 0.58))
	_torch.position = Vector2(roundf(split * 0.22), roundf(size.y * 0.34))
	_column.position = Vector2(split + 48.0, roundf(size.y * 0.34))


func _torch_sprite() -> AnimatedSprite2D:
	var frames := SpriteFrames.new()
	frames.set_animation_speed(&"default", 5.0)
	frames.set_animation_loop(&"default", true)
	for region in [Rect2i(336, 160, 16, 32), Rect2i(352, 160, 16, 32), Rect2i(368, 160, 16, 32), Rect2i(384, 160, 16, 32)]:
		frames.add_frame(&"default", Art.region_texture(Art.CASTLE, region))
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = frames
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.scale = Vector2(4, 4)
	sprite.play(&"default")
	return sprite
