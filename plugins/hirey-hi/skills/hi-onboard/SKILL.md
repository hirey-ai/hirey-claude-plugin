---
description: First-time setup for the Hirey Hi plugin. Use whenever (1) the user just installed the plugin and is about to do anything Hi-related, OR (2) `~/.config/hi/credentials.json` is missing or its `access_token` field is expired, OR (3) any subsequent `curl` to `https://hi.hirey.ai/v1/*` returned `401 invalid_token`. Bootstraps an anonymous Hi agent identity (no Hi account, no browser OAuth, no consent screen, no user click), writes a long-lived credentials file to `~/.config/hi/credentials.json`, and refreshes the bearer token from cached client_credentials. CRITICAL — this plugin does NOT use MCP, does NOT use `/mcp`, does NOT do interactive OAuth. The entire bootstrap is a few curl commands the assistant runs via Bash.
---

# Hi Onboard (one-time bootstrap, REST + client_credentials)

Hi is Hirey's people-to-people platform. This plugin gives Claude direct REST access to Hi's tools without any MCP layer, browser OAuth flow, or user interaction. Identity is anchored by a long-lived `client_credentials` pair the assistant generates and stores at `~/.config/hi/credentials.json`. Once that file exists, every subsequent Hi call uses the cached bearer token (or refreshes it via the cached client_id + client_secret).

## Use when

- the user just enabled the `hirey-hi` plugin and is about to ask for any Hi workflow
- the user types "set up hi", "install hi", "register hi"
- you are about to call a Hi REST endpoint and `[ -f ~/.config/hi/credentials.json ]` returns false
- the assistant just got a `401 invalid_token` or `agent_activation_required` from a Hi endpoint
- the user explicitly says "re-register", "reset hi identity", "log in again"

## Do not use when

- `~/.config/hi/credentials.json` already exists and the cached `access_token` is fresh (less than ~50 minutes old) — call the target Hi endpoint directly with the cached token
- the user is asking a workflow question (find, match, pair, meeting) — go to `hi-use` (which will pull credentials transparently)
- inbound events drain — go to `hi-events`

## Bootstrap sequence (assistant runs all of this via Bash, no user touch)

Run the script below verbatim. It is idempotent: if `credentials.json` already exists with valid creds, it only refreshes the token.

```bash
set -euo pipefail
HI_CRED_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hi"
HI_CRED_FILE="$HI_CRED_DIR/credentials.json"
HI_BASE="https://hi.hirey.ai"

mkdir -p "$HI_CRED_DIR"
chmod 700 "$HI_CRED_DIR"

# 1) Make sure we have a client_id + client_secret. If we don't, register a fresh anonymous agent.
if [ ! -f "$HI_CRED_FILE" ] || [ -z "$(jq -er '.client_id' "$HI_CRED_FILE" 2>/dev/null)" ]; then
  REG=$(curl -sS -X POST "$HI_BASE/v1/agents/register" \
    -H 'content-type: application/json' \
    --data '{"display_name":"Claude Code (Hirey plugin)","agent_kind":"external"}')
  echo "$REG" | jq '{
    client_id: .auth.client_id,
    client_secret: .auth.client_secret,
    agent_id: .agent.agent_id,
    installation_id: .installation.installation_id,
    issuer: .auth.issuer,
    audience: .auth.audience,
    token_url: .auth.token_url,
    platform_base_url: "'"$HI_BASE"'",
    access_token: null,
    access_token_issued_at: 0,
    access_token_expires_in: 0
  }' > "$HI_CRED_FILE"
  chmod 600 "$HI_CRED_FILE"
fi

# 2) Refresh the access_token if missing or close to expiry (5-min skew).
NOW=$(date +%s)
EXP_AT=$(( $(jq '.access_token_issued_at // 0' "$HI_CRED_FILE") + $(jq '.access_token_expires_in // 0' "$HI_CRED_FILE") - 300 ))
if [ "$NOW" -ge "$EXP_AT" ]; then
  CID=$(jq -r '.client_id' "$HI_CRED_FILE")
  CSEC=$(jq -r '.client_secret' "$HI_CRED_FILE")
  AUD=$(jq -r '.audience' "$HI_CRED_FILE")
  TOK=$(curl -sS -X POST "$HI_BASE/oauth/token" \
    --data "grant_type=client_credentials&client_id=$CID&client_secret=$CSEC&audience=$AUD")
  if [ -z "$(echo "$TOK" | jq -r '.access_token // empty')" ]; then
    echo "hi_token_refresh_failed: $TOK" >&2
    exit 1
  fi
  jq --argjson tok "$TOK" --arg now "$NOW" '
    .access_token = $tok.access_token
    | .access_token_issued_at = ($now | tonumber)
    | .access_token_expires_in = $tok.expires_in
  ' "$HI_CRED_FILE" > "$HI_CRED_FILE.tmp" && mv "$HI_CRED_FILE.tmp" "$HI_CRED_FILE"
fi

# 3) Activate the install (idempotent — second call is a no-op).
TOKEN=$(jq -r '.access_token' "$HI_CRED_FILE")
ACT=$(curl -sS -X POST "$HI_BASE/v1/agents/activate" \
  -H "authorization: Bearer $TOKEN" -H 'content-type: application/json' --data '{}')

# 4) Confirm: hit /v1/agents/me, surface status to the user.
ME=$(curl -sS "$HI_BASE/v1/agents/me" -H "authorization: Bearer $TOKEN")
echo "$ME" | jq '{agent_id: .agent.agent_id, status: .agent.status, installation_id: .installation.installation_id, installation_status: .installation.status}'
```

If any step exits non-zero or returns `error` JSON, report the error to the user verbatim and stop. Common errors:

- `agent_register_failed` — Hi platform is unreachable. Network issue, not a plugin issue. Surface the message and stop.
- `hi_auth_client_register_failed:*` — hi-auth service is down. Surface and stop.
- `invalid_grant` from `/oauth/token` — credentials file is stale (deleted client?). Delete `~/.config/hi/credentials.json` and re-run this skill from step 1.
- `installation_not_active` from `/v1/agents/activate` — server already moved the install to terminal state. Treat as fatal, surface, ask the user if they want a fresh identity (`rm ~/.config/hi/credentials.json` + redo).

## What to tell the user

After bootstrap succeeds, the entire onboarding output the user needs is one line:

> "Hi is set up. Agent ID `ag_xxxxxxxxxxxx`. Ready to find people, match candidates, schedule meetings."

Do NOT show them the client_secret, the access_token, or any other secret. The `agent_id` is fine to show.

## Why this works without OAuth/browser/clicks

Hi's `/v1/agents/register` endpoint is **deliberately unauthenticated**. Hitting it mints a fresh anonymous agent + installation + a long-lived `client_credentials` pair, all in one HTTP round trip. PKCE / browser-mediated OAuth would add user friction without adding security — there's no human identity to authenticate against (each install is its own anonymous agent), and the client_secret is generated server-side, transmitted once over TLS, and stored at user 600 perms locally.

This is the same identity model OpenClaw used (client_credentials baked into local state) — we just moved the storage from `~/.openclaw/hi-mcp/<profile>/` to `~/.config/hi/credentials.json` and dropped the local stdio MCP daemon. Every Hi tool call is a direct HTTPS POST to `https://hi.hirey.ai/v1/capabilities/<id>/call`.

## Reference (load on demand)

- Full REST API: see [../../reference/api.md](../../reference/api.md) for the complete endpoint list, capability schemas, and token lifecycle.
- Public Hi platform contract: `GET https://hi.hirey.ai/.well-known/hi-agent-platform.json` returns the canonical endpoint manifest.
