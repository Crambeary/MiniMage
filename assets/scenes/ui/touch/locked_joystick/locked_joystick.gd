class_name LockedJoystick
extends CanvasLayer
## Fixed on-screen virtual joystick anchored to the bottom-left corner.
##
## Drives the move_left / move_right / move_up / move_down input actions via
## Input.action_press / action_release with analog strength. Only the finger
## (or mouse) that started on the knob area is followed.

signal vector_changed(v: Vector2)

const MOUSE_POINTER: int = -2
const NO_POINTER: int = -1
## Viewport height the pixel sizes below were designed for (default 1152x648).
const REFERENCE_HEIGHT: float = 648.0

## Base radius in design pixels (scaled with the viewport height).
@export var radius: float = 70.0
## Normalised magnitude (0..1) below which the stick reads as zero.
@export_range(0.0, 0.9, 0.01) var deadzone: float = 0.15
## Hide (and disable) the joystick when the device has no touchscreen.
@export var visible_only_on_touchscreen: bool = false
## Gap between the base and the screen edges, in design pixels.
@export var margin: float = 40.0
## Minimum touch hit radius (design pixels), so the target is >= 120px wide.
@export var min_hit_radius: float = 60.0
@export var action_left: StringName = &"move_left"
@export var action_right: StringName = &"move_right"
@export var action_up: StringName = &"move_up"
@export var action_down: StringName = &"move_down"
@export_group("Colors")
@export var base_color: Color = Color(1, 1, 1, 0.18)
@export var base_border_color: Color = Color(1, 1, 1, 0.4)
@export var knob_color: Color = Color(1, 1, 1, 0.45)
@export var knob_pressed_color: Color = Color(1, 1, 1, 0.7)

var vector: Vector2 = Vector2.ZERO

var _pointer: int = NO_POINTER
var _offset: Vector2 = Vector2.ZERO # knob offset from base centre, in pixels
var _canvas: Control


func _ready() -> void:
	_canvas = $Canvas as Control
	_canvas.draw.connect(_on_canvas_draw)
	get_viewport().size_changed.connect(_canvas.queue_redraw)
	visibility_changed.connect(_on_visibility_changed)
	if visible_only_on_touchscreen and not DisplayServer.is_touchscreen_available():
		visible = false
	_canvas.queue_redraw()


func _exit_tree() -> void:
	_reset()


func _on_visibility_changed() -> void:
	if not visible:
		_reset()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_try_begin(touch.index, touch.position)
		elif touch.index == _pointer:
			_end()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _pointer:
			_update(drag.position)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index != MOUSE_BUTTON_LEFT:
			return
		if button.pressed:
			_try_begin(MOUSE_POINTER, button.position)
		elif _pointer == MOUSE_POINTER:
			_end()
	elif event is InputEventMouseMotion:
		if _pointer == MOUSE_POINTER:
			_update((event as InputEventMouseMotion).position)
			get_viewport().set_input_as_handled()


func _ui_scale() -> float:
	return maxf(get_viewport().get_visible_rect().size.y / REFERENCE_HEIGHT, 0.5)


func _scaled_radius() -> float:
	return radius * _ui_scale()


func _base_center() -> Vector2:
	var size: Vector2 = get_viewport().get_visible_rect().size
	var s: float = _ui_scale()
	return Vector2(margin * s + _scaled_radius(), size.y - margin * s - _scaled_radius())


func _try_begin(pointer: int, pos: Vector2) -> void:
	if _pointer != NO_POINTER:
		return # already following a finger (also ignores emulated mouse echoes)
	var hit_radius: float = maxf(_scaled_radius() * 1.25, min_hit_radius * _ui_scale())
	if pos.distance_to(_base_center()) > hit_radius:
		return
	_pointer = pointer
	_update(pos)
	get_viewport().set_input_as_handled()


func _update(pos: Vector2) -> void:
	var r: float = _scaled_radius()
	_offset = (pos - _base_center()).limit_length(r)
	_apply(_offset / r)
	_canvas.queue_redraw()


func _end() -> void:
	_reset()
	get_viewport().set_input_as_handled()


func _reset() -> void:
	_pointer = NO_POINTER
	_offset = Vector2.ZERO
	_apply(Vector2.ZERO)
	if is_instance_valid(_canvas):
		_canvas.queue_redraw()


## Applies the deadzone, then presses/releases the four move actions.
func _apply(raw: Vector2) -> void:
	var length: float = raw.length()
	var v: Vector2 = Vector2.ZERO
	if length > deadzone:
		v = raw / length * clampf((length - deadzone) / (1.0 - deadzone), 0.0, 1.0)
	_set_axis(action_left, action_right, v.x)
	_set_axis(action_up, action_down, v.y)
	if not v.is_equal_approx(vector):
		vector = v
		vector_changed.emit(vector)


func _set_axis(negative: StringName, positive: StringName, value: float) -> void:
	_set_action(negative, maxf(-value, 0.0))
	_set_action(positive, maxf(value, 0.0))


func _set_action(action: StringName, strength: float) -> void:
	if strength > 0.0:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)


func _on_canvas_draw() -> void:
	var center: Vector2 = _base_center()
	var r: float = _scaled_radius()
	_canvas.draw_circle(center, r, base_color)
	_canvas.draw_arc(center, r, 0.0, TAU, 48, base_border_color, 2.0, true)
	var active: bool = _pointer != NO_POINTER
	_canvas.draw_circle(center + _offset, r * 0.45, knob_pressed_color if active else knob_color)
