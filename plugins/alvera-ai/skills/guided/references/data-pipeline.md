# Data pipeline

Full flow for onboarding data from a file: compliance gate → column
profiling → create table → anti-pattern scan → interop template →
sandbox test → upload. Used when the outcome involves ingesting data.

## Step 1: Compliance gate

Before touching the file, ask exactly once:

> "Is this sample file **(a) dummy / synthetic**, **(b) real data you're
> OK sharing with me**, or **(c) real data I must not see** (PHI / PII
> under HIPAA, or covered by a BAA)? With (a) or (b) I'll read the file
> directly; with (c) I'll generate a local Python script for you to run,
> and only the column shape comes back — never row values."

Rules:
- Don't default. Wait for explicit (a), (b), or (c).
- Ambiguous → treat as (c).
- Don't re-ask. If (c), honour it for the rest of this dataset.

## Step 2: Column profiling

### Path (a)/(b) — direct profiling

Read file via `Read`, profile first 1000 rows.

Format detection:
- `.csv` → CSV. Sniff delimiter from first line.
- `.ndjson`/`.jsonl` → NDJSON.
- Other → sniff first non-blank line: `{` → NDJSON, else CSV.

Per column, derive: `original_name`, `suggested_name` (snake_case),
`inferred_type`, `null_rate`, `cardinality` (constant/unique/high/medium/low),
`min_length`, `max_length`, `looks_sensitive`, `detected_date_format`,
`looks_like_id`.

### Type inference (first match wins)

1. All int → `integer` (**but see ID override below**)
2. All float (not all int) → `float`
3. All match true/false/yes/no/0/1 → `boolean`
4. All ISO date (`YYYY-MM-DD`) → `date`
5. All ISO datetime → `datetime`
6. All match `HH:MM(:SS)?` → `time`
7. All match non-ISO date pattern → `date` with `detected_date_format`
8. Otherwise → `string`

### ID-like integer override

When column name looks like identifier (`_id`, `_key`, `mrn`, `zip`, `ssn`,
etc.) and all values parse as int, **default to `string`** and ask.

### Non-ISO date detection

| Source pattern   | `detected_date_format` | Needs interop fix |
|-----------------|------------------------|-------------------|
| `YYYY-MM-DD`    | `YYYY-MM-DD`           | No                |
| `MM/DD/YYYY`    | `MM/DD/YYYY`           | Yes               |
| `MM/DD/YY`      | `MM/DD/YY`             | Yes               |
| `M/D/YY`        | `M/D/YY`               | Yes               |
| `DD-Mon-YYYY`   | `DD-Mon-YYYY`          | Yes               |
| `MM-DD-YYYY`    | `MM-DD-YYYY`           | Yes               |

### Name normalisation

- Has spaces/non-alnum → lowercase, replace with `_`, propose rename.
- All-caps/mixed-case single token → lowercase only.
- Already lowercase, no spaces → keep verbatim.
- Collision → append `_2`, `_3`. Starts with digit → prefix `col_`.

### Path (c) — local profiling script

Copy `scripts/alvera-profile.py` to `/tmp/alvera-profile.py`. User runs
it, pastes JSON summary back. Delete the script after use.

```bash
cp scripts/alvera-profile.py /tmp/alvera-profile.py
chmod 600 /tmp/alvera-profile.py
# User runs: python3 /tmp/alvera-profile.py <path>
# Delete after: rm /tmp/alvera-profile.py
```

Output shape:

```json
{
  "format": "csv",
  "row_count": 1234,
  "sampled": 1000,
  "columns": [
    {
      "original_name": "First Name",
      "suggested_name": "first_name",
      "inferred_type": "string",
      "null_rate": 0.02,
      "cardinality": "high",
      "min_length": 1,
      "max_length": 64,
      "looks_sensitive": true
    }
  ]
}
```

## Step 3: Propose table

