# OpenCode Plugin API + SDK — verified source map (v1.18.13)

Pinned to tag `v1.18.13` (commit a105350812f05f). Every symbol below was read from the clone at
`.slim/clonedeps/repos/anomalyco__opencode` in the hermes-opencode-plugin workspace. Re-verify against the version you ship.

## 1. Plugin type — packages/plugin/src/index.ts

```ts
export type Plugin = (input: PluginInput, options?: PluginOptions) => Promise<Hooks>   // :74
export type PluginOptions = Record<string, unknown>                                       // :68
export type Config = Omit<SDKConfig, "plugin"> & { plugin?: Array<string | [string, PluginOptions]> } // :70
export type PluginModule = { id?: string; server: Plugin; tui?: never }                    // :76
```

PluginInput (hosted inside `packages/opencode/src/plugin/index.ts:151-166`):
- `client: ReturnType<typeof createOpencodeClient>` — live HTTP client to the running server
- `project: Project`, `directory: string`, `worktree: string`
- `experimental_workspace.{ register(type, adapter) }`
- `serverUrl: URL`, `$: BunShell`

Loading rules (`packages/opencode/src/plugin/shared.ts`): module must default-export `{ id?, server?, tui? }` (`readV1Plugin`); server and tui are mutually exclusive; path plugins must export `id` (`resolvePluginId`); npm plugins fall back to package.json `name`. Legacy fallback: any exported function is treated as a server plugin (`getLegacyPlugins`).

## 2. Hooks catalog — packages/plugin/src/index.ts:222-335

All hooks: `(input, output) => Promise<void>`, mutable output threaded in load order. Trigger impl: `packages/opencode/src/plugin/index.ts` (Plugin.Service.trigger, lines 282-294).

| Hook | Input → Output | Fires at |
|---|---|---|
| `event` | `{event:{id,type,properties}}` | every event, location-filtered (plugin/index.ts:253) |
| `config` | `Config` | plugin init, merged config |
| `tool` | `{[key]: ToolDefinition}` | registry build (tool/registry.ts:194) |
| `auth` / `provider` | AuthHook / ProviderHook | provider auth / model listing |
| `chat.message` | `{sessionID, agent, model, messageID, variant}` → `{message, parts}` | user message processed (session/prompt.ts:999) |
| `chat.params` | `{sessionID, agent, model, provider, message}` → `{temperature, topP, topK, maxOutputTokens, options}` | before LLM gen (session/llm/request.ts:114) |
| `chat.headers` | `→ {headers}` | request headers (request.ts:134) |
| `command.execute.before` | `{command, sessionID, arguments}` → `{parts}` | slash command run (session/prompt.ts:1460) |
| `tool.execute.before` | `{tool, sessionID, callID}` → `{args}` | every tool (session/tools.ts:106,175,258,338,401) |
| `tool.execute.after` | `{tool, sessionID, callID, args}` → `{title, output, metadata}` | after tool (session/tools.ts:121,208,...; tool/code-mode.ts) |
| `shell.env` | `{cwd, sessionID?, callID?}` → `{env}` | shell process spawns (tool/shell.ts:417, prompt.ts:554) |
| `tool.definition` | `{toolID}` → `{description, parameters}` | tools sent to LLM (tool/registry.ts:313) |
| `experimental.chat.messages.transform` | `{}` → `{messages}` | pre-LLM history rewrite (prompt.ts:1255; compaction:350) |
| `experimental.chat.system.transform` | `{sessionID?, model}` → `{system}` | pre-LLM system prompt (agent/agent.ts:381, llm/request.ts:69) |
| `experimental.provider.small_model` | `{provider}` → `{model?}` | small-model determinator (provider/provider.ts:1892) |
| `experimental.session.compacting` | `{sessionID}` → `{context, prompt?}` | compaction start (compaction.ts:343) |
| `experimental.compaction.autocontinue` | `{...}` → `{enabled}` | after compaction (compaction.ts:454) |
| `experimental.text.complete` | `{sessionID, messageID, partID}` → `{text}` | text part completion (processor.ts:516) |
| `permission.ask` | `(input: Permission, output: {status: ask|deny|allow})` | **declared only — no trigger site in v1.18.13.** Use `permission.asked/replied` events. |

