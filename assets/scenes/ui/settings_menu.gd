extends Node

## View settings over a live, frozen copy of level 1.
##
## The level runs its _ready and _process (so the camera, status bars and sprites
## are real) but no physics, so nothing moves, detects or ends the game. The
## sliders change ViewSettings, and the level's own CameraFit and HUD redraw at
## once, so the screen behind the panel is exactly what play will look like.
## The touch row switches TouchControls' scheme at once; the scheme itself stays
## hidden here so it never takes a slider touch, and shows again in the level.

const MAIN_MENU_SCENE: String = "res://assets/scenes/ui/MainMenu.tscn"
const PREVIEW_LEVEL_SCENE: PackedScene = preload("res://assets/scenes/levels/main.tscn")
const DETECTION_ARROW_SCENE: PackedScene = preload("res://assets/scenes/ui/detection_arrow.tscn")
## How strongly the sample arrow shows, so its size and colour match a real detection.
const SAMPLE_DETECTION_LEVEL: float = 0.8
const PANEL_MARGIN: float = 8.0
const PANEL_MAX_WIDTH: float = 560.0
## In landscape the panel takes at most this share of the width, so the player stays in view.
const PANEL_LANDSCAPE_WIDTH_FRACTION: float = 0.42
const TOUCH_BUTTON_SIZE: Vector2 = Vector2(72, 48)
const TOUCH_BUTTON_FONT_SIZE: int = 18
const TOUCH_HINTS: Dictionary = {
	"locked": "Fixed stick in the bottom-left corner",
	"floating": "Stick appears where your thumb lands",
	"drag": "Drag anywhere; the mage follows your thumb",
}

var _touch_buttons: Dictionary = {}

@onready var _preview: Node2D = $Preview
@onready var _panel: PanelContainer = $UI/Panel
@onready var _fov_slider: HSlider = %FovSlider
@onready var _fov_label: Label = %FovLabel
@onready var _hud_slider: HSlider = %HudSlider
@onready var _hud_label: Label = %HudLabel
@onready var _readout_toggle: CheckButton = %ReadoutToggle
@onready var _touch_row: HBoxContainer = %TouchRow
@onready var _touch_hint: Label = %TouchHint


func _ready() -> void:
	TouchControls.set_suspended(true)
	_fov_slider.min_value = ViewSettings.FOV_MIN * 100.0
	_fov_slider.max_value = ViewSettings.FOV_MAX * 100.0
	_hud_slider.min_value = ViewSettings.HUD_SCALE_MIN * 100.0
	_hud_slider.max_value = ViewSettings.HUD_SCALE_MAX * 100.0
	_build_touch_buttons()
	_sync_controls()
	_fov_slider.value_changed.connect(_on_fov_changed)
	_hud_slider.value_changed.connect(_on_hud_changed)
	_readout_toggle.toggled.connect(ViewSettings.set_debug_readout)
	%BackButton.pressed.connect(_on_back_pressed)
	%ResetButton.pressed.connect(_on_reset_pressed)
	ScreenLayout.layout_changed.connect(_place_panel)
	_place_panel()
	_spawn_preview()


func _exit_tree() -> void:
	TouchControls.set_suspended(false)


func _spawn_preview() -> void:
	var level: Node = PREVIEW_LEVEL_SCENE.instantiate()
	_preview.add_child(level)
	level.propagate_call("set_physics_process", [false])
	var player := get_tree().get_first_node_in_group("player") as Node2D
	var sentry := get_tree().get_first_node_in_group("sentry") as Node2D
	if player == null or sentry == null:
		return
	var arrow: DetectionArrow = DETECTION_ARROW_SCENE.instantiate()
	player.add_child(arrow)
	arrow.start_detection(sentry, SAMPLE_DETECTION_LEVEL)


func _sync_controls() -> void:
	_fov_slider.set_value_no_signal(ViewSettings.fov_scale * 100.0)
	_hud_slider.set_value_no_signal(ViewSettings.hud_scale * 100.0)
	_readout_toggle.set_pressed_no_signal(ViewSettings.debug_readout)
	_update_labels()
	_sync_touch_buttons()


func _update_labels() -> void:
	_fov_label.text = "World view: %d%%" % roundi(_fov_slider.value)
	_hud_label.text = "HUD size: %d%%" % roundi(_hud_slider.value)


# One toggle per scheme. Hidden when touch controls are off (e.g. `?touch=off`).
func _build_touch_buttons() -> void:
	var active: bool = not TouchControls.get_scheme_name().is_empty()
	_touch_row.visible = active
	_touch_hint.visible = active
	if not active:
		return
	var group := ButtonGroup.new()
	for scheme_name: String in TouchControls.SCHEME_SCENES:
		var button := Button.new()
		button.text = TouchControls.SCHEME_LABELS[scheme_name]
		button.toggle_mode = true
		button.button_group = group
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = TOUCH_BUTTON_SIZE
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", TOUCH_BUTTON_FONT_SIZE)
		button.pressed.connect(_on_touch_scheme_pressed.bind(scheme_name))
		_touch_row.add_child(button)
		_touch_buttons[scheme_name] = button


func _sync_touch_buttons() -> void:
	var current: String = TouchControls.get_scheme_name()
	for scheme_name: String in _touch_buttons:
		(_touch_buttons[scheme_name] as Button).set_pressed_no_signal(scheme_name == current)
	_touch_hint.text = TOUCH_HINTS.get(current, "")


func _on_touch_scheme_pressed(scheme_name: String) -> void:
	TouchControls.set_mode(scheme_name)
	_sync_touch_buttons()


func _on_fov_changed(value: float) -> void:
	ViewSettings.set_fov_scale(value / 100.0)
	_update_labels()


func _on_hud_changed(value: float) -> void:
	ViewSettings.set_hud_scale(value / 100.0)
	_update_labels()


func _on_reset_pressed() -> void:
	ViewSettings.set_fov_scale(1.0)
	ViewSettings.set_hud_scale(1.0)
	_sync_controls()


func _on_back_pressed() -> void:
	ViewSettings.save()
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


# Keeps the player in the middle of the preview clear: the right edge in landscape,
# the bottom edge in portrait.
func _place_panel() -> void:
	var safe: Rect2 = ScreenLayout.get_safe_rect().grow(-PANEL_MARGIN)
	var height: float = _panel.get_combined_minimum_size().y
	# On a screen shorter than the panel, keep the header (and Back) on screen.
	if safe.size.x > safe.size.y:
		var side_width: float = minf(safe.size.x * PANEL_LANDSCAPE_WIDTH_FRACTION, PANEL_MAX_WIDTH)
		var top: float = maxf(safe.get_center().y - height / 2.0, safe.position.y)
		_panel.position = Vector2(safe.end.x - side_width, top)
		_panel.size = Vector2(side_width, height)
		return
	var width: float = minf(safe.size.x, PANEL_MAX_WIDTH)
	_panel.position = Vector2(
		safe.get_center().x - width / 2.0, maxf(safe.end.y - height, safe.position.y)
	)
	_panel.size = Vector2(width, height)
