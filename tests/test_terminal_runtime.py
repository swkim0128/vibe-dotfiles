import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parents[1] / "vibe-tools"
spec = importlib.util.spec_from_file_location("terminal_runtime", HERE / "terminal_runtime.py")
runtime = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runtime)


class RuntimeTests(unittest.TestCase):
    """General terminal behavior: real temporary files, provider calls doubled."""

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.home = Path(self.temp.name)
        self.env = patch.dict(os.environ, {"HOME": str(self.home), "PATH": os.environ["PATH"]}, clear=True)
        self.env.start()
        self.config = self.home / ".config/vibe-tools/terminal-runtime.json"
        self.config.parent.mkdir(parents=True)


    def tearDown(self):
        self.env.stop()
        self.temp.cleanup()


    def configured(self, **changes):
        cfg = {"version": 1, "terminal": "ghostty", "multiplexer": "herdr", "herdr_session": "personal", "notifications": "auto", "display": {"title_mode": "osc", "hud_enabled": True}}
        cfg.update(changes)
        self.config.write_text(json.dumps(cfg))
        return runtime.settings()


    def backend_fixture(self):
        file = self.home / "terminal-backends.json"
        data = json.loads((HERE / "terminal-backends.json").read_text())
        file.write_text(json.dumps(data))
        return file, data


    def test_definition_changes_binary_prefix_and_native_argv_without_code_changes(self):
        cfg = self.configured()
        file, data = self.backend_fixture()
        data["tools"]["herdr"]["binary"] = "alternate-herdr"
        provider = data["providers"]["herdr"]
        provider["prefix_external"] = ["{binary}", "--named", "{session}"]
        provider["operations"]["pane_run"]["argv"] = ["terminal", "execute", "{command}", "--target", "{pane}"]
        file.write_text(json.dumps(data))
        command = 'printf "%s" "$(literal); {untouched}"'
        with patch.dict(os.environ, {"VIBE_TERMINAL_BACKENDS": str(file)}), patch.object(runtime.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, "", "")) as run:
            self.assertEqual(runtime.native(cfg, "pane_run", pane="w2:p9", command=command), {})
            self.assertEqual(runtime.settings()["definitions_path"], str(file.resolve()))
        self.assertEqual(run.call_args.args[0], ["alternate-herdr", "--named", "personal", "terminal", "execute", command, "--target", "w2:p9"])


    def test_definition_drives_provider_mapping_required_tools_apps_and_context(self):
        file, data = self.backend_fixture()
        tool = self.home / "Applications/Alternate.app/Contents/MacOS/alternate"
        tool.parent.mkdir(parents=True)
        tool.write_text("fixture")
        tool.chmod(0o755)
        data["tools"]["alternate_host"] = {"binary": "not-on-path", "app_candidates": ["~/Applications/Alternate.app/Contents/MacOS/alternate"]}
        provider = data["providers"]["herdr"]
        provider["terminal"] = "alternate_host"
        provider["required_tools"] = ["alternate_host", "herdr"]
        provider["context_env"] = {"NATIVE_TERMINAL_TEST": "active"}
        file.write_text(json.dumps(data))
        with patch.dict(os.environ, {"VIBE_TERMINAL_BACKENDS": str(file), "HERDR_ENV": "1"}), patch.object(runtime.shutil, "which", side_effect=lambda name: None if name == "not-on-path" else "/bin/" + name), contextlib.redirect_stdout(io.StringIO()):
            runtime.select_runtime("herdr")
            cfg = runtime.settings()
            self.assertFalse(cfg["herdr_context"])
            self.assertEqual(cfg["terminal"], "alternate_host")
            self.assertEqual(cfg["tool_paths"]["alternate_host"], str(tool))
            with patch.dict(os.environ, {"NATIVE_TERMINAL_TEST": "active", "TMUX": "stale", "TMUX_PANE": "%1"}):
                self.assertTrue(runtime.settings()["herdr_context"])
            tool.unlink()
            before = self.config.read_bytes()
            with self.assertRaisesRegex(ValueError, "alternate_host"):
                runtime.select_runtime("herdr")
            self.assertEqual(self.config.read_bytes(), before)


    def test_provider_alias_uses_existing_native_contract_from_definition_only(self):
        file, data = self.backend_fixture()
        alias = json.loads(json.dumps(data["providers"]["herdr"]))
        alias.update(multiplexer="native-alias", context_env={"NATIVE_ALIAS_TEST": "1"})
        alias["operations"]["pane_list"]["argv"] = ["alias-pane", "enumerate"]
        data["providers"]["native-alias"] = alias
        data["context_priority"].insert(0, "native-alias")
        file.write_text(json.dumps(data))
        with patch.dict(os.environ, {"VIBE_TERMINAL_BACKENDS": str(file)}), patch.object(runtime.shutil, "which", side_effect=lambda name: "/bin/" + name), contextlib.redirect_stdout(io.StringIO()):
            runtime.select_runtime("native-alias")
            cfg = runtime.settings()
            self.assertEqual(cfg["saved_multiplexer"], "native-alias")
            response = subprocess.CompletedProcess([], 0, '{"result":{"panes":[]}}', '')
            with patch.object(runtime.subprocess, "run", return_value=response) as run:
                self.assertEqual(runtime.native(cfg, "pane_list"), {"panes": []})
            self.assertEqual(run.call_args.args[0], ["herdr", "--session", "personal", "alias-pane", "enumerate"])
            with patch.dict(os.environ, {"NATIVE_ALIAS_TEST": "1", "TMUX": "stale", "TMUX_PANE": "%1"}):
                self.assertEqual(runtime.settings()["multiplexer"], "native-alias")


    def test_open_launcher_uses_definition_script_prefix_and_environment_rules(self):
        cfg = self.configured()
        file, data = self.backend_fixture()
        launch = data["providers"]["herdr"]["open"]
        launch.update(script="alternate.applescript", command_prefix=["/custom/env"], unset_prefixes=["OLD_"], attach_argv=["{binary}", "--connect", "{session}"])
        data["tools"]["osascript"]["binary"] = "alternate-osascript"
        file.write_text(json.dumps(data))
        with patch.dict(os.environ, {"VIBE_TERMINAL_BACKENDS": str(file), "OLD_CONTEXT": "stale", "KEEP_CONTEXT": "value"}), patch.object(runtime.shutil, "which", return_value="/path/herdr"), patch.object(runtime.subprocess, "run") as run, contextlib.redirect_stdout(io.StringIO()):
            runtime.open_ghostty(cfg)
        args = run.call_args.args[0]
        self.assertEqual(args[:2], ["alternate-osascript", str(HERE / "alternate.applescript")])
        command = shlex.split(args[2])
        self.assertEqual(command[0], "/custom/env")
        self.assertEqual(command[-3:], ["/path/herdr", "--connect", "personal"])
        self.assertNotIn("OLD_CONTEXT", run.call_args.kwargs["env"])
        self.assertEqual(run.call_args.kwargs["env"]["KEEP_CONTEXT"], "value")


    def test_missing_file_legacy_and_environment_override(self):
        self.assertEqual(runtime.settings()["multiplexer"], "tmux")
        with patch.dict(os.environ, {"VIBE_TERMINAL": "ghostty", "VIBE_MULTIPLEXER": "herdr"}):
            self.assertEqual(runtime.settings()["multiplexer"], "herdr")


    def test_selection_preserves_symlink_and_unmanaged_values_and_overrides(self):
        self.configured(extra={"keep": True}, notifications="off", herdr_session="other")
        target = self.config.with_name("real.json")
        self.config.rename(target)
        self.config.symlink_to(target.name)
        before = json.loads(target.read_text())
        with patch.object(runtime.shutil, "which", side_effect=lambda name: "/bin/" + name), patch.dict(os.environ, {"VIBE_TERMINAL": "ghostty", "VIBE_MULTIPLEXER": "herdr"}), contextlib.redirect_stdout(io.StringIO()) as out:
            runtime.select_runtime("tmux")
        self.assertTrue(self.config.is_symlink())
        after = json.loads(target.read_text())
        self.assertEqual(after, {**before, "terminal": "cmux", "multiplexer": "tmux"})
        status = json.loads(out.getvalue())
        self.assertEqual(status["saved_multiplexer"], "tmux")
        self.assertEqual(status["multiplexer"], "herdr")
        self.assertEqual(status["config_path"], str(self.config))
        self.assertEqual(status["tool_paths"]["tmux"], "/bin/tmux")


    def test_selection_first_file_and_missing_tool_or_invalid_file_preserved(self):
        with patch.object(runtime.shutil, "which", return_value="/bin/tool"), contextlib.redirect_stdout(io.StringIO()):
            runtime.select_runtime("herdr")
            runtime.select_runtime("herdr")
        before = self.config.read_bytes()
        with patch.object(runtime, "tool_path", side_effect=lambda name: None if name == "cmux" else "/bin/tool"):
            with self.assertRaisesRegex(ValueError, "cmux"):
                runtime.select_runtime("tmux")
        self.assertEqual(self.config.read_bytes(), before)
        self.config.write_text("{")
        with self.assertRaises(ValueError):
            runtime.select_runtime("herdr")
        self.assertEqual(self.config.read_text(), "{")
        with patch.dict(os.environ, {"VIBE_TERMINAL_CONFIG": ""}), self.assertRaisesRegex(ValueError, "비활성화"):
            runtime.select_runtime("herdr")
        with self.assertRaises(ValueError):
            runtime.select_runtime("other")


    def test_ghostty_app_install_without_path_binary_is_supported(self):
        executable = self.home / "Applications/Ghostty.app/Contents/MacOS/ghostty"
        executable.parent.mkdir(parents=True)
        executable.write_text("fixture")
        executable.chmod(0o755)
        with patch.object(runtime.shutil, "which", side_effect=lambda name: None if name == "ghostty" else "/bin/" + name), patch.object(runtime.os, "access", side_effect=lambda path, _mode: Path(path).is_relative_to(self.home)), contextlib.redirect_stdout(io.StringIO()):
            runtime.select_runtime("herdr")
            self.assertEqual(runtime.settings()["tool_paths"]["ghostty"], str(executable))
            runtime.dispatch(runtime.settings(), ["terminal", "check"])


    def test_herdr_in_cmux_keeps_host_identity_but_routes_only_herdr(self):
        self.configured(terminal="cmux", multiplexer="tmux")
        with patch.dict(os.environ, {"HERDR_ENV": "1", "CMUX_WORKSPACE_ID": "w", "CMUX_SURFACE_ID": "s", "TMUX": "stale", "TMUX_PANE": "%1"}):
            cfg = runtime.settings()
        self.assertEqual(cfg["actual_host"], "cmux")
        self.assertEqual(cfg["multiplexer"], "herdr")
        self.assertEqual(cfg["saved_multiplexer"], "tmux")


    def shell_fixture(self, **changes):
        pane = {"pane_id": "w2:p3", "tab_id": "w2:t3", "workspace_id": "w2", "terminal_id": "term_exec", "cwd": str(self.home), "foreground_cwd": str(self.home), "agent": None}
        pane.update(changes)
        info = {"pane_id": pane["pane_id"], "shell_pid": 123, "foreground_process_group_id": 123, "foreground_processes": [{"pid": 123, "name": "zsh", "argv0": "zsh", "argv": ["-zsh"], "cwd": str(self.home)}]}
        tab = {"tab_id": pane["tab_id"], "wspace_id": "w2", "number": 3, "pane_count": 1, "label": "exec·" + self.home.name}
        return pane, info, tab


    # [CLI-07] Preserve the general terminal safety contract.
    def test_run_reuses_only_managed_idle_shell_and_literal_command(self):
        cfg = self.configured()
        cfg["herdr_context"] = True
        pane, info, tab = self.shell_fixture()
        command = 'printf "%s" "a; $(echo literal)"'
        calls = []
        def api(_cfg, operation, **params):
            calls.append((operation, params))
            if operation == "pane_current":
                return {"pane": {"pane_id": "w2:p1", "workspace_id": "w2"}}
            if operation == "tab_list":
                return {"tabs": [tab]}
            if operation == "workspace_panes":
                return {"panes": [pane]}
            if operation == "pane_process_info":
                return {"process_info": info}
            self.assertEqual((operation, params), ("pane_run", {"pane": "w2:p3", "command": command}))
            return {}
        with patch.dict(os.environ, {"HERDR_PANE_ID": "w2:p1"}), patch.object(runtime, "execution_project", return_value=(self.home.name, self.home)), patch.object(runtime, "ensure_workspace", return_value=("w2", False)) as ensure, patch.object(runtime, "native", side_effect=api), contextlib.redirect_stdout(io.StringIO()) as out:
            self.assertEqual(runtime.peek_run(cfg, self.home, command), 0)
        ensure.assert_called_once_with(cfg, "CLI 실행", Path.home().resolve(), reuse_verified_anchor=True)
        self.assertIn(("workspace_panes", {"workspace": "w2"}), calls)
        self.assertIn(("pane_process_info", {"pane": "w2:p3"}), calls)
        self.assertEqual(json.loads(out.getvalue()), {"workspace_id": "w2", "pane_id": "w2:p3", "tab_id": "w2:t3", "created": False, "cwd": str(self.home), "command": command, "submitted": True, "completion": "unknown"})


    # [CLI-07] Preserve the general terminal safety contract.
    def test_run_blocks_unsafe_or_ambiguous_project_tabs_without_creating(self):
        for change in ("agent", "busy", "cwd", "caller", "duplicate", "split"):
            with self.subTest(change=change):
                cfg = self.configured()
                cfg["herdr_context"] = True
                pane, info, tab = self.shell_fixture()
                if change == "agent":
                    pane["agent"] = "codex"
                if change == "busy":
                    info["foreground_processes"].append({"pid": 456, "name": "vim"})
                if change == "cwd":
                    pane["foreground_cwd"] = "/other"
                if change == "caller":
                    pane["pane_id"] = "w2:p1"
                if change == "split":
                    tab["pane_count"] = 2
                calls = []
                def api(_cfg, operation, **params):
                    calls.append((operation, params))
                    if operation == "pane_current":
                        return {"pane": {"pane_id": "w2:p1", "workspace_id": "w2"}}
                    if operation == "tab_list":
                        return {"tabs": [tab, {**tab, "tab_id": "w2:t4"}] if change == "duplicate" else [tab]}
                    if operation == "workspace_panes":
                        return {"panes": [pane]}
                    if operation == "pane_process_info":
                        return {"process_info": info}
                    self.fail(f"Unexpected mutation: {operation} {params}")
                with patch.dict(os.environ, {"HERDR_PANE_ID": "w2:p1"}), patch.object(runtime, "execution_project", return_value=(self.home.name, self.home)), patch.object(runtime, "ensure_workspace", return_value=("w2", False)), patch.object(runtime, "native", side_effect=api), self.assertRaises(ValueError):
                    runtime.peek_run(cfg, self.home, "test command")
                self.assertFalse(any(c[0] in ("tab_create", "pane_run") for c in calls))


    # [CLI-07] Preserve the general terminal safety contract.
    def test_run_created_tab_requires_ready_shell_and_uses_returned_ids(self):
        cfg = self.configured()
        cfg["herdr_context"] = True
        pane, info, tab = self.shell_fixture()
        calls = []
        def api(_cfg, operation, **params):
            calls.append((operation, params))
            if operation == "pane_current":
                return {"pane": {"pane_id": "w2:p1", "workspace_id": "w2"}}
            if operation == "tab_list":
                return {"tabs": []}
            if operation == "tab_create":
                return {"tab": tab, "root_pane": pane}
            if operation == "workspace_panes":
                return {"panes": [pane]}
            if operation == "pane_process_info":
                return {"process_info": info}
            return {}
        with patch.dict(os.environ, {"HERDR_PANE_ID": "w2:p1"}), patch.object(runtime, "execution_project", return_value=(self.home.name, self.home)), patch.object(runtime, "ensure_workspace", return_value=("w2", False)), patch.object(runtime, "native", side_effect=api), contextlib.redirect_stdout(io.StringIO()) as out:
            runtime.peek_run(cfg, self.home, "pwd")
        self.assertTrue(json.loads(out.getvalue())["created"])
        self.assertEqual(calls[-1], ("pane_run", {"pane": "w2:p3", "command": "pwd"}))
        info["foreground_processes"] = []
        with patch.dict(os.environ, {"HERDR_PANE_ID": "w2:p1"}), patch.object(runtime, "execution_project", return_value=(self.home.name, self.home)), patch.object(runtime, "ensure_workspace", return_value=("w2", False)), patch.object(runtime, "native", side_effect=api), patch.object(runtime.time, "monotonic", side_effect=[0, 4]), self.assertRaises(ValueError):
            runtime.peek_run(cfg, self.home, "pwd")


    def test_xdg_config_and_explicit_empty_config_path(self):
        xdg = self.home / "custom-config"
        file = xdg / "vibe-tools/terminal-runtime.json"
        file.parent.mkdir(parents=True)
        self.configured()
        file.write_text(self.config.read_text())
        self.config.unlink()
        with patch.dict(os.environ, {"XDG_CONFIG_HOME": str(xdg)}):
            self.assertEqual(runtime.settings()["multiplexer"], "herdr")
            with patch.dict(os.environ, {"VIBE_TERMINAL_CONFIG": ""}):
                self.assertEqual(runtime.settings()["multiplexer"], "tmux")


    def test_json_rpc_error_is_not_a_successful_mutation(self):
        cfg = self.configured()
        response = subprocess.CompletedProcess([], 0, '{"error":{"message":"not applied"}}', '')
        with patch.object(runtime.subprocess, "run", return_value=response) as run:
            with self.assertRaises(ValueError):
                runtime.native(cfg, "workspace_list")
            self.assertEqual(run.call_count, 1)


    # [CLI-06] Preserve the general terminal safety contract.
    def test_reused_workspace_id_with_different_generation_cannot_reconnect(self):
        cfg = self.configured()
        state = self.home / ".local/state/vibe-tools"
        state.mkdir(parents=True)
        key = json.dumps(["personal", "project", str(self.home)])
        (state / "herdr-workspaces.json").write_text(json.dumps({key: {"workspace_id": "w1", "terminal_id": "old-generation"}}))
        calls = []
        def api(_cfg, operation, **params):
            calls.append((operation, params))
            if operation == "workspace_list":
                return {"workspaces": [{"workspace_id": "w1", "label": "project"}]}
            return {"panes": [{"terminal_id": "new-generation", "cwd": "/different/project"}]}
        with patch.object(runtime, "native", side_effect=api):
            with self.assertRaises(ValueError):
                runtime.ensure_workspace(cfg, "project", self.home)
        self.assertFalse(any(c[0] in ("workspace_create", "workspace_focus") for c in calls))


    def test_native_run_accepts_empty_ack_without_claiming_completion(self):
        cfg = self.configured()
        response = subprocess.CompletedProcess([], 0, "", "")
        with patch.object(runtime.subprocess, "run", return_value=response) as run:
            self.assertEqual(runtime.native(cfg, "pane_run", pane="w2:p3", command="pwd"), {})
        self.assertEqual(run.call_args.args[0], ["herdr", "--session", "personal", "pane", "run", "w2:p3", "pwd"])
        response = subprocess.CompletedProcess([], 0, '{"error":{"message":"not admitted"}}', '')
        with patch.object(runtime.subprocess, "run", return_value=response), self.assertRaises(ValueError):
            runtime.native(cfg, "pane_run", pane="w2:p3", command="pwd")


    def test_invalid_file_values_and_unsupported_combination(self):
        for changed in ({"version": True}, {"notifications": "wrong"}, {"terminal": "cmux"}, {"herdr_session": "--other"}):
            with self.subTest(changed=changed), self.assertRaises(ValueError):
                self.configured(**changed)
        self.config.write_text("{")
        with self.assertRaises(ValueError):
            runtime.settings()


    def test_context_has_priority_and_display_is_ignored(self):
        self.configured(terminal="cmux", multiplexer="tmux")
        with patch.dict(os.environ, {"HERDR_ENV": "1"}):
            self.assertEqual(runtime.settings()["multiplexer"], "herdr")
            self.assertEqual(runtime.settings()["configured_terminal"], "cmux")
        self.assertEqual(self.configured()["terminal"], "ghostty")


    # [CLI-06] Preserve the general terminal safety contract.
    def test_create_and_reconnect_use_exact_path_and_do_not_type(self):
        cfg = self.configured()
        path = self.home / "project with spaces"
        path.mkdir()
        calls = []
        live = []
        def api(_cfg, operation, **params):
            calls.append((operation, params))
            if operation == "workspace_list":
                return {"workspaces": live.copy()}
            if operation == "workspace_panes":
                self.assertEqual(params, {"workspace": "opaque-workspace"})
                return {"panes": [{"terminal_id": "terminal-generation", "cwd": str(path)}]}
            self.assertEqual((operation, params), ("workspace_create", {"cwd": str(path), "label": "project"}))
            live.append({"workspace_id": "opaque-workspace", "label": "project"})
            return {"workspace": live[0]}
        with patch.object(runtime, "native", side_effect=api):
            self.assertEqual(runtime.ensure_workspace(cfg, "project", path), ("opaque-workspace", True))
            self.assertEqual(runtime.ensure_workspace(cfg, "project", path), ("opaque-workspace", False))
        self.assertEqual(len([c for c in calls if c[0] == "workspace_create"]), 1)


    # [CLI-06] Preserve the general terminal safety contract.
    def test_unknown_previous_creation_is_not_repeated(self):
        cfg = self.configured()
        with patch.object(runtime, "native", return_value={"workspaces": [{"workspace_id": "w-existing", "label": "project"}]}):
            with self.assertRaises(ValueError):
                runtime.ensure_workspace(cfg, "project", self.home)


    def test_ghostty_uses_argv_and_clears_old_context(self):
        cfg = self.configured()
        with patch.dict(os.environ, {"TMUX": "old", "CMUX_OTHER": "old", "HERDR_ENV": "1"}), patch.object(runtime.shutil, "which", return_value="/binary with spaces/herdr"), patch.object(runtime.subprocess, "run") as run, contextlib.redirect_stdout(io.StringIO()):
            runtime.open_ghostty(cfg)
        args = run.call_args.args[0]
        self.assertEqual(args[:2], ["osascript", str(HERE / "ghostty-open.applescript")])
        command = shlex.split(args[2])
        self.assertEqual(command[-3:], ["/binary with spaces/herdr", "--session", "personal"])
        self.assertIn("CMUX_OTHER", command)
        self.assertNotIn("TMUX", run.call_args.kwargs["env"])
        self.assertNotIn("HERDR_ENV", run.call_args.kwargs["env"])



