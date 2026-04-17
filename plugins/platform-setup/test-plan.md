# End-to-end test plan

Validate all five skills in a single flow — from empty tenant to
queried data. Uses the `alvera` CLI throughout. Each phase maps to a
skill; the test proves the hand-offs work.

## Prerequisites

- `alvera` CLI installed (`npx -p @alvera-ai/platform-sdk alvera --version`)
- A tenant with valid credentials (`alvera login`)
- Local platform running or access to staging
- Python 3 available (for profiler scripts)
- Node.js available (for query-datasets scaffold)

---

## Phase 1 — Datalake + foundational resources (`/guided`)

**Goal:** Stand up a datalake and the minimum resources every
downstream skill needs.

### 1.1 Create or select datalake

```
/guided
→ profile=default, tenant=<your-tenant>
→ "Use existing datalake or create new?"
→ Create new: name "Test Datalake", domain healthcare, provide DB creds
```

Record the datalake slug (e.g. `test-datalake`).

### 1.2 Create two data sources

| # | Name | URI | Description |
|---|------|-----|-------------|
| 1 | Dummy EMR | `dummy-emr:test` | Simulated EMR system (patients, appointments) |
| 2 | Dummy Website | `dummy-web:test` | Simulated patient portal (reviews, contact-us, medicare) |

### 1.3 Create two tools (intent: `data_exchange`)

| # | Name | Data Source | Intent |
|---|------|-------------|--------|
| 1 | EMR Manual Upload | Dummy EMR | `data_exchange` |
| 2 | Website Manual Upload | Dummy Website | `data_exchange` |

### 1.4 Create two AI agents

| # | Name | Purpose |
|---|------|---------|
| 1 | EMR Ingestion Agent | Process patient and appointment data from dummy EMR |
| 2 | Website Ingestion Agent | Process reviews, feedback, contact-us, and medicare from dummy website |

**Verify:** `alvera ai-agents list <datalake>` returns both agents.

---

## Phase 2 — Define the 6 tables (`/custom-dataset-creation`)

**Goal:** Create generic tables from sample CSV files. Test the
compliance gate, profiler (including ID-as-string detection and
non-ISO date detection), and schema proposal.

Prepare 6 sample CSVs with 10-20 rows each:

### 2.1 Patient table

```csv
patient_id,first_name,last_name,dob,gender,phone,email,mrn,source_uri
1001,Jane,Doe,03/15/1960,Female,+15551234567,jane@example.com,MRN-001,dummy-emr:test
```

**What to verify:**
- `patient_id` and `mrn` flagged as `looks_like_id` → defaulted to `string`
- `dob` detected as `MM/DD/YYYY` → type `date` with `needs_interop_conversion: true`
- `gender` noted for downcase in hand-off
- `phone`, `email`, `dob` flagged as `looks_sensitive`

```
/custom-dataset-creation ./samples/patients.csv
→ compliance: (a) dummy data
→ confirm schema, proceed
```

### 2.2 Appointment table

```csv
appt_id,patient_mrn,appt_date,appt_time,duration,appt_status,visit_type,provider_name,source_uri
APT-001,MRN-001,04/18/2026,09:30,30,Scheduled,Annual Checkup,Dr. Smith,dummy-emr:test
```

**What to verify:**
- `appt_date` detected as `MM/DD/YYYY` → `needs_interop_conversion`
- `appt_status` unique values: Scheduled, Completed, Cancelled, No-Show
- `appt_id` stays `string` (not numeric)

### 2.3 Patient reviews table

```csv
review_id,patient_mrn,appt_id,rating,review_text,submitted_at,source_uri
REV-001,MRN-001,APT-001,5,Great experience,2026-04-18T10:00:00Z,dummy-web:test
```

### 2.4 CAHPS feedback table

```csv
feedback_id,patient_mrn,survey_type,question_code,response_value,submitted_at,source_uri
FB-001,MRN-001,CAHPS,Q1,9,2026-04-18T10:30:00Z,dummy-web:test
```

### 2.5 Contact-us submissions table

```csv
submission_id,patient_mrn,subject,message,contact_method,submitted_at,source_uri
SUB-001,MRN-001,Billing Question,I have a question about my bill,email,2026-04-18T11:00:00Z,dummy-web:test
```

### 2.6 Medicare eligibility table

