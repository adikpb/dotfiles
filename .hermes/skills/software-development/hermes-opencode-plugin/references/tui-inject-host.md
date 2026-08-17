# TUI inject host (2026-08-16)

`ctx.inject_message` has two official hosts on stock Hermes `main`:

| Host | How it lands | Extra grant |
| --- | --- | --- |
| Classic CLI | `_cli_ref` → `_pending_input` / `_interrupt_queue` | none |
| Messaging gateway | `gateway/run.py` `set_gateway_message_injector` | `allow_gateway_injection: true` + `session_key` |
| Ink TUI / desktop | neither, until a TUI host exists | same grant once a host exists |

Ink TUI does not set `_cli_ref`. Stock `tui_gateway` does not register an injector. Official inject then returns `False` (`no live gateway is available`). Being in a TUI is not enough.

## Do not steal the injector slot

`PluginManager.set_gateway_message_injector` is a single slot. Messaging already owns it. A TUI `set_gateway_message_injector` last-writer-wins and breaks Telegram/Discord if both run. The right host is a **separate TUI route** inside `inject_message` (see #80920 `inject_external_message`), not a stolen injector.

A local `tui_gateway` hook that reuses `prompt.submit` proved live injects can land (question + turn-complete unprompted: `ses_example_tui_a`, `ses_example_tui_b`). That is a local workaround, not the upstream design.

## Upstream tracker

- #87412 TUI/desktop is not an inject_message host (filed this session)
- #59263 / merged #84929: messaging-gateway `session_key` path
- #80920 (closest TUI fix, CONFLICTING vs main)
- #85279 (queue-safe superset, also CONFLICTING)

Do not open a third competing PR. Rebase or help #80920. CONTRIBUTING: search open *and* merged PRs first.

## Plugin grant

```bash
hermes config set plugins.entries.hermes-opencode.allow_gateway_injection true
```

Without the grant, gateway/TUI inject returns False at the permission check even when a host exists.

## Usage-test discipline

- Do not commit `scripts/test-prompt-*.md`. `pbcopy` the prompt.
- Commit permission/inject only after a live TUI pass (Allow creates the file; injects arrive unprompted).
- Isolate the coding TUI from the test TUI: a second Hermes on `127.0.0.1:4096` also handles `permission.asked`. Use `hermes -p noload --tui` with the plugin disabled for the coding session.
