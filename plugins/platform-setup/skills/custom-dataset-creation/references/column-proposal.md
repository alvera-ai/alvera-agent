# Column proposal

After profiling, propose the full generic table in plain language. Goal:
the user can confirm / override every field without reading JSON.

## Top-level fields

| Field         | Required | Default            | How to elicit                                           |
|---------------|----------|--------------------|---------------------------------------------------------|
| `title`       | **yes**  | file basename, cleaned | Show your guess, let user accept or override            |
| `description` | no       | `""`               | Ask — don't guess                                       |
| `data_domain` | no       | `null`             | Offer enum: `healthcare \| core_banking \| payment_risk \| accounts_receivable \| service_commerce \| trading \| null` |
| `columns`     | **yes**  | —                  | From profiling, one-by-one review below                 |

`data_domain` values above are conversation hints; API is authoritative
(same rule as in `guided/references/guardrails.md` → "Enum validation").
Pass user input through on a mismatch rather than rejecting locally.

## Per column

Present every column as a compact bullet. Every field gets a best guess
the user can override with a single word.

Fields and where they come from:

| Field                 | Required | Source of best guess                                   |
|-----------------------|----------|--------------------------------------------------------|
| `name`                | **yes**  | `suggested_name` from profiling (snake_case)           |
| `title`               | no       | Title-case of `original_name` (keeps readability)      |
| `type`                | no (`string`) | `inferred_type` from profiling                   |
| `description`         | **yes**  | You draft a one-liner; user confirms/rewrites          |
| `privacy_requirement` | no (`none`) | `looks_sensitive` → `redact_only`; else `none`       |
| `is_required`         | no (`false`) | `null_rate == 0` → `true`                           |
| `is_unique`           | no (`false`) | `cardinality == "unique"` → `true`                  |
| `is_array`            | no (`false`) | NDJSON + value is array → `true`; CSV → always false |

### Name handling

- **Only propose renaming when the original has spaces or mixed
  case.** Show both and ask: *"`First Name` → `first_name` for
  simplicity?"*. The user can accept or supply an alternative.
- **Don't inject underscores into already-concatenated tokens.**
  `parapptyn` stays `parapptyn` — you don't know the user's
  abbreviation scheme and guessing word boundaries is more often
  wrong than right. Do not produce `par_appt_yn`.
- If the user pushes back and insists on a name with spaces or mixed
  case, pass it through to the API — the server is the validator.

### Type

- Trust the profiler's `inferred_type`. When the user overrides (e.g.
  "this looks like an int but I want to store it as string"), respect
  it without argument — there are legitimate reasons (leading zeros on
  zip codes, opaque IDs that look numeric).
- Enum values: `string | integer | float | boolean | date | datetime | time`.
  If the user supplies something else, pass it through — API will
  reject and we re-elicit.

### `privacy_requirement` — LOCKED AT CREATION

- Enum: `none | tokenize | redact_only`.
- Default best guess:
  - `looks_sensitive == true` → `redact_only`
  - Free-text fields with `cardinality == unique` and long max_length
    → consider `tokenize` (ask the user)
  - Otherwise → `none`
- **State clearly at confirmation time**:

  > "Heads up: `privacy_requirement` is locked at creation in the
  > current Alvera version. If you need to change it later, you'll have
  > to recreate the table. Please review these carefully now."

- Do not offer an update command for this field. If the user asks to
  change it later, the answer is "recreate the table with the new
  value".

### `is_unique` — composite, not distinct

This is the single most-misunderstood field. In Alvera, setting
`is_unique: true` on multiple columns means **the combination of those
columns is unique**, not that each column is individually unique.

Concretely:

- `first_name.is_unique = true, last_name.is_unique = true` →
  `(first_name, last_name)` must be unique across rows. Two "John Smith"
  entries would be rejected.
- `first_name.is_unique = false, last_name.is_unique = false,
  email.is_unique = true` → only `email` values must be unique across
  rows.

When your proposal marks more than one column unique, say this at
confirmation time:

> "`is_unique` in Alvera is a **composite** constraint — not per-column.
> With `first_name` and `last_name` both marked unique, the combination
> `first_name + last_name` must be distinct across rows (one "John
> Smith" max). If you wanted each column independently unique, that's
> not something this schema can express — you'd typically pick the
> single column that's actually an identity key (`email`, `member_id`)
> and mark only that one. Keep it composite or change it?"

Don't auto-fix. Let the user decide.

### `is_required`

- `null_rate == 0` in the sample → propose `true`, but note that a
  1,000-row sample isn't proof. Example: "No nulls observed in the
  sample of 1,000 — marking required. Override if some rows can legitimately
  be empty."
- Otherwise `false`.

### `is_array`

- NDJSON only. If the sampled values for a column are JSON arrays,
  `is_array: true`.
- CSV doesn't natively represent arrays — never propose `true` for CSV
  input. If the user says "but this column is comma-separated values
  inside a cell", that's a tokenisation choice they need to handle in
  interop, not a `is_array: true` on the generic table.

## Presentation

Use a compact bulleted format, one column per bullet. Not JSON.

Example:

```
Proposed table: **patients** (title "Patients", domain healthcare,
1,234 rows sampled from 50,000)

Columns:
  - first_name (string, required, redact_only) — "Patient's first name"
  - last_name  (string, required, redact_only) — "Patient's last name"
  - dob        (date,   required, redact_only) — "Date of birth"
  - mrn        (string, required, unique, tokenize) — "Medical record number"
  - email      (string, optional, redact_only) — "Contact email"

Notes:
  - `privacy_requirement` is locked at creation — review above now.
  - `first_name` and `last_name` are both unique → composite key
    (first_name + last_name). Confirm or change.
  - Original headers "First Name", "Last Name" normalised to snake_case.

Proceed? (y/n)  or  "show the full body" for JSON
```

Only print JSON when the user explicitly requests it.