Plain-language proposal, one bullet per column:
- `name`, `type`, `privacy_requirement`, `is_required`, `is_unique`, `is_array`
- Flag non-ISO dates: stored as `date` (ISO), interop template converts.
- **State `privacy_requirement` is locked at creation.**
- **State `is_unique` is composite** when multiple columns have it.

Confirm with y/n. Only show JSON on explicit request.

## Step 4: Create table

```bash
alvera --profile <p> generic-tables create <datalake> [tenant] \
  --body-file /tmp/gt-<slug>.json
```

Tempfile hygiene: `chmod 600`, `rm` immediately on return. Append to
`alvera-<tenant-slug>.yaml` on 2xx.

## Step 5: Anti-pattern scan (before upload)

Run the anti-pattern scanner on the file. Detects date format issues,
gender/sex normalisation, status mapping, missing identifiers.

Copy `scripts/alvera-scan.py` to `/tmp/alvera-scan.py` and run it:

```bash
cp scripts/alvera-scan.py /tmp/alvera-scan.py
chmod 600 /tmp/alvera-scan.py
python3 /tmp/alvera-scan.py <file>
rm /tmp/alvera-scan.py
```

Surface findings as compact summary. Apply fixes in the Liquid template,
not the file.

### Anti-pattern fixes (Liquid templates)

**MM/DD/YYYY → YYYY-MM-DD:**
```liquid
{% assign parts = msg.dob | split: "/" -%}
{{ parts[2] }}-{{ parts[0] }}-{{ parts[1] }}
```

**MM/DD/YY → YYYY-MM-DD (century pivot at 30):**
```liquid
{% assign parts = msg.dob | split: "/" -%}
{% assign yr = parts[2] | plus: 0 -%}
{% if yr >= 100 -%}
  {{ parts[2] }}-{{ parts[0] }}-{{ parts[1] }}
{%- elsif yr > 30 -%}
  19{{ parts[2] }}-{{ parts[0] }}-{{ parts[1] }}
{%- else -%}
  20{{ parts[2] }}-{{ parts[0] }}-{{ parts[1] }}
{%- endif %}
```

**Gender downcase:**
```liquid
{{ msg.gender | downcase }}
```

**Single-letter to full word:**
```liquid
{% assign g = msg.gender | downcase -%}
{% if g == "m" %}male{% elsif g == "f" %}female{% else %}{{ g }}{% endif %}
```

**Status mapping:**
```liquid
{% assign s = msg.appt_status | downcase -%}
{% if s == "scheduled" -%}booked
{%- elsif s == "completed" -%}fulfilled
{%- elsif s == "cancelled" or s == "canceled" -%}cancelled
{%- elsif s == "no-show" or s == "noshow" -%}noshow
{%- else -%}proposed{%- endif %}
```

**Missing source_uri:**
```liquid
"source_uri": "{{ msg.source_uri | default: 'emr.my-practice.com' }}"
```

**Missing identifier system:**
```liquid
"identifier": [{"system": "urn:emr:patient-id", "value": "{{ msg.patient_id }}"}]
```

## Step 6: Resolve or create interop contract

### DAC already has contracts

Fetch each: `alvera interop get <datalake> <slug>`. Cross-check template
references against file columns. If template missing anti-pattern fixes,
warn and offer to update.

### No contract (create one)

Ask for `resource_type`. Fetch target metadata:
`alvera interop metadata <datalake> <contract-slug>`. Generate Liquid
template mapping source → FHIR. Present as plain-language table:

```
Source column   → FHIR field        Transform
─────────────────────────────────────────────────
patient_id      → identifier[0]     system: urn:our-emr:acme
first_name      → name[0].given[0]  —
dob             → birth_date        MM/DD/YY → YYYY-MM-DD
gender          → gender            | downcase
```

Create: `alvera interop create <datalake> --body-file <path>`.

Contract structure:
```json
{
  "name": "...",
  "resource_type": "patient",
  "data_activation_client_filter": "<liquid — output 'true' to skip>",
  "template_config": { "type": "custom", "body": "<liquid>" },
  "mdm_input_config": { "type": "custom", "body": "<liquid>" }
}
```

