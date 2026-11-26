extends Node

const MENU_SCENE := "res://assets/scenes/ui/MainMenu.tscn"
const LEVEL_EVENTS := {
	"res://assets/scenes/levels/main.tscn": "level_1_complete",
	"res://assets/scenes/levels/level_2.tscn": "level_2_complete",
}
const HEARTBEAT_SEC := 15.0

var _session_id := ""
var _started_ms := 0
var _open := false
var _finished := false
var _sent := {}

var _queue: Array[String] = []
var _inflight := false
var _exiting := false
var _web_warned := false
var _http: HTTPRequest
var _timer: Timer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not OS.has_feature("web"):
		_http = HTTPRequest.new()
		_http.process_mode = Node.PROCESS_MODE_ALWAYS
		_http.timeout = 10.0
		add_child(_http)
		_http.request_completed.connect(_on_request_completed)
	_timer = Timer.new()
	_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	_timer.wait_time = HEARTBEAT_SEC
	_timer.one_shot = false
	add_child(_timer)
	_timer.timeout.connect(_on_heartbeat)
	get_tree().scene_changed.connect(_on_scene_changed)


func settled() -> bool:
	return _queue.is_empty() and not _inflight


func notify_play_pressed() -> void:
	if _open and not _finished:
		_finish("menu")
	_start_session()
	_emit_named("play_pressed", {})


func notify_level_exit(scene_path: String) -> void:
	if not LEVEL_EVENTS.has(scene_path):
		return
	if not _open or _finished:
		_start_session()
	_emit_named(str(LEVEL_EVENTS[scene_path]), {"duration_ms": _elapsed_ms()})


func _start_session() -> void:
	_session_id = Crypto.new().generate_random_bytes(16).hex_encode()
	_started_ms = _now_ms()
	_open = true
	_finished = false
	_sent.clear()
	if is_instance_valid(_timer):
		_timer.start()
	_publish_web_session(true)


func _on_heartbeat() -> void:
	if not _open or _finished:
		return
	_publish_web_session(false)
	_emit("session_duration", {
		"duration_ms": _elapsed_ms(),
		"partial": true,
		"reason": "heartbeat",
	})


func _on_scene_changed() -> void:
	if not _open or _finished:
		return
	var current := get_tree().current_scene
	if current != null and current.scene_file_path == MENU_SCENE:
		_finish("menu")


func _exit_tree() -> void:
	_exiting = true
	if _open and not _finished:
		_finish("quit")
	_flush_blocking()


func _finish(reason: String) -> void:
	if not _open or _finished:
		return
	_finished = true
	_open = false
	if is_instance_valid(_timer):
		_timer.stop()
	_emit("session_duration", {
		"duration_ms": _elapsed_ms(),
		"partial": false,
		"reason": reason,
	})
	_publish_web_session(false)


func _emit_named(event_name: String, extra: Dictionary) -> void:
	if _sent.has(event_name):
		return
	_sent[event_name] = true
	_emit(event_name, extra)


func _emit(event_name: String, extra: Dictionary) -> void:
	var payload := {
		"event": event_name,
		"session_id": _session_id,
		"unix_ms": _now_ms(),
		"platform": OS.get_name(),
	}
	for key in extra:
		payload[key] = extra[key]
	var line := JSON.stringify(payload)
	_write_line(line)
	print("ANALYTICS " + line)
	if OS.has_feature("web"):
		_send_web(event_name, payload)
		return
	if _endpoint().is_empty():
		return
	_queue.append(line)
	if _exiting:
		return
	_pump()


func _ga_params(event_name: String, payload: Dictionary) -> Dictionary:
	var params := {
		"game_session_id": str(payload.get("session_id", "")),
		"game_platform": str(payload.get("platform", "")),
	}
	if payload.has("duration_ms"):
		params["duration_ms"] = int(payload["duration_ms"])
	else:
		params["duration_ms"] = _elapsed_ms()
	if event_name == "session_duration":
		params["session_end_reason"] = str(payload.get("reason", ""))
		params["partial"] = bool(payload.get("partial", false))
		if str(payload.get("reason", "")) == "quit":
			params["transport_type"] = "beacon"
	return params


func _send_web(event_name: String, payload: Dictionary) -> void:
	if event_name == "session_duration" and payload.get("partial", false):
		return
	var params_json := JSON.stringify(_ga_params(event_name, payload))
	var code := (
		"(function(){"
		+ "if(typeof window.miniMageAnalytics!=='function')return false;"
		+ "window.miniMageAnalytics(%s,%s);return true;"
		+ "})()"
	) % [JSON.stringify(event_name), JSON.stringify(params_json)]
	var sent: Variant = JavaScriptBridge.eval(code, true)
	if sent != true and not _web_warned:
		_web_warned = true
		print("PlayAnalytics web bridge missing window.miniMageAnalytics")


func _publish_web_session(reset_final: bool) -> void:
	if not OS.has_feature("web"):
		return
	var state := JSON.stringify({
		"open": _open and not _finished,
		"id": _session_id,
		"startedMs": _started_ms,
		"platform": OS.get_name(),
	})
	var reset := "true" if reset_final else "false"
	var code := (
		"if(typeof window.miniMagePublishSession==='function')"
		+ "window.miniMagePublishSession(%s,%s);"
	) % [state, reset]
	JavaScriptBridge.eval(code, true)


