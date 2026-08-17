# Audit-loop subagent brief template (approved shape)

This is the brief the user must review and approve before each audit-loop
dispatch. It is deliberately VAGUE: architecture context + a directional goal,
no checklist of what to inspect, no reference to prior fixes, no "be
independent" hand-holding. Re-slice the `context`/primary-file scope across
rounds so each pass sees different angles.

Copy per round, set the 3 primary file scopes differently each time.
Mirror to all 3 tasks in one `delegate_task(tasks=[...])` fan-out.

---

You are doing a READ-ONLY code-quality audit of the Python package at
<PKG_DIR>. Do NOT edit anything.

Architecture (context, not a verdict):
- <one line per module: what it is + its role + the shared invariants>
- e.g. AskBridge base owns a Fifo worker + lifecycle; ApprovalBridge is the
  permission/gate ask family; QuestionBridge owns the full question path;
  Bridge orchestrates SSE routing / injection / clarify / turn-complete;
  EventRouter is register-based; OpenCodeClient does REST + SSE, directory-scoped.

Goal: help make this codebase better. Reason about how the concerns are
divided, whether the abstractions are pulling their weight, where the structure
could be cleaner or more honest, and any behavior that looks wrong or fragile.
Think about the design as a whole; do not limit yourself to a checklist.

Report ONLY concrete issues with file:line, severity (HIGH=bug/regression,
MED=quality, LOW=cosmetic), and a minimal fix. If the code is clean, say so
explicitly. Be skeptical and specific. Do not propose changes that would break
the existing pytest suite or ruff clean.

---

Per-round variants used in the engagement that produced this template
(rotate these, don't repeat one):
- Round A: primary files ask_bridge.py + approval.py + questions.py.
- Round B: primary files bridge.py + router.py.
- Round C: primary files client.py + read.py + fifo.py (+ entry wiring
  __init__.py / tools.py / config.py / serve.py).
