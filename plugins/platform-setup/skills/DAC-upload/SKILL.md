---
name: DAC-upload
description: >
  Push a sample file into a data-activation-client (DAC) for bulk ingestion.
  Three-step flow: request a presigned upload URL from the **datalake**
  (`alvera datalakes upload-link`), PUT the file to object storage, then
  trigger processing on the **DAC** (`alvera data-activation-clients
  ingest-file`). Upload-link is datalake-scoped (it provisions storage),
  ingest-file is DAC-scoped (it interprets the file) — the skill needs
  **both** slugs. Supports CSV and NDJSON — the only two content types the
  API accepts. Use when the user says "upload a file to the DAC", "ingest a
  sample file", "push CSV into activation client X", or similar. Assumes
  the user already has the datalake slug + DAC slug (this skill does not
  create either — DAC CRUD isn't on the public API; both slugs come from
  the Alvera UI or an admin). Designed to run right after
  `custom-dataset-creation`, but is independently invokable.
---

# DAC upload

Three CLI calls, in order. The presigned URL is provisioned by the
**datalake**; the ingest is triggered on the **DAC**. Two different
slugs.

1. `alvera datalakes upload-link <datalake_slug> <filename>
   [tenant] --content-type <mime>` → returns `{ url, key, expires_in }`.
   `url` is a presigned HTTPS PUT URL (S3 / R2).
2. `curl -X PUT -H "Content-Type: <mime>" --upload-file <file> "<url>"`
   → uploads the file to storage. The `Content-Type` header **must**
   match what was sent in step 1, or the presigned URL will reject.
3. `alvera data-activation-clients ingest-file <dac_slug> <key>
   [tenant]` → triggers processing. Returns `{ batch_id, jobs_count,
   key }`.

## Prerequisites

- `alvera` CLI reachable, active session. If not, route to `guided`.
- **Datalake slug** — for the upload-link call. From `guided`'s
  `datalakes list` or the Alvera admin UI.
- **DAC slug** — for the ingest-file call. The user supplies it; this
  skill does not list or create DACs (the public API exposes neither).
- **File path** — CSV or NDJSON. Other formats rejected by the API
  (`content_type` enum is `text/csv | application/x-ndjson`).

## Workflow

1. **Resolve the datalake slug automatically, don't elicit it blind.**
   Before asking the user anything, run:

   ```bash
   alvera --profile <p> datalakes list [tenant]
   ```

   Use the returned slug list to disambiguate any slug blob the user
   supplied. Three cases:

   - **User supplied a clearly single slug** that matches one of the
     returned datalakes exactly → that's the datalake. Move on.
   - **User supplied an ambiguous blob** like
     `prime-medical-datalake-alvera-custom-alvera-reviews-dataactivationclient`
     → find the **longest datalake slug that is a prefix** of the
     blob, with a `-` boundary. Treat the remainder as the DAC slug
     candidate. Confirm back to the user: *"I'm reading this as
     datalake `prime-medical-datalake` + DAC
     `alvera-custom-alvera-reviews-dataactivationclient`. Correct?"*
     If they say no, ask them to split explicitly.
   - **User invoked the skill with no arguments** → list datalakes,
     present them as options if more than one, pick the one on `1`,
     then elicit the DAC slug + file + optional tenant.

   As of SDK 0.2.5, DAC CRUD is now public. After resolving the
   datalake, **also list DACs** to validate the DAC slug:

   ```bash
   alvera --profile <p> data-activation-clients list <datalake> [tenant]
   ```

   Match against the returned slugs. If the DAC slug doesn't match
   any, tell the user and list what's available.

2. **Elicit remaining fields in a single prompt** — whatever step 1
   didn't resolve:

   > "I've got:
   >   - datalake: `prime-medical-datalake` (resolved from your input)
   >   - DAC: `alvera-custom-alvera-reviews-dataactivationclient`
   >     (tentative — no API to validate)
   >
   > Still need:
   >   - **File path** (CSV, NDJSON, or JSONL).
   >   - Optional: **tenant slug** if your profile doesn't default to
   >     the right one."

   If the user already passed the file and tenant, skip the prompt
   and go straight to confirmation.

3. **Validate locally, before any API call:**
   - File exists, readable.
   - Extension is `.csv`, `.ndjson`, or `.jsonl`. Otherwise stop —
     even if the content is valid, the API enforces the enum.
   - File size: warn above 100 MiB ("this may take a while to
     upload"). Hard refuse above 2 GiB (presigned URL + server limits).
   - Map extension → content type:
     - `.csv` → `text/csv`
     - `.ndjson`, `.jsonl` → `application/x-ndjson`

4. **Confirm before calling the API.** Plain-language recap, single
   bullet list:

   > "Uploading:
   >   - file: `./patients-2026-04-13.ndjson` (48,291 lines, 12.4 MiB)
   >   - content type: `application/x-ndjson`
   >   - datalake: `prime-medical-datalake` (issues the presigned URL)
   >   - DAC: `acme-emr-dac` (triggers ingest after upload)
   >   - tenant: `acme` (from profile)
   >
   > Proceed? (y/n)"

5. **Run the three-step upload** — see `references/flow.md` for the
   full scripted version (including error paths and the `curl` PUT
   handling).

6. **Report the outcome.** On success:

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

## Stance: be proactive

Assume the user wants to upload. Default to the forward path and
confirm with yes/no. When inputs are resolved and the confirmation
is yes, move immediately — don't re-ask.

## Hard constraints

- **Auto-list datalakes before asking.** Run `alvera datalakes list
  [tenant]` at the start of the flow and use the result to
  disambiguate any slug blob the user supplied. Don't ask the user to
  manually split `prime-medical-datalake-alvera-custom-...` when the
  datalake list would have shown `prime-medical-datalake` immediately.
- **Auto-list DACs too** (SDK ≥ 0.2.5). DAC CRUD is now public.
  After resolving the datalake slug, run
  `alvera data-activation-clients list <datalake>` and validate the
  DAC slug against the returned slugs. If no match, list what's
  available and re-ask.
- **Content type must match.** The presigned PUT URL is signed with
  the content-type from the `upload-link` call. If the `curl` PUT
  sends a different `Content-Type` header, S3 / R2 rejects with 403.
  Use the mapped mime from step 3, verbatim, in both places.
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
