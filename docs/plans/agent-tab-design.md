# Agent tab — design

Status: **implemented** (P1–P3). See *Implementation notes* at the end for the
places where the code differs from the plan.

## Shape in one sentence

**Conversations persist, agents do not.** Every turn spins up a throwaway Jido
agent, runs one read-only ReAct loop against PSC's own tools, streams the events
into a LiveView, persists the result, and dies. There is no resident agent
process, no per-user `AgentServer`, and nothing to restart on deploy.

## Decisions

| # | Decision | Why |
|---|---|---|
| 1 | Session = rows in Postgres; agent = a process that lives for one turn | "Agents are not long lived" — restart/redeploy is a non-event |
| 2 | The tool surface **is** the MCP surface | "just chat and PSC MCP"; one registry, two transports |
| 3 | Read-only tools only | A model that can look but not touch cannot corrupt the event log |
| 4 | Streaming over `Phoenix.PubSub` | Reuses `Psc.PubSub`; the LiveView stays a renderer |
| 5 | Chat column is single, sessions are a rail | Matches the coding-agent idiom the user asked for |
| 6 | Turn-scoped agent via `AgentServer.start_link/1` | Linked to the `Task`, dies with it; no `DynamicSupervisor`, no Jido instance bootstrap |

## Verified mechanics (read from `deps/`, not guessed)

- `Jido.AI.Agent.ask_stream/3` → `{:ok, %{request: request, events: events}}`;
  `events` is an enumerable that blocks while consumed; `await(request)` returns
  the final result.
- `tool_context:` exists on the agent **and** per request, merged. That is the
  `current_scope` seam.
- `Jido.AgentServer.start_link(agent: MyAgent)` links the server to the caller —
  exactly right for a per-turn Task. `Jido.AgentServer.start/1` would require a
  running `Jido.AgentSupervisor`, which we do not want.
- `Jido.AI.ask/2` is **not** a stateless agent: it is `generate_text` plus text
  extraction. The loop always needs an `AgentServer` pid.
- `Jido.AI.Test.ReActScript` + `Jido.AI.Test.expect_react/1` give deterministic
  scripted turns (`:tool_call`, `:answer`, `:fail`).
- There is **no** `cancel/2` on request handles. Cancellation means stopping the
  turn process and persisting `:cancelled`.

## Data model

```
agent_sessions
  id               uuid pk
  user_id          fk users (on delete cascade)
  title            text             -- derived, renameable
  message_count    integer default 0
  last_message_at  utc_datetime
  inserted_at / updated_at

  index (user_id, last_message_at desc)   -- the rail query

agent_messages
  id            uuid pk
  session_id    fk agent_sessions (on delete cascade)
  role          enum: user | assistant
  content       text                -- Markdown
  status        enum: streaming | complete | cancelled | error
  error         text
  tool_calls    jsonb default []    -- [{name, arguments, result, status, duration_ms}]
  usage         jsonb               -- {input_tokens, output_tokens, model}
  inserted_at / updated_at

  index (session_id, inserted_at)
```

Two tables, not one: the rail needs session titles and ordering without reading
messages, and deleting a session should be a single cascade.

**Row budget.** Keep at most **200 messages per session** and **50 sessions per
user**; prune oldest on write. The prompt is **append-only**: every turn replays
the whole conversation until a hard cap (40 messages), then compacts once into a
summary message. A per-turn sliding window would look thrifty and cost more —
see *Prompt caching* below.

## Turn lifecycle

```
idle ──submit──▶ starting ──▶ thinking ──┬──▶ tool_running ──┐
                                          │                   │
                                          └──▶ streaming ◀────┘
                                                  │
                          ┌───────────────────────┼──────────────┐
                          ▼                       ▼              ▼
                      complete                cancelled        error
```

1. LiveView inserts the user message and an assistant placeholder
   (`status: :streaming`), then starts `Psc.Agent.Turn` under `Psc.Agent.TurnSupervisor`.
