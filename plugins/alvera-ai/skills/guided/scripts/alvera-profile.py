#!/usr/bin/env python3
"""Profile a CSV or NDJSON file. Emits schema + aggregates to stdout.
Never prints row values. Stdlib only. Usage: python3 alvera-profile.py <path>"""
import codecs, csv, json, re, sys
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
    with codecs.open(str(p), encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        headers = reader.fieldnames or []
        rows = []
        for i, row in enumerate(reader):
            if i >= n: break
            rows.append(row)
        return headers, rows

def iter_ndjson(p, n):
    headers, rows = [], []
    with codecs.open(str(p), encoding="utf-8-sig") as f:
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
    with codecs.open(str(p), encoding="utf-8-sig") as f:
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
