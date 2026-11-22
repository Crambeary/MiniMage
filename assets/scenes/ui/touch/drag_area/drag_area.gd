class_name TouchDragArea
extends CanvasLayer

## Invisible "drag anywhere" joystick for touchscreens.
##
## The point where a finger lands inside [member active_area] becomes the stick
## origin. Dragging away from it produces an analog direction which is fed into
## the movement actions through [method Input.action_press], so anything that
## reads [code]Input.get_vector("move_left", "move_right", "move_up", "move_down")[/code]
## just works.
##
## Input routing: events are read in [method _unhandled_input], so every GUI
## Control (pause button, menus, ...) gets first pick and a touch that lands on a
## button never starts a drag. The feedback Control uses MOUSE_FILTER_IGNORE so
## it never takes part in GUI picking and can never swallow a touch itself.
## Mouse events are accepted for desktop testing; touch-emulated mouse events are
## ignored so a single finger is never seen twice.

## Emitted whenever the produced movement vector changes (length 0..1, y down).
signal vector_changed(v: Vector2)
## Emitted when a touch was released quickly without ever leaving the deadzone.
signal tapped(position: Vector2)

const MOUSE_POINTER: int = -1000
const NO_POINTER: int = -1
const MM_PER_INCH: float = 25.4

@export_group("Actions")
@export var action_left: StringName = &"move_left"
@export var action_right: StringName = &"move_right"
@export var action_up: StringName = &"move_up"
@export var action_down: StringName = &"move_down"
## Pre-scale strengths so the actions' own InputMap deadzone (which
## Input.get_vector applies again) does not eat the low end of the analog range.
@export var compensate_action_deadzone: bool = true

@export_group("Area")
## Region that accepts a touch-down, as fractions of the viewport (0..1).
## Default is the whole screen. A drag that started inside may leave it.
@export var active_area: Rect2 = Rect2(0.0, 0.0, 1.0, 1.0)
## Hide (and ignore all input) on devices without a touchscreen.
@export var visible_only_on_touchscreen: bool = false
## Accept left-mouse drags (desktop testing). Touch-emulated mouse is ignored.
@export var accept_mouse: bool = true

@export_group("Feel")
## Drag distance for full strength, in millimetres on the physical screen.
## 12 mm (a ~2.4 cm wide virtual stick) suits a thumb on a ~6" phone.
@export_range(4.0, 40.0, 0.5, "suffix:mm") var max_drag_mm: float = 12.0
## Limits for the computed distance as a fraction of the viewport's short side,
## guarding against bogus DPI reports and tiny/huge windows.
@export_range(0.01, 0.5, 0.005) var min_drag_fraction: float = 0.04
@export_range(0.01, 0.5, 0.005) var max_drag_fraction: float = 0.2
## Fraction of the max distance that produces no movement.
@export_range(0.0, 0.9, 0.01) var deadzone: float = 0.15
## Once moving, the finger must come back inside deadzone * (1 - hysteresis)
## before movement stops, so jitter around the threshold doesn't flicker.
@export_range(0.0, 0.9, 0.01) var hysteresis: float = 0.35
## When the finger drags past the max distance, drag the origin along behind
## it so reversing direction responds immediately.
@export var re_anchor: bool = true
## Analog ramp exponent: 1 = linear, >1 = finer control near the centre.
@export_range(0.25, 4.0, 0.05) var response_exponent: float = 1.4
## Optional response curve (x: normalised drag 0..1 -> y: strength 0..1).
## Overrides response_exponent when set.
@export var response_curve: Curve
## Releases shorter than this that never left the deadzone emit [signal tapped].
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
## Dot radius as a fraction of the max drag distance.
@export_range(0.05, 0.8, 0.01) var dot_radius_ratio: float = 0.3

var _pointer: int = NO_POINTER
var _origin: Vector2 = Vector2.ZERO
var _finger: Vector2 = Vector2.ZERO
var _engaged: bool = false
var _left_deadzone: bool = false
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
	if what in [NOTIFICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT,
			NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_WINDOW_FOCUS_OUT]:
		_end_drag()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event
		if touch.pressed:
			_try_begin(touch.index, touch.position)
		elif touch.index == _pointer:
			_release(touch.position)
	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event
		if drag.index == _pointer:
			_move(drag.position)
	elif accept_mouse and event.device != InputEvent.DEVICE_ID_EMULATION:
		if event is InputEventMouseButton:
			var button: InputEventMouseButton = event
			if button.button_index != MOUSE_BUTTON_LEFT:
				return
			if button.pressed:
				_try_begin(MOUSE_POINTER, button.position)
			elif _pointer == MOUSE_POINTER:
				_release(button.position)
		elif event is InputEventMouseMotion and _pointer == MOUSE_POINTER:
			var motion: InputEventMouseMotion = event
			_move(motion.position)


## Current movement vector (length 0..1).
func get_vector() -> Vector2:
	return _vector


