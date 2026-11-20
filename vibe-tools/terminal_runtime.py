#!/usr/bin/env python3
"""Dotfiles-owned terminal selection and general workspace commands."""
import argparse
import fcntl
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
INSPECT = "vibe-terminal status"


def definitions_path():
    return Path(os.environ.get("VIBE_TERMINAL_BACKENDS", str(HERE / "terminal-backends.json"))).expanduser()


def definitions():
    data = json.loads(definitions_path().read_text())
    if not isinstance(data, dict) or data.get("version") != 1 or not data.get("providers"):
        raise ValueError("terminal-backends.json version 또는 provider 정의가 없습니다")
    return data


def render(argv, values):
    return [str(values[token[1:-1]]) if token.startswith("{") else token for token in argv]



def matches_context(mapping):
    return all(bool(os.environ.get(key)) if value == "*" else os.environ.get(key) == value for key, value in mapping.items())



def tool_path(name):
    tool = definitions()["tools"][name]
    binary = shutil.which(tool["binary"])
    if binary:
        return binary
    for path in tool["app_candidates"]:
        candidate = Path(path).expanduser()
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return str(candidate)
    return None



def runtime_paths():
    specs = definitions()["paths"]
    values = {"home": str(Path.home()), "config_home": str(Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config")), "state_home": str(Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state"))}

    def resolve(name, allow_empty=False):
        spec = specs[name]
        template = os.environ.get(spec["env"], spec["default"]) if allow_empty else os.environ.get(spec["env"]) or spec["default"]
        if allow_empty and template == "":
            return ""
        expanded = re.sub(r"\{([a-z_]+)\}", lambda match: values.get(match[1], "{invalid}"), template)
        path = Path(expanded).expanduser()
        if not template or "{" in expanded or "}" in expanded or not path.is_absolute():
            raise ValueError("실행 경로는 절대경로여야 합니다. 기본 경로 확인: " + shlex.join(["env", "-u", spec["env"], "-u", "XDG_CONFIG_HOME", "-u", "XDG_STATE_HOME", "vibe-terminal", "status"]))
        return str(path)

    selection = resolve("selection_file", allow_empty=True)
    return {"selection_file": selection, **{name: resolve(name) for name in specs if name != "selection_file"}}



def config_path():
    return runtime_paths()["selection_file"]



def settings():
    backend = definitions()
    path = config_path()
    cfg = dict(backend["defaults"])
    cfg["terminology"] = {"aliases": {}}
    if path and Path(path).exists():
        raw = json.loads(Path(path).read_text())
        if not isinstance(raw, dict) or not backend["defaults"].keys() <= raw.keys():
            raise ValueError("terminal-runtime.json 필수 실행 선택 키가 없습니다")
        cfg.update({key: raw[key] for key in backend["defaults"]})
        cfg["terminology"] = raw.get("terminology", {"aliases": {}})
    terminology = cfg["terminology"]
    if not isinstance(terminology, dict) or set(terminology) - {"aliases"}:
        raise ValueError("terminal-runtime.json terminology에는 aliases만 선언합니다")
    aliases = terminology.get("aliases", {})
    if not isinstance(aliases, dict) or any(not isinstance(values, list) or any(not isinstance(value, str) or not value.strip() for value in values) for values in aliases.values()):
        raise ValueError("사용자 별칭은 공통 개념별 문자열 목록이어야 합니다")
    cfg["saved_terminal"] = cfg["terminal"]
    cfg["saved_multiplexer"] = cfg["multiplexer"]
    cfg["terminal"] = os.environ.get("VIBE_TERMINAL", cfg["terminal"])
    cfg["multiplexer"] = os.environ.get("VIBE_MULTIPLEXER", cfg["multiplexer"])
    if type(cfg["version"]) is not int or cfg["version"] != 1:
        raise ValueError("terminal-runtime.json version은 1이어야 합니다")
    if cfg["multiplexer"] not in backend["providers"]:
        raise ValueError("terminal 또는 multiplexer 값이 지원되지 않습니다")
    if not isinstance(cfg["herdr_session"], str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,63}", cfg["herdr_session"]):
        raise ValueError("herdr_session 이름이 올바르지 않습니다")
    if cfg["notifications"] not in ("auto", "herdr", "cmux", "off"):
        raise ValueError("notifications는 auto|herdr|cmux|off여야 합니다")
    if cfg["terminal"] != backend["providers"][cfg["multiplexer"]]["terminal"]:
        raise ValueError("지원 조합은 terminal-backends.json의 provider 매핑을 확인하세요")
    actual_provider = next((name for name in backend["context_priority"] if matches_context(backend["providers"][name]["context_env"])), None)
    actual = actual_provider is not None and backend["providers"][actual_provider]["execution"] == "native"
    cfg["configured_terminal"] = cfg["terminal"]
    cfg["configured_multiplexer"] = cfg["multiplexer"]
    cfg["actual_host"] = next((name for name in backend["host_priority"] if matches_context(backend["tools"][name]["context_env"])), "unknown")
    cfg["actual_multiplexer"] = backend["providers"][actual_provider]["multiplexer"] if actual_provider else "unknown"
    if actual_provider:
        cfg["terminal"] = backend["providers"][actual_provider]["terminal"]
        cfg["multiplexer"] = backend["providers"][actual_provider]["multiplexer"]
    cfg["herdr_context"] = actual
    cfg["provider_context"] = actual_provider == cfg["multiplexer"]
    cfg["config_path"] = path
    cfg["definitions_path"] = str(definitions_path().resolve())
    cfg["config_exists"] = bool(path and Path(path).exists())
    cfg["config_source"] = "file" if cfg["config_exists"] else "defaults" if path else "disabled"
    cfg["tool_paths"] = {name: tool_path(name) for name in backend["tools"]}
    cfg["paths"] = runtime_paths()
    return cfg