2. The turn process:
   - `Jido.AgentServer.start_link(agent: Psc.Agent.CanvasAgent)`
   - seeds prior turns, `ask_stream/3` with `tool_context: %{scope: scope}`
   - enumerates `events`, broadcasting each on `agent_session:<id>`
   - persists the final assistant message; bumps `last_message_at`; derives the
     title if this was the first user message
   - exits → the linked `AgentServer` dies with it
3. The LiveView only renders: `handle_info` for the PubSub events, `stream/3`
   for the message list.

**Reconnect.** The LiveView re-renders from the database on mount, so a reload
mid-turn shows the persisted history. A message left in `:streaming` by a dead
turn is swept to `:cancelled` on boot (same pattern as `Psc.EventsSweeper`).

**Stop button.** `Psc.Agent.Turn.cancel/1` stops the Task, marks the assistant
message `:cancelled`, keeps whatever text arrived. No Jido API for this —
verified.

## Modules

| Path | Role |
|---|---|
| `lib/psc/agent.ex` | Context: `list_sessions/1`, `get_session/2`, `create_session/2`, `rename_session/2`, `delete_session/2`, `append_message/3`, `history/2`, `prune/1` |
| `lib/psc/agent/session.ex`, `message.ex` | Schemas |
| `lib/psc/agent/turn.ex` | One turn: start agent, stream, broadcast, persist |
| `lib/psc/agent/turn_supervisor.ex` | `Task.Supervisor` for turns |
| `lib/psc/agent/canvas_agent.ex` | `use Jido.AI.Agent` — ReAct, `tools: [...]`, system prompt |
| `lib/psc/agent/tools/*.ex` | `Jido.Action` modules — `run(params, context)`, read `context[:scope]` |
| `lib/psc/agent/tools.ex` | The single list both the agent and the MCP server read |
| `lib/psc_web/live/agent_live/index.ex` | Session rail + empty state |
| `lib/psc_web/live/agent_live/chat.ex` | Single-column chat + composer |
| `lib/psc_web/mcp/plug.ex` | `ex_mcp` endpoint at `/mcp` (phase 3) |

Tools call **`Psc.Canvas` / `Psc.Notes`**, never `Repo` — same rule as the
LiveViews, and the reason an agent cannot outrun the event-sourcing invariants.

## UI

