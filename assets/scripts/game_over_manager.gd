extends Node

const GAME_OVER_SCREEN: PackedScene = preload("res://assets/scenes/ui/GameOverScreen.tscn")
const SENTRY_GROUP: StringName = &"sentry"

var _screen: Node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().node_added.connect(_on_node_added)


func show_game_over() -> void:
	if is_instance_valid(_screen):
		return
	get_tree().paused = true
	_screen = GAME_OVER_SCREEN.instantiate()
	_screen.retry_requested.connect(_on_retry_requested)
	_screen.main_menu_requested.connect(_on_main_menu_requested)
	get_tree().root.add_child(_screen)


func _on_node_added(node: Node) -> void:
	if node.is_in_group(SENTRY_GROUP) and node.has_signal("player_caught"):
		node.player_caught.connect(_on_player_caught)


func _on_player_caught(_catcher: Node2D) -> void:
	show_game_over.call_deferred()


func _on_retry_requested() -> void:
	_close_screen()
	get_tree().reload_current_scene()


func _on_main_menu_requested() -> void:
	_close_screen()
	get_tree().change_scene_to_file("res://assets/scenes/ui/MainMenu.tscn")


func _close_screen() -> void:
	get_tree().paused = false
	_screen.queue_free()
	_screen = null
