# Resource elicitation rules

Required fields are **bold**. Defaults shown after `=`. Enum values are
**hints**, not authoritative — the API is the source of truth
(see `guardrails.md`).

---

## Datalake

`alvera datalakes create [tenant] --body-file <path>`

PostgreSQL-backed data container with **four distinct DB role connections**:
regulated-reader, regulated-writer, unregulated-reader, unregulated-writer.

Elicit in three passes.

### Pass 1 — identity & domain

| Field         | Required | Default | Notes                                                            |
|---------------|----------|---------|------------------------------------------------------------------|
| `name`        | **yes**  | —       | Unique within the tenant                                         |
| `slug`        | no       | auto    | Auto-generated from `name`                                       |
| `description` | no       | —       | —                                                                |
| `data_domain` | **yes**  | —       | Enum: `healthcare \| core_banking \| payment_risk \| accounts_receivable \| service_commerce \| trading` |
| `timezone`    | **yes**  | —       | IANA tz string (e.g. `America/New_York`)                         |
| `pool_size`   | **yes**  | `10`    | DB connection pool size per role                                  |

### Pass 2 — DB topology

Four roles × 8 fields each (host, port, name, schema, auth_method,
enable_ssl, user, pass) = up to 32 values. Ask these topology questions
to reduce the total:

1. Same host for regulated and unregulated? → reuse `host`/`port`.
2. Reader/writer same connection, different credentials? Or separate?
3. Same `auth_method` across all roles? Enum: `password \| iam_role`.
4. SSL on all connections? (recommend yes)

Per-role fields (roles: `unregulated_db_writer`, `unregulated_db_reader`,
`regulated_data_db_writer`, `regulated_data_db_reader`):

| Field                | Required | Notes                              |
|----------------------|----------|------------------------------------|
| `<role>_host`        | **yes**  |                                    |
| `<role>_port`        | **yes**  | integer                            |
| `<role>_name`        | **yes**  | database name                      |
| `<role>_schema`      | **yes**  | schema name                        |
| `<role>_auth_method` | **yes**  | `password \| iam_role`             |
| `<role>_enable_ssl`  | **yes**  | boolean                            |

### Pass 3 — credentials (sensitive)

Elicit credentials in the same prompt as Pass 2 topology (not a separate
interaction). For each role with `auth_method: password`, need
`<role>_user` and `<role>_pass`. `iam_role` roles skip these.

Three sourcing patterns (actively ask, see `guardrails.md`):
- **(a) Existing env vars** — user gives names, skill uses `envsubst`.
- **(b) Scaffold `.alvera.datalake.env`** — skill writes variable names
  with empty quotes, appends to `.gitignore`, user fills in, skill sources.
- **(c) One-shot literals** — write to tempfile, run, rm.

Hard rules:
- Never `--body '<json>'` with embedded passwords — always `--body-file`.
- Tempfile: `chmod 600`, delete immediately after create returns.
- Never echo resolved passwords.
- Never write resolved passwords to YAML receipt.

---

## Data source

`alvera data-sources create <datalake> [tenant] --body '<json>'`

| Field         | Required | Default  | Notes                                |
|---------------|----------|----------|--------------------------------------|
| `name`        | **yes**  | —        | Unique within the datalake           |
| `uri`         | **yes**  | —        | External identifier, e.g. `our-emr:acme` |
| `description` | no       | `""`     |                                      |
| `status`      | no       | `active` | `draft \| active \| archived`        |
| `is_default`  | no       | `false`  | Tenant primary source                |

---

## Tool

`alvera tools create [tenant] --body '<json>'`

| Field            | Required | Default  | Notes                                     |
|------------------|----------|----------|-------------------------------------------|
| `name`           | **yes**  | —        | Unique within the tenant                  |
| `intent`         | **yes**  | —        | `data_exchange \| sms \| email \| status_poller` |
| `status`         | no       | `active` | `active \| inactive`                      |
| `datalake_id`    | **yes**  | —        | From session                              |
| `data_source_id` | no       | —        | Present → attached; absent → standalone   |
| `body`           | **yes**  | —        | Set `body.__type__` per tool kind         |

### Tool body shapes (`body.__type__`)

- `manual_upload` — no extra fields.
- `s3` — `{ region, bucket, auth_method, ... }`.
- `sns` — `{ region, phone_number, auth_method, assume_role_arn, ... }`.
- `cloud_watch_log_group` — `{ region, auth_method, assume_role_arn, ... }`.
- `restapi` — `{ base_url, headers, ... }`.

For `auth_method: assume_role`, require `assume_role_arn` and
`assume_role_external_id` as **secrets** (env var names preferred).

---

## Generic table

`alvera generic-tables create <datalake> [tenant] --body-file <path>`

Handled via the data pipeline sub-flow — see `references/data-pipeline.md`.
That flow includes: compliance gate, column profiling, schema proposal,
table creation, and optional upload.

