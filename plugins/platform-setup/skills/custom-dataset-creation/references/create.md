# Create + receipt

## CLI call

```bash
alvera --profile <p> generic-tables create <datalake_slug> [tenant_slug] \
  --body-file /tmp/gt-<slug>.json
```

- `<datalake_slug>` — from session state. Required positional.
- `[tenant_slug]` — optional if the profile has a default tenant.
- Always `--body-file`; never `--body '<json>'` for this resource —
  columns make the payload big, and the tempfile habit pays off when
  we add sensitive fields later.

## Body shape

```json
{
  "title": "Patients",
  "description": "Patient demographics from EMR",
  "data_domain": "healthcare",
  "columns": [
    {
      "name": "first_name",
      "title": "First Name",
      "type": "string",
      "description": "Patient's first name",
      "privacy_requirement": "redact_only",
      "is_required": true,
      "is_unique": true,
      "is_array": false
    }
  ]
}
```

Rules:
- `title` required.
- `columns` length ≥ 1. Enforce client-side — refuse a zero-column
  table without calling the API.
- `name` must be snake_case. Enforce client-side.
- All other column fields optional with documented defaults
  (`type: string`, `privacy_requirement: none`, booleans `false`).
- `data_domain` omitted or `null` is fine for cross-domain tables.

## Tempfile hygiene

```bash
BODY=/tmp/gt-$(date +%s).json
umask 077
# write body here…
chmod 600 "$BODY"

if alvera --profile "$P" generic-tables create "$DL" ["$T"] --body-file "$BODY"; then
  rm -f "$BODY"
  # append receipt (see below)
else
  rm -f "$BODY"
  # surface stderr verbatim, re-elicit offending field
fi
```

Never leave the tempfile behind. Never write the body to a path that
will be checked in.

## Error handling

Non-zero exit → authoritative validation failure:

- Surface stderr verbatim to the user.
- If the error names a field, re-elicit just that field.
- If the error is a structural complaint we should have caught
  client-side (empty `columns`, non-snake_case name), add that rule to
  the client-side checklist for the session so we don't repeat it.
- Do not retry the same payload. Do not paper over with a fallback.

## YAML receipt append

Only on 2xx. Append under `generic_tables:`:

```yaml
generic_tables:
  - title: Patients
    name: patients            # server-returned, auto-derived from title
    description: Patient demographics from EMR
    data_domain: healthcare
    datalake: prime-health    # slug reference, not id
    columns:
      - name: first_name
        title: First Name
        type: string
        description: Patient's first name
        privacy_requirement: redact_only
        is_required: true
        is_unique: true
        is_array: false
      # ...
```

- Reference datalake by **slug**, not id (matches the pattern in
  `guided`'s yaml-receipt).
- Record every column verbatim with the fields that were actually sent
  — don't re-derive defaults. If the user explicitly set
  `is_required: false`, write it; if they accepted the default, omit
  it. The receipt should show intent, not defaults.
- Do not write the server-returned id.
- Append-only per turn. If the same title gets created twice in a
  session (shouldn't happen — `list` gates that), append a second
  entry rather than rewriting the first.

## After create

- Tell the user: the table is created, and `privacy_requirement` is now
  locked. If they need to change it, they'll recreate.
- Ask what's next: another dataset, or done? This skill is single-
  purpose — no "now set up a tool" menu. Done = done.
