@tool
class_name Waypoint2D
extends Marker2D

## One stop on a PatrolPath2D. Its position is the stop; the exports say what
## the sentry does there.

@export var action: String = "walk"
@export var wait_time: float = 0.0:
	set(value):
		wait_time = value
		_redraw_path()
@export var facing_direction: Vector2 = Vector2.ZERO


func _enter_tree() -> void:
	if Engine.is_editor_hint():
		set_notify_local_transform(true)
	_redraw_path()


func _exit_tree() -> void:
	_redraw_path()


func _notification(what: int) -> void:
	if what == NOTIFICATION_LOCAL_TRANSFORM_CHANGED:
		_redraw_path()


func _redraw_path() -> void:
	var parent := get_parent()
	if parent is CanvasItem and Engine.is_editor_hint():
		(parent as CanvasItem).queue_redraw()
