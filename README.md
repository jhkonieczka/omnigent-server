# omnigent-server
Container recipe for the Go Painting franchise Studio (studio.gopainting.com): Omnigent server, accounts mode,
one proposals agent. Built by Coolify from this repo. No secrets here; see the Coolify environment.

## The server is the host (2026-10-05)
Claude Code runs inside this container on the corporate seat (`CLAUDE_CODE_OAUTH_TOKEN`); `entrypoint.sh` writes the
kit's credential files from env (`ENGINE_CREDENTIALS`, `COMPANYCAM_API_KEY`, `COMPFINDER_API_KEY`), the user-scope MCP
servers (gp-estimator, HubSpot read-only from `HUBSPOT_READ_TOKEN`), clones the kit (`KIT_GIT_URL`, `GITHUB_TOKEN`)
and each franchise's market repo (`FRANCHISES` JSON), writes `/data/franchises/<CODE>/CLAUDE.md`, starts the server,
logs in as the seeded admin and registers itself as the host. Sessions take `workspace=/data/franchises/<CODE>/Projects`.
The engine (`proposals.gopainting.com`) frames and drives this Studio with the owner's login: `OMNIGENT_CORS_ORIGINS`,
`OMNIGENT_COOKIE_SAMESITE=none` and `patch_samesite.py` (applied at build) make that work.
