---
name: agentic-workflow-creation
description: >
  Create, test, and validate agentic workflows on an Alvera datalake.
  Offers production-grade templates (review SMS, age-aware survey) that
  can be customised conversationally, or builds a workflow from scratch
  via guided elicitation. Auto-detects available tools, AI agents, and
  connected apps. Creates in draft, auto-runs a dry-run test, interprets
  execution logs, and offers to promote to live. Drives the `alvera`
  CLI. Use when the user says "create a workflow", "set up an SMS
  workflow", "build an automation", "add a review workflow", or similar.
  For simple one-off workflow creation as part of a broader setup
  session, `guided` can handle it — this skill is for production-grade
  workflows with filters, scheduling, idempotency, and connected apps.
---

# Agentic workflow creation

Build, test, and validate event-driven automation workflows. The user
describes what they want; the skill proposes a template or builds
from scratch, creates in draft, dry-runs against a real record, and
promotes to live when validated.

```
use case → template or custom build → create (draft)
  → dry-run test → interpret logs → promote to live
```

## Prerequisites

- `alvera` CLI reachable, active session. If not, route to `guided`.
- **Datalake** — workflows are datalake-scoped.
- **At least one tool** — workflows execute actions through tools
  (SMS, REST API, etc.). A tool with the right action type must exist.
- **AI agents** (optional) — for enrichment before the decision stage.
- **Connected apps** (optional) — for magic-link URLs in SMS/email.
- **Data in the datalake** — dry-run testing requires at least one
  record of the target `dataset_type` (appointment, patient, etc.).

## Workflow

1. **Resolve datalake** — `alvera datalakes list [tenant]`. Same
   disambiguation rules as other skills.

2. **Understand the use case.** Ask what the workflow should do:

   > "What should this workflow automate? For example:
   >   - Send a review SMS after appointments
   >   - Send an age-aware survey to patients 65+
   >   - Trigger a REST API call when new patients are ingested
   >   - Something custom
   >
   > I have production-grade templates for the first two — just pick
   > one and customise, or describe what you need."

   Match to a template if possible (see `references/templates.md`).
   Otherwise, build from scratch via elicitation.

3. **Auto-detect available resources.** Run in parallel:

   ```bash
   alvera --profile <p> tools list [tenant]
   alvera --profile <p> ai-agents list <datalake> [tenant]
   alvera --profile <p> connected-apps list <datalake> [tenant]
   ```

   Surface what's available. If a required resource is missing (e.g.
   no SMS tool for a review workflow), hand off to `guided`.

4. **Build the workflow** — two paths:

   **4a — Template-based.** Load the template from
   `references/templates.md`. Present the customisation points as a
   compact checklist:

   > Template: **Review SMS Workflow**
   >   - dataset_type: `appointment` (change?)
   >   - source filter: `emr.my-practice.com` → **what's your source_uri?**
   >   - SMS delay: 3 hours after appointment → **change?**
   >   - dedup window: 6 months → **change?**
   >   - SMS tool: `<auto-detected>` → **confirm**
   >   - connected app: `<auto-detected or none>` → **confirm**
   >   - SMS body: "How did we do..." → **customise?**
   >   - action window: none → **add delivery hours?**

   Fill in answers, generate the full workflow body.

   **4b — Custom build.** Elicit in passes (same structure as
   `guided/references/resources.md` → Agentic Workflow, but more
   hands-off):

   - **Pass 1 — identity**: name, description, dataset_type,
     generic_table_id (if generic_table), status (default `draft`)
   - **Pass 2 — filter** (optional): ask what records should enter
     the workflow. Offer common patterns (source_uri gate, recency
     gate, age gate). Generate the Liquid template.
   - **Pass 3 — decision**: for simple workflows, auto-generate a
     static decision config that outputs one key. For multi-action
     workflows, ask what determines which action fires.
   - **Pass 4 — context datasets** (optional): ask if additional
     data is needed before the decision (e.g. prior messages for
     dedup). Generate where_clause.
   - **Pass 5 — actions**: walk through each action. For each:
     - decision_key, action_type, tool (auto-detect), position
     - trigger_template (when: now, delay, scheduled)
     - idempotency_template (dedup key)
     - runtime_filter (per-action guards: phone exists, status check)
     - tool_call (SMS body, REST endpoint, etc.)
     - connected app integration (optional)
     - action_window (optional delivery hours)
   - **Pass 6 — AI agents** (optional): attach agents for enrichment

