extends CanvasLayer

signal retry_requested
signal main_menu_requested

const ABOVE_TOUCH_CONTROLS_LAYER: int = 102

@onready var retry_button: Button = $MarginContainer/VBoxContainer/HBoxContainer/RetryButton


func _ready() -> void:
	layer = ABOVE_TOUCH_CONTROLS_LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	retry_button.grab_focus()


func _on_retry_button_pressed() -> void:
	retry_requested.emit()


func _on_main_menu_button_pressed() -> void:
	main_menu_requested.emit()
