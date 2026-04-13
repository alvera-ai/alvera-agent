# Resource elicitation rules

Required fields are **bold**. Defaults shown after `=`. Enum values
listed here are **hints to guide elicitation**, not an authoritative
whitelist — the API is the source of truth and its 4xx response is the
validator of record (see `guardrails.md` → "Enum validation: the API is
authoritative"). If the user supplies an enum value outside the local
list, prefer passing it through and letting the API adjudicate over
rejecting it locally on stale info. Structural rules (required fields,
length ≥ 1, positive integers, valid cron, JSON shape) stay client-side
— they don't drift.

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

---

## Connected app

`alvera connected-apps create <datalake> [tenant] --body-file <path>`

External web application connected to the platform via M2M API key.
Datalake-scoped. Two deployment modes with different required fields —
elicit `mode` first, then branch.

| Field                      | Required | Default | Notes                                                              |
|----------------------------|----------|---------|--------------------------------------------------------------------|
| `name`                     | **yes**  | —       | Unique within the datalake                                         |
| `mode`                     | **yes**  | —       | Enum: `managed \| self_hosted`                                     |
| `description`              | no       | —       | —                                                                  |
| `repo_url`                 | cond.    | —       | **Required when** `mode = managed`. Optional for `self_hosted`.    |
| `urls`                     | cond.    | `[]`    | **At least one required when** `mode = self_hosted`. See shape below. |
| `cloudflare_pages_config`  | cond.    | —       | **Required when** `mode = managed`. See shape below.               |

### `urls[]` shape

| Field        | Required | Default | Notes                                  |
|--------------|----------|---------|----------------------------------------|
| `url`        | **yes**  | —       | Must be `http://` or `https://`        |
| `is_primary` | no       | `false` | Exactly one entry should be primary    |
| `label`      | no       | —       | Human-readable                         |

If the user supplies multiple URLs and none is marked primary, ask
which one. Do not auto-pick.

### `cloudflare_pages_config` shape (managed mode)

| Field                  | Required | Default      | Notes                                                       |
|------------------------|----------|--------------|-------------------------------------------------------------|
| `account_id`           | **yes**  | —            | Cloudflare account ID                                       |
| `api_token`            | **yes**  | —            | **Secret** (writeOnly). Env-var name preferred — see `guardrails.md`. |
| `github_auth_method`   | **yes**  | —            | Enum: `github_app \| pat`                                   |
| `github_pat`           | cond.    | —            | **Required when** `github_auth_method = pat`. **Secret.**   |
| `production_branch`    | no       | `main`       | Git branch for production builds                            |
| `build_command`        | no       | —            | Build command                                               |
| `destination_dir`      | no       | —            | Build output directory                                      |

`project_name` is server-assigned (readOnly) — never elicit.

### `sync-routes`

`alvera connected-apps sync-routes <datalake> <id>` triggers a route sync
against the connected app. No body. Treat it like a destructive-ish
action: confirm before invoking, since it mutates routing state on the
remote app.
