---
name: hi-onboard
description: Connect, upgrade, or recover Hirey Hi in Claude through the hosted remote MCP endpoint and the normal Claude OAuth flow. Use when workspace_workflows or hi_agent_status is missing, a Hi MCP call returns a structured 401/403 authentication error, the server reports an older plugin version, or the user asks to connect Hi.
---

# Hi Onboard (Claude)

Hirey Hi is configured by this plugin as a remote MCP server at `https://mcp.hirey.ai/mcp`. There is
no npm package, local daemon, manually pasted API key, or anonymous Person to create.

Read [references/common.md](references/common.md) for the shared identity, confirmation, error and
receipt rules that every Hi host must follow. The sections below are the Claude-specific
install, OAuth, reload and recovery steps.

## Connect

1. Make sure the `hirey-hi` plugin is installed and enabled, or add the remote server directly with
   the host CLI:

   ```text
   claude mcp add --transport http --scope user hi https://mcp.hirey.ai/mcp
   ```

   Use `--scope local`, `--scope user`, or `--scope project` as the user prefers; do not choose for
   them. Trust the project scope only for a repository the user already trusts. The plugin's
   declared server is in [references/mcp.json](references/mcp.json).
2. Complete OAuth through `/mcp` in Claude, letting the user finish only the browser page.
   The server advertises OAuth discovery at `https://mcp.hirey.ai/mcp`.
3. Fully restart Claude so the MCP server and its skills load in the new session.
4. Verify that `hi_agent_status` and `workspace_workflows` are present.
5. Call `hi_agent_status` with `client_plugin_version: "0.3.4"`, then call
   `workspace_workflows` with `action: catalog` before continuing.

If OAuth returns an error, report that exact error. Do not fall back to a local MCP process, an npm
package, a static API key, or an invented installation endpoint. Do not add a REST client, a local
business schema cache, or a custom token-refresh loop: the host's native OAuth and the remote MCP
service own those.

Authentication establishes the Account, Person, Workspace, Agent, and Agent Session used by Core.
Anonymous browsing may create a pending Agent, but it does not create a permanent anonymous Person
and it is not a replacement for OAuth when private Workspace data is needed.

## Bind on the first authenticated connection

After OAuth completes and the tools are verified, bind this installation as part of the connection
instead of waiting for a later instance-directed action. A fresh Agent must start on the new
per-identity instance mechanism:

1. Run the `hi-instance` helper's bare `status --host claude` to obtain the stable
   `installation_ref`. It creates the installation record but no key pair.
2. Call `agent_instance.current` with `{local_instance_ref: <installation_ref>}`. If it reports
   `binding_status: "bound"`, this Agent Session is already bound; continue.
3. When it reports `instance_binding_required`, complete the `hi-instance` first-bind flow:
   `status --profile <profile_key> --confirmed-fingerprint <existing_public_key_fingerprint>` (omit
   the flag for a null fingerprint), `agent_instance.binding.begin`, sign the exact challenge,
   `agent_instance.binding.finish`, then `record` the returned instance id.
4. Report the instance `agent_instance.current` returns now, not a remembered one. Ordinary Hi work
   stays available even if binding cannot complete; a binding failure is an unbound instance, not an
   invalid credential.

This skill is the deterministic trigger available to the host. A host runtime that never runs its
onboarding skill after OAuth has no automatic post-login hook, so its first bind still happens on the
first instance-directed action; never claim an automatic first-login bind for such a host.

## Recover an expired or invalid credential

Do not treat every 401 as a request to create a new anonymous Agent. If Hi worked before, the saved
credential may have expired or a manual header may be overriding OAuth. For `invalid_token`,
`missing_bearer`, or a failed OAuth refresh:

1. Tell the user that the saved Hi credential is no longer valid and that reconnecting will attach
   this Claude installation to their existing Hi account.
2. Inspect the `hi` server with the host's native MCP commands. Remove only a manual
   `Authorization` header or static key override; keep the plugin's declared remote server.
3. Complete the host's OAuth flow again through `/mcp`. Do not read, print, or ask the user to paste
   the old credential.
4. Fully restart Claude, then call `hi_agent_status` with version
   `0.3.4`, call `workspace_workflows(action: catalog)`, and retry the original
   request once.

Do not create an anonymous API key for this recovery. It must not replace or mask an expired
signed-in credential.

## Version diagnostics

Host and plugin versions are diagnostic metadata, never business authority. Report a returned
`update_required` or `update_recommended` hint without refusing an otherwise compatible and
authorized call. Enforce actual protocol, identity and business permission errors separately.
A null update result is unknown or not applicable; do not infer an obsolete installation.
`restart_required` is package-update guidance for a known older client version only: it is never
credential or business-authority evidence, and it never means the OAuth credential must be reset.
Diagnose a credential or permission problem from `error_code` in Status recovery. Use only the
installed host's supported update instructions. Do not execute a command belonging to another host
or assume an unpublished candidate has a public installer. After an actual update, follow the host's
reload requirements; an update may need a reload without an OAuth restart. No branded package
version is required for a Generic client.

## Local file capability

The `agentic-media` upload helper needs a local file plus shell access. Use it only when the current
Claude session actually grants both; otherwise report that the local file cannot be read and
do not invent a URL-fetching or scraping workaround.

## Local instance

