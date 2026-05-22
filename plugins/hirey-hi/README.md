# Hirey Hi for Claude Code

Claude Code plugin that gives Claude first-class access to the Hi people-to-people platform — jobs, hiring, housing, friendship, dating, lawyers, founders, investors, cofounders, any human lead.

**Plugin + Remote MCP + OAuth.** Zero local install. No `npm install`, no Node daemon, no state dir. Every Hi tool call goes from Claude Code over HTTPS to `https://hi.hirey.ai/mcp`, authenticated with a bearer token that Claude Code stores in its keychain after a one-time browser OAuth.

## Install

```text
# 1) Register the Hirey marketplace (one-time; Claude Code git-clones this repo)
/plugin marketplace add hirey-ai/hirey-claude-plugin

# 2) Install the plugin
/plugin install hirey-hi@hirey

# 3) Authorize via the /mcp panel
/mcp
# > arrow-key to `plugin:hirey-hi:hi` → press Enter → Authenticate
```

Step 3 opens a browser tab, redirects to a Claude Code loopback callback (port 7717), and closes itself in about a second. **There is no Hi account to create, no consent screen to click through, no email/phone to verify** — Hi auto-provisions a fresh anonymous agent identity for every install (same anonymity model OpenClaw and Codex use).

After authorization, send Claude any people-finding request — "find me 10 backend engineers in Tokyo", "help me reach out to candidates from yesterday", "schedule a Zoom with Alex" — and it will use Hi's tools directly.

> **Why step 3 isn't fully automatic.** Claude Code's plugin OAuth has an open bug ([anthropics/claude-code#36307](https://github.com/anthropics/claude-code/issues/36307)) — the browser flow does not fire on plugin enable, even with the Slack-pattern `oauth.clientId` pre-registered in `.mcp.json`. We ship that pre-registration anyway so step 3 skips Dynamic Client Registration (token issuance is one fewer round-trip) and stays anonymous per install via Hi's `mints_subject_per_authorize` flag. When Anthropic fixes #36307, the `/mcp` step should drop out automatically with no plugin re-release needed.

## Auth (pre-registered client_id + per-`/authorize` subject mint)

The plugin ships a pre-registered OAuth client (`oac_ETbApJKcMETA7spK-ZNK05j8`) and a fixed loopback callback port (`7717`) baked into `.mcp.json`'s `oauth` block. When you click Authenticate in `/mcp`, Claude Code uses this client_id directly instead of doing Dynamic Client Registration. The Hi authorization server has `metadata_json.mints_subject_per_authorize` set on this client, so every `/authorize` call mints a fresh anonymous `subject_id` — two Claude Code installs talking to the same client_id end up with two different agent identities on the Hi side, preserving the per-install anonymity that DCR-based callers (Codex, OpenClaw) get for free.

| Step | What Claude Code does | What Hi does | What the user sees |
|---|---|---|---|
| 1. `/mcp` → `plugin:hirey-hi:hi` → Authenticate | Starts loopback listener on `localhost:7717`, opens browser at `https://auth.hi.hirey.ai/oauth/authorize?client_id=oac_…&redirect_uri=http://localhost:7717/callback&code_challenge=…&code_challenge_method=S256&resource=https://hi.hirey.ai/mcp` | Mints a **fresh anonymous subject** (per-install identity), issues an auth code bound to it, 302-redirects to the loopback callback. **No HTML rendered, no consent screen.** | Browser tab opens then closes (~1s) |
| 2. Token exchange | `POST /oauth/token` with code + PKCE verifier + RFC 8707 `resource` | Returns access token (RS256 JWT, `aud=https://hi.hirey.ai/mcp`, `sub=<new subject>`) + rotating refresh token | Nothing |
| 3. Subsequent `/mcp` calls | `Authorization: Bearer <token>` on every request | Verifies signature + `aud` exact-match, resolves the Hi installation by `sub`, dispatches tool | Nothing |

Same end-state as OpenClaw and the Codex plugin: agent self-registers, no human identity is bound. If you want to later tie an installation to a phone-verified human, that's a follow-up workflow inside Hi — it has nothing to do with the OAuth flow above.

## What the plugin actually ships

```
plugins/hirey-hi/
  .claude-plugin/plugin.json   # Claude Code plugin manifest
  .mcp.json                    # remote MCP server config (type + url + oauth.clientId + oauth.callbackPort)
  skills/
    hi-onboard/SKILL.md        # first-time setup fallback (only if the auto-flow didn't fire)
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
| Auth | client_credentials baked into local state | OAuth 2.1 (DCR + PKCE) via `codex mcp login hi` | OAuth 2.1 (pre-registered client_id + PKCE) via `/mcp` Authenticate; per-`/authorize` subject minting keeps each install anonymous. Browser flow auto-trigger on enable is blocked by [#36307](https://github.com/anthropics/claude-code/issues/36307); the `/mcp` step will drop out when that's fixed |
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
