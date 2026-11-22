#!/usr/bin/env python3
"""Verify pinned upstream tooling, signed release, and exact vendored bytes.

Offline: Python 3.11..3.14 and OpenSSL only. Never reads capability records.
"""
import hashlib
import importlib.util
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
VENDOR = ROOT / "tools/vendor/godot-ai-v4.3.1"
ASSETS = ROOT / "docs/agent-tooling/godot-ai-v4.3.1/release"
SOURCE = "35da2c2fe1e2c20e11b5be01841e966951d6314b"
PIN = "84ebbd811f3a12c09ff4e236bbbbb9310fc23e03fcfc3717ba546747d0d21072"


def main():
    provenance = json.loads((VENDOR / "SOURCE.json").read_text())
    assert provenance["commit"] == SOURCE
    assert provenance["public_key_spki_sha256"] == PIN
    for name, digest in provenance["files"].items():
        assert hashlib.sha256((VENDOR / name).read_bytes()).hexdigest() == digest, name
    spec = importlib.util.spec_from_file_location("release_verify", VENDOR / "src/godot_ai/release_verify.py")
    verifier = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(verifier)
    assert verifier.PUBLIC_KEY_SPKI_SHA256 == PIN
    expected = ("hi-godot/godot-ai", "stable", "v4.3.1", "4.3.1", SOURCE)
    manifest = verifier.verify_release(
        ASSETS / "godot-ai-v4-plugin.zip",
        ASSETS / "godot-ai-v4-plugin.manifest.json",
        ASSETS / "godot-ai-v4-plugin.manifest.sig", expected)
    # Public API binds every path and byte, rejects extras and symlinks.
    verifier._verify_installed_tree(ROOT / "addons/godot_ai", manifest)
    print("PASS: pinned upstream verifier, signed v4.3.1, exact physical addon inventory")


if __name__ == "__main__":
    main()
