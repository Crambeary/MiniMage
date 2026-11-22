@tool
extends EditorPlugin

## Edits the selected PatrolPath2D in the 2D viewport.
##   Drag a handle      move the waypoint (snapped to the path's snap_step)
##   Ctrl + click       add a waypoint (inserted into a nearby segment, else appended)
##   Right-click handle remove the waypoint
##   Click a handle     select that waypoint (to edit it in the inspector)
##   Esc while dragging cancel the drag
## Every edit is undoable. See docs/design/patrol-path-editor.md.

const HANDLE_RADIUS := 6.0
const PICK_RADIUS := 9.0
const SEGMENT_PICK_DISTANCE := 10.0

var _path: PatrolPath2D
var _drag_index := -1
var _drag_wp: Waypoint2D
var _drag_from := Vector2.ZERO
var _hover_index := -1


func _handles(object: Object) -> bool:
	return _path_for(object) != null


func _edit(object: Object) -> void:
	var path := _path_for(object)
	if path != _path:
		_end_drag()
	_path = path
	_hover_index = -1
	update_overlays()


func _make_visible(visible: bool) -> void:
	if not visible:
		_end_drag()
		_path = null
	update_overlays()


func _path_for(object: Object) -> PatrolPath2D:
	if object is PatrolPath2D:
		return object
	if object is Waypoint2D and (object as Node).get_parent() is PatrolPath2D:
		return (object as Node).get_parent()
	return null


func _forward_canvas_gui_input(event: InputEvent) -> bool:
	if not is_instance_valid(_path) or not _path.is_inside_tree():
		return false

	if _is_dragging() and event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and key.keycode == KEY_ESCAPE:
			_cancel_drag()
			return true

	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _is_dragging():
			if not (motion.button_mask & MOUSE_BUTTON_MASK_LEFT):
				# The release happened outside the viewport and never reached us.
				_commit_drag()
				return false
			_drag_wp.global_position = _path.snap_global(_screen_to_global(motion.position))
			update_overlays()
			return true
		var hover := _pick_handle(motion.position)
		if hover != _hover_index:
			_hover_index = hover
			update_overlays()
		return false

	if not event is InputEventMouseButton:
		return false
	var button := event as InputEventMouseButton

	if button.button_index == MOUSE_BUTTON_LEFT:
		if button.pressed:
			var index := _pick_handle(button.position)
			if button.ctrl_pressed or button.meta_pressed:
				if index < 0: # Ctrl+click on a handle must not stack a new waypoint on it
					_add_waypoint_at(button.position)
				return true
			if index >= 0:
				_drag_index = index
				_drag_wp = _path.get_waypoints()[index]
				_drag_from = _drag_wp.position
				return true
		elif _is_dragging():
			_commit_drag()
			return true

	if button.button_index == MOUSE_BUTTON_RIGHT and button.pressed:
		if _is_dragging():
			return true # never remove waypoints mid-drag
		var index := _pick_handle(button.position)
		if index >= 0:
			_remove_waypoint(index)
			return true

	return false


func _forward_canvas_draw_over_viewport(overlay: Control) -> void:
	if not is_instance_valid(_path) or not _path.is_inside_tree():
		return
	var font := ThemeDB.fallback_font
	var wps := _path.get_waypoints()
	for i in wps.size():
		var screen := _global_to_screen(wps[i].global_position)
		var fill := Color(1.0, 1.0, 1.0) if i == _hover_index or i == _drag_index else _path.preview_color
		overlay.draw_circle(screen, HANDLE_RADIUS + 1.5, Color(0, 0, 0, 0.8))
		overlay.draw_circle(screen, HANDLE_RADIUS, fill)
		overlay.draw_string(font, screen + Vector2(HANDLE_RADIUS + 2.0, -HANDLE_RADIUS), str(i + 1),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
	var hint := "Patrol path: drag to move (Esc cancels) · click to select · Ctrl+click to add · right-click to remove"
	overlay.draw_string(font, Vector2(8, overlay.size.y - 10), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.8))


func _is_dragging() -> bool:
	return _drag_index >= 0 and is_instance_valid(_drag_wp)


