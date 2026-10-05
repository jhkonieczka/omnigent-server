#!/bin/sh
# Studio + host in one container (Jay 2026-10-05). Order: credentials → kit + market repos → franchise folders →
# server (background) → login → host → wait. Every secret comes from the environment; nothing is baked in.
set -e
export HOME=/data
mkdir -p /data/.omnigent /data/projects /data/franchises /data/Projects /data/.config/gp-engine /data/.config/companycam /data/.config/comp-finder /data/.claude/skills
umask 077

# ---- credentials the kit reads from files (installer-placed on a franchisee's Mac; here from env)
[ -n "${ENGINE_CREDENTIALS:-}" ]   && printf '%s' "$ENGINE_CREDENTIALS"   > /data/.config/gp-engine/credentials
[ -n "${COMPANYCAM_API_KEY:-}" ]   && printf '%s' "$COMPANYCAM_API_KEY"   > /data/.config/companycam/api-key
[ -n "${COMPFINDER_API_KEY:-}" ]   && printf '%s' "$COMPFINDER_API_KEY"   > /data/.config/comp-finder/api-key
umask 022

# ---- Claude Code: corporate seat via CLAUDE_CODE_OAUTH_TOKEN (read by the CLI itself); MCP servers at user scope
# (no per-project approval prompt): gp-estimator (Airtable through the corporate estimates MCP, franchise-scoped key)
# and HubSpot read-only.
python3 - <<'PY'
import json, os
p = "/data/.claude.json"
try:
    d = json.load(open(p))
except Exception:
    d = {}
m = d.setdefault("mcpServers", {})
if os.environ.get("COMPFINDER_API_KEY"):
    m["gp-estimator"] = {"type": "http", "url": os.environ.get("ESTIMATES_MCP_URL", "https://estimator.gopainting.com/api/mcp"),
                         "headers": {"Authorization": "Bearer " + os.environ["COMPFINDER_API_KEY"]}}
if os.environ.get("HUBSPOT_READ_TOKEN"):
    m["hubspot"] = {"type": "stdio", "command": "npx", "args": ["-y", "@hubspot/mcp-server"],
                    "env": {"PRIVATE_APP_ACCESS_TOKEN": os.environ["HUBSPOT_READ_TOKEN"]}}
d["hasCompletedOnboarding"] = True
json.dump(d, open(p, "w"), indent=1)
s = "/data/.claude/settings.json"
try:
    st = json.load(open(s))
except Exception:
    st = {}
st.setdefault("permissions", {})["defaultMode"] = os.environ.get("CLAUDE_PERMISSION_MODE", "auto")
json.dump(st, open(s, "w"), indent=1)
PY

