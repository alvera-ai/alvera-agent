# Healthcare reference fixtures

The integration-tests at `@alvera-ai/platform-sdk@0.8.0` ship reference
fixtures that this skill can point at when the user doesn't have their
own data ready. They are **synthetic** — never real PHI — and live at:

```
https://github.com/alvera-ai/platform-sdk/tree/v0.8.0/integration-tests/tests/healthcare/fixtures
```

## When to use them vs the user's data

| Situation | Use fixtures? |
|---|---|
| User exploring Alvera for the first time, no real data on hand | **Yes** — walk the canonical 11 phases against fixtures |
| User has a sample from their EMR but is anxious about format | **Yes for the first phase**, then switch to user data once they see the shape |
| User has prod-ish data and a target schema | **No** — drive the conversation off their data, fixtures are reference-only |
| User's data is regulated PHI | **Definitely not** — `/custom-dataset-creation`'s compliance gate covers this; never inline PHI into chat |

## What's in the fixtures dir

- **CSV files under `fixtures/csv/`** — bulk ingest source files, e.g.
  `alvera_reviews_cahps_appointments_batch1.csv` (3 rows of synthetic
  CAHPS appointment-review data). Used by phase 9 (run-dac-bulk).
- **Liquid templates under `fixtures/templates/`** — three reference
  interop contracts:
  - `appointment-mapping.liquid` — Athena appt → FHIR Appointment
  - `patient-mapping.liquid` — EMR patient → FHIR Patient
  - `contact-us-mapping.liquid` — inbound contact form → custom dataset
  Used by phase 4 (interoperability-contracts) and phase 11
  (agent-driven-workflow).
- **JSON inline bodies inside specs** — single-row payloads for phase 8
  (run-dac-single) live in the spec files themselves, not as separate
  fixture files. Refer the user to the spec source if they want the
  exact shape.

## Mapping fixtures → phases

| Phase | Reference fixture | Where to find it |
|---|---|---|
| 4 interop-contracts | `fixtures/templates/*.liquid` | three Liquid templates |
| 8 run-dac-single | inline JSON in `run-dac-single.test.ts` | `expect(ingest…).toBe()` blocks |
| 9 run-dac-bulk | `fixtures/csv/alvera_reviews_cahps_appointments_batch1.csv` | bulk CSV |
| 10 standard-workflow | inline appointment row in `standard-workflow.test.ts` | `runWorkflow` payload |
| 11 agent-driven-workflow | three contact-us payloads in `agent-driven-workflow.test.ts` | §6 of the spec |

## Pin discipline

These fixtures are pinned to **v0.8.0** alongside this skill. If the
user's local checkout is on a different SDK version, the fixture paths
or contents may have shifted — re-pin or surface the drift.
