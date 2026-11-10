"""Forward Herdr state events to local Hammerspoon IPC; never submit agent input."""

import argparse
import json
import os
import shutil
import subprocess
from pathlib import Path
from uuid import UUID


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--test", choices=("done", "blocked"))
    args = parser.parse_args()
    if args.test:
        payload = {"status": args.test, "text": "상단 중앙 알림 연결 테스트"}
    else:
        event = json.loads(os.environ["HERDR_PLUGIN_EVENT_JSON"])["data"]
        status = event.get("agent_status")
        if status not in ("done", "blocked"):
            return
        context = json.loads(os.environ.get("HERDR_PLUGIN_CONTEXT_JSON", "{}"))
        location = " · ".join(str(value) for value in (
            context.get("workspace_label") or event.get("workspace_id"),
            event.get("pane_id"),
            event.get("display_agent") or event.get("agent"),
        ) if value)
        title = " ".join(str(event.get("title") or context.get("tab_label") or "").split())
        payload = {"status": status, "text": (location + "\n" + title)[:300]}
    cli = shutil.which("hs") or next((str(root / "Hammerspoon.app/Contents/Frameworks/hs/hs")
                                     for root in (Path.home() / "Applications", Path("/Applications"))
                                     if (root / "Hammerspoon.app/Contents/Frameworks/hs/hs").is_file()), None)
    if not cli:
        raise RuntimeError("Hammerspoon CLI missing: brew install --cask hammerspoon")
    # Decimal byte escapes keep event text as data, including quotes and Lua syntax.
    encoded = '"' + "".join(f"\\{byte:03d}" for byte in
                            json.dumps(payload, ensure_ascii=False).encode()) + '"'
    result = subprocess.run([cli, "-c", f"return vibeHerdrAlert(hs.json.decode({encoded}))"],
                            stdin=subprocess.DEVNULL, capture_output=True, text=True,
                            timeout=5, check=True)
    receipt = result.stdout.strip().splitlines()
    if not receipt:
        raise RuntimeError("Hammerspoon did not acknowledge the alert; check its config")
    print(UUID(receipt[-1]))


if __name__ == "__main__":
    main()
