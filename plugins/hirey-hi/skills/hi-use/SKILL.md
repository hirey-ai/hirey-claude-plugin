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
| **Find a specific person / listing by NAME or free text** (no listing needed, anonymous) | `hi.owners` | **`search`** (`q="walter"` / `q="founder building agent infra"`) — see "Search by name" below |
| Capture / update who the user is (name, headline, bio) | `hi.owners` | `update_profile`, `get`, `list_listings`, `peers_feed` — **call this first** when the user has just introduced themselves |
| Publish / browse listings | `hi.agent-listings` | `upsert`, `update_status`, `get`, `list`, `browse_recent` |
| Pick taxonomy (job kinds, housing kinds, …) | `hi.listing-taxonomy` | (see schema endpoint — exact actions vary) |
| Browse the live match feed for a listing | `hi.matching-sessions` | `match_feed`, `search`, `contact_match` |
| Open a 1:1 thread with a matched person | `hi.pairings` | `create`, `timeline`, `contact_target` |
| Negotiate / schedule a meeting | `hi.thread-meetings` | `start`, `respond`, `get` |
| Host / discover public multi-party activities | `hi.event-groups` | `create`, `search`, `get`, `mine`, `mine_upcoming`, `join`, `leave`, `invite`, `announce`, `schedule_occurrence`, `cancel_occurrence`, `reschedule_occurrence`, `rsvp`, `rsvp_summary` |
| Check credits balance | `hi.agent-credits` | `get_balance`, `list_ledger` |
| **Bind the owner identity at the first write** (Sign in with Google — default) | `hi.google-link` | `start`, `poll` — see "Binding the owner identity" below; `hi.phone-binding` / `hi.email-binding` are the fallbacks |
| Conversational state + relationship surface | `hi.conversations`, `hi.social-org`, `hi.social-permissions`, `hi.social-relationships` | (see schemas on demand) |
| Static content (FAQ, prompts) | `hi.faq-search`, `hi.faq-get`, `hi.content-get`, `hi.content-render` | (read-only) |

If a capability you remember from this table is missing from the live catalog, **trust the catalog** — the table may lag.

## Binding the owner identity (Google default)

The anonymous credentials in `~/.config/hi/credentials.json` are the **connection** layer — they let you read and search immediately. The **owner identity** is bound separately, and only when the user's first WRITE hits the write gate: a capability call (e.g. `hi.agent-listings` `upsert`, `hi.matching-sessions` `contact_match`) returns `phone_binding_required` (a.k.a. `caller_owner_unresolved`). Binding proves who the owner is and joins this device to their workspace. There are **three equivalent anchors — default to Google:**

**DEFAULT — Sign in with Google** (`hi.google-link`; lowest friction, nothing to type). Start the link, read the URL to the user, then poll:

```bash
# 1) Start — returns a verification_url valid ~10 min.
curl -sS -X POST "$HI_BASE/v1/capabilities/hi.google-link/call" \
  -H "authorization: Bearer $HI_TOKEN" -H 'content-type: application/json' \
  --data '{"action":"start"}'
# → {ok, link_id, verification_url, expires_at, instructions}
```

**Read/paste the `verification_url` to the user** and tell them what to expect: open it in a **browser**, sign in with Google, and wait for the **"✅ Signed in as …" success page** — that's the signal it worked; have them reply (e.g. "done") once they see it. You can't open a browser — the user does. Then poll until verified:

```bash
# 2) Poll — repeat every few seconds. (link_id optional; the bearer scopes it.)
curl -sS -X POST "$HI_BASE/v1/capabilities/hi.google-link/call" \
  -H "authorization: Bearer $HI_TOKEN" -H 'content-type: application/json' \
  --data '{"action":"poll"}'
# pending  → {ok, status:"pending"}   ← keep polling; do NOT call start again
# verified → {ok, status:"verified", workspace_id, email, joined_existing_workspace,
#             agents_in_workspace, workspace_agents:[{agent_id,device_label,status,last_seen,is_self}]}
```

While the user hasn't finished it returns `status:"pending"` — keep polling, **do not call `start` again on each poll**. If `start`/`poll` returns `link_expired` or `link_already_consumed`, tell the user and call `start` once more to get a fresh URL.

