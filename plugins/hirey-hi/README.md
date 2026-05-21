# Hirey Hi for Claude Code

Claude Code plugin that gives Claude first-class access to the Hi people-to-people platform — jobs, hiring, housing, friendship, dating, lawyers, founders, investors, cofounders, any human lead.

**Plugin + Remote MCP + OAuth.** Zero local install. No `npm install`, no Node daemon, no state dir. Every Hi tool call goes from Claude Code over HTTPS to `https://hi.hirey.ai/mcp`, authenticated with a bearer token that Claude Code stores in its keychain after a one-time browser OAuth.

## Install

```text
# 1) Register the Hirey marketplace (one-time; Claude Code git-clones this repo)
/plugin marketplace add hirey-ai/hirey-claude-plugin

# 2) Install the plugin
/plugin install hirey-hi@hirey

# 3) Authorize this Claude Code installation against Hi (zero-touch — see "Auth" below)
/mcp
# > select "hi" → "Authenticate"
```

Step 3 takes ~1 second. The browser opens a tab, instantly redirects back to a Claude Code loopback callback, and closes itself. **There is no Hi account to create, no consent screen to click through, no email/phone to verify** — the Hi server auto-provisions an anonymous agent identity for this Claude Code install (same model OpenClaw and Codex use).

After step 3, send Claude any people-finding request — "find me 10 backend engineers in Tokyo", "help me reach out to candidates from yesterday", "schedule a Zoom with Alex" — and it will use Hi's tools directly.

## Auth (zero-touch OAuth)

| Step | What Claude Code does | What Hi does | What the user sees |
|---|---|---|---|
| 1. First `/mcp` call | Sends no Authorization header | 401 + `WWW-Authenticate: Bearer resource_metadata="https://hi.hirey.ai/.well-known/oauth-protected-resource"` | `/mcp` panel flags `hi` as "needs authentication" |
| 2. User clicks "Authenticate" in `/mcp` | Fetches RFC 9728 metadata, then RFC 8414 AS metadata | Returns JSON with `authorization_endpoint` / `token_endpoint` / `registration_endpoint` | Nothing yet |
| 3. DCR | `POST /oauth/register` with loopback `redirect_uris` | Mints `client_id` + (silently) provisions a fresh anonymous Hi subject for this Claude Code install | Nothing |
| 4. `/authorize` | Opens browser at `/oauth/authorize?...` | **No HTML rendered.** Issues an auth code bound to the new Hi identity and 302-redirects to Claude Code's loopback callback | Browser tab opens then closes (~200ms) |
| 5. Token exchange | `POST /oauth/token` with code + PKCE verifier + RFC 8707 `resource` | Returns access token (RS256 JWT, `aud=https://hi.hirey.ai/mcp`) + rotating refresh token | Nothing |
| 6. Subsequent `/mcp` calls | `Authorization: Bearer <token>` on every request | Verifies signature + `aud` exact-match, resolves the Hi installation by `sub`, dispatches tool | Nothing |

This is the same identity model as OpenClaw and the Codex plugin: agent self-registers, no human identity is bound. If you want to later tie an installation to a phone-verified human, that's a follow-up workflow inside Hi — it has nothing to do with the OAuth flow above.

## What the plugin actually ships

```
plugins/hirey-hi/
  .claude-plugin/plugin.json   # Claude Code plugin manifest
  .mcp.json                    # remote MCP server config (type: http, url)
  skills/
    hi-onboard/SKILL.md        # first-time setup (the `/mcp` Authenticate flow)
    hi-use/SKILL.md            # post-onboarding workflows (listings/matching/pairings/meetings)
    hi-events/SKILL.md         # durable pull for inbound events
  README.md                    # this file
```

The marketplace entry at `.claude-plugin/marketplace.json` (in the repo root) points to this folder with `source: "./plugins/hirey-hi"`.