class PublicCliTests(unittest.TestCase):
    """CLI-01~03 and CLI-06: real dotfiles CLI, temporary files/provider double."""

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name).resolve()
        self.config = self.home / "config.json"
        self.config.write_text(json.dumps({"version": 1, "terminal": "ghostty", "multiplexer": "herdr",
                                           "herdr_session": "fixture", "notifications": "auto"}))
        self.env = {"HOME": str(self.home), "PATH": os.environ["PATH"],
                    "VIBE_TERMINAL_CONFIG": str(self.config), "VIBE_ROUTE_PYTHON": sys.executable,
                    "VIBE_RUNTIME_STATE_DIR": str(self.home / "state")}

    def invoke(self, args):
        return subprocess.run(["bash", str(HERE / "vibe-terminal.sh"), *args], env=self.env,
                              capture_output=True, text=True, timeout=10)

    def test_CLI_01_settings_and_backend_publish_only_general_contract(self):
        result = self.invoke(["settings"])
        self.assertEqual(result.returncode, 0, result.stderr)
        cfg = json.loads(result.stdout)
        self.assertEqual((cfg["terminal"], cfg["multiplexer"], cfg["herdr_context"]), ("ghostty", "herdr", False))
        self.assertEqual(cfg["paths"]["state_dir"], str(self.home / "state"))
        result = self.invoke(["backend"])
        self.assertEqual(result.returncode, 0, result.stderr)
        backend = json.loads(result.stdout)
        self.assertEqual(backend["providers"]["herdr"]["operations"]["pane_run"],
                         {"argv": ["pane", "run", "{pane}", "{command}"], "response": "empty_ack"})
        self.assertNotIn("clients", backend)
        self.assertFalse(any(key.startswith("agent_") for key in backend["providers"]["herdr"]["operations"]))
        self.assertFalse((self.home / "state").exists())

    def test_CLI_02_invalid_selection_fails_without_replacing_file_or_creating_state(self):
        for content in ("{", '{"version":2}', '[]'):
            with self.subTest(content=content):
                self.config.write_text(content)
                result = self.invoke(["start", "fixture", str(self.home)])
                self.assertEqual(result.returncode, 2, result.stderr)
                self.assertEqual(self.config.read_text(), content)
                self.assertFalse((self.home / "state").exists())

    def test_CLI_03_public_path_commands_cancel_and_unsupported_exit(self):
        path = self.home / "project with spaces; $(literal)"
        path.mkdir()
        result = self.invoke(["project-path", str(path)])
        self.assertEqual((result.returncode, result.stdout), (0, str(path) + "\n"), result.stderr)
        tools = self.home / "tools"
        tools.mkdir()
        raw = 'literal $(value); {command}\nsecond line\n'
        (tools / "commands_common.txt").write_text(raw)
        self.env["VIBE_TOOLS_DIR"] = str(tools)
        result = self.invoke(["commands", "common"])
        self.assertEqual((result.returncode, result.stdout), (0, raw), result.stderr)
        fake = self.home / "bin"
        fake.mkdir()
        (fake / "fzf").write_text("#!/bin/sh\nexit 130\n")
        (fake / "fzf").chmod(0o755)
        (tools / "sessionizer-paths.txt").write_text(str(self.home) + "\n")
        self.env["PATH"] = str(fake) + os.pathsep + self.env["PATH"]
        result = self.invoke(["select-project"])
        self.assertEqual((result.returncode, result.stdout), (0, ""), result.stderr)
        result = self.invoke(["unsupported-command"])
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("vibe-terminal", result.stderr)
        self.assertFalse((self.home / "state").exists())

    def test_CLI_06_explicit_start_creates_once_then_reuses(self):
        # Given: the public CLI with a recording general provider executable.
        fake = self.home / "fake-herdr"
        fake.write_text("#!" + sys.executable + "\n" + '''
import json
from pathlib import Path
import sys
home = Path(__file__).parent
args = sys.argv[1:]
if args[:1] == ["--session"]:
    args = args[2:]
with (home / "calls.jsonl").open("a") as out:
    out.write(json.dumps(args) + "\\n")
record = home / "server.json"
workspace = {"workspace_id": "w3", "label": "regression-project"}
if args[:2] == ["workspace", "list"]:
    result = {"workspaces": [workspace] if record.exists() else []}
elif args[:2] == ["workspace", "create"]:
    record.write_text(args[args.index("--cwd") + 1])
    result = {"workspace": workspace}
elif args[:2] == ["pane", "list"]:
    result = {"panes": [{"terminal_id": "created-generation", "cwd": record.read_text()}]}
else:
    raise SystemExit("Unexpected mutation: " + repr(args))
print(json.dumps({"result": result}))
''')
        fake.chmod(0o755)
        backend = json.loads((HERE / "terminal-backends.json").read_text())
        backend["tools"]["herdr"]["binary"] = str(fake)
        file = self.home / "backend.json"
        file.write_text(json.dumps(backend))
        self.env["VIBE_TERMINAL_BACKENDS"] = str(file)
        path = self.home / "project with spaces"
        path.mkdir()
        # When: request the same workspace twice through the public shell entrypoint.
        for created in (True, False):
            result = self.invoke(["start", "regression-project", str(path)])
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads(result.stdout), {"workspace_id": "w3", "created": created,
                                                       "cwd": str(path), "attach": "vibe-terminal open"})
        # Then: exactly one creation with literal path/name, followed by generation checks.
        self.assertEqual([json.loads(line) for line in (self.home / "calls.jsonl").read_text().splitlines()], [
            ["workspace", "list"], ["workspace", "create", "--cwd", str(path), "--label", "regression-project", "--no-focus"],
            ["pane", "list", "--workspace", "w3"], ["workspace", "list"], ["pane", "list", "--workspace", "w3"]])


if __name__ == "__main__":
    unittest.main()
