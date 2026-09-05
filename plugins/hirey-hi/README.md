# Hirey Hi for Claude Code

Claude Code plugin that gives Claude direct access to the Hi people-to-people platform — jobs, hiring, housing, friendship, dating, lawyers, founders, investors, cofounders, any human lead.

**Pure-skill plugin. No MCP. No browser OAuth. No user clicks.** The plugin is markdown only; on first use, Claude runs a short Bash script that registers an anonymous Hi agent and caches credentials at `~/.config/hi/credentials.json`. Every subsequent Hi tool call is a direct `curl` to `https://hi.hirey.ai/v1/*` with a cached bearer.

## Install

```bash
curl -fsSL https://hi.hirey.ai/v1/install/claude.sh | bash
```

The script drops `hi-onboard`, `hi-use`, `hi-events`, and `hi-repair` into `~/.claude/skills/`, creates one pending Hi Agent, and stores durable client credentials plus an expiring cached bearer at `${XDG_CONFIG_HOME:-$HOME/.config}/hi/credentials.json`. Claude Code [picks up new skills live](https://code.claude.com/docs/en/skills#live-change-detection) — no restart needed.

Once it finishes, just talk to Claude: "find me 10 backend engineers in San Francisco", "reach out to candidates from yesterday", "schedule a Zoom with Alex". The assistant uses Hi's tools directly.

### Alternative: plugin-marketplace install

The same skills are also published as a Claude Code plugin:

```text
/plugin marketplace add hirey-ai/hirey-claude-plugin
/plugin install hirey-hi@hirey
```

Use this if you want the `/plugin` manager UX. The `curl` install above is recommended because it sidesteps Claude Code's third-party plugin enable/reload friction.

## How it works under the hood

```
Step 1 (first use only — assistant runs via Bash, no user touch):
  # Use the guarded installer/onboard script; do not issue raw non-idempotent registration.
  # POST https://hi.hirey.ai/v1/agents/api-keys
    → { agent_id, status: "pending", api_key: "hi_ak_<version-1 envelope>" }
    → strictly decode client_id/client_secret; atomic private credential file
  curl -X POST https://hi.hirey.ai/oauth/token (grant_type=client_credentials)
    → { access_token, expires_in: 3600 }
  → write everything to ~/.config/hi/credentials.json (mode 600)

Step 2 (every subsequent tool call):
  curl -X POST https://hi.hirey.ai/v1/capabilities/<id>/call
    -H "Authorization: Bearer <cached_access_token>"
    --data '{ "action": "<verb>", ... }'

Step 3 (when the cached token expires — also assistant-only):
  curl -X POST https://hi.hirey.ai/oauth/token (re-grant client_credentials)
    → fresh access_token, update credentials.json
```

Anonymous installation is zero-touch. The credentials file persists across Claude conversations, restarts, and (within the OS user account) machine reboots. A pending Agent is already ready for public reads; private Workspace reads and writes prompt for Google, email, or phone verification and then attach the same installation to the user's existing identity.

## Identity model

| | OpenClaw native plugin | Codex plugin | Claude Code (this plugin) |
|---|---|---|---|
| Distribution | ClawHub `clawhub:hirey` / `npm i @hirey/hi-mcp-server` | `codex plugin marketplace add hirey-ai/hirey-codex-plugin` | `/plugin marketplace add hirey-ai/hirey-claude-plugin` |
| Local install | native OpenClaw plugin | none | none |
| Process model | in-process tools + event service | remote MCP over HTTPS | **pure REST over HTTPS, no MCP layer** |
| Auth | `client_credentials` in plugin state | OAuth 2.1 (DCR + PKCE) via Codex connector | **`client_credentials` minted on first use, cached at `~/.config/hi/credentials.json`** |
| Event delivery | in-process claim/push service | remote MCP event tools | business Inbox via `workspace_workflows` |
| State on user machine | `~/.openclaw/hi-mcp/<profile>/` | Codex keychain entry only | `~/.config/hi/credentials.json` (mode 600) |
| User interaction at install | none after `openclaw plugins install` | one keystroke in `/mcp` Authenticate | **none at all** |
| Updates | `openclaw plugins update hirey` / existing release event | Codex marketplace | Claude plugin marketplace |

All three start with an installation Agent. Anonymous-capable reads do not create a Person. When private data or a write requires verified identity, Google, email, or phone binds that existing installation to the user's Workspace instead of minting a replacement Agent.

## Update

```bash
curl -fsSL https://hi.hirey.ai/v1/install/claude.sh | bash
```

Then run `/reload-plugins`. Re-running the installer preserves the existing credential and updates
all four Skills, including curl-installed copies outside the marketplace cache.

Version 0.2.6 and newer asks Hi for the Claude-specific release policy before credential recovery and routes every business operation through `workspace_workflows`. A required plugin update, a 401 credential problem, and a 403 permission problem lead to different actions.

## What the plugin actually ships

```
plugins/hirey-hi/
  .claude-plugin/plugin.json     # Claude Code plugin manifest
  skills/
    hi-onboard/SKILL.md          # one-time bootstrap (idempotent)
    hi-use/SKILL.md              # canonical workspace_workflows REST adapter
    hi-events/SKILL.md           # canonical business Inbox
    hi-repair/SKILL.md           # scoped Product Signal -> root cause -> reviewable PR workflow
  reference/
    api.md                       # full REST API + credentials lifecycle reference
  README.md                      # this file
```

**No code.** No `.mcp.json`, no `package.json`, no `dist/`, no MCP server. The plugin shell is a few markdown files; Claude does everything via its built-in Bash + curl + jq.

## Backing service

`https://hi.hirey.ai` is hi-platform (Express + REST). The `hi-mcp-server` used by Codex and generic
MCP hosts remains at `https://mcp.hirey.ai/mcp`; this plugin calls `/v1/*` REST endpoints directly.
The public capability catalog exposes `workspace_workflows` plus the three identity-binding tools.
The live `workspace_workflows` `catalog` action is the source of truth for business operations.

## Local development / staging

To point the bootstrap at a staging Hi, override `HI_BASE` before triggering the `hi-onboard` skill:

```bash
HI_BASE=https://staging.hi.hirey.ai
# ... rest of the onboard script from the skill
```

Or delete `~/.config/hi/credentials.json` and edit the onboard SKILL.md locally to point at staging before re-installing the plugin via `--plugin-dir`.

For fully local Hi development, run `hi-platform` on your laptop and use `HI_BASE=http://127.0.0.1:4012` (or whatever port). The capabilities surface is the same.

## Versioning

This plugin's `version` is independent from `hi-platform` versions. The plugin only needs to be re-released when:

- the bundled SKILL.md instructions change
- a new top-level skill (e.g. `hi-billing`) is added
- the credentials file shape changes
- the bootstrap recipe changes (e.g., new endpoint to call during onboard)

Tool-level additions to Hi's capability catalog show up in the live `/v1/capabilities` response — no plugin release required.

## Why not MCP?

The MCP path (Codex / OpenClaw / `hi-mcp-server`) is fine but Claude Code's current MCP client has a known bug ([anthropics/claude-code#36307](https://github.com/anthropics/claude-code/issues/36307)) where the OAuth browser flow doesn't auto-trigger on plugin enable. The recommended workaround (Slack-pattern pre-registered `oauth.clientId`) still requires the user to manually open `/mcp` and click "Authenticate" in 2.1.138.

Since Hi already exposes everything as REST, we just skipped MCP entirely on Claude Code. The pure-skill approach has fewer moving parts, fewer failure modes, and gets the user to "ready to use" in zero touches. When Anthropic fixes #36307, we can revisit — but a pure-skill plugin is arguably the better long-term shape anyway (less infrastructure, faster onboarding, easier to debug).

Codex and OpenClaw still use the MCP path because their hosts handle MCP OAuth correctly.
