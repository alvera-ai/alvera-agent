# Healthcare — example transcript

A condensed reference for what an end-to-end conversation looks like.
Phases are abbreviated; real conversations include more confirmations
and clarifications. Read this once to internalise the cadence; do
**not** read aloud as a script.

---

**User:** I want to set up healthcare on Alvera end to end.

**Skill:** Great. I'll walk you through 11 phases — same sequence the
integration-tests suite runs against the dev stack at
platform-sdk@0.8.0. Roughly 30-45 min if you have data on hand;
longer if we use the reference fixtures.

First, the SDK version: `alvera --version` → ✅ reports 0.8.0.

Ready to start with phase 1 (bootstrap — tenant + datalake)?

**User:** Go.

---

### Phase 1 — bootstrap

**Skill:** Handing off to `/guided` for datalake creation. I'll need
DB credentials (regulated + unregulated), S3 bucket info, and a
tenant name. Got those, or want to use a `.env` file?

*(`/guided` runs its full datalake-create flow; returns datalake slug
`prime-health-lake-001`)*

**Skill:** Bootstrap done. Datalake `prime-health-lake-001` reached
`status: ready`. Verify locally any time:
`pnpm test:healthcare -- bootstrap`. Phase 2 next?

---

### Phase 2 — data-sources

**Skill:** What external system are you ingesting from? Athena,
Epic, Cerner, custom?

**User:** Athena.

**Skill:** Naming the source `Athena Health EMR` with URI
`our-emr:athena-001`. Confirm? *(yes)* …handing to `/guided`
data-sources create. ✅ created.

---

### Phase 3 — custom-datasets

**Skill:** Any custom (non-FHIR) tables you need? Common in healthcare
ops: appointment reviews, contact-us forms, intake questionnaires.

**User:** Yes, a contact-us form.

**Skill:** Got a sample CSV or NDJSON? *(user provides
`contact-us-sample.csv`)* …handing to `/custom-dataset-creation`
— it'll do the compliance gate, profile your columns, and propose
a schema. Compliance class likely "shareable" since it's a contact
form, not PHI.

---

### Phases 4-7 (compressed)

**Skill:** Phase 4 is interop-contracts. You'll need at least one
mapping a source row to a FHIR / custom-table shape. I have three
reference Liquid templates in fixtures if you want to start there.
*(user picks `contact-us-mapping.liquid`)*

…phases 4 → 7 walk via `/guided` with handoffs. Each lands; verify
spec is named after each phase ends.

---

### Phase 8 — run-dac-single

**Skill:** Now for the proof of life — single-row ingest end-to-end.
Got a single sample record matching your DAC's source schema?

**User:** Use the reference fixture.

**Skill:** OK — pulling from `tests/healthcare/run-dac-single.test.ts`
§2 (`a CAHPS-shaped JSON row`). Handing to `/DAC-upload` single-row
mode. *(uploads, polls, succeeds)*. ✅ row landed in the unregulated
datalake; tokenised birth_date present, plain gender present.

---

### Phase 9 — run-dac-bulk

**Skill:** Same pipeline, bulk CSV. Reference fixture is
`fixtures/csv/alvera_reviews_cahps_appointments_batch1.csv` — 3 rows.
Use it, or you have a CSV?

**User:** Reference.

**Skill:** Handing to `/DAC-upload` bulk. *(uploads, polls — bulk is
slower, ~25s)*. ✅ batch landed; 3 appointments + 3 patients
ingested.

---

### Phase 10 — standard-workflow

**Skill:** Workflow time. Canonical example: review SMS after
appointments. Use the template, or a custom workflow?

**User:** Template.

**Skill:** Handing to `/agentic-workflow-creation` Review SMS path.
Need: source URI (use the DAC from phase 7 — `cahps-manual-recon`),
SMS body Liquid, dedup window. *(elicits, creates draft, dry-runs,
promotes to live)*. ✅ workflow active.

---

### Phase 11 — agent-driven-workflow

**Skill:** Last phase — AI-agent enrichment. The reference is a
"Contact Us triage" workflow that classifies inbound messages with
an LLM and routes to SMS / email / human. Need: an Ollama or OpenAI
endpoint, an LLM tool, an AI agent prompt, action mapping per
classification.

…handing to `/agentic-workflow-creation` custom-build path.
*(2 LLM tools created — happy URL + bad URL for error-path testing,
mirroring the reference spec; AI agent created; workflow with
3 action branches; dry-runs both happy and bad-URL paths to confirm
`error.json` carries `tool_execution_failed` for the bad URL)*. ✅
both workflows active.

---

### Wrap-up

**Skill:** All 11 phases done. Three things:

1. Run `pnpm test:healthcare` end-to-end as a regression check —
   should be 11/72 green.
2. `alvera-<tenant-slug>.yaml` is at `./alvera-<tenant-slug>.yaml` — under version control will
   give you a reproducible record of what was provisioned.
3. For row-level verification of the data that landed, invoke
   `/query-datasets` — it scaffolds a local PostgREST explorer.
   Data never enters chat.

Anything else, or wrap?

**User:** Wrap.

**Skill:** ✅ healthcare host setup complete.
