# Audit delegation prompt (copy per subagent; re-slice scopes each round)

Split N ways; vary the "Read primarily" file list across rounds so the same
code is seen from a new angle. Keep the brief vague (no checklist of what to
inspect, no references to prior audits/fixes).

---

You are doing a READ-ONLY code-quality audit of the Python package at
<REPO>/hermes_opencode. Do NOT edit anything.

Architecture (context, not a verdict):
- hermes-opencode bridges Hermes Agent to the opencode CLI/API.
- ask_bridge.py: AskBridge base owns a Fifo worker + lifecycle; AskSurface
  protocol; shared safe_call helper (in fifo.py).
- approval.py: ApprovalBridge(AskBridge) - the permission/gate ask family;
  approval callback is captured on the main thread and passed in.
- questions.py: QuestionBridge(AskBridge) - the question ask family; owns the
  full question path.
- bridge.py: Bridge orchestrator - SSE routing, injection into the conversation,
  clarify, turn-complete watcher, prompt delegation.
- router.py: EventRouter - register-based dispatch of SSE events.
- client.py: OpenCodeClient - REST + SSE against opencode; directory-scoped calls.

Read primarily: <SLICE_FILES>. Cross-reference the rest of the package as needed.

Goal: help make this codebase better. Reason about how the concerns are
divided, whether the abstractions are pulling their weight, where the
structure could be cleaner or more honest, and any behavior that looks wrong or
fragile. Think about the design as a whole; do not limit yourself to a checklist.

Report ONLY concrete issues with file:line, severity (HIGH=bug/regression,
MED=quality, LOW=cosmetic), and a minimal fix. If the code is clean, say so
explicitly. Be skeptical and specific. Do not propose changes that would break
the existing pytest suite or ruff clean.

---

For a HIGH-severity claim that contradicts the code's own design doc or an
earlier "clean" pass, do NOT trust either — dispatch a separate verification
subagent that reads the ACTUAL upstream dependency source (file:line evidence)
before acting.

# Verification gate (run after applying a round)
cd <REPO> && source .venv/bin/activate && \
  ruff check hermes_opencode tests && python -m pytest -q