```csv
eligibility_id,patient_mrn,plan_name,plan_id,effective_date,termination_date,status,source_uri
ELIG-001,MRN-001,Medicare Part A,PLAN-A,01/01/2026,12/31/2026,active,dummy-web:test
```

**What to verify:**
- `effective_date` and `termination_date` detected as `MM/DD/YYYY`
- `plan_id` and `eligibility_id` defaulted to `string`

**After all 6:** `alvera generic-tables list <datalake>` returns all 6.
Check `infra.yaml` has all entries under `generic_tables:`.

---

## Phase 3 — Interop contracts + DAC for patient & appointment (`/DAC-upload`)

**Goal:** Create interop contracts with Liquid templates that transform
the dummy EMR data into FHIR format, auto-detect anti-patterns, sandbox
test, then upload.

### 3.1 Upload patients.csv

```
/DAC-upload ./samples/patients.csv
```

**Expected automated flow:**
1. Datalake auto-resolved
2. No DAC exists → skill offers to create one
3. Tool auto-detected: `EMR Manual Upload`
4. Data source auto-detected: `Dummy EMR`
5. Headers read: `patient_id,first_name,last_name,dob,gender,...`
6. Anti-pattern scan:
   - `dob`: `MM/DD/YYYY` → needs conversion
   - `gender`: `Female`, `Male` → needs `| downcase`
7. Resource type: `patient`
8. Interop contract auto-generated with Liquid template:
   - `patient_id` → `identifier[0].value` (system: `urn:dummy-emr:test`)
   - `dob` → `birth_date` with `MM/DD/YYYY → YYYY-MM-DD` conversion
   - `gender` → `gender | downcase`
9. Sandbox test: first row piped through `interop run` → verify `transformed` output
10. DAC created: `emr-patient-ingest`
11. Three-step upload: upload-link → curl PUT → ingest-file
12. Result: `batch_id`, `jobs_count: 1`

**Verify:**
- `alvera interop list <datalake>` shows the patient contract
- `alvera data-activation-clients list <datalake>` shows the DAC
- `alvera data-activation-clients logs <datalake> <dac-slug>` shows processing log

### 3.2 Upload appointments.csv

```
/DAC-upload ./samples/appointments.csv
```

**Expected:**
- New interop contract for `appointment` resource type
- Status mapping: Scheduled → booked, Completed → fulfilled, etc.
- `appt_date` conversion: MM/DD/YYYY → YYYY-MM-DD
- MDM input: resolves patient by `patient_mrn`
- New DAC or reuse existing (user's choice)
- Sandbox test passes
- Upload succeeds

### 3.3 Upload remaining 4 files

For the 4 generic tables (reviews, CAHPS, contact-us, medicare), these
use `dataset_type: generic_table` in the interop contract rather than
FHIR resource types. The skill should detect this and handle accordingly.

Each upload:
1. Auto-resolve DAC (create new or reuse)
2. Interop contract with `identity` type (data is already in target format)
   or `custom` if columns need mapping
3. Sandbox test
4. Upload

---

## Phase 4 — Agentic workflow (`/agentic-workflow-creation`)

**Goal:** Create a workflow that fires after appointment processing.

### 4.1 Review SMS workflow (template-based)

```
/agentic-workflow-creation
→ "Send a review SMS after appointments"
→ Template: Review SMS Workflow
→ Customise:
    - source_uri: dummy-emr:test
    - SMS tool: EMR Manual Upload (or create an SMS tool if needed)
    - No connected app (plain SMS)
    - SMS body: "Thank you for visiting. How was your experience?"
    - Delay: 1 hour (for testing, not 3h)
```

**Expected:**
1. Workflow created in `draft`
2. Auto dry-run: `mode: dry_run` against one appointment
3. Check workflow-logs → status: `completed` (or `filtered` if filter
   rejects the test record — adjust `source_uri`)
4. Promote to `live` on confirmation

**Verify:**
- `alvera workflows list <datalake>` shows the workflow
- `alvera workflows workflow-logs <workflow-slug>` shows dry-run log with
  `status: completed`

### 4.2 Custom workflow (optional stretch goal)

Create a second workflow using the custom build path:
- Dataset type: `patient`
- No filter (process all)
- Action: REST API call to a webhook (mock endpoint)
- Fire immediately
- Idempotency: `patient_id + decision_key`

---

## Phase 5 — Verify ingested data (`/query-datasets`)

**Goal:** Scaffold a React explorer and verify rows landed.

### 5.1 Set up PostgREST

Ensure PostgREST is running against the datalake's DB (see
`docker-compose.local.yml` for the `postgrest-prime` service config).

