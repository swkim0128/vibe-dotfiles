"""Herdr status failures must stay unknown and native HUD must fail closed."""

import json
import hashlib
import os
import subprocess
import sys
import tempfile
import time
import unittest
from datetime import datetime, timedelta
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

HERDR = Path(__file__).resolve().parents[1] / "herdr"
sys.path.insert(0, str(HERDR))
import hud
import status


class SidebarTests(unittest.TestCase):
    def test_project_alias_prefers_longest_match_and_accepts_linked_worktree(self):
        mappings = [(Path("/repo/shop/ashop"), "ashop"), (Path("/repo/shop"), "shop")]
        self.assertEqual(hud.sidebar_project({"cwd": "/repo/shop/ashop/src"}, mappings), "ashop")
        self.assertEqual(hud.sidebar_project({"cwd": "/worktree/feature", "project_root": "/repo/shop/ashop"}, mappings), "ashop")
        self.assertEqual(hud.sidebar_project({"cwd": "/repo/shop/ashop-extra"}, mappings), "shop")

    def test_current_task_matches_official_session_and_rejects_stale_or_ambiguous_state(self):
        for age, watching, count, expected in ((0, True, 1, "T-A · 첫째 작업"),
                                               (45, True, 1, "유휴"),
                                               (0, False, 1, "유휴"),
                                               (0, True, 2, "유휴")):
            with self.subTest(age=age, watching=watching, count=count):
                native = "11000000-0000-0000-0000-000000000000"
                pane = {"agent": "codex", "agent_status": "idle", "cwd": "/repo",
                        "foreground_cwd": "/repo", "agent_session":
                        {"agent": "codex", "kind": "id", "source": "herdr:codex", "value": native}}
                digest = hashlib.sha256(native.encode()).hexdigest()
                relay = {"schema": 1, "scope": "work", "harness": "codex", "session_id": native,
                         "observation_status": "watching" if watching else "unknown", "revision": 7,
                         "updated_at": (datetime.now().astimezone() - timedelta(seconds=age)).isoformat(),
                         "current": ["r1", "r2"][:count]}
                tasks = [{"task_id": f"T-{letter}", "title": title,
                          "assignments": [{"session_id": native, "harness": "codex", "current_request_id": rid}],
                          "requests": {rid: {"status": "in-progress"}}}
                         for letter, rid, title in (("A", "r1", "첫째 작업"), ("B", "r2", "둘째 작업"))]
                monitor = {"scope": "work", "revision": 7, "tasks": tasks}
                paths = {f"/state/hud/requests/codex-{digest}-work.json": relay,
                         "/state/tracking/work/monitor.json": monitor}
                def read(path):
                    if str(path) not in paths:
                        raise FileNotFoundError(path)
                    return paths[str(path)]
                module = SimpleNamespace(read_json=read, state_directory=lambda _: Path("/state/hud"))
                self.assertEqual(hud.sidebar_task(pane, module, {}), expected)

    def test_queue_relay_uses_exact_owner_wait_and_terminal_generation(self):
        native = "22000000-0000-0000-0000-000000000000"
        pane = {"pane_id": "w1:p2", "agent": "codex", "agent_status": "working", "cwd": "/repo",
                "foreground_cwd": "/repo", "terminal_id": "term_1", "agent_session":
                {"agent": "codex", "kind": "id", "source": "herdr:codex", "value": native}}
        records = [{"id": 83, "owner_tool": "codex", "owner_conversation_id": native,
                    "status": "running", "request_data":
                    {"goal": "EP URL", "control": {"wait": {"kind": "external"}}}}]
        with tempfile.TemporaryDirectory() as directory:
            socket_path = Path(directory) / "herdr.sock"
            hud.publish_sidebar_queue(socket_path, 1, pane, "codex", native, records)
            self.assertEqual(hud.sidebar_task(pane, None, {}, socket_path, 1), "#83 · EP URL · 외부 대기")
            self.assertEqual(hud.sidebar_task({**pane, "terminal_id": "term_2"}, None, {}, socket_path, 1), "작업 미확인")
            self.assertEqual(hud.sidebar_task(pane, None, {}, socket_path, 2), "작업 미확인")
            hud.publish_sidebar_queue(socket_path, 1, pane, "codex", native, records + [{**records[0], "id": 84}])
            self.assertEqual(hud.sidebar_task(pane, None, {}, socket_path, 1), "작업 미확인")
            hud.publish_sidebar_queue(socket_path, 1, pane, "codex", native, [])
            self.assertEqual(hud.sidebar_task(pane, None, {}, socket_path, 1), "작업 미확인")


