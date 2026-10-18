# Routing map

Which pipeline and `live_session` scope serves each route, and which context backs it.
Authentication lives entirely at the router level: `:fetch_current_scope_for_user` runs
in the `:browser` pipeline, and each `live_session` attaches the matching `on_mount`
hook.

Terminology: a **canvas** is a configurable workspace instance; a **template** is the
reusable structure it is created from.

```mermaid
flowchart TD
    subgraph PUB["pipeline :browser (no auth) — live_session :current_user"]
        R1["GET /"] --> P1["PageController.home"]
        R2["/users/register"] --> V1["UserLive.Registration"]
        R3["/users/log-in"] --> V2["UserLive.Login"]
        R4["/users/log-in/:token"] --> V3["UserLive.Confirmation"]
        R5["POST /users/log-in · DELETE /users/log-out"] --> C1["UserSessionController"]
    end

    subgraph PRIV["require_authenticated_user — live_session :require_authenticated_user"]
        R6["/documents · /documents/:id"] --> V4["DocumentLive.Index · Editor"]
        R7["/canvases · /canvases/:id"] --> V5["UnstrCanvasLive.Index · Editor<br/>(canvas editor)"]
        R8["/templates · /templates/new · /templates/:id"] --> V6["CanvasLayoutLive.Index · Editor<br/>(template designer)"]
        R9["/psc-canvas · /psc-canvas/:id"] --> V7["CanvasLive.Index · Editor<br/>(fixed 12-cell PSC)"]
        R10["/users/settings"] --> V8["UserLive.Settings"]
    end

    subgraph DEV["dev only — dev_routes"]
        R11["/dev/dashboard"] --> V9["Phoenix.LiveDashboard"]
        R12["/dev/mailbox"] --> V10["Swoosh MailboxPreview"]
    end

    V4 --> DC2["Psc.Documents"]
    V5 --> CA2["Psc.Canvas (UnstrCanvas + cells)"]
    V6 --> CA2
    V7 --> CA3["Psc.Canvas (Canvas + cell embeds)"]
    V3 --> AC2["Psc.Accounts"]
    V8 --> AC2
    C1 --> AC2
```

Route additions must land inside an **existing** `live_session` block — a
`live_session` name may only be defined once in the router. Authenticated pages go in
`live_session :require_authenticated_user`; pages that work with or without a login go
in `live_session :current_user`.

## Related diagrams

- [architecture.md](architecture.md) — system-wide layering
- [data_model.md](data_model.md) — what each LiveView persists to