### Common resource patterns

**Patient mapping:**

| Source | FHIR | Transform |
|--------|------|-----------|
| patient_id | identifier[].value | Add system |
| first_name | name[].given[] | — |
| last_name | name[].family | — |
| dob | birth_date | Check format |
| gender | gender | `| downcase` |
| phone | telecom[] (phone) | — |
| email | telecom[] (email) | — |

**Appointment mapping:**

| Source | FHIR | Transform |
|--------|------|-----------|
| appt_id | identifier[].value | Add system |
| appt_status | status | Map to FHIR |
| appt_date + appt_time | start | Combine |
| duration | minutes_duration | Default 30 |
| patient_mrn | MDM resolution | — |

## Step 7: Create DAC (if needed)

```bash
alvera data-activation-clients create <datalake> [tenant] --body-file <path>
```

Body:
```json
{
  "name": "<user-provided>",
  "tool_id": "<auto-detected>",
  "data_source_id": "<auto-detected>",
  "tool_call": { "tool_call_type": "manual_upload" },
  "interoperability_contract_ids": ["<from step 6>"]
}
```

Auto-detect tool (first with `intent: data_exchange`) and data source.
If neither exists, create them first.

## Step 8: Sandbox test

Run one sample row through the contract pipeline:

```bash
# CSV — use python for robust parsing (handles BOM, quoted fields, etc.)
python3 -c "
import csv, json, sys, codecs
f = codecs.open(sys.argv[1], encoding='utf-8-sig')
r = csv.DictReader(f)
row = next(r)
f.close()
print(json.dumps(row))
" <file> | alvera interop run <datalake> <contract-slug> --body-file -

# NDJSON
python3 -c "
import codecs, sys
f = codecs.open(sys.argv[1], encoding='utf-8-sig')
for line in f:
    line = line.strip()
    if line:
        print(line)
        break
f.close()
" <file> | alvera interop run <datalake> <contract-slug> --body-file -
```

If the command fails with a parse error, check for BOM headers or
Windows line endings. The python snippets above handle UTF-8 BOM
(`utf-8-sig`) automatically.

The model sees only the pipeline output, never raw data.

| `stage` | Meaning | Action |
|---------|---------|--------|
| `completed` | Pipeline works | Proceed |
| `filtered` | Row filtered out | Warn — check filter |
| Error | Template bug | Surface pointer, fix, re-test |

## Step 9: Upload

Confirm, then execute three-step upload:

```bash
# 1. Presigned URL
alvera datalakes upload-link <datalake> <filename> --content-type <mime>

# 2. PUT the file
curl --fail --show-error --silent -X PUT \
  -H "Content-Type: <mime>" \
  --upload-file "<file>" "<url>"

# 3. Trigger processing
alvera data-activation-clients ingest-file <datalake> <dac> <key>
```

Content-type: `.csv` → `text/csv`, `.ndjson`/`.jsonl` → `application/x-ndjson`.
Never log the presigned URL — print only the `key`.

## Hard constraints

- **Compliance gate is non-negotiable.** If (c), never read the file.
- **Privacy is locked at creation.** Warn at confirmation time.
- **`is_unique` is composite.** State semantics when multiple columns.
- **Anti-pattern scan is non-negotiable.** Always run.
- **Sandbox test before first live ingest.** Never skip on new contracts.
- **Fixes go in the template, not the file.** Don't ask user to reformat.
- **Don't stream data through the model.** File goes disk → presigned URL.
- **Content-type must match.** Presigned URL signed with it; mismatch → 403.
- **One file per invocation.** Batch = loop.
- **Tempfile hygiene.** `chmod 600`, `rm` on return regardless of exit code.
- **Script cleanup.** Both `/tmp/alvera-profile.py` and `/tmp/alvera-scan.py`
  must be deleted after use. If a script fails on edge cases (BOM, Windows
  line endings), fix inline and re-run — don't modify the source scripts.
  The scripts handle UTF-8 BOM (`utf-8-sig`) automatically.
