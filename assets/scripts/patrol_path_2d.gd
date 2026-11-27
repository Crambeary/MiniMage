@tool
class_name PatrolPath2D
extends Node2D

## A sentry's patrol route. The Waypoint2D children, in child order, are the
## stops. Edit it in the 2D viewport with the Patrol Path Editor plugin; see
## docs/design/patrol-path-editor.md.

enum Mode {
	LOOP,  ## 0 → n−1, then back to 0.
	PING_PONG,  ## 0 → n−1 → 0 by retracing, without repeating an end point.
}

@export var mode: Mode = Mode.LOOP:
	set(value):
		mode = value
		queue_redraw()

## Grid that waypoints snap to while dragged or added in the editor, in
## global pixels. (0, 0) turns snapping off. 8 reaches both corners and
## centres of the 16 px castle tiles.
@export var snap_step: Vector2 = Vector2(8, 8)

## Colour of the route preview in the editor.
@export var preview_color: Color = Color(1.0, 0.75, 0.2, 0.9):
	set(value):
		preview_color = value
		queue_redraw()


func get_waypoints() -> Array[Waypoint2D]:
	var result: Array[Waypoint2D] = []
	for child in get_children():
		if child is Waypoint2D:
			result.append(child)
	return result


## The stop after `index` when moving in direction `step` (+1 or −1).
## Returns Vector2i(next_index, next_step).
func next(index: int, step: int) -> Vector2i:
	var count := get_waypoints().size()
	if count <= 1:
		return Vector2i(0, 1)
	match mode:
		Mode.PING_PONG:
			var candidate := index + step
			if candidate < 0 or candidate >= count:
				step = -step
				candidate = index + step
			return Vector2i(candidate, step)
		_:
			return Vector2i((index + 1) % count, 1)


## Snaps a global position to this path's grid.
func snap_global(point: Vector2) -> Vector2:
	if snap_step.x <= 0.0 or snap_step.y <= 0.0:
		return point
	return point.snapped(snap_step)


func _ready() -> void:
	if Engine.is_editor_hint():
		child_order_changed.connect(_on_child_order_changed)


func _on_child_order_changed() -> void:
	queue_redraw()
	update_configuration_warnings()


func _get_configuration_warnings() -> PackedStringArray:
	if get_waypoints().is_empty():
		return PackedStringArray(
			["Add Waypoint2D children (Ctrl+click in the 2D viewport with this node selected)."]
		)
	return PackedStringArray()


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var points: Array[Vector2] = []
	for wp in get_waypoints():
		points.append(wp.position)
	var width := 1.5
	for i in points.size() - 1:
		_draw_segment(points[i], points[i + 1], width)
	if mode == Mode.LOOP and points.size() > 2:
		_draw_segment(points[-1], points[0], width)
	var wps := get_waypoints()
	for i in wps.size():
		if wps[i].wait_time > 0.0:
			draw_arc(points[i], 6.0, 0.0, TAU, 16, preview_color, 1.0)


func _draw_segment(from: Vector2, to: Vector2, width: float) -> void:
	draw_line(from, to, preview_color, width)
	var length := from.distance_to(to)
	if length < 8.0:
		return
	var dir := (to - from) / length
	var tip := from.lerp(to, 0.5) + dir * 3.0
	var side := dir.orthogonal() * 3.0
	draw_colored_polygon(
		PackedVector2Array([tip, tip - dir * 6.0 + side, tip - dir * 6.0 - side]), preview_color
	)
