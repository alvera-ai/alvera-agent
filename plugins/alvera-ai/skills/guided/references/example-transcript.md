# Reference transcripts

End-to-end conversations demonstrating the top-down, outcome-driven flow.

## Transcript 1: "Send review SMS after appointments"

```
USER: I want to set up review SMS after appointments on Alvera.

AGENT: Before we start, I need:
  1. Profile name — default `default`
  2. Tenant slug
  3. Base URL — default https://admin.alvera.ai

USER: defaults for everything, tenant=acme

AGENT: [runs: alvera --profile default whoami]
       → hasSessionToken: false.

       Run this in your own terminal:

         alvera --profile default login \
           --base-url https://admin.alvera.ai \
           --tenant acme \
           --email <your-email>

       Tell me when you're done.

USER: done.

AGENT: [runs: alvera --profile default whoami]
       → session valid.
       [runs: alvera --profile default ping]
       → ok.
       [runs: alvera --profile default datalakes list acme]
       → 1 datalake: `acme-health`

       Using datalake `acme-health`.

       To achieve **review SMS after appointments**, I need:
         ✓ Datalake `acme-health` — exists
         → Data source (for the appointment feed)
         → SMS tool (to send messages)
         → Review SMS workflow

       Let me check what exists:
       [runs: alvera --profile default data-sources list acme-health acme]
       → 1 data source: `acme-emr` (uri: our-emr:acme, active, primary)
       [runs: alvera --profile default tools list acme]
       → 1 tool: `Acme Manual Upload` (data_exchange) — no SMS tool

       Gap analysis:
         ✓ Datalake `acme-health` — exists
         ✓ Data source `acme-emr` — exists
         ✗ SMS tool — missing
         ✗ Review SMS workflow — missing

       I'll create in this order:
         1. SMS tool (depends on: data source ✓)
         2. Review SMS workflow (depends on: SMS tool ✓, data source ✓)
       Proceed? (y/n)

USER: y

AGENT: Creating **SMS tool** attached to data source `acme-emr`:
         - name: Acme SMS
         - intent: sms
         - status: active
         - kind: sns
       I need AWS region and auth for the SMS tool.
       Do you have env vars for the AWS credentials, or should I scaffold
       an env file?

USER: env vars: AWS_REGION, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY,
      and assume role arn is in ASSUME_ROLE_ARN

AGENT: [runs: alvera --profile default tools create acme --body-file /tmp/tool.json]
       Created tool **Acme SMS** (id: 9b2e-...).
       Appended to alvera-<tenant-slug>.yaml.

       Now building the **Review SMS Workflow**.

       Template: Review SMS (production-grade).
       Customisation:
         - source_uri: `our-emr:acme` (from data source) — correct?
         - SMS delay: 3 hours after appointment — change?
         - Dedup window: 6 months — change?
         - SMS body: "How was your visit? Leave a review: {{ connected_app_form_url }}"
           — customise?
         - Connected app: none found. Skip, or create one?

USER: source_uri is fine. Make it 2 hours. Keep 6-month dedup. SMS body
      is fine. No connected app for now.

AGENT: Creating workflow **Review SMS Workflow** (draft):
         - listens on: `appointment`
         - filter: source_uri = our-emr:acme + last 24h
         - decision: always → `send_appointment_review_sms`
         - action: SMS via Acme SMS, 2h delay, 6-month dedup
         - no connected app
       Proceed? (y/n)

USER: y

AGENT: [runs: alvera --profile default workflows create acme-health acme
              --body-file /tmp/workflow.json]
       Created workflow **Review SMS Workflow** (slug: review-sms-workflow, status: draft).
       Appended to alvera-<tenant-slug>.yaml.

       Running dry-run test...
       [runs: alvera --profile default workflows run review-sms-workflow acme
              --body '{"sql_where_clause":"1=1 LIMIT 1","mode":"dry_run"}']
       → enqueued_count: 1

       [runs: alvera --profile default workflows workflow-logs review-sms-workflow acme]
       → status: completed. All actions passed.

       Dry-run passed. Promote to live? (y/n)

USER: y

AGENT: [runs: alvera --profile default workflows update acme-health <id> acme
              --body-file /tmp/workflow-live.json]
       Workflow **Review SMS Workflow** is now live.

       Done — review SMS workflow is live. What else do you want to achieve?
```

## Transcript 2: "Onboard patient data from CSV"

```
USER: I need to onboard patient data from a CSV file.

AGENT: To onboard data from a file, I need:
  - The file path (CSV or NDJSON)
  - Whether to create a new table or upload to an existing one

What's the file path?

USER: ./patients.csv — new table

AGENT: Is this sample file **(a) dummy / synthetic**, **(b) real data
       you're OK sharing with me**, or **(c) real data I must not see**
       (PHI / PII under HIPAA, or covered by a BAA)?

USER: (a) — it's synthetic test data.

AGENT: [reads ./patients.csv, profiles first 1000 rows]

       Proposed table **patients** (domain healthcare, 1247 rows):

         - patient_id  (string, required, unique, tokenize) — "Patient identifier"
         - first_name  (string, required, redact_only)      — "First name"
         - last_name   (string, required, redact_only)      — "Last name"
         - dob         (date,   required, redact_only)      — "Date of birth"
           ⚠ Source format: **MM/DD/YY** — stored as YYYY-MM-DD
         - gender      (string, required, none)             — "Gender"
         - email       (string, optional, redact_only)      — "Contact email"
         - phone       (string, optional, redact_only)      — "Phone number"
         - active      (boolean, required, none)            — "Active status"

       Notes:
         - `privacy_requirement` is locked at creation — review now.
         - `dob` has dates in MM/DD/YY — the interop template will convert.
         - Only `patient_id` is unique → single-column key.

       Proceed with table creation? (y/n)

USER: y

AGENT: [runs: alvera generic-tables list acme-health acme] No collision.
       [creates table]
       Created generic table **patients** (id: 7f3a-...).
       Appended to alvera-<tenant-slug>.yaml.

       Now I'll set up the data pipeline to upload the file.
       Anti-pattern scan results:
         - `dob`: MM/DD/YY → will convert to YYYY-MM-DD in template
         - `gender`: values are capitalised → will `| downcase`

       Mapping source columns → patient FHIR fields:
         patient_id → identifier[0]     system: urn:our-emr:acme
         first_name → name[0].given[0]  —
         last_name  → name[0].family    —
         dob        → birth_date        MM/DD/YY → YYYY-MM-DD
         gender     → gender            | downcase
         phone      → telecom[0]        system: phone
         email      → telecom[1]        system: email

       Proceed with interop contract + upload? (y/n)

USER: y

AGENT: [creates interop contract]
       [sandbox test — passed]
       [creates DAC]
       [uploads file via presigned URL]
       [triggers ingest]

       Uploaded and queued.
         - batch_id: 550e8400-...
         - jobs_count: 1

       Processing runs async. To verify rows landed, I can scaffold
       a PostgREST explorer.

       What else do you want to achieve?
```

## Notes on style

- **Outcome-first.** User says what they want, skill derives the plan.
- **Gap analysis before execution.** Show what exists vs what's missing.
- **Execute in dependency order.** Bottom-up provisioning.
- **Plain-language confirmations.** Bullets, not JSON.
- **Proactive defaults.** Don't ask when one path is obvious.
- **Confirm once.** Don't re-confirm after user says yes.
- **Report IDs and file updates.** Always surface the create result.
- **Loop with outcome prompt.** "What else do you want to achieve?"
