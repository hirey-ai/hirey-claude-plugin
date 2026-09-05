---
name: hi-use
description: Use Hirey Hi for existing Person, Workspace, Need, Listing, People, Pairing, Message and Meeting workflows through the canonical workspace_workflows REST capability.
---

# Use Hirey Hi from Claude Code

Hi exposes one business capability, `workspace_workflows`. Its `catalog` action is authoritative for
the available operations, write behavior, and confirmation requirements. Do not call retired
capabilities such as `hi.owners`, `hi.agent-listings`, `hi.matching-sessions`, `hi.pairings`, or
`hi.thread-meetings`; current Hi deployments intentionally return 404 for those legacy routes.

## REST adapter

Use the existing credential from `~/.config/hi/credentials.json`. Never print its access token,
client secret, or the credential file. If the bearer is missing or expired, follow `hi-onboard`.

For every business call, send exactly one request to:

```text
POST https://hi.hirey.ai/v1/capabilities/hi.workspace-workflows/call
Authorization: Bearer <cached access_token>
Content-Type: application/json
x-hirey-plugin-host: claude
x-hirey-plugin-version: 0.2.6
```

The JSON body is the same shape as the tool contract:

```json
{"action":"catalog"}
```

or:

```json
{"action":"people.find","payload":{"query":"founder building agent infrastructure"}}
```

Read the operation receipt from the response `result`. Do not add a second request when one
operation already returns the complete result.

## Call discipline

- Call `catalog` before using an operation not inspected in the current session.
- Pass business inputs under `payload`; never send Account, Person, Workspace, Agent, or Agent
  Session authority fields.
- Every write or external effect requires a stable `idempotency_key`, reused only for its exact
  retry.
- If catalog requires explicit confirmation, ask the user first and send
  `confirmation: {"approved":true,"operation":"<exact action>"}`.
- Use identifiers returned by the preceding call; never guess identifiers or results.
- On 401, refresh the existing credential once. On 403, follow the returned binding/scope action;
  never create a replacement Agent to bypass it.

A pending Agent may use only `people.find`, `people.explain`, and staged `capture.record`.
Private Workspace reads, contact, messaging, meetings, and publication require verified identity.

Common operation families include private `person.*` memory, `need.*`, `listing.*`, `people.find`,
`match.*`, `pairing.*`, `message.*`, `reach.*`, `meeting.*`, and `meeting_link.*`. These are Core
operation names, not separate Claude tools. If an operation is absent from the live catalog, do not
call it.
