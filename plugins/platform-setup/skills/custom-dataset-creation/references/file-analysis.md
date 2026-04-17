# File analysis

## Compliance gate

Ask exactly once, with three labelled choices:

> "Is this sample file **(a) dummy / synthetic**, **(b) real data you're
> OK sharing with me**, or **(c) real data I must not see** (PHI / PII
> under HIPAA, or covered by a BAA)? With (a) or (b) I'll read the file
> directly; with (c) I'll generate a local Python script for you to
> run, and only the column shape comes back to me — never row values."

Rules:

- Don't default. Wait for an explicit (a), (b), or (c).
- Ambiguous answer ("I think it's fine?", "mostly synthetic but not
  sure") → treat as (c). Cheaper to be wrong in the safe direction.
- Don't re-ask. If the user picks (c), honour it for the rest of this
  dataset. Don't negotiate mid-flow ("any chance I could see just one
  row?"). No.

### Why this matters

Anthropic's API is not covered by a BAA for most users by default.
When the user picks (c), they're telling you the file cannot cross the
conversation boundary. That means, for this skill:

- Do not call `Read` on the file.
- Do not ask the user to paste sample rows "just to check".
- Do not echo anything that could contain row values in the output —
  only aggregate facts (names, types, null rate, cardinality bucket).

## Path (a) / (b): direct profiling

Call `Read` on the sample, then profile inline.

Format detection:

- Extension `.csv` → CSV. Sniff delimiter (`,` / `;` / `\t`) from the
  first line. First row is the header.
- Extension `.ndjson` / `.jsonl` → NDJSON. Each line is a JSON object.
- Anything else → sniff the first non-blank line: starts with `{` →
  NDJSON, else CSV. If ambiguous, ask.

Sample size: first 1,000 rows. Skip blank lines. Cap the read on huge
files — tell the user you profiled a prefix.

Per column, derive:

| Field             | How                                                            |
|-------------------|----------------------------------------------------------------|
| `original_name`   | Raw header / first-row JSON key                                |
| `suggested_name`  | `snake_case(original_name)` — see normalisation rules below    |
| `inferred_type`   | Apply type rules below; first match wins                       |
| `null_rate`       | `count(empty/null) / row_count`                                |
| `cardinality`     | Bucket distinct count: 1 → `constant`, = row_count → `unique`, > 50% → `high`, > 5% → `medium`, else → `low` |
| `min_length`      | Shortest non-null string                                       |
| `max_length`      | Longest non-null string                                        |
| `looks_sensitive` | Regex on name: `email\|phone\|ssn\|dob\|birth\|address\|name\|zip\|postal` |
| `detected_date_format` | If values match a date pattern (ISO or not), report the format. `null` if not a date. |
| `looks_like_id` | `true` if the column name contains `id\|key\|code\|num\|ref\|mrn\|npi\|zip\|ssn\|fax` and all values parse as int. |

### Type inference (in order — first match wins)

Apply to non-null values only. If there are zero non-null values,
fall back to `string`.

1. All parse as `int` → `integer` **(but see ID override below)**
2. All parse as `float` (and at least one isn't a pure int) → `float`
3. All match `true|false|yes|no|0|1` (case-insensitive) → `boolean`
4. All parse as ISO-8601 date (`YYYY-MM-DD`) → `date`
5. All parse as ISO-8601 datetime → `datetime`
6. All match `HH:MM(:SS)?` → `time`
7. All match a **non-ISO date pattern** (MM/DD/YY, MM/DD/YYYY,
   M/D/YY, DD-Mon-YYYY, MM-DD-YYYY) → `date`, with
   `detected_date_format` set to the pattern. The generic table
   stores ISO dates; the interop template handles conversion.
8. Otherwise → `string`

### ID-like integer override

When a column's values all parse as `int` but its name looks like an
identifier (`id`, `key`, `code`, `num`, `ref`, `mrn`, `npi`, `zip`,
`ssn`, `fax`), **default the proposed type to `string`** and ask:

> "`patient_id` — all values are numeric, but the name suggests an
> identifier. Storing as `string` (default) — IDs often have leading
> zeros or shouldn't support arithmetic. Want `integer` instead?"

Why: IDs that happen to be numeric today may gain prefixes, dashes,
or leading zeros tomorrow. Storing as `string` is the safe default.
`zip` codes and `ssn` values especially break if stored as integers
(leading zeros are stripped).

The profiler sets `looks_like_id: true` on these columns. The column
proposal step uses this to flip the default.

### Non-ISO date detection

The profiler recognises these source formats and still classifies
the column as `date` (not `string`):

| Source pattern | `detected_date_format` | Needs interop fix |
|---------------|----------------------|-------------------|
| `YYYY-MM-DD` | `YYYY-MM-DD` | No — already ISO |
| `MM/DD/YYYY` | `MM/DD/YYYY` | Yes |
| `MM/DD/YY` | `MM/DD/YY` | Yes (ambiguous century) |
| `M/D/YY` | `M/D/YY` | Yes (no zero-padding) |
| `DD-Mon-YYYY` | `DD-Mon-YYYY` | Yes |
| `MM-DD-YYYY` | `MM-DD-YYYY` | Yes |

When a non-ISO format is detected, the column proposal flags it:
*"`dob` looks like dates in MM/DD/YY format. Column type → `date`
(the generic table stores YYYY-MM-DD). The interop template created
by `/DAC-upload` will auto-convert."*

This bridges the gap between custom-dataset-creation (schema) and
DAC-upload (ingestion template). The user knows at schema time that
their source data will need transformation.

`is_array: true` is only applicable to NDJSON where the column value is
a JSON array. CSV cannot represent arrays natively — don't propose it
for CSV input.

### Name normalisation

Only transform names that **actually have separators** (spaces, hyphens,
mixed case with word boundaries). Single-token column names that are
already lowercase and contiguous stay as-is — don't inject underscores
where the original had none.

Rules:

- **Has spaces or non-alphanumeric chars** → lowercase, replace runs
  of non-`[a-z0-9]+` with a single `_`, strip leading / trailing `_`.
  Propose the rename to the user: *"`First Name` → `first_name` for
  simplicity?"*
- **All-caps or mixed-case single token** → lowercase only. `MRN` →
  `mrn`. `PatientDOB` → `patientdob` (don't CamelCase-split — too
  error-prone; ask the user if they want `patient_dob` instead).
- **Already lowercase, no spaces** → keep verbatim. `parapptyn`
  stays `parapptyn`. Do **not** try to word-split abbreviations
  (`par_appt_yn` etc.) — you don't know the user's abbreviation
  scheme and guessing wrong is worse than leaving it untouched.
- If the result collides with another column, append `_2`, `_3`, …
- If the result starts with a digit, prefix `col_`.

Examples:
  - `First Name` → ask: `first_name`?   (has a space)
  - `Patient DOB` → ask: `patient_dob`?  (has a space)
  - `parapptyn` → keep as `parapptyn`    (already lowercase, no spaces)
  - `MRN` → `mrn`                        (just lowercase, single token)
  - `123 Main St` → `col_123_main_st`    (has spaces + leading digit)

## Path (c): local profiling script

The user runs a standalone script on their machine. The script emits a
JSON summary (schema + aggregates, **no row values**) which the user
pastes back. Claude never reads the file.

Requirements:

- **stdlib only** — `csv`, `json`, `collections`, `datetime`, `re`,
  `sys`, `pathlib`. Zero `pip install` surface area.
- Single file, runnable as `python3 alvera-profile.py <path>`.
- Works for CSV and NDJSON, sniffing from extension with content
  fallback.
- Output is a single JSON document on stdout. No row content.
- Exit 0 on success; non-zero with a clear message on malformed input.

Output shape (matches what path (a)/(b) produces internally, so the
downstream column proposal step is format-agnostic):

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
    },
    {
      "original_name": "DOB",
      "suggested_name": "dob",
      "inferred_type": "date",
      "null_rate": 0.0,
      "cardinality": "high",
      "min_length": 8,
      "max_length": 10,
      "looks_sensitive": true,
      "detected_date_format": "MM/DD/YY",
      "needs_interop_conversion": true
    }
  ]
}
```

When `needs_interop_conversion` is `true`, the column proposal step
flags it and the hand-off to `/DAC-upload` mentions it — so the
user knows at schema time that the source format differs from ISO.

### Script template

Write this verbatim to `./alvera-profile.py` in the user's cwd. Keep it
stdlib-only even when tempted to reach for `pandas` — the point is the
user shouldn't have to install anything.

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

# Non-ISO date patterns (checked after ISO fails, so we still classify as date)
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
        return low  # already clean — don't inject underscores
    s = re.sub(r"[^a-z0-9]+", "_", low).strip("_")
    if s and s[0].isdigit(): s = "col_" + s
    return s or "col"

def detect_date_format(vals):
    """Return the dominant non-ISO date pattern, or None."""
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
    # Non-ISO dates: still classify as "date" — the generic table stores
    # ISO, and the interop template (created by /DAC-upload) converts.
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

### Handoff to the user

After writing the script, say exactly this (substituting their actual
path):

> "Run `python3 alvera-profile.py <your-file>` and paste the JSON
> output here. I won't see the file content — only that summary. When
> you're done, you can delete `alvera-profile.py` or keep it for the
> next dataset."

When the user pastes, validate it's the expected shape (keys: `format`,
`row_count`, `columns`) before proceeding. If they paste raw rows by
mistake, stop immediately and remind them — don't read it.
