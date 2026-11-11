"""Display-only bridge from Herdr's native identity to the existing dashboard HUD."""

import importlib.util
import json
import os
import re
import shlex
import socket
import subprocess
import time
import sys
import urllib.parse
import urllib.request
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


def dashboard_script():
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
    return script


def dashboard():
    script = dashboard_script()
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


class ScopeError(ValueError):
    pass


def subagents(scope):
    """Read lifecycle observations only for an explicitly bound TUI instance."""
    scope["_phase"] = "herdr_scope"
    socket_path = Path(os.environ["HERDR_SOCKET_PATH"])
    generation = socket_path.stat().st_ino
    view = rpc("pane.get", pane_id=scope["view_pane"])["pane"]
    parent = rpc("pane.get", pane_id=scope["parent_pane"])["pane"]
    if os.getppid() != scope["view_pid"]:
        raise ScopeError("not this TUI process")
    view_info = rpc("pane.process_info", pane_id=scope["view_pane"])["process_info"]
    if not any(process.get("pid") == scope["view_pid"]
               for process in view_info["foreground_processes"]):
        raise ScopeError("TUI process outside bound pane")
    if (generation != scope["socket_generation"]
            or view["terminal_id"] != scope["view_terminal"]
            or parent["terminal_id"] != scope["parent_terminal"]
            or parent["tab_id"] != view["tab_id"]
            or parent["workspace_id"] != view["workspace_id"]
            or parent.get("agent_session") != scope["parent_session"]):
        raise ScopeError("TUI scope changed")
    if not parent.get("agent_session"):
        return {"state": "parent_unbound"}
    scope["_phase"] = "parent_identity"
    try:
        harness, native, pid, stamp = identity(parent)
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        raise ScopeError("official parent identity unavailable") from error
    if (harness != "codex" or pid not in scope["parent_cli_pids"]
            or stamp != scope["parent_stamp"]):
        raise ScopeError("parent Codex process changed")
    binding = [native, pid, stamp]
    if scope.get("binding") is not None and scope["binding"] != binding:
        raise ScopeError("parent process recycled")
    base = scope.get("api_url") or os.environ.get("VIBE_SUBAGENTS_API_URL", "")
    if not base:
        scope["_phase"] = "dashboard_config"
        # Locate the registered producer without loading legacy HUD/storage state.
        sys.path.insert(0, str(dashboard_script().resolve().parents[1]))
        from vibe_dashboard.config import load
        base = f"http://127.0.0.1:{load()['port']}"
    url = urllib.parse.urlsplit(base)
    # Lifecycle data is private; never follow redirects or send it off-host.
    if (url.scheme != "http" or url.hostname not in ("127.0.0.1", "localhost", "::1")
            or url.username or url.password or url.query or url.fragment
            or url.path not in ("", "/")):
        return {"state": "unconnected", "binding": binding}

    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, req, fp, code, msg, headers, newurl):
            return None

    endpoint = base.rstrip("/") + "/api/subagents.json?" + urllib.parse.urlencode(
        {"session_id": native, "internal": "1"})
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
    timeout = float(scope.get("http_timeout_seconds", 2))
    if not 0 < timeout <= 10:
        raise ValueError("invalid subagent HTTP deadline")
    scope["_phase"] = "native_http"
    with opener.open(endpoint, timeout=timeout) as response:
        raw = response.read(1048577)
    if len(raw) > 1048576:
        raise ValueError("subagent response too large")
    data = json.loads(raw)
    scope["_phase"] = "native_contract"
    observation = data.get("observation", {})
    kind = observation.get("kind")
    current_provider = kind == "codex-app-server"
    if (data.get("scope") != {"session_id": native}
            or kind not in ("lifecycle", "codex-app-server")
            or not isinstance(data.get("running"), list)
            or not isinstance(data.get("recent"), list)
            or (current_provider and (observation.get("complete") is not True
                or observation.get("parent_loaded") is not True
                or observation.get("coverage") != "direct_children_of_loaded_parent"))
            or (not current_provider and observation.get("complete") is not False)):
        raise ValueError("scoped lifecycle API unavailable")
    for agent in data["running"] + data["recent"]:
        if agent.get("session_id") != native or agent.get("harness") != "codex":
            raise ScopeError("other parent or harness in scoped response")
        if current_provider and agent.get("native_status", {}).get("type") != agent.get("state"):
            raise ValueError("native agent status mismatch")
    if current_provider and any(agent.get("state") != "active" for agent in data["running"]):
        raise ValueError("non-active agent in native running list")
    scope["_phase"] = "herdr_recheck"
    current = rpc("pane.get", pane_id=scope["parent_pane"])["pane"]
    current_view = rpc("pane.get", pane_id=scope["view_pane"])["pane"]
    if (socket_path.stat().st_ino != generation
            or current.get("agent_session") != parent.get("agent_session")
            or current["terminal_id"] != parent["terminal_id"]
            or current["tab_id"] != view["tab_id"]
            or current["workspace_id"] != view["workspace_id"]
            or current_view["terminal_id"] != view["terminal_id"]
            or current_view["tab_id"] != view["tab_id"]
            or identity(current) != (harness, native, pid, stamp)):
        raise ScopeError("TUI occupant changed during read")
    observed = data["observation"]
    scope["_phase"] = "freshness"
    fresh_at = observed["observed_at"] if current_provider else observed["queried_at"]
    queried = datetime.fromisoformat(fresh_at.replace("Z", "+00:00"))
    if queried.tzinfo is None:
        raise ValueError("query timestamp has no timezone")
    age = time.time() - queried.timestamp()
    last = observed.get("last_event_at")
    event_age = None
    if last:
        event_age = time.time() - datetime.fromisoformat(last.replace("Z", "+00:00")).timestamp()
    if not current_provider and data["running"] and event_age is None:
        raise ValueError("running observation has no lifecycle timestamp")
    return {"state": "observed", "binding": binding, "age": age,
            "event_age": event_age, "data": data}


def observation_receipt(scope, result, error_type=None, error_module=None):
    """Keep only stage/type metadata for this exact TUI; no prompts or API payload."""
    try:
        if scope.get("view_pid") != os.getppid() or not re.fullmatch(r"[A-Za-z0-9:_-]+", scope["view_pane"]):
            return
        path = Path(os.environ["HERDR_SOCKET_PATH"]).with_suffix(
            f".vibe-subagents-{scope['socket_generation']}-{scope['view_pane']}.observation.json")
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW, 0o600)
        with os.fdopen(fd, "w") as handle:
            json.dump({"state": result["state"], "phase": scope.get("_phase"),
                       "error_type": error_type, "error_module": error_module,
                       "python_executable": sys.executable,
                       "python_version": list(sys.version_info[:2]), "observed_at": time.time()}, handle)
    except (KeyError, OSError, TypeError):
        pass


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--subagents":
        scope = {}
        error_type = None
        error_module = None
        try:
            scope = json.loads(sys.argv[2])
            result = subagents(scope)
        except ScopeError as error:
            result = {"state": "unconnected", "reason": str(error)}
            error_type = type(error).__name__
        except (KeyError, ValueError, TypeError, ImportError, OSError, subprocess.SubprocessError) as error:
            result = {"state": "failed"}
            error_type = type(error).__name__
            error_module = getattr(error, "name", None)
        observation_receipt(scope, result, error_type, error_module)
        print(json.dumps(result))
    else:
        refresh()
