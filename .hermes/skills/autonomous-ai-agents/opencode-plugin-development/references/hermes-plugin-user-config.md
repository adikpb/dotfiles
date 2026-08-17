# Hermes plugin user configuration (plugins.entries.<id>.*)

How a Hermes plugin (e.g. the Hermes↔OpenCode bridge) exposes user-facing
settings — verified in the hermes-agent clone (hermes_cli/plugins.py,
hermes_cli/config.py) and official docs (developer-guide/plugins).

## The namespace

Per-plugin user settings live under `plugins.entries.<plugin_id>.*` in
`~/.hermes/config.yaml`. This is the SAME namespace Hermes core uses for its
own plugin trust gates:

- `plugins.entries.<plugin_id>.allow_tool_override: true` — required before
  `register_tool(override=True)` may replace a built-in tool (hermes_cli/plugins.py:443-444; 476).
  Bundled plugins are trusted by default; everyone else fails closed.
- `plugins.entries.<plugin_id>.llm.*` — gates `ctx.llm` (PluginLlm) override
  capability (model/agent/auth) (plugins.py:359).

There is NO dedicated `ctx.config`/`ctx.get_config` helper. Plugins read
config.yaml directly, same as the gates do:

```python
from hermes_cli.config import load_config, cfg_get

cfg = load_config() or {}
port = cfg_get(cfg, "plugins", "entries", "hermes-opencode",
               "server_port", default=4096)
```

- `cfg_get(cfg, *keys, default=None)` is the nested-key getter
  (hermes_cli/config.py:2886). Entry keys are free-form; the plugin owns
  validation and defaults (no schema enforcement).
- `plugin_id` = the manifest key (`name:` or the path-derived key).
- Users set values WITHOUT hand-editing config.yaml:
  `hermes config set plugins.entries.<id>.<key> <value>` (dotted path,
  safely writes YAML). View with `hermes config show`.

## Secrets and precedence

- Secrets never go in config.yaml: declare them in the manifest
  `requires_env:` (`- NAME` simple, or rich `- name, description, url, secret`),
  users put them in `~/.hermes/.env`. Env-presence gates plugin load.
- Precedence: CLI args > config.yaml > .env > built-in defaults.

## Bridge defaults proposed for hermes-opencode (R7)

`auto_serve: true`, `hostname: 127.0.0.1` / `port: 4096`, `tail_size: 8`,
`rule_key_prefix: "opencode"`, `tail_role`/`display_kind` ("tool"/"opencode_session");
secret `OPENCODE_SERVER_PASSWORD` via requires_env/.env.