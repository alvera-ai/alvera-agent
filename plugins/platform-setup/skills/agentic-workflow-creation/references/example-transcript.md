# Reference transcripts

## Template-based: Review SMS workflow

```
USER: /agentic-workflow-creation I want to send review SMS after appointments

AGENT: [runs: alvera --profile default datalakes list]
       → [{"slug":"prime-medical-datalake"}]

       [runs in parallel:]
       [alvera tools list → {"id":"t-001","name":"Twilio SMS","intent":"sms"}]
       [alvera connected-apps list prime-medical-datalake
        → {"id":"ca-001","name":"Patient Portal","slug":"patient-portal"}]
       [alvera ai-agents list prime-medical-datalake → []]

       I have a **Review SMS Workflow** template for this. Let me
       customise it for you:

         - dataset_type: `appointment`
         - source filter: **what's your `source_uri`?** (e.g. emr.acme.com)
         - SMS delay: 3 hours after appointment (change?)
         - dedup window: 6 months (change?)
         - SMS tool: `Twilio SMS` (auto-detected)
         - connected app: `Patient Portal` — **form route?**
           (default: `/forms/review`)
         - SMS body: "How did we do on your recent visit to
           {{ location }}? We would love to hear from you at
           {{ connected_app_form_url }}" (customise?)
         - action window: none (add delivery hours?)

USER: source_uri is emr.acme-health.com, form route is /reviews,
      add action window 8am-8pm, rest is fine

AGENT: Creating workflow **Review SMS Workflow** (draft):
         - listens on: `appointment`
         - filter: source_uri = `emr.acme-health.com` + last 24h
         - decision: always → `send_appointment_review_sms`
         - action: SMS via Twilio SMS, 3h delay, 6-month dedup
         - connected app: Patient Portal → `/reviews`
         - delivery window: 8 AM - 8 PM
         - idempotency: patient_id + appointment_id + decision_key

       Proceed? (y/n)

USER: y

AGENT: [writes /tmp/workflow.json, chmod 600]
       [runs: alvera --profile default workflows create
              prime-medical-datalake --body-file /tmp/workflow.json]
       [rm /tmp/workflow.json]
       → slug: review-sms-workflow, id: wf-001

       Created **Review SMS Workflow** (draft). Running dry-run test...

       [runs: alvera --profile default workflows run review-sms-workflow
              --body '{"sql_where_clause":"1=1 LIMIT 1","mode":"dry_run"}']
       → enqueued_count: 1, batch_id: manual:abc123

       [runs: alvera --profile default workflows workflow-logs list
              review-sms-workflow]
       → status: completed, filter_result: true

       Dry-run passed:
         - Record entered the pipeline (filter: passed)
         - Action scheduled (3h after appointment start)
         - Runtime filter: passed (phone exists, no prior message,
           status is fulfilled)

       Ready to promote to live. This will make the workflow respond
       to new appointment events automatically. Promote? (y/n)

USER: y

AGENT: [reads workflow, updates status to "live"]
       [runs: alvera --profile default workflows update
              prime-medical-datalake wf-001
              --body-file /tmp/workflow-live.json]
       → status: live

       **Review SMS Workflow** is now live. It will automatically
       process new appointments from `emr.acme-health.com`.

       To monitor: `alvera workflows workflow-logs list review-sms-workflow`
```

## Custom build: REST API action workflow

```
USER: /agentic-workflow-creation I need a workflow that calls our
      internal API when a new patient is ingested

AGENT: [resolves datalake: prime-medical-datalake]
       [auto-detects: tools → {"id":"t-002","name":"Internal API",
        "intent":"data_exchange"}]

       Building a custom workflow. Let me walk through the setup:

       **Pass 1 — Identity:**
         - name: **what should this workflow be called?**
         - dataset_type: `patient` (since you said "new patient")
         - description: (optional)

USER: "Patient Sync Webhook", patient, "Notify internal systems
      when a new patient is ingested"

AGENT: **Pass 2 — Filter (optional):**
       Do you want to filter which patients enter the workflow?
       Common options:
         - Source URI gate (only patients from a specific EMR)
         - Recency (only patients ingested in last 24h)
         - No filter (all patients)

USER: no filter, process all

AGENT: **Pass 3 — Action:**
       One action: call your Internal API tool.
         - decision_key: `notify_internal_system`
         - action_type: `data_exchange` (REST API)
         - tool: Internal API (auto-detected)
         - When should it fire? (`now`, or a delay?)
         - What endpoint/method? (e.g. POST /webhooks/patient-sync)

USER: fire immediately, POST /webhooks/patient-sync

AGENT: What should the request body contain? I can use patient data
       from the pipeline. For example:
       ```
       {"patient_id": "{{ mdm_output.patient.id }}",
        "mrn": "{{ mdm_output.regulated_patient.identifier[0].value }}",
        "event": "patient_created"}
       ```

USER: yes that works, add first_name and last_name too

AGENT: Creating workflow **Patient Sync Webhook** (draft):
         - listens on: `patient`
         - filter: none (all patients)
         - decision: always → `notify_internal_system`
         - action: POST /webhooks/patient-sync via Internal API,
           fires immediately
         - idempotency: patient_id + decision_key

       Proceed? (y/n)

USER: y

AGENT: [creates workflow in draft]
       [auto dry-run]
       [checks logs]

       Created and tested. Dry-run passed — action scheduled
       immediately for the test patient record.

       Promote to live? (y/n)
```

## Debugging: workflow filters out all records

```
USER: my workflow isn't processing any appointments

AGENT: Let me check. What's the workflow slug?

USER: review-sms-workflow

AGENT: [runs: alvera --profile default workflows workflow-logs list
              review-sms-workflow]
       → last 5 logs all show status: "filtered"

       All recent records were filtered out. Let me run one manually
       to see why:

       [runs: alvera --profile default workflows run review-sms-workflow
              --body '{"sql_where_clause":"1=1 LIMIT 1","mode":"dry_run",
              "manual_override":true}']
       [runs: alvera --profile default workflows workflow-logs list
              review-sms-workflow]
       → status: filtered, filter_expression: ""
         (filter output was empty — not "true")

       The filter returned empty (not "true"), which means the record
       was rejected. Looking at the filter_config:

       ```
       {% if appointment.source_uri == "emr.old-system.com" %}...
       ```

       The `source_uri` in your filter is `emr.old-system.com`, but
       your appointments probably come from a different source. What
       source_uri do your appointments have?

USER: they're from emr.acme-health.com

AGENT: That's the issue — the filter is checking for
       `emr.old-system.com`. Want me to update it to
       `emr.acme-health.com`? (y/n)

USER: y

AGENT: [reads current workflow, updates filter, PUTs full body]
       [re-runs dry-run test]
       → status: completed

       Fixed. The workflow now processes appointments from
       `emr.acme-health.com`. Dry-run passed.
```

## Notes on style

- **Templates first.** When the use case matches a template, propose
  it with customisation points — don't start from scratch.
- **Dry-run is automatic.** Always run after create, don't ask.
- **Plain-language results.** Don't dump raw log JSON — interpret the
  status and say what it means.
- **Confirm before live.** Draft → dry-run → confirm → live. Never
  skip to live.
- **One workflow per invocation.** After creation, ask "another
  workflow, or done?"
- **Connected apps are optional.** Don't require them — many workflows
  send plain SMS without magic links.
