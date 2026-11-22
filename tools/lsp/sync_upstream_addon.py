#!/usr/bin/env python3
"""Install or verify the unmodified addon from the locked npm package."""
import argparse
import json
from pathlib import Path
import shutil

root = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--install", action="store_true", help="copy the addon if it is absent")
args = parser.parse_args()
package = root / "tools/lsp/upstream-trial/node_modules/@shin2344234/godot-mcp"
if not (package / "package.json").is_file():
    parser.error("run npm ci --prefix tools/lsp/upstream-trial --ignore-scripts first")
if json.loads((package / "package.json").read_text())["version"] != "0.1.2":
    parser.error("expected pinned upstream version 0.1.2")
source = package / "addon/godot_mcp"
target = root / "addons/godot_mcp"
if args.install and not target.exists():
    shutil.copytree(source, target)
expected = {p.relative_to(source): p for p in source.rglob("*") if p.is_file()}
actual = {p.relative_to(target): p for p in target.rglob("*") if p.is_file()}
differences = sorted(str(p) for p in expected.keys() | actual.keys()
                     if p not in expected or p not in actual or expected[p].read_bytes() != actual[p].read_bytes())
if differences:
    parser.error("addon differs from pinned package: " + ", ".join(differences))
print(f"Verified {len(expected)} addon files against @shin2344234/godot-mcp@0.1.2")