### Desktop — `/agent/:id`

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ [P] PSC   Canvases  Templates  Catalog  Agent                  [◐] [A ▾]     │
├────────────────────┬─────────────────────────────────────────────────────────┤
│  ＋ New chat        │  Weekly review prep                              ⋯      │
│                    │  read-only · 5 tools · claude-haiku                     │
│  Today             │  ─────────────────────────────────────────────────────  │
│  ▸ Weekly review…  │                                                         │
│    2m ago          │   You                                        14:02      │
│  ▸ Q3 canvas gaps  │   What changed on the Q3 canvas this week?              │
│    1h ago          │                                                         │
│                    │   Assistant                                             │
│  Yesterday         │   Let me look at your canvases.                         │
│  ▸ Roadmap ideas   │   ┌───────────────────────────────────────────────────┐ │
│                    │   │ 🔧 list_canvases                           ✓ 118ms│ │
│  Last 7 days       │   │ 3 canvases · owner, shared                        │ │
│  ▸ Onboarding note │   └───────────────────────────────────────────────────┘ │
│                    │   You edited **Q3 Planning** twice this week — once on  │
│                    │   Tuesday (cells r2_c1, r3_c2) and once Thursday.       │
│                    │                                                         │
│                    │  ┌───────────────────────────────────────────────────┐  │
│                    │  │ Ask about your canvases…                  [ ▮ ]    │  │
│                    │  │ ⏎ send · ⇧⏎ newline        [■ Stop]               │  │
│                    │  └───────────────────────────────────────────────────┘  │
└────────────────────┴─────────────────────────────────────────────────────────┘
```

### New session — `/agent`

```
┌────────────────────┬─────────────────────────────────────────────────────────┐
│  ＋ New chat        │                                                         │
│                    │              What do you want to look at?               │
│  Today             │                                                         │
│  ▸ Weekly review…  │      ┌───────────────────────────────────────────┐      │
│                    │      │  List my canvases                          │      │
│  Yesterday         │      ├───────────────────────────────────────────┤      │
│  ▸ Roadmap ideas   │      │  Summarise my notes on Q3 Planning         │      │
│                    │      ├───────────────────────────────────────────┤      │
│                    │      │  What did I change this week?              │      │
│                    │      └───────────────────────────────────────────┘      │
│                    │                                                         │
│                    │  ┌───────────────────────────────────────────────────┐  │
│                    │  │ Ask about your canvases…                  [ ▮ ]    │  │
│                    │  └───────────────────────────────────────────────────┘  │
└────────────────────┴─────────────────────────────────────────────────────────┘
```

### Mobile — rail becomes a drawer

```
┌─────────────────────────────┐     ┌─────────────────────────────┐
│ ☰  Weekly review prep    ⋯  │     │ Sessions              ✕     │
│ ─────────────────────────── │     │ ＋ New chat                 │
│ You                         │     │ Today                       │
│ What changed on the Q3…     │     │ ▸ Weekly review…            │
│                             │     │ Yesterday                   │
│ Assistant                   │     │ ▸ Roadmap ideas             │
│ ┌─────────────────────────┐ │     └─────────────────────────────┘
│ │ 🔧 list_canvases  ✓ 118 │ │
│ └─────────────────────────┘ │
│ You edited **Q3 Planning**… │
│                             │
│ ┌─────────────────────────┐ │
│ │ Ask…              [ ▮ ] │ │
│ └─────────────────────────┘ │
└─────────────────────────────┘
```

### States to build, not to discover

| State | Rendering |
|---|---|
| Empty session | Suggested prompts (above) |
| Thinking | Cursor in the assistant bubble + `Stop` enabled |
| Tool running | Card with spinner, tool name, elapsed; collapses to a one-line summary on result |
| Streaming answer | Token append into a single node; no re-render of earlier messages |
| Cancelled | Grey bubble, "Stopped" + `Retry` |
| Error | Red-bordered bubble, provider message, `Retry`; the user message is kept |
| Tool denied / no access | Card renders the tool's error string verbatim — it is written for the model and the user |
| Session rail empty | "No conversations yet" + `New chat` |

Tool cards are **collapsed by default** (name, status, duration); expanding shows
the arguments and the JSON result. That is the coding-agent idiom: the transcript
reads as prose, the machinery is one click away.

## Streaming contract

Topic: `agent_session:<session_id>` (subscribed on mount, unsubscribed on
terminate by LiveView).

| Event | Payload |
|---|---|
| `{:delta, message_id, text}` | assistant text chunk |
| `{:tool_started, message_id, %{name, arguments}}` | card opens |
| `{:tool_finished, message_id, %{name, status, result, duration_ms}}` | card resolves |
| `{:completed, message_id, %{usage}}` | final persisted content replaces the streamed buffer |
| `{:failed, message_id, reason}` | error card |
| `{:cancelled, message_id}` | stopped card |

The final `:completed` event replaces the accumulated buffer with the persisted
text, so a dropped chunk can never leave the UI different from the database.

## Tools (v1, read-only) and MCP

| Tool | Args | Returns |
|---|---|---|
| `list_templates` | — | built-in + own + shared templates |
| `list_canvases` | — | owned + shared, marked `owner`/`shared` |
| `get_canvas` | `id` | metadata + cell matrix |
| `list_notes` | `canvas_id` | note titles + ids |
| `get_note` | `note_id` | title + Markdown content |

Same modules back `ex_mcp` at `/mcp` in phase 3 — one `Jido.Action`, two
transports. Nothing in the tab's tool list may exist in only one place.

## Config and environment

| Var | Purpose |
|---|---|
| `AGENT_MODEL` | e.g. `anthropic:claude-haiku-4-5` (req_llm spec); unset ⇒ the tab is disabled with a clear message |
| Provider key | `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, … resolved by `req_llm` |
| `PSC_MCP_TOKEN` / `PSC_MCP_USER` | external MCP clients (phase 3); unset ⇒ `/mcp` 404s |
| `AGENT_MAX_TURNS` | ReAct loop ceiling, default 8 |

