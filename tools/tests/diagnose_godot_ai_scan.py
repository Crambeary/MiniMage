#!/usr/bin/env python3
"""Reproduce cold headed editor scanning with an isolated, disposable project.

Only public plugin bytes are copied. Private XDG state is never inspected.
The probe prints EditorFileSystem state and exits after a bounded deadline.
"""
import argparse
import ctypes
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading
import time


PROBE = '''@tool
extends EditorPlugin
var elapsed := 0.0
var report_at := 0.0
var started := Time.get_ticks_msec()
func _enter_tree() -> void:
    EditorInterface.get_editor_settings().set_setting("godot_ai/v4_endpoint_ports", {"http_port": 18445, "ws_port": 19445})
    EditorInterface.get_editor_settings().set_setting("godot_ai/telemetry_enabled", false)
func _process(_delta: float) -> void:
    elapsed = (Time.get_ticks_msec() - started) / 1000.0
    if elapsed < report_at:
        return
    report_at = elapsed + 1.0
    var fs := EditorInterface.get_resource_filesystem()
    print("SCAN_PROBE pid=", OS.get_process_id(), " seconds=", elapsed, " scanning=", fs.is_scanning(), " importing=", fs.is_importing(), " processing=", fs.is_processing(), " progress=", fs.get_scanning_progress())
    if elapsed > 10.0 and int(elapsed) % 10 == 0:
        for window in get_tree().root.find_children("*", "Window", true, false):
            if window.visible:
                print("SCAN_PROBE dialog=", window.name, " title=", window.title)
                for label in window.find_children("*", "Label", true, false):
                    if label.is_visible_in_tree():
                        print("SCAN_PROBE label=", label.text)
    if not fs.is_scanning() and elapsed > 3.0:
        print("SCAN_PROBE PASS")
        get_tree().quit(0)
    elif elapsed > 30.0:
        print("SCAN_PROBE TIMEOUT")
        set_process(false)
        get_tree().quit(1)
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True)
    parser.add_argument("--with-addon", action="store_true")
    parser.add_argument("--full-project", action="store_true",
                        help="Copy tracked project bytes, excluding the import cache")
    parser.add_argument("--editors", type=int, choices=[1, 2], default=1)
    parser.add_argument("--ignore", action="append", default=[],
                        help="Ignore a project directory in the disposable copy")
    parser.add_argument("--render-load-seconds", type=int, default=0,
                        help="Run the game concurrently, then stop it after this many seconds")
    parser.add_argument("--debuggable", action="store_true",
                        help="Linux: let same-user debuggers attach to these disposable editors")
    parser.add_argument("--single-window", action="store_true",
                        help="Embed editor dialogs instead of creating native popup windows")
    parser.add_argument("--display-driver", choices=["x11", "wayland"])
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    private = Path(tempfile.mkdtemp(prefix="fry-scan-probe-"))
    private.chmod(0o700)
    project = private / "project"
    if args.full_project:
        names = subprocess.check_output(["git", "ls-files", "-z"], cwd=root).decode().split("\0")
        for name in filter(None, names):
            source = root / name
            if not source.is_file():
                continue
            target = project / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
    probe = project / "addons/probe"
    probe.mkdir(parents=True)
    (probe / "plugin.gd").write_text(PROBE)
    (probe / "plugin.cfg").write_text('[plugin]\nname="Scan probe"\ndescription="Bounded scan observer"\nauthor="FryTruckGame"\nversion="1"\nscript="plugin.gd"\n')
    plugins = ['"res://addons/probe/plugin.cfg"']
    if args.with_addon:
        if not args.full_project:
            shutil.copytree(root / "addons/godot_ai", project / "addons/godot_ai")
        plugins += ['"res://addons/godot_ai/plugin.cfg"']
    settings = 'config_version=5\n[application]\nconfig/name="Scan probe"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n'
    if args.full_project:
        settings = (project / "project.godot").read_text()
        start = settings.index("[editor_plugins]")
        end = settings.find("\n[", start + 1)
        end = len(settings) if end < 0 else end
        settings = settings[:start] + settings[end:]
    (project / "project.godot").write_text(settings + '\n[editor_plugins]\nenabled=PackedStringArray(' + ','.join(plugins) + ')\n')
    for name in args.ignore:
        directory = (project / name).resolve()
        if not directory.is_relative_to(project) or not directory.is_dir():
            parser.error("--ignore must name a directory inside the fixture")
        (directory / ".gdignore").write_text("")
    env = os.environ.copy()
    for kind in ("CONFIG", "DATA", "CACHE"):
        env[f"XDG_{kind}_HOME"] = str(private / kind.lower())
    env["GODOT_AI_DISABLE_TELEMETRY"] = "true"
    args.output.parent.mkdir(parents=True, exist_ok=True)
    projects = [project]
    if args.editors == 2:
        peer = private / "peer"
        shutil.copytree(project, peer)
        projects.append(peer)
    processes = []
    def allow_debugger():
        # PR_SET_PTRACER/PR_SET_PTRACER_ANY, for only this child process.
        if ctypes.CDLL(None).prctl(0x59616D61, ctypes.c_ulong(-1).value, 0, 0, 0):
            raise OSError("Cannot enable fixture debugger attachment")
    with args.output.open("w") as log:
        load = None
        timer = None
        codes = [124]
        try:
            if args.render_load_seconds:
                load = subprocess.Popen([args.godot, "--path", str(root)], env=env,
                                        stdout=log, stderr=subprocess.STDOUT)
                def end_load():
                    log.write("SCAN_PROBE stopping render load\n")
                    log.flush()
                    load.terminate()
                timer = threading.Timer(args.render_load_seconds, end_load)
                timer.start()
                time.sleep(2)
            for path in projects:
                command = [args.godot, "--path", str(path), "--editor"]
                if args.single_window:
                    command.append("--single-window")
                if args.display_driver:
                    command += ["--display-driver", args.display_driver]
                processes.append(subprocess.Popen(command,
                                 env=env, stdout=log, stderr=subprocess.STDOUT,
                                 preexec_fn=allow_debugger if args.debuggable else None))
            deadline = time.monotonic() + 60
            codes = [proc.wait(timeout=max(0.1, deadline - time.monotonic())) for proc in processes]
        except subprocess.TimeoutExpired:
            log.write("SCAN_PROBE supervisor TIMEOUT; closing owned fixture editors\n")
        finally:
            if timer:
                timer.cancel()
                timer.join()
            if load:
                if load.poll() is None:
                    load.terminate()
                try:
                    load.wait(timeout=8)
                except subprocess.TimeoutExpired:
                    load.kill()
                    load.wait()
            for proc in processes:
                if proc.poll() is None:
                    proc.terminate()
                    try:
                        proc.wait(timeout=8)
                    except subprocess.TimeoutExpired:
                        proc.kill()
                        proc.wait()
    print("exit", codes)
    return int(any(codes))


if __name__ == "__main__":
    raise SystemExit(main())
