class_name FloatingJoystick
extends CanvasLayer

signal vector_changed(v: Vector2)

const ACTION_LEFT: StringName = &"move_left"
const ACTION_RIGHT: StringName = &"move_right"
const ACTION_UP: StringName = &"move_up"
const ACTION_DOWN: StringName = &"move_down"
const MOVE_ACTIONS: Array[StringName] = [ACTION_LEFT, ACTION_RIGHT, ACTION_UP, ACTION_DOWN]
const MOUSE_POINTER: int = -2
const NO_POINTER: int = -1
const EMULATE_TOUCH_SETTING: String = "input_devices/pointing/emulate_touch_from_mouse"
const RIM_WIDTH: float = 3.0
const CIRCLE_SEGMENTS: int = 48

@export var activation_area: Rect2 = Rect2(0.0, 0.0, 0.6, 1.0)
@export_range(20.0, 300.0, 1.0, "suffix:px") var radius: float = 80.0
@export_range(8.0, 150.0, 1.0, "suffix:px") var knob_radius: float = 34.0
@export_range(0.0, 0.9, 0.01) var deadzone: float = 0.15
@export var base_follows_finger: bool = false
@export var visible_only_on_touchscreen: bool = false
@export var base_color: Color = Color(1.0, 1.0, 1.0, 0.22)
@export var rim_color: Color = Color(1.0, 1.0, 1.0, 0.45)
@export var knob_color: Color = Color(1.0, 1.0, 1.0, 0.6)
@export_range(0.0, 1.0, 0.01, "suffix:s") var fade_time: float = 0.15

var _active_pointer: int = NO_POINTER
var _base_center: Vector2 = Vector2.ZERO
var _knob_offset: Vector2 = Vector2.ZERO
var _vector: Vector2 = Vector2.ZERO
var _fade_tween: Tween

@onready var _canvas: Control = $Canvas


func _ready() -> void:
	_hide_canvas()
	_canvas.draw.connect(_on_canvas_draw)
	visibility_changed.connect(_on_visibility_changed)
	if visible_only_on_touchscreen and not DisplayServer.is_touchscreen_available():
		set_process_input(false)
		visible = false


func _exit_tree() -> void:
	_release_actions()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event
		if touch.pressed:
			_try_begin(touch.index, touch.position)
		elif touch.index == _active_pointer:
			_end()
	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event
		if drag.index == _active_pointer:
			_move_finger_to(drag.position)
	elif event is InputEventMouseButton and _is_genuine_mouse(event):
		var button: InputEventMouseButton = event
		if button.button_index != MOUSE_BUTTON_LEFT:
			return
		if button.pressed:
			_try_begin(MOUSE_POINTER, button.position)
		elif _active_pointer == MOUSE_POINTER:
			_end()
	elif event is InputEventMouseMotion and _is_genuine_mouse(event):
		if _active_pointer == MOUSE_POINTER:
			_move_finger_to((event as InputEventMouseMotion).position)


func _is_genuine_mouse(event: InputEvent) -> bool:
	# Godot dispatches a touch's emulated mouse event before the touch itself.
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		return false
	if ProjectSettings.get_setting(EMULATE_TOUCH_SETTING, false):
		return false
	return _active_pointer == NO_POINTER or _active_pointer == MOUSE_POINTER


func _is_in_activation_area(screen_position: Vector2) -> bool:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var area_in_pixels := Rect2(activation_area.position * viewport_size, activation_area.size * viewport_size)
	return area_in_pixels.has_point(screen_position)


func _try_begin(pointer: int, screen_position: Vector2) -> void:
	if _active_pointer != NO_POINTER or not _is_in_activation_area(screen_position):
		return
	_active_pointer = pointer
	_base_center = screen_position
	_knob_offset = Vector2.ZERO
	_show_canvas()
	_set_vector(Vector2.ZERO)


func _move_finger_to(screen_position: Vector2) -> void:
	var finger_offset: Vector2 = screen_position - _base_center
	if base_follows_finger and finger_offset.length() > radius:
		_base_center = screen_position - finger_offset.normalized() * radius
	_knob_offset = finger_offset.limit_length(radius)
	_canvas.queue_redraw()
	_set_vector(_apply_deadzone(_knob_offset / radius))


func _apply_deadzone(raw: Vector2) -> Vector2:
	var length: float = raw.length()
	if length < deadzone:
		return Vector2.ZERO
	return raw.normalized() * ((length - deadzone) / (1.0 - deadzone))


func _end() -> void:
	_active_pointer = NO_POINTER
	_knob_offset = Vector2.ZERO
	_release_actions()
	_fade_out_canvas()


func _set_vector(new_vector: Vector2) -> void:
	var changed: bool = not new_vector.is_equal_approx(_vector)
	_vector = new_vector
	_drive_axis(ACTION_LEFT, ACTION_RIGHT, new_vector.x)
	_drive_axis(ACTION_UP, ACTION_DOWN, new_vector.y)
	if changed:
		vector_changed.emit(new_vector)


func _drive_axis(negative_action: StringName, positive_action: StringName, value: float) -> void:
	if value > 0.0:
		Input.action_release(negative_action)
		Input.action_press(positive_action, value)
	elif value < 0.0:
		Input.action_release(positive_action)
		Input.action_press(negative_action, -value)
	else:
		Input.action_release(negative_action)
		Input.action_release(positive_action)


func _release_actions() -> void:
	for action: StringName in MOVE_ACTIONS:
		Input.action_release(action)
	if not _vector.is_zero_approx():
		_vector = Vector2.ZERO
		vector_changed.emit(Vector2.ZERO)


func _on_visibility_changed() -> void:
	if not visible and _active_pointer != NO_POINTER:
		_active_pointer = NO_POINTER
		_knob_offset = Vector2.ZERO
		_release_actions()
		_hide_canvas()


func _show_canvas() -> void:
	_kill_fade()
	_canvas.modulate.a = 1.0
	_canvas.visible = true
	_canvas.queue_redraw()


func _hide_canvas() -> void:
	_canvas.modulate.a = 0.0
	_canvas.visible = false


func _fade_out_canvas() -> void:
	_kill_fade()
	if not is_inside_tree() or fade_time <= 0.0:
		_canvas.visible = false
		return
	_fade_tween = create_tween()
	_fade_tween.tween_property(_canvas, "modulate:a", 0.0, fade_time)
	_fade_tween.tween_callback(func() -> void: _canvas.visible = false)


func _kill_fade() -> void:
	if _fade_tween:
		_fade_tween.kill()


func _on_canvas_draw() -> void:
	_canvas.draw_circle(_base_center, radius, base_color)
	_canvas.draw_arc(_base_center, radius, 0.0, TAU, CIRCLE_SEGMENTS, rim_color, RIM_WIDTH, true)
	_canvas.draw_circle(_base_center + _knob_offset, knob_radius, knob_color)