Fire sites live in `packages/opencode/src/session/*`, `tool/*`, `agent/*`, `provider/*`, `plugin/*` — grep for `\.trigger(` with one line of trailing context to see the hook name (it is often on the NEXT line).

## 3. Tools — packages/plugin/src/tool.ts (whole file)

```ts
export function tool<Args extends z.ZodRawShape>(input: {
  description: string
  args: Args
  execute(args: z.infer<z.ZodObject<Args>>, context: ToolContext): Promise<ToolResult>
}) { return input }
tool.schema = z
export type ToolDefinition = ReturnType<typeof tool>
```

- `ToolContext = { sessionID, messageID, agent, directory, worktree, abort: AbortSignal, metadata(input), ask(input: AskInput) }`; AskInput `{ permission, patterns, always, metadata }`.
- `ToolResult = string | { title?, output, metadata?, attachments?: {type:"file", mime, url, filename?}[] }`.
- Host integration: `packages/opencode/src/tool/registry.ts` `fromPlugin()` (zod→JSON schema via zodJsonSchema or legacy), dispatch via EffectBridge; plugin tools get regular `tool.execute.before/after` hooks and `ctx.ask` permissions. Files in project `tool/` or `tools/` dirs are also loaded as tools. `tool.definition` hook runs at model-time on each tool.

## 4. Config & registration

