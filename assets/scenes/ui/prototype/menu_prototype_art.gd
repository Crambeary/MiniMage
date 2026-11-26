extends RefCounted

## Throwaway art cuts for the main-menu vibe prototype. Not production UI.

const CASTLE := "res://assets/art/tilesets/CastleTiles.png"
const MAGE := "res://assets/art/characters/DG_Asha/Blue Asha Idle 32x32.png"
const RAISE := "res://assets/art/characters/DG_Asha/Blue Asha Raising 1 32x32.png"
const KNIGHT := "res://assets/art/characters/Knight/Idle-Sheet.png"
const GLOW := "res://assets/art/vfx/2d_64x64_lights_and_shadows_neutral_point_light.png"

static var _images: Dictionary = {}


static func image(path: String) -> Image:
	if _images.has(path):
		return _images[path]
	var texture := load(path) as Texture2D
	var loaded: Image = texture.get_image() if texture != null else null
	if loaded == null:
		loaded = Image.new()
		loaded.load(path)
	_images[path] = loaded
	return loaded


static func region_texture(path: String, region: Rect2i) -> ImageTexture:
	return ImageTexture.create_from_image(image(path).get_region(region))


static func animated(path: String, frame: Vector2i, count: int, speed: float) -> AnimatedSprite2D:
	var frames := SpriteFrames.new()
	frames.set_animation_speed(&"default", speed)
	frames.set_animation_loop(&"default", true)
	for index in count:
		var region := Rect2i(index * frame.x, 0, frame.x, frame.y)
		frames.add_frame(&"default", region_texture(path, region))
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = frames
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.play(&"default")
	return sprite


static func tiled(path: String, region: Rect2i) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = region_texture(path, region)
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	rect.stretch_mode = TextureRect.STRETCH_TILE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


static func sprite(path: String, region: Rect2i, scale: float) -> Sprite2D:
	var node := Sprite2D.new()
	node.texture = region_texture(path, region)
	node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	node.scale = Vector2(scale, scale)
	return node


static func glow(scale: float, tint: Color) -> Sprite2D:
	var node := Sprite2D.new()
	node.texture = load(GLOW)
	node.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	node.scale = Vector2(scale, scale)
	node.modulate = tint
	var material := CanvasItemMaterial.new()
	material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	node.material = material
	return node


static func fill(color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = color
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


static func title_label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


static func start_button() -> Button:
	var button := Button.new()
	button.text = "Start Game"
	button.custom_minimum_size = Vector2(140, 36)
	button.button_up.connect(func() -> void:
		button.get_tree().change_scene_to_file("res://assets/scenes/levels/main.tscn")
	)
	return button
