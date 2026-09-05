# Hirey Hi — REST API reference

This reference is loaded on demand by the `hi-onboard`, `hi-use`, `hi-events`, and `hi-repair` skills. It documents every endpoint the assistant calls and the lifecycle of the cached credentials.

All endpoints are under `https://hi.hirey.ai` unless otherwise noted.

## Credentials file

`~/.config/hi/credentials.json` (mode 600, dir mode 700):

```json
{
  "client_id":             "hagc_agit_<12hex>",
  "client_secret":         "<43-char base64url>",
  "agent_id":              "ag_<12hex>",
  "installation_id":       "agit_<12hex>",
  "issuer":                "https://hi.hirey.ai",
  "audience":              "hirey-hi",
  "token_url":             "https://hi.hirey.ai/oauth/token",
  "platform_base_url":     "https://hi.hirey.ai",
  "access_token":          "<RS256 JWT, ~1KB>",
  "access_token_issued_at":   1779432232,
  "access_token_expires_in":  3600
}
```

The `client_id` + `client_secret` pair is long-lived (no expiry advertised today). The `access_token` lives ~1h; refresh it with the cached pair whenever it's within 5 minutes of expiry.

## Bootstrap endpoints (no auth)

### `POST /v1/agents/register`

Registers a fresh anonymous agent + installation, returns ready-to-use credentials. **No auth required.**

Request body (everything optional):

```json
{
  "display_name": "Claude Code (Hirey plugin)",
  "agent_kind":   "external",
  "metadata":     { "host": "claude-code" }
}
```

Response (200):

```json
{
  "agent":        { "agent_id": "ag_<12hex>", "display_name": "...", "status": "active", ... },
  "installation": { "installation_id": "agit_<12hex>", "status": "pending", ... },
  "auth": {
    "grant_type": "client_credentials",
    "client_id":     "hagc_agit_<12hex>",
    "client_secret": "<base64url>",
    "issuer":        "https://hi.hirey.ai",
    "audience":      "hirey-hi",
    "token_url":     "https://hi.hirey.ai/oauth/token"
  },
  "contract": { "version": "v1", "scopes": [...] }
}
```

Save everything except `client_secret` and `access_token` indiscriminately; both `client_secret` and (later) `access_token` are secret and need 600 perms on the file containing them.

### `POST /oauth/token`

`client_credentials` grant. **No bearer required**, but client_id + client_secret in the body.

Request (form-urlencoded):

```
grant_type=client_credentials&client_id=<>&client_secret=<>&audience=hirey-hi
```

Response (200):

```json
{ "access_token": "eyJ…", "token_type": "Bearer", "expires_in": 3600 }
```

## Authenticated endpoints (Bearer)

All require `Authorization: Bearer <access_token>`.

### Installation status

| Endpoint | Purpose | Idempotent? |
|---|---|---|
| `GET  /v1/agents/me` | Returns `{agent, installation}` for the current bearer's install. | Read |
| `GET  /v1/agents/me/installation` | Just the installation portion. | Read |
| `GET  /v1/agents/me/endpoints` | What delivery endpoints (if any) the install has registered. | Read |
| `GET  /v1/agents/me/subscriptions` | Topic subscriptions for events. | Read |

`installation.status="pending"` is a valid anonymous state: public reads are available immediately. Do not call the retired activation endpoint or treat pending as a failed install. Verified identity binding unlocks private Workspace reads and writes.

### Capability catalog (the actual Hi tools)

```
GET  /v1/capabilities                              # list all capabilities (no auth)
GET  /v1/capabilities/<cap_id>                     # capability metadata (no auth)
GET  /v1/capabilities/<cap_id>/schema              # JSON Schema for the request body (no auth)
POST /v1/capabilities/<cap_id>/call                # invoke (Bearer required)
```

The business surface is intentionally narrow:

| Capability ID | Tool name | What it does |
|---|---|---|
| `hi.workspace-workflows` | `workspace_workflows` | Canonical Core operations. Call `action:"catalog"` first. |
| `hi.google-link` | `google_link` | **Default** owner-identity bind at the write gate — Sign in with Google (`start` → surface `verification_url`, `poll` until `status:"verified"`) |
| `hi.phone-binding` | `phone_binding` | Fallback owner-identity bind — `bind` (phone) → `verify` (SMS code) |
| `hi.email-binding` | `email_binding` | Fallback owner-identity bind — `bind` (email) → `verify` (emailed code) |

Call shape:

```bash
curl -sS -X POST "https://hi.hirey.ai/v1/capabilities/hi.workspace-workflows/call" \
  -H "authorization: Bearer $HI_TOKEN" \
  -H 'content-type: application/json' \
  -H 'x-hirey-plugin-host: claude' \
  -H 'x-hirey-plugin-version: 0.2.6' \
  --data '{"action":"people.find","payload":{"query":"senior Go engineers in San Francisco"}}'
```

