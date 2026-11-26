extends Control

const CASTLE := preload("res://assets/art/tilesets/CastleTiles.png")
const IDLE := preload("res://assets/art/characters/DG_Asha/Blue Asha Idle 32x32.png")

const TORCH_REGIONS: Array[Rect2] = [
	Rect2(336, 160, 16, 32),
	Rect2(352, 160, 16, 32),
	Rect2(368, 160, 16, 32),
	Rect2(384, 160, 16, 32),
]
const GLOW_REGION := Rect2(176, 192, 80, 80)
const EMBER_REGION := Rect2(214, 228, 2, 2)

const TORCH_SCALE := 4.0
const MAGE_SCALE := 4.0
const EMBER_COUNT := 22

var _torches: Array[Node2D] = []
var _glows: Array[Sprite2D] = []
var _mage: AnimatedSprite2D
var _embers: Array[Dictionary] = []
var _time := 0.0
var _embers_seeded := false


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	_build_torches()
	_build_mage()
	_build_embers()
	resized.connect(_layout)
	_layout()


func _process(delta: float) -> void:
	_time += delta
	var bounds := size
	if bounds.x < 8.0:
		return
	var bob := int(sin(_time * 1.7) * 2.0)
	_mage.position = Vector2(roundf(bounds.x * 0.5), bounds.y - 78.0 + float(bob))
	for i in _glows.size():
		_glows[i].modulate.a = 0.16 + 0.12 * (0.5 + 0.5 * sin(_time * 2.6 + float(i) * 1.7))
	for ember: Dictionary in _embers:
		var sprite := ember["sprite"] as Sprite2D
		var y := float(ember["y"]) - delta * float(ember["speed"])
		var x := float(ember["x"]) + sin(_time * float(ember["sway"]) + float(ember["phase"])) * 8.0
		if y < -8.0:
			var spot := _ember_spot(bounds)
			y = bounds.y + 8.0
			ember["x"] = spot.x
			x = spot.x
		ember["y"] = y
		sprite.position = Vector2(roundf(x), roundf(y))
		sprite.modulate.a = float(ember["alpha"]) * (0.55 + 0.45 * sin(_time * float(ember["flicker"]) + float(ember["phase"])))


func _build_torches() -> void:
	var frames := _frames(CASTLE, TORCH_REGIONS, 5.0)
	for index in 2:
		var root := Node2D.new()
		var glow := Sprite2D.new()
		glow.texture = _atlas(CASTLE, GLOW_REGION)
		glow.texture_filter = TEXTURE_FILTER_NEAREST
		glow.scale = Vector2(2.25, 2.25)
		glow.modulate = Color(1, 0.72, 0.42, 0.2)
		root.add_child(glow)
		var flame := AnimatedSprite2D.new()
		flame.sprite_frames = frames
		flame.texture_filter = TEXTURE_FILTER_NEAREST
		flame.scale = Vector2(TORCH_SCALE, TORCH_SCALE)
		flame.play(&"default")
		flame.frame = index * 2
		root.add_child(flame)
		add_child(root)
		_torches.append(root)
		_glows.append(glow)


func _build_mage() -> void:
	var regions: Array[Rect2] = []
	for column in 8:
		regions.append(Rect2(column * 32, 0, 32, 32))
	_mage = AnimatedSprite2D.new()
	_mage.sprite_frames = _frames(IDLE, regions, 6.0)
	_mage.texture_filter = TEXTURE_FILTER_NEAREST
	_mage.scale = Vector2(MAGE_SCALE, MAGE_SCALE)
	_mage.play(&"default")
	add_child(_mage)


func _build_embers() -> void:
	var texture := _atlas(CASTLE, EMBER_REGION)
	for index in EMBER_COUNT:
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.texture_filter = TEXTURE_FILTER_NEAREST
		var pixel_scale := 4.0 if index % 3 == 0 else 3.0
		sprite.scale = Vector2(pixel_scale, pixel_scale)
		sprite.modulate = Color(1.0, 0.62, 0.28, 0.7)
		add_child(sprite)
		_embers.append({
			"sprite": sprite,
			"x": 0.0,
			"y": 0.0,
			"speed": randf_range(16.0, 38.0),
			"sway": randf_range(0.5, 1.3),
			"flicker": randf_range(2.0, 5.0),
			"phase": randf() * TAU,
			"alpha": randf_range(0.4, 0.9),
		})


func _layout() -> void:
	var bounds := size
	if bounds.x < 8.0 or _torches.size() < 2:
		return
	_torches[0].position = Vector2(roundf(bounds.x * 0.16), roundf(bounds.y * 0.30))
	_torches[1].position = Vector2(roundf(bounds.x * 0.84), roundf(bounds.y * 0.30))
	_mage.position = Vector2(roundf(bounds.x * 0.5), bounds.y - 78.0)
	if _embers_seeded:
		return
	_embers_seeded = true
	for ember: Dictionary in _embers:
		var spot := _ember_spot(bounds)
		ember["x"] = spot.x
		ember["y"] = spot.y


func _ember_spot(bounds: Vector2) -> Vector2:
	if randf() < 0.5:
		return Vector2(randf_range(20.0, bounds.x * 0.30), randf_range(16.0, bounds.y - 16.0))
	return Vector2(
		randf_range(bounds.x * 0.70, maxf(bounds.x - 20.0, bounds.x * 0.70)),
		randf_range(72.0, bounds.y - 16.0)
	)


func _frames(atlas: Texture2D, regions: Array[Rect2], speed: float) -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.set_animation_speed(&"default", speed)
	frames.set_animation_loop(&"default", true)
	for region in regions:
		frames.add_frame(&"default", _atlas(atlas, region))
	return frames


func _atlas(atlas: Texture2D, region: Rect2) -> AtlasTexture:
	var texture := AtlasTexture.new()
	texture.atlas = atlas
	texture.region = region
	return texture
