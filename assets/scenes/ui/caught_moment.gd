class_name CaughtMoment
extends CanvasLayer
## Short "SPOTTED" beat played when a sentry catches the player, just before the
## game-over screen. Slows time, drains the colour, punches in a title card and
## plays a low sting. Any key, click or touch skips it. Emits `finished` once,
## after restoring the time scale.

signal finished

const BELOW_GAME_OVER_LAYER: int = 101
const SHADER: Shader = preload("res://assets/scenes/ui/caught_moment.gdshader")
const STING: AudioStream = preload("res://assets/audio/sfx/boo_1.wav")

const SLOW_TIME_SCALE: float = 0.15
const SLOW_IN_SECONDS: float = 0.2
const TITLE_DELAY_SECONDS: float = 0.15
const TITLE_IN_SECONDS: float = 0.25
const TOTAL_SECONDS: float = 2.1
const FADE_OUT_SECONDS: float = 0.25

var _done: bool = false
var _filter: ColorRect
var _title: Label
var _tween: Tween


func _ready() -> void:
	layer = BELOW_GAME_OVER_LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_play()


func skip() -> void:
	_finish()


func _input(event: InputEvent) -> void:
	if _done:
		return
	var pressed: bool = (
		(event is InputEventKey and event.pressed and not event.echo)
		or (event is InputEventMouseButton and event.pressed)
		or (event is InputEventScreenTouch and event.pressed)
		or (event is InputEventJoypadButton and event.pressed)
	)
	if pressed:
		get_viewport().set_input_as_handled()
		_finish()


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
	_title.text = "SPOTTED"
	_title.add_theme_font_size_override("font_size", 96)
	_title.add_theme_color_override("font_color", Color(0.85, 0.08, 0.1))
	_title.add_theme_color_override("font_outline_color", Color(0.05, 0.0, 0.0))
	_title.add_theme_constant_override("outline_size", 12)
	_title.modulate.a = 0.0
	_title.resized.connect(_center_pivot)
	center.add_child(_title)

	var sting := AudioStreamPlayer.new()
	sting.stream = STING
	sting.pitch_scale = 0.55
	sting.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(sting)
	sting.play()


func _center_pivot() -> void:
	_title.pivot_offset = _title.size * 0.5


func _play() -> void:
	_center_pivot()
	_title.scale = Vector2(1.8, 1.8)
	# Tweens run on real time so the slow-mo does not stretch the moment itself.
	_tween = create_tween().set_ignore_time_scale(true)
	_tween.set_parallel(true)
	_tween.tween_property(Engine, "time_scale", SLOW_TIME_SCALE, SLOW_IN_SECONDS).set_trans(
		Tween.TRANS_QUAD
	)
	_tween.tween_method(_set_amount, 0.0, 1.0, SLOW_IN_SECONDS).set_trans(Tween.TRANS_QUAD)
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
	Engine.time_scale = 1.0
	finished.emit()
	queue_free()