## True while a finger (or mouse) is being tracked.
func is_dragging() -> bool:
	return _pointer != NO_POINTER


## Maximum drag distance in viewport pixels for the current screen.
func get_max_distance() -> float:
	var viewport: Viewport = get_viewport()
	var view_size: Vector2 = viewport.get_visible_rect().size
	var short_side: float = minf(view_size.x, view_size.y)
	var dpi: float = float(DisplayServer.screen_get_dpi())
	# Physical px -> viewport px (differs from 1 once a stretch mode is used).
	var stretch: float = viewport.get_final_transform().get_scale().x
	if stretch <= 0.0:
		stretch = 1.0
	var px: float = max_drag_mm / MM_PER_INCH * dpi / stretch
	if dpi <= 0.0:
		px = short_side * 0.1
	return clampf(px, short_side * min_drag_fraction, short_side * max_drag_fraction)


func _try_begin(pointer: int, pos: Vector2) -> void:
	if _pointer != NO_POINTER:
		return # Only follow the first finger.
	var rect_size: Vector2 = get_viewport().get_visible_rect().size
	var area := Rect2(active_area.position * rect_size, active_area.size * rect_size)
	if not area.has_point(pos):
		return
	_pointer = pointer
	_origin = pos
	_finger = pos
	_engaged = false
	_left_deadzone = false
	_press_time_ms = Time.get_ticks_msec()
	get_viewport().set_input_as_handled()
	_feedback.queue_redraw()


func _move(pos: Vector2) -> void:
	_finger = pos
	var max_distance: float = get_max_distance()
	var drag_offset: Vector2 = _finger - _origin
	var distance: float = drag_offset.length()
	if re_anchor and distance > max_distance:
		_origin = _finger - drag_offset / distance * max_distance
		drag_offset = _finger - _origin
		distance = max_distance

	var normalized: float = minf(distance / max_distance, 1.0)
	var threshold: float = deadzone * (1.0 - hysteresis) if _engaged else deadzone
	_engaged = normalized > threshold and normalized > 0.0
	if normalized > deadzone:
		_left_deadzone = true

	var v: Vector2 = Vector2.ZERO
	if _engaged:
		# Ramp from the release threshold so a finger hovering just inside the
		# deadzone keeps a small, stable output instead of toggling to zero.
		var low: float = deadzone * (1.0 - hysteresis)
		var t: float = clampf((normalized - low) / maxf(1.0 - low, 0.001), 0.0, 1.0)
		var strength: float = response_curve.sample(t) if response_curve else pow(t, response_exponent)
		v = drag_offset / distance * clampf(strength, 0.0, 1.0)
	_apply_vector(v)
	get_viewport().set_input_as_handled()
	_feedback.queue_redraw()


func _release(pos: Vector2) -> void:
	var was_tap: bool = not _left_deadzone \
			and Time.get_ticks_msec() - _press_time_ms <= int(tap_max_time * 1000.0)
	get_viewport().set_input_as_handled()
	_end_drag()
	if was_tap:
		tapped.emit(pos)


func _end_drag() -> void:
	_pointer = NO_POINTER
	_engaged = false
	_apply_vector(Vector2.ZERO)
	if is_node_ready():
		_feedback.queue_redraw()


func _apply_vector(v: Vector2) -> void:
	if v == _vector:
		return
	_vector = v
	var out: Vector2 = v
	if compensate_action_deadzone and v != Vector2.ZERO:
		# Input.get_vector() remaps length (dz..1) -> (0..1); invert that here.
		var dz: float = _actions_deadzone()
		out = v / v.length() * (dz + v.length() * (1.0 - dz))
	_set_action(action_left, maxf(-out.x, 0.0))
	_set_action(action_right, maxf(out.x, 0.0))
	_set_action(action_up, maxf(-out.y, 0.0))
	_set_action(action_down, maxf(out.y, 0.0))
	vector_changed.emit(v)


func _set_action(action: StringName, strength: float) -> void:
	if not InputMap.has_action(action):
		return
	if strength > 0.0:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)


func _actions_deadzone() -> float:
	var total: float = 0.0
	var count: int = 0
	for action: StringName in [action_left, action_right, action_up, action_down]:
		if InputMap.has_action(action):
			total += InputMap.action_get_deadzone(action)
			count += 1
	return total / count if count > 0 else 0.0


func _on_visibility_changed() -> void:
	if not visible:
		_end_drag()


func _on_feedback_draw() -> void:
	if not show_feedback or _pointer == NO_POINTER:
		return
	var max_distance: float = get_max_distance()
	_feedback.draw_arc(_origin, max_distance, 0.0, TAU, 48, ring_color, ring_width, true)
	var knob: Vector2 = _origin + (_finger - _origin).limit_length(max_distance)
	_feedback.draw_circle(knob, max_distance * dot_radius_ratio, dot_color)
