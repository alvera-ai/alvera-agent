# Outcome catalog

Maps business outcomes to resource dependency chains. The skill matches
user intent to one of these patterns, derives the chain, then gap-analyses
against existing resources.

## Data direction rule

When deriving chains, classify each action by data direction:

- **Data IN** (ingest, record, sync, store) → **DAC**
- **Data OUT** (send, notify, trigger, push) → **Agentic Workflow**

**Escape hatch — when the 80% rule breaks:**

Ask: "Does this action *write* data somewhere, or does it *send/trigger*
something?" If it writes → DAC regardless of how the user phrased it.

Common traps:
- "Record patient responses to SMS" → sounds like workflow, but it's
  writing response data → **DAC**
- "Sync reviews to a table" → writing → **DAC**
- "Push a notification" → sending → **Workflow**
- "Log a webhook payload" → writing → **DAC**

When ambiguous, ask: "Will this create rows in a table, or trigger an
external action (SMS, API call, email)?"

## How to read the chains

Each chain lists resources in **provisioning order** (create first → last).
The skill creates them left-to-right.

`→` means "then create". Resources to the left must exist before the
resource to the right can be created.

---

## Outcome 1: Send SMS after appointments

**Triggers:** "review SMS", "appointment SMS", "send SMS after", "review text",
"post-visit SMS", "survey SMS"

**Chain:**
```
datalake → data source → SMS tool → agentic workflow
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
datalake → tool → data source → generic table → interop contract → DAC (ingest)
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
datalake → data source → tool → AI agent
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
datalake → data source → [AI agents for enrichment] → [tools needed by actions] → agentic workflow
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
datalake → connected app
```

**May also need:** SMS tool (if the app sends SMS via workflows),
agentic workflow (if the app is used as a connected_app target in actions).

---

## Outcome 6: Push data from external system

**Triggers:** "data activation", "DAC", "pull from API", "fetch from S3",
"sync from external"

**Chain:**
```
datalake → data source → tool (with external config) → DAC
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
datalake → data source → tool → action status updater
```

---

## Outcome 9: Raw resource creation

**Triggers:** "create a data source", "add a tool", "create datalake",
or any direct resource name

**Chain:**
```
datalake → [dependencies] → [named resource]
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
  datalake → data source → SMS tool → connected app (for confirmation link)
  → agentic workflow (two actions: confirmation + reminder)
```

Present the derived plan and ask the user to confirm.
