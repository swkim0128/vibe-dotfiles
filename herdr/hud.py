"""Display-only bridge from Herdr's native identity to the existing dashboard HUD."""

import importlib.util
import json
import os
import re
import shlex
import socket
import subprocess
import time
from datetime import datetime
from pathlib import Path


def rpc(method, **params):
    path = os.environ.get("HERDR_SOCKET_PATH")
    if not path:
        raise ValueError("no Herdr socket context")
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
        client.settimeout(0.3)
        client.connect(path)
        client.sendall((json.dumps({"id": "vibe-display", "method": method,
                                    "params": params}) + "\n").encode())
        raw = bytearray()
        while b"\n" not in raw and len(raw) < 1048576:
            chunk = client.recv(65536)
            if not chunk:
                break
            raw.extend(chunk)
        response = json.loads(raw)
        if "error" in response:
            raise ValueError("Herdr API rejected display request")
        return response["result"]


def dashboard():
    configured = os.environ.get("VIBE_DASHBOARD_HUD_SCRIPT")
    if configured:
        script = Path(configured).expanduser()
    else:
        # Locate the installed producer from the user's actual hook registration.
        # This discovers code, never a conversation from cwd/title/recency.
        settings = Path.home() / ".codex/hooks.json"
        hooks = json.loads(settings.read_text()).get("hooks", {})
        scripts = set()
        for groups in hooks.values():
            for group in groups:
                for hook in group.get("hooks", []):
                    for word in shlex.split(hook.get("command", "")):
                        if Path(word).name == "vibe-dashboard-hook.sh":
                            scripts.add(Path(word).expanduser().resolve().with_name("hud_state.py"))
        if len(scripts) != 1:
            raise ValueError("HUD producer not uniquely installed")
        script = scripts.pop()
    spec = importlib.util.spec_from_file_location("herdr_dashboard_hud", script)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    from vibe_dashboard.config import load
    module.configure(load())
    return module


def process_stamp(pid):
    result = subprocess.run(["ps", "-p", str(pid), "-o", "lstart=", "-o", "comm="],
                            capture_output=True, text=True, check=True, timeout=0.3)
    if not result.stdout.strip():
        raise ValueError("CLI ended")
    return result.stdout.strip()


def identity(pane, call=rpc):
    ref = pane.get("agent_session") or {}
    harness = pane.get("agent")
    native = ref.get("value", "")
    if (harness not in ("codex", "claude") or ref.get("agent") != harness
            or ref.get("kind") != "id" or not re.fullmatch(r"[0-9a-fA-F-]{36}", native)
            or ref.get("source") != f"herdr:{harness}"):
        raise ValueError("official full native identity missing")
    info = call("pane.process_info", pane_id=pane["pane_id"])["process_info"]
    processes = [p for p in info["foreground_processes"]
                 if Path(p.get("name", "")).name == harness]
    if len(processes) != 1:
        raise ValueError("foreground CLI is not unique")
    pid = processes[0]["pid"]
    stamp = process_stamp(pid)
    cursor = pid
    for _ in range(32):
        if cursor == info["shell_pid"]:
            break
        parent = subprocess.run(["ps", "-p", str(cursor), "-o", "ppid="],
                                capture_output=True, text=True, check=True, timeout=0.3)
        cursor = int(parent.stdout.strip())
        if cursor <= 1:
            raise ValueError("CLI outside pane ancestry")
    else:
        raise ValueError("pane ancestry exceeded bound")
    return harness, native, pid, stamp


