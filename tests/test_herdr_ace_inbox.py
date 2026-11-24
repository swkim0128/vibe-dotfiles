"""Exercise the real stdio client with a fixture Ace MCP server."""

from pathlib import Path
import json
import os
import subprocess
import sys
import tempfile
import unittest

COLLECTOR = Path(__file__).resolve().parents[1] / "herdr/runtime/ace_inbox.py"
SERVER = r'''
import json
import os
import sys
from pathlib import Path

root = Path(os.environ["FIXTURE_ROOT"])
for line in sys.stdin:
    request = json.loads(line)
    with (root / "methods.jsonl").open("a") as log:
        print(json.dumps(request), file=log)
    method, sequence = request["method"], request.get("id")
    if method == "initialize":
        result = {"protocolVersion": "2025-03-26"}
    elif method == "notifications/initialized":
        continue
    elif method == "tools/call":
        assert request["params"] == {
            "name": "get_inbox", "arguments": {"unread_only": True, "limit": 1},
        }
        state = (root / "fixture-state").read_text()
        if state == "failed":
            result = {"isError": True}
        elif state == "malformed":
            result = {"structuredContent": {"items": None}}
        elif state == "unread":
            result = {"structuredContent": {"items": [{"title": "private notification"}]}}
        else:
            result = {"content": [{"type": "text", "text": '{"items":[]}'}]}
    else:
        raise AssertionError(method)
    print(json.dumps({"jsonrpc": "2.0", "id": sequence, "result": result}), flush=True)
'''


class AceInboxTest(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        server = self.root / "fixture.py"
        server.write_text(SERVER)
        self.config = self.root / "config.toml"
        self.config.write_text(
            '[mcp_servers.ace]\ncommand = ' + json.dumps(sys.executable)
            + '\nargs = [' + json.dumps(str(server)) + ']\n'
        )
        self.cache = self.root / "cache" / "ace-inbox.json"
        self.methods = self.root / "methods.jsonl"

    def refresh(self, fixture_state=None, expire=False):
        if fixture_state is not None:
            (self.root / "fixture-state").write_text(fixture_state)
        if expire:
            cache = json.loads(self.cache.read_text())
            cache["at"] -= 61
            self.cache.write_text(json.dumps(cache))
        env = {**os.environ, "CODEX_HOME": str(self.root), "FIXTURE_ROOT": str(self.root)}
        subprocess.run([sys.executable, "-I", COLLECTOR, self.cache], env=env,
                       check=True, capture_output=True, timeout=12)
        record = json.loads(self.cache.read_text())
        self.assertEqual(set(record), {"state", "at"})
        return record["state"]

    def test_empty_unread_failure_and_recovery(self):
        for index, state in enumerate(("empty", "unread", "failed", "empty")):
            self.assertEqual(self.refresh(state, expire=index > 0), state)
        requests = [json.loads(line) for line in self.methods.read_text().splitlines()]
        self.assertEqual([row["method"] for row in requests],
                         ["initialize", "notifications/initialized", "tools/call"] * 4)
        self.assertNotIn("private notification", self.cache.read_text())

    def test_malformed_and_cached_result(self):
        self.assertEqual(self.refresh("unread"), "unread")
        self.assertEqual(self.refresh("malformed"), "unread")
        self.assertEqual(len(self.methods.read_text().splitlines()), 3)
        self.assertEqual(self.refresh(expire=True), "failed")

    def test_unconfigured_profile_does_not_start_ace(self):
        self.config.unlink()
        self.assertEqual(self.refresh(), "unconfigured")
        self.assertFalse(self.methods.exists())


if __name__ == "__main__":
    unittest.main()