This package ships the `hi-instance` skill. When a Hi call answers `instance_binding_required`, or
when the user asks which computer this Claude installation is running on, use it: read the
verified `profile_key` from `agent_instance.current` and the server-confirmed
`existing_public_key_fingerprint` for the local `installation_ref`, then run
`python3 scripts/hi_instance.py status --host claude --profile <profile_key>
--confirmed-fingerprint <existing_public_key_fingerprint>` from that skill's directory and follow
its bind flow. The installation keeps one stable audit reference, and each verified Person and
logical Agent gets its own key pair outside this plugin's version cache, so updating, reinstalling
or re-authorizing the plugin keeps the profile and switching Person never shares a key. Recover an
`instance_key_mismatch` or `instance_revoked` refusal with the helper's `recover` plus the explicit
`agent_instance.recovery.begin` route, never by forgetting the whole installation. Only an explicit
`forget` of the whole installation, a wiped user data directory or a new computer rotates the
reference. The reported display name is only a label — the instance identity is the key pair, and
the reference is not proof of a physical machine.

## Connection surface

When you report the connection, use the shared connection copy and the separate evidence fields below
instead of an opaque "connected" flag.

## Connection copy

Product-facing wording for a connection surface. This is reviewable copy; any public UI exposure
remains subject to the existing product-change and release contract.

- Title: **Choose your Agent and connect Hi**
- Subtitle: **Use Hi from the Agent you already work with.**
- Host card shows: support status; **Connect Hi**; sign-in/authorization status; a reload
  instruction when needed; plugin version/update when applicable; local-file limitations; the
  validation result.

Display separate evidence instead of one opaque "connected" flag:

- **Tools available**
- **Credential valid**
- **Identity verified**
- **Permission for this action**
- **Update available/required**

An authenticated identity does not imply every business permission. An unknown state stays **Not
checked**; never render an unknown as a pass. A generic client without a branded plugin shows
**Plugin version: Not applicable** and never another host's upgrade command. A host whose package is
only a candidate is labeled **Awaiting host verification**.

## Status recovery

On `reconnect_required`, tell the user the returned message and stop; do not retry, even if `update_required` is true and `update_command` is null.

Use `error_code`, not the HTTP status by itself. This table stays authoritative:

| HTTP | `error_code` | Action |
|---:|---|---|
| 401 | `missing_bearer` | Use the host-supported credential-recovery flow, finish OAuth, then retry once. Reload only if the host requires it. |
| 401 | `invalid_token` | Use the host-supported credential recovery; remove only a host-diagnosed manual override, finish OAuth, then retry once. Follow host-specific reload requirements. |
| 401 | `token_expired` | Let Claude refresh OAuth; if refresh fails, use the recovery flow. Do not create another Agent. |
| 403 | `insufficient_oauth_scope` | Reauthorize the returned `required_scopes` through the normal consent flow; do not reinstall or create an Agent. |
| 403 | existing identity-binding requirement | Bind through the returned Google/email/phone `next`, then retry once. |
| 403 | `forbidden` | Stop and explain the business permission boundary; repeated login will not fix it. |

A 401 is a credential result, `insufficient_oauth_scope` is a credential-authorization result, and a
business 403 is a permission result: never treat every 403 alike. Reauthorize only the returned
scopes through normal consent, keeping the verified scope set already on the installation, and never
read tokens, keychain entries, or broad grants to reconstruct it. A `restart_required` or reload
hint is package-update guidance only and is never evidence about credentials or business authority.

The native MCP transport may carry the same authorization result as an OAuth Bearer challenge: an
HTTP 403 with `WWW-Authenticate: Bearer error="insufficient_scope", scope="...",
resource_metadata="..."` for a structured `insufficient_oauth_scope`. Both name the same
scope-recovery semantics: reauthorize through the host's OAuth challenge and the scopes it returns,
and treat the structured `required_scope` or `required_scopes` and the challenge `scope` as the same
input evidence. A generic business 403 carries no challenge and never starts a reauthorization loop;
if a host exposes only a generic failure with no typed challenge or scope evidence, do not guess
scopes or read credentials, and obtain host-supported diagnostics or normal consent instead. Never
scrape a broad catalog or broad grants, and never infer a permission from message phrases.

Recovery is bounded. Finish the required connect or reauthorize step and let the host-supported
reconnect or refresh take effect, then retry the original bounded operation once. Further reload or
refresh specifics belong to the host template, so follow the installed host's own requirements
there. Do not add fake sleeps or unbounded retry loops, and never repeat a business write whose
outcome is uncertain: resolve it through the returned receipt or idempotency-key lookup instead. If
tools are still missing or old after an actual install, update, or configuration change, reload or
start a new session (because Claude reloads Skills only in a new session) and report the concrete remaining error. Escalate to the
last supported action, fully restart Claude, only with that evidence, and do not repeat
reinstall/restart cycles.

A valid pending Agent may continue with the existing anonymous operations `people.find`,
`people.explain`, and staged `capture.record`. Do not require login merely because the user is
anonymous. Login is required only when the requested operation needs private Workspace data or an
authenticated write.

## Boundaries

- The plugin only declares the remote MCP connection and usage skills.
- `hi-mcp-server` adapts MCP and forwards the live capability call.
- `hi-auth` performs OAuth and issues the Agent Session credential.
- `hi-platform` exposes the public capability catalog and call endpoint.
- Secretary Core owns Person, Workspace, Message, Moment, Relationship and the other business
  records.

Readiness requires both: `hi_agent_status` reports a valid credential, and
`workspace_workflows(action: "catalog")` succeeds. `activated:false` may still be a valid anonymous
pending Agent; apply the anonymous-operation boundary above instead of treating it as disconnected.