def select_runtime(choice):
    backend = definitions()
    if choice not in backend["providers"]:
        raise ValueError("사용법: vibe-terminal use " + "|".join(backend["providers"]))
    path = config_path()
    if not path:
        raise ValueError("VIBE_TERMINAL_CONFIG가 비어 저장이 비활성화돼 있습니다. 설정 경로를 지정하세요")
    # Validate the saved file independently of temporary environment overrides.
    overrides = {k: os.environ.pop(k) for k in ("VIBE_TERMINAL", "VIBE_MULTIPLEXER") if k in os.environ}
    try:
        cfg = settings()
    finally:
        os.environ.update(overrides)
    provider = backend["providers"][choice]
    missing = [name for name in provider["required_tools"] if not tool_path(name)]
    if missing:
        raise ValueError("선택을 저장하지 않았습니다. 필요한 실행 파일이 없습니다: " + ", ".join(missing))
    destination = Path(path).expanduser().resolve()
    raw = json.loads(destination.read_text()) if destination.exists() else {key: cfg[key] for key in ("version", "herdr_session", "notifications")}
    raw.update(terminal=provider["terminal"], multiplexer=provider["multiplexer"])
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", dir=destination.parent, prefix=".terminal-runtime-", delete=False) as out:
            temporary = out.name
            json.dump(raw, out, ensure_ascii=False, indent=2)
            out.write("\n")
            out.flush()
            os.fsync(out.fileno())
        os.replace(temporary, destination)
    finally:
        if temporary and Path(temporary).exists():
            Path(temporary).unlink()
    print(json.dumps(settings(), ensure_ascii=False))



def native(cfg, operation, *, timeout=20, extra_argv=(), **params):
    backend = definitions()
    provider = backend["providers"][cfg["multiplexer"]]
    if operation not in provider.get("operations", {}):
        raise ValueError("선택 provider의 미지원 동작: " + operation + ". 지원·대체 명령: vibe-terminal backend")
    definition = provider["operations"][operation]
    values = {"binary": backend["tools"][provider["tool"]]["binary"], "session": cfg["herdr_session"], **params}
    prefix = render(provider["prefix_current"] if cfg.get("provider_context", cfg["herdr_context"]) else provider["prefix_external"], values)
    args = [*render(definition["argv"], values), *extra_argv]
    result = subprocess.run([*prefix, *args], capture_output=True, text=True, timeout=timeout)
    if result.returncode:
        try:
            failure = json.loads(result.stderr or result.stdout)
        except ValueError:
            failure = {}
        error = failure.get("error", {}) if isinstance(failure, dict) else {}
        if not isinstance(error, dict):
            error = {}
        if isinstance(error, dict) and error.get("code") == "timeout":
            raise subprocess.TimeoutExpired([*prefix, *args], timeout)
        raise ValueError("선택 provider 명령 실패: " + str(error.get("code", result.returncode)) + ". 문맥 확인: " + INSPECT)
    if definition["response"] == "text":
        return result.stdout
    if definition["response"] == "empty_ack" and not result.stdout.strip():
        return {}  # Native run acknowledges admission with exit 0 and no JSON body.
    packet = json.loads(result.stdout)
    if not isinstance(packet, dict) or packet.get("ok") is False or "error" in packet:
        raise ValueError("provider 응답을 확인하지 못했습니다. 변경 명령을 자동 재시도하지 마세요. 확인: " + INSPECT)
    result = packet.get("result", packet)
    if not isinstance(result, (dict, list)):
        raise ValueError("provider result 형식이 다릅니다. 변경 명령을 자동 재시도하지 마세요. 확인: " + INSPECT)
    return result



