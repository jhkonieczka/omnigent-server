# omnigent-server
Container recipe for the Go Painting franchise Studio (`studio.gopainting.com`): Omnigent server in accounts mode,
and the **host** that runs every proposal session, in one container. Built and deployed by Coolify from this repo
(app `omnigent-studio`). No secrets here; everything arrives as Coolify environment variables. Written for Gustavo and
for whoever operates this next; the engine side is documented in `proposal-engine/docs/franchise-workspace-design-v0.1.md`
§12–§13.

## What runs here (2026-10-05)
- **Omnigent server** (`omnigent==0.16.0`, pinned in the Dockerfile) with `patch_samesite.py` applied at build so the
  proposal engine (`proposals.gopainting.com`) can frame and drive this Studio with the owner's own login cookie
  (`OMNIGENT_COOKIE_SAMESITE=none`, `OMNIGENT_CORS_ORIGINS`, `OMNIGENT_WS_ALLOWED_ORIGINS`). Omnigent upgrades must
  re-apply the patch (the build asserts the patched lines exist; a failing build means upstream changed the cookie code).
- **Claude Code** (Node 20, `@anthropic-ai/claude-code`) inside the container, on the seat named by
  `CLAUDE_CODE_OAUTH_TOKEN`. tmux and procps are required (the claude-native harness runs Claude Code inside tmux).
- **Two agents** registered at boot (`--agent`, both under `/opt/agents`):
  - `proposals`: the full flow (estimator → Airtable load → writer → the owner presses Send in the engine).
  - `proposals-training`: for a franchise in training. CEL policies deny the estimator and Airtable-load skills and their
    files, deny estimates-MCP writes, and deny `/engine/draft`; the session writes a walk summary (`gp-walk-summary`) and
    the first draft through the engine's Compose. The engine picks this agent when the franchise profile has
    `layout.training` (its `/engine/me` returns `agent_name: proposals-training`).
- **The host**: after the server is up, the entrypoint logs in as the seeded admin and runs `omnigent host` as a sibling
  process, registered under `OMNIGENT_HOST_NAME` (`HOST_NAME` env, default `studio-host`). Sessions take
  `workspace=/data/franchises/<CODE>/Projects`.
- **Logs**: every Omnigent log file (server, host, per-session runner) streams to the container stdout, so Coolify's log
  view shows session failures (e.g. the `tmux is not installed` traceback that broke the first sessions).

## Files and volumes
| Path (container) | What | Persistence |
|---|---|---|
| `/data` | `HOME`; `.omnigent/` (accounts DB, sessions, logs), `.claude/`, `.claude.json`, `.config/` | Coolify volume `studio-data` |
| `/data/Projects/gp-proposal-skills` | the kit, cloned or fast-forwarded at every boot from `KIT_GIT_URL`; skills symlinked into `/data/.claude/skills` | volume |
| `/data/franchises/<CODE>/` | `CLAUDE.md` (identity, written at boot from the kit template), `Projects/` (deal folders), `market-reference/` (the franchise's private market repo), `market-notes.md` | volume; `franchises/` is also bind-mounted into the engine apps as `FRANCHISE_FILES_ROOT` (prod) and `franchises-staging/` (staging) |
| `/opt/agents` | the two agent definitions | image |

The deal folder convention is the engine's: `<CODE>/Projects/<number>_<Property>/{00_intake,01_estimate,02_contractor,03_proposal}`.
The engine writes the sent PDF and the executed contract into `03_proposal`; sessions write intake, estimate and
contractor files; nothing in there is modified or deleted by the engine.

## Environment (Coolify)
| Variable | Purpose |
|---|---|
| `CLAUDE_CODE_OAUTH_TOKEN` | the Claude seat every session on this host runs on (see **Accounts** below) |
| `CLAUDE_PERMISSION_MODE` | Claude Code default mode (`auto`) |
| `OMNIGENT_ACCOUNTS_INIT_ADMIN_USERNAME` / `_PASSWORD` | seeded admin; also used by the entrypoint to log the host in |
| `OMNIGENT_CORS_ORIGINS`, `OMNIGENT_WS_ALLOWED_ORIGINS`, `OMNIGENT_COOKIE_SAMESITE=none` | let the engine frame and drive the Studio |
| `ENGINE_CREDENTIALS` | `user:password` for the engine (login `studio`, an editor login the engine hides from pickers) → `/data/.config/gp-engine/credentials` |
| `COMPANYCAM_API_KEY`, `COMPFINDER_API_KEY` | kit credential files; `COMPFINDER_API_KEY` is also the Bearer for the `gp-estimator` MCP (`ESTIMATES_MCP_URL`) |
| `HUBSPOT_READ_TOKEN` | HubSpot MCP, read-only |
| `KIT_GIT_URL`, `GITHUB_TOKEN` | kit + market repos. **The token is currently Jay's personal GitHub token; replace it with a read-only deploy key or a machine user.** |
| `FRANCHISES` | JSON `{"BOS-JK": {"market": "Boston", "owner": "Jay Konieczka", "market_repo": "https://github.com/jhkonieczka/gp-market-BOS-JK.git"}, ...}` |
| `HOST_NAME` | the registered host name (default `studio-host`; per-franchise hosts use `studio-host-<CODE>`) |

## Operations
- **A restart kills every running session** (tmux inside the container). Deploy when no one is mid-proposal; tell the
  owners first.
- **The kit is cloned at boot.** After a kit merge the host needs a restart to see it (or wait for the next deploy).
- **Adding a franchise (same host, shared seat):** add its entry to `FRANCHISES` (and create its private market repo
  from the market-reference template), set the engine's franchise profile and logins, redeploy. The boot writes
  `/data/franchises/<CODE>/CLAUDE.md`; the first upload or send creates its deal folders.
- **Adding a franchise on its own seat (own container):** deploy this same image as a second Coolify app with its own
  `CLAUDE_CODE_OAUTH_TOKEN`, `FRANCHISES` holding only that franchise, `HOST_NAME=studio-host-<CODE>`, and **no**
  server role needed if you prefer one Studio: run only the host part against the shared server (set the server URL in
  the entrypoint's `omnigent host` call; today the entrypoint starts a server too, so the simplest first version is a
  full second Studio for that franchise, pointed at by the engine's `USER_STUDIO` for that login). The engine pane
  picks the host by name: `STUDIO_SESSION_DEFAULTS` may carry `"host_name": "studio-host-{code}"`.
- **Studio password for a new user:** the admin invites from the Studio UI (accounts mode); the engine login is separate.

## Accounts: whose Claude seat runs the sessions
Today one seat (`CLAUDE_CODE_OAUTH_TOKEN`) runs every session on this host. That is the simplest setup and it is
what Boston uses. Two things to know before putting more franchisees on it: Anthropic's Team/Enterprise seats are
per person, so one seat shared by several owners is outside the terms, and a shared seat shares one rate limit (a
Boston session hit the seat limit mid-send on 10/4). The design supports the alternative with no engine change beyond
`host_name`: **one host container per franchise, each with its own token.** The token can come from a corporate
Team seat Shaun assigns to the franchisee, or from the franchisee's own Claude subscription (they run
`claude setup-token` once on their machine and hand the long-lived token to the home office). Either way the
franchisee still never holds a kit key or an engine password; those stay in the container's environment.
