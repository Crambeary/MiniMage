extends MarginContainer

@onready var button: Button = $VBoxContainer/HBoxContainer/Button



func _on_button_button_up() -> void:
	var current := get_tree().current_scene
	if current != null and current.scene_file_path == "res://assets/scenes/ui/MainMenu.tscn":
		PlayAnalytics.notify_play_pressed()
	get_tree().change_scene_to_file("res://assets/scenes/levels/main.tscn")