## Commits a drag that is still in progress (selection changed, plugin hidden).
func _end_drag() -> void:
	if _is_dragging():
		_commit_drag()
	_drag_index = -1
	_drag_wp = null


func _cancel_drag() -> void:
	_drag_wp.position = _drag_from
	_drag_index = -1
	_drag_wp = null
	update_overlays()


func _commit_drag() -> void:
	var wp := _drag_wp
	var to := wp.position
	_drag_index = -1
	_drag_wp = null
	if to == _drag_from:
		# A click without movement selects the waypoint, so it can be edited in the inspector.
		var selection := EditorInterface.get_selection()
		selection.clear()
		selection.add_node(wp)
		update_overlays()
		return
	var ur := get_undo_redo()
	ur.create_action("Move waypoint")
	ur.add_do_property(wp, "position", to)
	ur.add_undo_property(wp, "position", _drag_from)
	ur.add_do_method(self, "update_overlays")
	ur.add_undo_method(self, "update_overlays")
	ur.commit_action(false)
	update_overlays()


func _add_waypoint_at(screen_pos: Vector2) -> void:
	var root := EditorInterface.get_edited_scene_root()
	var wp := Waypoint2D.new()
	wp.name = _free_point_name()
	wp.position = _path.to_local(_path.snap_global(_screen_to_global(screen_pos)))
	var index := _insert_index_for(screen_pos)

	var ur := get_undo_redo()
	ur.create_action("Add waypoint")
	ur.add_do_method(_path, "add_child", wp, true)
	ur.add_do_method(_path, "move_child", wp, index)
	ur.add_do_property(wp, "owner", root)
	ur.add_do_reference(wp)
	ur.add_undo_method(_path, "remove_child", wp)
	ur.add_do_method(self, "update_overlays")
	ur.add_undo_method(self, "update_overlays")
	ur.commit_action()


func _remove_waypoint(index: int) -> void:
	var root := EditorInterface.get_edited_scene_root()
	var wp: Waypoint2D = _path.get_waypoints()[index]
	var child_index := wp.get_index()

	var ur := get_undo_redo()
	ur.create_action("Remove waypoint")
	ur.add_do_method(_path, "remove_child", wp)
	ur.add_undo_method(_path, "add_child", wp, true)
	ur.add_undo_method(_path, "move_child", wp, child_index)
	ur.add_undo_property(wp, "owner", root)
	ur.add_undo_reference(wp)
	ur.add_do_method(self, "update_overlays")
	ur.add_undo_method(self, "update_overlays")
	ur.commit_action()
	_hover_index = -1


## Child index for a new waypoint clicked at screen_pos: right after the start
## of the nearest segment within reach, otherwise at the end.
func _insert_index_for(screen_pos: Vector2) -> int:
	var wps := _path.get_waypoints()
	var segments := wps.size() - 1
	if _path.mode == PatrolPath2D.Mode.LOOP and wps.size() > 2:
		segments += 1 # the closing segment; inserting there means appending
	var best := -1
	var best_distance := SEGMENT_PICK_DISTANCE
	for i in segments:
		var a := _global_to_screen(wps[i].global_position)
		var b := _global_to_screen(wps[(i + 1) % wps.size()].global_position)
		var d := screen_pos.distance_to(Geometry2D.get_closest_point_to_segment(screen_pos, a, b))
		if d < best_distance:
			best_distance = d
			best = i
	if best < 0 or best == wps.size() - 1:
		return _path.get_child_count()
	return wps[best + 1].get_index()


func _pick_handle(screen_pos: Vector2) -> int:
	var wps := _path.get_waypoints()
	for i in range(wps.size() - 1, -1, -1):
		if _global_to_screen(wps[i].global_position).distance_to(screen_pos) <= PICK_RADIUS:
			return i
	return -1


func _free_point_name() -> String:
	var n := _path.get_child_count() + 1
	while _path.has_node(NodePath("Point%d" % n)):
		n += 1
	return "Point%d" % n


func _global_to_screen(point: Vector2) -> Vector2:
	return _path.get_viewport_transform() * point


func _screen_to_global(point: Vector2) -> Vector2:
	return _path.get_viewport_transform().affine_inverse() * point
