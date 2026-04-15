---
name: custom-dataset-creation
description: >
  Conversationally create a custom dataset (generic table) on an existing Alvera
  datalake by analysing a sample file. Handles the full flow — a compliance gate
  (dummy vs real vs regulated), local column profiling (python stdlib only),
  plain-language column proposal (name, type, privacy_requirement,
  is_required/unique/array, description), explicit user review, then
  `alvera generic-tables create`. Supports CSV and NDJSON sample files. Use when
  the user says "create a generic table", "define a custom dataset", "onboard a
  new table from this file", "add a custom table", or similar. Assumes an
  `alvera` session and a target datalake already exist — if not, route the user
  to the `guided` skill first. Does NOT handle data activation client CRUD,
  interop mappings, or runtime ingest (activation-client CRUD and interop aren't
  exposed on the public API; runtime ingest is out of scope for a setup skill).
---

# Custom dataset creation

Onboard a custom dataset (generic table) to an existing datalake by
analysing a sample file, proposing a schema, getting explicit
confirmation, then creating it via `alvera generic-tables create`.
Output is a row appended to `infra.yaml`.

## Prerequisites

- `alvera` CLI reachable, and an active session for the target tenant.
  If `alvera --profile <p> whoami` shows `hasSessionToken: false`, route
  the user to the `guided` skill — it handles install, login, and
  datalake selection. Don't re-implement bootstrap here.
- Target datalake slug known. If the user hasn't picked one, run
  `alvera --profile <p> datalakes list <tenant>` and confirm.
- A sample file: **CSV or NDJSON**. Other formats (xlsx, parquet,
  fixed-width) are not supported yet — say so and stop.

## Workflow

1. **Compliance gate — one question, three choices.** Before touching
   the file, ask exactly this:

   > "Is this sample file **(a) dummy / synthetic**, **(b) real data
   > you're OK sharing with me**, or **(c) real data I must not see**
   > (PHI / PII under HIPAA, or covered by a BAA)? With (a) or (b) I'll
   > read the file directly; with (c) I'll generate a local Python
   > script for you to run, and only the column shape comes back to me
   > — never row values."

   Don't split this into two turns. Don't default. Don't infer. If the
   user is ambiguous, treat it as (c). Full rules:
   `references/file-analysis.md`.

2. **Profile columns.**
   - (a) / (b) → skill reads the file via `Read` and profiles inline.
   - (c) → skill writes `./alvera-profile.py` (stdlib only, no pip), the
     user runs it, pastes the JSON summary back. No row values cross
     the boundary.

   Details and the script: `references/file-analysis.md`.

3. **Propose the generic table**, in plain language — not JSON:
   - `title` (default = file basename, cleaned).
   - `description` (ask, don't guess).
   - `data_domain` (optional — list the enum).
   - Column list, one bullet per column, with best guesses for:
     `name`, `title`, `type`, `description`, `privacy_requirement`,
     `is_required`, `is_unique`, `is_array`.
   - Flag columns whose original header has spaces / mixed case and
     propose `snake_case` (`First Name` → `first_name`). Ask the user
     to accept or override.
   - **State explicitly that `privacy_requirement` is locked at
     creation** — changing it later means recreating the table.
   - If multiple columns get `is_unique: true`, surface it as a
     **composite** constraint: "`first_name + last_name` together form
     a unique key — not each column individually. Confirm that's what
     you want."

   Full rules: `references/column-proposal.md`.

4. **Explicit confirmation.** Compact bullet recap, no JSON. Ask
   "Proceed? (y/n)". Only show JSON if the user asks ("show the full
   body").

5. **List before create.** `alvera --profile <p> generic-tables list
   <datalake> [tenant]` — if the title collides, stop and ask (update
   / rename / skip). Never auto-upsert.

6. **Create.** Write body to `/tmp/gt-<slug>.json`, `chmod 600`, then:

   ```bash
   alvera --profile <p> generic-tables create <datalake> [tenant] \
     --body-file /tmp/gt-<slug>.json
   ```

   `rm` the tempfile immediately on return — success or failure. Treat
   any non-zero exit as authoritative: surface stderr verbatim, map it
   back to the offending field, re-elicit only that field. Do not
   retry the same payload.

7. **Append to `infra.yaml`** under `generic_tables:` — only on 2xx.
   Schema: `references/create.md`.

## Hard constraints

- **Compliance gate is non-negotiable.** If the user picks (c), do not
  read the file, do not ask for "just a few sample rows", do not echo
  anything that could contain row values. Only schema-level aggregates
  (column names, inferred types, null rate, cardinality bucket) cross
  the boundary.
- **Privacy is locked at creation.** No update flow for
  `privacy_requirement`. Warn at confirmation time.
- **`is_unique` is composite, not distinct.** Any time more than one
  column has it, state the combined-key semantics explicitly and
  confirm.
- **No silent upsert.** Always `list` before `create`.
- **Tempfile hygiene.** `chmod 600`, `rm` on return regardless of exit
  code. Never inline the body via `--body '<json>'` (stays out of shell
  history even if no secrets today — habit matters).
- **Structural validation stays client-side** (column count ≥ 1,
  `name` is snake_case, `type` is in the enum). Enum drift and
  cross-field rules are API-authoritative — surface 4xx verbatim and
  re-elicit.

## References

- `references/file-analysis.md` — compliance gate + profiling (both paths), script template
- `references/column-proposal.md` — per-field elicitation and type inference
- `references/create.md` — CLI call, body shape, YAML receipt append
- `references/example-transcript.md` — reference end-to-end dialog