def project_path(target):
    direct = Path(target).expanduser()
    if direct.is_dir():
        return direct.resolve()
    config = Path(runtime_paths()["tools_dir"])
    for filename in definitions()["project_mappings"]:
        file = config / filename
        if not file.is_file():
            continue
        for line in file.read_text().splitlines():
            fields = line.split("|")
            if len(fields) > 1 and fields[0].strip() == target:
                value = fields[1].strip().replace("${HOME}", str(Path.home())).replace("$HOME", str(Path.home()))
                path = Path(value).expanduser()
                if path.is_dir():
                    return path.resolve()
    raise ValueError("프로젝트 경로를 확인할 수 없습니다. vibe-terminal start NAME /absolute/path 또는 vibe-terminal peek /absolute/path를 사용하세요")



def workspaces(cfg):
    result = native(cfg, "workspace_list")
    values = result.get("workspaces") if isinstance(result, dict) else result
    if not isinstance(values, list) or any(not isinstance(v, dict) or not isinstance(v.get("workspace_id"), str) for v in values):
        raise ValueError("Herdr workspace 목록 형식이 다릅니다. 상태를 확인한 뒤 재시도하세요")
    return values



def workspace_panes(cfg, identity):
    result = native(cfg, "workspace_panes", workspace=identity)
    values = result.get("panes") if isinstance(result, dict) else None
    if not isinstance(values, list) or any(not isinstance(p, dict) for p in values):
        raise ValueError("Herdr pane 목록 형식이 다릅니다. 기존 workspace를 자동 재사용하지 않습니다")
    return values



