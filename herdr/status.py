"""Herdr's bounded status command; reads existing sources without starting collectors."""

import fcntl
import json
import os
import re
import subprocess
import sys
import time
import unicodedata
from pathlib import Path


def run(argv, timeout=0.5):
    try:
        result = subprocess.run(argv, capture_output=True, text=True, timeout=timeout,
                                check=True)
        return result.stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return None


def plain(value, width=100):
    value = re.sub(r"\x1b\[[0-?]*[ -/]*[@-~]|#\[[^]]*\]", "", str(value))
    value = "".join(c for c in value if not unicodedata.category(c).startswith("C"))
    result, size = "", 0
    for char in value:
        size += 2 if unicodedata.east_asian_width(char) in "WF" else 1
        if size > width:
            return result + "…"
        result += char
    return result


def dock(cache, now):
    try:
        path = cache / "dock-badges.raw"
        if now - path.stat().st_mtime > 30:
            return "알림?오래됨"
        # A successful read may legitimately contain no badged apps. The old
        # collector has no success marker, so an empty cache cannot prove zero.
        value = path.read_text()[:4096].strip()
        if not value:
            return "알림?"
        return plain(value.replace("\n", " ").replace("=", ":"), 20)
    except (OSError, UnicodeError):
        return "알림?"


def usage_value(payload):
    for item in payload:
        if item.get("provider") != "codex" or item.get("error"):
            continue
        usage = item.get("usage") or {}
        values = []
        for key, label in (("primary", "5h"), ("secondary", "주")):
            percent = (usage.get(key) or {}).get("usedPercent")
            if isinstance(percent, (int, float)) and 0 <= percent <= 100:
                values.append(f"{label}{100 - percent:g}%")
        if values:
            return "Codex " + "/".join(values)
    return "CB?데이터없음"


def usage(cache, now):
    path = cache / "herdr-codexbar.json"
    saved = {}
    try:
        saved = json.loads(path.read_text())
        if 0 <= now - saved["at"] < 60:
            return saved["label"]
    except (OSError, ValueError, KeyError, TypeError):
        pass
    label = "CB?조회중"
    try:
        cache.mkdir(parents=True, exist_ok=True)
        with (cache / "herdr-codexbar.lock").open("w") as lock:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                return label
            binary = Path(os.environ.get("CODEXBAR_CLI", "/Applications/CodexBar.app/Contents/Helpers/CodexBarCLI"))
            try:
                result = subprocess.run([str(binary), "usage", "--provider", "codex", "--source", "cli",
                                         "--format", "json", "--no-credits"], timeout=8,
                                        capture_output=True, text=True, check=True)
                label = usage_value(json.loads(result.stdout))
            except subprocess.TimeoutExpired:
                label = "CB?시간초과"
            except FileNotFoundError:
                label = "CB?미설치"
            except (OSError, subprocess.CalledProcessError, ValueError, TypeError):
                label = "CB?조회실패"
            good_at = now if label.startswith("Codex ") else saved.get("good_at")
            good_label = label if label.startswith("Codex ") else saved.get("good_label")
            if label.startswith("CB?") and good_at is not None and good_label:
                age = max(0, int(now - good_at))
                label = f"{good_label}~{age}s" if age <= 300 else f"CB 오래됨({age}s)"
            # Store only the display label, never the provider's account/token data.
            temporary = path.with_suffix(f".{os.getpid()}.tmp")
            temporary.write_text(json.dumps({"at": now, "label": label,
                                             "good_at": good_at, "good_label": good_label}))
            temporary.chmod(0o600)
            temporary.replace(path)
    except (OSError, ValueError, TypeError):
        pass
    return label


def resources():
    cpu = run(["ps", "-A", "-o", "%cpu="])
    cpu_label = "CPU?"
    if cpu:
        try:
            cpu_label = f"CPU~{sum(float(n) for n in cpu.split()) / (os.cpu_count() or 1):.0f}%"
        except ValueError:
            pass
    ram = "RAM?"
    vm = run(["vm_stat"])
    if vm:
        counts = dict(re.findall(r"^([^:\n]+):\s+(\d+)", vm, re.M))
        try:
            active = sum(int(counts[k]) for k in ("Pages active", "Pages wired down", "Pages occupied by compressor"))
            page = int(re.search(r"page size of (\d+) bytes", vm)[1])
            ram = f"RAM{active * page / 1073741824:.1f}GiB"
        except (KeyError, ValueError, TypeError):
            pass
    battery = run(["pmset", "-g", "batt"])
    match = re.search(r"(\d+)%", battery or "")
    return f"{cpu_label} {ram} " + (f"BAT{match[1]}%" if match else "AC/BAT?")


def context(env):
    pane = env.get("HERDR_ACTIVE_PANE_ID", "pane?")
    cwd = env.get("HERDR_ACTIVE_PANE_CWD", "")
    label = plain(Path(cwd).name if cwd else "cwd?", 22)
    branch = run(["git", "-C", cwd, "status", "--porcelain=v1", "--branch"]) if cwd else None
    if branch:
        lines = branch.splitlines()
        label += " " + plain(lines[0].removeprefix("## ").split("...")[0], 16)
        if len(lines) > 1:
            label += "*"
    return f"{plain(pane, 14)} {label}"


def main():
    cache = Path(os.environ.get("VIBE_CACHE_DIR", str(Path.home() / ".cache/vibe")))
    now = time.time()
    if "--usage" in sys.argv:
        print(usage(cache, now))
        return
    from hud import refresh
    refresh()
    parts = [context(os.environ), resources(), dock(cache, now)]
    print(" · ".join(parts))


if __name__ == "__main__":
    main()
