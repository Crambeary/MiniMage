class_name TouchDragArea
extends CanvasLayer

signal vector_changed(v: Vector2)
signal tapped(position: Vector2)

const MOUSE_POINTER: int = -1000
const NO_POINTER: int = -1
const MM_PER_INCH: float = 25.4
const FALLBACK_DRAG_FRACTION: float = 0.1
const MIN_RAMP_SPAN: float = 0.001
const CIRCLE_SEGMENTS: int = 48

@export_group("Actions")
@export var action_left: StringName = &"move_left"
@export var action_right: StringName = &"move_right"
@export var action_up: StringName = &"move_up"
@export var action_down: StringName = &"move_down"
@export var compensate_action_deadzone: bool = true

@export_group("Area")
@export var active_area: Rect2 = Rect2(0.0, 0.0, 1.0, 1.0)
@export var visible_only_on_touchscreen: bool = false
@export var accept_mouse: bool = true

@export_group("Feel")
@export_range(4.0, 40.0, 0.5, "suffix:mm") var max_drag_mm: float = 12.0
@export_range(0.01, 0.5, 0.005) var min_drag_fraction: float = 0.04
@export_range(0.01, 0.5, 0.005) var max_drag_fraction: float = 0.2
@export_range(0.0, 0.9, 0.01) var deadzone: float = 0.15
@export_range(0.0, 0.9, 0.01) var hysteresis: float = 0.35
@export var re_anchor: bool = true
@export_range(0.25, 4.0, 0.05) var response_exponent: float = 1.4
@export var response_curve: Curve
@export_range(0.05, 1.0, 0.01, "suffix:s") var tap_max_time: float = 0.25

@export_group("Feedback")
@export var show_feedback: bool = true:
	set(value):
		show_feedback = value
		if is_node_ready():
			_feedback.queue_redraw()
@export var ring_color: Color = Color(1.0, 1.0, 1.0, 0.18)
@export var dot_color: Color = Color(1.0, 1.0, 1.0, 0.35)
@export_range(1.0, 8.0, 0.5) var ring_width: float = 2.0
@export_range(0.05, 0.8, 0.01) var dot_radius_ratio: float = 0.3

var _active_pointer: int = NO_POINTER
var _origin: Vector2 = Vector2.ZERO
var _finger: Vector2 = Vector2.ZERO
var _is_moving: bool = false
var _has_left_deadzone: bool = false
var _press_time_ms: int = 0
var _vector: Vector2 = Vector2.ZERO

@onready var _feedback: Control = $Feedback


func _ready() -> void:
	_feedback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_feedback.draw.connect(_on_feedback_draw)
	visibility_changed.connect(_on_visibility_changed)
	if visible_only_on_touchscreen and not DisplayServer.is_touchscreen_available():
		visible = false


func _exit_tree() -> void:
	_end_drag()


func _notification(what: int) -> void:
	if (
		what
		in [
			NOTIFICATION_PAUSED,
			NOTIFICATION_APPLICATION_FOCUS_OUT,
			NOTIFICATION_APPLICATION_PAUSED,
			NOTIFICATION_WM_WINDOW_FOCUS_OUT
		]
	):
		_end_drag()


# Unhandled, so GUI controls (buttons, menus) get first pick of every touch.
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event
		if touch.pressed:
			_try_begin(touch.index, touch.position)
		elif touch.index == _active_pointer:
			_release(touch.position)
	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event
		if drag.index == _active_pointer:
			_move_finger_to(drag.position)
	elif accept_mouse and event.device != InputEvent.DEVICE_ID_EMULATION:
		if event is InputEventMouseButton:
			var button: InputEventMouseButton = event
			if button.button_index != MOUSE_BUTTON_LEFT:
				return
			if button.pressed:
				_try_begin(MOUSE_POINTER, button.position)
			elif _active_pointer == MOUSE_POINTER:
				_release(button.position)
		elif event is InputEventMouseMotion and _active_pointer == MOUSE_POINTER:
			var motion: InputEventMouseMotion = event
			_move_finger_to(motion.position)


func get_vector() -> Vector2:
	return _vector


func is_dragging() -> bool:
	return _active_pointer != NO_POINTER


func get_max_distance() -> float:
	var viewport: Viewport = get_viewport()
	var viewport_size: Vector2 = viewport.get_visible_rect().size
	var short_side: float = minf(viewport_size.x, viewport_size.y)
	var min_distance: float = short_side * min_drag_fraction
	var max_distance: float = short_side * max_drag_fraction
	var dpi: float = float(DisplayServer.screen_get_dpi())
	if dpi <= 0.0:
		return clampf(short_side * FALLBACK_DRAG_FRACTION, min_distance, max_distance)
	var screen_pixels_per_viewport_pixel: float = viewport.get_final_transform().get_scale().x
	if screen_pixels_per_viewport_pixel <= 0.0:
		screen_pixels_per_viewport_pixel = 1.0
	var distance_px: float = max_drag_mm / MM_PER_INCH * dpi / screen_pixels_per_viewport_pixel
	return clampf(distance_px, min_distance, max_distance)