**Fallbacks** (offer only if the user prefers them — all three converge to the same workspace):
- **phone** — `hi.phone-binding`: `bind` (user gives a phone number) → `verify` with the SMS code.
- **email** — `hi.email-binding`: `bind` (user gives an email) → `verify` with the emailed code.

The `google-link` `poll` response is identical to `phone-binding`/`email-binding` `verify` (plus a `status` field), so the continuity guidance below applies to all three. Offer Google first ("I can sign you in with Google — want me to?"); only fall back to phone/email if the user asks. New to Hi → binding creates the agent + a fresh workspace; returning (any anchor, used before) → the **same** Google account / phone / email rejoins the existing workspace, and the verified response carries `joined_existing_workspace` + `workspace_agents` — say it out loud and list their devices. Because every write requires a bind, offer Google sign-in early rather than after the user has created data.

## Binding / connecting your identity to Hi (proactive)

When the user wants to **bind / connect / add / save** their **email, phone, or Google account to Hi** — to keep their identity, recover their workspace across devices/reinstalls, or unlock writes — use **Hi's OWN capabilities** (the call shapes are in "Binding the owner identity" above; this is just the routing):

- **Email → default `hi.google-link`** (one-click Sign in with Google — `start` → give the user the `verification_url` → `poll`). If they'd rather not use Google, **`hi.email-binding`** (`bind` → `verify` with the emailed code).
- **Phone → `hi.phone-binding`** (`bind` → `verify` with the SMS code).

⚠️ **This is Hi's identity binding, NOT a host-native email/Gmail/calendar connector.** Never tell the user to reauthorize or reconnect a host app (e.g. a Claude/OpenClaw "Gmail connector") for this — that's a different thing and won't bind them to Hi. If a host shows a "reauthenticate this app" message for some Gmail/email connector, that is NOT how you bind email to Hi; call `hi.google-link` / `hi.email-binding` instead.

The three anchors (phone / email / Google) are **equivalent and additive in ANY order**: a user who already bound one can bind another later and it **converges to the same workspace** — never a second account. So "I bound my phone, now I also want to add my email/Google" (and vice-versa) just works — go ahead and bind the additional anchor.

## Device identity & continuity (name your devices · move identity across machines)

Hi identity = the install-time credential in `~/.config/hi/credentials.json`; binding the owner identity (Google by default — see above — or phone/email) anchors it to a durable workspace. Three things keep multi-device life sane:

**Name this device** — in a multi-device workspace, give each agent/device a self-label so the user can tell them apart. The label is **internal** (never shown to counterparts):

```bash
curl -sS -X POST "$HI_BASE/v1/capabilities/hi.owners/call" \
  -H "authorization: Bearer $HI_TOKEN" -H 'content-type: application/json' \
  --data '{"action":"set_device_label","device_label":"my MacBook (Claude)"}'
```

**On sign-in, tell the user what they rejoined** — the bind response (`hi.google-link` `poll` once `status:"verified"`, or `hi.phone-binding`/`hi.email-binding` `verify`) returns `workspace_agents:[{agent_id,device_label,status,last_seen,is_self}]` + `joined_existing_workspace`. When `joined_existing_workspace=true`, say it out loud: *"You're back in your existing workspace — your listings, threads, and replies are all here, and this device can reply to them."* List the devices by `device_label`. This kills the "did I lose everything / am I a new agent now?" worry.

**Carry your identity to a NEW machine (claim re-attach)** — when the user reinstalls / switches machines / lost their creds and does NOT want a brand-new empty agent:
1. On the OLD (working, phone-bound) device, mint a one-time transfer token:
   ```bash
   curl -sS -X POST "$HI_BASE/v1/agents/claim/export" -H "authorization: Bearer $HI_TOKEN" -H 'content-type: application/json' --data '{}'
   # → {claim_token, agent_id, expires_at}. Treat claim_token like a password — single-use + short-lived.
   ```
2. On the NEW device (after its own bootstrap), redeem it to become the SAME agent:
   ```bash
   curl -sS -X POST "$HI_BASE/v1/agents/claim/redeem" -H "authorization: Bearer $HI_TOKEN" -H 'content-type: application/json' --data '{"claim_token":"<paste>"}'
   # → {ok, agent_id}. This device IS that agent now — listings/threads/replies all follow.
   ```
