---
name: healthcare
description: >
  End-to-end provisioning of a healthcare host on Alvera, walking the canonical
  11-phase setup defined by `tests/healthcare/_order.json` in
  `@alvera-ai/platform-sdk@0.8.0` (the executable contract). Each phase delegates
  to a primitive skill (`guided`, `custom-dataset-creation`, `DAC-upload`,
  `agentic-workflow-creation`, `query-datasets`) and ends with a verification
  pointer back at the corresponding integration-tests spec, so the conversational
  setup and the automated suite never drift apart. Use when the user says
  "set up healthcare", "provision a healthcare tenant", "walk me through
  healthcare setup end to end", or similar. Domain-first orchestrator —
  invoke the primitive skills directly for ad-hoc / out-of-sequence work.
---

# Healthcare host setup

End-to-end domain orchestrator. The user describes their healthcare data;
this skill walks them through the same 11 phases the integration-tests
suite executes against the dev stack — but with their real data instead
of synthetic fixtures.

## SDK pin

This skill targets **`@alvera-ai/platform-sdk@0.8.0`** exactly. The walk
below mirrors the manifest at that tag:

```
https://github.com/alvera-ai/platform-sdk/blob/v0.8.0/integration-tests/tests/healthcare/_order.json
```

If the user has a different SDK version installed, prompt to install
`@alvera-ai/platform-sdk@0.8.0` before continuing — version drift breaks
the phase-to-spec mapping below.

## Prerequisites

- `alvera` CLI reachable (delegate to `/guided` "Step 0" if not)
- Active session for the target tenant (`alvera login`, then `alvera whoami`
  to verify) — the skill never sees the password
- A working dev / test environment of Alvera (this skill is not for prod
  bring-up — provision in a sandbox tenant first)

## The 11-phase walk

Each phase below is a single line: **what gets provisioned** + **which
primitive skill drives it** + **the spec that verifies it landed**.

| # | Phase | Primitive skill | Verifies via |
|---|---|---|---|
| 1 | bootstrap | `/guided` (datalake create) | `bootstrap.test.ts` |
| 2 | data-sources | `/guided` (data-sources create) | `data-sources.test.ts` |
| 3 | custom-datasets | `/custom-dataset-creation` | `custom-datasets.test.ts` |
| 4 | interoperability-contracts | `/guided` (interop-contracts create) | `interoperability-contracts.test.ts` |
| 5 | invite-team | `/guided` (admin invite) | `invite-team.test.ts` |
| 6 | tools | `/guided` (tools create) | `tools.test.ts` |
| 7 | create-dac | `/guided` (data-activation-clients create) | `create-dac.test.ts` |
| 8 | run-dac-single | `/DAC-upload` (single-row) | `run-dac-single.test.ts` |
| 9 | run-dac-bulk | `/DAC-upload` (CSV) | `run-dac-bulk.test.ts` |
| 10 | standard-workflow | `/agentic-workflow-creation` (template) | `standard-workflow.test.ts` |
| 11 | agent-driven-workflow | `/agentic-workflow-creation` (custom + AI agent) | `agent-driven-workflow.test.ts` |

Detailed walkthrough — what to elicit, what to confirm, what to verify —
lives in `references/order-walk.md`. Read it before opening the phase
loop.

## Workflow

1. **Confirm SDK pin** — `alvera --version` should report `0.8.0`. If not,
   install: `npm install -g @alvera-ai/platform-sdk@0.8.0` (or the user's
   preferred package manager). Stop and ask if the user wants a different
   pin — the phase-to-spec mapping is tied to this exact tag.

2. **Open the phase loop** — announce the 11-phase plan up front so the
   user knows what they're agreeing to. Example:

   > "I'll walk you through the canonical healthcare host setup —
   > 11 phases, end-to-end, mirroring the `tests/healthcare/_order.json`
   > sequence at platform-sdk@0.8.0. We can stop at any phase, skip
   > non-essential ones (invite-team is the obvious one), or pause and
   > resume later. Ready?"

3. **Per phase** (1 → 11):
   - Read the corresponding section of `references/order-walk.md`.
   - Hand off to the primitive skill with a tight scoping handover —
     don't reimplement what `/guided` or `/custom-dataset-creation`
     already does.
   - On return, confirm the resource landed (one CLI list call) and
     point at the integration-tests spec as the executable check the
     user can run themselves: `pnpm test:healthcare -- <spec-name>`.
   - Append to `infra.yaml` if the receipt is enabled.

4. **Stop on first failure.** If any phase fails (4xx, missing
   prerequisite, validation error), do NOT skip to the next phase —
   subsequent phases assume the previous one's output. Surface the
   failure plainly, route the user to fix it (often by going back to
   the relevant primitive skill in isolation), and pick up the walk
   from the failed phase.

## Stance: be a conductor, not a re-implementer

The five primitive skills already know how to provision their resources.
This skill's job is to:

- Sequence them correctly (per `_order.json`)
- Hand off scoped context (datalake slug, prior phase IDs)
- Verify each phase before advancing
- Translate between the user's domain language ("our patient data",
  "appointment reminders") and the primitive skills' resource language

Do **NOT** duplicate any elicitation logic the primitive skills own.
If the user wants to override a phase mid-walk (e.g. "I already have an
EMR data source — skip phase 2"), accept and verify by listing the
existing resource, then continue.

## Out of scope

- **Prod tenant setup** — this skill is for dev / test environments.
  Real prod onboarding has additional compliance gates (BAA, PHI handling
  audits) outside this skill's purview.
- **Cross-domain setup** — for `accounts-receivable` or `payment-risk`
  industries, use those domain skills (currently stubs — they delegate
  to `/guided`).
- **Runtime ops** — workflow execution, dataset search, and DAC ingest
  beyond the canonical-walk verifications belong to runtime usage, not
  setup. Out of scope here.

## References

- `references/order-walk.md` — per-phase elicitation + verification
- `references/fixtures.md` — synthetic fixtures from platform-sdk and
  how they relate to user-supplied real data
- `references/example-transcript.md` — sample 11-phase conversation