5. **Confirm.** Plain-language recap — not JSON:

   > Creating workflow **Review SMS Workflow** (draft):
   >   - listens on: `appointment`
   >   - filter: source_uri = emr.my-practice.com + last 24h
   >   - decision: always → `send_appointment_review_sms`
   >   - action: SMS via `Acme SMS Tool`, 3h delay, 6-month dedup
   >   - connected app: `Acme Portal` (review form)
   >
   > Proceed? (y/n)

6. **Create in draft.**

   ```bash
   alvera --profile <p> workflows create <datalake> [tenant] \
     --body-file /tmp/workflow.json
   ```

   Report the slug. Always start as `draft` — never auto-promote.

7. **Auto dry-run test.** After creation, immediately run a test:

   ```bash
   # Get workflow metadata to understand available variables
   alvera --profile <p> workflows metadata <datalake> <id> [tenant]

   # Dry-run against a single record
   alvera --profile <p> workflows run <slug> [tenant] \
     --body '{"sql_where_clause":"1=1 LIMIT 1","mode":"dry_run"}'
   ```

   Or if the user has a specific record:
   ```bash
   alvera --profile <p> workflows execute <slug> [tenant] \
     --body '{"dataset_id":"<uuid>","decision_key":"<key>","mode":"dry_run"}'
   ```

8. **Interpret logs.** Check execution results:

   ```bash
   alvera --profile <p> workflows workflow-logs list <slug> [tenant]
   ```

   Surface the result in plain language:

   | Log status | Meaning | Next step |
   |------------|---------|-----------|
   | `completed` | Full pipeline passed | Ready to promote |
   | `filtered` | filter_config rejected the record | Check filter logic or pick a different test record |
   | `failed` | Execution error | Surface error_message, fix template |
   | `partial` | Some actions ok, some failed | Check individual action logs |

   For action-level issues, check the nested action execution logs
   (see `references/execution.md`).

9. **Promote to live** (on user confirmation):

   ```bash
   alvera --profile <p> workflows update <datalake> <id> [tenant] \
     --body-file /tmp/workflow-live.json
   ```

   Change `status` from `draft` to `live`. Confirm before doing this:
   > "This will make the workflow respond to automated events (new
   > appointments, patient updates, etc.). Promote to live? (y/n)"

10. **Append to `infra.yaml`** under `agentic_workflows:`.

## Stance: be proactive

- Default to templates when they fit. Don't force custom elicitation
  for standard use cases.
- Auto-detect tools, AI agents, connected apps — don't ask the user
  to look up IDs.
- Auto-run dry-run test after creation — don't ask if they want one.
- When the test passes, immediately offer promotion to live.
- For simple workflows (one action, no filter), collapse the passes
  into a single prompt.

## Hard constraints

- **Always create in draft first.** Never auto-promote to live. The
  user must explicitly confirm after seeing dry-run results.
- **Dry-run before live.** Always test before promoting. `mode:
  "dry_run"` runs the full pipeline without making external tool calls.
- **Confirm before live execution.** `live` mode fires real SMS/API
  calls. Always confirm: "This will send real SMS messages. Proceed?"
- **Idempotency is non-negotiable.** Every action must have an
  `idempotency_template`. If the user tries to skip it, explain: "Without
  idempotency, the same patient could receive duplicate messages.
  At minimum, use `{{ patient_id }}-{{ decision_key }}`."
- **Filter semantics: `true` = proceed.** The filter outputs `"true"`
  to let a record through. Empty/nil/false = filtered out. This is the
  opposite intuition from "filter = skip" — state it clearly.
- **Runtime filter semantics: `true` = execute.** Same as filter — the
  runtime_filter outputs `"true"` to execute the action. Clarify this
  when building actions.
- **Don't hardcode phone numbers.** Template SMS `to` fields should use
  `{{ mdm_output.regulated_patient.telecom | where: "system", "phone"
  | map: "value" | first }}` — not literal numbers.
- **Connected app URLs are magic links.** The `{{ connected_app_form_url }}`
  variable is auto-generated by the platform when `connected_app_id` +
  `connected_app_route` are set. Don't construct URLs manually.
- **PUT = full replace.** Updates require the complete workflow body,
  not patches. Always read-before-write.

## References

- `references/templates.md` — production-grade workflow presets
- `references/liquid-variables.md` — variables available at each stage
- `references/execution.md` — execute, run-workflow, logs, debugging
- `references/example-transcript.md` — reference dialogs

## Downstream

After a workflow is live and processing, the user may want:
- `guided` → create additional tools, AI agents, or connected apps
- `/query-datasets` → verify records are being processed correctly
