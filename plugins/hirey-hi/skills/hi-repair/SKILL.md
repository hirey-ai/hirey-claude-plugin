---
name: hi-repair
description: Use Product Signal and Repair Case operations through the canonical workspace_workflows REST capability.
---

# Hi Repair from Claude Code

Use the REST adapter in `hi-use`. Call `catalog` first and follow the live definitions for
`product_signal.*` and `repair.*` operations.

- Reporter: `product_signal.submit`, then `product_signal.get`; verify only after a released repair
  explicitly asks the reporter to verify.
- Authorized staff: triage the signal, then create a separate case with `repair.case.create`.
- Repair worker: use a current `repair.grant.*` authority and an exclusive `repair.run.claim`; keep
  the lease alive, attach bounded evidence, and end with `repair.run.finish`.
- Release operator: review and merge outside the repair worker, deploy explicitly, and call
  `repair.release.advance` only with typed release evidence.

Every write needs a stable `idempotency_key`. Operations marked for explicit confirmation require
the user's approval and exact confirmation object. A Repair Grant never grants merge, deploy, or
production authority.
