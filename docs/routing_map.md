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
        R1["GET /<br/>(→ /canvas when signed in, else /users/log-in)"] --> P1["PageController.home"]
        R2["/users/register"] --> V1["UserLive.Registration"]
        R3["/users/log-in"] --> V2["UserLive.Login"]
        R4["/users/log-in/:token"] --> V3["UserLive.Confirmation"]
        R5["POST /users/log-in · DELETE /users/log-out"] --> C1["UserSessionController"]
    end

    subgraph PRIV["require_authenticated_user — live_session :require_authenticated_user"]
        R7["/canvas · /canvas/:id"] --> V5["UnstrCanvasLive.Index · Editor<br/>(canvas editor)"]
        R7b["/canvases · /canvases/:id<br/>(redirects to /canvas)"] --> C2["RedirectController"]
        R8["/templates · /templates/new · /templates/:id"] --> V6["CanvasLayoutLive.Index · Editor<br/>(template designer)"]
        R9["/catalog"] --> V7["CatalogLive.Index<br/>(catalog)"]
        R10["/users/settings"] --> V8["UserLive.Settings"]
    end

    subgraph ADMIN["require_authenticated_user + require_admin — live_session :admin"]
        A1["/admin"] --> AV1["Admin.DashboardLive"]
        A2["/admin/users · /admin/templates<br/>/admin/canvases · /admin/notes"] --> AV2["Admin.*Live (Backpex)<br/>index · show · edit"]
        A4["/admin/api-keys"] --> AV4["Admin.ApiKeyLive<br/>(agent keys, per account)"]
        A3["POST /admin/backpex_preferences"] --> AC3["Backpex.PreferencesController"]
    end

    subgraph DEV["dev only — dev_routes"]
        R11["/dev/dashboard"] --> V9["Phoenix.LiveDashboard"]
        R12["/dev/mailbox"] --> V10["Swoosh MailboxPreview"]
    end

    V5 --> CA2["Psc.Canvas (UnstrCanvas + cells)"]
    V5 --> NO2["Psc.Notes"]
    V6 --> CA2
    V7 --> CA2
    C2 --> CA2
    V3 --> AC2["Psc.Accounts"]
    V8 --> AC2
    C1 --> AC2
```

Route additions must land inside an **existing** `live_session` block — a
`live_session` name may only be defined once in the router. Authenticated pages go in
`live_session :require_authenticated_user`; pages that work with or without a login go
in `live_session :current_user`.

The administration scope is guarded twice: the `:require_admin` plug protects the dead
render, and the `:require_admin` `on_mount` re-checks the role on the live connection.
Backpex's preference endpoint lives in that same scope, behind the same plugs.

## Related diagrams

- [architecture.md](architecture.md) — system-wide layering
- [data_model.md](data_model.md) — what each LiveView persists to
