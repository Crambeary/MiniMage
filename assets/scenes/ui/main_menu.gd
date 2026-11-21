extends MarginContainer

@onready var button: Button = $VBoxContainer/HBoxContainer/Button



func _on_button_button_up() -> void:
	get_tree().change_scene_to_file("res://assets/scenes/levels/main.tscn")
