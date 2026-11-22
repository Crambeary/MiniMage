"""Check forwarding of engine flags and the plugin's LSP-port user argument."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


class LauncherTests(unittest.TestCase):
    def launch(self, *args):
        root = Path(__file__).resolve().parents[2]
        with tempfile.TemporaryDirectory() as temp:
            engine = Path(temp) / "fake-godot"
            engine.write_text('#!/usr/bin/env python3\nimport json,sys\nprint(json.dumps(sys.argv[1:]))\n')
            engine.chmod(0o755)
            output = subprocess.check_output(["bash", "tools/open-editor.sh", *args],
                cwd=root, env=dict(os.environ, GODOT_BIN=str(engine)), text=True)
        return json.loads(output)

    def test_default_does_not_invent_port(self):
        self.assertEqual(self.launch()[2:], ["--editor"])

    def test_explicit_port_reaches_engine_and_plugin(self):
        forwarded = self.launch("--lsp-port", "16005", "--dap-port", "16006")
        self.assertEqual(forwarded[3:], ["--lsp-port", "16005", "--dap-port", "16006", "--", "--godot-mcp-lsp-port=16005"])

    def test_existing_user_arguments_keep_one_separator(self):
        forwarded = self.launch("--lsp-port", "16005", "--", "--example")
        self.assertEqual(forwarded.count("--"), 1)
        self.assertEqual(forwarded[-2:], ["--example", "--godot-mcp-lsp-port=16005"])


if __name__ == "__main__":
    unittest.main()