`export` requires the OLD device to have a bound owner identity (Google/phone/email — proof of ownership). If the user can't reach the old device, the fallback still works: on the new device, sign in with the SAME Google account (default) — or bind the same phone/email — and it rejoins the same workspace (you just get one extra device entry).

## Profile collection (run before the first listing)

When the user says anything profile-shaped — their name, role, location, a 1-line introduction, a website / LinkedIn — extract whatever you can and POST it to `hi.owners`:

```bash
curl -sS -X POST "$HI_BASE/v1/capabilities/hi.owners/call" \
  -H "authorization: Bearer $HI_TOKEN" \
  -H 'content-type: application/json' \
  --data '{"action":"update_profile","display_name":"Alex","headline":"San Francisco backend engineer (8y)","bio_markdown":"<2-3 short lines>","location_text":"San Francisco, USA"}'
```

Returns `{ok, owner_profile, owner_public_url}`. Hand the `owner_public_url` back to the user so they can see their own page.

Why this matters: matching feeds, the first contact message, AND meeting invites all surface the sender's profile to the counterpart. Use the user's **real name** (plus a one-line headline) — the platform's outbound gate now rejects generic agent/device labels like "Claude Code (Hirey skill)" or "Hi agent" (the other person sees a robot instead of a human, and Zoom invites get declined). Without a real `display_name` + `headline`, the other side sees "someone with a listing" instead of "Alex, San Francisco backend engineer who is hiring." Reply rates drop visibly.

A single user turn can carry both a profile and a listing in one breath ("I'm Alex, San Francisco backend 8y, looking to hire a senior frontend") — handle it as two POSTs in the same turn: `hi.owners` first, then `hi.agent-listings`. Only fill what the user actually told you. Don't invent fields.

`update_profile` is self-scoped: the bearer's owner is the only profile you can edit. Don't pass `customer_id` to edit anyone else — returns 403.

## Search by NAME or free text — "find me a person/listing called X"

When the user names someone or describes who/what they're looking for — **"给我搜一个叫 walter 的人"**,
"find a founder building agent infra", "搜一下旧金山的后端招聘" — use `hi.owners` with `action=search`.
This is the by-name / free-text entry point: **anonymous (no login), no listing required**, fuzzy +
partial + typo-tolerant, bilingual (it auto-expands EN↔中文 — searching "walter" also matches 沃尔特,
and a Chinese query matches English profiles). It searches **both owner profiles and listings**.

```bash
curl -sS -X POST "$HI_BASE/v1/capabilities/hi.owners/call" \
  -H "authorization: Bearer $HI_TOKEN" \
  -H 'content-type: application/json' \
  --data '{"action":"search","q":"walter"}'
```

Returns `{query, understanding, people[], listings[]}`. `people[]` = matching owner cards
(display_name + headline + owner_public_url); `listings[]` = matching public listings (preview +
publisher card). `understanding` shows how the query was expanded (intent + term groups) — for
transparency, don't surface it to the user. Show the people + listings; offer to open a pairing
(listing → matching → contact_match) if the user wants to reach someone.

Use `search` (not `matching_sessions.search`) for "find a specific person/thing by name or keywords."
Use `matching_sessions.search` only when the user already has a published listing and wants
structured role/requirement matchmaking against it.

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

0. **Set up: outline the plan, then capture the user's real identity.** For a new user, first tell them in one line how Hi works so setup isn't confusing: *"Here's how this works: I'll set up your Hi profile (your real name + a one-line headline), post what you're looking for, show you matches, and connect you — we can even schedule a Zoom, all from this chat."* Then capture their profile (see "Profile collection" above — use their **real name**, never a generic/agent label). One `update_profile` POST, then continue.

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
| `caller_owner_unresolved` / `phone_binding_required` | The caller agent has no `owner_customer_id` — typically an anonymous bootstrap that hasn't bound an owner identity yet (this IS the write gate). | Bind the owner identity — **default: Sign in with Google** (`hi.google-link`; see "Binding the owner identity" above), with `hi.phone-binding` / `hi.email-binding` as fallbacks. After the bind verifies, retry the write. |
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
