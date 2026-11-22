@tool
extends EditorPlugin

func _enter_tree() -> void:
    var settings := EditorInterface.get_editor_settings()
    settings.set_setting("godot_ai/v4_endpoint_ports", {
        "http_port": int(OS.get_environment("GODOT_AI_PORT")),
        "ws_port": int(OS.get_environment("GODOT_AI_WS_PORT")),
    })
    settings.set_setting("godot_ai/telemetry_enabled", false)
    _enable.call_deferred()

func _enable() -> void:
    EditorInterface.set_plugin_enabled("godot_ai", true)
    print("MIGRATION_FIXTURE: isolated endpoint settings applied")

# Test harness requests a real EditorUndoRedoManager undo by creating this
# public marker in the isolated data directory. No custom plugin code changes.
func _process(_delta: float) -> void:
    var marker := OS.get_environment("XDG_DATA_HOME").path_join("migration-undo")
    if not FileAccess.file_exists(marker):
        return
    if FileAccess.get_file_as_string(marker) != ProjectSettings.globalize_path("res://"):
        return
    DirAccess.remove_absolute(marker)
    var root := EditorInterface.get_edited_scene_root()
    if root != null:
        var manager := get_undo_redo()
        var history := manager.get_history_undo_redo(manager.get_object_history_id(root))
        var undone := history.undo()
        print("MIGRATION_FIXTURE: undo=", undone)