class DisplayTests(unittest.TestCase):
    def test_dock_missing_empty_stale_and_plain(self):
        with tempfile.TemporaryDirectory() as directory:
            cache = Path(directory)
            self.assertEqual(status.dock(cache, time.time()), "알림?")
            raw = cache / "dock-badges.raw"
            raw.write_text("")
            self.assertEqual(status.dock(cache, time.time()), "알림?")
            raw.write_text("Slack=3\nMail=2")
            self.assertEqual(status.dock(cache, time.time()), "Slack:3 Mail:2")
            os.utime(raw, (1, 1))
            self.assertEqual(status.dock(cache, time.time()), "알림?오래됨")
            raw.unlink()
            raw.mkdir()
            self.assertEqual(status.dock(cache, time.time()), "알림?")

    def test_usage_redacts_provider_data_and_unknown_windows(self):
        payload = [{"provider": "codex", "usage": {"accountEmail": "private",
                    "secondary": {"usedPercent": 81}, "primary": None}}]
        self.assertEqual(status.usage_value(payload), "Codex 주19%")
        self.assertEqual(status.usage_value([]), "CB?데이터없음")
        with tempfile.TemporaryDirectory() as directory:
            with patch.object(status.subprocess, "run", return_value=SimpleNamespace(stdout=json.dumps(payload))):
                self.assertEqual(status.usage(Path(directory), 100), "Codex 주19%")
            saved = (Path(directory) / "herdr-codexbar.json").read_text()
            self.assertNotIn("private", saved)
            self.assertNotIn("accountEmail", saved)

    def test_usage_timeout_missing_binary_and_bad_response(self):
        failures = [(subprocess.TimeoutExpired("codexbar", 8), "CB?시간초과"),
                    (FileNotFoundError(), "CB?미설치"), (ValueError(), "CB?조회실패")]
        for error, expected in failures:
            with self.subTest(expected=expected), tempfile.TemporaryDirectory() as directory:
                with patch.object(status.subprocess, "run", side_effect=error):
                    self.assertEqual(status.usage(Path(directory), 100), expected)

    def test_terminal_formats_and_cell_width(self):
        self.assertEqual(status.plain("#[fg=red]\x1b[31mSlack\n:3"), "Slack:3")
        self.assertEqual(status.plain("한글abc", 5), "한글a…")
        with patch.object(status, "run", return_value="## main...origin/main\n M file"):
            value = status.context({"HERDR_ACTIVE_PANE_ID": "w2:p7", "HERDR_ACTIVE_PANE_CWD": "/tmp/proj"})
            self.assertEqual(value, "w2:p7 proj main*")

    def test_usage_failure_keeps_bounded_last_success_and_marks_stale(self):
        for now, expected in ((200, "Codex 주19%~100s"), (500, "CB 오래됨(400s)")):
            with self.subTest(now=now), tempfile.TemporaryDirectory() as directory:
                cache = Path(directory)
                (cache / "herdr-codexbar.json").write_text(json.dumps(
                    {"at": 100, "label": "Codex 주19%", "good_at": 100, "good_label": "Codex 주19%"}))
                with patch.object(status.subprocess, "run", side_effect=subprocess.TimeoutExpired("cb", 8)):
                    self.assertEqual(status.usage(cache, now), expected)


class IdentityTests(unittest.TestCase):
    def setUp(self):
        self.pane = {"pane_id": "w1:p2", "terminal_id": "terminal-a", "agent": "codex",
                     "agent_session": {"source": "herdr:codex", "agent": "codex", "kind": "id",
                                       "value": "11111111-1111-4111-8111-111111111111"}}

    def call(self, method, **params):
        if method == "pane.process_info":
            return {"process_info": {"shell_pid": 12,
                                      "foreground_processes": [{"name": "codex", "pid": 34}]}}
        return {"pane": self.pane}

    def test_missing_native_ref_and_partial_id_rejected(self):
        for ref in (None, {**self.pane["agent_session"], "value": "11111111"},
                    {**self.pane["agent_session"], "source": "title"}):
            with self.subTest(ref=ref), self.assertRaises(ValueError):
                hud.identity({**self.pane, "agent_session": ref}, self.call)

    def test_exact_native_identity_requires_pane_process_ancestry(self):
        with patch.object(hud, "process_stamp", return_value="stamp"), patch.object(
                hud.subprocess, "run", return_value=SimpleNamespace(stdout="12")):
            identity = hud.identity(self.pane, self.call)
            self.assertEqual(identity, ("codex", self.pane["agent_session"]["value"], 34, "stamp"))
        with patch.object(hud, "process_stamp", return_value="stamp"), patch.object(
                hud.subprocess, "run", return_value=SimpleNamespace(stdout="1")):
            with self.assertRaises(ValueError):
                hud.identity(self.pane, self.call)

    def test_recycled_pid_or_other_conversation_rejected(self):
        module = SimpleNamespace(state_directory=lambda env: Path("/unused"),
                                 session_path=lambda *args: Path("/unused"),
                                 load_state=lambda *args: {"agents": {}, "parent": "unknown", "complete": False},
                                 request_label=lambda *args: "", truncate=lambda text, width: text)
        with patch.object(hud, "identity", return_value=("codex", "native", 34, "original")):
            with patch.object(hud, "process_stamp", return_value="recycled"):
                with self.assertRaises(ValueError):
                    hud.label(self.pane, module, self.call)
            replacement = {"pane": {**self.pane, "terminal_id": "other"}}
            with self.assertRaises(ValueError):
                hud.label(self.pane, module, lambda *args, **kwargs: replacement)

    def test_no_native_mapping_reports_unknown_with_expiry_only(self):
        with tempfile.NamedTemporaryFile() as sock:
            calls = []
            def call(method, **params):
                calls.append((method, params))
                return {"panes": [{"pane_id": "w1:p2", "agent": "codex"}]} if method == "pane.list" else {}
            with patch.dict(os.environ, {"HERDR_ACTIVE_WORKSPACE_ID": "w1", "HERDR_SOCKET_PATH": sock.name}):
                with patch.object(hud, "rpc", side_effect=call):
                    hud.refresh()
            method, params = calls[-1]
            self.assertEqual(method, "pane.report_metadata")
            self.assertEqual(params["tokens"], {"hud": "HUD 미연결"})
            self.assertEqual(params["ttl_ms"], 15000)
            self.assertNotIn("state", params)


if __name__ == "__main__":
    unittest.main()
