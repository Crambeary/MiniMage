extends CanvasLayer
## Autoload that hosts one of three touch-movement schemes and a tiny switcher
## so they can be compared on a phone. Active on touchscreens and in web builds.
## URL override for the web build: ?touch=locked|floating|drag|off

const MODES: Dictionary = {
	"locked": "res://assets/scenes/ui/touch/locked_joystick/locked_joystick.tscn",
	"floating": "res://assets/scenes/ui/touch/floating_joystick/floating_joystick.tscn",
	"drag": "res://assets/scenes/ui/touch/drag_area/drag_area.tscn",
}
const LABELS: Dictionary = {"locked": "Locked", "floating": "Floating", "drag": "Drag"}
const DEFAULT_MODE: String = "floating"

var _mode: String = ""
var _scheme: Node
var _buttons: Dictionary = {}


func _ready() -> void:
	layer = 101
	process_mode = Node.PROCESS_MODE_ALWAYS
	var requested: String = DEFAULT_MODE
	if OS.has_feature("web"):
		var q: Variant = JavaScriptBridge.eval("new URLSearchParams(location.search).get('touch') || ''")
		if q is String and not (q as String).is_empty():
			requested = q
	if requested == "off" or not (DisplayServer.is_touchscreen_available() or OS.has_feature("web") or requested in MODES):
		return
	_build_switcher()
	set_mode(requested if requested in MODES else DEFAULT_MODE)


func set_mode(mode: String) -> void:
	if not MODES.has(mode) or mode == _mode:
		return
	if is_instance_valid(_scheme):
		_scheme.queue_free()  # schemes release their actions on _exit_tree
	_scheme = (load(MODES[mode]) as PackedScene).instantiate()
	add_child(_scheme)
	_mode = mode
	for key: String in _buttons:
		(_buttons[key] as Button).button_pressed = key == mode


func _build_switcher() -> void:
	var box := HBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 8)
	box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	box.add_theme_constant_override("separation", 4)
	add_child(box)
	for key: String in MODES:
		var b := Button.new()
		b.text = LABELS[key]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(72, 36)
		b.modulate.a = 0.7
		b.pressed.connect(set_mode.bind(key))
		box.add_child(b)
		_buttons[key] = b
