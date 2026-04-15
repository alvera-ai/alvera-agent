# Upload flow

Three steps, in order. Each step has a non-retryable failure mode —
surface the error to the user and stop, don't paper over.

## Step 1 — request a presigned URL (datalake-scoped)

```bash
alvera --profile <p> datalakes upload-link \
  <datalake_slug> <filename> [tenant] \
  --content-type <mime>
```

Upload provisioning is a datalake concern (the storage belongs to the
lake); ingestion (step 3) is a DAC concern (the DAC interprets the
file). Two different slugs.

Inputs:
- `<datalake_slug>` — the datalake whose object storage receives the
  file. From `alvera datalakes list` or `guided`'s session state.
- `<filename>` — basename of the local file (e.g. `patients.ndjson`).
  Used server-side to derive the object's extension.
- `<mime>` — `text/csv` or `application/x-ndjson`. Must match the
  local file's actual format; the server trusts the header for
  routing.

Stdout (JSON):

```json
{
  "url": "https://<bucket>.r2.cloudflarestorage.com/api-ingest/<tenant_id>/uploads/<rand>.ndjson?X-Amz-Signature=...",
  "key": "api-ingest/<tenant_id>/uploads/<rand>.ndjson",
  "expires_in": 3600
}
```

Parse `url` and `key` from stdout. Tell the user **only** the `key`
(the URL contains a signed auth token). If the skill needs to echo
progress that references the URL, elide the query string.

Failure modes:
- Non-zero exit / 4xx → surface stderr verbatim. Common: wrong DAC
  slug (`not found`), wrong content_type enum.
- Hang > 30s → very likely a network issue on the user's side. Tell
  them and stop.

## Step 2 — PUT the file to the presigned URL

```bash
curl --fail --show-error --silent \
  -X PUT \
  -H "Content-Type: <mime>" \
  --upload-file "<local_path>" \
  "<url>"
```

Notes:
- `--upload-file` is `-T` equivalent; it streams the file — no full
  read into memory. Important for large NDJSON.
- `Content-Type` header value **must** equal the mime from step 1
  verbatim. Mismatch → S3 / R2 rejects with `403 SignatureDoesNotMatch`
  or `Content-Type header value does not match presigned request`.
- `--fail` makes `curl` exit non-zero on 4xx / 5xx so we can detect
  failure (otherwise `curl` happily treats HTTP errors as "the
  request succeeded, here's an error body").

Do not use `curl -d @file` (not a PUT body streamer) or
`curl --data-binary @file` without `-X PUT` — behaves differently
around Content-Type and Expect headers.

Failure modes:
- `403 SignatureDoesNotMatch` → content-type header mismatch most
  likely.
- `403 RequestTimeTooSkewed` → the user's clock drifted. Tell them.
- `MalformedPOSTRequest` → check you're using PUT not POST.
- Expired URL → rare (`expires_in` is typically 3600s). Start over
  from step 1.

On any non-zero exit, surface stderr and stop. Do not retry — a failed
PUT may have partial data server-side depending on the bucket policy.

## Step 3 — trigger processing

```bash
alvera --profile <p> data-activation-clients ingest-file \
  <dac_slug> <key> [tenant]
```

`<key>` is the value parsed from step 1's response — pass it verbatim.
Do not construct it yourself.

Stdout (JSON):

```json
{
  "batch_id": "550e8400-e29b-41d4-a716-446655440000",
  "jobs_count": 1,
  "key": "api-ingest/<tenant_id>/uploads/<rand>.ndjson"
}
```

Print `batch_id` and `jobs_count` back to the user. `jobs_count` is
the number of processing jobs created — usually 1 per file, more for
chunked bulk uploads.

Failure modes:
- `not found` on key → the PUT in step 2 probably silently failed
  despite curl exit 0. Re-run step 2 with `--verbose` to inspect.
- `already processed` → same key was submitted twice. Ignore or ask.
- Any schema-level validation error (columns don't match the target
  table) will appear **asynchronously** — not in this response.
  Surface the batch_id + `/query-datasets` hint so the user can check
  rows landed.

## Full scripted version

```bash
set -e
PROFILE=default
DATALAKE=prime-medical-datalake
DAC=acme-emr-dac
FILE=./patients-2026-04-13.ndjson
TENANT=acme

case "$FILE" in
  *.csv)           CT=text/csv ;;
  *.ndjson|*.jsonl) CT=application/x-ndjson ;;
  *) echo "unsupported extension" >&2; exit 2 ;;
esac

FILENAME=$(basename "$FILE")

# Step 1 — ask the datalake for a presigned upload URL.
LINK_JSON=$(alvera --profile "$PROFILE" datalakes upload-link \
  "$DATALAKE" "$FILENAME" "$TENANT" --content-type "$CT")

URL=$(printf '%s' "$LINK_JSON" | python3 -c 'import sys,json; print(json.load(sys.stdin)["url"])')
KEY=$(printf '%s' "$LINK_JSON" | python3 -c 'import sys,json; print(json.load(sys.stdin)["key"])')

# Step 2 — PUT the file to that presigned URL.
curl --fail --show-error --silent \
  -X PUT \
  -H "Content-Type: $CT" \
  --upload-file "$FILE" \
  "$URL"

# Step 3 — tell the DAC to ingest the uploaded key.
alvera --profile "$PROFILE" data-activation-clients ingest-file \
  "$DAC" "$KEY" "$TENANT"
```

Use `python3` (not `jq`) for the JSON parse so we don't assume a
third-party CLI is installed. Python is already a prereq for the
`custom-dataset-creation` profiler.

Two slugs in play:
- `$DATALAKE` (e.g. `prime-medical-datalake`) — used in step 1, names
  the storage container that issues the presigned URL.
- `$DAC` (e.g. `acme-emr-dac`) — used in step 3, names the activation
  client that interprets the file.

These can be different (one datalake, many DACs is the common shape).
Surface both clearly in the user-facing recap so a wrong slug error
maps to the right field.
