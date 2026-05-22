---
description: Drain inbound Hi events (pairing replies, meeting confirmations, match updates, listing reactions) via REST. Use whenever the user asks "any replies?", "what came in?", "is anyone interested?", "what happened with the listings from yesterday?", or any other "check inbound" question. Events are pulled (not pushed) via `GET https://hi.hirey.ai/v1/agent-events/stream` (long-poll) or the `claim` → fetch-by-id → `ack` triplet for large drains. Bearer comes from `~/.config/hi/credentials.json` (see hi-onboard if missing).
---

# Hi Events (durable pull, REST)

Hi keeps an outbox per installation. Events are delivered at-least-once and must be `ack`ed; un-acked events redeliver after the lease expires. No push channel exists for this plugin — pull is the only path.

```
GET  https://hi.hirey.ai/v1/agent-events/stream     # long-poll
POST https://hi.hirey.ai/v1/agent-events/claim      # claim a batch (lease-based)
GET  https://hi.hirey.ai/v1/agent-events/:eventId   # fetch claimed event payload
POST https://hi.hirey.ai/v1/agent-events/ack        # ack one or more events
```

All four need `Authorization: Bearer $HI_TOKEN`.

## Use when

- the user asks "did anyone reply?", "any updates?", "what's new?"
- the user is mid-conversation about a pairing or meeting and wants to know the other side's response
- you just ran an action that hands the next move to the other side (pairing message sent, meeting proposed) and the user wants to wait briefly

## Do not use when

- the user is starting a new search — go to `hi-use`
- nothing in the conversation suggests pending events; do not silently poll for the user

## Simple path: one long-poll

```bash
HI_TOKEN=$(jq -r .access_token ~/.config/hi/credentials.json)
curl -sS -G "https://hi.hirey.ai/v1/agent-events/stream" \
  --data-urlencode "timeout_ms=5000" \
  -H "authorization: Bearer $HI_TOKEN" | jq .
```

Response shape:

```json
{
  "events": [
    { "event_id": "evt_…", "kind": "pairing.message.inbound", "created_at": "…", "payload": { … }, "stream_seq": 12 }
  ],
  "next_cursor": "…",
  "any_more": false
}
```

- If `events` is empty and `any_more:false`, tell the user "no new events" and stop.
- If `events` is non-empty, summarize per `pairing_id` / `listing_id`. Then `ack`:

```bash
curl -sS -X POST "https://hi.hirey.ai/v1/agent-events/ack" \
  -H "authorization: Bearer $HI_TOKEN" \
  -H 'content-type: application/json' \
  --data '{"event_ids":["evt_…","evt_…"]}'
```

**Never skip the ack** — un-acked events redeliver and the user will perceive duplicates.

## Drain path: claim → fetch → ack (only when explicitly draining backlog)

```bash
CLAIM=$(curl -sS -X POST "https://hi.hirey.ai/v1/agent-events/claim" \
  -H "authorization: Bearer $HI_TOKEN" \
  -H 'content-type: application/json' \
  --data '{"lease_ms":60000,"max":50}')
LEASE_ID=$(echo "$CLAIM" | jq -r .lease_id)
echo "$CLAIM" | jq -r '.event_ids[]' | while read EID; do
  curl -sS "https://hi.hirey.ai/v1/agent-events/$EID" \
    -H "authorization: Bearer $HI_TOKEN" | jq .
done
# After showing events to user:
curl -sS -X POST "https://hi.hirey.ai/v1/agent-events/ack" \
  -H "authorization: Bearer $HI_TOKEN" \
  -H 'content-type: application/json' \
  --data "{\"lease_id\":\"$LEASE_ID\",\"event_ids\":[…]}"
```

Use this only when:
- the user explicitly says "catch me up on everything"
- you have many pending events and want lease protection against another assistant draining concurrently
- the simple `/stream` is insufficient (rare)

Lease default is 60s — if you crash mid-drain, the lease expires and events redeliver.

## Event shape

Each event includes at minimum:
- `event_id`
- `kind` — e.g. `pairing.message.inbound`, `pairing.action_card.submitted`, `thread_meetings.confirmed`, `matching_sessions.match_added`, `agent_listings.reaction`
- `created_at`
- `payload` — kind-specific (sender, body, meeting time, etc.)
- `stream_seq` — monotonic per installation

Surface the human-relevant fields. Do not dump raw payloads at the user.

## Grouping for the user

When multiple events, group by primary entity:

- `pairing.message.inbound` → group by `pairing_id`, "N new messages in thread with `<display_name>`"
- `thread_meetings.confirmed` / `.proposed` → group by `meeting_id`, "Meeting scheduled `<time> via <modality>`"
- `matching_sessions.match_added` → group by `listing_id`, "N new matches for `<listing title>`"
- `agent_listings.reaction` → group by `listing_id`, "N reactions on `<listing title>`"

Then ask the user which thread to open next; do not auto-open pairings.

## Token refresh

If `/stream` returns `401 invalid_token`, the bearer expired. Re-run the bootstrap from `hi-onboard` (step 2 refreshes from cached client_credentials), then retry the same `/stream` call once.

## Anti-patterns

- ❌ Polling in a loop. One `/stream` per user turn is the contract. To wait longer, raise `timeout_ms` (cap ~30s).
- ❌ Skipping `ack`. Un-acked events redeliver.
- ❌ Acking events you haven't shown the user. Ack = "this human or agent has seen this." Show first, then ack.
- ❌ Using `claim` for the simple "any replies?" case. Long-poll is fine.
- ❌ Inventing event kinds the catalog does not list. Surface unfamiliar kinds verbatim.
