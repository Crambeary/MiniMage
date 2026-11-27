extends Node

## The player's settings: how much world the camera shows, how big the world HUD is,
## and which on-screen touch scheme moves the mage.
##
## Every screen shows the same area of world (DEFAULT_VISIBLE_WORLD_AREA), in portrait
## and landscape alike, so a phone sees as much of a sentry's patrol as a desktop.
## The FOV setting scales that area's width and height by a narrow factor. The HUD
## scale grows the in-world HUD (sentry status bars, detection arrows) without
## changing the world view. TouchControls applies touch_scheme. All of them persist
## in SETTINGS_PATH.

signal changed

## World pixels on screen at FOV 100%: the old 1152x648 desktop framing (384 x 216 world px).
const DEFAULT_VISIBLE_WORLD_AREA: float = 384.0 * 216.0
const TILE_SIZE: float = 16.0
const FOV_MIN: float = 0.85
const FOV_MAX: float = 1.15
const HUD_SCALE_MIN: float = 0.75
const HUD_SCALE_MAX: float = 2.5
const SETTINGS_PATH: String = "user://settings.cfg"
const SECTION: String = "view"
const TOUCH_SECTION: String = "touch"
const SAVE_DELAY_SECONDS: float = 0.5
const READOUT_TOGGLE_KEY: Key = KEY_F3
## Above TouchControls (layer 101), so no touch scheme ever draws over the readout.
const READOUT_LAYER: int = 102
const READOUT_MARGIN: float = 8.0
const READOUT_FONT_SIZE: int = 14

var fov_scale: float = 1.0
var hud_scale: float = 1.0
var debug_readout: bool = false
## The saved touch scheme name, or "" when the player never picked one (TouchControls
## then uses its default).
var touch_scheme: String = ""

var _save_timer: Timer
var _readout_layer: CanvasLayer
var _readout: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load()
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = SAVE_DELAY_SECONDS
	_save_timer.timeout.connect(save)
	add_child(_save_timer)
	_build_readout()


func _process(_delta: float) -> void:
	if _readout_layer.visible:
		_readout.text = _readout_text()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key.pressed and not key.echo and key.keycode == READOUT_TOGGLE_KEY:
		set_debug_readout(not debug_readout)


func set_fov_scale(value: float) -> void:
	value = clampf(value, FOV_MIN, FOV_MAX)
	if is_equal_approx(value, fov_scale):
		return
	fov_scale = value
	_on_setting_changed()


func set_hud_scale(value: float) -> void:
	value = clampf(value, HUD_SCALE_MIN, HUD_SCALE_MAX)
	if is_equal_approx(value, hud_scale):
		return
	hud_scale = value
	_on_setting_changed()


func set_debug_readout(enabled: bool) -> void:
	if enabled == debug_readout:
		return
	debug_readout = enabled
	_readout_layer.visible = enabled
	_on_setting_changed()


func set_touch_scheme(scheme_name: String) -> void:
	if scheme_name == touch_scheme:
		return
	touch_scheme = scheme_name
	_on_setting_changed()


## World pixels the camera should show at this FOV.
func get_visible_world_area() -> float:
	return DEFAULT_VISIBLE_WORLD_AREA * fov_scale * fov_scale


func save() -> void:
	var config := ConfigFile.new()
	config.set_value(SECTION, "fov_scale", fov_scale)
	config.set_value(SECTION, "hud_scale", hud_scale)
	config.set_value(SECTION, "debug_readout", debug_readout)
	if not touch_scheme.is_empty():
		config.set_value(TOUCH_SECTION, "scheme", touch_scheme)
	var error := config.save(SETTINGS_PATH)
	if error != OK:
		push_error("ViewSettings: could not save %s (%s)" % [SETTINGS_PATH, error_string(error)])


func _load() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	fov_scale = clampf(float(config.get_value(SECTION, "fov_scale", 1.0)), FOV_MIN, FOV_MAX)
	hud_scale = clampf(
		float(config.get_value(SECTION, "hud_scale", 1.0)), HUD_SCALE_MIN, HUD_SCALE_MAX
	)
	debug_readout = bool(config.get_value(SECTION, "debug_readout", false))
	touch_scheme = str(config.get_value(TOUCH_SECTION, "scheme", ""))


func _on_setting_changed() -> void:
	changed.emit()
	_save_timer.start()


func _build_readout() -> void:
	_readout_layer = CanvasLayer.new()
	_readout_layer.layer = READOUT_LAYER
	_readout_layer.visible = debug_readout
	add_child(_readout_layer)
	_readout = Label.new()
	_readout.add_theme_font_size_override("font_size", READOUT_FONT_SIZE)
	_readout.add_theme_color_override("font_outline_color", Color.BLACK)
	_readout.add_theme_constant_override("outline_size", 4)
	_readout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_readout_layer.add_child(_readout)
	ScreenLayout.layout_changed.connect(_place_readout)
	_place_readout()


# Top-left corner of the safe area; no other screen element sits there.
func _place_readout() -> void:
	var safe: Rect2 = ScreenLayout.get_safe_rect()
	_readout.position = safe.position + Vector2(READOUT_MARGIN, READOUT_MARGIN)


func _readout_text() -> String:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var orientation: String = "portrait" if viewport_size.y > viewport_size.x else "landscape"
	var lines: PackedStringArray = [
		(
			"%s  viewport %dx%d u  window %dx%d px"
			% [
				orientation,
				viewport_size.x,
				viewport_size.y,
				get_tree().root.size.x,
				get_tree().root.size.y
			]
		),
		(
			"fov %d%%  hud %d%%  touch %s"
			% [
				roundi(fov_scale * 100.0),
				roundi(hud_scale * 100.0),
				TouchControls.get_scheme_name() if TouchControls.get_scheme_name() else "off"
			]
		),
	]
	var camera: Camera2D = get_viewport().get_camera_2d()
	if camera != null and camera.zoom.x > 0.0:
		var world: Vector2 = viewport_size / camera.zoom
		lines.append(
			(
				"world %dx%d px  tiles %.1fx%.1f  zoom %.2f"
				% [world.x, world.y, world.x / TILE_SIZE, world.y / TILE_SIZE, camera.zoom.x]
			)
		)
	return "\n".join(lines)
