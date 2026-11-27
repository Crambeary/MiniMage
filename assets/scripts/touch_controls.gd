extends CanvasLayer

## Shows the on-screen touch scheme that moves the mage.
##
## The player picks the scheme in Settings; the choice lives in ViewSettings.touch_scheme
## and persists with the other settings. On the web, `?touch=<scheme>` (or `?touch=off`)
## overrides the saved choice for that page load.

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

var _current_scheme_name: String = ""
var _scheme: Node
var _suspended: bool = false


func _ready() -> void:
	layer = ALWAYS_ON_TOP_LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	var requested_scheme: String = _requested_scheme_name()
	if not _should_show_touch_controls(requested_scheme):
		return
	_show_scheme(requested_scheme if requested_scheme in SCHEME_SCENES else DEFAULT_SCHEME)


## Switches to a scheme ("locked", "floating", "drag") and saves it as the player's choice.
## Does nothing while touch controls are off.
func set_mode(scheme_name: String) -> void:
	if not SCHEME_SCENES.has(scheme_name) or _current_scheme_name.is_empty():
		return
	ViewSettings.set_touch_scheme(scheme_name)
	_show_scheme(scheme_name)


## The scheme in use ("locked", "floating", "drag"), or "" when touch controls are off.
func get_scheme_name() -> String:
	return _current_scheme_name


## The active scheme node (a LockedJoystick, FloatingJoystick or DragArea), or null.
func get_scheme() -> Node:
	return _scheme if is_instance_valid(_scheme) else null


## Hides the scheme and stops it taking input, e.g. while a settings screen needs
## every touch for its own sliders.
func set_suspended(suspended: bool) -> void:
	_suspended = suspended
	process_mode = Node.PROCESS_MODE_DISABLED if suspended else Node.PROCESS_MODE_ALWAYS
	visible = not suspended
	_apply_suspended_to_scheme()


func _show_scheme(scheme_name: String) -> void:
	if scheme_name == _current_scheme_name:
		return
	if is_instance_valid(_scheme):
		_scheme.queue_free()
	_scheme = (load(SCHEME_SCENES[scheme_name]) as PackedScene).instantiate()
	add_child(_scheme)
	_current_scheme_name = scheme_name
	_apply_suspended_to_scheme()


# A scheme is its own CanvasLayer, which does not inherit this layer's visibility.
func _apply_suspended_to_scheme() -> void:
	if is_instance_valid(_scheme) and _scheme is CanvasLayer:
		(_scheme as CanvasLayer).visible = not _suspended


func _requested_scheme_name() -> String:
	if OS.has_feature("web"):
		var url_choice: Variant = JavaScriptBridge.eval(WEB_SCHEME_QUERY)
		if url_choice is String and not (url_choice as String).is_empty():
			return url_choice
	if ViewSettings.touch_scheme in SCHEME_SCENES:
		return ViewSettings.touch_scheme
	return DEFAULT_SCHEME


func _should_show_touch_controls(requested_scheme: String) -> bool:
	if requested_scheme == DISABLED_SCHEME:
		return false
	return (
		DisplayServer.is_touchscreen_available()
		or OS.has_feature("web")
		or requested_scheme in SCHEME_SCENES
	)