Business inputs always live under `payload`. Write and external-effect operations require a stable
`idempotency_key`; operations marked `explicit_user_confirmation` also require the exact
`confirmation` object. The response wraps the Core operation receipt in top-level `result`.

Never call legacy business capability IDs such as `hi.owners`, `hi.agent-listings`,
`hi.matching-sessions`, `hi.pairings`, or `hi.thread-meetings`; they are not aliases and return 404.

### Owner-identity binding at the write gate

Pending credentials may call only the anonymous operations returned by `workspace_workflows`
(`people.find`, `people.explain`, and staged `capture.record`). Private Workspace work requires
verified identity. **Default anchor: Sign in with Google** via `hi.google-link`;
`hi.phone-binding` and `hi.email-binding` are fallbacks.

```bash
# start → returns a verification_url the user opens in a browser to Sign in with Google (valid ~10 min)
curl -sS -X POST "https://hi.hirey.ai/v1/capabilities/hi.google-link/call" \
  -H "authorization: Bearer $HI_TOKEN" -H 'content-type: application/json' \
  --data '{"action":"start"}'
# → { ok, link_id, verification_url, expires_at, instructions }

# poll → repeat until verified; do NOT call start again on each poll (link_id optional)
curl -sS -X POST "https://hi.hirey.ai/v1/capabilities/hi.google-link/call" \
  -H "authorization: Bearer $HI_TOKEN" -H 'content-type: application/json' \
  --data '{"action":"poll"}'
# pending  → { ok, status:"pending" }
# verified → { ok, status:"verified", workspace_id, email, joined_existing_workspace,
#              agents_in_workspace, workspace_agents:[{agent_id,device_label,status,last_seen,is_self}] }
```

The `poll` "verified" payload is identical to `hi.phone-binding` / `hi.email-binding` `verify` plus a `status` field. Errors `link_expired` / `link_already_consumed` mean the link is dead — call `start` again for a fresh URL. See the `hi-use` skill's "Binding the owner identity (Google default)" section for the agent-facing flow.

### Transport event surface

| Endpoint | Method | Purpose |
|---|---|---|
| `/v1/agent-events/stream` | GET | Transport delivery only; do not use it as the business Inbox. |
| `/v1/agent-events/claim` | POST | Claim a lease-protected batch. Body `{lease_ms?: 60000, max?: 50}`. |
| `/v1/agent-events/:eventId` | GET | Fetch a single event's full payload (claim-only). |
| `/v1/agent-events/ack` | POST | Ack transport events. Body `{event_ids: [...], lease_id?: "..."}`. |

For messages, tasks, notifications, and user-visible work, call the canonical
`agent_message.list` operation through `workspace_workflows`. Listing is read-only and must not
claim or acknowledge items.

## Public discovery (no auth)

| Endpoint | Returns |
|---|---|
| `GET /.well-known/hi-agent-platform.json` | Canonical manifest: all `/v1/agents/*` URLs, contract version, scopes. |
| `GET /.well-known/hi-recommended-versions.json` | Versions of `hi-mcp-server`, `hi-agent-receiver`, etc. (legacy OpenClaw uses these). |
| `GET /v1/capabilities` | Full capability catalog. |

If you ever need to verify the platform is reachable / which endpoints exist, hit `hi-agent-platform.json` first.

## Token lifecycle pitfalls

- The bearer JWT's `sub` is the `installation_id`, NOT `agent_id`. Don't confuse them.
- The `aud` claim is `hirey-hi` (not the platform base URL). Don't try to RFC 8707 audience-bind to `https://hi.hirey.ai/mcp` — that's the MCP endpoint's audience and it's a different code path entirely.
- `client_credentials` is replay-protected by client_secret confidentiality (kept in `~/.config/hi/credentials.json` at 600 perms). Don't put it in env vars or logs.
- If you accidentally leak the file: delete it, run `hi-onboard`, you'll get a fresh anonymous identity. The old install becomes orphan (zombie listings remain in Hi but you can no longer act on them).

## Why no OAuth, no MCP

The Hi backend treats every installation as an anonymous agent — there is no human user to authenticate. OAuth's role (proving you're the right human) doesn't apply. We use OAuth's `client_credentials` grant purely for machine-to-machine token issuance, which is functionally equivalent to a long-lived API key with rotation hooks. The plugin is pure markdown + Bash because (a) Hi already exposes everything as REST, (b) Claude Code's MCP-over-HTTP auto-trigger is broken upstream ([anthropics/claude-code#36307](https://github.com/anthropics/claude-code/issues/36307)), and (c) MCP added zero value for a remote-only, REST-natural surface.

Codex CLI and OpenClaw still use the MCP path (`hi-mcp-server` is a separate service at `https://mcp.hirey.ai/mcp`, legacy alias `https://hi.hirey.ai/mcp`). That path's identity model (a stable `hi_ak_…` API key by default, per-install DCR + PKCE browser-OAuth as fallback) and this skill's model (per-install client_credentials) both end up minting one anonymous Hi subject per install — same end state, different wire.
