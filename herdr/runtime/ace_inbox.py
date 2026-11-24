"""Read-only Ace MCP inbox probe for the Herdr notification cache."""

import fcntl
import json
import os
from pathlib import Path
import select
import signal
import subprocess
import sys
import tempfile
import time
import tomllib


def unread(config):
    try:
        with config.open("rb") as source:
            server = tomllib.load(source).get("mcp_servers", {}).get("ace")
    except FileNotFoundError:
        return "unconfigured"
    if server is None or server.get("enabled") is False:
        return "unconfigured"
    command = server["command"]
    args = server.get("args", [])
    child = subprocess.Popen(
        [command, *args], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL, cwd=Path.home(), start_new_session=True,
        env={**os.environ, **server.get("env", {})},
    )
    buffer = bytearray()
    deadline = time.monotonic() + 9

    def send(method, params=None, sequence=None):
        message = {"jsonrpc": "2.0", "method": method}
        if params is not None:
            message["params"] = params
        if sequence is not None:
            message["id"] = sequence
        child.stdin.write(json.dumps(message, separators=(",", ":")).encode() + b"\n")
        child.stdin.flush()

    def receive(sequence):
        fd = child.stdout.fileno()
        while time.monotonic() < deadline:
            if b"\n" not in buffer:
                if not select.select([fd], [], [], max(0, deadline - time.monotonic()))[0]:
                    break
                chunk = os.read(fd, 8192)
                if not chunk or len(buffer) + len(chunk) > 131072:
                    raise ValueError("invalid Ace MCP response")
                buffer.extend(chunk)
                continue
            line, _, remaining = buffer.partition(b"\n")
            buffer[:] = remaining
            reply = json.loads(line)
            if reply.get("id") != sequence:
                continue
            result = reply.get("result")
            if "error" in reply or not isinstance(result, dict) or result.get("isError") is True:
                raise ValueError("Ace MCP request failed")
            return result
        raise TimeoutError("Ace MCP deadline")

    try:
        send("initialize", {"protocolVersion": "2025-03-26", "capabilities": {},
                            "clientInfo": {"name": "herdr-ace-inbox", "version": "1"}}, 1)
        if not isinstance(receive(1).get("protocolVersion"), str):
            raise ValueError("invalid Ace MCP initialization")
        send("notifications/initialized")
        send("tools/call", {"name": "get_inbox", "arguments": {"unread_only": True, "limit": 1}}, 2)
        result = receive(2)
        items = result.get("structuredContent")
        if items is None:
            content = result["content"]
            if len(content) != 1 or content[0].get("type") != "text":
                raise ValueError("unknown Ace inbox response")
            items = json.loads(content[0]["text"])
        if not isinstance(items, dict) or not isinstance(items.get("items"), list):
            raise ValueError("missing Ace inbox item list")
        return "unread" if items["items"] else "empty"
    finally:
        try:
            os.killpg(child.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        child.stdin.close()
        child.stdout.close()
        child.wait()


def refresh(path):
    path.parent.mkdir(parents=True, exist_ok=True)
    lock_fd = os.open(path.with_suffix(".lock"), os.O_WRONLY | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    with os.fdopen(lock_fd, "w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return
        try:
            age = time.time() - json.loads(path.read_text())["at"]
            if 0 <= age < 60:
                return
        except (OSError, ValueError, KeyError, TypeError):
            pass
        config = Path(os.environ.get("CODEX_HOME") or Path.home() / ".codex") / "config.toml"
        try:
            state = unread(config)
        except (AttributeError, OSError, ValueError, TypeError, KeyError, subprocess.SubprocessError):
            state = "failed"
        with tempfile.NamedTemporaryFile("w", dir=path.parent, delete=False) as output:
            staged = Path(output.name)
            try:
                json.dump({"state": state, "at": time.time()}, output)
                output.close()
                staged.replace(path)
            finally:
                staged.unlink(missing_ok=True)


if __name__ == "__main__":
    refresh(Path(sys.argv[1]))
