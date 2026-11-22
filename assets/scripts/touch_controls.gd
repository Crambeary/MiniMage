extends CanvasLayer

const SCHEME_SCENES: Dictionary = {
	"locked": "res://assets/scenes/ui/touch/locked_joystick/locked_joystick.tscn",
	"floating": "res://assets/scenes/ui/touch/floating_joystick/floating_joystick.tscn",
	"drag": "res://assets/scenes/ui/touch/drag_area/drag_area.tscn",
}
const SCHEME_LABELS: Dictionary = {"locked": "Locked", "floating": "Floating", "drag": "Drag"}
const DEFAULT_SCHEME: String = "floating"
const DISABLED_SCHEME: String = "off"
const WEB_SCHEME_QUERY: String = "new URLSearchParams(location.search).get('touch') || ''"
const ALWAYS_ON_TOP_LAYER: int = 101
const SWITCHER_MARGIN: float = 8.0
const SWITCHER_SPACING: int = 8
# UI units (see ScreenLayout); at least 0.9 pt each, so 48 units is a ~44 pt thumb target.
const SWITCHER_BUTTON_SIZE: Vector2 = Vector2(88, 48)
const SWITCHER_BUTTON_ALPHA: float = 0.7

var _current_scheme_name: String = ""
var _scheme: Node
var _scheme_buttons: Dictionary = {}
var _switcher: HBoxContainer


func _ready() -> void:
	layer = ALWAYS_ON_TOP_LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	var requested_scheme: String = _requested_scheme_name()
	if not _should_show_touch_controls(requested_scheme):
		return
	_build_switcher()
	set_mode(requested_scheme if requested_scheme in SCHEME_SCENES else DEFAULT_SCHEME)


func set_mode(scheme_name: String) -> void:
	if not SCHEME_SCENES.has(scheme_name) or scheme_name == _current_scheme_name:
		return
	if is_instance_valid(_scheme):
		_scheme.queue_free()
	_scheme = (load(SCHEME_SCENES[scheme_name]) as PackedScene).instantiate()
	add_child(_scheme)
	_current_scheme_name = scheme_name
	for button_scheme_name: String in _scheme_buttons:
		(_scheme_buttons[button_scheme_name] as Button).button_pressed = button_scheme_name == scheme_name


## True when a viewport point lands on a switcher button, so a scheme can leave that touch alone.
func is_switcher_at(viewport_position: Vector2) -> bool:
	return is_instance_valid(_switcher) and _switcher.visible and _switcher.get_global_rect().has_point(viewport_position)


func _requested_scheme_name() -> String:
	if not OS.has_feature("web"):
		return DEFAULT_SCHEME
	var url_choice: Variant = JavaScriptBridge.eval(WEB_SCHEME_QUERY)
	if url_choice is String and not (url_choice as String).is_empty():
		return url_choice
	return DEFAULT_SCHEME


func _should_show_touch_controls(requested_scheme: String) -> bool:
	if requested_scheme == DISABLED_SCHEME:
		return false
	return DisplayServer.is_touchscreen_available() or OS.has_feature("web") or requested_scheme in SCHEME_SCENES


func _build_switcher() -> void:
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE)
	row.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	row.add_theme_constant_override("separation", SWITCHER_SPACING)
	add_child(row)
	_switcher = row
	for scheme_name: String in SCHEME_SCENES:
		var button := Button.new()
		button.text = SCHEME_LABELS[scheme_name]
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = SWITCHER_BUTTON_SIZE
		button.modulate.a = SWITCHER_BUTTON_ALPHA
		button.pressed.connect(set_mode.bind(scheme_name))
		row.add_child(button)
		_scheme_buttons[scheme_name] = button
	ScreenLayout.layout_changed.connect(_place_switcher)
	_place_switcher()


# Keeps the row in the top-right corner of the safe area (clear of a notch or island).
func _place_switcher() -> void:
	var insets: Vector4 = ScreenLayout.get_safe_insets()
	var row_size: Vector2 = _switcher.get_combined_minimum_size()
	_switcher.offset_right = -(insets.z + SWITCHER_MARGIN)
	_switcher.offset_left = _switcher.offset_right - row_size.x
	_switcher.offset_top = insets.y + SWITCHER_MARGIN
	_switcher.offset_bottom = _switcher.offset_top + row_size.y
