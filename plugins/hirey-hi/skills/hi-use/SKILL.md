---
description: Use Hirey Hi for people-to-people workflows — post listings, see matches, search candidates, start 1:1 pairings, schedule meetings. Use whenever the user asks to find, recruit, match, reach out to, pair with, or meet anyone (job candidate, tenant, friend, date, cofounder, investor, lawyer, etc.). Calls Hi's REST API directly via `curl` with a bearer token cached at `~/.config/hi/credentials.json` — no MCP, no browser OAuth, no `/mcp`. If the credentials file is missing or the token is expired, run the `hi-onboard` skill first (or its inline bootstrap snippet) before any Hi call.
---

# Hi Use (REST workflows for people-finding)

Every Hi business tool is exposed as a single REST endpoint:

```
POST https://hi.hirey.ai/v1/capabilities/<capability_id>/call
Authorization: Bearer $(jq -r .access_token ~/.config/hi/credentials.json)
Content-Type: application/json

{"action": "<verb>", ...other_args}
```

Capabilities are loaded live from Hi's catalog (`GET https://hi.hirey.ai/v1/capabilities`) — names + tool surface stay in sync with the backend automatically.

## Use when

- the credentials file at `~/.config/hi/credentials.json` exists and its token is fresh (`hi-onboard` does the refresh; if you can't tell, just call onboard first — it's a no-op when current)
- the user asks anything in these shapes:
  - "find me X people for Y" (hiring, housing, friendship, dating, cofounder, investor, lawyer, etc.)
  - "post a job / listing / ad for …"
  - "show me my listings"
  - "reach out to candidate N from the last batch"
  - "set up a Zoom / phone call with …"

## Helper: one-line bearer

Every recipe below assumes you have this token in scope. Run it once at the top of any Hi turn:

```bash
HI_BASE="https://hi.hirey.ai"
HI_TOKEN=$(jq -r .access_token ~/.config/hi/credentials.json 2>/dev/null)
# If empty, re-run the bootstrap from the `hi-onboard` skill, then re-read.
[ -z "$HI_TOKEN" ] && { echo "credentials missing — run hi-onboard"; exit 1; }
```

## Capability map (loaded dynamically; this is just the cheat sheet)

| Intent | `capability_id` | Common actions |
|---|---|---|
| Capture / update who the user is (name, headline, bio) | `hi.owners` | `update_profile`, `get`, `list_listings`, `peers_feed` — **call this first** when the user has just introduced themselves |
| Publish / browse listings | `hi.agent-listings` | `upsert`, `update_status`, `get`, `list`, `browse_recent` |
| Pick taxonomy (job kinds, housing kinds, …) | `hi.listing-taxonomy` | (see schema endpoint — exact actions vary) |
| Browse the live match feed for a listing | `hi.matching-sessions` | `match_feed`, `search`, `contact_match` |
| Open a 1:1 thread with a matched person | `hi.pairings` | `create`, `timeline`, `contact_target` |
| Negotiate / schedule a meeting | `hi.thread-meetings` | `start`, `respond`, `get` |
| Host / discover public multi-party activities | `hi.event-groups` | `create`, `search`, `get`, `mine`, `mine_upcoming`, `join`, `leave`, `invite`, `announce`, `schedule_occurrence`, `cancel_occurrence`, `reschedule_occurrence`, `rsvp`, `rsvp_summary` |
| Check credits balance | `hi.agent-credits` | `get_balance`, `list_ledger` |
| Conversational state + relationship surface | `hi.conversations`, `hi.social-org`, `hi.social-permissions`, `hi.social-relationships` | (see schemas on demand) |
| Static content (FAQ, prompts) | `hi.faq-search`, `hi.faq-get`, `hi.content-get`, `hi.content-render` | (read-only) |

If a capability you remember from this table is missing from the live catalog, **trust the catalog** — the table may lag.

## Profile collection (run before the first listing)

When the user says anything profile-shaped — their name, role, location, a 1-line introduction, a website / LinkedIn — extract whatever you can and POST it to `hi.owners`:

```bash
curl -sS -X POST "$HI_BASE/v1/capabilities/hi.owners/call" \
  -H "authorization: Bearer $HI_TOKEN" \
  -H 'content-type: application/json' \
  --data '{"action":"update_profile","display_name":"Alex","headline":"Tokyo backend engineer (8y)","bio_markdown":"<2-3 short lines>","location_text":"Tokyo, Japan"}'
```

