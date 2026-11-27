extends MarginContainer


func _on_button_button_up() -> void:
	var current := get_tree().current_scene
	if current != null and current.scene_file_path == "res://assets/scenes/ui/MainMenu.tscn":
		PlayAnalytics.notify_play_pressed()
	get_tree().change_scene_to_file("res://assets/scenes/levels/main.tscn")


func _on_settings_button_pressed() -> void:
	get_tree().change_scene_to_file("res://assets/scenes/ui/SettingsMenu.tscn")
