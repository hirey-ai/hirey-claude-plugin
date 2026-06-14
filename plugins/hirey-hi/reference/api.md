# Hirey Hi — REST API reference

This reference is loaded on demand by the `hi-onboard`, `hi-use`, and `hi-events` skills. It documents every endpoint the assistant calls and the lifecycle of the cached credentials.

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

### Activation / status

| Endpoint | Purpose | Idempotent? |
|---|---|---|
| `POST /v1/agents/activate` (body `{}`) | Move install from `pending` → `active`. Safe to call on every bootstrap. | Yes |
| `GET  /v1/agents/me` | Returns `{agent, installation}` for the current bearer's install. | Read |
| `GET  /v1/agents/me/installation` | Just the installation portion. | Read |
| `GET  /v1/agents/me/endpoints` | What delivery endpoints (if any) the install has registered. | Read |
| `GET  /v1/agents/me/subscriptions` | Topic subscriptions for events. | Read |

### Capability catalog (the actual Hi tools)

```
GET  /v1/capabilities                              # list all capabilities (no auth)
GET  /v1/capabilities/<cap_id>                     # capability metadata (no auth)
GET  /v1/capabilities/<cap_id>/schema              # JSON Schema for the request body (no auth)
POST /v1/capabilities/<cap_id>/call                # invoke (Bearer required)
```

`<cap_id>` examples (full list comes from `/v1/capabilities`):

| Capability ID | Tool name | What it does |
|---|---|---|
| `hi.agent-listings` | `agent_listings` | CRUD on the user's search listings ("I want to find …") |
| `hi.listing-taxonomy` | `listing_taxonomy` | Read-only taxonomy of `listing_kind` / `subkind` values |
| `hi.matching-sessions` | `matching_sessions` | Pull the ranked match feed for a listing; mark candidates for contact |
| `hi.pairings` | `pairings` | Open and continue 1:1 message threads with matched people |
| `hi.thread-meetings` | `thread_meetings` | Propose / confirm meetings inside a pairing |
| `hi.agent-credits` | `agent_credits` | Read-only credits balance and ledger |
| `hi.google-link` | `google_link` | **Default** owner-identity bind at the write gate — Sign in with Google (`start` → surface `verification_url`, `poll` until `status:"verified"`) |
| `hi.phone-binding` | `phone_binding` | Fallback owner-identity bind — `bind` (phone) → `verify` (SMS code) |
| `hi.email-binding` | `email_binding` | Fallback owner-identity bind — `bind` (email) → `verify` (emailed code) |
| `hi.conversations` | `conversations` | Conversation history surface |
| `hi.social-org` | `social_org` | Org / company surface |
| `hi.social-permissions` | `social_permissions` | Permission edges between subjects |
| `hi.social-relationships` | `social_relationships` | Relationship edges (cofounder, etc.) |
| `hi.faq-get` / `hi.faq-search` | `faq_get` / `faq_search` | Public FAQ surface |
| `hi.content-get` / `hi.content-render` | `content_get` / `content_render` | Static + templated content |

Call shape:

```bash
curl -sS -X POST "https://hi.hirey.ai/v1/capabilities/hi.agent-listings/call" \
  -H "authorization: Bearer $HI_TOKEN" \
  -H 'content-type: application/json' \
  --data '{"action":"upsert","text":"need 5 senior Go engineers in San Francisco"}'
```

`status` is not accepted on `upsert` (returns `status_not_allowed_in_upsert_use_update_status`). After upsert, open the listing separately: `{"action":"update_status","listing_id":"<from upsert>","status":"open"}`.

Returns either `{ ok: true, data: {...} }` or `{ error: "...", capability_id, tool_name }`.

### Owner-identity binding at the write gate

Reading/searching works on the anonymous bootstrap credentials. The owner identity is bound only when the first WRITE hits the write gate — the capability call returns `phone_binding_required` / `caller_owner_unresolved`. **Default anchor: Sign in with Google** via `hi.google-link`; `hi.phone-binding` and `hi.email-binding` are the fallbacks. All three are write-gate-exempt (callable on the anonymous bearer) and converge to the **same** workspace — the same Google account / phone / email never creates a second one.

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

### Event surface

| Endpoint | Method | Purpose |
|---|---|---|
| `/v1/agent-events/stream` | GET | Long-poll for inbound events. Query param `timeout_ms` (default 30000, cap ~30s). |
| `/v1/agent-events/claim` | POST | Claim a lease-protected batch. Body `{lease_ms?: 60000, max?: 50}`. |
| `/v1/agent-events/:eventId` | GET | Fetch a single event's full payload (claim-only). |
| `/v1/agent-events/ack` | POST | Ack events. Body `{event_ids: [...], lease_id?: "..."}`. |

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

Codex CLI and OpenClaw still use the MCP path (`hi-mcp-server` is a separate service at `https://hi.hirey.ai/mcp`). That path's identity model (per-install DCR + PKCE) and this skill's model (per-install client_credentials) both end up minting one anonymous Hi subject per install — same end state, different wire.
