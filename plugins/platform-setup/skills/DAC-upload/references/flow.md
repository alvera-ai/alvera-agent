# Pipeline flow

Full ingestion pipeline — from file inspection through sandbox test to
upload. Each step has a non-retryable failure mode — surface the error
and stop, don't paper over.

## Step 0 — resolve datalake slug

```bash
alvera --profile <p> datalakes list [tenant]
```

Use the returned slugs to disambiguate whatever the user passed:

- **Exact match** → use it.
- **Ambiguous blob** (e.g.
  `prime-medical-datalake-alvera-custom-alvera-reviews-dataactivationclient`)
  → find the **longest** datalake slug that is a prefix of the blob
  with a `-` boundary. Treat the remainder as the candidate DAC slug.
  Confirm back to the user.
- **Nothing supplied** → list the datalakes, present them (numbered if
  more than one), let the user pick.

## Step 1 — resolve DAC

```bash
alvera --profile <p> data-activation-clients list <datalake> [tenant]
```

Match the user's slug against the returned list. If no match, show
what's available. If no DACs exist, move to step 1b.

### Step 1b — create a DAC (when needed)

Requires a tool (`intent: data_exchange`) and a data source. Auto-detect:

```bash
alvera --profile <p> tools list [tenant]
alvera --profile <p> data-sources list <datalake> [tenant]
```

Pick the first tool with `intent: data_exchange` and the first (or
only) data source. If neither exists, hand off to `guided` — DAC-upload
does not create these.

Defer the actual `data-activation-clients create` until after the
interop contract is resolved (step 3), because the DAC payload needs
`interoperability_contract_ids`.

```bash
alvera --profile <p> data-activation-clients create <datalake> [tenant] \
  --body-file <path>
```

Body shape:

```json
{
  "name": "<user-provided>",
  "description": "<user-provided>",
  "tool_id": "<auto-detected>",
  "data_source_id": "<auto-detected>",
  "tool_call": { "tool_call_type": "manual_upload" },
  "interoperability_contract_ids": ["<from step 3>"]
}
```

## Step 2 — inspect the file

Two sub-steps. Neither sends data values to the model.

### 2a — read headers

```bash
# CSV
head -n 1 <file>
# → patient_id,first_name,last_name,dob,gender,phone,source_uri

# NDJSON
head -n 1 <file> | python3 -c "import sys,json; print(list(json.load(sys.stdin).keys()))"
# → ['patient_id', 'first_name', 'last_name', 'dob', 'gender']
```

Parse the column names. These are metadata, not data.

### 2b — anti-pattern scan

Run the scanner script from `anti-patterns.md`. It reads the first 100
rows from the file and outputs a JSON pattern summary. The model reads
the summary — never the raw data.

```bash
python3 /tmp/alvera-scan.py <file>
```

Output example:

```json
{
  "row_count": 1247,
  "columns": {
    "dob": {
      "non_null": 1244,
      "detected_format": "MM/DD/YY",
      "sample_formats": ["03/15/60", "11/02/85"],
      "needs_fix": true
    },
    "gender": {
      "non_null": 1247,
      "unique_values": ["Male", "Female", "Other"],
      "needs_downcase": true
    },
    "appt_status": {
      "non_null": 1247,
      "unique_values": ["Scheduled", "Completed", "Cancelled", "No-Show"],
      "needs_mapping": true
    }
  }
}
```

Surface the findings to the user as a compact summary:

> Anti-pattern scan (first 100 rows of 1,247):
>   - `dob`: dates in MM/DD/YY format → will convert to YYYY-MM-DD in
>     the interop template
>   - `gender`: values are capitalised (Male, Female, Other) → will
>     `| downcase` in the template
>   - `appt_status`: needs mapping (Scheduled → booked, Completed →
>     fulfilled, Cancelled → cancelled)

## Step 3 — resolve or create interop contract

### 3a — DAC already has contracts

```bash
alvera --profile <p> interop get <datalake> <contract-slug> [tenant]
```

Inspect the `template_config.body`. Check:
- Every `{{ msg.X }}` reference has a matching column in the file
- Anti-patterns detected in step 2 are handled by the template (look
  for date-conversion logic, `| downcase`, status mapping)

If the template is missing fixes for detected anti-patterns, warn:

> The contract `emr-patient-transform` passes `{{ msg.dob }}` through
> unchanged, but your file has dates in MM/DD/YY format. Update the
> template to convert? (y/n)

Then update via `alvera interop update <datalake> <slug> --body-file`.

### 3b — no contract (create one)

Ask for `resource_type` if not known. Fetch field metadata:

```bash
alvera --profile <p> interop metadata <datalake> <contract-slug> [tenant]
```

If no contract exists to query metadata from, create a disposable
identity contract first (it can be updated later):

```bash
alvera --profile <p> interop create <datalake> [tenant] --body '{
  "name": "<resource_type> identity",
  "resource_type": "<resource_type>",
  "template_config": {"type": "identity"},
  "mdm_input_config": {"type": "identity"}
}'
```

