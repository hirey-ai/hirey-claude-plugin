---
name: hi-repair
description: Run HiRey's root-cause-first bug repair workflow from Claude Code using Product Signals, case-scoped Repair Grants, exclusive leases, evidence, and reviewable pull requests. Use when somebody reports a bug, staff assign a Problem Case, Claude Code should process an assigned repair, Walter wants a PR-ready repair without automatic deployment, or the original reporter needs to verify a released fix.
---

# Hi Repair

Turn a report into a bounded investigation and reviewable PR without exposing the repository to the reporter or delegating release authority.

## Call Hi safely

Use the authenticated REST pattern from `hi-use`. The capability IDs are:

- `hi.product-signals` for reporter intake and post-release verification.
- `hi.repair-cases` for staff admission, grants, leases, evidence, and PR submission.

Send action arguments as JSON to `POST https://hi.hirey.ai/v1/capabilities/<capability-id>/call`. Read the bearer from `~/.config/hi/credentials.json` without printing it. If credentials are missing or a call returns `401 invalid_token`, run `hi-onboard`, then retry once.

Notation such as `repair_cases(action="claim", ...)` below means a REST call to `hi.repair-cases` with that JSON body. Never put the bearer, claim code, lease token, contact data, or raw provider payload in logs, evidence, commits, or chat.

## Keep authority separated

- Reporter: submit Product Signals and verify only after production asks them to retry.
- Product Signals staff: triage, create a separate Problem Case, and create or revoke a case-scoped grant.
- Repair worker: work only through an active grant and lease; stop at a PR or an explicit blocked result.
- Walter: review, merge, manually deploy, attach production truth, and decide release status.

Never ask for Walter's Claude/OpenAI token. The local Claude Code session supplies model work; the Hi bearer only authorizes HiRey data.

## Admit and assign

1. Preserve observed facts with `product_signals(action="submit")`. Split independent symptoms and reuse a stable idempotency key for retries.
2. Staff reads the company queue and records explicit one-field decisions through `repair_cases(action="triage_signal")`.
3. Define an observable `failure_contract`; do not send an untriaged complaint straight into a repository.
4. Create a separate Problem Case and keep the source signal immutable. Put hypotheses and engineering evidence on the case.
5. Keep identity/consent, PII/security, notification/outbox, schema migration, cross-repository contract, and deployment-mechanism risks out of the autonomous lane.
6. Create a grant with `read_pack` plus only required capabilities, an exact lowercase GitHub `owner/name` allowlist, and a bounded expiry. Give another person the one-time `claim_code` privately; use `bind_to_self=true` only for Walter's own worker.

## Process one repair

Handle at most one case per interactive or scheduled run:

1. Call `repair_cases(action="list_grants", scope="mine")`, then `get_pack` for one active grant.
2. Confirm `risk_class=normal`, the repository is allowlisted, and the failure contract is concrete. Otherwise stop and report the required staff decision.
3. Claim with the exact repository and `agent_kind="claude_code"`. Keep the lease token private and heartbeat during longer work.
4. Read repository instructions, check current work ownership, and create an isolated branch/worktree from the canonical remote base.
5. Reproduce before editing. Add only bounded, non-secret evidence.
6. Establish `first_bad_state`, `violated_invariant`, and a concrete `causal_chain`. Mark root cause verified only when reproduction supports it.
7. Implement the smallest durable correction and regression guard; run the repository's required checks.
8. Push the correctly prefixed branch, open a reviewable PR, and call `repair_cases(action="submit_pr")` with its exact URL, branch, and causal summary.
9. Stop. A PR or green CI is not deployed. Do not merge, deploy, add deploy/production evidence, or mark the case resolved.

If the lease conflicts, refresh rather than working concurrently. If evidence is insufficient, scope is wrong, or risk becomes non-normal, release the lease with a precise `blocked_reason`.

## Verify a released fix

Only when `product_signals(action="get")` returns `repair.status="live_please_verify"`, ask the original reporter to retry the original symptom. Record `works_now` or `still_broken` with `product_signals(action="verify_repair")` and a stable idempotency key. Reporter confirmation never replaces a deploy receipt or production probe.

Always report one truthful state: `PR open`, `merged, unreleased`, or `deployed and verified`.

## Scheduled task prompt

> Use $hi-repair to process at most one assigned normal-risk Repair Grant. If none is assigned, inspect the staff repair inbox and admit at most one concrete, non-duplicate, normal-risk bug whose expected behavior and repository are clear. Work in an isolated worktree, prove the root cause, add a regression guard, and stop after opening and recording a reviewable PR. Never invent priority, merge, or deploy. If blocked or high risk, record the exact reason.
