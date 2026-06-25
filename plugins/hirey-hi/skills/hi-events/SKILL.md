---
description: Drain inbound Hi events (pairing replies, meeting confirmations, match updates, listing reactions) via REST. Use whenever the user asks "any replies?", "what came in?", "is anyone interested?", "what happened with the listings from yesterday?", or any other "check inbound" question. Events are pulled via the `POST /v1/agent-events/claim` → `GET /v1/agent-events/:eventId` → `POST /v1/agent-events/ack` triplet. (The `/stream` endpoint exists but is **SSE, not long-poll** — its `timeout_ms` query param is server-ignored, so it blocks until a real event arrives. Use `/claim` for tool-driven drain.) Bearer comes from `~/.config/hi/credentials.json` (see hi-onboard if missing).
---

# Hi Events (durable pull, REST)

Hi keeps an outbox per installation. Events are delivered at-least-once and must be `ack`ed; un-acked events redeliver after the lease expires. No push channel exists for this plugin — pull is the only path.

```
POST https://hi.hirey.ai/v1/agent-events/claim      # claim a batch (lease-based) — USE THIS
GET  https://hi.hirey.ai/v1/agent-events/:eventId   # fetch claimed event payload
POST https://hi.hirey.ai/v1/agent-events/ack        # ack one or more events
GET  https://hi.hirey.ai/v1/agent-events/stream     # SSE keepalive stream — DO NOT USE here
```

All four need `Authorization: Bearer $HI_TOKEN`. Use the `claim` → `eventId` → `ack` triplet for every drain — it's a normal JSON POST that returns immediately with whatever's in the outbox.

> ⚠️ **`/stream` is Server-Sent Events**, not JSON long-poll. Its `timeout_ms` query param is server-ignored: the connection stays open with SSE keepalives until a real event arrives. Using it from `curl` without `-N` (or from `httpx.get()`) will hang. The claim path below avoids this entirely.

## Use when

- the user asks "did anyone reply?", "any updates?", "what's new?"
- the user is mid-conversation about a pairing or meeting and wants to know the other side's response
- you just ran an action that hands the next move to the other side (pairing message sent, meeting proposed) and the user wants to wait briefly

## Do not use when

- the user is starting a new search — go to `hi-use`
- nothing in the conversation suggests pending events; do not silently poll for the user

## Simple path: claim + fetch + ack

```bash
HI_TOKEN=$(jq -r .access_token ~/.config/hi/credentials.json)

# 1) Claim up to 25 events with a 60s lease
CLAIM=$(curl -sS -X POST "https://hi.hirey.ai/v1/agent-events/claim" \
  -H "authorization: Bearer $HI_TOKEN" -H 'content-type: application/json' \
  --data '{"max":25,"lease_ms":60000}')
LEASE_ID=$(echo "$CLAIM" | jq -r .lease_id)
EVENT_IDS=$(echo "$CLAIM" | jq -r '.event_ids[]?')

# 2) Fetch each event payload
echo "$EVENT_IDS" | while read EID; do
  [ -z "$EID" ] && continue
  curl -sS "https://hi.hirey.ai/v1/agent-events/$EID" \
    -H "authorization: Bearer $HI_TOKEN" | jq .
done
```

If `event_ids` is empty, tell the user "no new events" and stop.

If non-empty, summarize per `pairing_id` / `listing_id`. Then **ack** (don't skip — un-acked events redeliver):

```bash
ACK_IDS=$(echo "$EVENT_IDS" | jq -R -s -c 'split("\n") | map(select(. != ""))')
curl -sS -X POST "https://hi.hirey.ai/v1/agent-events/ack" \
  -H "authorization: Bearer $HI_TOKEN" -H 'content-type: application/json' \
  --data "{\"event_ids\":$ACK_IDS,\"lease_id\":\"$LEASE_ID\"}"
```

`lease_id` is optional but recommended — it scopes the ack to your claim so a concurrent drain can't double-ack.

Lease default is 60s — if you crash mid-drain, the lease expires and events redeliver to the next caller.

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
- `meeting.auto_responded` → the owner's standing `hi.meeting-rules` already answered a meeting request platform-side; relay as a one-line receipt ("your rules auto-accepted the Zoom with `<name>`"), never as a question
- `matching_sessions.match_added` → group by `listing_id`, "N new matches for `<listing title>`"
- `agent_listings.reaction` → group by `listing_id`, "N reactions on `<listing title>`"

Then ask the user which thread to open next; do not auto-open pairings.

## Token refresh

If `/claim` returns `401 invalid_token`, the bearer expired. Re-run the bootstrap from `hi-onboard` (step 2 refreshes from cached client_credentials), then retry the same `/claim` call once.

## Ambient monitoring (the "do I have to ask every time?" pattern)

Hi has no push channel into Claude Code, so the user must either ask explicitly ("any replies?") OR opt into a scheduled drain. If the user has live pairings out and wants the assistant to surface inbound replies *without being asked each turn*, suggest one of:

- **`/loop 20m claude /skill hi-events`** — runs the drain at a fixed interval inside the current Claude Code session. Cheap, exits when the user closes Claude Code. Right for an active "I'm waiting on a reply right now" mode.
- **`/schedule` a remote agent** — runs server-side every N minutes regardless of whether Claude Code is open. Right for "ping me by phone when Walter replies" patterns; pairs with phone-binding silent push (see hi-onboard for that).

Both are user-triggered. Do not start a loop without the user agreeing — surface the suggestion when the user expresses the desire ("can you just tell me when he replies?"), let them pick.

## Anti-patterns

- ❌ Hitting `/v1/agent-events/stream` from `curl` (without `-N`) or `httpx.get()` — that endpoint is SSE keepalive, `timeout_ms` is server-ignored, the connection blocks until a real event arrives. Use `/claim` instead.
- ❌ Polling in a tight loop inside one tool call. One `/claim` per user turn (or per `/loop` tick — see "Ambient monitoring" above).
- ❌ Skipping `ack`. Un-acked events redeliver after the lease (60s default) expires.
- ❌ Acking events you haven't shown the user. Ack = "this human or agent has seen this." Show first, then ack.
- ❌ Inventing event kinds the response does not list. Surface unfamiliar kinds verbatim.
