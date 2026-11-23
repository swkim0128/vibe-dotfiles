"""Display-only bridge from Herdr's native identity to the existing dashboard HUD."""

import importlib.util
import json
import os
import re
import shlex
import socket
import shutil
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
                        if Path(word).name in ("vibe-dashboard-hook.sh", "vibe-dashboard-hook.py"):
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


def bound_parent(scope):
    """Verify the official parent and this exact TUI before reading private state."""
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
            or parent["workspace_id"] != view["workspace_id"]):
        raise ScopeError("TUI scope changed")
    if not parent.get("agent_session"):
        return {"state": "parent_unbound"}
    if parent["agent_session"] != scope["parent_session"]:
        raise ScopeError("parent conversation changed")
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
    return socket_path, generation, view, parent, harness, native, pid, stamp, binding


def recheck_parent(scope, context):
    socket_path, generation, view, parent, harness, native, pid, stamp, _ = context
    scope["_phase"] = "herdr_recheck"
    current = rpc("pane.get", pane_id=scope["parent_pane"])["pane"]
    current_view = rpc("pane.get", pane_id=scope["view_pane"])["pane"]
    if (socket_path.stat().st_ino != generation
            or current.get("agent_session") != parent.get("agent_session")
            or current.get("cwd") != parent.get("cwd")
            or current["terminal_id"] != parent["terminal_id"]
            or current["tab_id"] != view["tab_id"]
            or current["workspace_id"] != view["workspace_id"]
            or current_view["terminal_id"] != view["terminal_id"]
            or current_view["tab_id"] != view["tab_id"]
            or identity(current) != (harness, native, pid, stamp)):
        raise ScopeError("TUI occupant changed during read")


def subagents(scope):
    """Read lifecycle observations only for an explicitly bound TUI instance."""
    context = bound_parent(scope)
    if isinstance(context, dict):
        return context
    _, _, _, _, _, native, _, _, binding = context
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
    recheck_parent(scope, context)
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


def current_task(scope):
    """Project the public queue snapshot without changing any request's owner."""
    context = bound_parent(scope)
    if isinstance(context, dict):
        return context
    _, _, _, parent, _, native, pid, _, binding = context
    info = rpc("pane.process_info", pane_id=scope["parent_pane"])["process_info"]
    processes = [process for process in info["foreground_processes"] if process.get("pid") == pid]
    cwd = parent.get("cwd")
    if (len(processes) != 1 or processes[0].get("cwd") != cwd
            or not isinstance(cwd, str) or not Path(cwd).is_absolute() or not Path(cwd).is_dir()):
        raise ScopeError("parent pane and Codex cwd do not match")
    cli = shutil.which("vibe") or str(Path.home() / ".local/bin/vibe")
    if not os.access(cli, os.X_OK):
        raise ValueError("public vibe queue CLI unavailable")
    timeout = float(scope.get("queue_timeout_seconds", 4))
    if not 0 < timeout <= 10:
        raise ValueError("invalid queue observation deadline")
    deadline = time.monotonic() + timeout

    def read(action, *args):
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError("queue observation deadline")
        result = subprocess.run([cli, "queue", action, *map(str, args), "--tool", "codex",
                                 "--conversation-id", native, "--json"], cwd=cwd,
                                capture_output=True, check=True, timeout=remaining)
        if len(result.stdout) > 1048576:
            raise ValueError("queue response too large")
        return json.loads(result.stdout)

    scope["_phase"] = "queue_list"
    try:
        listed = read("list", "--all")
    except (TimeoutError, subprocess.TimeoutExpired, json.JSONDecodeError, subprocess.CalledProcessError) as error:
        if isinstance(error, subprocess.CalledProcessError) and not re.search(
                r"\bdatabase (?:table )?is (?:locked|busy)\b", error.stderr or "", re.IGNORECASE):
            raise
        recheck_parent(scope, context)
        scope["_phase"] = "queue_list"
        return {"state": "transient_failure", "binding": binding,
                "error_type": type(error).__name__}
    if not isinstance(listed, list):
        raise ValueError("queue list contract unavailable")
    for item in listed:
        if not isinstance(item, dict) or type(item.get("id")) is not int:
            raise ValueError("queue record identity unavailable")
    listed = [item for item in listed
              if not (item.get("status") == "done" and item.get("completion_confirmed") is True)]
    common_definition = scope.get("queue_default_definition")
    if not isinstance(common_definition, dict) or common_definition.get("definition_id") != "common-workflow":
        common_definition = None
    if common_definition is None and any(
           item.get("kind") == "request" and not (item.get("request_data") or {}).get("definition")
           for item in listed):
        try:
            default = read("definition-default")
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
            # Older queue binaries lack the public default definition command.
            default = next((definition for item in listed
                            if (definition := (item.get("request_data") or {}).get("definition"))
                            and definition.get("definition_id") == "common-workflow"), None)
        if isinstance(default, dict) and default.get("definition_id") == "common-workflow":
            common_definition = default
    records = []
    for item in listed:
        scope["_phase"] = "queue_projection"
        full = item
        metadata = full.get("request_data") or {}
        execution = metadata.get("execution")
        record = task_record(full, execution, common_definition if full.get("kind") == "request" else None)
        records.append(record)
    records.sort(key=lambda record: (record["priority"], record["id"]), reverse=True)
    recheck_parent(scope, context)
    return {"state": "observed", "binding": binding, "thread": native,
            "view": "queue", "total": len(listed),
            "queued_count": sum(record["queue_status"] == "queued" for record in records),
            "review_count": sum(record["needs_review"] for record in records),
            "queue_default_definition": common_definition,
            "observed_at": datetime.now().astimezone().isoformat(), "records": records,
            "requests": [{"id": item["id"], "status": item.get("status"),
                          "goal": str((item.get("request_data") or {}).get("goal") or item.get("text") or "")[:240]}
                         for item in listed], "limited": False}


