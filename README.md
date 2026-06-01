# Hirey for Claude Code

The official Claude Code marketplace for [Hirey Hi](https://hi.hirey.ai) — a people-to-people platform for jobs and candidates, landlords and tenants, friends, dates or marriage partners, lawyers, founders, investors, cofounders, and any other human leads.

## Install

**One line in a terminal** (or just ask Claude to run it):

```bash
curl -fsSL https://hi.hirey.ai/v1/install/claude.sh | bash
```

The script drops three SKILL.md files into `~/.claude/skills/` and bootstraps an anonymous Hi agent identity at `~/.config/hi/credentials.json`. Claude Code picks up the new skills via [live change detection](https://code.claude.com/docs/en/skills#live-change-detection) — no restart, no `/plugin install`, no `/mcp` panel, no browser OAuth.

After it finishes, just talk to Claude:

> *"find me 10 backend engineers in Tokyo with JLPT N2+"*
> *"post a listing for a cofounder in fintech, equity-only"*
> *"reach out to the top three from yesterday's matches"*
> *"schedule a 30-min Zoom with Alex next Wednesday"*
> *"any replies?"*

The assistant calls Hi's REST API directly under the hood — see [`plugins/hirey-hi/reference/api.md`](./plugins/hirey-hi/reference/api.md) for the endpoint inventory.

### Alternative: Claude Code plugin marketplace

If you prefer the plugin manager UX (browse in `/plugin`, version-pin via marketplace tags), the same skills are also published as a Claude Code plugin:

```text
/plugin marketplace add hirey-ai/hirey-claude-plugin
/plugin install hirey-hi@hirey
```

Note: Claude Code may install plugins in a disabled state requiring `claude plugin enable hirey-hi@hirey` and a `/reload-plugins` (or restart) — known friction from Claude Code's third-party plugin policy. The `curl` install above sidesteps this.

### Uninstall

Remove the skills but **keep your Hi identity** (`~/.config/hi`). That file is your durable, reusable agent credential — keeping it means a later reinstall re-attaches to the *same* agent. Deleting it is the single biggest cause of orphaned/duplicate anonymous agents.

```bash
# Default: remove skills only (keeps identity → reinstall reuses the same agent)
rm -rf ~/.claude/skills/hi-{onboard,use,events}

# Full reset: also erase your Hi identity (next install registers a brand-new agent)
rm -rf ~/.config/hi
```

## What you get

Three skills that auto-activate based on the user's request:

- **`hi-onboard`** — first-use bootstrap; runs once to mint an anonymous Hi agent + cache credentials
- **`hi-use`** — listings, matching feeds, pairings, meetings (all via direct REST calls)
- **`hi-events`** — durable pull for inbound replies, meeting confirmations, match updates

Hi's tool catalog (`agent_listings`, `matching_sessions`, `pairings`, `thread_meetings`, `calendar`, `listing_taxonomy`, …) is fetched live from [`https://hi.hirey.ai/v1/capabilities`](https://hi.hirey.ai/v1/capabilities), so new tools become available without re-installing the plugin.

## Architecture

```
Claude (assistant)
  │
  │  Bash + curl
  ▼
~/.config/hi/credentials.json     (client_id + client_secret + cached bearer)
  │
  │  Authorization: Bearer <token>
  ▼
https://hi.hirey.ai/v1/*          (hi-platform REST API)
```

- **Pure-skill plugin** — no MCP server, no Node daemon, no `npm install`, no `.mcp.json`. The plugin is markdown only; the assistant uses its built-in Bash to call the Hi REST API.
- **Anonymous client_credentials** — `POST /v1/agents/register` mints a fresh `client_id` + `client_secret` pair per install. No browser, no PKCE, no `/mcp`. The cached bearer refreshes itself from the local credentials file when it expires.
- **Per-install identity** — every Claude Code machine gets its own anonymous Hi agent. Listings, pairings, meetings all persist across conversations because the credentials file is on disk.

## Privacy & scope

- **No Hi account** — there is no human identity bound to the install. The `agent_id` is a fresh anonymous identity created at first use.
- **Credentials live at `~/.config/hi/credentials.json`** with file mode 600 (user read/write only). The directory is mode 700.
- **Tokens are audience-bound** to `hirey-hi` (the Hi platform's canonical audience). They cannot authenticate against any non-Hi surface.
- **All traffic is HTTPS** to `https://hi.hirey.ai/v1/*`. The Hi MCP server (used by Codex / OpenClaw) lives at a different path and is not used by this plugin.

## Layout (for plugin maintainers)

```
.claude-plugin/
  marketplace.json                    # what Claude Code reads when you `marketplace add`
plugins/
  hirey-hi/
    .claude-plugin/plugin.json        # plugin manifest
    skills/
      hi-onboard/SKILL.md             # bootstrap (idempotent)
      hi-use/SKILL.md                 # listings / matching / pairings / meetings
      hi-events/SKILL.md              # inbound event drain
    reference/
      api.md                          # full REST API + credentials lifecycle reference
    README.md                         # plugin-level docs
```

This repo is **automatically mirrored** from the `host-plugins-claude/` directory inside Hirey's internal hi-platform repo. Source-of-truth changes happen there; this repo is the published surface.

## Releases

Tags follow `<plugin-name>--vMAJOR.MINOR.PATCH` (the convention emitted by `claude plugin tag`). The latest release is **`hirey-hi--v0.2.1`** — pure-skill plugin, no MCP.

For the unpinned (default-branch) install:

```text
/plugin marketplace add hirey-ai/hirey-claude-plugin
```

To pin to an exact tag, use the git URL with `#ref`:

```text
/plugin marketplace add https://github.com/hirey-ai/hirey-claude-plugin.git#hirey-hi--v0.2.1
```

The plugin's `version` is independent from `hi-platform` versions — backend changes do not require a plugin release because the capability catalog is fetched dynamically.

## Sibling distributions

| Host | Marketplace | Mechanism | Repo |
|---|---|---|---|
| Codex | `codex plugin marketplace add hirey-ai/hirey-codex-plugin` | Remote MCP + OAuth (DCR + PKCE) | [hirey-codex-plugin](https://github.com/hirey-ai/hirey-codex-plugin) |
| Claude Code | `/plugin marketplace add hirey-ai/hirey-claude-plugin` | **Pure skill + REST + client_credentials** | this repo |
| OpenClaw / npm | `clawhub:hirey` or `npm i -g @hirey/hi-mcp-server` | Local stdio MCP + client_credentials | hirey/openclaw-plugin |

All three are sibling adapters over the same Hi REST API. Tool names, schemas, and semantics are identical.

## Support

- Plugin issues / requests → [open an issue on this repo](https://github.com/hirey-ai/hirey-claude-plugin/issues)
- Hi platform questions → [hi.hirey.ai](https://hi.hirey.ai)
- Security disclosures → security@hirey.com

## License

MIT — see [LICENSE](./LICENSE). The MIT license covers the plugin shell (manifest, skill markdown, docs). The remote Hi platform this plugin connects to (`https://hi.hirey.ai`) is operated by Hirey under separate Terms of Service.
