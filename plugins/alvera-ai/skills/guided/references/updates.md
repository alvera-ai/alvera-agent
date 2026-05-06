# Resource updates

Per-resource mutability rules. Which fields can change after creation,
what the API behavior is, and how to handle updates safely.

## General update rules

- **Read-before-write.** Always fetch current state before updating.
- **PUT = full replace** for workflows and interop contracts. Send the
  complete body, not just changed fields.
- **PATCH-like** for most other resources. Send only the fields you want
  to change (plus required identifiers).
- **Show diffs.** Present `old -> new` for every changed field. Require
  explicit y/n before submitting.

## Per-resource mutability

### Datalake

**Not updatable via API.** `scope.md` lists only `list`, `get`, `create`,
`upload-link`. If the user needs to change datalake settings, they must
create a new one or contact their Alvera admin.

### Data source

| Field | Mutable | Notes |
|-------|---------|-------|
| `name` | yes | |
| `uri` | yes | Changing URI may break downstream workflow filters that match on `source_uri` |
| `description` | yes | |
| `status` | yes | `draft -> active -> archived` |
| `is_default` | yes | Only one per tenant; setting this unsets the previous default |

### Tool

| Field | Mutable | Notes |
|-------|---------|-------|
| `name` | yes | |
| `intent` | no | Locked at creation. Create a new tool if intent changes. |
| `status` | yes | `active <-> inactive` |
| `datalake_id` | no | Locked at creation |
| `data_source_id` | yes | Detach/reattach |
| `body` | yes | Full body replace. Changing `__type__` is effectively a new tool. |

### Generic table

| Field | Mutable | Notes |
|-------|---------|-------|
| `title` | no | Not updatable via API. Create a new table. |
| `columns` | no | **Locked at creation.** Cannot add, remove, or modify columns. |
| `columns[].privacy_requirement` | no | **Locked at creation.** Choose carefully. |

### Action status updater

| Field | Mutable | Notes |
|-------|---------|-------|
| `name` | yes | |
| `cron_expression` | yes | |
| `updater_type` | no | Locked at creation |
| `updater_tool_id` | yes | |
| `message_config` | yes | |
| `action_log_config` | yes | |
| `updater_body` | yes | Must match `updater_type` |

### AI agent

| Field | Mutable | Notes |
|-------|---------|-------|
| `name` | yes | |
| `model` | yes | |
| `tool_id` | yes | |
| `data_access` | yes | Changing from `unregulated` to `regulated` has compliance implications — confirm. |
| `temperature` | yes | |
| `max_tokens` | yes | |
| `enabled` | yes | |
| `prompt_config` | yes | |
| `input_schema` | yes | |
| `llm_response_schema` | yes | |

### Connected app

| Field | Mutable | Notes |
|-------|---------|-------|
| `name` | yes | |
| `description` | yes | |
| `mode` | no | Locked at creation |
| `urls` | yes | Full array replace |
| `repo_url` | yes | Only relevant for future `managed` mode |

### Agentic workflow

**PUT = full replace.** Always send the complete workflow body.

| Field | Mutable | Notes |
|-------|---------|-------|
| `name` | yes | |
| `description` | yes | |
| `dataset_type` | no | Locked at creation |
| `generic_table_id` | no | Locked at creation |
| `status` | yes | `draft <-> live`. Promoting to `live` requires explicit confirmation. |
| `filter_config` | yes | |
| `decision_config` | yes | |
| `context_datasets` | yes | Full array replace |
| `actions` | yes | Full array replace. Changing `tool_id` or `decision_key` affects running actions. |
| `ai_agents` | yes | Full array replace |

### Interoperability contract

**PUT = full replace.** Always send the complete contract body.

| Field | Mutable | Notes |
|-------|---------|-------|
| `name` | yes | |
| `resource_type` | no | Locked at creation |
| `generic_table_id` | no | Locked at creation |
| `description` | yes | |
| `template_config` | yes | Changing templates affects all future DAC runs using this contract |
| `mdm_input_config` | yes | |
| `data_activation_client_filter` | yes | |

### Data activation client

| Field | Mutable | Notes |
|-------|---------|-------|
| `name` | yes | |
| `data_source_id` | yes | |
| `tool_id` | yes | Must match `tool_call.tool_call_type` |
| `cron_expressions` | yes | Empty array = on-demand only |
| `row_filter` | yes | |
| `filter_config` | yes | |
| `tool_call` | yes | Changing `tool_call_type` is effectively a new DAC |
| `interoperability_contract_ids` | yes | Full array replace. Order matters for chained contracts. |
| `downstream_connection_ids` | yes | |