func _elapsed_ms() -> int:
	return maxi(_now_ms() - _started_ms, 0)


func _now_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)


func _endpoint() -> String:
	var from_env := OS.get_environment("MINIMAGE_ANALYTICS_URL")
	if not from_env.is_empty():
		return from_env
	return str(ProjectSettings.get_setting("analytics/endpoint", ""))


func _log_path() -> String:
	var from_env := OS.get_environment("MINIMAGE_ANALYTICS_LOG")
	if not from_env.is_empty():
		return from_env
	return "user://analytics/events.jsonl"


func _write_line(line: String) -> void:
	var path := _log_path()
	_ensure_parent(path)
	var file := FileAccess.open(path, FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(path, FileAccess.WRITE_READ)
	if file == null:
		print("PlayAnalytics log failed path=%s error=%s" % [path, FileAccess.get_open_error()])
		return
	file.seek_end()
	file.store_line(line)
	file.flush()


func _ensure_parent(path: String) -> void:
	var directory := path.get_base_dir()
	if directory.is_empty():
		return
	var absolute := directory
	if directory.begins_with("user://") or directory.begins_with("res://"):
		absolute = ProjectSettings.globalize_path(directory)
	DirAccess.make_dir_recursive_absolute(absolute)


func _pump() -> void:
	if OS.has_feature("web") or _exiting or _inflight or _queue.is_empty():
		return
	var endpoint := _endpoint()
	if endpoint.is_empty():
		_queue.clear()
		return
	var body: String = _queue.pop_front()
	_inflight = true
	var err := _http.request(
		endpoint,
		PackedStringArray(["Content-Type: text/plain"]),
		HTTPClient.METHOD_POST,
		body
	)
	if err != OK:
		_inflight = false
		print("PlayAnalytics POST failed to start error=%s" % err)
		_pump()


func _on_request_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	_body: PackedByteArray
) -> void:
	_inflight = false
	if result != HTTPRequest.RESULT_SUCCESS:
		print("PlayAnalytics POST failed result=%s code=%s" % [result, response_code])
	_pump()


func _flush_blocking() -> void:
	if OS.has_feature("web"):
		_queue.clear()
		_inflight = false
		return
	var endpoint := _endpoint()
	if endpoint.is_empty():
		_queue.clear()
		_inflight = false
		return
	var deadline := Time.get_ticks_msec() + 3000
	while not _queue.is_empty() and Time.get_ticks_msec() <= deadline:
		var body: String = _queue.pop_front()
		_post_blocking(endpoint, body, deadline)
	_queue.clear()
	_inflight = false


func _post_blocking(endpoint: String, body: String, deadline: int) -> void:
	var parts := _split_url(endpoint)
	if parts.is_empty():
		print("PlayAnalytics POST failed bad url")
		return
	var client := HTTPClient.new()
	var err := client.connect_to_host(parts["host"], int(parts["port"]), parts["tls"])
	if err != OK:
		print("PlayAnalytics POST failed connect error=%s" % err)
		return
	while client.get_status() == HTTPClient.STATUS_CONNECTING or client.get_status() == HTTPClient.STATUS_RESOLVING:
		client.poll()
		if Time.get_ticks_msec() > deadline:
			print("PlayAnalytics POST failed connect timeout")
			return
		OS.delay_msec(10)
	if client.get_status() != HTTPClient.STATUS_CONNECTED:
		print("PlayAnalytics POST failed status=%s" % client.get_status())
		return
	err = client.request(HTTPClient.METHOD_POST, parts["path"], ["Content-Type: text/plain"], body)
	if err != OK:
		print("PlayAnalytics POST failed request error=%s" % err)
		return
	var saw_response := false
	while Time.get_ticks_msec() <= deadline:
		client.poll()
		var status := client.get_status()
		if status == HTTPClient.STATUS_BODY:
			saw_response = true
			client.read_response_body_chunk()
			if client.get_status() != HTTPClient.STATUS_BODY:
				return
		elif status == HTTPClient.STATUS_CONNECTED and client.get_response_code() != 0:
			return
		elif status == HTTPClient.STATUS_DISCONNECTED or status == HTTPClient.STATUS_CONNECTION_ERROR or status == HTTPClient.STATUS_CANT_CONNECT:
			break
		OS.delay_msec(10)
	if not saw_response:
		print("PlayAnalytics POST failed request timeout")


func _split_url(endpoint: String) -> Dictionary:
	var tls := false
	var rest := endpoint
	if rest.begins_with("https://"):
		tls = true
		rest = rest.substr(8)
	elif rest.begins_with("http://"):
		rest = rest.substr(7)
	else:
		return {}
	var slash := rest.find("/")
	var hostport := rest if slash < 0 else rest.substr(0, slash)
	var path := "/" if slash < 0 else rest.substr(slash)
	var host := hostport
	var port := 443 if tls else 80
	var colon := hostport.rfind(":")
	if colon > 0:
		host = hostport.substr(0, colon)
		port = int(hostport.substr(colon + 1))
	var tls_options: TLSOptions = TLSOptions.client() if tls else null
	return {"host": host, "port": port, "path": path, "tls": tls_options}
