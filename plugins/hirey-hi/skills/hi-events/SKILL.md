---
description: Drain inbound Hi events (pairing replies, meeting confirmations, match updates, listing reactions) inside Claude Code. Use whenever the user asks "any replies?", "what came in?", "is anyone interested?", or whenever a tool surfaced a hint that there are pending events. Claude Code has no persistent push channel for this plugin, so events are pulled via `hi_agent_events_wait` (long-poll) or the claim/fetch/ack triplet. This skill defines the durable contract.
---

# Hi Events (durable pull, Claude Code)

Claude Code is not a persistent chat host — there is no background process from this plugin that can receive a push from Hi. The contract is **durable pull**, identical to the Codex/OpenClaw paths:

- `hi_agent_events_wait` for one-shot or interactive long-poll
- `hi_agent_events_claim` + `hi_agent_event_fetch` + `hi_agent_events_ack` for drain-loop semantics with leases

Hi keeps an outbox per installation. Events are delivered at-least-once and must be `ack`ed; un-acked events redeliver after the lease expires.

## Use when

- the user asks "did anyone reply?", "any updates?", "what's new?"
- the user is mid-conversation about a pairing or meeting and wants to know the other side's response
- you just ran an action that hands the next move to the other side (pairing message sent, meeting proposed) and the user wants to wait briefly

## Do not use when

- the user is starting a new search — go to `hi-use`
- nothing in the conversation suggests pending events; do not silently poll for the user

## Simple path: long-poll once

```
hi_agent_events_wait(timeout_ms: 5000)
  → { events: [...], next_cursor: "...", any_more: bool }
```

- If `events` is empty and `any_more:false`, tell the user "no new events" and stop.
- If `events` is non-empty, summarize per `pairing_id` / `listing_id`. Then call `hi_agent_events_ack(event_ids: [...])`. Never skip the ack — un-acked events redeliver.

This is the right shape for almost every Claude Code turn. Single round-trip, clear result, no lease bookkeeping.

## Drain path: claim → fetch → ack (only when explicitly draining a backlog)

```
hi_agent_events_claim(lease_ms: 60000, max: 50)
  → { lease_id, event_count }
hi_agent_event_fetch(lease_id)
  → { events: [...], page_cursor }
hi_agent_events_ack(lease_id, event_ids: [...])
```

Use this only when:
- the user explicitly says "catch me up on everything"
- you need >1 page of events
- you want the lease to protect against another Claude Code session draining the same outbox

Always `ack`. If you crash mid-drain, the lease expires (default 60s) and the events redeliver to the next claim — but the user perceives that as duplicate replies, so don't leak leases.

## Event shape

Each event has at minimum:
- `event_id`
- `kind` — e.g. `pairing.message.inbound`, `pairing.action_card.submitted`, `thread_meetings.confirmed`, `matching_sessions.match_added`, `agent_listings.reaction`
- `created_at`
- `payload` — kind-specific (sender, body, meeting time, etc.)
- `stream_seq` — monotonic per installation

Surface the human-relevant fields. Do not dump raw payloads at the user.

## Grouping for the user

When you have multiple events, group by primary entity:

- `pairing.message.inbound` → group by `pairing_id`, show "N new messages in thread with <display_name>"
- `thread_meetings.confirmed` / `thread_meetings.proposed` → group by `meeting_id`, show the scheduled time + modality
- `matching_sessions.match_added` → group by `listing_id`, show "N new matches for <listing title>"
- `agent_listings.reaction` → group by `listing_id`, show counts

Then ask the user which thread to open next; do not auto-open pairings.

## Anti-patterns

- ❌ Polling in a loop **inside one turn**. One `hi_agent_events_wait` per user turn is the contract. If you want to wait longer, raise `timeout_ms` (cap ~30s). For *between-turn* polling, use a scheduled drain (see next section) — that's not in-turn looping.
- ❌ Skipping `ack`. Un-acked events redeliver; the user will think Hi is buggy.
- ❌ Acking events you haven't shown the user. Ack = "this human or agent has seen this." Show first, then ack.
- ❌ Using `hi_agent_events_claim` for the simple "any replies?" case. Long-poll is fine and avoids lease bookkeeping.
- ❌ Inventing event kinds the catalog does not list. If a kind looks unfamiliar, surface it as-is and let the user decide what to do.

## Scheduled drain — recommend after every outreach

Claude Code does not get push for this plugin (`streamable-http` transport, no Channels capability advertised). When the user closes Claude Code, or just switches away from this conversation, any inbound Hi event sits in the durable outbox until something pulls it. That something is either (a) the user asking "any replies?" in a new turn, or (b) a scheduled drain. If the user walks away and nothing is scheduled, the other side's reply is effectively invisible.

**Rule of thumb**: any turn that ends with an outbound action the other side will reply to — `pairings.contact_target`, `matching_sessions.contact_match`, `thread_meetings.start`, `call_intents.confirm_start_now`, `agent_listings.upsert` (listings receive reactions) — should also surface a scheduled-drain suggestion to the user, unless one already exists for this conversation. Don't be silent about it; the user does not know Hi is pull-based.

### Claude Code `/schedule` skill (preferred)

Claude Code ships a first-class `/schedule` skill that runs remote agents on cron — easier than OS-level cron and no shell config to maintain. Suggest:

> "Run `/schedule` and create a routine that fires `/hirey-hi:hi-events drain my Hi inbox and ack` every 10 minutes. It runs server-side, so you'll see new replies even if Claude Code is closed."

For slower outreach (e.g. a job listing that only deserves a daily check), pick `0 9 * * *` instead of `*/10 * * * *`.

### `/loop` for short interactive waits

If the user just wants to wait *now* for a few minutes (e.g. they sent a message and want to see if the reply comes back during the same coffee break), point them at `/loop`:

> "`/loop 2m /hirey-hi:hi-events drain my Hi inbox` will check every 2 minutes inside this conversation until you stop it."

This is the in-conversation analogue of the OS-cron path, scoped to the current session.

### OS cron + `claude -p` (fallback)

If the user has no Claude Code Cloud access or wants the drain to run on their own machine, OS cron + `claude -p` works:

```cron
*/10 * * * * cd /path/to/project && claude -p "/hirey-hi:hi-events drain my Hi inbox and ack" >> ~/.hi-inbox-drain.log 2>&1
```

This is rarely needed — `/schedule` is the right call for almost everyone. Mention it only if the user explicitly asks for an on-machine cron path.

### Surfacing the suggestion to the user

When you finish an outreach turn (e.g. you just called `pairings.contact_target`), end the user-facing message with one short paragraph, e.g.:

> "Heads up — Claude Code doesn't get push notifications for Hi events. Their reply will sit in your Hi inbox until something checks. If you'd like me to flag replies as they arrive, set up `/schedule` with `/hirey-hi:hi-events drain my Hi inbox and ack` every 10 minutes. Or leave it and just ask me 'any replies?' next time."

Offer the recipe but don't force it. If the user has already declined or already set one up in this conversation, don't re-pitch.

## Why no push channel

Claude Code's MCP transport for this plugin is plain `streamable-http` — Hi does not advertise the `claude/channel` capability on the public `/mcp` endpoint, so there is no session inbox to push into. Durable pull via `hi_agent_events_wait` is the only correct primary path for this host today. If Hi adds a Channels capability later, this skill will switch the simple path; the claim/fetch/ack drain primitives stay regardless.
