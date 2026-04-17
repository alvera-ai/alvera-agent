# Anti-pattern detection

Common data-quality issues in source files that silently corrupt
downstream data if passed through an identity or naive template.
The skill detects these automatically and either fixes them in the
Liquid template or warns the user.

## Patterns to detect

### 1. Date formats — not ISO 8601

Source files frequently use US-style dates. The FHIR `birth_date`,
`start`, and similar fields require `YYYY-MM-DD`.

| Source pattern | Example | Risk |
|---------------|---------|------|
| `MM/DD/YY` | `03/15/60` | Ambiguous century (1960 or 2060?) |
| `MM/DD/YYYY` | `03/15/1960` | Not ISO — rejected by strict parsers |
| `M/D/YY` | `3/15/60` | No zero-padding + ambiguous century |
| `DD-Mon-YYYY` | `15-Mar-1960` | Locale-dependent month name |
| `MM-DD-YYYY` | `03-15-1960` | Not ISO, easily confused with DD-MM |

**Template fix — MM/DD/YYYY → YYYY-MM-DD:**

```liquid
{% assign parts = msg.dob | split: "/" -%}
{{ parts[2] }}-{{ parts[0] }}-{{ parts[1] }}
```

**Template fix — MM/DD/YY → YYYY-MM-DD (with century pivot at 30):**

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

### 2. Gender / sex normalisation

FHIR expects lowercase: `male`, `female`, `other`, `unknown`.

| Source pattern | Example |
|---------------|---------|
| Title case | `Male`, `Female` |
| Upper case | `MALE`, `FEMALE` |
| Abbreviated | `M`, `F` |

**Template fix — downcase:**

```liquid
{{ msg.gender | downcase }}
```

**Template fix — single-letter to full word:**

```liquid
{% assign g = msg.gender | downcase -%}
{% if g == "m" %}male{% elsif g == "f" %}female{% else %}{{ g }}{% endif %}
```

### 3. Status mapping

FHIR appointment statuses: `proposed`, `pending`, `booked`,
`arrived`, `fulfilled`, `cancelled`, `noshow`, `entered-in-error`,
`checked-in`, `waitlist`.

Source systems use different vocabularies:

| Source | FHIR |
|--------|------|
| `Scheduled` | `booked` |
| `Completed` | `fulfilled` |
| `Cancelled` / `Canceled` | `cancelled` |
| `No-Show` / `NoShow` | `noshow` |

**Template fix:**

```liquid
{% assign s = msg.appt_status | downcase -%}
{% if s == "scheduled" -%}booked
{%- elsif s == "completed" -%}fulfilled
{%- elsif s == "cancelled" or s == "canceled" -%}cancelled
{%- elsif s == "no-show" or s == "noshow" -%}noshow
{%- else -%}proposed{%- endif %}
```

### 4. Missing `source_uri`

Every ingested record should carry a `source_uri` for provenance. If
the source file doesn't have one, inject a static value in the
template using the data source's URI:

```liquid
"source_uri": "{{ msg.source_uri | default: 'emr.my-practice.com' }}"
```

### 5. Identifier system missing or inconsistent

MDM resolution depends on a consistent `identifier.system`. If the
source file has a patient ID column but no system, the template must
supply one:

```liquid
"identifier": [{"system": "urn:emr:patient-id", "value": "{{ msg.patient_id }}"}]
```

If the source uses different column names for the same concept
(`mrn`, `patient_id`, `pat_id`), normalise in the template — don't
ask the user to rename the CSV.

## Scanner script

A local Python script that reads the file and outputs a pattern
summary. **No data values enter the conversation** — only format
patterns and category labels.

Write this to `/tmp/alvera-scan.py` and run it:

```python
#!/usr/bin/env python3
"""Anti-pattern scanner for DAC-upload. Outputs pattern summary as JSON.
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
    """Return the dominant date pattern or None."""
    counts = Counter()
    for v in values:
        v = v.strip()
        if not v:
            continue
        for regex, label in DATE_PATTERNS:
            if re.match(regex, v):
                counts[label] += 1
                break
    if not counts:
        return None
    dominant = counts.most_common(1)[0]
    return dominant[0] if dominant[1] >= len(values) * 0.5 else None

def scan_file(path):
    is_ndjson = path.endswith((".ndjson", ".jsonl"))
    rows = []

    with open(path, "r") as f:
        if is_ndjson:
            for i, line in enumerate(f):
                if i >= MAX_ROWS:
                    break
                line = line.strip()
                if line:
                    rows.append(json.loads(line))
        else:
            reader = csv.DictReader(f)
            for i, row in enumerate(reader):
                if i >= MAX_ROWS:
                    break
                rows.append(row)

    if not rows:
        print(json.dumps({"error": "no rows found"}))
        return

    # Count total rows (cheap — just count lines)
    with open(path, "r") as f:
        total = sum(1 for _ in f)
    if not is_ndjson:
        total -= 1  # header row

    columns = {}
    for col in rows[0].keys():
        values = [r.get(col, "") for r in rows if r.get(col)]
        entry = {"non_null": len(values), "total_scanned": len(rows)}

        # Date detection
        fmt = detect_date_format(values)
        if fmt:
            entry["detected_format"] = fmt
            entry["needs_fix"] = fmt != "YYYY-MM-DD"

        # Enum-like detection (few unique values relative to rows)
        unique = set(v.strip().lower() for v in values if v.strip())
        if 1 < len(unique) <= 10:
            entry["unique_values"] = sorted(set(v.strip() for v in values if v.strip()))
            # Gender check
            if unique & GENDER_KEYWORDS:
                has_upper = any(v[0].isupper() for v in entry["unique_values"])
                entry["needs_downcase"] = has_upper

        columns[col] = entry

    print(json.dumps({
        "row_count": total,
        "scanned": len(rows),
        "columns": columns
    }, indent=2))

if __name__ == "__main__":
    scan_file(sys.argv[1])
```

### Reading the output

The script produces a JSON summary. Key fields per column:

| Field | Meaning |
|-------|---------|
| `detected_format` | Date pattern found (e.g. `MM/DD/YY`) |
| `needs_fix` | `true` if date format is not ISO 8601 |
| `unique_values` | Category labels for enum-like columns |
| `needs_downcase` | `true` if enum values have capitalisation |
| `needs_mapping` | `true` if status values need FHIR mapping |

Surface findings to the user as a compact summary, then apply the
fixes in the Liquid template — never ask the user to reformat the
file.