**No code**, no `package.json`, no `dist/`. Claude Code plugins are declarative — the manifest tells Claude Code where Hi lives, the skills tell the LLM how to use Hi, and the MCP server runs in Hi's cloud.

## How this differs from sibling distributions

| | OpenClaw (npm-based) | Codex plugin | Claude Code (this plugin) |
|---|---|---|---|
| Distribution | ClawHub `clawhub:hirey` / npm `@hirey/hi-mcp-server` | `codex plugin marketplace add hirey-ai/hirey-codex-plugin` | `/plugin marketplace add hirey-ai/hirey-claude-plugin` |
| Local install | `npm install` of `@hirey/hi-mcp-server` + `@hirey/hi-agent-receiver` | none | none |
| Process model | local stdio MCP child + local hi-agent-receiver | remote HTTPS, no local process | remote HTTPS, no local process |
| Auth | client_credentials baked into local state | OAuth 2.1 (DCR + PKCE) via `codex mcp login hi` | OAuth 2.1 (DCR + PKCE) via `/mcp` Authenticate |
| Event delivery | local receiver hooks + durable claim | durable claim via `hi_agent_events_wait` | durable claim via `hi_agent_events_wait` |
| State on user machine | `~/.openclaw/hi-mcp/<profile>/` | Codex keychain entry only | Claude Code keychain entry only |
| Updates | user re-runs `openclaw plugins install` | Hi backend deploy — no user action | Hi backend deploy — no user action |

All three are sibling adapters over the same Hi public capability catalog. Tool names, schemas, and semantics are identical. The plugin shell is what differs.

## Backing service

The remote MCP endpoint at `https://hi.hirey.ai/mcp` is served by `hi-mcp-server >= 0.1.24` running in HTTP mode (`HI_MCP_TRANSPORT=http`). Multi-tenant: each Claude Code installation's OAuth subject resolves to a Hi installation server-side. Tools are loaded dynamically from Hi's public capability catalog (`/v1/capabilities`) so the Claude Code tool inventory stays in sync with Hi without a plugin re-release.

## Local development / staging

To point this plugin at a staging Hi, drop a project-scoped override in your project's `.mcp.json`:

```json
{
  "mcpServers": {
    "hi": {
      "type": "http",
      "url": "https://staging.hi.hirey.ai/mcp"
    }
  }
}
```

Then re-authenticate via `/mcp` → `hi` → Authenticate.

For fully local Hi development, run `hi-mcp-server` in HTTP mode on your laptop and point Claude Code at it via the same `.mcp.json` override:

```bash
HI_PLATFORM_BASE_URL=http://127.0.0.1:3000 \
HI_MCP_TRANSPORT=http \
HI_MCP_HOST=127.0.0.1 \
HI_MCP_PORT=8788 \
hi-mcp-server
```

```json
{
  "mcpServers": {
    "hi": {
      "type": "http",
      "url": "http://127.0.0.1:8788/mcp"
    }
  }
}
```

For local dev without OAuth, attach a bearer token via the standard MCP `headers` form:

```json
{
  "mcpServers": {
    "hi": {
      "type": "http",
      "url": "http://127.0.0.1:8788/mcp",
      "headers": { "Authorization": "Bearer ${HI_DEV_TOKEN}" }
    }
  }
}
```

Then `export HI_DEV_TOKEN=<a token minted from gateway /oauth/token client_credentials>`. Never use bearer-token mode in production — it is the OpenClaw-path auth model and bypasses Hi's per-user installation binding.

## Versioning

This plugin's `version` is independent from `hi-mcp-server` and `hi-platform`. The plugin only needs to be re-released when:

- the bundled SKILL.md instructions change
- a new top-level skill (e.g. `hi-billing`) is added
- the MCP transport or URL changes
- the Claude Code minimum version changes
- the OAuth scope set advertised by Hi changes (and downstream skill copy needs updating)

Tool-level additions to Hi's capability catalog show up in Claude Code's tool inventory automatically — no plugin release required.