`config :jido_ai, model_aliases: %{default: ..., fast: ...}` maps friendly names
to provider specs so the UI can show a model chip without leaking a key.

## Prompt caching

**Throwaway agents do not touch the cache.** Provider caches are server-side and
content-addressed: the key is the exact token prefix (system, tool definitions,
messages) inside a provider/organisation/model. Process lifetime is not part of
it, so a brand-new turn that rebuilds an identical prefix hits the same entry a
warm process would. Long-lived agents have no advantage here; if anything they
are likelier to drift.

**No cache id needs storing** for Anthropic (breakpoint-based) or OpenAI
(caching is on by default). The only providers that want a handle are Gemini's
explicit `cachedContents` (a resource id with its own TTL) and OpenAI's optional
`prompt_cache_key` (a routing hint). We use neither.

**req_llm already implements Anthropic's automatic mode.** With
`anthropic_prompt_cache: true` it puts the breakpoint on the last tool, the
system block and the last message, and moves it forward as the history grows;
`anthropic_prompt_cache_ttl: "1h"` selects the long TTL. Reads and writes come
back as `usage.cached_tokens` and `usage.cache_creation_tokens`. The same option
path covers Bedrock, Vertex, Azure and OpenRouter.

What we must not do — each of these silently turns a hit into a miss:

| Rule | Why |
|---|---|
| System prompt is a constant: no dates, no clock, no user name | one changed byte invalidates the entire prefix |
| Tool list serialised in a stable order (sort by name) | tool definitions are part of the prefix |
| History is append-only, compacted once at the cap | a per-turn sliding window changes the prefix at message 1, so *every* turn misses |
| Replay a stored rendering of past turns, not re-serialised `jsonb` | JSONB does not preserve key order; re-rendering `tool_calls` can drift between turns |
| Persist `cached_tokens` / `cache_creation_tokens` per message | without it we cannot tell whether caching works, and we would optimise blind |

Two honest caveats: providers enforce a **minimum cacheable prefix** (small on
the large models, larger on the cheap ones), so a short system prompt plus five
tool schemas may not be cacheable at all until the conversation grows — that is
expected, not a bug. And the default TTL is short (minutes), so a user who walks
away mid-conversation pays a cache write on their next turn. Pick the 1-hour TTL
only if sessions routinely idle that long; it costs more to write.

## Safety and limits

- **Read-only by construction.** No write tools exist, so the worst a turn can do
  is read what its `scope` already allows.
