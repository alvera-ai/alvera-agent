---
name: DAC-upload
description: >
  End-to-end data ingestion through a data-activation-client (DAC). Goes
  beyond raw file upload: auto-resolves prerequisites (datalake, DAC,
  interop contract), inspects file headers and sample-row patterns to
  detect data-quality anti-patterns (MM/DD/YY dates, un-normalised gender,
  missing identifiers), auto-generates a Liquid interop template when the
  source schema doesn't match the FHIR target, sandbox-tests the pipeline
  against a sample row, then executes the three-step presigned upload.
  Designed for a hands-off experience: user provides a file and
  (optionally) a target resource type — the skill handles the rest.
  Supports CSV and NDJSON. Use when the user says "upload a file to the
  DAC", "ingest data", "push CSV into activation client X", or similar.
---

# DAC upload

End-to-end ingestion pipeline. The user drops a file; the skill resolves
prerequisites, checks data quality, builds/validates the interop
template, sandbox-tests one row, then uploads the whole file.

```
file → inspect → anti-pattern scan → resolve/create interop contract
     → sandbox test → presigned upload → ingest-file → verify
```

## Prerequisites

- `alvera` CLI reachable, active session. If not, route to `guided`.
- **File path** — CSV (`.csv`) or NDJSON (`.ndjson` / `.jsonl`).
- A **data source** and **tool** (intent `data_exchange`) must exist on
  the datalake. The skill checks; if missing, it hands off to `guided`
  (DAC-upload does not create data sources or tools).

## Workflow

1. **Resolve datalake** — `alvera datalakes list [tenant]`.
   Disambiguate any slug blob the user supplied (exact match,
   longest-prefix with `-` boundary, or pick from list). Same rules as
   before — see `references/flow.md` step 0.

2. **Resolve DAC** — `alvera data-activation-clients list <datalake>`.

   | Case | Action |
   |------|--------|
   | User supplied slug, matches list | Use it |
   | User supplied slug, no match | Show available, re-ask |
   | No slug, one DAC exists | Propose it |
   | No slug, multiple DACs | List and ask |
   | No DAC exists | Offer to create one (step 2b) |

   **2b — Create a DAC** (when none exists or user wants a new one):
   - Auto-detect tool (`alvera tools list`) — pick the first with
     `intent: data_exchange`. If none, hand off to `guided`.
   - Auto-detect data source (`alvera data-sources list <datalake>`).
     If none, hand off to `guided`.
   - Elicit **name** and **description** only (everything else is
     auto-resolved or set after the interop contract is created in
     step 4).
   - `tool_call_type`: always `manual_upload` for file ingest.
   - The DAC is created after the interop contract (step 4), because it
     needs `interoperability_contract_ids`.

3. **Inspect the file** — two sub-steps, neither sends data values to
   the model:

   a. **Read headers only** — column names are not data:
      - CSV: `head -n 1 <file>` → parse column names
      - NDJSON: `head -n 1 <file>` → parse JSON keys

   b. **Run the anti-pattern scanner** — a local Python script that
      reads the first 100 rows and outputs a pattern summary (date
      formats, value distributions for enum-like fields). The model
      sees patterns and category labels, never individual row values.
      See `references/anti-patterns.md` for the script template.

4. **Resolve or create interop contract:**

   a. **DAC already has contracts** — fetch each via
      `alvera interop get <datalake> <slug>`. Cross-check the
      template's `{{ msg.X }}` references against the file's columns.
      If columns mismatch, warn. If anti-patterns were detected (e.g.
      date format), check whether the template already handles them
      (look for date-conversion Liquid logic). If not, offer to update
      the contract.

   b. **No contract, or user wants a new one** — auto-generate:
      - Ask for `resource_type` if not already known (patient,
        appointment, etc.)
      - Fetch target field metadata:
        `alvera interop metadata <datalake> <any-contract-slug>`
        (or create a disposable identity contract to get metadata)
      - Map file columns → FHIR fields. Present the proposed mapping
        as a plain-language table:

        ```
        Source column   → FHIR field        Transform
        ─────────────────────────────────────────────────
        patient_id      → identifier[0]     system: urn:<ds-uri>
        first_name      → name[0].given[0]  —
        last_name       → name[0].family    —
        dob             → birth_date        MM/DD/YY → YYYY-MM-DD
        gender          → gender            | downcase
        ```

      - Apply anti-pattern fixes as Liquid transforms in the template
        (see `references/templates.md` for snippets).
      - Confirm the mapping with the user, then create:
        `alvera interop create <datalake> --body-file <path>`

   If creating a new DAC (step 2b), create it now with the contract id.

