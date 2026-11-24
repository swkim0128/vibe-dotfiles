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
    def test_project_mapping_does_not_use_issue_alias_as_project_name(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "terminal-backends.json").write_text(json.dumps({"project_mappings": ["projects.txt"]}))
            (root / "projects.txt").write_text("DWDEV-2959|/repo/BillingMPAdmin|issue\nBillingMPAdmin|/repo/BillingMPAdmin|repo\n")
            with patch.dict(os.environ, {"VIBE_TOOLS_DIR": directory,
                                         "VIBE_TERMINAL_BACKENDS": str(root / "terminal-backends.json")}):
                self.assertEqual(hud.project_names(), [(Path("/repo/BillingMPAdmin"), "BillingMPAdmin")])

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
        self.assertEqual((record["stage"], record["state"]), ("verify", "검증 중"))
        self.assertEqual((record["needs_review"], record["priority"]), (False, 3))
        self.assertEqual(record["stages"][1], {"id": "verify", "state": "current"})
        self.item["status"] = "queued"
        record = hud.task_record(self.item, self.execution)
        self.assertEqual((record["queue_status"], record["state"]), ("queued", "단계 기록"))
        self.assertEqual(record["stages"][1], {"id": "verify", "state": "recorded"})
        self.assertEqual(record["priority"], 2)

    def test_scn_84_02_wait_preserves_entire_reason(self):
        reason = "긴 의존 사유 " * 80 + "\n마지막 조건"
        self.item["request_data"]["control"] = {"wait": {"kind": "external", "reason": reason}}
        record = hud.task_record(self.item, self.execution)
        self.assertEqual((record["state"], record["waiting"], record["wait"]), ("외부 대기", True, reason))
        self.assertEqual(record["stages"][1], {"id": "verify", "state": "blocked"})
        self.assertEqual(record["priority"], 1)
        self.item["control_scope"] = {"paused": 1, "evidence": "사용자 선택 대기"}
        record = hud.task_record(self.item, self.execution)
        self.assertEqual((record["state"], record["wait"]), ("Question 대기", "사용자 선택 대기"))

    def test_verification_dependency_wait_keeps_its_label(self):
        self.item["request_data"]["control"] = {"wait": {"kind": "verification", "reason": "검증 자료 대기"}}
        record = hud.task_record(self.item, self.execution)
        self.assertEqual((record["state"], record["priority"]), ("의존 대기", 1))

    def test_scn_84_03_legacy_row_retains_unknown_stage_flow(self):
        self.item["request_data"] = {}
        self.item["status"] = "queued"
        record = hud.task_record(self.item, None, self.definition)
        self.assertTrue(record["goal"].startswith("[개인]"))
        self.assertEqual([stage["state"] for stage in record["stages"]], ["unknown", "unknown"])

    def test_company_slack_origin_requires_request_key_and_matching_permalink(self):
        item = {"kind": "request", "key": "slack-C123ABC-1794460950000000"}
        origin = "https://cowavecc.slack.com/archives/C123ABC/p1794460950000000"
        item["text"] = f"Slack 요청 <{origin}?thread_ts=1794460000.000000>"
        self.assertEqual(hud.queue_category(item, {}), "회사")
        for unexpected in (
            origin.replace("cowavecc.slack.com", "other.slack.com"),
            origin.replace("cowavecc.slack.com", "cowavecc.slack.com.example.org"),
            origin.replace("C123ABC", "C123XYZ"),
            origin[:-1] + "1",
            origin + "1",
        ):
            with self.subTest(origin=unexpected):
                self.assertEqual(hud.queue_category({**item, "text": unexpected}, {}), "미분류")
        self.assertEqual(hud.queue_category({**item, "kind": "command"}, {}), "미분류")

    def test_vault_and_explicit_key_classification_still_take_precedence(self):
        item = {"kind": "request", "key": "slack-C123ABC-1794460950000000",
                "text": "https://cowavecc.slack.com/archives/C123ABC/p1794460950000000"}
        personal = Path.home() / "Project" / "personal" / "PARA"
        with patch.dict(os.environ, {"PERSONAL_PARA_ROOT": str(personal)}):
            self.assertEqual(hud.queue_category(item, {"note_path": str(personal / "note.md")}), "개인")
        self.assertEqual(hud.queue_category({**item, "key": "personal-example"}, {}), "개인")
        self.assertEqual(hud.queue_category({**item, "key": "DWDEV-1000"}, {}), "회사")

    def test_verify_requires_current_completion_evidence_before_review_priority(self):
        self.item.update(status="done", completion_token="v1", completion_confirmed=False)
        self.assertFalse(hud.task_record(self.item, self.execution)["needs_review"])
        self.execution["completed_stages"].append("verify")
        record = hud.task_record(self.item, self.execution)
        self.assertEqual((record["priority"], record["state"]), (4, "검증완료·확인대기"))
        self.item["completion_review"] = "deferred"
        self.assertEqual(hud.task_record(self.item, self.execution)["priority"], 1)
        self.item["completion_review"] = None
        self.execution["definition_version"] = 2
        self.assertFalse(hud.task_record(self.item, self.execution)["needs_review"])

    def test_projection_hides_confirmed_and_reuses_definition(self):
        context = (None, None, None, {"cwd": str(HERDR)}, None, "thread", 1, None, ["thread"])
        completed = {**self.execution, "completed_stages": ["plan", "verify"]}
        waiting = {"definition": self.definition, "execution": self.execution,
                   "control": {"wait": {"kind": "external", "reason": "waiting"}}}
        rows = [
            {**self.item, "id": 6, "status": "queued", "request_data": {}},
            {**self.item, "id": 83, "request_data": waiting},
            {**self.item, "id": 8, "request_data": {"definition": self.definition, "execution": self.execution}},
            {**self.item, "id": 4, "status": "done", "completion_token": "v1",
             "request_data": {"definition": self.definition, "execution": completed}},
            {**self.item, "id": 9, "status": "done", "completion_confirmed": True},
        ]
        def read(args, **kwargs):
            return SimpleNamespace(stdout=json.dumps(rows if args[2] == "list" else self.definition))
        with patch.object(hud, "bound_parent", return_value=context), patch.object(hud, "recheck_parent"), \
                patch.object(hud, "rpc", return_value={"process_info": {"foreground_processes": [
                    {"pid": 1, "cwd": str(HERDR)}]}}), patch.object(hud.os, "access", return_value=True), \
                patch.object(hud.subprocess, "run", side_effect=read) as read_cli:
            first = hud.current_task({"parent_pane": "fixture"})
            second = hud.current_task({"parent_pane": "fixture",
                                       "queue_default_definition": first["queue_default_definition"]})
        self.assertEqual([row["id"] for row in second["records"]], [4, 8, 83, 6])
        self.assertEqual((second["records"][2]["state"], second["records"][2]["queue_status"]),
                         ("외부 대기", "running"))
        self.assertEqual(second["review_count"], 1)
        self.assertEqual([call.args[0][2] for call in read_cli.call_args_list],
                         ["list", "definition-default", "list"])

    def test_transient_queue_errors_recheck_parent_before_returning_binding(self):
        binding = ["thread", 1, "stamp"]
        context = (None, None, None, {"cwd": str(HERDR)}, None, "thread", 1, "stamp", binding)
        rpc = {"process_info": {"foreground_processes": [{"pid": 1, "cwd": str(HERDR)}]}}
        errors = [
            subprocess.TimeoutExpired("vibe", 4),
            subprocess.CalledProcessError(2, "vibe", stderr='{"error":"database is locked"}'),
        ]
        with patch.object(hud, "bound_parent", return_value=context), patch.object(hud, "rpc", return_value=rpc), \
                patch.object(hud.os, "access", return_value=True), patch.object(hud, "recheck_parent") as recheck, \
                patch.object(hud.subprocess, "run") as read:
            for error in errors:
                with self.subTest(error=type(error).__name__):
                    recheck.reset_mock()
                    read.side_effect = error
                    outcome = hud.current_task({"parent_pane": "fixture"})
                    self.assertEqual((outcome["state"], outcome["binding"]), ("transient_failure", binding))
                    recheck.assert_called_once()
            read.side_effect = None
            read.return_value = SimpleNamespace(stdout="{")
            self.assertEqual(hud.current_task({"parent_pane": "fixture"})["error_type"], "JSONDecodeError")
            read.side_effect = subprocess.CalledProcessError(2, "vibe", stderr="authorization failed")
            recheck.reset_mock()
            with self.assertRaises(subprocess.CalledProcessError):
                hud.current_task({"parent_pane": "fixture"})
            recheck.assert_not_called()
            read.side_effect = subprocess.TimeoutExpired("vibe", 4)
            recheck.side_effect = hud.ScopeError("parent conversation changed")
            with self.assertRaises(hud.ScopeError):
                hud.current_task({"parent_pane": "fixture"})


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
