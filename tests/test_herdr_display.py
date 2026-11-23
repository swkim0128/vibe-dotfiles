"""Herdr status failures must stay unknown and native HUD must fail closed."""

import json
import os
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

HERDR = Path(__file__).resolve().parents[1] / "herdr"
sys.path.insert(0, str(HERDR))
import hud
import status


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


class QueueDisplayTests(unittest.TestCase):
    def setUp(self):
        self.definition = {"definition_id": "common-workflow", "version": 1,
                           "stages": [{"id": "plan"}, {"id": "verify"}]}
        self.execution = {"definition_id": "common-workflow", "definition_version": 1,
                          "current_stage": "verify", "completed_stages": ["plan"]}
        self.item = {"id": 84, "kind": "request", "key": "personal-test", "status": "running",
                     "owner_tool": "codex", "owner_conversation_id": "recorded-owner",
                     "request_data": {"definition": self.definition}}

    def test_scn_84_01_assignment_and_verify_follow_queue_record(self):
        record = hud.task_record(self.item, self.execution)
        self.assertEqual((record["owner_tool"], record["owner_thread"]), ("codex", "recorded-owner"))
        self.assertEqual((record["stage"], record["state"]), ("verify", "검증 단계"))
        self.assertEqual(record["stages"][1], {"id": "verify", "state": "current"})
        self.item["status"] = "queued"
        record = hud.task_record(self.item, self.execution)
        self.assertEqual((record["queue_status"], record["state"]), ("queued", "단계 기록"))
        self.assertEqual(record["stages"][1], {"id": "verify", "state": "recorded"})

    def test_scn_84_02_wait_preserves_entire_reason(self):
        reason = "긴 의존 사유 " * 80 + "\n마지막 조건"
        self.item["request_data"]["control"] = {"wait": {"kind": "external", "reason": reason}}
        record = hud.task_record(self.item, self.execution)
        self.assertEqual((record["state"], record["waiting"], record["wait"]), ("의존 대기", True, reason))
        self.assertEqual(record["stages"][1], {"id": "verify", "state": "blocked"})
        self.item["control_scope"] = {"paused": 1, "evidence": "사용자 선택 대기"}
        record = hud.task_record(self.item, self.execution)
        self.assertEqual((record["state"], record["wait"]), ("Question 대기", "사용자 선택 대기"))

    def test_scn_84_03_legacy_row_retains_unknown_stage_flow(self):
        self.item["request_data"] = {}
        self.item["status"] = "queued"
        record = hud.task_record(self.item, None, self.definition)
        self.assertTrue(record["goal"].startswith("[개인]"))
        self.assertEqual([stage["state"] for stage in record["stages"]], ["unknown", "unknown"])


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