Generate the Liquid template — see `templates.md` for the mapping
rules and common patterns. Present the mapping as a table for
confirmation, then update/create:

```bash
alvera --profile <p> interop update <datalake> <slug> [tenant] \
  --body-file <path>
```

If creating a new DAC (step 1b was deferred), create it now:

```bash
alvera --profile <p> data-activation-clients create <datalake> [tenant] \
  --body-file <path>
```

## Step 4 — sandbox test

Run one sample row through the contract pipeline without DB writes.
The row goes from disk directly to the CLI — the model sees only the
pipeline output.

```bash
# CSV — convert first data row to JSON, pipe to interop run
head -n 2 <file> | python3 -c "
import csv, json, sys
r = csv.DictReader(sys.stdin)
print(json.dumps(next(r)))
" | alvera --profile <p> interop run <datalake> <contract-slug> [tenant] \
    --body-file -

# NDJSON — first line is already JSON
head -n 1 <file> | alvera --profile <p> interop run <datalake> <contract-slug> [tenant] \
    --body-file -
```

Interpret the response:

| `stage` | `filter_result` | Meaning | Action |
|---------|----------------|---------|--------|
| `completed` | `pass` | Pipeline works | Show `transformed` + `mdm_input`, proceed |
| `filtered` | `skip` | Row was filtered out | Warn — filter may be too aggressive |
| Error pointers in response | — | Template bug | Surface the failing pointer, fix, re-test |

Error pointers map to template stages:
- `/data_activation_client_filter` → filter template error
- `/template_config/body` → transform template error
- `/mdm_input_config/body` → MDM input template error

On success, show the user the transformed output (this is FHIR-shaped
output, not source data — safe to display).

## Step 5 — request a presigned URL (datalake-scoped)

```bash
alvera --profile <p> datalakes upload-link \
  <datalake_slug> <filename> [tenant] \
  --content-type <mime>
```

Inputs:
- `<datalake_slug>` — the datalake whose object storage receives the file
- `<filename>` — basename of the local file (e.g. `patients.ndjson`)
- `<mime>` — `text/csv` or `application/x-ndjson`

Map extension → content type:
- `.csv` → `text/csv`
- `.ndjson`, `.jsonl` → `application/x-ndjson`

Stdout (JSON):

```json
{
  "url": "https://<bucket>.r2.cloudflarestorage.com/...",
  "key": "api-ingest/<tenant_id>/uploads/<rand>.ndjson",
  "expires_in": 3600
}
```

Parse `url` and `key`. Tell the user **only** the `key`.

## Step 6 — PUT the file

```bash
curl --fail --show-error --silent \
  -X PUT \
  -H "Content-Type: <mime>" \
  --upload-file "<local_path>" \
  "<url>"
```

Notes:
- `Content-Type` header **must** match the mime from step 5. Mismatch →
  `403 SignatureDoesNotMatch`.
- `--fail` makes curl exit non-zero on 4xx/5xx.
- Do not use `curl -d @file` or `--data-binary @file` without `-X PUT`.

Failure modes:
- `403 SignatureDoesNotMatch` → content-type mismatch
- `403 RequestTimeTooSkewed` → user's clock drifted
- Expired URL → start over from step 5

## Step 7 — trigger processing

```bash
alvera --profile <p> data-activation-clients ingest-file \
  <datalake_slug> <dac_slug> <key> [tenant]
```

`<key>` is from step 5 — pass verbatim. `<datalake_slug>` is required
(DACs are datalake-scoped in the CLI).

Stdout (JSON):

```json
{
  "batch_id": "550e8400-e29b-41d4-a716-446655440000",
  "jobs_count": 1,
  "key": "api-ingest/<tenant_id>/uploads/<rand>.ndjson"
}
```

Report `batch_id` and `jobs_count`. Point to `/query-datasets`.

## Full scripted version

```bash
set -e
PROFILE=default
DATALAKE=prime-medical-datalake
DAC=emr-patient-ingest
FILE=./patients-2026-04-13.csv
TENANT=acme

case "$FILE" in
  *.csv)           CT=text/csv ;;
  *.ndjson|*.jsonl) CT=application/x-ndjson ;;
  *) echo "unsupported extension" >&2; exit 2 ;;
esac

FILENAME=$(basename "$FILE")

# Step 5 — presigned URL
LINK_JSON=$(alvera --profile "$PROFILE" datalakes upload-link \
  "$DATALAKE" "$FILENAME" "$TENANT" --content-type "$CT")

URL=$(printf '%s' "$LINK_JSON" | python3 -c 'import sys,json; print(json.load(sys.stdin)["url"])')
KEY=$(printf '%s' "$LINK_JSON" | python3 -c 'import sys,json; print(json.load(sys.stdin)["key"])')

# Step 6 — PUT
curl --fail --show-error --silent \
  -X PUT \
  -H "Content-Type: $CT" \
  --upload-file "$FILE" \
  "$URL"

# Step 7 — trigger processing (note: datalake slug is first positional arg)
alvera --profile "$PROFILE" data-activation-clients ingest-file \
  "$DATALAKE" "$DAC" "$KEY" "$TENANT"
```