def ensure_workspace(cfg, name, path):
    # Per-session mapping prevents duplicate creation and detects an uncertain prior create.
    state = Path(runtime_paths()["state_dir"])
    state.mkdir(mode=0o700, parents=True, exist_ok=True)
    context_keys = definitions()["providers"][cfg["multiplexer"]]["context_keys"]
    scope = cfg["herdr_session"] if not cfg["herdr_context"] else os.environ.get(context_keys["scope"], "current-context")
    key = json.dumps([scope, name, str(path)])
    with (state / "herdr-workspaces.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        file = state / "herdr-workspaces.json"
        saved = json.loads(file.read_text()) if file.exists() else {}
        if not isinstance(saved, dict):
            raise ValueError("Herdr 로컬 연결 기록의 형식이 다릅니다. 파일을 보존하고 workspace list로 확인하세요")
        live = workspaces(cfg)
        record = saved.get(key, {})
        existing = next((w for w in live if isinstance(record, dict) and w["workspace_id"] == record.get("workspace_id")), None)
        if existing:
            # terminal_id is an API-issued generation anchor. w1 alone can be reused
            # after a server restart, so ID, label, original cwd and anchor must agree.
            panes = workspace_panes(cfg, existing["workspace_id"])
            anchor = next((p for p in panes if p.get("terminal_id") == record.get("terminal_id")), None)
            if anchor and existing.get("label") == name and anchor.get("cwd") == str(path):
                return existing["workspace_id"], False
            if anchor:
                raise unsupported(cfg, "기존 workspace의 이름 또는 cwd가 바뀌어 재사용하지 않았습니다")
        collision = next((w for w in live if w.get("label") == name), None)
        if collision:
            raise unsupported(cfg, "같은 이름의 관리되지 않은 workspace가 있어 중복 생성하지 않았습니다")
        result = native(cfg, "workspace_create", cwd=str(path), label=name)
        workspace = result.get("workspace", {})
        identity = workspace.get("workspace_id")
        if not isinstance(identity, str) or not identity:
            raise ValueError("생성 결과의 workspace ID가 없습니다. workspace list로 확인하고 자동 재생성하지 마세요")
        panes = workspace_panes(cfg, identity)
        anchor = next((p for p in panes if p.get("cwd") == str(path) and isinstance(p.get("terminal_id"), str)), None)
        if not anchor:
            raise ValueError("새 workspace의 실제 cwd/terminal ID를 확인하지 못했습니다. workspace list로 확인하고 재생성하지 마세요")
        saved[key] = {"workspace_id": identity, "terminal_id": anchor["terminal_id"]}
        temporary = file.with_suffix(".tmp")
        with temporary.open("x") as out:
            json.dump(saved, out)
        os.replace(temporary, file)
        return identity, True



def open_ghostty(cfg):
    backend = definitions()
    provider = backend["providers"][cfg["multiplexer"]]
    launch = provider["open"]
    binary = tool_path(provider["tool"])
    if not binary:
        raise ValueError("herdr 실행 파일이 없습니다. 설치 후 vibe-terminal check를 실행하세요")
    removed = set(launch["unset_env"])
    removed.update(k for k in os.environ if any(k.startswith(prefix) for prefix in launch["unset_prefixes"]) and k not in launch["keep_env"])
    command = list(launch["command_prefix"])
    for key in sorted(removed):
        command += [launch["unset_flag"], key]
    command += render(launch["attach_argv"], {"binary": binary, "session": cfg["herdr_session"]})
    environment = {k: v for k, v in os.environ.items() if k not in removed}
    # AppleScript receives data through argv; it only creates a new tab/window.
    script = HERE / launch["script"]
    try:
        subprocess.run([backend["tools"][launch["runner_tool"]]["binary"], str(script), shlex.join(command), str(Path.cwd())], env=environment, check=True, timeout=30)
    except subprocess.SubprocessError as error:
        alternate = ["open", "-na", "Ghostty.app", "--args", "--working-directory=" + str(Path.cwd()), "-e", *command]
        raise ValueError("Ghostty 새 화면을 만들지 못했습니다. OS 권한 확인 후 직접 실행: " + shlex.join(alternate)) from error
    print("Ghostty 새 화면에서 Herdr session에 접속합니다. 기존 대화는 이동·재시작하지 않습니다")



def tabs(cfg, workspace):
    result = native(cfg, "tab_list", workspace=workspace)
    values = result.get("tabs") if isinstance(result, dict) else None
    if not isinstance(values, list) or any(not isinstance(t, dict) for t in values):
        raise unsupported(cfg, "현재 workspace의 tab 목록을 확인하지 못했습니다")
    return values



def idle_shell(cfg, pane, path):
    if pane.get("agent") or pane.get("cwd") != str(path) or pane.get("foreground_cwd") != str(path):
        return False
    info = native(cfg, "pane_process_info", pane=pane["pane_id"]).get("process_info", {})
    if not isinstance(info, dict):
        return False
    processes = info.get("foreground_processes", [])
    pid = info.get("shell_pid")
    return (isinstance(processes, list) and len(processes) == 1 and isinstance(processes[0], dict)
            and type(pid) is int and pid > 0 and info.get("pane_id") == pane["pane_id"]
            and info.get("foreground_process_group_id") == pid and len(processes) == 1
            and processes[0].get("pid") == pid and processes[0].get("cwd") == str(path)
            and processes[0].get("name") in ("zsh", "bash", "fish", "sh", "dash", "ksh")
            and Path(str(processes[0].get("argv0", "")).lstrip("-")).name == processes[0].get("name"))



def peek_context(cfg, path, command=None):
    provider = definitions()["providers"][cfg["multiplexer"]]
    context_keys = provider["context_keys"]
    invocation = ["vibe-terminal", "peek", str(path)] + (["run", command] if command is not None else [])
    alternative = "선택 provider의 실행 셸에서 실행: " + shlex.join(invocation) + ". 문맥 확인: " + INSPECT
    popup_keys = provider["command_context_keys"]
    popup = not os.environ.get(context_keys["pane"]) and os.environ.get(popup_keys["pane"])
    if popup:
        socket = os.environ.get(context_keys["scope"])
        if not socket or not Path(socket).is_socket() or not all(os.environ.get(key) for key in popup_keys.values()):
            raise ValueError("팝업의 호출 pane·tab·workspace·소켓 문맥이 없습니다. " + alternative)
        popup_cfg = {**cfg, "provider_context": True}
        matches = [pane for pane in native(popup_cfg, "pane_list").get("panes", [])
                   if pane.get("pane_id") == popup
                   and pane.get("workspace_id") == os.environ[popup_keys["workspace"]]
                   and pane.get("tab_id") == os.environ[popup_keys["tab"]]]
        if len(matches) != 1:
            raise ValueError("팝업의 원래 pane·tab·workspace를 확인하지 못해 생성하지 않았습니다. " + alternative)
        current = matches[0]
        cfg["provider_context"] = True  # 이후 탭 생성도 확인한 팝업 소켓을 사용한다.
    else:
        if not cfg["herdr_context"]:
            result = native(cfg, "pane_list")
            panes = result.get("panes") if isinstance(result, dict) else None
            if not isinstance(panes, list) or any(not isinstance(pane, dict) for pane in panes):
                raise ValueError("프로젝트 경로를 대조할 pane 목록을 확인하지 못했습니다. " + alternative)
            matches = {pane.get("workspace_id") for pane in panes
                       if (pane.get("foreground_cwd") or pane.get("cwd")) == str(path)}
            if any(not isinstance(workspace, str) or not workspace for workspace in matches):
                raise ValueError("프로젝트 경로에 연결된 workspace ID가 미확인입니다. " + alternative)
            if len(matches) > 1:
                raise ValueError("프로젝트 경로가 여러 workspace에 있어 실행 위치를 선택하지 않았습니다. " + alternative)
            workspace = next(iter(matches)) if matches else ensure_workspace(cfg, path.name, path)[0]
            return workspace, None
        if not os.environ.get(context_keys["pane"]):
            raise ValueError("peek의 호출 pane 문맥이 없어 대상 workspace를 추정하지 않았습니다. " + alternative)
        current = native(cfg, "pane_current").get("pane", {})
    if not isinstance(current, dict):
        raise ValueError("현재 Herdr pane 응답이 다릅니다. " + alternative)
    workspace = current.get("workspace_id")
    caller = current.get("pane_id")
    if not isinstance(workspace, str) or not workspace or not isinstance(caller, str) or not caller:
        raise ValueError("현재 Herdr pane/workspace를 확인하지 못했습니다. " + alternative)
    inherited = os.environ.get(popup_keys["workspace"] if popup else context_keys["workspace"])
    if inherited and inherited != workspace:
        raise ValueError("상속된 workspace와 native 호출 pane의 workspace가 달라 생성하지 않았습니다. " + alternative)
    return workspace, caller



def peek_run(cfg, path, command):
    workspace, caller = peek_context(cfg, path, command)
    label = "exec·" + path.name
    live_tabs = tabs(cfg, workspace)
    panes = workspace_panes(cfg, workspace)
    selected = None
    for tab in live_tabs:
        if (type(tab.get("number")) is not int or tab["number"] <= 1
                or tab.get("pane_count") != 1 or tab.get("wspace_id", tab.get("workspace_id")) != workspace):
            continue
        candidates = [p for p in panes if p.get("tab_id") == tab.get("tab_id")]
        if len(candidates) != 1:
            continue
        pane = candidates[0]
        if pane.get("pane_id") != caller and pane.get("workspace_id") == workspace and idle_shell(cfg, pane, path):
            selected = pane
            break
    created = selected is None
    if created:
        result = native(cfg, "tab_create", workspace=workspace, cwd=str(path), label=label)
        tab_id = result.get("tab", {}).get("tab_id")
        pane_id = result.get("root_pane", {}).get("pane_id")
        if not tab_id or not pane_id:
            raise unsupported(cfg, "새 실행 탭 ID가 미확인입니다. 자동 재생성하지 마세요")
        selected = next((p for p in workspace_panes(cfg, workspace) if p.get("pane_id") == pane_id and p.get("tab_id") == tab_id and p.get("workspace_id") == workspace), None)
        if not selected or selected["pane_id"] == caller or not idle_shell(cfg, selected, path):
            raise unsupported(cfg, "실행 탭 셸 준비가 미확인입니다. 자동 재생성하지 마세요")
    # Native run admits literal text and Enter; it does not report command completion.
    native(cfg, "pane_run", pane=selected["pane_id"], command=command)
    print(json.dumps({"pane_id": selected["pane_id"], "tab_id": selected["tab_id"], "created": created, "cwd": str(path), "command": command, "submitted": True, "completion": "unknown"}, ensure_ascii=False))
    return 0


def unsupported(cfg, reason, feature="status"):
    return ValueError(reason + ". 선택·문맥 확인: " + INSPECT)


def select_project():
    paths_file = Path(runtime_paths()["tools_dir"]) / "sessionizer-paths.txt"
    if not paths_file.is_file():
        raise ValueError("검색 경로 목록이 없습니다: " + str(paths_file))
    paths = []
    seen = set()
    for line in paths_file.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        path = Path(line).expanduser()
        if not path.is_dir():
            continue
        identity = (path.stat().st_dev, path.stat().st_ino)
        if identity not in seen:
            paths.append(str(path))
            seen.add(identity)
    if not paths:
        raise ValueError("유효한 검색 경로가 없습니다: " + str(paths_file))
    result = subprocess.run(["find", *paths, "-mindepth", "1", "-maxdepth", "3", "-type", "d", "-not", "-path", "*/.*"], capture_output=True, text=True, check=True)
    selected = subprocess.run(["fzf", "--prompt=📂 프로젝트 선택 > ", "--height=100%", "--layout=reverse", "--border=rounded"], input=result.stdout, stdout=subprocess.PIPE, text=True, check=False)
    if selected.returncode in (1, 130):
        return None
    if selected.returncode:
        raise ValueError("프로젝트 선택기에 실패했습니다. 검색 경로와 fzf 설치를 확인하세요")
    return Path(selected.stdout.rstrip("\n")) if selected.stdout.strip() else None


def tmux_start(name, path):
    if not re.fullmatch(r"[A-Za-z0-9가-힣_.-]+", name):
        raise ValueError("작업공간 이름에는 문자·숫자·밑줄·점·하이픈을 사용하세요")
    existing = subprocess.run(["tmux", "has-session", "-t", "=" + name], capture_output=True, check=False)
    if existing.returncode:
        subprocess.run(["tmux", "new-session", "-d", "-s", name, "-n", "shell", "-c", str(path)], check=True)
    print(json.dumps({"session": name, "created": bool(existing.returncode), "cwd": str(path)}, ensure_ascii=False))
    return 0


def tmux_peek(path, command=None):
    pane = os.environ.get("TMUX_PANE")
    if not pane or not os.environ.get("TMUX"):
        raise ValueError("현재 tmux pane 문맥이 없습니다. tmux 실행 셸에서 실행: " + shlex.join(["vibe-terminal", "peek", str(path)] + (["run", command] if command is not None else [])))
    session = subprocess.run(["tmux", "display-message", "-p", "-t", pane, "#{session_id}"], capture_output=True, text=True, check=True).stdout.strip()
    target = subprocess.run(["tmux", "new-window", "-t", session + ":", "-n", ("exec·" if command else "peek·") + path.name, "-c", str(path), "-P", "-F", "#{pane_id}"], capture_output=True, text=True, check=True).stdout.strip()
    if command is not None:
        subprocess.run(["tmux", "send-keys", "-t", target, "-l", "--", command], check=True)
        subprocess.run(["tmux", "send-keys", "-t", target, "Enter"], check=True)
    print(json.dumps({"pane_id": target, "created": True, "cwd": str(path), "submitted": command is not None, "completion": "unknown"}, ensure_ascii=False))
    return 0


def dispatch(cfg, args):
    if args and args[0] == "terminal":
        args = args[1:]
    command = args[0] if args else "help"
    provider = definitions()["providers"][cfg["multiplexer"]]
    if command in ("help", "--help", "-h"):
        print("vibe-terminal status|use herdr|tmux|check|open|backend|settings\nvibe-terminal project-path TARGET\nvibe-terminal start NAME PATH\nvibe-terminal peek PATH [run COMMAND]\nvibe-terminal fzf [--window]\nvibe-terminal helper project|issue [인자…]\nvibe-terminal native OP --params JSON [--timeout SECONDS]")
        return 0
    if command in ("status", "settings"):
        print(json.dumps(cfg, ensure_ascii=False))
        return 0
    if command == "backend":
        print(json.dumps(definitions(), ensure_ascii=False))
        return 0
    if command == "project-path" and len(args) == 2:
        print(project_path(args[1]))
        return 0
    if command == "select-project" and len(args) == 1:
        selected = select_project()
        if selected is not None:
            print(selected)
        return 0
    if command == "commands" and len(args) == 2 and args[1] in ("common", "main", "sub"):
        print((Path(runtime_paths()["tools_dir"]) / ("commands_" + args[1] + ".txt")).read_text(), end="")
        return 0
    if command == "use" and len(args) == 2:
        select_runtime(args[1])
        return 0
    if command == "check":
        missing = [name for name in provider["required_tools"] + provider["check_tools"] if not tool_path(name)]
        if missing:
            raise ValueError("필요한 실행 파일이 없습니다: " + ", ".join(missing))
        print("터미널 설정·실행 파일 확인 완료 (서비스·창 변경 없음)")
        return 0
    if command == "open" and provider["execution"] == "native":
        open_ghostty(cfg)
        return 0
    if command == "native":
        parser = argparse.ArgumentParser(prog="vibe-terminal native")
        parser.add_argument("operation", choices=list(provider.get("operations", {})))
        parser.add_argument("--params", default="{}")
        parser.add_argument("--timeout", type=float, default=20)
        options = parser.parse_args(args[1:])
        params = json.loads(options.params)
        expected = {value[1:-1] for value in provider["operations"][options.operation]["argv"] if value.startswith("{")}
        if not isinstance(params, dict) or set(params) != expected or not 0 < options.timeout <= 3600:
            raise ValueError("native 인자와 operation 정의가 일치해야 하고 timeout은 0초 초과 3600초 이하여야 합니다")
        result = native(cfg, options.operation, timeout=options.timeout, **params)
        print(result if isinstance(result, str) else json.dumps(result, ensure_ascii=False))
        return 0
    if command == "entrypoint":
        if provider["execution"] == "legacy":
            return 10
        if len(args) != 3 or definitions()["entrypoints"].get(args[1]) != "project_select" or args[2].startswith("-"):
            raise unsupported(cfg, "선택 터미널에서 이 진입점의 일반 작업공간 준비를 지원하지 않습니다")
        return dispatch(cfg, ["start", args[2], str(project_path(args[2]))])
    if command == "helper" and len(args) > 1 and args[1] in ("project", "issue"):
        script = HERE / ("cmux-proj.sh" if args[1] == "project" else "cmux-issue.sh")
        return subprocess.run(["bash", str(script), *args[2:]], check=False).returncode
    if command == "fzf" and args[1:] in ([], ["--window"]):
        if provider["execution"] == "native" and args[1:] != ["--window"]:
            raise ValueError("Herdr 사용법: vibe-terminal fzf --window")
        path = select_project()
        if path is None:
            return 0
        if args[1:] == ["--window"]:
            return dispatch(cfg, ["peek", str(path)])
        result = dispatch(cfg, ["start", path.name, str(path)])
        if provider["execution"] == "legacy":
            action = "switch-client" if os.environ.get("TMUX") else "attach-session"
            return subprocess.run(["tmux", action, "-t", "=" + path.name], check=False).returncode
        return result
    if command == "peek":
        if len(args) not in (2, 4) or len(args) == 4 and args[2] != "run":
            raise ValueError("사용법: vibe-terminal peek PATH [run COMMAND]")
        path = project_path(args[1])
        literal = args[3] if len(args) == 4 else None
        if provider["execution"] == "legacy":
            return tmux_peek(path, literal)
        if literal is not None:
            return peek_run(cfg, path, literal)
        workspace, _ = peek_context(cfg, path)
        native(cfg, "tab_create", workspace=workspace, cwd=str(path), label="peek·" + path.name)
        print("현재 Herdr workspace에 별도 셸 탭을 준비했습니다")
        return 0
    if command == "main" and len(args) <= 2:
        path = project_path(args[1] if len(args) == 2 else os.environ.get("PARA_PATH", "para"))
        return dispatch(cfg, ["start", "para", str(path)])
    if command == "start" and len(args) == 3 and args[1]:
        name, path = args[1], project_path(args[2])
        if provider["execution"] == "legacy":
            return tmux_start(name, path)
        workspace, created = ensure_workspace(cfg, name, path)
        if cfg["herdr_context"]:
            native(cfg, "workspace_focus", workspace=workspace)
        print(json.dumps({"workspace_id": workspace, "created": created, "cwd": str(path), "attach": "vibe-terminal open"}, ensure_ascii=False))
        return 0
    raise unsupported(cfg, "미지원 명령: " + shlex.join(args))


if __name__ == "__main__":
    try:
        os.umask(0o077)
        raise SystemExit(dispatch(settings(), sys.argv[1:]))
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print("오류: " + str(error), file=sys.stderr)
        raise SystemExit(2)

