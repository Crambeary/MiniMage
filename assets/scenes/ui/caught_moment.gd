class_name CaughtMoment
extends CanvasLayer
## Short "DETENTION" beat played when a sentry catches the player, just before the
## game-over screen. The world is already frozen (the manager pauses the tree);
## this drains the colour, punches in a title card and plays a low sting.
## A key, click or touch skips it, and the skip finishes only on the matching
## release so the rest of that gesture cannot reach the game-over screen.
## Emits `finished` once, unless the node is freed first.

signal finished

const BELOW_GAME_OVER_LAYER: int = 101
const SHADER: Shader = preload("res://assets/scenes/ui/caught_moment.gdshader")
const STING: AudioStream = preload("res://assets/audio/sfx/boo_1.wav")

const TITLE: String = "DETENTION"
const TITLE_FONT_SIZE: int = 96
const TITLE_MIN_FONT_SIZE: int = 24
## Share of the viewport width the title may take, outline included.
const TITLE_MAX_WIDTH_FRACTION: float = 0.9
const TITLE_OUTLINE_SIZE: int = 12
const DRAIN_SECONDS: float = 0.2
const TITLE_DELAY_SECONDS: float = 0.15
const TITLE_IN_SECONDS: float = 0.25
const TOTAL_SECONDS: float = 2.1
const FADE_OUT_SECONDS: float = 0.25
## A skip waits for the release of its press, but never longer than this.
const MAX_RELEASE_WAIT_MSEC: int = 600

var _done: bool = false
var _skip_pressed_at_msec: int = -1
var _skip_id: String = ""
var _skip_released: bool = false
var _filter: ColorRect
var _title: Label
var _tween: Tween


func _ready() -> void:
	layer = BELOW_GAME_OVER_LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_play()


func _exit_tree() -> void:
	# Freed from outside: stop the tween, emit nothing; the manager cleans up.
	_done = true
	if _tween != null:
		_tween.kill()


func _process(_delta: float) -> void:
	if (
		not _done
		and _skip_pressed_at_msec >= 0
		and Time.get_ticks_msec() - _skip_pressed_at_msec > MAX_RELEASE_WAIT_MSEC
	):
		_finish()


## Ends the moment at once, as if it had run out.
func skip() -> void:
	_finish()


func _input(event: InputEvent) -> void:
	# Touch emulates a mouse click ahead of the touch itself; the touch is the
	# gesture we follow, so swallow the emulated mouse events.
	if event is InputEventMouseButton and event.device == InputEvent.DEVICE_ID_EMULATION:
		get_viewport().set_input_as_handled()
		return
	var id: String = _gesture_id(event)
	if id.is_empty():
		return
	var pressed: bool = _is_press(event)
	if _done:
		_swallow_leftover(id, pressed)
		return
	if pressed:
		get_viewport().set_input_as_handled()
		if _skip_id.is_empty():
			_skip_id = id
			_skip_pressed_at_msec = Time.get_ticks_msec()
	elif id == _skip_id:
		get_viewport().set_input_as_handled()
		_skip_released = true
		_finish()


## After a skip that ended while its gesture was still held, keep eating that
## gesture until its own release so it cannot activate the game-over controls.
func _swallow_leftover(id: String, pressed: bool) -> void:
	if not _skip_id.is_empty() and not _skip_released:
		if id == _skip_id and not pressed:
			get_viewport().set_input_as_handled()
			queue_free()
		elif id == _skip_id:
			get_viewport().set_input_as_handled()
		elif pressed:
			# A new gesture means the old release was lost; stop swallowing.
			queue_free()


static func _gesture_id(event: InputEvent) -> String:
	if event is InputEventKey:
		if event.echo:
			return ""
		return "key:%d:%d" % [event.device, event.physical_keycode]
	if event is InputEventMouseButton:
		return "mouse:%d:%d" % [event.device, event.button_index]
	if event is InputEventScreenTouch:
		return "touch:%d" % event.index
	if event is InputEventJoypadButton:
		return "joy:%d:%d" % [event.device, event.button_index]
	return ""


static func _is_press(event: InputEvent) -> bool:
	return event.is_pressed()


func _build() -> void:
	_filter = ColorRect.new()
	_filter.set_anchors_preset(Control.PRESET_FULL_RECT)
	_filter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = SHADER
	_filter.material = material
	add_child(_filter)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_title = Label.new()
	_title.text = TITLE
	_fit_title()
	get_viewport().size_changed.connect(_fit_title)
	_title.add_theme_color_override("font_color", Color(0.85, 0.08, 0.1))
	_title.add_theme_color_override("font_outline_color", Color(0.05, 0.0, 0.0))
	_title.add_theme_constant_override("outline_size", TITLE_OUTLINE_SIZE)
	_title.modulate.a = 0.0
	_title.resized.connect(_center_pivot)
	center.add_child(_title)

	var sting := AudioStreamPlayer.new()
	sting.stream = STING
	sting.pitch_scale = 0.55
	sting.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(sting)
	sting.play()


## Shrinks the title so it fits a narrow viewport (a phone in portrait).
func _fit_title() -> void:
	var font: Font = _title.get_theme_font("font")
	var width: float = font.get_string_size(TITLE, HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_FONT_SIZE).x
	width += TITLE_OUTLINE_SIZE * 2.0
	var available: float = get_viewport().get_visible_rect().size.x * TITLE_MAX_WIDTH_FRACTION
	var size: int = clampi(
		floori(TITLE_FONT_SIZE * available / width), TITLE_MIN_FONT_SIZE, TITLE_FONT_SIZE
	)
	_title.add_theme_font_size_override("font_size", size)


func _center_pivot() -> void:
	_title.pivot_offset = _title.size * 0.5


func _play() -> void:
	_center_pivot()
	_title.scale = Vector2(1.8, 1.8)
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_method(_set_amount, 0.0, 1.0, DRAIN_SECONDS).set_trans(Tween.TRANS_QUAD)
	_tween.tween_property(_title, "modulate:a", 1.0, TITLE_IN_SECONDS).set_delay(
		TITLE_DELAY_SECONDS
	)
	(
		_tween
		. tween_property(_title, "scale", Vector2.ONE, TITLE_IN_SECONDS)
		. set_delay(TITLE_DELAY_SECONDS)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_OUT)
	)
	_tween.tween_property(_title, "modulate:a", 0.0, FADE_OUT_SECONDS).set_delay(
		TOTAL_SECONDS - FADE_OUT_SECONDS
	)
	_tween.chain().tween_callback(_finish)


func _set_amount(value: float) -> void:
	(_filter.material as ShaderMaterial).set_shader_parameter("amount", value)


func _finish() -> void:
	if _done:
		return
	_done = true
	if _tween != null:
		_tween.kill()
	var held: bool = not _skip_id.is_empty() and not _skip_released
	finished.emit()
	if held:
		# Stay in the tree, invisible, until the skip press is released.
		_title.hide()
	else:
		queue_free()