### 5.2 Scaffold and verify patient data

```
/query-datasets
→ PostgREST URL: http://localhost:3002
→ Schema: unregulated (or regulated, depending on table)
→ JWT secret: <from docker-compose>
→ Table: patients
```

**Expected:**
1. Scaffold created: `./patients-explorer/`
2. `npm install` runs
3. `npm run dev` starts → Vite URL printed
4. Open in browser → see patient rows with:
   - `birth_date` in YYYY-MM-DD format (converted by interop template)
   - `gender` in lowercase
   - All `patient_id` values as strings

### 5.3 Verify appointment data

Repeat for `appointments` table. Check:
- `status` values are FHIR-mapped (booked, fulfilled, etc.)
- `start` dates are in ISO format
- `patient_id` FK links to correct patients (MDM resolved)

### 5.4 Verify generic tables

Repeat for reviews, CAHPS, contact-us, medicare tables. These should
have the raw data as-is (identity interop) or transformed per the
contract.

---

## Pass/fail criteria

| # | Check | Pass condition |
|---|-------|---------------|
| 1 | Datalake created | `alvera datalakes list` returns it |
| 2 | 2 data sources created | `alvera data-sources list <dl>` returns 2 |
| 3 | 2 tools created | `alvera tools list` returns 2 with `data_exchange` |
| 4 | 2 AI agents created | `alvera ai-agents list <dl>` returns 2 |
| 5 | 6 generic tables created | `alvera generic-tables list <dl>` returns 6 |
| 6 | ID columns defaulted to string | Profiler shows `looks_like_id: true`, proposed type is `string` |
| 7 | Non-ISO dates detected | Profiler shows `needs_interop_conversion: true` for `dob`, `appt_date`, etc. |
| 8 | Patient interop contract created | `alvera interop list <dl>` shows patient contract with custom template |
| 9 | Appointment interop contract created | Same, with status mapping and MDM input |
| 10 | Sandbox tests pass | `interop run` returns `stage: completed` for both |
| 11 | DAC upload succeeds for patients | `ingest-file` returns `batch_id` + `jobs_count: 1` |
| 12 | DAC upload succeeds for appointments | Same |
| 13 | DAC logs show processed rows | `data-activation-clients logs` shows `rows_ingested > 0` |
| 14 | Workflow created in draft | `alvera workflows list <dl>` shows it |
| 15 | Workflow dry-run passes | `workflow-logs` shows `status: completed` |
| 16 | Query explorer works | Browser shows rows in the table with correct transforms |
| 17 | Patient birth_date is YYYY-MM-DD | Interop template correctly converted MM/DD/YYYY |
| 18 | Gender is lowercase | Interop template applied `\| downcase` |
| 19 | Appointment status is FHIR-mapped | booked/fulfilled/cancelled, not Scheduled/Completed/Cancelled |
| 20 | infra.yaml has all resources | Append-only receipt covers all created resources |

---

## Sample file generation

Create a `samples/` directory with the 6 CSV files. Each should have
10-20 rows with realistic dummy data. Include edge cases:

- **Dates:** mix MM/DD/YYYY and M/D/YYYY (no zero-padding)
- **Gender:** include Male, Female, Other, Unknown
- **Status:** include all appointment statuses (Scheduled, Completed,
  Cancelled, No-Show)
- **Nulls:** a few empty phone/email fields to test `is_required`
- **IDs:** all numeric to trigger `looks_like_id` detection
- **Duplicate MRNs:** same patient across appointments to test MDM
  idempotency (2 appointments for MRN-001)

---

## Execution order

```
Phase 1 (guided)           ← foundation: datalake, sources, tools, agents
  ↓
Phase 2 (custom-dataset)   ← define 6 table schemas from sample CSVs
  ↓
Phase 3 (DAC-upload)       ← interop templates + upload all 6 files
  ↓
Phase 4 (workflow)         ← create + dry-run review SMS workflow
  ↓
Phase 5 (query-datasets)   ← scaffold explorer, verify rows in browser
```

Each phase depends on the previous. If a phase fails, fix and re-run
from that phase — don't start over.
