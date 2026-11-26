extends Control

## Three variants of the main menu vibe, switchable with left/right or the bottom bar, hosted on MainMenu.
## Throwaway prototype. Debug builds only. Not the production menu.

const VARIANTS: Array[Dictionary] = [
	{"key": "A", "name": "Approach", "script": preload("res://assets/scenes/ui/prototype/variant_approach.gd")},
	{"key": "B", "name": "Notice", "script": preload("res://assets/scenes/ui/prototype/variant_notice.gd")},
	{"key": "C", "name": "Watch", "script": preload("res://assets/scenes/ui/prototype/variant_watch.gd")},
]

var _index := 0
var _current: Control
var _label: Label


func _ready() -> void:
	if not OS.is_debug_build():
		hide()
		return
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	for child in get_parent().get_children():
		if child != self:
			child.queue_free()
	_index = _starting_index()
	resized.connect(_fit_current)
	_show_current()
	_build_bar()
	_report()


func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build() or not visible:
		return
	if _typing():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_LEFT:
			_step(-1)
		elif event.physical_keycode == KEY_RIGHT:
			_step(1)


func _step(delta: int) -> void:
	_index = posmod(_index + delta, VARIANTS.size())
	_show_current()
	_report()


func _show_current() -> void:
	if _current != null:
		_current.queue_free()
		_current = null
	var script: Script = VARIANTS[_index]["script"]
	_current = script.new()
	_current.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_current)
	move_child(_current, 0)
	_fit_current()


func _fit_current() -> void:
	if _current == null or size.x < 8.0:
		return
	_current.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_current.call_deferred("_layout")


func _report() -> void:
	var entry: Dictionary = VARIANTS[_index]
	var state := "variant=%s name=%s" % [entry["key"], entry["name"]]
	print("PROTOTYPE_MENU %s" % state)
	if _label != null:
		_label.text = "%s · %s" % [entry["key"], entry["name"]]


func _starting_index() -> int:
	for arg in OS.get_cmdline_user_args():
		if not str(arg).begins_with("--variant="):
			continue
		var key := str(arg).trim_prefix("--variant=")
		for index in VARIANTS.size():
			if str(VARIANTS[index]["key"]) == key:
				return index
	return 0


func _typing() -> bool:
	var focus := get_viewport().gui_get_focus_owner()
	return focus is LineEdit or focus is TextEdit


func _build_bar() -> void:
	var bar := PanelContainer.new()
	bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bar.offset_left = -150.0
	bar.offset_right = 150.0
	bar.offset_top = -58.0
	bar.offset_bottom = -14.0
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.02, 0.02, 0.94)
	style.border_color = Color(1, 0.82, 0.35)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	bar.add_theme_stylebox_override(&"panel", style)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", 10)
	bar.add_child(row)
	row.add_child(_arrow("◀", -1))
	_label = Label.new()
	_label.custom_minimum_size = Vector2(150, 0)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override(&"font_size", 16)
	row.add_child(_label)
	row.add_child(_arrow("▶", 1))
	add_child(bar)
	_report()


func _arrow(text: String, delta: int) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(36, 28)
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(_step.bind(delta))
	return button
