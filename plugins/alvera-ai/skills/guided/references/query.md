# Query — Dataset Search

Search and inspect datalake data using the SDK's built-in `datasets` commands.
Purpose: verification after data activation, or ad-hoc inspection. Not a BI tool.

## Commands

```bash
alvera datasets search   <dataset> [--datalake-id <id>] [--page <n>] [--page-size <n>]
alvera datasets metadata <dataset-type> [--datalake-id <id>] [--generic-table-id <id>]
```

| Flag              | Default | Purpose                          |
|-------------------|---------|----------------------------------|
| `--datalake-id`   | from bootstrap | Scope search to a specific lake (defaults to datalake chosen at bootstrap) |
| `--page`          | 1       | Pagination page number           |
| `--page-size`     | 20      | Results per page                 |
| `--generic-table-id` | —    | For metadata on generic tables   |

## Workflow

1. **Identify the dataset** — use `alvera data-sources list` or ask the user
   which dataset they want to query.
2. **Search** — run `alvera datasets search <dataset>` and show the results.
3. **Paginate** — if more rows exist, offer to page through with `--page`.
4. **Metadata** — use `alvera datasets metadata <dataset-type>` to inspect
   schema/column info when the user needs structure, not content.

## Output

- **Stdout:** Pretty-printed JSON (rows or metadata object)
- **Stderr:** Status messages, errors (prefixed with `alvera: `)
- **Exit code:** 0 success, 1 failure

## Hard constraints

- **Read-only.** These commands never mutate data.
- **No sensitive data in conversation.** If results contain PII or PHI,
  summarize structure (column names, row count) — don't paste raw rows
  unless the user explicitly asks.
- **Pagination over bulk.** Never fetch all rows at once. Default page size
  is 20; increase only if the user requests it.

## Post-provisioning monitoring

After provisioning, use these commands to verify things are working:

| What to check | Command |
|---------------|---------|
| Data landed after DAC ingest | `alvera datasets search <dataset> --datalake-id <id>` |
| DAC processing status | `alvera data-activation-clients logs <datalake> <slug>` |
| Workflow execution history | `alvera workflows workflow-logs <slug>` |
| Batch run status | `alvera workflows batch-logs <slug>` |
| Patient identity resolution | `alvera mdm verify <datalake> --body '<json>'` |
| Platform health | `alvera ping` |

For workflow debugging, see `references/workflows.md` → "Debugging
common issues" and `references/errors.md` for error recovery.
