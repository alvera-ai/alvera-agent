---
name: payment-risk
description: >
  End-to-end provisioning of a payment-risk host on Alvera. Currently a STUB —
  the canonical setup walk lives in `tests/payment_risk/_order.json` at
  `@alvera-ai/platform-sdk@0.8.0`, which today contains only a smoke spec
  because the payment-risk industry is not yet productionised. Use this skill
  to get a stub setup conversation that lists payment-risk-specific resource
  types and routes to `/guided` for ad-hoc creation. Real domain orchestration
  replaces this stub when payment-risk integration coverage lands. Use when the
  user says "set up payment-risk", "provision a KYC/AML tenant", "fraud setup",
  or similar.
---

# Payment-Risk host setup — stub

End-to-end domain orchestrator for payment-risk (KYC, AML, fraud).
**Currently a stub.** The integration-tests suite at
`@alvera-ai/platform-sdk@0.8.0` includes only a smoke spec for
`tests/payment_risk/`; a real phase-by-phase walk will land here once
the payment-risk domain has full integration coverage.

## SDK pin

This skill targets **`@alvera-ai/platform-sdk@0.8.0`** exactly, matching
the rest of the domain skills. Payment-risk manifest:

```
https://github.com/alvera-ai/platform-sdk/blob/v0.8.0/integration-tests/tests/payment_risk/_order.json
```

Currently `["smoke"]`. When real specs land, this skill will be expanded
to walk them in order.

## What this skill does today

Routes the user to `/guided` for ad-hoc resource creation, with
payment-risk-specific suggestions. The primitive skills (`guided`,
`custom-dataset-creation`, `DAC-upload`, `agentic-workflow-creation`,
`query-datasets`) all work for payment-risk resources today — they're
domain-agnostic. What's missing is the *opinionated phase sequence*
that the healthcare skill provides.

## Workflow

1. **Confirm SDK pin.** `alvera --version` should report `0.8.0`. If
   not, install `@alvera-ai/platform-sdk@0.8.0`.
2. **Set expectations explicitly.** Tell the user this is a stub —
   they're getting `/guided` with payment-risk-flavoured suggestions,
   not the full canonical walk that healthcare gets. If they need a
   phase sequence today, point at the healthcare skill's
   `references/order-walk.md` as a reference template they can adapt.
3. **Suggest typical payment-risk resource types.** Common shapes:
   - **Custom datasets** — KYC submissions, sanctions hits, AML
     alerts, transaction-screening events. Use `/custom-dataset-creation`.
   - **Tools** — sanctions-screening APIs, identity-verification
     vendors, internal alert webhooks. Use `/guided`.
   - **AI agents + workflows** — transaction triage, AML narrative
     generation, sanctions hit review. Use
     `/agentic-workflow-creation`.
4. **Hand off to `/guided`** for the resource loop. Don't try to
   sequence — that's what the healthcare skill does and that machinery
   isn't ready for payment-risk yet.

## When this stub gets replaced

When `tests/payment_risk/_order.json` grows beyond `["smoke"]`,
re-pin this skill to the new SDK tag and replace this stub with a
phase-walk modelled on `skills/healthcare/SKILL.md`. The structure
should mirror healthcare's: `SKILL.md` + `references/order-walk.md` +
`references/fixtures.md` + `references/example-transcript.md`.

## Out of scope

Same as the healthcare skill — prod tenant setup, cross-domain setup,
runtime ops are all out of scope here. Domain stubs aren't a license
to expand the surface.
