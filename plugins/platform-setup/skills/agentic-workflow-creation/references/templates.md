# Workflow templates

Production-grade presets. Pick one, customise the marked fields, and
create. Each template includes all Liquid templates for filter,
decision, actions, and context datasets.

## Template A: Review SMS Workflow

**Use case:** After an appointment, send the patient an SMS asking for
a review of their visit. Includes a magic-link to a connected app form.

**Business rules baked in:**
- Source URI gate (only process appointments from a specific EMR)
- Recency gate (appointments within last 24h only)
- 6-month dedup (skip if patient already received a review SMS)
- Phone guard (skip if no phone on file)
- Status guard (only fulfilled/arrived/checked_in)
- 3-hour delay after appointment start
- Idempotency: one SMS per patient per appointment

### Customisation points

| Field | Default | What to ask |
|-------|---------|-------------|
| `source_uri` | `emr.my-practice.com` | "What's the `source_uri` for your appointments?" |
| SMS delay | 3 hours | "How long after the appointment should the SMS fire?" |
| Dedup window | 6 months | "How often can a patient receive a review SMS?" |
| SMS body | Generic review prompt | "What should the SMS say?" |
| Connected app route | `/forms/review` | "What's the form route in your connected app?" |
| Action window | None (anytime) | "Restrict delivery to certain hours? (e.g. 7 AM - 7 PM)" |

### Full body

```json
{
  "name": "Review SMS Workflow",
  "description": "Send review SMS after appointment, with recency + source_uri filter",
  "dataset_type": "appointment",
  "status": "draft",

  "filter_config": {
    "type": "custom",
    "body": "{% if appointment.source_uri == \"__SOURCE_URI__\" %}{% assign appt_date = appointment.start | date: \"%Y-%m-%d\" %}{% assign cutoff = \"\" | now | date: \"%Y-%m-%d\", \"subtract\", \"24 hours\" %}{% if appt_date >= cutoff %}true{% endif %}{% endif %}"
  },

  "decision_config": {
    "type": "custom",
    "body": "[\"send_appointment_review_sms\"]",
    "output_schema": {"type": "array", "items": {"type": "string"}}
  },

  "context_datasets": [
    {
      "dataset_type": "message",
      "where_clause": "rm.patient_id = '{{ patient_id }}' AND rm.decision_key = 'send_appointment_review_sms' AND rm.sent_at > NOW() - INTERVAL '__DEDUP_WINDOW__'",
      "limit": 1,
      "position": 0
    }
  ],

  "actions": [
    {
      "decision_key": "send_appointment_review_sms",
      "action_type": "sms",
      "tool_id": "__TOOL_ID__",
      "position": 0,

      "trigger_template": "{{ appointment.start | date: \"%Y-%m-%d %H:%M:%S\", \"add\", \"__DELAY__\", timezone }}",

      "idempotency_template": "{{ patient_id }}-{{ appointment.unregulated_appointment_id }}-{{ decision_key }}",

      "runtime_filter": "{% assign phone = mdm_output.regulated_patient.telecom | where: \"system\", \"phone\" | map: \"value\" | first %}{% if phone and phone != \"\" %}{% if additional_context.message.size == 0 %}{% if appointment.status == \"fulfilled\" or appointment.status == \"arrived\" or appointment.status == \"checked_in\" %}true{% endif %}{% endif %}{% endif %}",

      "connected_app_id": "__CONNECTED_APP_ID__",
      "connected_app_route": "__FORM_ROUTE__",
      "connected_app_metadata_template": "{\"appointment_uuid\":\"{{ appointment.unregulated_appointment_id }}\",\"patient_uuid\":\"{{ mdm_output.patient.id }}\",\"patient_identifier\":\"{{ mdm_output.regulated_patient.identifier[0].value }}\",\"first_name\":\"{{ mdm_output.regulated_patient.name[0].given[0] }}\",\"last_name\":\"{{ mdm_output.regulated_patient.name[0].family }}\",\"location_name\":\"{{ appointment.location_participants[0].location.name }}\"}",

      "tool_call": {
        "tool_call_type": "sms_request",
        "to": {"type": "custom", "body": "{{ mdm_output.regulated_patient.telecom | where: \"system\", \"phone\" | map: \"value\" | first }}"},
        "body": {"type": "custom", "body": "__SMS_BODY__"},
        "sms_type": "transactional"
      }
    }
  ]
}
```

Placeholders to replace: `__SOURCE_URI__`, `__DEDUP_WINDOW__`,
`__TOOL_ID__`, `__DELAY__`, `__CONNECTED_APP_ID__`, `__FORM_ROUTE__`,
`__SMS_BODY__`.

If no connected app, remove `connected_app_id`, `connected_app_route`,
`connected_app_metadata_template`, and any `{{ connected_app_form_url }}`
from the SMS body.

---

## Template B: Age-Aware Survey Workflow

**Use case:** Send an age-aware survey SMS to patients 65+ seven days
after their appointment. Includes delivery window and daily dedup.

**Additional rules vs Review SMS:**
- Age gate: patient must be >= 65 years old
- 7-day delay (after appointment end, not start)
- Delivery window: 7 AM - 7 PM (patient timezone)
- Daily dedup (one survey per patient per day)

