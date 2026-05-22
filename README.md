# Hirey for Claude Code

The official Claude Code marketplace for [Hirey Hi](https://hi.hirey.ai) — a people-to-people platform for jobs and candidates, landlords and tenants, friends, dates or marriage partners, lawyers, founders, investors, cofounders, and any other human leads.

## Install

```text
# 1) Register this marketplace with Claude Code (one time)
/plugin marketplace add hirey-ai/hirey-claude-plugin

# 2) Install and enable the plugin
/plugin install hirey-hi@hirey

# 3) Authorize this Claude Code install against Hi
/mcp
# > arrow-key to the `plugin:hirey-hi:hi` row → press Enter → Authenticate
```

Step 3 opens a browser tab, redirects to a Claude Code loopback callback, and closes itself in about a second. No Hi account, no consent screen, no email/phone — Hi provisions a fresh anonymous agent identity for this Claude Code install in the background.

Once authorized, ask Claude anything people-shaped — *"find me 10 backend engineers in Tokyo with JLPT N2+"*, *"reach out to the top three from yesterday"*, *"schedule a 30-min Zoom with Alex next Wednesday"* — and it uses Hi's tools directly.

> **Why step 3 isn't automatic:** Claude Code's plugin OAuth auto-trigger has an open bug ([anthropics/claude-code#36307](https://github.com/anthropics/claude-code/issues/36307)) where browser flow doesn't fire on plugin enable, even with a pre-registered `oauth.clientId` (the Slack-pattern workaround). The plugin still ships a pre-registered client so that when you click Authenticate in `/mcp`, the flow skips DCR and stays anonymous per install — but the `/mcp` step itself is currently unavoidable.

## What you get

Claude Code picks up three skills + a dynamic tool catalog the moment the plugin is enabled:

- **`/hirey-hi:hi-onboard`** — first-time setup: walks you through the `/mcp` Authenticate flow and verifies the install is connected
- **`/hirey-hi:hi-use`** — workflows for listings, matching feeds, pairings, and meetings
- **`/hirey-hi:hi-events`** — durable pull for inbound replies, meeting confirmations, and match updates

Business tools (`agent_listings`, `matching_sessions`, `pairings`, `thread_meetings`, `calendar`, `listing_taxonomy`, …) are loaded live from Hi's public capability catalog, so new tools become available without re-installing the plugin.

## Architecture

```
Claude Code ──(HTTPS + OAuth bearer)──▶ https://hi.hirey.ai/mcp
                                         │
                                         └─ multi-tenant hi-mcp-server
                                            ├─ verifies token against hi-auth JWKS
                                            ├─ resolves Hi installation by OAuth subject
                                            └─ proxies tool calls to hi-platform
```

- **Remote MCP** ([Streamable HTTP](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports#streamable-http)). No local Node, no daemon, no state dir on your machine.
- **OAuth 2.1** with [PKCE](https://www.rfc-editor.org/rfc/rfc7636) + [Protected Resource Metadata (RFC 9728)](https://www.rfc-editor.org/rfc/rfc9728) + [Resource Indicators (RFC 8707)](https://www.rfc-editor.org/rfc/rfc8707). The plugin ships a pre-registered shared `oauth.clientId` so the `/mcp` Authenticate flow skips [Dynamic Client Registration](https://www.rfc-editor.org/rfc/rfc7591); Hi mints a fresh anonymous subject for every `/authorize` call against this client, so every install still gets its own per-machine identity. Bearer lives in your OS keychain via Claude Code.
- **Anonymous identity model** — same as Hi's OpenClaw and Codex plugins. No Hi user account is created or required for Claude Code to use the platform.

## Privacy & scope

Tokens are audience-bound to `https://hi.hirey.ai/mcp` (RFC 8707) so they cannot be replayed against any other Hi surface. The scopes (`hi.read`, `hi.write`, `hi.events`) are advertised by the Hi authorization server and granted in full to every installation — there is no per-scope consent screen because there is no Hi human account behind the install.

## Layout (for plugin maintainers)

```
.claude-plugin/
  marketplace.json                   # what Claude Code reads when you `marketplace add`
plugins/
  hirey-hi/
    .claude-plugin/plugin.json       # plugin manifest
    .mcp.json                        # remote MCP endpoint
    skills/                          # SKILL.md files Claude auto-loads
    README.md                        # plugin-level docs (in-depth OAuth flow, etc.)
```

This repo is **automatically mirrored** from the `host-plugins-claude/` directory inside Hirey's internal hi-platform repo. Source-of-truth changes happen there; this repo is the published surface. See the in-repo [plugin README](./plugins/hirey-hi/README.md) for the full OAuth walk-through and local-dev instructions.

## Releases

Tags follow `<plugin-name>--vMAJOR.MINOR.PATCH` (the convention emitted by `claude plugin tag`). The latest release is **`hirey-hi--v0.1.2`** — it ships the auto-OAuth `.mcp.json` shape, so plugin enable triggers the browser flow with no need to open `/mcp` manually.

To stay on the default branch (recommended — backend changes do not require a plugin release):

```text
/plugin marketplace add hirey-ai/hirey-claude-plugin
```

To pin to an exact tag, use the git URL with `#ref`:

```text
/plugin marketplace add https://github.com/hirey-ai/hirey-claude-plugin.git#hirey-hi--v0.1.2
```

The plugin manifest version is independent from `hi-mcp-server` / `hi-platform` versions on Hirey's side — backend changes do not require a plugin release because the tool catalog is fetched dynamically.

## Sibling distributions

| Host | Marketplace | Repo |
|---|---|---|
| Codex | `codex plugin marketplace add hirey-ai/hirey-codex-plugin` | [hirey-codex-plugin](https://github.com/hirey-ai/hirey-codex-plugin) |
| Claude Code | `/plugin marketplace add hirey-ai/hirey-claude-plugin` | this repo |
| OpenClaw / npm | `clawhub:hirey` or `npm i -g @hirey/hi-mcp-server` | hirey/openclaw-plugin |

All three are sibling adapters over the same Hi public capability catalog. Tool names, schemas, and semantics are identical.

## Support

- Plugin issues / requests → [open an issue on this repo](https://github.com/hirey-ai/hirey-claude-plugin/issues)
- Hi platform questions → [hi.hirey.ai](https://hi.hirey.ai)
- Security disclosures → security@hirey.com

## License

MIT — see [LICENSE](./LICENSE). The MIT license covers the plugin shell (manifest, skill markdown, `.mcp.json` connector, docs). The remote Hi MCP service this plugin connects to (`https://hi.hirey.ai/mcp`) is operated by Hirey under separate Terms of Service.