For quick single-resource creation (user explicitly says "create a generic
table" with known schema), elicit directly:

| Field         | Required | Default              | Notes                          |
|---------------|----------|----------------------|--------------------------------|
| `title`       | **yes**  | —                    | Human-readable                 |
| `description` | no       | `""`                 |                                |
| `data_domain` | no       | `null`               | Enum from datalake             |
| `columns`     | **yes**  | —                    | Array, length ≥ 1              |

Per column:

| Field                 | Required | Default   | Notes                                    |
|-----------------------|----------|-----------|------------------------------------------|
| `name`                | **yes**  | —         | snake_case                               |
| `title`               | no       | Title-case|                                          |
| `type`                | no       | `string`  | `string \| integer \| float \| boolean \| date \| datetime \| time` |
| `description`         | **yes**  | —         | One-liner                                |
| `privacy_requirement` | no       | `none`    | `none \| tokenize \| redact_only` — **locked at creation** |
| `is_required`         | no       | `false`   |                                          |
| `is_unique`           | no       | `false`   | **Composite** when multiple columns set  |
| `is_array`            | no       | `false`   | NDJSON only                              |

---

## Action status updater

`alvera action-status-updaters create [tenant] --body-file <path>`

| Field               | Required | Default | Notes                                              |
|---------------------|----------|---------|----------------------------------------------------|
| `name`              | **yes**  | —       |                                                    |
| `cron_expression`   | **yes**  | —       | 5-field cron, e.g. `*/5 * * * *`                   |
| `updater_type`      | **yes**  | —       | `cloud_watch \| restapi`                           |
| `updater_tool_id`   | **yes**  | —       | Existing tool's id — list and pick                 |
| `datalake_id`       | **yes**  | —       | From session                                       |
| `sender_tool_ids`   | no       | —       | List of tool ids                                   |
| `message_config`    | no       | —       | `{ type, path? \| body? }`                         |
| `action_log_config` | no       | —       | Same shape as `message_config`                     |
| `updater_body`      | no       | —       | Matches `updater_type`                             |

### `updater_body` shapes

- `cloud_watch_request` — `{ __type__, log_group_name, start_time, end_time }`
- `restapi_request` — `{ __type__, ...arbitrary }`

---

## AI agent

`alvera ai-agents create <datalake> [tenant] --body-file <path>`

| Field                | Required | Default | Notes                                               |
|----------------------|----------|---------|-----------------------------------------------------|
| `name`               | **yes**  | —       |                                                     |
| `model`              | **yes**  | —       | E.g. `claude-opus-4-6`, `gpt-4o`                    |
| `tool_id`            | **yes**  | —       | Existing tool's id                                  |
| `data_access`        | **yes**  | `unregulated` | `regulated \| unregulated` — see guidance below |
| `temperature`        | **yes**  | —       | `0..1`                                              |
| `max_tokens`         | **yes**  | —       | Positive integer                                    |
| `enabled`            | **yes**  | —       | Boolean                                             |
| `slug`               | no       | auto    |                                                     |
| `description`        | no       | —       |                                                     |
| `input_schema`       | no       | —       | JSON Schema                                         |
| `llm_response_schema`| no       | —       | JSON Schema                                         |
| `prompt_config`      | no       | —       | Free-form object                                    |

**`data_access` guidance:** Default to `unregulated`. AI agents process
data through LLM providers — for compliance, they should only see
de-identified (unregulated) data. Use `regulated` only if the agent
explicitly needs PHI/PII access AND the user confirms their BAA covers
LLM processing of regulated data.

---

## Connected app

`alvera connected-apps create <datalake> [tenant] --body-file <path>`

Elicit `mode` first, then branch.

- **`self_hosted`** — user hosts the app themselves and provides URLs.
  This is the current default. Use when the user already has a deployed
  frontend or is hosting their own forms/portal.
- **`managed`** — Alvera deploys the app automatically via Cloudflare
  Pages from a repo. Not yet available — if user asks, explain it's
  coming and default to `self_hosted`.

| Field                      | Required | Default | Notes                                        |
|----------------------------|----------|---------|----------------------------------------------|
| `name`                     | **yes**  | —       | Unique within datalake                       |
| `mode`                     | **yes**  | —       | `managed \| self_hosted` (default to `self_hosted`) |
| `description`              | no       | —       |                                              |
| `repo_url`                 | cond.    | —       | Required when `mode = managed`               |
| `urls`                     | cond.    | `[]`    | ≥1 required when `mode = self_hosted`        |
| `cloudflare_pages_config`  | cond.    | —       | Required when `mode = managed`               |

### `urls[]` shape

| Field        | Required | Default | Notes                        |
|--------------|----------|---------|------------------------------|
| `url`        | **yes**  | —       | `http://` or `https://`      |
| `is_primary` | no       | `false` | Exactly one should be primary |
| `label`      | no       | —       |                              |

### `cloudflare_pages_config` (managed)

| Field                  | Required | Default  | Notes                                  |
|------------------------|----------|----------|----------------------------------------|
| `account_id`           | **yes**  | —        |                                        |
| `api_token`            | **yes**  | —        | **Secret** (env var name preferred)    |
| `github_auth_method`   | **yes**  | —        | `github_app \| pat`                    |
| `github_pat`           | cond.    | —        | Required when `pat`. **Secret.**       |
| `production_branch`    | no       | `main`   |                                        |
| `build_command`        | no       | —        |                                        |
| `destination_dir`      | no       | —        |                                        |

### `sync-routes`

`alvera connected-apps sync-routes <datalake> <id>` — confirm before
invoking, mutates routing state.

---

## Agentic workflow

`alvera workflows create <datalake> [tenant] --body-file <path>`

Handled via the workflow sub-flow — see `references/workflows.md`.
That flow includes: template matching or custom build, draft creation,
dry-run testing, log interpretation, and promotion to live.

For quick single-resource creation, elicit in passes:

### Pass 1 — identity

| Field                 | Required | Default  | Notes                                      |
|-----------------------|----------|----------|--------------------------------------------|
| `name`                | **yes**  | —        | Unique within datalake                     |
| `description`         | no       | —        |                                            |
| `dataset_type`        | **yes**  | —        | `patient`, `appointment`, `generic_table`, etc. |
| `generic_table_id`    | cond.    | —        | Required when `dataset_type == "generic_table"` |
| `status`              | no       | `draft`  | Start as draft                             |

### Pass 2 — AI agents (optional)

List existing agents, let user pick. Each: `ai_agent_id`, `position`,
`context_mapping_config`.

### Pass 3 — context datasets (optional)

Each: `dataset_type`, `generic_table_id`, `where_clause`, `limit`, `position`.

### Pass 4 — filter config (optional)

`type`: `system \| custom \| identity \| null`. `body` for custom.

### Pass 5 — decision config (optional)

Free-form object or auto-generate static decision.

### Pass 6 — actions

Each action: `action_type`, `decision_key`, `tool_id`, `position`,
`tool_call` (polymorphic by action type), `trigger_template`,
`idempotency_template`, `runtime_filter`, `action_window_start/end`,
`connected_app_id`, `connected_app_route`.

`tool_call` discriminator: `sms_request`, `restapi_request`, `s3_request`,
`aws_lambda_request`, `sftp_request`.

### Slug vs ID usage

| Operation | Identifier |
|-----------|-----------|
| `create` | returns both slug and ID |
| `run` / `execute` / `workflow-logs` / `batch-logs` | use **slug** |
| `update` / `delete` / `get` / `metadata` | use **ID** |

Always store both after creation. Use slug for execution, ID for mutations.

### After create

- Offer dry-run: `alvera workflows run <slug> --body '{"sql_where_clause":"1=1 LIMIT 1","mode":"dry_run"}'`.
- Promote to live on user confirmation.
- Append to `infra.yaml`.

---

## Interoperability contract

`alvera interop create <datalake> [tenant] --body-file <path>`

| Field                          | Required | Default | Notes                                |
|--------------------------------|----------|---------|--------------------------------------|
| `name`                         | **yes**  | —       |                                      |
| `resource_type`                | **yes**  | —       | `patient`, `appointment`, etc.       |
| `generic_table_id`             | cond.    | —       | Required when `resource_type == "generic_table"` |
| `type`                         | no       | —       | `system \| custom`                   |
| `description`                  | no       | —       |                                      |
| `data_activation_client_filter`| no       | —       | Liquid filter                        |
| `template_config`              | no       | —       | TemplateConfig                       |
| `mdm_input_config`             | no       | —       | TemplateConfig                       |

TemplateConfig shape: `{ type: "system\|custom\|identity\|null", body?, path?, output_schema? }`.

---

## Data activation client

`alvera data-activation-clients create <datalake> [tenant] --body-file <path>`

| Field                          | Required | Default | Notes                                 |
|--------------------------------|----------|---------|---------------------------------------|
| `name`                         | **yes**  | —       | Unique within datalake                |
| `data_source_id`               | **yes**  | —       | Owning data source                    |
| `tool_id`                      | **yes**  | —       | External connection tool              |
| `description`                  | no       | —       |                                       |
| `cron_expressions`             | no       | `[]`    | Crontab array, empty = on-demand      |
| `row_filter`                   | no       | —       | Liquid row filter                     |
| `filter_config`                | no       | —       | TemplateConfig                        |
| `loop_over`                    | no       | —       | Context keys to iterate               |
| `downstream_connection_ids`    | no       | `[]`    | DAC IDs triggered after completion    |
| `interoperability_contract_ids`| no       | `[]`    | Contract IDs for row-level transform  |
| `tool_call`                    | **yes**  | —       | Polymorphic, set `tool_call_type`     |

### `tool_call` types

- `manual_upload` — no extra config
- `restapi_request` — `{ method, path, params, body, pagination_context_template }`
- `s3_request`, `aws_lambda_request`, `sftp_request`, `sql_query`,
  `microsoft_share_point_excel_request` — respective configs
