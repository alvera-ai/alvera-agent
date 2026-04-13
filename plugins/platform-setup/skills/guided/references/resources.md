# Resource elicitation rules

Required fields are **bold**. Defaults shown after `=`. Enums are hard —
reject anything outside them at conversation time.

---

## Data source

`alvera data-sources create <datalake> [tenant] --body '<json>'`

| Field         | Required | Default  | Notes                                |
|---------------|----------|----------|--------------------------------------|
| `name`        | **yes**  | —        | Unique within the datalake           |
| `uri`         | **yes**  | —        | External identifier, e.g. `our-emr:acme` |
| `description` | no       | `""`     | Human-readable                       |
| `status`      | no       | `active` | Enum: `draft \| active \| archived`  |
| `is_default`  | no       | `false`  | Tenant primary source                |

**Conversation prompt:**
> "What system is this representing (EMR, billing, etc.)? Give me a short
> name and a URI like `our-emr:<slug>`."

---

## Tool

`alvera tools create [tenant] --body '<json>'`

| Field            | Required | Default  | Notes                                                     |
|------------------|----------|----------|-----------------------------------------------------------|
| `name`           | **yes**  | —        | Unique within the tenant                                  |
| `intent`         | **yes**  | —        | Enum: `data_exchange \| sms \| email \| status_poller`    |
| `status`         | no       | `active` | Enum: `active \| inactive`                                |
| `datalake_id`    | **yes**  | —        | From bootstrap                                            |
| `data_source_id` | no       | —        | Present → attached; absent → standalone                   |
| `body`           | **yes**  | —        | Typed payload — set `body.__type__` per tool kind         |

### Tool body shapes (set `body.__type__`)

- `manual_upload` — no extra fields.
- `s3` — `{ region, bucket, auth_method, ... }`. Note: legacy YAML
  `type: s3_storage` translates to `__type__: s3`.
- `sns` — `{ region, phone_number, auth_method, assume_role_arn, ... }`.
- `cloud_watch_log_group` — `{ region, auth_method, assume_role_arn, ... }`.
- `restapi` — `{ base_url, headers, ... }`.

For `auth_method: assume_role`, require `assume_role_arn` and
`assume_role_external_id` as **secrets** (env var names preferred — see
`guardrails.md`).

---

## Generic table

`alvera generic-tables create <datalake> [tenant] --body-file <path>`

| Field         | Required | Default | Notes                                                                 |
|---------------|----------|---------|-----------------------------------------------------------------------|
| `title`       | **yes**  | —       | Human-readable                                                        |
| `description` | no       | `""`    | —                                                                     |
| `data_domain` | no       | `null`  | Enum: `healthcare \| core_banking \| payment_risk \| accounts_receivable \| service_commerce \| trading \| null` |
| `columns`     | **yes**  | —       | Length ≥ 1                                                            |

### Column shape

| Field                 | Required | Default  | Notes                                                            |
|-----------------------|----------|----------|------------------------------------------------------------------|
| `name`                | **yes**  | —        | snake_case identifier                                            |
| `title`               | no       | —        | Human-readable                                                   |
| `type`                | no       | `string` | Enum: `string \| integer \| float \| boolean \| date \| datetime \| time` |
| `description`         | **yes**  | —        | —                                                                |
| `privacy_requirement` | no       | `none`   | Enum: `none \| tokenize \| redact_only`                          |
| `is_required`         | no       | `false`  | —                                                                |
| `is_unique`           | no       | `false`  | —                                                                |
| `is_array`            | no       | `false`  | —                                                                |

Ask column-by-column. Reject tables with zero columns.

---

## Action status updater

`alvera action-status-updaters create [tenant] --body-file <path>`

| Field               | Required | Default | Notes                                                  |
|---------------------|----------|---------|--------------------------------------------------------|
| `name`              | **yes**  | —       | —                                                      |
| `cron_expression`   | **yes**  | —       | Standard 5-field cron, e.g. `*/5 * * * *`. Reject malformed. |
| `updater_type`      | **yes**  | —       | Enum: `cloud_watch \| restapi`                         |
| `updater_tool_id`   | **yes**  | —       | Existing tool's id — list and pick                     |
| `datalake_id`       | **yes**  | —       | From bootstrap                                         |
| `sender_tool_ids`   | no       | —       | List of tool ids for notifications                     |
| `message_config`    | no       | —       | `{ type: 'system' \| 'custom', path? \| body? }`       |
| `action_log_config` | no       | —       | Same shape as `message_config`                         |
| `updater_body`      | no       | —       | See below; matches `updater_type`                      |

### `updater_body` shapes

- `cloud_watch_request` — `{ __type__: 'cloud_watch_request', log_group_name, start_time, end_time }`
- `restapi_request` — `{ __type__: 'restapi_request', ...arbitrary }`

---

## AI agent

`alvera ai-agents create <datalake> [tenant] --body-file <path>`

| Field                | Required | Default | Notes                                                                                |
|----------------------|----------|---------|--------------------------------------------------------------------------------------|
| `name`               | **yes**  | —       | —                                                                                    |
| `model`              | **yes**  | —       | E.g. `claude-opus-4-6`, `gpt-4o`                                                     |
| `tool_id`            | **yes**  | —       | Existing tool's id                                                                   |
| `data_access`        | **yes**  | —       | Enum: `regulated \| unregulated`. Ask explicitly — wrong value is a security concern. |
| `temperature`        | **yes**  | —       | `0..1`                                                                               |
| `max_tokens`         | **yes**  | —       | Positive integer                                                                     |
| `enabled`            | **yes**  | —       | Boolean                                                                              |
| `slug`               | no       | auto    | Auto-generated if omitted                                                            |
| `description`        | no       | —       | —                                                                                    |
| `input_schema`       | no       | —       | JSON Schema                                                                          |
| `llm_response_schema`| no       | —       | JSON Schema                                                                          |
| `prompt_config`      | no       | —       | Free-form object                                                                     |