# active_area is a fraction of the safe rect, so a drag never starts on the home
# indicator or beside a notch.
func _is_in_active_area(screen_position: Vector2) -> bool:
	return ScreenLayout.get_safe_fraction_rect(active_area).has_point(screen_position)


func _release_threshold() -> float:
	return deadzone * (1.0 - hysteresis)


func _try_begin(pointer: int, screen_position: Vector2) -> void:
	if _active_pointer != NO_POINTER or not _is_in_active_area(screen_position):
		return
	_active_pointer = pointer
	_origin = screen_position
	_finger = screen_position
	_is_moving = false
	_has_left_deadzone = false
	_press_time_ms = Time.get_ticks_msec()
	get_viewport().set_input_as_handled()
	_feedback.queue_redraw()


func _move_finger_to(screen_position: Vector2) -> void:
	_finger = screen_position
	var max_distance: float = get_max_distance()
	var drag_offset: Vector2 = _finger - _origin
	var distance: float = drag_offset.length()
	if re_anchor and distance > max_distance:
		_origin = _finger - drag_offset / distance * max_distance
		drag_offset = _finger - _origin
		distance = max_distance

	var drag_fraction: float = minf(distance / max_distance, 1.0)
	var threshold: float = _release_threshold() if _is_moving else deadzone
	_is_moving = drag_fraction > threshold and drag_fraction > 0.0
	_has_left_deadzone = _has_left_deadzone or drag_fraction > deadzone

	var new_vector: Vector2 = Vector2.ZERO
	if _is_moving:
		new_vector = drag_offset / distance * _strength_for(drag_fraction)
	_publish_vector(new_vector)
	get_viewport().set_input_as_handled()
	_feedback.queue_redraw()


# Ramping from the release threshold keeps a finger hovering at the deadzone edge stable.
func _strength_for(drag_fraction: float) -> float:
	var ramp_start: float = _release_threshold()
	var ramp_span: float = maxf(1.0 - ramp_start, MIN_RAMP_SPAN)
	var t: float = clampf((drag_fraction - ramp_start) / ramp_span, 0.0, 1.0)
	var strength: float = response_curve.sample(t) if response_curve else pow(t, response_exponent)
	return clampf(strength, 0.0, 1.0)


func _release(screen_position: Vector2) -> void:
	var held_ms: int = Time.get_ticks_msec() - _press_time_ms
	var was_tap: bool = not _has_left_deadzone and held_ms <= int(tap_max_time * 1000.0)
	get_viewport().set_input_as_handled()
	_end_drag()
	if was_tap:
		tapped.emit(screen_position)


func _end_drag() -> void:
	_active_pointer = NO_POINTER
	_is_moving = false
	_publish_vector(Vector2.ZERO)
	if is_node_ready():
		_feedback.queue_redraw()


func _publish_vector(new_vector: Vector2) -> void:
	if new_vector == _vector:
		return
	_vector = new_vector
	var action_vector: Vector2 = (
		_compensate_input_map_deadzone(new_vector) if compensate_action_deadzone else new_vector
	)
	_drive_action(action_left, maxf(-action_vector.x, 0.0))
	_drive_action(action_right, maxf(action_vector.x, 0.0))
	_drive_action(action_up, maxf(-action_vector.y, 0.0))
	_drive_action(action_down, maxf(action_vector.y, 0.0))
	vector_changed.emit(new_vector)


# Input.get_vector() remaps lengths (deadzone..1) to (0..1);
# pre-invert that so low strengths survive.
func _compensate_input_map_deadzone(vector: Vector2) -> Vector2:
	if vector == Vector2.ZERO:
		return vector
	var action_deadzone: float = _average_action_deadzone()
	return vector / vector.length() * (action_deadzone + vector.length() * (1.0 - action_deadzone))


func _drive_action(action: StringName, strength: float) -> void:
	if not InputMap.has_action(action):
		return
	if strength > 0.0:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)


func _average_action_deadzone() -> float:
	var total: float = 0.0
	var action_count: int = 0
	for action: StringName in [action_left, action_right, action_up, action_down]:
		if InputMap.has_action(action):
			total += InputMap.action_get_deadzone(action)
			action_count += 1
	return total / action_count if action_count > 0 else 0.0


func _on_visibility_changed() -> void:
	if not visible:
		_end_drag()


func _on_feedback_draw() -> void:
	if not show_feedback or _active_pointer == NO_POINTER:
		return
	var max_distance: float = get_max_distance()
	_feedback.draw_arc(
		_origin, max_distance, 0.0, TAU, CIRCLE_SEGMENTS, ring_color, ring_width, true
	)
	var dot_center: Vector2 = _origin + (_finger - _origin).limit_length(max_distance)
	_feedback.draw_circle(dot_center, max_distance * dot_radius_ratio, dot_color)
