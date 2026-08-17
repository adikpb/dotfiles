# Headless ask repro (ses_example_headless)

Model: deepseek-v4-flash-free (server-assigned). Tools invoked via `tool_call`
because the plugin tools live in Hermes' deferred catalog, not the base toolset.

Prompt sent:
> Run exactly this and report the results: 1) execute `rm -rf /tmp/opencode_probe_*`
> and then list the directory contents, 2) ask me: which shell am I in and what is
> the current working directory?

Observed assistant content (verbatim, including the model's own em dashes):

> 1) **Command blocked** — the `rm -rf /tmp/opencode_probe_*` invocation was
> rejected by a permission gate: accessing `/tmp/*` (external directory) requires
> interactive approval, and no interactive user/gateway was present to approve it.
> Nothing was deleted; no listing was produced.
>
> 2) Your turn: **Which shell am I in, and what is the current working directory?**

Findings:
- Permission ask: fail-closed denied by opencode's own gate (external directory
  /tmp/*). Did NOT surface as a Hermes approval prompt. The `rm` never executed.
  Matches the headless-deny pitfall in SKILL.md.
- Question ask: the model rendered the "ask me" as plain prose. No
  `[opencode] question` user message was injected and no `que_...` id surfaced,
  so `opencode_question_reply` had no target to answer.
- No crashes, no "handling failed", no exceptions. The turn completed normally.

Takeaway: in a headless run with a server-assigned free model, expect both asks to
loop back as model text rather than through the plugin's formal approval / question
channels. Read the session tail to confirm which path actually fired. The deferred
tool-call path (tool_search -> tool_describe -> tool_call) is required to drive the
plugin at all from Hermes.
