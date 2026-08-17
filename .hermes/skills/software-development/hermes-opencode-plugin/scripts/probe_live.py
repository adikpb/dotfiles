"""Deterministic live probe for the hermes-opencode plugin.

WHY: a deferred-tool verification (tool_call to opencode_prompt / etc.) runs
outside an interactive TUI, so the bridge's _inject_text returns False (no
live cli_ref / session_key) and every event-driven pillar appears to "not
fire". That is a HARNESS sink limitation, not a fix regression. This script
proves the FIX LOGIC independent of the sink by driving the REAL Bridge with a
recording context that returns a valid session_key, so injects actually land
and can be asserted on.

It also exposes the SSE subscription root cause directly: compare the router's
received event `type`s against a separate raw client.iter_events connection.
On the location-filter bug the router gets only server.connected/heartbeat
while the raw connection gets question.asked/permission.asked/session.status.

Run (from the plugin repo, venv active):
    python scripts/probe_live.py
It needs a live `opencode serve` on 127.0.0.1:4096 with directory /tmp.

Exit non-zero only on unexpected crash; it prints a SUMMARY of what landed.
"""

from __future__ import annotations

import queue
import threading
import time

from hermes_opencode.config import load_bridge_config
from hermes_opencode.client import OpenCodeClient
from hermes_opencode.bridge import Bridge


class RecCtx:
    """Recording plugin-context double.

    Returns a valid session_key so inject_message SUCCEEDS (unlike the
    deferred-tool harness where no session_key exists). Records every
    injected message so the script can assert on it.
    """

    def __init__(self):
        self.injected = []
        self._session_key = "agent:main:tui:probe:" + str(int(time.time()))

    def inject_message(self, content, role="user", session_key=None):
        self.injected.append((session_key, content))
        return True


def main():
    cfg = load_bridge_config()
    # Force the real serve dir: under this cwd the config dir may be empty,
    # and the canonical realpath (/private/tmp on macOS) is what opencode's
    # location filter expects.
    cfg["directory"] = "/tmp"
    host = cfg.get("hostname", "127.0.0.1")
    port = int(cfg.get("port", 4096))
    directory = "/tmp"

    client = OpenCodeClient(
        hostname=host,
        port=port,
        directory=directory,
        username=cfg.get("username", "opencode"),
        password=cfg.get("password", ""),
        timeout=30,
    )
    ctx = RecCtx()
    bridge = Bridge(ctx=ctx, cfg=dict(cfg), client=client)
    bridge.start()

    # --- raw SSE capture: a SEPARATE client.iter_events connection, to prove
    #     the events are on the wire even if the bridge router filters them.
    captured: list[str] = []
    captured_lock = threading.Lock()

    def raw_sse(duration=20):
        try:
            for ev in client.iter_events(directory=directory):
                with captured_lock:
                    captured.append(ev.get("type", "?"))
        except Exception:
            pass

    raw_thread = threading.Thread(target=raw_sse, args=(22,), daemon=True)
    raw_thread.start()

    # --- Scenario A: tail-on-idle injection
    sidA = client.create_session(directory=directory)
    bridge.prompt("What is 6*7+1? Just answer the number.", session_id=sidA)
    time.sleep(8)

    # --- Scenario B: question ask -> held que_ id
    sidB = client.create_session(directory=directory)
    bridge.prompt(
        "Before you do anything, ask me: which do you prefer, apples or oranges? "
        "Then wait for my answer before finishing.",
        session_id=sidB,
    )
    time.sleep(20)
    raw_thread.join(timeout=1)

    que_held = bridge._approval.held_question_ids() if bridge._approval else []
    print("\n=== SUMMARY ===")
    print(f"router held question ids: {que_held}")
    print(f"raw SSE event types seen: {sorted(set(captured))}")
    print(f"total injected messages: {len(ctx.injected)}")
    for i, (sk, c) in enumerate(ctx.injected):
        print(f"  [{i}] sk={sk!r} :: {c[:140]}")
    bridge.stop()


if __name__ == "__main__":
    main()
