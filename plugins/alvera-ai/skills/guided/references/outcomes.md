# Outcome catalog

Maps business outcomes to resource dependency chains. The skill matches
user intent to one of these patterns, derives the chain, then gap-analyses
against existing resources.

## Data direction rule

When deriving chains, classify each action by data direction:

- **Data IN** (ingest, record, sync, store) → **DAC**
- **Data OUT** (send, notify, trigger, push) → **Agentic Workflow**

This holds ~80% of the time. Agentic workflows only send — they don't
store or ingest. "Record responses" is ingestion, not output.

## How to read the chains

Each chain lists resources in **dependency order** (leaves first). The skill
provisions them bottom-up but the design is top-down — the user only sees
the goal.

`→` means "depends on". Resources to the right must exist before the
resource to the left can be created.

---

## Outcome 1: Send SMS after appointments

**Triggers:** "review SMS", "appointment SMS", "send SMS after", "review text",
"post-visit SMS", "survey SMS"

**Chain:**
```
agentic workflow → SMS tool → data source → datalake
```

**Defaults:**
- Tool `intent`: `sms`
- Workflow `dataset_type`: `appointment`
- Filter: source_uri gate + recency + status guard
- Action: SMS with configurable delay

**Workflow path:** Use `references/workflows.md` → Template A (Review SMS)

**If SMS tool exists but no workflow:** only create workflow.
**If neither exists:** create tool first, then workflow.

---

## Outcome 2: Onboard data from a file

**Triggers:** "upload CSV", "ingest data", "push file", "load patients from",
"import data from file", "onboard table from CSV"

**Chain:**
```
DAC (ingest) → interop contract → generic table → data source → tool → datalake
```

**Sub-flow:** Follow `references/data-pipeline.md` for the full
compliance gate → profile → create table → anti-pattern scan → template →
sandbox test → upload flow.

**If generic table already exists:** skip to interop contract + upload.
**If DAC already exists:** check its contract, validate against file columns.

---

## Outcome 3: Create an AI agent

**Triggers:** "AI agent", "create agent", "set up agent for", "agent to triage",
"agent for classification"

**Chain:**
```
AI agent → tool → data source → datalake
```

**Defaults:**
- Tool `intent`: `data_exchange` (unless user specifies SMS/email)
- Agent `data_access`: ask explicitly (security concern)

---

## Outcome 4: Build an automation / workflow

**Triggers:** "workflow", "automation", "build a workflow", "event-driven",
"trigger when", "automate X", "create workflow"

**Chain (depends on actions):**
```
agentic workflow → [tools needed by actions] → [AI agents for enrichment] → data source → datalake
```

**Workflow path:** Use `references/workflows.md` — template selection
or custom build.

If the user describes a standard pattern (review SMS, survey), match to
Template A or B. Otherwise, build custom via elicitation passes.

---

## Outcome 5: Set up a connected app

**Triggers:** "connected app", "patient portal", "hosted app", "magic link",
"forms app"

**Chain:**
```
connected app → datalake
```

**May also need:** SMS tool (if the app sends SMS via workflows),
agentic workflow (if the app is used as a connected_app target in actions).

---

## Outcome 6: Push data from external system

**Triggers:** "data activation", "DAC", "pull from API", "fetch from S3",
"sync from external"

**Chain:**
```
DAC → tool (with external config) → data source → datalake
```

**May also need:** interop contract (if source schema differs from target),
generic table (if storing custom data).

---

## Outcome 7: Query / verify data

**Triggers:** "query table", "see rows", "verify data", "explore table",
"check if data loaded"

**Chain:**
```
datasets search — no platform resources needed (read-only)
```

**Sub-flow:** Follow `references/query.md` — uses `alvera datasets search`
to inspect data. Paginate results, summarize structure.

---

## Outcome 8: Status tracking / polling

**Triggers:** "status updater", "track status", "poll for updates",
"check appointment status"

**Chain:**
```
action status updater → tool → data source → datalake
```

---

## Outcome 9: Raw resource creation

**Triggers:** "create a data source", "add a tool", "create datalake",
or any direct resource name

**Chain:**
```
[named resource] → [its dependencies] → datalake
```

Treat as a minimal chain. Look up the resource's dependencies in
`references/resources.md` and ensure they exist.

---

## Fallback: free-form

If the user's description doesn't match any pattern:

1. Parse the intent — what data is involved? What should happen?
2. Identify the most complex resource in the likely chain (usually a
   workflow or DAC).
3. Work backwards from that resource to its dependencies.
4. Present the derived plan and ask the user to confirm or adjust.

Example:
```
User: "I want patients to get an SMS when their appointment is confirmed,
      and if they don't confirm within 2 hours, send a reminder."

Derived chain:
  agentic workflow (two actions: confirmation + reminder)
  → SMS tool → data source → datalake
  → connected app (for confirmation link) → datalake
```

Present the derived plan and ask the user to confirm.
