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
  "status":                "pending",
  "issuer":                "https://hi.hirey.ai",
  "audience":              "hirey-hi",
  "token_url":             "https://hi.hirey.ai/oauth/token",
  "platform_base_url":     "https://hi.hirey.ai",
  "access_token":          "<pending opaque token or active-session JWT>",
  "access_token_issued_at":   1779432232,
  "access_token_expires_in":  3600
}
```

The `client_id` + `client_secret` pair is long-lived (no expiry advertised today). Use the returned `access_token_expires_in`; refresh it with the cached pair whenever it's within 5 minutes of expiry.

## Bootstrap endpoints (no auth)

### `POST /v1/agents/api-keys`

Creates one pending Agent, backed only by the current Core database. No human Person is created.
Request: `{"agent_type":"claude","display_name":"Claude Code (Hirey skill)","client_version":"0.2.6"}`.
Response: `{"api_key":"hi_ak_<base64url>","agent_id":"ag_...","status":"pending"}`.

The envelope decodes to `{"v":1,"id":"<client_id>","secret":"<client_secret>"}`.
Validate the prefix, base64url, JSON version, and nonempty string fields before saving;
store decoded credentials, not an additional API-key copy. The endpoint does not accept
referral channel metadata. Report unsupported attribution instead of silently dropping it.

This endpoint is not idempotent. Both installer and onboard hold `.register.lock` and persist
a non-secret `.registration-pending.json` fence before POST. Keep the fence after network,
HTTP, or malformed-response failures. Never delete it and retry automatically: the request
may already have created an Agent. Only successful atomic credential persistence removes it.
Existing credentials are reused, never replaced by a new registration.

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

A successful client-credentials token exchange confirms installation authentication.
Pending credentials receive an opaque `hi_ai_` token, not an active-session JWT.
Do not call `GET /v1/agents/me` as a pending-install success gate: that route requires an
active, verified Agent Session. After binding and refreshing, it returns flat
`account_id/person_id/workspace_id/agent_id/agent_session_id` plus `agent`, not an
`installation` object.

Hold the shared `.register.lock` through freshness re-read and token refresh because refreshing
a pending token invalidates its previous bearer. Claude and Hermes share this format under
`${XDG_CONFIG_HOME:-$HOME/.config}/hi/credentials.json`; isolated acceptance must honor XDG.
After an explicitly consented binding returns verified, use the guarded onboard script with
`HI_FORCE_TOKEN_REFRESH=1`, then verify the flat identity returned by `/v1/agents/me`.
Do not trust the historical local installation `status` or JWT shape as proof of login.

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
curl -sS --connect-timeout 5 --max-time 30 -X POST "https://hi.hirey.ai/v1/capabilities/hi.workspace-workflows/call" \
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
curl -sS --connect-timeout 5 --max-time 30 -X POST "https://hi.hirey.ai/v1/capabilities/hi.google-link/call" \
  -H "authorization: Bearer $HI_TOKEN" -H 'content-type: application/json' \
  --data '{"action":"start"}'
# → { ok, link_id, verification_url, expires_at, instructions }

# poll → repeat until verified; do NOT call start again on each poll (link_id optional)
curl -sS --connect-timeout 5 --max-time 30 -X POST "https://hi.hirey.ai/v1/capabilities/hi.google-link/call" \
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

- Pending `hi_ai_` tokens are opaque. Active JWT `sub` is the canonical Agent ID; `sid` is the Agent Session ID.
- The `aud` claim is `hirey-hi` (not the platform base URL). Don't try to RFC 8707 audience-bind to `https://hi.hirey.ai/mcp` — that's the MCP endpoint's audience and it's a different code path entirely.
- `client_credentials` is replay-protected by client_secret confidentiality (kept in `~/.config/hi/credentials.json` at 600 perms). Don't put it in env vars or logs.
- If credentials leak, stop and arrange credential revocation/recovery. Do not delete the identity and silently register a replacement.

## Host transport

Claude Code uses pure skills plus REST. Normal installation is anonymous; private data and
writes require explicit verified identity binding. Pending and active credentials converge on
the same Agent, Person and Workspace through the current backend contract. Do not infer
active identity from installation alone or substitute Codex credentials for host acceptance.