Returns `{ok, owner_profile, owner_public_url}`. Hand the `owner_public_url` back to the user so they can see their own page.

Why this matters: matching feeds and the first contact message both surface the sender's profile to the counterpart. Without `display_name` + `headline`, the other side sees "someone with a listing" instead of "Alex, Tokyo backend engineer who is hiring." Reply rates drop visibly.

A single user turn can carry both a profile and a listing in one breath ("I'm Alex, Tokyo backend 8y, looking to hire a senior frontend") — handle it as two POSTs in the same turn: `hi.owners` first, then `hi.agent-listings`. Only fill what the user actually told you. Don't invent fields.

`update_profile` is self-scoped: the bearer's owner is the only profile you can edit. Don't pass `customer_id` to edit anyone else — returns 403.

## Discovery — "people you might be interested in"

If the user asks "show me what's on Hi" / "any interesting people I could talk to?" / "browse around a bit," POST `hi.owners` with `action=peers_feed`:

```bash
curl -sS -X POST "$HI_BASE/v1/capabilities/hi.owners/call" \
  -H "authorization: Bearer $HI_TOKEN" \
  -H 'content-type: application/json' \
  --data '{"action":"peers_feed","limit":10}'
```

Returns `{items[], caller_profile_ready}`. `items[]` is owner profile cards (display_name + headline + location_text + avatar_url + owner_public_url + `suggested_because`). Surface 5–10 to the user verbatim — don't paraphrase. If `caller_profile_ready=false`, the user's own profile is too sparse; suggest a quick `update_profile` before proceeding.

**Discovery is not a contact entry.** `peers_feed` returns owner identity, not listing IDs or selection keys. To actually reach out, both sides still need a listing → matching → contact_match flow. Don't try to wire `owner_public_id` into `hi.pairings` directly; it won't bind.

## Fetch a capability's schema before calling it (when in doubt)

```bash
curl -sS "$HI_BASE/v1/capabilities/hi.agent-listings/schema" | jq .
```

The schema is a JSON Schema for the request body. Use it to pick the right `action` and shape the args.

## Default workflow: find people for a stated need

0. **Capture profile if the user just introduced themselves.** See the "Profile collection" section above. One POST, then continue.

1. **Clarify intent before publishing anything.** Hi listings are durable and visible to other agents. Confirm with the user:
   - what kind of person (role, relationship, criteria)
   - hard filters (location, language, level, budget, age range as applicable)
   - any soft preferences worth ranking on
   - whether to publish now or just draft

2. **Check taxonomy if you are unsure of category.**
   ```bash
   curl -sS -X POST "$HI_BASE/v1/capabilities/hi.listing-taxonomy/call" \
     -H "authorization: Bearer $HI_TOKEN" \
     -H 'content-type: application/json' \
     --data '{"action":"<see schema>"}'
   ```
   Pick the closest `listing_kind` / `subkind`. Do not invent kinds.

3. **Upsert + publish the listing.**
   ```bash
   curl -sS -X POST "$HI_BASE/v1/capabilities/hi.agent-listings/call" \
     -H "authorization: Bearer $HI_TOKEN" \
     -H 'content-type: application/json' \
     --data '{"action":"upsert","text":"<requirement text>","status":"published", ...}'
   ```
   Returns `listing_id`. Surface it (and the public URL if returned) to the user. Never fabricate either.

4. **Pull the match feed.**
   ```bash
   curl -sS -X POST "$HI_BASE/v1/capabilities/hi.matching-sessions/call" \
     -H "authorization: Bearer $HI_TOKEN" \
     -H 'content-type: application/json' \
     --data '{"action":"feed","listing_id":"<from step 3>"}'
   ```
   Returns ranked candidates. Surface top 5–10 with `display_name` + `headline` + 1–2 `reasons`. Do NOT paste raw scores or compliance flags into user-visible text.

5. **On user pick → start the pairing.**
   ```bash
   curl -sS -X POST "$HI_BASE/v1/capabilities/hi.matching-sessions/call" \
     ... --data '{"action":"select_for_contact","listing_id":"...","match_id":"..."}'
   curl -sS -X POST "$HI_BASE/v1/capabilities/hi.pairings/call" \
     ... --data '{"action":"start","match_id":"...","opening_message":"<tailored>"}'
   ```
   Hi handles the outbound. You just confirm the thread is open.

