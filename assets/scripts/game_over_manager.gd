extends Node

const GAME_OVER_SCREEN: PackedScene = preload("res://assets/scenes/ui/GameOverScreen.tscn")
const CAUGHT_MOMENT: GDScript = preload("res://assets/scenes/ui/caught_moment.gd")
const SENTRY_GROUP: StringName = &"sentry"

var _screen: Node
var _moment: Node
## True from the first catch until the run is retried, abandoned or interrupted.
var _caught: bool = false
var _caught_scene: Node
var _moment_finished: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().node_added.connect(_on_node_added)


func show_game_over() -> void:
	if is_instance_valid(_screen):
		return
	_caught = true
	Engine.time_scale = 1.0
	get_tree().paused = true
	_screen = GAME_OVER_SCREEN.instantiate()
	_screen.retry_requested.connect(_on_retry_requested)
	_screen.main_menu_requested.connect(_on_main_menu_requested)
	get_tree().root.add_child(_screen)


func _on_node_added(node: Node) -> void:
	if node.is_in_group(SENTRY_GROUP) and node.has_signal("player_caught"):
		node.player_caught.connect(_on_player_caught)


func _on_player_caught(_catcher: Node2D) -> void:
	if _caught:
		return
	# The catch is final the instant it happens: freeze the world now, play the
	# beat over it afterwards.
	_caught = true
	get_tree().paused = true
	show_caught_moment.call_deferred()


## Plays the short "SPOTTED" beat, then the game-over screen. Failure is already
## decided; this is presentation only.
func show_caught_moment() -> void:
	if is_instance_valid(_screen) or is_instance_valid(_moment):
		return
	_caught = true
	get_tree().paused = true
	_moment_finished = false
	_caught_scene = get_tree().current_scene
	if _caught_scene != null:
		_caught_scene.tree_exited.connect(_on_caught_scene_exited, CONNECT_ONE_SHOT)
	_moment = CAUGHT_MOMENT.new()
	_moment.finished.connect(_on_moment_finished, CONNECT_ONE_SHOT)
	_moment.tree_exited.connect(_on_moment_exited, CONNECT_ONE_SHOT)
	get_tree().root.add_child(_moment)


func _on_moment_finished() -> void:
	_moment_finished = true
	_open_game_over_if_still_here.call_deferred()


func _open_game_over_if_still_here() -> void:
	var scene_gone: bool = _caught_scene != null and not is_instance_valid(_caught_scene)
	if scene_gone or get_tree().current_scene != _caught_scene:
		_abandon_moment()
		return
	_disconnect_scene_watch()
	show_game_over()


func _on_moment_exited() -> void:
	# Freed without finishing: nothing will open the game-over screen, so undo the freeze.
	if not _moment_finished:
		_abandon_moment()


func _on_caught_scene_exited() -> void:
	# The scene was torn down or replaced mid-moment; the overlay belongs to it.
	if is_instance_valid(_moment) and not _moment_finished:
		_moment.queue_free()
	elif not is_instance_valid(_moment) and not is_instance_valid(_screen):
		_abandon_moment()


func _abandon_moment() -> void:
	# Engine shutdown frees the overlay after the tree is gone; nothing to undo then.
	if not is_inside_tree():
		return
	_disconnect_scene_watch()
	if is_instance_valid(_moment):
		_moment.queue_free()
	_moment = null
	_caught_scene = null
	_caught = false
	Engine.time_scale = 1.0
	if not is_instance_valid(_screen):
		get_tree().paused = false


func _disconnect_scene_watch() -> void:
	if (
		is_instance_valid(_caught_scene)
		and _caught_scene.tree_exited.is_connected(_on_caught_scene_exited)
	):
		_caught_scene.tree_exited.disconnect(_on_caught_scene_exited)


func _on_retry_requested() -> void:
	_close_screen()
	get_tree().reload_current_scene()


func _on_main_menu_requested() -> void:
	_close_screen()
	get_tree().change_scene_to_file("res://assets/scenes/ui/MainMenu.tscn")


func _close_screen() -> void:
	_caught = false
	_moment = null
	_caught_scene = null
	Engine.time_scale = 1.0
	get_tree().paused = false
	_screen.queue_free()
	_screen = null
