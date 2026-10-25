# Hirey for Claude Code

The official Claude Code marketplace for [HiRey](https://hi.hirey.ai): the people you meet, their Pages, your Needs, messages, introductions and meetings, from Claude.

## Install

**One line in a terminal** (or just ask Claude to run it):

```bash
curl -fsSL https://hi.hirey.ai/v1/install/claude.sh | bash
```

Or inside Claude Code:

```text
/plugin marketplace add hirey-ai/hirey-claude-plugin
/plugin install hirey-hi@hirey
```

Then sign in to HiRey once (opens your browser):

```bash
claude mcp login plugin:hirey-hi:hi
```

or run `/mcp` inside Claude Code, and restart Claude Code. After that, just talk to Claude:

> *"who did I meet this week?"*
> *"build Pages for the people I met at the conference"*
> *"find me a fintech cofounder in San Francisco"*
> *"any replies?"*

### Moving from the earlier REST installer (0.2.x)

Run the install line above. It moves the earlier skills out of `~/.claude/skills/hi-{onboard,use,events,repair}` into `~/.claude/skills/.hirey-legacy-<time>/` (nothing is deleted) and installs the plugin. The earlier anonymous identity file is left as it is; the plugin signs in with your HiRey account instead.

## On the Claude desktop app, claude.ai web, mobile & Cowork

The install above is for **Claude Code**. In the **desktop app**, on **claude.ai**, in **Cowork** or on your **phone**, add HiRey as a remote MCP connector instead:

1. Open **Settings → Connectors → Add custom connector**
2. Name it **HiRey** and paste the URL: `https://mcp.hirey.ai/mcp`
3. Click **Add** and complete the one-time sign-in

Full per-surface steps: <https://hirey.ai/install/claude>

### Uninstall

```bash
claude plugin uninstall hirey-hi@hirey
```

## What you get

- One remote MCP server, `https://mcp.hirey.ai/mcp`, with OAuth sign-in. Its `workspace_workflows` tool exposes HiRey's live operation catalog, so new operations need no plugin update.
- Skills: `hi-onboard` (sign-in and plugin status), `hi-use`, `hi-pages` (Pages for the people you met, written by HiRey's Page writer), `hi-events` (Inbox), `hi-instance`, `agentic-media` and `hi-repair`.

Your Agent acts as you: it gets no identity, publication or consent authority beyond your own, and HiRey asks you before writes that reach others or cannot be undone.

## Layout (for plugin maintainers)

```
.claude-plugin/marketplace.json   # what Claude Code reads when you `marketplace add`
plugins/hirey-hi/                 # the plugin (manifest, .mcp.json, skills)
install.sh                        # served at https://hi.hirey.ai/v1/install/claude.sh
.sync-source                      # hi-platform prod commit the plugin was mirrored from
```

`plugins/hirey-hi/` is mirrored from `agent-packages/claude/` in Hirey's hi-platform repository (generated from `agent-integration/`); change it there.

## Releases

The plugin reports its version to HiRey (`x-hirey-plugin-version`), so required and recommended updates come back from the server. Update with the install line above, or `claude plugin update hirey-hi@hirey`, then restart Claude Code.

## Sibling distributions

| Host | Install | Repo |
|---|---|---|
| Codex | `codex plugin marketplace add hirey-ai/hirey-codex-plugin` | [hirey-codex-plugin](https://github.com/hirey-ai/hirey-codex-plugin) |
| Claude Code | `curl -fsSL https://hi.hirey.ai/v1/install/claude.sh \| bash` | this repo |
| Hermes | `curl -fsSL https://hi.hirey.ai/v1/install/hermes.sh \| bash` | [hirey-hermes-plugin](https://github.com/hirey-ai/hirey-hermes-plugin) |
| OpenClaw | `openclaw plugins install clawhub:hirey` | [hi-openclaw-plugin](https://github.com/hirey-ai/hi-openclaw-plugin) |

## Support

- Plugin issues / requests → [open an issue on this repo](https://github.com/hirey-ai/hirey-claude-plugin/issues)
- HiRey questions → [hi.hirey.ai](https://hi.hirey.ai)
- Security disclosures → security@hirey.com

## License

MIT — see [LICENSE](./LICENSE). The MIT license covers the plugin shell (manifest, skill markdown, docs). The HiRey platform this plugin connects to is operated by Hirey under separate Terms of Service.