5. **Sandbox test** — run one sample row through the contract pipeline
   without writing to the DB:

   ```bash
   # CSV — extract first data row as JSON, pipe directly to CLI
   head -n 2 <file> | python3 -c "
   import csv, json, sys
   r = csv.DictReader(sys.stdin)
   print(json.dumps(next(r)))
   " | alvera interop run <datalake> <contract-slug> --body-file -

   # NDJSON — first line is already JSON
   head -n 1 <file> | alvera interop run <datalake> <contract> --body-file -
   ```

   The sample row goes from disk to CLI — the model sees only the
   pipeline output (`transformed`, `mdm_input`, `filter_result`).

   - `stage: "completed"` → show the transformed output, proceed
   - `stage: "filtered"` → row was filtered — warn (the filter may be
     too aggressive for the data)
   - Error pointers in response → the template has a bug. Surface which
     stage failed (`/template_config/body`, `/mdm_input_config/body`,
     or `/data_activation_client_filter`), fix, and re-test

6. **Confirm and upload** — plain-language recap:

   > Uploading:
   >   - file: `./patients.csv` (12,431 rows, 2.1 MiB)
   >   - content type: `text/csv`
   >   - datalake: `prime-medical-datalake`
   >   - DAC: `emr-patient-ingest` (manual_upload)
   >   - contract: `emr-patient-transform` (patient, custom template)
   >   - anti-patterns fixed: dob (MM/DD/YY → YYYY-MM-DD), gender (downcase)
   >   - sandbox test: passed
   >
   > Proceed? (y/n)

   Then execute the three-step upload — see `references/flow.md`.

7. **Report outcome:**

   > Uploaded and queued.
   >   - key: `api-ingest/.../uploads/1a2b3c4d.csv`
   >   - batch_id: `550e8400-...`
   >   - jobs_count: 1
   >
   > Processing runs async. To verify rows landed, run
   > `/query-datasets` and query the target table.

   On failure at any step, surface stderr verbatim. Map step-specific
   failures to the offending input. Do not retry automatically.

## Stance: be proactive

Assume the user wants to upload. Default to the forward path:
- Resolve everything you can before asking.
- When only one option exists (one datalake, one DAC, one tool), use it.
- Anti-pattern scan runs automatically — don't ask permission.
- Template generation proposes a mapping — user confirms with y/n.
- Sandbox test runs automatically — don't ask permission.
- When all inputs are resolved and confirmation is yes, move immediately.

## Hard constraints

- **Anti-pattern scan is non-negotiable.** Always run the scanner. Date
  format mismatches silently corrupt data downstream — a `03/15/60`
  stored as-is in a `birth_date` field is useless for age calculations.
- **Sandbox test before first live ingest.** Never skip the sandbox test
  on the first upload through a new or modified contract. Skip only on
  repeat uploads through a previously-validated contract (user can opt
  out: "skip sandbox").
- **Fixes go in the template, not the file.** Don't ask the user to
  reformat their CSV. The Liquid template handles normalisation (date
  conversion, case folding, status mapping).
- **Don't stream data through the model.** File goes from disk to
  presigned URL via `curl`. Headers are OK to read (column names, not
  data). For sample-row analysis, pipe directly to CLI / scanner — the
  model sees only the output summary, never raw data values.
- **Don't log the presigned URL.** Print the `key` for reference; elide
  the query string.
- **Content-type must match.** Presigned URL is signed with the
  content-type from `upload-link`. The `curl` PUT must send the same
  header, or S3/R2 rejects with 403.
- **One file per invocation.** Batch = loop: "another file, or done?"
- **Never persist the file.** No tempfile copying, no re-encoding.

## References

- `references/flow.md` — full pipeline procedure with CLI commands
- `references/anti-patterns.md` — data quality patterns and scanner
- `references/templates.md` — Liquid template generation and common
  patterns
- `references/example-transcript.md` — reference dialogs

## Downstream

After a successful upload:
- `/query-datasets` — scaffold a PostgREST + React explorer to verify
  rows landed in the target table
