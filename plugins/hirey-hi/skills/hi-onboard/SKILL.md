---
description: First-time setup for Hirey Hi inside Claude Code. Use whenever `hi_agent_status` reports `connected:false`, any `hi_*` tool returns an auth or `agent_not_registered` error, or the user explicitly asks to "set up", "log in to", "connect", "activate", or "install" Hi. CRITICAL — this plugin is Claude Code's remote-MCP path; never tell the user to `npm install`, never ask for a client_id / client_secret / API token, never run a local `hi-mcp-server`. Authorization is fully automated through the `/mcp` panel — no consent screen, no Hi account, no human form to fill in. The browser tab opens, instantly redirects, and closes; total user touch is one keystroke in `/mcp`.
---

# Hi Onboard (first-time setup, Claude Code remote-MCP)

Hi is Hirey's people-to-people platform — jobs, hiring, housing, friendship, dating, lawyers, founders, investors, cofounders, any human lead. This Claude Code plugin runs entirely through a remote MCP server at `https://hi.hirey.ai/mcp`. **There is no local install, no Hi account to sign up for, and no consent screen to click through** — Claude Code's `/mcp` panel does Dynamic Client Registration + an automated PKCE handshake, and the Hi server provisions a fresh anonymous agent identity for this Claude Code installation in the background. This mirrors OpenClaw's existing zero-touch `hi_agent_install` model.

## Use when

- the user just installed the `hirey-hi` plugin and is asking what to do next
- `hi_agent_status` reports `connected:false` or `activated:false`
- any `hi_*` tool call returns `401`, `agent_not_registered`, `installation_not_active`, or `oauth_required`
- the user explicitly asks to "log in", "set up", "activate", "register", or "connect" Hi

## Do not use when

- `hi_agent_status` already reports `connected:true` + `activated:true` — go to `hi-use` instead
- the user is asking a workflow question (find, match, pair, meeting) — go to `hi-use`

## Steps

1. Check inventory first. If `hi_agent_status` is not in your current tool inventory, the plugin's MCP server has not loaded yet. Tell the user: "Open `/plugin` and confirm `hirey-hi@hirey` is installed and enabled (run `/plugin marketplace add hirey-ai/hirey-claude-plugin` then `/plugin install hirey-hi@hirey` if not), then run `/reload-plugins` and send another message — I don't get a fresh tool list mid-turn." Do not improvise.

2. Call `hi_agent_status`. Possible outcomes:
   - `connected:true` + `activated:true` → already onboarded, switch to `hi-use`
   - `connected:false` or `oauth_required:true` → continue with step 3
   - any other error → surface the real error verbatim; do not retry blindly

3. Ask the user to open the **`/mcp`** panel in Claude Code and authenticate the `hi` server. Concretely:

   ```text
   /mcp
   # select "hi" → "Authenticate"
   ```

   This triggers Claude Code's automated OAuth flow against the Hi MCP server:
   - Claude Code first hit `https://hi.hirey.ai/mcp` without a token, got `401` + `WWW-Authenticate: Bearer resource_metadata="https://hi.hirey.ai/.well-known/oauth-protected-resource"`, and cached that hint
   - On "Authenticate", Claude Code fetches RFC 9728 protected-resource metadata, then the RFC 8414 authorization-server metadata
   - Claude Code DCR-registers itself at `/oauth/register`, which **also auto-provisions a fresh anonymous Hi agent identity** behind the scenes (no Hi account, no signup)
   - Claude Code opens a browser at `/oauth/authorize` — the page **does not render any UI**; it 302-redirects back to Claude Code's loopback callback within milliseconds
   - Claude Code exchanges the authorization code for a bearer token, stored in its keychain, audience-bound (RFC 8707) to `https://hi.hirey.ai/mcp`
   - The browser tab closes on its own

   **End-user touch is exactly one keystroke in `/mcp`.** No Hi account, no consent click, no copy-paste. If the user reports that the browser opened a Hi login form, something is broken — surface that as `unexpected_consent_screen` and stop.

4. After the user reports the browser flow finished, call `hi_agent_status` again. If `connected:true` + `activated:true`, run `hi_agent_doctor` once to verify end-to-end (capability call + event subscription). Report the doctor result verbatim.

5. If `hi_agent_install` is in the tool inventory and `hi_agent_status` reports `connected:true` but `activated:false`, call `hi_agent_install` with no arguments. Hi's gateway will materialize the installation against the OAuth subject and return a real `agent_id` (`ag_<12-hex>`). Never invent `agent_id`.

6. If `hi_agent_install` returns a `welcome` payload (shape: `{kind:"install_welcome_onboarding", instruction_to_llm, recent_activity, intent_options}`), follow `welcome.instruction_to_llm` exactly. Run the welcome conversation in the user's chat language.

## What NOT to ask the user for

- ❌ `client_id` / `client_secret` — never. OAuth is the only path on Claude Code.
- ❌ `HI_PLATFORM_BASE_URL` env var — the URL is baked into `.mcp.json`. If they truly need a non-prod environment, edit the project-scoped `.mcp.json` to point at staging, then re-authenticate via `/mcp`.
- ❌ npm install commands — there is no npm package in this path. If the user is following an OpenClaw-style guide that mentions `@hirey/hi-mcp-server`, tell them that path is for OpenClaw (local stdio), not this Claude Code plugin.
- ❌ `agent_id` to type by hand — Hi assigns it from the OAuth subject.

## Anti-patterns

- ❌ Pretending the user is already connected. Every false claim breaks at the next tool call.
- ❌ Skipping the doctor probe "because status was green". Status is local belief; doctor proves the round-trip.
- ❌ Telling the user to copy a token from a webpage. OAuth is browser-mediated and the token lands in Claude Code's keychain — the user never sees or pastes it.
- ❌ Retrying `/mcp` Authenticate automatically. If it failed, surface the real error (network, OAuth callback port, denied scope) and let the user decide.

## Why one OAuth click is enough

Claude Code registers the MCP server at install time from `./.mcp.json`. The plugin already told Claude Code where Hi lives (`https://hi.hirey.ai/mcp`). The `/mcp` Authenticate action is the only human-driven step — everything inside it is machine-to-machine: RFC 9728 discovery + DCR + PKCE + silent /authorize redirect + RFC 8707 audience-bound code exchange + token storage. The Hi server treats the entire flow as agent self-provisioning, exactly the way OpenClaw's `hi_agent_install` tool does.

## Naming clarification

| | `/mcp` Authenticate (this flow) | OpenClaw's `hi_agent_install` (peer pattern) |
|---|---|---|
| Where it runs | Claude Code CLI on user's machine | OpenClaw runtime in the user's host |
| What it does | DCR + silent OAuth → bearer token in Claude Code keychain | Calls Hi gateway `/v1/agents/register` + `/v1/agents/activate` |
| Anonymous? | Yes — fresh Hi subject per Claude Code install, no email/phone | Yes — fresh Hi agent per OpenClaw install, no email/phone |
| UI? | Browser tab opens and closes (~200ms, no form) | None — tool call |
| Human action | One keystroke in `/mcp` | One tool call from the LLM |

Both happen exactly once per installation. After that, every `hi_*` tool call goes Claude Code → `/mcp` over HTTPS with the bearer header, and Hi resolves the installation server-side. No local state, no daemon, no receiver process, no Hi account.
