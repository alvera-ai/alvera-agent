# Liquid template generation

When the DAC has no interop contract, or the existing contract uses
`identity` (pass-through) and the source data doesn't match the FHIR
target schema, the skill auto-generates a custom Liquid template.

## TemplateConfig types

| Type | Body | Path | When to use |
|------|------|------|-------------|
| `identity` | Forbidden | Forbidden | Source data is already FHIR-formatted |
| `custom` | Required | Forbidden | Source data needs transformation (most cases) |
| `system` | Forbidden | Required | Platform-managed template — don't touch |
| `null` | Forbidden | Forbidden | Disable the stage |

**Default to `custom`** unless the user explicitly says their data is
already FHIR-formatted (rare for CSV/NDJSON exports from EMR systems).

## Contract structure

An interop contract has three Liquid stages:

```json
{
  "name": "...",
  "resource_type": "patient",
  "data_activation_client_filter": "<liquid — output 'true' to skip>",
  "template_config": {
    "type": "custom",
    "body": "<liquid — source → FHIR transform>"
  },
  "mdm_input_config": {
    "type": "custom",
    "body": "<liquid — extract identifiers for MDM resolution>"
  }
}
```

### Filter (`data_activation_client_filter`)

Optional. Outputs `"true"` to skip the row, anything else (or empty)
to pass. Uses `msg.row.X` (note: `msg.row`, not just `msg`).

```liquid
{% if msg.row.active == "false" %}true{% endif %}
```

### Transform (`template_config.body`)

Maps source fields to FHIR output. Uses `msg.X` for field access.
The output must be valid JSON matching the `resource_type` schema.

### MDM input (`mdm_input_config.body`)

Extracts patient identifiers for Master Data Management resolution.
Required for any resource that links to a patient (appointments,
observations, etc.). Uses `msg.X`.

## Generation approach

1. **Read file headers** — column names from CSV line 1 or NDJSON keys
2. **Get target metadata** — `alvera interop metadata <datalake> <slug>`
   returns a markdown doc describing available fields for the
   `resource_type`
3. **Map source → target** using name similarity and domain knowledge
4. **Apply anti-pattern fixes** from the scan results
5. **Present as a table** for user confirmation

## Common resource patterns

### Patient

Source columns → FHIR fields:

| Source | FHIR | Notes |
|--------|------|-------|
| `patient_id`, `mrn`, `pat_id` | `identifier[].value` | Must add `system` |
| `first_name`, `given_name` | `name[].given[]` | |
| `last_name`, `family_name`, `surname` | `name[].family` | |
| `dob`, `birth_date`, `date_of_birth` | `birth_date` | **Check format** |
| `gender`, `sex` | `gender` | `\| downcase` |
| `phone`, `phone_number` | `telecom[] (system: phone)` | |
| `email` | `telecom[] (system: email)` | |
| `active` | `active` | |
| `source_uri` | `source_uri` | Default if missing |

**Template:**

```liquid
{
  "active": true,
  "identifier": [
    {"system": "urn:emr:patient-id", "value": "{{ msg.patient_id }}"}
  ],
  "name": [
    {
      "use": "official",
      "family": "{{ msg.last_name }}",
      "given": ["{{ msg.first_name }}"]
    }
  ],
  "gender": "{{ msg.gender | downcase }}",
  "birth_date": "{% assign p = msg.dob | split: '/' %}{{ p[2] }}-{{ p[0] }}-{{ p[1] }}",
  "telecom": [
    {% if msg.phone %}{"system": "phone", "value": "{{ msg.phone }}", "use": "home"}{% endif %}
    {% if msg.email %}{% if msg.phone %},{% endif %}{"system": "email", "value": "{{ msg.email }}", "use": "home"}{% endif %}
  ],
  "source_uri": "{{ msg.source_uri | default: '<data-source-uri>' }}"
}
```

**MDM input:**

```liquid
{
  "identifiers": [
    {"system": "urn:emr:patient-id", "value": "{{ msg.patient_id }}"}
  ],
  "family_name": "{{ msg.last_name }}",
  "given_name": "{{ msg.first_name }}"
}
```

### Appointment

Source columns → FHIR fields:

| Source | FHIR | Notes |
|--------|------|-------|
| `appt_id`, `appointment_id` | `identifier[].value` | Must add `system` |
| `appt_status`, `status` | `status` | **Needs mapping** |
| `appt_date`, `date` | `start` (date part) | Combine with time |
| `appt_time`, `time` | `start` (time part) | |
| `duration`, `minutes` | `minutes_duration` | Default 30 |
| `visit_type`, `type` | `description` | |
| `patient_mrn`, `mrn` | MDM resolution | |
| `patient_first_name` | MDM resolution | |
| `patient_last_name` | MDM resolution | |

**Template:**

```liquid
{
  {% assign s = msg.appt_status | downcase -%}
  {% if s == "scheduled" -%}"status": "booked"
  {%- elsif s == "completed" -%}"status": "fulfilled"
  {%- elsif s == "cancelled" or s == "canceled" -%}"status": "cancelled"
  {%- elsif s == "no-show" or s == "noshow" -%}"status": "noshow"
  {%- else -%}"status": "proposed"{%- endif %},
  "start": "{{ msg.appt_date }}T{{ msg.appt_time }}:00Z",
  "minutes_duration": {{ msg.duration | default: 30 }},
  "description": "{{ msg.visit_type }}",
  "identifier": [
    {"system": "urn:emr:appointment-id", "value": "{{ msg.appt_id }}"}
  ],
  "source_uri": "{{ msg.source_uri | default: '<data-source-uri>' }}"
}
```

**MDM input** (resolves the patient by MRN):

```liquid
{
  "identifiers": [
    {"system": "urn:emr:patient-id", "value": "{{ msg.patient_mrn }}"}
  ],
  "family_name": "{{ msg.patient_last_name }}",
  "given_name": "{{ msg.patient_first_name }}"
}
```

## Presentation

Present the proposed mapping as a plain-language table, not raw
Liquid. The user confirms with y/n:

```
Source column   → FHIR field        Transform
─────────────────────────────────────────────────
patient_id      → identifier[0]     system: urn:emr:patient-id
first_name      → name[0].given[0]  —
last_name       → name[0].family    —
dob             → birth_date        MM/DD/YY → YYYY-MM-DD
gender          → gender            | downcase
phone           → telecom[0]        system: phone
```

Only show the raw Liquid body if the user explicitly asks ("show me
the template", "show the JSON").

## Sandbox test

After creating or updating a contract, always sandbox-test before
live ingest. The `/run` endpoint processes one row through the full
pipeline (filter → transform → MDM) without writing to the DB.

Pipe the first data row directly from disk to the CLI — the model
sees only the pipeline output, never raw source data.

Check that:
- `stage` is `completed` (not `filtered` or errored)
- `transformed` output has all expected FHIR fields populated
- Date fields are in `YYYY-MM-DD` format in the output
- Gender is lowercase
- Identifiers have the correct `system`