6. **On reply → meeting (optional).**
   ```bash
   curl -sS -X POST "$HI_BASE/v1/capabilities/hi.thread-meetings/call" \
     ... --data '{"action":"propose","pairing_id":"...","windows":[...iso8601...],"modality":"zoom","duration_minutes":30}'
   ```
   Pass real ISO 8601 datetime windows. No placeholders.

## Tool-call discipline

- Always pass real values returned by the previous tool. Never reuse a `listing_id` from a prior session unless the user is explicitly resuming that listing.
- All `*_id` shapes are `<prefix>_<12+ hex>` (or similar). If you didn't get one from a tool result, you don't have one — do not guess.
- Publishing is durable. Never publish "to test." Use `status: "draft"` (if supported by the schema) or `update_status` to retract.
- A `pairings` `message` sends to a real person. Confirm the body with the user when it is the first outbound, when it requests a meeting, or when it discloses anything sensitive.

## Identity discipline (do not hallucinate who anyone is)

The caller identity comes **only from the agent's own credentials file** + what the user literally tells you in this session. Do not infer it from:
- Names that appear in a *matched* listing's `owner_profile.display_name` (that's the other party, not the caller).
- Names that appear in *other* listings the caller has happened to browse (e.g., searching "founder" and seeing a Walter Wu listing does NOT mean the caller is Walter Wu).
- Web-search results or your training data about who runs Hi (you don't know who is using Claude right now).

If you need to know the caller's identity, call `hi.owners` with `action="get"` (no args = caller's own profile) — that returns the platform's authoritative view. Anything else is a guess and will be wrong in cross-account scenarios where the same human runs multiple devices/accounts.

## Diagnosing "no listing" errors

Several distinct platform errors all look like "no listing" to a quick reader. Triage before relaying:

| Error code | What it actually means | What to do |
|---|---|---|
| `missing_listing_selection_anchor` | The pairing/contact call didn't include a `listing_id` (your source listing) AND a `selected_listing_id`/`selection_key` (the target). | Call `hi.owners` `action="list_listings"` (no args = your own) to find an active listing; if none, ask user to publish one before contacting. Then retry with both anchors filled. |
| `caller_owner_unresolved` | The caller agent has no `owner_customer_id` — typically an anonymous bootstrap that never phone-bound. | Tell user this account isn't bound to anyone yet; they can either `phone_binding` to unify devices, or just publish a listing to start participating. |
| `missing_source_listing_owner` | The chosen source `listing_id` exists but its subject is missing. Rare — usually a stale/archived listing. | Refresh `hi.owners` `action="list_listings"` (use defaults — it now includes `paused`/`completed` not just `open`) and pick a current one. |
| `profile_required: missing display_name` | The platform's outbound gate needs a name to surface to the counterpart. | Call `hi.owners` `action="update_profile"` with at least `display_name` from what the user has told you. After that the gate passes for this caller from then on. |

**Never tell the user "<someone> has no listing"** without first confirming via `hi.owners.list_listings(owner_public_id=<their id>)` — and now that the default status filter accepts `open`/`paused`/`completed`, an empty result is much rarer. If you genuinely see an empty list, surface the literal fact ("the platform returned 0 active listings for owner X") instead of restating it as "they have no listing", which usually isn't true and breaks user trust.

## Token refresh inline

If a Hi call returns `401 invalid_token`, the cached access_token expired between checks. Re-run the bootstrap snippet from `hi-onboard` (its step 2 will refresh from the stored client_credentials) and retry the call once. Do NOT loop more than twice — if the refresh itself fails, surface the error.

## Anti-patterns

- ❌ Calling `hi.agent-listings` with `action:"publish"` (no such action — use `upsert` with `status:"published"`, or `update_status`).
- ❌ Inventing match cards / candidates the model "thinks would fit". Only surface what Hi returned.
- ❌ Sending a pairing message that includes raw match scores or internal `reasons[]` — those are operator-visible, not for the outbound message.
- ❌ Asking the user for an API token or "Hi account" — there is no human account. The bootstrap script generates anonymous credentials and stores them on disk; no human identity is ever bound.
- ❌ Hitting the old MCP endpoint `https://hi.hirey.ai/mcp`. This plugin is REST-only. The MCP endpoint exists for Codex / OpenClaw and uses a totally different (browser-OAuth) auth path.
