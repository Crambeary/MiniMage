class_name FloatingJoystick
extends CanvasLayer
## Floating virtual joystick: the base spawns where the finger first touches
## inside [member activation_area], the knob follows the finger and the base
## fades out on release. Drives the move_* actions through Input.action_press.

## Emitted every time the stick vector changes. Length is 0..1, deadzone applied.
signal vector_changed(v: Vector2)

const ACTION_LEFT: StringName = &"move_left"
const ACTION_RIGHT: StringName = &"move_right"
const ACTION_UP: StringName = &"move_up"
const ACTION_DOWN: StringName = &"move_down"
const MOUSE_POINTER: int = -2
const NO_POINTER: int = -1

## Activation region as a fraction of the viewport (position and size, 0..1).
@export var activation_area: Rect2 = Rect2(0.0, 0.0, 0.6, 1.0)
## Base radius in pixels; the knob is clamped to this distance.
@export_range(20.0, 300.0, 1.0, "suffix:px") var radius: float = 80.0
## Knob radius in pixels.
@export_range(8.0, 150.0, 1.0, "suffix:px") var knob_radius: float = 34.0
## Normalized deadzone below which no input is produced.
@export_range(0.0, 0.9, 0.01) var deadzone: float = 0.15
## If true, dragging beyond the radius drags the base along with the finger.
@export var follow_finger: bool = false
## If true, the joystick is inactive on devices without a touchscreen.
@export var visible_only_on_touchscreen: bool = false
@export var base_color: Color = Color(1.0, 1.0, 1.0, 0.22)
@export var rim_color: Color = Color(1.0, 1.0, 1.0, 0.45)
@export var knob_color: Color = Color(1.0, 1.0, 1.0, 0.6)
@export_range(0.0, 1.0, 0.01, "suffix:s") var fade_time: float = 0.15

var _pointer: int = NO_POINTER
var _center: Vector2 = Vector2.ZERO
var _knob_offset: Vector2 = Vector2.ZERO
var _vector: Vector2 = Vector2.ZERO
var _fade_tween: Tween

@onready var _canvas: Control = $Canvas


func _ready() -> void:
	_canvas.modulate.a = 0.0
	_canvas.visible = false
	_canvas.draw.connect(_on_canvas_draw)
	visibility_changed.connect(_on_visibility_changed)
	if visible_only_on_touchscreen and not DisplayServer.is_touchscreen_available():
		set_process_input(false)
		visible = false


func _exit_tree() -> void:
	_release_all()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event
		if touch.pressed:
			_try_begin(touch.index, touch.position)
		elif touch.index == _pointer:
			_end()
	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event
		if drag.index == _pointer:
			_update(drag.position)
	elif event is InputEventMouseButton and _accept_mouse(event):
		var button: InputEventMouseButton = event
		if button.button_index != MOUSE_BUTTON_LEFT:
			return
		if button.pressed:
			_try_begin(MOUSE_POINTER, button.position)
		elif _pointer == MOUSE_POINTER:
			_end()
	elif event is InputEventMouseMotion and _accept_mouse(event):
		if _pointer == MOUSE_POINTER:
			_update((event as InputEventMouseMotion).position)


## Mouse is only used when it is not a duplicate of an emulated touch.
func _accept_mouse(event: InputEvent) -> bool:
	# Mouse events synthesized from a touch are dispatched before the touch
	# itself; drop them so the real touch index owns the stick.
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		return false
	if ProjectSettings.get_setting("input_devices/pointing/emulate_touch_from_mouse", false):
		return false
	# A real touch already owns the stick; its emulated mouse twin is ignored.
	return _pointer == NO_POINTER or _pointer == MOUSE_POINTER


func _in_activation_area(pos: Vector2) -> bool:
	var size: Vector2 = get_viewport().get_visible_rect().size
	var area := Rect2(activation_area.position * size, activation_area.size * size)
	return area.has_point(pos)


func _try_begin(pointer: int, pos: Vector2) -> void:
	if _pointer != NO_POINTER or not _in_activation_area(pos):
		return
	_pointer = pointer
	_center = pos
	_knob_offset = Vector2.ZERO
	_show_visual()
	_set_vector(Vector2.ZERO)


func _update(pos: Vector2) -> void:
	var delta: Vector2 = pos - _center
	if delta.length() > radius:
		if follow_finger:
			_center = pos - delta.normalized() * radius
		delta = delta.limit_length(radius)
	_knob_offset = delta
	_canvas.queue_redraw()
	var raw: Vector2 = delta / radius
	var length: float = raw.length()
	if length < deadzone:
		_set_vector(Vector2.ZERO)
	else:
		_set_vector(raw.normalized() * ((length - deadzone) / (1.0 - deadzone)))


func _end() -> void:
	_pointer = NO_POINTER
	_knob_offset = Vector2.ZERO
	_release_all()
	_hide_visual()


func _set_vector(v: Vector2) -> void:
	var changed: bool = not v.is_equal_approx(_vector)
	_vector = v
	_drive(ACTION_LEFT, ACTION_RIGHT, v.x)
	_drive(ACTION_UP, ACTION_DOWN, v.y)
	if changed:
		vector_changed.emit(v)


func _drive(negative: StringName, positive: StringName, value: float) -> void:
	if value > 0.0:
		Input.action_release(negative)
		Input.action_press(positive, value)
	elif value < 0.0:
		Input.action_release(positive)
		Input.action_press(negative, -value)
	else:
		Input.action_release(negative)
		Input.action_release(positive)


func _release_all() -> void:
	for action: StringName in [ACTION_LEFT, ACTION_RIGHT, ACTION_UP, ACTION_DOWN]:
		Input.action_release(action)
	if not _vector.is_zero_approx():
		_vector = Vector2.ZERO
		vector_changed.emit(Vector2.ZERO)


func _on_visibility_changed() -> void:
	if not visible and _pointer != NO_POINTER:
		_pointer = NO_POINTER
		_knob_offset = Vector2.ZERO
		_release_all()
		_canvas.visible = false
		_canvas.modulate.a = 0.0


func _show_visual() -> void:
	if _fade_tween:
		_fade_tween.kill()
	_canvas.modulate.a = 1.0
	_canvas.visible = true
	_canvas.queue_redraw()


func _hide_visual() -> void:
	if _fade_tween:
		_fade_tween.kill()
	if not is_inside_tree() or fade_time <= 0.0:
		_canvas.visible = false
		return
	_fade_tween = create_tween()
	_fade_tween.tween_property(_canvas, "modulate:a", 0.0, fade_time)
	_fade_tween.tween_callback(func() -> void: _canvas.visible = false)


func _on_canvas_draw() -> void:
	_canvas.draw_circle(_center, radius, base_color)
	_canvas.draw_arc(_center, radius, 0.0, TAU, 48, rim_color, 3.0, true)
	_canvas.draw_circle(_center + _knob_offset, knob_radius, knob_color)
