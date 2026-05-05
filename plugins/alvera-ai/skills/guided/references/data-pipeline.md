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

Write `./alvera-profile.py` (stdlib only). User runs it, pastes JSON
summary back. Output shape:

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

Script (write verbatim to `./alvera-profile.py`):

```python
#!/usr/bin/env python3
"""Profile a CSV or NDJSON file. Emits schema + aggregates to stdout.
Never prints row values. Stdlib only. Usage: python3 alvera-profile.py <path>"""
import csv, json, re, sys
from collections import Counter
from datetime import date, datetime, time
from pathlib import Path

ISO_DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
ISO_DATETIME = re.compile(r"^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}(:\d{2})?(\.\d+)?(Z|[+-]\d{2}:?\d{2})?$")
CLOCK = re.compile(r"^\d{1,2}:\d{2}(:\d{2})?$")
BOOL = {"true","false","yes","no","0","1"}
SENSITIVE = re.compile(r"email|phone|ssn|dob|birth|address|name|zip|postal", re.I)
ID_LIKE = re.compile(r"_?id$|_key$|_code$|_num$|_ref$|^id$|^key$|^mrn$|^npi$|^zip$|^ssn$|^fax$", re.I)

DATE_PATTERNS = [
    (re.compile(r"^\d{1,2}/\d{1,2}/\d{2}$"), "M/D/YY"),
    (re.compile(r"^\d{1,2}/\d{1,2}/\d{4}$"), "M/D/YYYY"),
    (re.compile(r"^\d{2}/\d{2}/\d{2}$"), "MM/DD/YY"),
    (re.compile(r"^\d{2}/\d{2}/\d{4}$"), "MM/DD/YYYY"),
    (re.compile(r"^\d{2}-\d{2}-\d{4}$"), "MM-DD-YYYY"),
    (re.compile(r"^\d{2}-[A-Za-z]{3}-\d{4}$"), "DD-Mon-YYYY"),
]

def norm(s):
    low = s.lower()
    if re.fullmatch(r"[a-z0-9_]+", low):
        return low
    s = re.sub(r"[^a-z0-9]+", "_", low).strip("_")
    if s and s[0].isdigit(): s = "col_" + s
    return s or "col"

def detect_date_format(vals):
    counts = Counter()
    for v in vals:
        v = v.strip()
        if not v: continue
        if ISO_DATE.match(v):
            counts["YYYY-MM-DD"] += 1
            continue
        for regex, label in DATE_PATTERNS:
            if regex.match(v):
                counts[label] += 1
                break
    if not counts: return None
    dominant = counts.most_common(1)[0]
    return dominant[0] if dominant[1] >= len(vals) * 0.5 else None

def classify(vals):
    if not vals: return "string"
    def allmatch(pred):
        try: return all(pred(v) for v in vals)
        except Exception: return False
    if allmatch(lambda v: v.lstrip("-").isdigit()): return "integer"
    if allmatch(lambda v: float(v) is not None) and not allmatch(lambda v: v.lstrip("-").isdigit()): return "float"
    if allmatch(lambda v: v.lower() in BOOL): return "boolean"
    if allmatch(lambda v: ISO_DATE.match(v) is not None): return "date"
    if allmatch(lambda v: ISO_DATETIME.match(v) is not None): return "datetime"
    if allmatch(lambda v: CLOCK.match(v) is not None): return "time"
    fmt = detect_date_format(vals)
    if fmt: return "date"
    return "string"

def bucket(distinct, total):
    if total == 0: return "constant"
    if distinct == 1: return "constant"
    if distinct == total: return "unique"
    r = distinct / total
    if r > 0.5: return "high"
    if r > 0.05: return "medium"
    return "low"

def detect_format(p: Path) -> str:
    ext = p.suffix.lower()
    if ext == ".csv": return "csv"
    if ext in (".ndjson", ".jsonl"): return "ndjson"
    with p.open() as f:
        for line in f:
            s = line.strip()
            if s: return "ndjson" if s[0] == "{" else "csv"
    return "csv"

def iter_csv(p, n):
    with p.open(newline="") as f:
        reader = csv.DictReader(f)
        headers = reader.fieldnames or []
        rows = []
        for i, row in enumerate(reader):
            if i >= n: break
            rows.append(row)
        return headers, rows

def iter_ndjson(p, n):
    headers, rows = [], []
    with p.open() as f:
        for i, line in enumerate(f):
            if i >= n: break
            line = line.strip()
            if not line: continue
            obj = json.loads(line)
            for k in obj:
                if k not in headers: headers.append(k)
            rows.append(obj)
    return headers, rows

def count_total_rows(p: Path, fmt: str) -> int:
    with p.open() as f:
        return sum(1 for line in f if line.strip()) - (1 if fmt == "csv" else 0)

def profile(path):
    p = Path(path)
    fmt = detect_format(p)
    headers, rows = iter_csv(p, 1000) if fmt == "csv" else iter_ndjson(p, 1000)
    total = count_total_rows(p, fmt)
    cols = []
    for h in headers:
        raw = [r.get(h) for r in rows]
        nulls = sum(1 for v in raw if v is None or v == "")
        non_null = [str(v) for v in raw if v is not None and v != ""]
        distinct = len(set(non_null))
        lens = [len(v) for v in non_null]
        date_fmt = detect_date_format(non_null)
        col = {
            "original_name": h,
            "suggested_name": norm(h),
            "inferred_type": classify(non_null),
            "null_rate": round(nulls / max(len(raw), 1), 4),
            "cardinality": bucket(distinct, len(non_null)),
            "min_length": min(lens) if lens else 0,
            "max_length": max(lens) if lens else 0,
            "looks_sensitive": bool(SENSITIVE.search(h)),
        }
        if date_fmt:
            col["detected_date_format"] = date_fmt
            col["needs_interop_conversion"] = date_fmt != "YYYY-MM-DD"
        if col["inferred_type"] == "integer" and ID_LIKE.search(h):
            col["looks_like_id"] = True
        cols.append(col)
    return {"format": fmt, "row_count": total, "sampled": len(rows), "columns": cols}

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("usage: python3 alvera-profile.py <path>", file=sys.stderr); sys.exit(2)
    json.dump(profile(sys.argv[1]), sys.stdout, indent=2)
    print()
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
`infra.yaml` on 2xx.

## Step 5: Anti-pattern scan (before upload)

Run the anti-pattern scanner on the file. Detects date format issues,
gender/sex normalisation, status mapping, missing identifiers.

Scanner script (write to `/tmp/alvera-scan.py`):

```python
#!/usr/bin/env python3
"""Anti-pattern scanner. Outputs pattern summary as JSON.
Reads only the first MAX_ROWS rows. Never prints raw data values."""

