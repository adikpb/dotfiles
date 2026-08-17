# Bridge surfaces: question tool, permission deny-reason, command registry (v1.18.13)

Extends `references/opencode-plugin-api-v1-18-13.md` with the surfaces a
Hermes↔OpenCode serve bridge needs that the hooks model does NOT cover:
the `question` tool, permission deny-with-reason, and slash-command listing.
Every symbol was read from the clone at `.slim/clonedeps/repos/anomalyco__opencode`
(hermes-opencode-plugin workspace, tag v1.18.13). Re-verify against the version you ship.

## Serve mode

- `opencode serve` (packages/opencode/src/cli/cmd/serve.ts:6-24): headless server,
  `--hostname/--port` via network opts; prints `opencode server listening on http://host:port`;
  logs a WARNING when `OPENCODE_SERVER_PASSWORD` is unset (server unsecured);
  project instances load per-request via the `x-opencode-directory` header (no project at startup).
- SDK spawns it via `createOpencodeServer` (packages/sdk/js/src/server.ts:22-99), config injected
  as `OPENCODE_CONFIG_CONTENT` env JSON.
- `flags.client` defaults to `"cli"` (packages/opencode/src/effect/runtime-flags.ts:56) — matters for question-tool enablement below.

## Question tool ("ask the user")

- Builtin `question` tool (packages/opencode/src/tool/question.ts): args
  `questions: [{ question, header (≤30 chars), options[{label, description}], multiple?, custom? }]`
  (packages/schema/src/question.ts:22-44). Ask BLOCKS until answered; unanswered → `"Unanswered"` in output.
- Enablement: registered only when `["app","cli","desktop"].includes(flags.client) || flags.enableQuestionTool`
  (packages/opencode/src/tool/registry.ts:202-228). Serve defaults client to `"cli"` → **enabled by
  default in serve mode**; `OPENCODE_ENABLE_QUESTION_TOOL=true` forces it on.
- Service lifecycle (packages/opencode/src/question/index.ts): `ask()` registers a `que_*` request,
  publishes `question.asked`, blocks on a Deferred; `reply()` publishes `question.replied` and returns
  answers to the tool; `reject()` publishes `question.rejected` and fails the ask with
  `QuestionRejectedError` ("The user dismissed this question", index.ts:27-31).
- HTTP (v2 protocol group `server.question`, packages/protocol/src/groups/question.ts):
  - `GET /api/question/request` — all pending asks (location-scoped)
  - `GET /api/session/:sessionID/question` — pending asks for a session
  - `POST /api/session/:sessionID/question/:requestID/reply` — body `{ answers: string[][] }`
    (one array of selected labels per question)
  - `POST /api/session/:sessionID/question/:requestID/reject` — dismiss
  - OpenAPI ids: `v2.question.request.list`, `v2.session.question.list/reply/reject`
- Events on the wire: runtime emits v1 names `question.asked/replied/rejected`
  (packages/schema/src/v1/question.ts:58-60); current-contract `question.v2.*` definitions also exist
  (packages/schema/src/question.ts:70-86); both families in the event manifest
  (packages/schema/src/event-manifest.ts:54,76).
- The `plan` tool also asks a confirm question through the same service (packages/opencode/src/tool/plan.ts:19-34).

## Permission deny WITH a reason

- `ReplyBody = { reply: "once"|"always"|"reject", message? }` (packages/schema/src/v1/permission.ts:41-43) —
  the reason travels in `message`.
- `reply: "reject"` + `message` fails the pending ask with `PermissionV1.CorrectedError({ feedback: message })`,
  message = "The user rejected permission to use this specific tool call with the following feedback: …"
  (packages/core/src/v1/permission.ts:7-17). Reject WITHOUT `message` → bare `RejectedError` (no reason).
  Bridge policy: always attach `message` on reject.
- Sibling fan-out on reply: one reply also resolves OTHER pending asks of the same session
  (reject fans out as reject, approve fan-out as allow-if-now-allowed) (packages/opencode/src/permission/index.ts:129-167).

## Slash commands over HTTP — and why the list is already non-TUI

- `GET /api/command` (protocol group `server.command`, packages/server/src/handlers/command.ts:6-8 →
  `CommandV2.Service.list()`, location-scoped via `directory`) returns
  `CommandV2.Info = { name, template, description?, agent?, model?, subtask? }` (packages/schema/src/command.ts:8-15).
  Legacy `GET /command` (instance route, SDK `client.command.list`, openapi.json:2662-2718) exposes the same registry.
- Registry composition (packages/opencode/src/command/index.ts): built-ins `init` + `review` only;
  `opencode.json` `command` field plus `{command,commands}/**/*.md` files (frontmatter gives
  description/agent/model/subtask, packages/opencode/src/config/command.ts:13-39); MCP prompts (`source:"mcp"`);
  installed skills (`source:"skill"`).
- TUI-only commands (`/models`, `/themes`, `/new`, `/sessions`, `/help`, `/editor`, `/rename`, `/connect` —
  packages/tui/src/feature-plugins/home/tips-view.tsx:172-283) live inside the TUI client and are NOT in the
  server registry, so the API list IS exactly the non-TUI set to surface (name + description + routing metadata).
- Note: v1 in-process `Command.Info` also had `source` and `hints` ($1..$n, $ARGUMENTS); `CommandV2.Info` drops both.

## v2 plugin API relevant fragments

- Plugin context domain `command` = `Hooks<{ transform: CommandDraft }>` with
  `CommandDraft { list(), get(name), update(name, fn), remove(name) }` (packages/plugin/src/v2/promise/command.ts
  + v2/effect/command.ts:4-13). Same transform-registry pattern for agent/aisdk/catalog/integration/reference/skill.
- v2 session/event surface: `POST /session/{id}/message` (parts-based, `noReply` for pure injection),
  `GET /event` SSE with `directory`/`workspace` params; current event family `session.next.*`
  (prompted, text delta, tool called/success/failed, ...) (packages/sdk/js/src/v2/gen/types.gen.ts:7-60).