# ---- the proposal kit (read-only library) and per-franchise market repos, cloned or fast-forwarded every start
auth_url() { # add a token to a GitHub https URL when one is configured
  case "$1" in https://github.com/*) [ -n "${GITHUB_TOKEN:-}" ] && echo "https://x-access-token:${GITHUB_TOKEN}@github.com/${1#https://github.com/}" || echo "$1" ;; *) echo "$1" ;; esac; }
sync_repo() { # $1 url  $2 dir
  if [ -d "$2/.git" ]; then git -C "$2" fetch -q origin && git -C "$2" reset -q --hard origin/HEAD 2>/dev/null || git -C "$2" pull -q --ff-only || true
  else git clone -q --depth 1 "$(auth_url "$1")" "$2" || echo "WARN: could not clone $1" ; fi
  [ -d "$2/.git" ] && git -C "$2" remote set-url origin "$1" || true; }
KIT_URL="${KIT_GIT_URL:-https://github.com/shaungopainting/gp-proposal-skills.git}"
echo "github token: $([ -n "${GITHUB_TOKEN:-}" ] && echo "set (${#GITHUB_TOKEN} chars)" || echo MISSING); kit url: $(auth_url "$KIT_URL" | sed 's#x-access-token:[^@]*@#x-access-token:<tok>@#')"
git -c credential.helper= ls-remote "$(auth_url "$KIT_URL")" HEAD >/dev/null 2>&1 && echo "kit repo reachable" || echo "WARN: kit repo NOT reachable with the token"
export GIT_TERMINAL_PROMPT=0
sync_repo "$KIT_URL" /data/Projects/gp-proposal-skills
for s in estimator estimator-airtable-load gp-pipeline gp-proposal-writer gp-schedule-a; do
  [ -d "/data/Projects/gp-proposal-skills/$s" ] && ln -sfn "/data/Projects/gp-proposal-skills/$s" "/data/.claude/skills/$s"; done

# ---- franchises: FRANCHISES is JSON {"BOS-JK": {"market": "Boston", "owner": "Jay Konieczka", "market_repo": "https://github.com/.../gp-market-BOS-JK.git"}, ...}
# Each gets /data/franchises/<CODE>/{CLAUDE.md, Projects/, market-reference/, market-notes.md}; a session's workspace
# is /data/franchises/<CODE>/Projects, so Claude Code reads the franchise CLAUDE.md from the parent folder.
python3 - <<'PY'
import json, os, subprocess
fr = json.loads(os.environ.get("FRANCHISES", "{}") or "{}")
tpl = "/data/Projects/gp-proposal-skills/onboarding/machine-claude-template.md"
base_tpl = open(tpl).read() if os.path.exists(tpl) else "Go Painting of [MARKET] ([FRANCHISE-CODE], [Owner Name]).\n"
for code, f in fr.items():
    root = f"/data/franchises/{code}"
    os.makedirs(f"{root}/Projects", exist_ok=True)
    txt = base_tpl.replace("[MARKET]", f.get("market", code)).replace("[FRANCHISE-CODE]", code).replace("[Owner Name]", f.get("owner", ""))
    txt = txt.replace("~/Projects/market-reference/", f"{root}/market-reference/").replace("~/Projects/market-notes.md", f"{root}/market-notes.md")
    txt = txt.replace("~/Projects/CLAUDE.md", f"{root}/CLAUDE.md").replace("~/Projects/gp-proposal-skills", "/data/Projects/gp-proposal-skills")
    txt += ("\n\n## This machine is the Studio server (2026-10-05)\n"
            "- Deal folders live under `%s/Projects/<code>_<Property>/`; the proposal engine is the record for every deal file, so nothing is copied to Drive.\n"
            "- The owner works in the engine workspace beside this session: never paste editor or customer-view links; the owner presses Send there.\n"
            "- CompanyCam, the estimates MCP (gp-estimator) and HubSpot (read-only) are already connected; never ask the owner for a key.\n" % root)
    open(f"{root}/CLAUDE.md", "w").write(txt)
    open(f"{root}/market-notes.md", "a").close()
    if f.get("market_repo"):
        subprocess.call(["sh", "-c", 'auth_url() { case "$1" in https://github.com/*) [ -n "${GITHUB_TOKEN:-}" ] && echo "https://x-access-token:${GITHUB_TOKEN}@github.com/${1#https://github.com/}" || echo "$1" ;; *) echo "$1" ;; esac; }; '
                        f'd="{root}/market-reference"; u="{f["market_repo"]}"; if [ -d "$d/.git" ]; then git -C "$d" fetch -q origin && git -C "$d" reset -q --hard origin/HEAD || true; else git clone -q --depth 1 "$(auth_url "$u")" "$d" || echo "WARN: no market repo for {code}"; fi; [ -d "$d/.git" ] && git -C "$d" remote set-url origin "$u" || true'])
print("franchises:", ", ".join(fr) or "(none)")
PY

# ---- server, then this container registers itself as the host
omnigent server --host 0.0.0.0 --port 6767 --agent /opt/agents/proposals &
SERVER_PID=$!
for i in $(seq 1 60); do curl -sf -o /dev/null http://127.0.0.1:6767/ && break; sleep 1; done
if [ -n "${OMNIGENT_ACCOUNTS_INIT_ADMIN_USERNAME:-}" ] && [ -n "${OMNIGENT_ACCOUNTS_INIT_ADMIN_PASSWORD:-}" ]; then
  printf '%s\n%s\n' "$OMNIGENT_ACCOUNTS_INIT_ADMIN_USERNAME" "$OMNIGENT_ACCOUNTS_INIT_ADMIN_PASSWORD" | omnigent login http://127.0.0.1:6767 || echo "WARN: host login failed"
  # the host daemon runs as a sibling process with its output on this container's stdout (Coolify logs), not detached
  (omnigent --log-to-stderr host http://127.0.0.1:6767 --no-open --non-interactive 2>&1 | sed 's/^/[host] /') &
  sleep 25
  echo "--- host status"; omnigent host status 2>&1 | sed 's/^/[host-status] /' | head -30
fi
wait $SERVER_PID