def queue_category(item, metadata):
    note = metadata.get("note_path")
    if isinstance(note, str) and note:
        path = Path(os.path.normpath(os.path.expanduser(note)))
        project = Path.home() / "Project"
        personal_vault = Path(os.environ.get("PERSONAL_PARA_ROOT") or project / "personal" / "PARA").expanduser()
        if path.is_absolute() and path.is_relative_to(personal_vault):
            return "개인"
        if path.is_relative_to(project / "para"):
            return "회사"
    key = item.get("key") or ""
    if key.startswith("personal-"):
        return "개인"
    if key.startswith("work-") or re.fullmatch(r"DWDEV-\d+", key):
        return "회사"
    if item.get("kind") == "request":
        slack_key = re.fullmatch(r"slack-([A-Z0-9]+)-([0-9]{16})", key)
        if slack_key:
            channel, timestamp = slack_key.groups()
            permalink = re.escape(f"https://cowavecc.slack.com/archives/{channel}/p{timestamp}")
            if re.search(rf"(?:^|[\s<(\[]){permalink}(?=$|[\s>)\]?#])", item.get("text") or ""):
                return "회사"
    return "미분류"


def task_record(item, execution, default_definition=None):
    metadata = item.get("request_data") or {}
    execution = execution if isinstance(execution, dict) else {}
    control = metadata.get("control") or {}
    stage = execution.get("current_stage", "request")
    version, attempt = control.get("version"), control.get("attempt")
    valid_run = isinstance(version, str) and bool(version.strip()) and type(attempt) is int and attempt > 0
    events = control.get("events") or []
    result = next((str(event.get("evidence") or "")[:1024] for event in reversed(events)
        if valid_run and isinstance(event, dict) and event.get("kind") == "result"
        and event.get("version") == version and event.get("attempt") == attempt
        and event.get("stage") == stage and event.get("request_id") == item["id"]
        and event.get("owner_tool") == item.get("owner_tool")
        and event.get("owner_thread") == item.get("owner_conversation_id")), "")
    wait = control.get("wait") or {}
    scope_wait = item.get("control_scope") or {}
    if scope_wait.get("paused") == 1:
        wait = {"kind": "user", "reason": scope_wait.get("evidence"),
                "resume_condition": "실제 사용자 답변 후 원담당 scope-resume 필요"}
    queue_status = item.get("status")
    state = {"queued": "큐 대기", "running": "실행 기록", "done": "기록상 완료",
             "failed": "실패 기록"}.get(queue_status, "진척 미확인")
    if wait:
        state = {"user": "Question 대기", "external": "외부 대기"}.get(wait.get("kind"), "의존 대기")
    elif result:
        state = {"done": "기록상 완료", "failed": "실패 기록", "running": "단계 결과 있음"}.get(item.get("status"), state)
    if item.get("status") == "done" and item.get("completion_review") in ("deferred", "changes_requested"):
        state = "검토 보류" if item["completion_review"] == "deferred" else "수정 요청"
    artifacts = []
    for artifact in execution.get("artifacts", []):
        if not isinstance(artifact, dict):
            continue
        confirmations = [confirmation for confirmation in execution.get("confirmations", [])
            if isinstance(artifact.get("stage"), str) and bool(artifact["stage"])
            and confirmation.get("artifact_id") == artifact.get("id")
            and confirmation.get("artifact_version") == artifact.get("version")
            and confirmation.get("stage") == artifact.get("stage")]
        decision = confirmations[-1] if confirmations else {}
        artifacts.append({"id": artifact.get("id"), "stage": artifact.get("stage"), "version": artifact.get("version"),
                          "reference": artifact.get("reference"), "decision": decision.get("decision", "미확인"),
                          "confirmation_reference": decision.get("reference")})
    updated_age = None
    if item.get("updated_at"):
        updated = datetime.fromisoformat(item["updated_at"].replace("Z", "+00:00"))
        if updated.tzinfo is not None:
            updated_age = time.time() - updated.timestamp()
    definition = metadata.get("definition") or default_definition or {}
    stages = definition.get("stages") or []
    completed = execution.get("completed_stages") or []
    stage_ids = [entry.get("id") for entry in stages if isinstance(entry, dict)]
    valid_definition = (bool(metadata.get("definition")) and bool(stage_ids)
                        and all(isinstance(key, str) and key for key in stage_ids)
                        and len(set(stage_ids)) == len(stages)
                        and execution.get("definition_id") == definition.get("definition_id")
                        and execution.get("definition_version") == definition.get("version")
                        and stage in stage_ids and all(key in stage_ids for key in completed))
    stage_recorded = valid_definition and bool(completed or artifacts)
    verify_complete = valid_definition and "verify" in completed
    verify_review = (stage == "verify" and (control.get("wait") or {}).get("kind") == "user")
    final_review = (queue_status == "done" and bool(item.get("completion_token"))
                    and item.get("completion_review") not in ("deferred", "changes_requested"))
    needs_review = verify_complete and item.get("completion_confirmed") is not True and (verify_review or final_review)
    active = queue_status == "running" and not wait
    priority = (4 if needs_review else 3 if active
                else 2 if queue_status == "queued" and stage_recorded and not wait
                else 1 if wait or queue_status in ("queued", "done") else 0)
    if valid_definition and not wait:
        if queue_status == "queued" and stage_recorded:
            state = "단계 기록"
        elif active and stage == "verify":
            state = "검증 완료" if verify_complete else "검증 중"
    if needs_review:
        state = "검증완료·확인대기"
    flow = []
    if valid_definition:
        for key in stage_ids:
            status = "waiting"
            if key in completed:
                status = "completed"
                evidence = [artifact for artifact in execution.get("artifacts", [])
                            if artifact.get("stage") == key and artifact.get("id") == "evidence"]
                latest = max(evidence, key=lambda artifact: artifact.get("version", 0), default={})
                if (definition.get("definition_id") == "common-workflow"
                        and str(latest.get("reference", "")).startswith("not-applicable:")):
                    status = "not_applicable"
            elif key == stage:
                status = ("blocked" if wait else "failed" if item.get("status") == "failed"
                          else "current" if queue_status == "running"
                          else "recorded" if queue_status == "queued" and stage_recorded else "unknown")
            flow.append({"id": key, "state": status})
    elif stage_ids and not execution:
        # Reading old records never fabricates historical stage completion.
        flow = [{"id": key, "state": "waiting" if metadata.get("definition") and item.get("status") == "queued" else "unknown"}
                for key in stage_ids]
    goal = str(metadata.get("goal") or item.get("text") or "")
    return {"id": item["id"], "goal": f"[{queue_category(item, metadata)}] {goal}"[:512],
            "owner_tool": item.get("owner_tool"), "owner_thread": item.get("owner_conversation_id"),
            "completion_confirmed": item.get("completion_confirmed") is True,
            "review_decision": item.get("completion_review"), "kind": item.get("kind"),
            "stage": execution.get("current_stage"), "state": state, "queue_status": queue_status,
            "waiting": bool(wait),
            "needs_review": needs_review, "verify_complete": verify_complete, "priority": priority,
            "completion_token": item.get("completion_token"),
            "wait": str(wait.get("reason") or ""), "result": result,
            "next_action": str((wait.get("resume_condition") or "대기 해소 조건 미기록") if wait
                               else metadata.get("next_action") or "")[:512],
            "version": version, "attempt": attempt, "artifacts": artifacts, "stages": flow,
            "stage_definition": "observed" if valid_definition else "default" if flow else "mismatch" if definition else "undefined",
            "updated_at": item.get("updated_at"), "updated_age": updated_age}


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
    if len(sys.argv) == 3 and sys.argv[1] in ("--subagents", "--current-task"):
        scope = {}
        error_type = None
        error_module = None
        try:
            scope = json.loads(sys.argv[2])
            result = current_task(scope) if sys.argv[1] == "--current-task" else subagents(scope)
        except ScopeError as error:
            result = {"state": "unconnected", "reason": str(error)}
            error_type = type(error).__name__
        except (KeyError, ValueError, TypeError, ImportError, OSError, subprocess.SubprocessError) as error:
            result = {"state": "failed"}
            error_type = type(error).__name__
            error_module = getattr(error, "name", None)
        result["phase"] = scope.get("_phase")
        result["error_type"] = error_type or result.get("error_type")
        observation_receipt(scope, result, result["error_type"], error_module)
        print(json.dumps(result))
    else:
        refresh()