### Customisation points

| Field | Default | What to ask |
|-------|---------|-------------|
| `source_uri` | `emr.my-practice.com` | Same as Review SMS |
| Age threshold | 65 | "Minimum patient age?" |
| Survey delay | 7 days | "How long after appointment should the survey fire?" |
| Action window | 7 AM - 7 PM | "Delivery hours?" |
| SMS body | Generic survey prompt | "What should the survey SMS say?" |
| Connected app route | `/forms/survey` | "What's the survey form route?" |

### Full body

```json
{
  "name": "Age-Aware Survey Workflow",
  "description": "Send age-aware survey to patients 65+ seven days after appointment",
  "dataset_type": "appointment",
  "status": "draft",

  "filter_config": {
    "type": "custom",
    "body": "{% if appointment.source_uri == \"__SOURCE_URI__\" %}{% assign patient_age = mdm_output.regulated_patient.birth_date | age %}{% if patient_age >= __AGE_THRESHOLD__ %}{% assign appt_date = appointment.start | date: \"%Y-%m-%d\" %}{% assign cutoff = \"\" | now | date: \"%Y-%m-%d\", \"subtract\", \"24 hours\" %}{% if appt_date >= cutoff %}true{% endif %}{% endif %}{% endif %}"
  },

  "decision_config": {
    "type": "custom",
    "body": "[\"send_age_aware_survey\"]",
    "output_schema": {"type": "array", "items": {"type": "string"}}
  },

  "actions": [
    {
      "decision_key": "send_age_aware_survey",
      "action_type": "sms",
      "tool_id": "__TOOL_ID__",
      "position": 0,
      "action_window_start": __WINDOW_START__,
      "action_window_end": __WINDOW_END__,

      "trigger_template": "{{ appointment.end_time | date: \"%Y-%m-%d %H:%M:%S\", \"add\", \"__DELAY__\", timezone }}",

      "idempotency_template": "{{ patient_id }}-{{ \"\" | now | date: \"%Y-%m-%d\" }}-{{ decision_key }}",

      "runtime_filter": "{% assign phone = mdm_output.regulated_patient.telecom | where: \"system\", \"phone\" | map: \"value\" | first %}{% if phone and phone != \"\" %}{% if appointment.status == \"fulfilled\" or appointment.status == \"arrived\" or appointment.status == \"checked_in\" %}true{% endif %}{% endif %}",

      "connected_app_id": "__CONNECTED_APP_ID__",
      "connected_app_route": "__FORM_ROUTE__",
      "connected_app_metadata_template": "{\"appointment_uuid\":\"{{ appointment.unregulated_appointment_id }}\",\"patient_uuid\":\"{{ mdm_output.patient.id }}\",\"patient_identifier\":\"{{ mdm_output.regulated_patient.identifier[0].value }}\",\"first_name\":\"{{ mdm_output.regulated_patient.name[0].given[0] }}\",\"last_name\":\"{{ mdm_output.regulated_patient.name[0].family }}\",\"location_name\":\"{{ appointment.location_participants[0].location.name }}\"}",

      "tool_call": {
        "tool_call_type": "sms_request",
        "to": {"type": "custom", "body": "{{ mdm_output.regulated_patient.telecom | where: \"system\", \"phone\" | map: \"value\" | first }}"},
        "body": {"type": "custom", "body": "__SMS_BODY__"},
        "sms_type": "transactional"
      }
    }
  ]
}
```

---

## Template C: Minimal Workflow (scaffold)

**Use case:** Starting point for any custom workflow. No filter, no
decision logic, one action. Good for testing tool integration.

```json
{
  "name": "__NAME__",
  "description": "__DESCRIPTION__",
  "dataset_type": "__DATASET_TYPE__",
  "status": "draft",
  "actions": [
    {
      "decision_key": "__DECISION_KEY__",
      "action_type": "__ACTION_TYPE__",
      "tool_id": "__TOOL_ID__",
      "position": 0,
      "trigger_template": "now",
      "idempotency_template": "{{ checksum }}-{{ action_id }}",
      "tool_call": {
        "tool_call_type": "__TOOL_CALL_TYPE__",
        "__TOOL_CALL_FIELDS__": "..."
      }
    }
  ]
}
```

### Tool call types

| `tool_call_type` | Action type | Key fields |
|-----------------|-------------|------------|
| `sms_request` | `sms` | `to`, `body`, `sms_type` |
| `restapi_request` | `data_exchange` | `method`, `path`, `pagination_context_template` |
| `s3_request` | `data_exchange` | `file_path` |
| `aws_lambda_request` | `data_exchange` | `payload`, `timeout_ms` |
| `sftp_request` | `data_exchange` | `path`, `content_type` |

Each field in `tool_call` can be a TemplateConfig:
`{"type": "custom", "body": "<liquid>"}` or `{"type": "identity"}`.

## Presentation

Don't show raw JSON templates to the user. Present customisation
points as a checklist. Fill in defaults, ask about the rest. Only
show the full JSON body on explicit request ("show the JSON").