- **Prompt injection.** Canvas and note content is untrusted model input. With no
  write tools the blast radius is limited to what the user could already read —
  but that content does leave for the model provider. Say so in the UI ("read-only
  · your content is sent to the model provider"), and keep sessions private.
- **Quota.** Per-user turns/hour and tokens/day, enforced in `Psc.Agent.Context`
  before a turn starts; surfaced as a friendly message.
- **Loop bound.** `AGENT_MAX_TURNS` plus a wall-clock timeout per turn.
- **Provider outage** is a message in the transcript, never a crash loop.

## Testing

| Layer | Approach |
|---|---|
| Tools | Plain ExUnit against the contexts, with two users to prove scope isolation |
| Turn | `Jido.AI.Test.expect_react/1` scripted turns — a tool call then an answer; assert the persisted rows and the broadcast events |
| LiveView | Session rail, send → streamed chunks, tool card, stop, retry, reload mid-turn |
| MCP | `initialize` / `tools/list` / `tools/call`, bearer auth, unknown tool |
| E2E | One Playwright flow against a scripted provider; the suite must never need a key |

No test may hit a network. That is a hard rule, not a preference.

## Phases

| Phase | Scope | Done when |
|---|---|---|
| P0 | Spike: one turn-scoped agent, scripted turn, events enumerated into a log | We know the event shapes and how history is seeded |
| P1 | Sessions + single-column chat, no tools | `/agent` works end to end with a scripted model |
| P2 | The 5 read-only tools + tool cards + stop | A real model answers using canvas data |
| P3 | `/mcp` for external clients (same tools), token auth | Claude Desktop lists PSC tools |
| P4 | Rename/delete, retention pruning, quota, mobile drawer | Shippable |

## Defaults taken (change any of these and the design follows)

These were open questions; they are now decided so the design is buildable as
written. Each is a one-line change if you disagree.

| # | Default | Rationale | If you change it |
|---|---|---|---|
| 1 | **Platform key with a per-user quota** (no BYO key in v1) | One less settings surface; the feature must work on first visit. `AGENT_MODEL` unset ⇒ the tab is hidden entirely, which is also the kill switch | BYO key adds a `user_settings` field and a composer-affordance, not an architecture change |
| 2 | **Title = first user message, truncated to 60 chars**, renameable | Free, instant, predictable; a title call adds latency and cost for cosmetics | Swap in a `fast` alias call inside the turn process; the rail never blocks on it |
| 3 | **Retention: 200 messages/session, 50 sessions/user**; prompt append-only to 40 then compact once | Keeps the rail scannable and the table small without throwing away the cacheable prefix every turn | Numbers live in one module attribute in `Psc.Agent` |
| 4 | **Every signed-in member**, not admin-only | It is a product surface, not an admin tool; the real gate is `AGENT_MODEL` being configured plus the per-user quota | Admin-only = one extra `on_mount` guard on the live session, same as `/admin` |
| 5 | **`Agent` in the main nav**, standalone `/agent` routes | Sessions span canvases; nesting it under a canvas would imply a canvas scope the tools do not have | Moving it later is a route + nav change only |

## One mechanic to verify before P1 (P0)

**History seeding.** A turn-scoped agent starts empty, so the prior turns have to
be handed in. Two candidates, both plausible from the source:

1. Pass the transcript as `[ContentPart]` to `ask_stream/3` (it accepts a list).
2. Seed the agent's thread context before asking.

P0 is a spike against a scripted turn: pick whichever produces correct
multi-turn behaviour, then delete the spike. Nothing else in this design depends
on the answer.

## Implementation notes

Where the shipped code differs from the plan above:

* **History seeding (P0) answered.** Jido's `ask_stream/3` accepts a string or
  content parts, and a running server's thread is not publicly seedable, so the
  transcript is *rendered into the prompt* by `Psc.Agent.Turn.render_prompt/1`.
  The first turn is sent unwrapped; later turns put earlier messages in a
  delimited block and the current message last. It is append-only and
  deterministic, which is what the caching section requires.
* **MCP is a hand-written JSON-RPC plug, not `ex_mcp`.** `initialize`,
  `tools/list`, `tools/call`, notifications and the bearer guard are ~200 lines
  that the tests cover completely, and the tool list comes from
  `Psc.Agent.Tools.mcp_specs/0`, so swapping in `ex_mcp` later changes one module.
* **Tools are invoked through `Jido.Exec.run/3`** in the MCP plug so JSON string
  keys are validated and coerced by the action schema instead of reaching
  `run/2` raw.
* **`utc_datetime_usec`, not `utc_datetime`.** A turn inserts the user message
  and the assistant placeholder in the same second; second precision made both
  transcript order and pruning order ambiguous.
* **The system prompt is not `@moduledoc`-driven**: it is a literal in
  `Psc.Agent.CanvasAgent` because Jido rejects function calls in `tools:` /
  `tool_context:` and the prompt must stay byte-stable for caching.
* **The session rail is an assign, not a stream.** A streaming answer mutates one
  message many times per second; re-inserting a stream item per token costs more
  than the bounded list walk.
* **Jido's scripted test harness is bypassed.** `Jido.AI.Test.expect_react/1`
  keys its registry by `Process.group_leader()`, and the ReAct worker runs under
  Jido's supervisor rather than the test process, so it never finds the script.
  `Turn.run/4` therefore accepts `script: [...]`, and one test drives the real
  Jido path against an unresolvable model to prove it fails gracefully.