- opencode.json key: `"plugin": ["npm-pkg", "./path/to/plugin.ts", ["name", {options}]]` — `ConfigPluginV1.Spec = string | [string, Options]` (`packages/core/src/v1/config/plugin.ts`).
- Auto-discovery: files in `{plugin,plugins}/*.{ts,js}` at project root are auto-loaded (`packages/opencode/src/config/plugin.ts:21`); `tool,{tools}` glob for tool-only plugins.
- Resolver: npm spec via `npm-package-arg` (`name@version`); path specs via `resolvePathPluginTarget` (file://, ./ , absolute). Checks engines field (`checkPluginCompatibility`).
- Loading pipeline: `PluginLoader.loadExternal` → `createPluginEntry` → entrypoint resolution via package.json `exports.` map → import → `applyPlugin` (runs sequentially, deterministic order).
- Compat gate: plugin package.json `engines.opencode` range must satisfy running version.

## 5. Permissions — packages/schema/src/v1/permission.ts + packages/opencode/src/permission/index.ts

```ts
export const Rule = Schema.Struct({ permission: String, pattern: String, action: Literals(["allow","deny","ask"]) })
export const Request = { id, sessionID, permission, patterns: String[], metadata, always: String[], tool? }
export const Reply = ["once" | "always" | "reject"]
```
- Service `{ ask, reply, list }`; `ask` evaluates each pattern against merged rulesets (wildcard last-match-wins), blocks until reply; publishes `permission.asked` / `permission.replied` events.
- Tools gate themselves via `ctx.ask({permission, patterns, always, metadata})` — see `edit`, `read`, `write`, `apply_patch`, `shell`, `websearch`, `task`, `external-directory`, `code_mode`, etc.
- HTTP: `/api/permission/request` list, `/api/session/{id}/permission` (create/list/get/reply). Plugin `ctx.ask` bridge in the registry.
- The plugin-facing `permission.ask` hook does NOT fire in v1.18.13 core — use the `permission.asked` / `permission.replied` events.

## 7. Message injection (push into a session from outside)

1. **session.prompt** — `client.session.prompt({ path: { id }, body: { parts: [...] } })` → `POST /session/{id}/message` → handled in `packages/opencode/src/server/routes/instance/httpapi/handlers/session.ts` (`promptSvc.prompt`), streams the new message back. This is the canonical injection path.
2. **session.promptAsync** — `POST /{id}/prompt_async`, fires and returns `202` early.
3. **plugin client** — plugins get `input.client` and can `client.session.prompt({...})` themselves.
4. **TUI bridge** — `tui.appendPrompt` (`POST /tui/append-prompt`), `tui.submitPrompt` (`/tui/submit-prompt`).
Also: v2 SDK `session.prompt`/`promptAsync` (v2 `packages/sdk/js/src/v2`).

## SDK client usage (v1)

```ts
// packages/sdk/js/example/example.ts, condensed
const server = await createOpencodeServer()                    // spawns `opencode serve --hostname=127.0.0.1 --port=4096`, parses "opencode server listening on <url>"
const client = createOpencodeClient({ baseUrl: server.url })   // sets x-opencode-directory header
const session = await client.session.create()                  // POST /session
await client.session.prompt({ path: { id: session.data.id }, body: { parts: [{ type: "text", text: "…" }] } })
for await (const event of client.event.subscribe()) { /* SSE /event */ }
const sessions = await client.session.list()
const tools    = await client.tool.list()                      // /experimental/tool with JSON schemas
await client.session.message({ path: { id, messageID } })      // single message
```

`createOpencodeServer` default host 127.0.0.1:4096, reads stderr/stdout for "opencode server listening ON URL". Config content can be passed via env `OPENCODE_CONFIG_CONTENT` in `createOpencodeServer` (server.ts:38).

## v2 SDK + v2 plugin surface (experimental in 1.18.13)

- v2 client `createOpencodeClient({ directory?, experimental_WorkspaceID?, … })` → adds `x-opencode-workspace`; HTTP API groups include `session.list` (GET /api/session, cursor paged), `session.background` (`/{id}/background`), `/api/...` permission/question endpoints, `/event` SSE with location params.
- v2 event union much larger: `SessionNextTextDelta/StepStarted/ToolCalled/ToolSuccess/ToolFailed/Prompted/PromptAdmitted`, etc. (`packages/sdk/js/src/v2/gen/types.gen.ts:7-60`).
- v2 plugin API: `packages/plugin/src/v2/promise/plugin.ts` — `Plugin { id, setup(PluginContext) }`; `PluginContext { options, agent, aisdk, catalog, command, integration, plugin, reference, skill }`, each a `Hooks<Spec>` registration map returning `{ dispose, reload }` (`v2/promise/registration.ts`). Effect variant: `{ id, effect(ctx) }` (`v2/effect/plugin.ts`).

## Recon workflow that produced this

```bash
# find every hook trigger site (name often on the NEXT line):
rg -n -A1 '\.trigger\(' packages/opencode/src --glob '*.ts'
# collect hook names:
rg -o 'trigger\("[a-z0-9._]+"' ... | sort | uniq -c
# type defs: read packages/plugin/src/index.ts (full), tool.ts, v2/*, gen sdk.types
# wire: packages/protocol/src/groups/*.ts is the Effect HttpApi source of truth for routes.
```

## Key files table (v1.18.13)

| Path | Contents |
|---|---|
| packages/plugin/src/index.ts | Plugin types, Hooks, Auth/Provider hooks |
| packages/plugin/src/tool.ts | ToolContext/ToolDefinition |
| packages/opencode/src/plugin/{index,shared,loader}.ts | host loader, ids, entrypoints, install |
| src/session/{prompt,processor,tools}.ts | chat.message/tool.execute triggers |
| src/session/llm/request.ts | chat.params / chat.headers / system.transform |
| src/compaction.ts | experimental.session.compacting / autocontinue / messages.transform |
| src/schema/v1/* | box model (Permission, SessionStatus) |
| packages/sdk/js/{client,server}.ts, gen/sdk.gen.ts | diff client, spawn, generated HTTP verbs |
| packages/sdk/js/src/v2/gen/*.ts | v2 client surface |
| packages/protocol/src/groups/{session,event,permission}.ts | Effect HttpApi route definitions |