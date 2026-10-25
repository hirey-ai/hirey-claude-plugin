# Hirey Hi for Claude

This package is the native Claude Code plugin that connects Claude to the hosted Hirey Hi
remote MCP endpoint:

```text
https://mcp.hirey.ai/mcp
```

It ships shared Hi business Skills, including `hi-pages` for resumable private Page batches,
plus the shared onboarding skill and one remote MCP
server declaration. There is no npm package, local MCP daemon, or manually managed API key.

## Install and authenticate

```bash
curl -fsSL https://hi.hirey.ai/v1/install/claude.sh | bash
```

or, inside Claude Code:

```text
/plugin marketplace add hirey-ai/hirey-claude-plugin
/plugin install hirey-hi@hirey
```

Then sign in once with `claude mcp login plugin:hirey-hi:hi` (or `/mcp` in Claude Code) and
restart Claude Code. Verify `hi_agent_status` and `workspace_workflows` are present, then call
`hi_agent_status` with `client_plugin_version: "0.3.4"` and `workspace_workflows`
with `action: catalog`.

The user-facing connection copy plus the shared identity, confirmation, error and recovery rules
live only in [skills/hi-onboard/references/common.md](skills/hi-onboard/references/common.md); do not
repeat them here.

## Version

**0.3.4** is the first native release; it replaces the retired REST bundle
(`host-plugins-claude/`, last 0.2.6). The installer moves that bundle's skills out of
`~/.claude/skills/` (it never deletes them) and leaves that bundle's local identity file alone.

## Local file capability

`agentic-media` can preserve a local image or video only when the Claude Code session actually
grants file and shell access. When it does not, report that the local file cannot be read and do not
invent a workaround. The upstream service still owns upload, processing and publication.

This package is generated from `agent-integration/` by `node scripts/build-agent-packages.mjs`.
Edit the source there, not this copy.
