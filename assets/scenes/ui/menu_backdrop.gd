extends Control

const RAISE := preload("res://assets/art/characters/DG_Asha/Blue Asha Raising 1 32x32.png")
const GLOW := preload("res://assets/art/vfx/2d_64x64_lights_and_shadows_neutral_point_light.png")

const ORB_COUNT := 12
const RADIUS := 168.0

var _ring: Node2D
var _mage: AnimatedSprite2D
var _spin := 0.0


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	_ring = Node2D.new()
	add_child(_ring)
	for index in ORB_COUNT:
		var orb := Sprite2D.new()
		orb.texture = GLOW
		orb.texture_filter = TEXTURE_FILTER_LINEAR
		var wide := index % 2 == 0
		orb.scale = Vector2(2.4, 2.4) if wide else Vector2(1.5, 1.5)
		orb.modulate = Color(0.55, 0.75, 1.2, 0.7) if wide else Color(0.9, 0.5, 1.15, 0.55)
		var material := CanvasItemMaterial.new()
		material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		orb.material = material
		var angle := TAU * float(index) / float(ORB_COUNT)
		orb.position = Vector2(cos(angle), sin(angle)) * RADIUS
		_ring.add_child(orb)
	_mage = AnimatedSprite2D.new()
	_mage.sprite_frames = _raise_frames()
	_mage.texture_filter = TEXTURE_FILTER_NEAREST
	_mage.scale = Vector2(4, 4)
	_mage.play(&"default")
	_mage.frame = 4
	add_child(_mage)
	resized.connect(_layout)
	_layout()


func _process(delta: float) -> void:
	_spin += delta * 0.35
	_ring.rotation = _spin


func _layout() -> void:
	if size.x < 8.0:
		return
	var center := Vector2(size.x * 0.5, size.y * 0.42)
	_ring.position = center
	_mage.position = center + Vector2(0, 36)


func _raise_frames() -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.set_animation_speed(&"default", 8.0)
	frames.set_animation_loop(&"default", true)
	for column in 8:
		var atlas := AtlasTexture.new()
		atlas.atlas = RAISE
		atlas.region = Rect2(column * 32, 0, 32, 32)
		frames.add_frame(&"default", atlas)
	return frames