import csv, json, re, sys
from collections import Counter

MAX_ROWS = 100

DATE_PATTERNS = [
    (r"\d{1,2}/\d{1,2}/\d{2}$", "M/D/YY"),
    (r"\d{1,2}/\d{1,2}/\d{4}$", "M/D/YYYY"),
    (r"\d{2}/\d{2}/\d{2}$", "MM/DD/YY"),
    (r"\d{2}/\d{2}/\d{4}$", "MM/DD/YYYY"),
    (r"\d{4}-\d{2}-\d{2}$", "YYYY-MM-DD"),
    (r"\d{2}-\d{2}-\d{4}$", "MM-DD-YYYY"),
    (r"\d{2}-[A-Za-z]{3}-\d{4}$", "DD-Mon-YYYY"),
]

GENDER_KEYWORDS = {"male", "female", "other", "unknown", "m", "f", "u"}

def detect_date_format(values):
    counts = Counter()
    for v in values:
        v = v.strip()
        if not v: continue
        for regex, label in DATE_PATTERNS:
            if re.match(regex, v):
                counts[label] += 1
                break
    if not counts: return None
    dominant = counts.most_common(1)[0]
    return dominant[0] if dominant[1] >= len(values) * 0.5 else None

def scan_file(path):
    is_ndjson = path.endswith((".ndjson", ".jsonl"))
    rows = []
    with open(path, "r") as f:
        if is_ndjson:
            for i, line in enumerate(f):
                if i >= MAX_ROWS: break
                line = line.strip()
                if line: rows.append(json.loads(line))
        else:
            reader = csv.DictReader(f)
            for i, row in enumerate(reader):
                if i >= MAX_ROWS: break
                rows.append(row)
    if not rows:
        print(json.dumps({"error": "no rows found"}))
        return
    with open(path, "r") as f:
        total = sum(1 for _ in f)
    if not is_ndjson: total -= 1
    columns = {}
    for col in rows[0].keys():
        values = [r.get(col, "") for r in rows if r.get(col)]
        entry = {"non_null": len(values), "total_scanned": len(rows)}
        fmt = detect_date_format(values)
        if fmt:
            entry["detected_format"] = fmt
            entry["needs_fix"] = fmt != "YYYY-MM-DD"
        unique = set(v.strip().lower() for v in values if v.strip())
        if 1 < len(unique) <= 10:
            entry["unique_values"] = sorted(set(v.strip() for v in values if v.strip()))
            if unique & GENDER_KEYWORDS:
                has_upper = any(v[0].isupper() for v in entry["unique_values"])
                entry["needs_downcase"] = has_upper
        columns[col] = entry
    print(json.dumps({"row_count": total, "scanned": len(rows), "columns": columns}, indent=2))

if __name__ == "__main__":
    scan_file(sys.argv[1])
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
# CSV
head -n 2 <file> | python3 -c "
import csv, json, sys
r = csv.DictReader(sys.stdin)
print(json.dumps(next(r)))
" | alvera interop run <datalake> <contract-slug> --body-file -

# NDJSON
head -n 1 <file> | alvera interop run <datalake> <contract> --body-file -
```

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
