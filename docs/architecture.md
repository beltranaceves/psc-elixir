# Architecture overview

`psc-elixir` is a Phoenix 1.8 / LiveView 1.2 / PostgreSQL platform for configurable
collaborative visual-inquiry tools (Problem–Solution Canvas), with CRDT-style,
event-sourced real-time collaboration.

This diagram shows the end-to-end layering: browser hooks → `PscWeb` web layer →
`Psc` domain contexts → OTP infrastructure → Postgres.

```mermaid
flowchart LR
    subgraph CLIENT["Browser — assets/js (esbuild + Tailwind v4)"]
        direction TB
        LS["LiveView client<br/>websocket /live"]
        EH["EditorHook<br/>textarea diff + cursor"]
        CH["CellHook<br/>markdown cell editing"]
        MF["MarkdownField"]
        SUI["SaladUI component hooks<br/>dialog · tabs · popover · toast …"]
    end

    subgraph WEB["PscWeb — web layer"]
        direction TB
        EP["PscWeb.Endpoint<br/>Bandit, port 4000 / PSC_PORT"]
        RT["PscWeb.Router<br/>pipeline :browser / :api<br/>live_session :require_authenticated_user · :current_user"]
        AUTH["PscWeb.UserAuth<br/>plugs + on_mount hooks"]
        LV["LiveViews<br/>Document · Canvas · UnstrCanvas · CanvasLayout · User"]
        CT["Controllers<br/>Page · UserSession"]
        CC["Components<br/>Layouts · core_components · ui/* (SaladUI)"]
    end

    subgraph CTX["Psc — domain contexts"]
        direction TB
        AC["Accounts<br/>User · UserToken · Scope · UserNotifier"]
        DC["Documents<br/>Document · DocumentEvent"]
        CA["Canvas<br/>Canvas (12 cell embeds) · UnstrCanvas · CanvasLayout"]
        SYN["Sync engines<br/>CRDT · SnapshotManager · ConsistencyManager<br/>UnstrCanvasCRDT"]
    end

    subgraph INF["OTP / infrastructure"]
        direction TB
        SUP["Psc.Application<br/>one_for_one"]
        REPO["Psc.Repo<br/>Ecto / Postgrex"]
        PUBSUB["Phoenix.PubSub<br/>Psc.PubSub"]
        PRES["PscWeb.Presence"]
        TELE["PscWeb.Telemetry"]
        DNS["DNSCluster"]
        MAIL["Psc.Mailer<br/>Swoosh"]
    end

    PG[("PostgreSQL")]
    GIG["Gigalixir release<br/>migrate-on-boot"]

    LS --- EH
    LS --- CH
    LS --- MF
    LS --- SUI
    EH -->|"update_content · update_cursor"| LV
    CH -->|"update_cell · render_field"| LV
    LV -->|"content_updated · cell_updated · field_rendered"| LS

    EP --> RT --> AUTH --> LV
    RT --> CT
    LV --> CC

    LV --> AC
    LV --> DC
    LV --> CA
    DC --> SYN
    CA --> SYN

    AC --> REPO
    DC --> REPO
    CA --> REPO
    DC --> PUBSUB
    CA --> PUBSUB
    LV <--> PUBSUB
    LV --> PRES
    REPO --> PG
    EP --> TELE
    DNS -.-> EP
    MAIL -.-> AC
    GIG -.-> EP
```

## Related diagrams

- [design-decisions.md](design-decisions.md) — why these structures are the way they are (ADR log)
- [supervision_tree.md](supervision_tree.md) — OTP process tree under `Psc.Application`
- [documents_collaboration_flow.md](documents_collaboration_flow.md) — event-sourced text documents
- [unstr_canvas_collaboration_flow.md](unstr_canvas_collaboration_flow.md) — per-cell canvas editing
- [data_model.md](data_model.md) — Ecto schemas and tables
- [routing_map.md](routing_map.md) — routes, pipelines, and `live_session` scopes
