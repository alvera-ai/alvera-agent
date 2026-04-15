---
name: DAC-upload
description: >
  Push a sample file into a data-activation-client (DAC) for bulk ingestion.
  Three-step flow: request a presigned upload URL from Alvera
  (`alvera data-activation-clients upload-link`), PUT the file to object
  storage, then trigger processing (`alvera data-activation-clients
  ingest-file`). Supports CSV and NDJSON — the only two content types the
  API accepts. Use when the user says "upload a file to the DAC", "ingest a
  sample file", "push CSV into activation client X", or similar. Assumes the
  user already has the DAC slug (this skill does not create DACs — DAC CRUD
  isn't on the public API; the slug comes from the Alvera UI or an admin).
  Designed to be runnable right after `custom-dataset-creation`, but is
  independently invokable — does not need a prior skill in the chain.
---

# DAC upload

Three CLI calls, in order:

1. `alvera data-activation-clients upload-link <dac_slug> <filename>
   [tenant] --content-type <mime>` → returns `{ url, key, expires_in }`.
   `url` is a presigned HTTPS PUT URL (S3 / R2).
2. `curl -X PUT -H "Content-Type: <mime>" --data-binary @<file> "<url>"`
   → uploads the file to storage. The `Content-Type` header **must**
   match what was sent in step 1, or the presigned URL will reject.
3. `alvera data-activation-clients ingest-file <dac_slug> <key>
   [tenant]` → triggers processing. Returns `{ batch_id, jobs_count,
   key }`.

## Prerequisites

- `alvera` CLI reachable, active session. If not, route to `guided`.
- **DAC slug** — the user supplies it. This skill does not list or
  create DACs (the public API exposes neither). Typical source: Alvera
  admin UI, or a previous invocation of the `guided` skill wiring up
  the client.
- **File path** — CSV or NDJSON. Other formats rejected by the API
  (`content_type` enum is `text/csv | application/x-ndjson`).

## Workflow

1. **Elicit the three inputs in one prompt:**

   > "I need three things to upload:
   >   1. The **data-activation-client slug** (e.g. `acme-emr-dac`).
   >   2. The **file path** to upload (CSV or NDJSON only).
   >   3. Optional: a **tenant slug** if your profile doesn't default
   >      to the right one.
   > What are they?"

2. **Validate locally, before any API call:**
   - File exists, readable.
   - Extension is `.csv`, `.ndjson`, or `.jsonl`. Otherwise stop —
     even if the content is valid, the API enforces the enum.
   - File size: warn above 100 MiB ("this may take a while to
     upload"). Hard refuse above 2 GiB (presigned URL + server limits).
   - Map extension → content type:
     - `.csv` → `text/csv`
     - `.ndjson`, `.jsonl` → `application/x-ndjson`

3. **Confirm before calling the API.** Plain-language recap, single
   bullet list:

   > "Uploading:
   >   - file: `./patients-2026-04-13.ndjson` (48,291 lines, 12.4 MiB)
   >   - content type: `application/x-ndjson`
   >   - DAC: `acme-emr-dac`
   >   - tenant: `acme` (from profile)
   >
   > Proceed? (y/n)"

4. **Run the three-step upload** — see `references/flow.md` for the
   full scripted version (including error paths and the `curl` PUT
   handling).

5. **Report the outcome.** On success:

   > "Uploaded and queued.
   >   - key: `api-ingest/.../uploads/1a2b3c4d.ndjson`
   >   - batch_id: `550e8400-...`
   >   - jobs_count: 1
   >
   > Processing runs async server-side. To verify rows landed, run
   > `/query-datasets` and query the target table."

   On failure at any step, surface stderr verbatim. Do not retry
   automatically. Map step-specific failures to the offending input
   (wrong slug → re-ask slug; wrong content-type → check file
   extension; presigned URL rejection → likely wrong content-type
   header).

## Hard constraints

- **Content type must match.** The presigned PUT URL is signed with
  the content-type from the `upload-link` call. If the `curl` PUT
  sends a different `Content-Type` header, S3 / R2 rejects with 403.
  Use the mapped mime from step 2, verbatim, in both places.
- **Don't stream through the model.** The file goes from the user's
  disk directly to the presigned URL via `curl`. Do not `Read` the
  file into the conversation — it may contain data the user has not
  authorised for us to see (same rule as `custom-dataset-creation`'s
  compliance gate, applied here).
- **Don't log the presigned URL.** It's short-lived but still
  contains auth material. Print the `key` for reference; elide the
  query string of the URL when showing progress.
- **One file per invocation.** This skill uploads exactly one file.
  Batch runs loop the user: "another file, or done?".
- **Never persist the file** — no tempfile copying, no re-encoding.
  The file the user named is the file that's uploaded.

## References

- `references/flow.md` — the full three-step upload procedure, with
  error handling and `curl` details
- `references/example-transcript.md` — reference dialog

## Downstream

After a successful upload, the user typically wants:

- `/query-datasets` — scaffold a local PostgREST + React explorer to
  verify rows landed in the target table
