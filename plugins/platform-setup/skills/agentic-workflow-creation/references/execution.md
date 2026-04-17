# Execution and debugging

Two execution endpoints with different scopes. Use `/execute` for
iterating on action templates; use `/run-workflow` for full pipeline
validation.

## Execute vs run-workflow

| | `/execute` | `/run-workflow` |
|---|---|---|
| **Scope** | Single action, one record | Bulk, SQL-filtered records |
| **Filter evaluated?** | No | Yes |
| **Decision evaluated?** | No (you supply `decision_key`) | Yes |
| **Runtime filter?** | Yes | Yes |
| **Trigger template?** | Yes | Yes |
| **Idempotency?** | Yes (unless `manual_override`) | Yes (unless `manual_override`) |
| **When to use** | Iterating on action templates | Validating the full pipeline |

## Single-action execution

```bash
alvera --profile <p> workflows execute <slug> [tenant] \
  --body '{"dataset_id":"<uuid>","decision_key":"<key>","mode":"dry_run"}'
```

| Field | Required | Description |
|-------|----------|-------------|
| `dataset_id` | yes | UUID of the record (appointment, patient, etc.) |
| `decision_key` | yes | Which action to execute |
| `mode` | no | `live` (default) or `dry_run` |
| `manual_override` | no | `true` to bypass idempotency |

Response:

```json
{
  "workflow_execution_log_id": "uuid",
  "status": "pending",
  "scheduled_count": 1
}
```

- `scheduled_count: 1` → action was scheduled
- `scheduled_count: 0` → decision_key didn't match, or runtime_filter
  rejected

## Bulk workflow run

```bash
alvera --profile <p> workflows run <slug> [tenant] \
  --body '{"sql_where_clause":"<where>","mode":"dry_run"}'
```

| Field | Required | Description |
|-------|----------|-------------|
| `sql_where_clause` | yes | SQL WHERE to select records |
| `mode` | no | `live` or `dry_run` |
| `manual_override` | no | `true` to bypass dedup |

Response:

```json
{
  "enqueued_count": 1,
  "batch_id": "manual:uuid",
  "workflow_run_log_id": "uuid"
}
```

### SQL WHERE clause patterns

```sql
-- By regulated identifier (EMR ID)
ri.value = 'EMR-APPT-12345'

-- By public UUID
a.id = 'uuid-of-appointment'

-- Multiple records
ri.value IN ('appt-001', 'appt-002')

-- Date range
a.start >= '2026-04-01' AND a.start < '2026-04-17'

-- Single record for testing
1=1 LIMIT 1

-- All records (use with caution)
1=1
```

For `patient` datasets, use `p.id` or `ri.value` instead of `a.*`.

## Checking execution logs

### Workflow execution logs (per-event)

```bash
alvera --profile <p> workflows workflow-logs <slug> [tenant]
alvera --profile <p> workflows workflow-log <slug> <id> [tenant]
```

Key fields:

| Field | Description |
|-------|-------------|
| `status` | `filtered`, `pending`, `executing`, `completed`, `failed`, `partial` |
| `mode` | `live` or `dry_run` |
| `filter_result` | What the filter evaluated to |
| `filter_expression` | Rendered filter template (debugging) |
| `error_message` | Error details if failed |

### Status meanings

| Status | What happened | Next step |
|--------|--------------|-----------|
| `filtered` | `filter_config` rejected (output was not `"true"`) | Check filter logic; maybe pick a record that should pass |
| `pending` | Queued, not yet processed | Wait |
| `executing` | Currently running | Wait |
| `completed` | All actions finished | Ready to promote |
| `failed` | Error in execution | Read `error_message`, fix template |
| `partial` | Some actions ok, some failed | Check individual action logs |

### Action execution logs (nested)

Inside each workflow execution log, individual action results:

| AEL status | Meaning |
|------------|---------|
| `completed` | Action executed successfully |
| `skipped` | Runtime filter rejected, or idempotency dedup |
| `scheduled` | Scheduled for future execution (trigger_template) |
| `failed` | Tool call error |

When `skipped`, check `runtime_filter_result`:
- `false` → runtime_filter template didn't output `"true"`
- Look at which guard failed: phone missing? prior message? status?

### Batch run logs

```bash
alvera --profile <p> workflows batch-logs <slug> [tenant]
alvera --profile <p> workflows batch-log <slug> <id> [tenant]
alvera --profile <p> workflows batch-log-refresh <slug> <id> [tenant]
```

### Download execution context

```bash
alvera --profile <p> workflows workflow-log-download <slug> <id> [tenant]
```

Returns the full JSON context available during execution — useful for
debugging Liquid template rendering.

## Debugging common issues

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| WEL status `filtered` | `filter_config` didn't output `"true"` | Check `filter_expression` in log; verify source_uri, recency, age |
| AEL status `skipped` + `runtime_filter_result: false` | Runtime filter guard failed | Missing phone? Prior message exists? Wrong appointment status? |
| `scheduled_count: 0` | `decision_key` doesn't match any action | Verify action's `decision_key` matches the execute request |
| AEL `skipped` on repeat | Idempotency dedup | Expected — use `manual_override: true` to bypass |
| Action scheduled but not executing | Future trigger_template or Oban queue | Check `scheduled_at` — might be 3h/7d in the future |
| `422` on create | Invalid Liquid syntax or missing required field | Check `errors` array in response |
| SMS not received | `dry_run` mode, or action_window outside hours | Verify `mode: "live"` and check action_window_start/end |

## Testing recipe: validate a workflow

```bash
# 1. Create in draft
alvera workflows create <datalake> --body-file /tmp/workflow.json

# 2. Dry-run against one record
alvera workflows run <slug> \
  --body '{"sql_where_clause":"1=1 LIMIT 1","mode":"dry_run"}'

# 3. Check the log
alvera workflows workflow-logs <slug>
# → status should be "completed" (or "filtered" if filter rejected)

# 4. If filtered, pick a record that should pass and retry
alvera workflows run <slug> \
  --body '{"sql_where_clause":"ri.value = '\''EMR-APPT-12345'\''","mode":"dry_run"}'

# 5. If completed, review the rendered templates
alvera workflows workflow-log-download <slug> <log-id>

# 6. Promote to live (with user confirmation)
# Update status from "draft" to "live" via PUT
```
