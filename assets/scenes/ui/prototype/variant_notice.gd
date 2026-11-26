extends Control

## B (Notice): the menu is a poster pinned to a stone wall. The mage is a portrait in the sheet, not a figure in a room.

const Art = preload("res://assets/scenes/ui/prototype/menu_prototype_art.gd")

var _poster: Control


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var wall := Art.tiled(Art.CASTLE, Rect2i(16, 16, 32, 32))
	wall.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(wall)
	_poster = Control.new()
	_poster.custom_minimum_size = Vector2(320, 390)
	_poster.clip_contents = true
	_poster.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_poster)
	var paper := ColorRect.new()
	paper.color = Color(0.29, 0.24, 0.2)
	paper.set_anchors_preset(Control.PRESET_FULL_RECT)
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_poster.add_child(paper)
	var window := Art.sprite(Art.CASTLE, Rect2i(160, 80, 64, 80), 3.0)
	window.position = Vector2(160, 150)
	_poster.add_child(window)
	var title := Art.title_label("Mini Mage", 36)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.offset_top = 200.0
	title.offset_bottom = 242.0
	title.offset_left = -140.0
	title.offset_right = 140.0
	_poster.add_child(title)
	var line := Art.title_label("a stealth in the castle", 14)
	line.modulate = Color(0.85, 0.75, 0.62)
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.set_anchors_preset(Control.PRESET_CENTER_TOP)
	line.offset_top = 246.0
	line.offset_bottom = 268.0
	line.offset_left = -140.0
	line.offset_right = 140.0
	_poster.add_child(line)
	var button := Art.start_button()
	button.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	button.offset_left = -70.0
	button.offset_right = 70.0
	button.offset_top = -64.0
	button.offset_bottom = -28.0
	_poster.add_child(button)
	var portrait := Art.animated(Art.MAGE, Vector2i(32, 32), 8, 6.0)
	portrait.scale = Vector2(3, 3)
	portrait.position = Vector2(72, 248)
	_poster.add_child(portrait)
	resized.connect(_layout)
	_layout()


func _layout() -> void:
	if size.x < 8.0:
		return
	_poster.position = Vector2(roundf((size.x - 320.0) * 0.5), 28.0)
