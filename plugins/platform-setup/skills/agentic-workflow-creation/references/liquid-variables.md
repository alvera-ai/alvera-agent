# Liquid variables

Variables available at each pipeline stage. Use
`alvera workflows metadata <datalake> <id>` to get the full list for
a specific workflow — it returns a markdown doc describing all
variables per stage.

## Variable availability by stage

| Variable | Filter | Decision | Action (runtime_filter / trigger / tool_call) |
|----------|--------|----------|----------------------------------------------|
| `appointment.*` | yes | yes | yes |
| `patient.*` | yes | yes | yes |
| `mdm_output.*` | yes | yes | yes |
| `additional_context.*` | no | yes | yes |
| `patient_id` | yes | yes | yes |
| `checksum` | no | no | yes |
| `action_id` | no | no | yes |
| `decision_key` | no | no | yes |
| `connected_app_form_url` | no | no | yes (if connected_app configured) |
| `timezone` | yes | yes | yes |

## Common variable paths

### Appointment fields (`appointment.*`)

```liquid
{{ appointment.start }}                    → "2026-06-15T09:30:00Z"
{{ appointment.end_time }}                 → "2026-06-15T10:15:00Z"
{{ appointment.status }}                   → "fulfilled"
{{ appointment.source_uri }}               → "emr.my-practice.com"
{{ appointment.minutes_duration }}         → 45
{{ appointment.unregulated_appointment_id }} → "uuid"
{{ appointment.identifier[0].value }}      → "EMR-APPT-12345"
{{ appointment.location_participants[0].location.name }} → "Main Clinic"
```

### Patient fields (via MDM resolution)

```liquid
{{ mdm_output.patient.id }}                → "uuid" (public patient ID)
{{ mdm_output.regulated_patient.birth_date }} → "1960-03-15"
{{ mdm_output.regulated_patient.gender }}  → "female"
{{ mdm_output.regulated_patient.name[0].given[0] }} → "Jane"
{{ mdm_output.regulated_patient.name[0].family }}   → "Doe"
{{ mdm_output.regulated_patient.identifier[0].value }} → "P-12345"
```

### Telecom (phone / email lookup)

```liquid
{% comment %} Phone number {% endcomment %}
{% assign phone = mdm_output.regulated_patient.telecom
  | where: "system", "phone" | map: "value" | first %}
{{ phone }}  → "+15551234567"

{% comment %} Email {% endcomment %}
{% assign email = mdm_output.regulated_patient.telecom
  | where: "system", "email" | map: "value" | first %}
{{ email }}  → "jane@example.com"
```

### Context datasets (`additional_context.*`)

Loaded by `context_datasets` config. Available after the filter stage.

```liquid
{{ additional_context.message.size }}      → 0 (no prior messages)
{{ additional_context.message[0].sent_at }} → "2026-01-15T..."
```

## Common Liquid patterns

### Date formatting

```liquid
{{ appointment.start | date: "%Y-%m-%d" }}           → "2026-06-15"
{{ appointment.start | date: "%Y-%m-%d %H:%M:%S" }}  → "2026-06-15 09:30:00"
```

### Date arithmetic (scheduling)

```liquid
{% comment %} 3 hours after appointment start {% endcomment %}
{{ appointment.start | date: "%Y-%m-%d %H:%M:%S", "add", "3 hours", timezone }}

{% comment %} 7 days after appointment end {% endcomment %}
{{ appointment.end_time | date: "%Y-%m-%d %H:%M:%S", "add", "7 days", timezone }}

{% comment %} "now" — fire immediately {% endcomment %}
now
```

### Age calculation

```liquid
{% assign patient_age = mdm_output.regulated_patient.birth_date | age %}
{% if patient_age >= 65 %}true{% endif %}
```

### Recency gate (last 24 hours)

```liquid
{% assign appt_date = appointment.start | date: "%Y-%m-%d" %}
{% assign cutoff = "" | now | date: "%Y-%m-%d", "subtract", "24 hours" %}
{% if appt_date >= cutoff %}true{% endif %}
```

### Phone exists guard

```liquid
{% assign phone = mdm_output.regulated_patient.telecom
  | where: "system", "phone" | map: "value" | first %}
{% if phone and phone != "" %}true{% endif %}
```

### Appointment status guard

```liquid
{% if appointment.status == "fulfilled"
  or appointment.status == "arrived"
  or appointment.status == "checked_in" %}true{% endif %}
```

### Prior message dedup (via context dataset)

```liquid
{% if additional_context.message.size == 0 %}true{% endif %}
```

### Combining guards in runtime_filter

Chain guards with nested `{% if %}`. All must pass for `"true"`:

```liquid
{% assign phone = mdm_output.regulated_patient.telecom
  | where: "system", "phone" | map: "value" | first %}
{% if phone and phone != "" %}
  {% if additional_context.message.size == 0 %}
    {% if appointment.status == "fulfilled"
      or appointment.status == "arrived"
      or appointment.status == "checked_in" %}true{% endif %}
  {% endif %}
{% endif %}
```

## Filter vs runtime_filter semantics

Both output `"true"` to **proceed** (not to skip):

| Template | Scope | `"true"` means | Empty/nil means |
|----------|-------|----------------|-----------------|
| `filter_config` | Entire workflow | Record enters pipeline | Record is filtered out |
| `runtime_filter` | Single action | Action executes | Action is skipped |

This matches the guide's convention. State it clearly when building
templates — the user's intuition may be "filter = skip".
