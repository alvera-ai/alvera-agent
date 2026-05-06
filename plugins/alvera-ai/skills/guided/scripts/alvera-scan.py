#!/usr/bin/env python3
"""Anti-pattern scanner. Outputs pattern summary as JSON.
Reads only the first MAX_ROWS rows. Never prints raw data values."""

import codecs, csv, json, re, sys
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
    with codecs.open(path, encoding="utf-8-sig") as f:
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
    with codecs.open(path, encoding="utf-8-sig") as f:
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
