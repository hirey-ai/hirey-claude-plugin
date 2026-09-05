---
name: hi-events
description: Read and process the current Person's Hirey Hi business inbox through the canonical workspace_workflows REST capability.
---

# Hi business inbox from Claude Code

Use the REST adapter in `hi-use`; do not look for a separate legacy event or message capability.

1. Call `workspace_workflows` with `action: "agent_message.list"`. Use `payload.types` only when the
   user narrows the request to `message`, `task`, or `event`.
2. Read `result.items`. Listing is read-only; do not claim, mark, acknowledge, or complete anything
   merely to inspect it.
3. Call `agent_message.claim` only for an `agent_request` that must actually be processed. Show the
   human-relevant content first.
4. Complete or fail only the exact lease returned by that claim. Other messages, tasks, and
   notifications use the actions returned by the live catalog.

Core hides transport-only pending, leased, retry, delivery-attempt, and dead-letter bookkeeping.
Never present those as user messages. A zero-item response means no user-visible item matched this
request; it is not evidence about a different Person or Workspace.

Claims are at-least-once leases. Never complete unseen content, invent an item, reuse identifiers
from another session, or put names, contact details, credentials, or account-specific examples into
reusable instructions.
