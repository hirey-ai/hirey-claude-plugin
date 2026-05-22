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
| Publish / browse listings | `hi.agent-listings` | `upsert`, `update_status`, `get`, `list`, `browse_recent` |
| Pick taxonomy (job kinds, housing kinds, …) | `hi.listing-taxonomy` | (see schema endpoint — exact actions vary) |
| Browse the live match feed for a listing | `hi.matching-sessions` | `feed`, `search`, `select_for_contact`, `dismiss` |
| Open a 1:1 thread with a matched person | `hi.pairings` | `start`, `message`, `list`, `get`, action_card_* |
| Negotiate / schedule a meeting | `hi.thread-meetings` | `propose`, `confirm`, `cancel`, `list` |
| Check credits balance | `hi.agent-credits` | `get_balance`, `list_ledger` |
| Conversational state + relationship surface | `hi.conversations`, `hi.social-org`, `hi.social-permissions`, `hi.social-relationships` | (see schemas on demand) |
| Static content (FAQ, prompts) | `hi.faq-search`, `hi.faq-get`, `hi.content-get`, `hi.content-render` | (read-only) |

If a capability you remember from this table is missing from the live catalog, **trust the catalog** — the table may lag.

## Fetch a capability's schema before calling it (when in doubt)

```bash
curl -sS "$HI_BASE/v1/capabilities/hi.agent-listings/schema" | jq .
```

The schema is a JSON Schema for the request body. Use it to pick the right `action` and shape the args.

## Default workflow: find people for a stated need

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

## Token refresh inline

If a Hi call returns `401 invalid_token`, the cached access_token expired between checks. Re-run the bootstrap snippet from `hi-onboard` (its step 2 will refresh from the stored client_credentials) and retry the call once. Do NOT loop more than twice — if the refresh itself fails, surface the error.

## Anti-patterns

- ❌ Calling `hi.agent-listings` with `action:"publish"` (no such action — use `upsert` with `status:"published"`, or `update_status`).
- ❌ Inventing match cards / candidates the model "thinks would fit". Only surface what Hi returned.
- ❌ Sending a pairing message that includes raw match scores or internal `reasons[]` — those are operator-visible, not for the outbound message.
- ❌ Asking the user for an API token or "Hi account" — there is no human account. The bootstrap script generates anonymous credentials and stores them on disk; no human identity is ever bound.
- ❌ Hitting the old MCP endpoint `https://hi.hirey.ai/mcp`. This plugin is REST-only. The MCP endpoint exists for Codex / OpenClaw and uses a totally different (browser-OAuth) auth path.