def label(pane, module, call=rpc):
    harness, native, pid, stamp = identity(pane, call)
    directory = module.state_directory(os.environ)
    obj = module.load_state(module.session_path(directory, harness, native), harness, native)
    if obj.get("updated_at"):
        age = (datetime.now().astimezone() - datetime.fromisoformat(obj["updated_at"])).total_seconds()
        if age < 0 or age > 60:
            raise ValueError("HUD snapshot stale")
    running = [agent for agent in obj["agents"].values() if agent["status"] == "running"]
    known = obj["complete"] and all(a["status"] != "unknown" for a in obj["agents"].values())
    text = f"서브 {len(running)}" if known else "서브 미확인"
    if not known and running:
        text += f"(관측 {len(running)})"
    text += " · 부모 " + {"active": "실행", "idle": "대기", "ended": "종료"}.get(obj["parent"], "미확인")
    text += module.request_label(directory, harness, native) or " · 요청 미연결"
    # Revalidate the live occupant after storage reads; never carry a label across
    # a pane move, replacement, socket generation change or recycled CLI PID.
    current = call("pane.get", pane_id=pane["pane_id"])["pane"]
    if (current["terminal_id"] != pane["terminal_id"]
            or current.get("agent_session") != pane.get("agent_session")
            or process_stamp(pid) != stamp):
        raise ValueError("occupant changed")
    return module.truncate(text, 88)


def project_title(pane, path, cwd):
    if pane["agent"] != "codex":
        return f"{pane['agent']} · {path}"
    try:
        result = subprocess.run(["git", "-C", cwd, "branch", "--show-current"],
                                capture_output=True, text=True, check=True, timeout=0.3)
        branch = result.stdout.strip()
    except (OSError, subprocess.SubprocessError):
        branch = ""
    native = pane.get("terminal_title_stripped") or pane.get("terminal_title") or ""
    details = native.partition(" | ")[2]
    if branch and details.startswith(branch + " | "):
        details = details[len(branch) + 3:]
    model, _, task = details.partition(" | ")
    return f"{path} | {branch or '-'} | {model or '모델 미확인'} | {task or '작업 제목 미확인'}"


def refresh_paths():
    try:
        panes = rpc("pane.list")["panes"]
        home = str(Path.home())
        for pane in panes:
            if not pane.get("agent"):
                continue
            cwd = pane.get("foreground_cwd") or pane.get("cwd")
            if not cwd:
                continue
            path = "~" + cwd[len(home):] if cwd == home or cwd.startswith(home + "/") else cwd
            rpc("pane.report_metadata", pane_id=pane["pane_id"], source="vibe:project",
                agent=pane["agent"], title=project_title(pane, path, cwd),
                tokens={"project_path": path}, seq=time.time_ns(), ttl_ms=15000)
    except (OSError, ValueError, KeyError, TypeError):
        return


def refresh_status(tokens):
    try:
        workspaces = rpc("workspace.list")["workspaces"]
        for workspace in workspaces:
            rpc("workspace.report_metadata", workspace_id=workspace["workspace_id"],
                source="vibe:status", tokens=tokens, seq=time.time_ns(), ttl_ms=15000)
    except (OSError, ValueError, KeyError, TypeError):
        return


def refresh():
    workspace = os.environ.get("HERDR_ACTIVE_WORKSPACE_ID")
    if not workspace:
        return
    try:
        socket_path = Path(os.environ["HERDR_SOCKET_PATH"])
        generation = socket_path.stat().st_ino
        panes = rpc("pane.list", workspace_id=workspace)["panes"]
        module = None
        for pane in panes:
            if not pane.get("agent"):
                continue
            text = "HUD 미연결"
            if pane.get("agent_session"):
                try:
                    module = module or dashboard()
                    text = label(pane, module)
                except (OSError, ValueError, KeyError, TypeError, ImportError,
                        RuntimeError, subprocess.SubprocessError):
                    text = "HUD 연결 미확인"
            if socket_path.stat().st_ino != generation:
                return
            rpc("pane.report_metadata", pane_id=pane["pane_id"], source="vibe:display",
                tokens={"hud": text}, seq=time.time_ns(), ttl_ms=15000)
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError):
        # Existing metadata expires; no false zero or semantic state update.
        return


if __name__ == "__main__":
    refresh()
