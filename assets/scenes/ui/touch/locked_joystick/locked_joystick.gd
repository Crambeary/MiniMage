class_name LockedJoystick
extends CanvasLayer

signal vector_changed(v: Vector2)

const MOUSE_POINTER: int = -2
const NO_POINTER: int = -1
const GRAB_RADIUS_FACTOR: float = 1.25
const KNOB_RADIUS_FACTOR: float = 0.45
const BASE_BORDER_WIDTH: float = 2.0
const CIRCLE_SEGMENTS: int = 48

@export var radius: float = 70.0
@export_range(0.0, 0.9, 0.01) var deadzone: float = 0.15
@export var visible_only_on_touchscreen: bool = false
@export var margin: float = 40.0
@export var min_grab_radius: float = 60.0
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

var _active_pointer: int = NO_POINTER
var _knob_offset_px: Vector2 = Vector2.ZERO
var _canvas: Control


func _ready() -> void:
	_canvas = $Canvas as Control
	_canvas.draw.connect(_on_canvas_draw)
	ScreenLayout.layout_changed.connect(_canvas.queue_redraw)
	visibility_changed.connect(_on_visibility_changed)
	if visible_only_on_touchscreen and not DisplayServer.is_touchscreen_available():
		visible = false
	_canvas.queue_redraw()


func _exit_tree() -> void:
	_release_stick()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_try_grab(touch.index, touch.position)
		elif touch.index == _active_pointer:
			_release_and_consume()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _active_pointer:
			_move_knob_to(drag.position)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index != MOUSE_BUTTON_LEFT:
			return
		if button.pressed:
			_try_grab(MOUSE_POINTER, button.position)
		elif _active_pointer == MOUSE_POINTER:
			_release_and_consume()
	elif event is InputEventMouseMotion:
		if _active_pointer == MOUSE_POINTER:
			_move_knob_to((event as InputEventMouseMotion).position)
			get_viewport().set_input_as_handled()


func _is_held() -> bool:
	return _active_pointer != NO_POINTER


## The stick's centre in viewport units. Sizes are UI units; ScreenLayout scales them to
## the screen. The stick sits in the bottom-left corner of the safe area so it clears a
## notch and the home indicator.
func get_base_center() -> Vector2:
	var safe: Rect2 = ScreenLayout.get_safe_rect()
	var inset: float = margin + radius
	return Vector2(safe.position.x + inset, safe.end.y - inset)


func _grab_radius() -> float:
	return maxf(radius * GRAB_RADIUS_FACTOR, min_grab_radius)


func _try_grab(pointer: int, screen_position: Vector2) -> void:
	if _is_held():
		return
	if screen_position.distance_to(get_base_center()) > _grab_radius():
		return
	_active_pointer = pointer
	_move_knob_to(screen_position)
	get_viewport().set_input_as_handled()


func _move_knob_to(position: Vector2) -> void:
	_knob_offset_px = (position - get_base_center()).limit_length(radius)
	_publish_vector(_knob_offset_px / radius)
	_canvas.queue_redraw()


func _release_and_consume() -> void:
	_release_stick()
	get_viewport().set_input_as_handled()


func _release_stick() -> void:
	_active_pointer = NO_POINTER
	_knob_offset_px = Vector2.ZERO
	_publish_vector(Vector2.ZERO)
	if is_instance_valid(_canvas):
		_canvas.queue_redraw()


func _publish_vector(raw: Vector2) -> void:
	var new_vector: Vector2 = _apply_deadzone(raw)
	_drive_axis(action_left, action_right, new_vector.x)
	_drive_axis(action_up, action_down, new_vector.y)
	if not new_vector.is_equal_approx(vector):
		vector = new_vector
		vector_changed.emit(vector)


func _apply_deadzone(raw: Vector2) -> Vector2:
	var length: float = raw.length()
	if length <= deadzone:
		return Vector2.ZERO
	var rescaled_length: float = clampf((length - deadzone) / (1.0 - deadzone), 0.0, 1.0)
	return raw / length * rescaled_length


func _drive_axis(negative_action: StringName, positive_action: StringName, value: float) -> void:
	_drive_action(negative_action, maxf(-value, 0.0))
	_drive_action(positive_action, maxf(value, 0.0))


func _drive_action(action: StringName, strength: float) -> void:
	if strength > 0.0:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)


func _on_visibility_changed() -> void:
	if not visible:
		_release_stick()


func _on_canvas_draw() -> void:
	var center: Vector2 = get_base_center()
	_canvas.draw_circle(center, radius, base_color)
	_canvas.draw_arc(
		center, radius, 0.0, TAU, CIRCLE_SEGMENTS, base_border_color, BASE_BORDER_WIDTH, true
	)
	var current_knob_color: Color = knob_pressed_color if _is_held() else knob_color
	_canvas.draw_circle(center + _knob_offset_px, radius * KNOB_RADIUS_FACTOR, current_knob_color)
