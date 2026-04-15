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

## Datalake

`alvera datalakes create [tenant] --body-file <path>`

A datalake is a PostgreSQL-backed data container with **four distinct DB
role connections**: regulated-reader, regulated-writer,
unregulated-reader, unregulated-writer. Each role gets its own host,
port, database, schema, auth method, and SSL setting. "Regulated"
holds PHI / sensitive data and is usually isolated from "unregulated".

Elicit in three passes — don't dump all 38 fields at once.

### Pass 1 — identity & domain

| Field         | Required | Default | Notes                                                            |
|---------------|----------|---------|------------------------------------------------------------------|
| `name`        | **yes**  | —       | Human-readable, unique within the tenant                         |
| `slug`        | no       | auto    | URL-friendly; auto-generated from `name` if omitted              |
| `description` | no       | —       | —                                                                |
| `data_domain` | **yes**  | —       | Enum (API authoritative): `healthcare \| core_banking \| payment_risk \| accounts_receivable \| service_commerce \| trading` |
| `timezone`    | **yes**  | —       | IANA tz string (e.g. `America/New_York`, `UTC`)                  |
| `pool_size`   | **yes**  | `10`    | DB connection pool size per role; integer. Suggest 10 unless the user knows better. |

### Pass 2 — DB topology (ask as yes/no, pick the common shape)

Four role pairs × 5 connection fields each = 20 config values. Most
deployments have symmetry. Ask up front:

1. "Are the regulated and unregulated DBs on the **same host**, or
   different hosts?" → if same, reuse `host`/`port` for both.
2. "Do reader and writer use **the same connection** (same host/port)
   with different credentials, or fully separate endpoints (e.g. a
   read replica)?"
3. "Do all four roles use the **same `auth_method`**?" Enum per role
   (API authoritative): `password \| iam_role`.
4. "Will SSL be enabled on all connections?" (recommend yes for
   anything non-local.)

Derive the 4×5 matrix from the user's answers. Echo it back as a table
before moving to Pass 3 so they can spot mistakes early.

Per-role connection fields (repeat for each of the four roles):

| Field           | Required | Notes                                         |
|-----------------|----------|-----------------------------------------------|
| `<role>_host`   | **yes**  | `unregulated_db_writer_host` etc.             |
| `<role>_port`   | **yes**  | integer                                       |
| `<role>_name`   | **yes**  | database name                                 |
| `<role>_schema` | **yes**  | schema name                                   |
| `<role>_auth_method` | **yes** | Enum: `password \| iam_role`              |
| `<role>_enable_ssl`  | **yes** | boolean                                    |

Roles: `unregulated_db_writer`, `unregulated_db_reader`,
`regulated_data_db_writer`, `regulated_data_db_reader`.

### Pass 3 — credentials (sensitive)

For each role using `auth_method: password`, we need a `<role>_user` and
`<role>_pass`. `iam_role` roles skip these fields.

**Don't just list options passively.** Ask the user directly:

> "Credentials next — how do you want to supply the DB passwords?
> I can:
>   a) Use env vars you've already set (give me the names).
>   b) **Scaffold an `.alvera.datalake.env` for you** — I write the
>      variable names you need (values left blank), you fill them in,
>      tell me when you're done, and I'll source it.
>   c) Accept one-shot literal values typed here (least preferred —
>      they hit your chat history).
> Which?"

Default recommendation: (b) for first-time setup, (a) for users who
already manage secrets in their shell/1Password/vault.

#### (a) Existing env vars

User sets shell env vars before running the skill; gives the skill the
*names*, not values. The skill expands them via `envsubst` into a
tempfile body:

```bash
# user does (in their own shell, outside Claude):
export REG_W_USER=... REG_W_PASS=... REG_R_USER=... REG_R_PASS=... \
       UNR_W_USER=... UNR_W_PASS=... UNR_R_USER=... UNR_R_PASS=...

# skill writes body template to tempfile, then:
envsubst < /tmp/datalake.json.tpl > /tmp/datalake.json
alvera datalakes create --body-file /tmp/datalake.json
rm /tmp/datalake.json   # immediately after create returns
```

#### (b) Scaffold `.alvera.datalake.env` (proactive)

Offer to write the file for the user. Workflow:

1. Skill writes `./.alvera.datalake.env` with the variable *names* they
   need, values left as empty quotes:
   ```bash
   # .alvera.datalake.env — fill in values, do not commit
   REG_W_USER=""
   REG_W_PASS=""
   REG_R_USER=""
   REG_R_PASS=""
   UNR_W_USER=""
   UNR_W_PASS=""
   UNR_R_USER=""
   UNR_R_PASS=""
   ```
2. Skill appends `.alvera.datalake.env` to `./.gitignore` (creating it
   if needed). Never commit the filled file.
3. Skill tells the user: *"Fill in the eight values in
   `.alvera.datalake.env`, save it, and tell me when you're done."*
4. On the user's confirmation, skill runs:
   ```bash
   set -a; source ./.alvera.datalake.env; set +a
   # verify all vars non-empty; if any are blank, stop and tell the user which
   envsubst < /tmp/datalake.json.tpl > /tmp/datalake.json
   alvera datalakes create --body-file /tmp/datalake.json
   rm /tmp/datalake.json
   ```
5. After success, remind the user they can delete
   `.alvera.datalake.env` now (creds are already applied on the
   platform side), or keep it for re-runs — their call.

Filename is deliberately `.alvera.datalake.env` (not generic `.env`) so
it doesn't clash with project-level dotenv files.

#### (c) One-shot literal values

Least preferred but accepted for small throwaway tests. Skill writes
values directly into a tempfile body, runs `alvera datalakes create
--body-file`, then `rm`s the tempfile. Values are never echoed back to
the user, never written to the YAML receipt, never retained in skill
memory beyond the single create call.

Hard rules (also in `guardrails.md`):

- **Never** pass passwords via `--body '<json>'` on the command line —
  shell history + `ps` both leak it.
- **Never** write a resolved password to the YAML receipt. Use
  `$ENV_NAME` placeholder or `<set at runtime>` for literal.
- **Never** echo a resolved password back to the user.
- Tempfile body path must be `/tmp/` (or similar), `chmod 600`, and
  deleted immediately after `alvera datalakes create` returns —
  regardless of whether it succeeded.

### After create

- Pin the returned datalake slug for the rest of the session.
- Append to `infra.yaml` (see `yaml-receipt.md`): only `name`, `slug`,
  `data_domain`, `timezone`, `pool_size`, and the DB host/port/schema/
  SSL/auth_method values. Credential fields → `$ENV_NAME` placeholders
  only, never resolved values.

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

**Out of scope for this skill — hand off to `custom-dataset-creation`.**

Generic-table (custom dataset) creation involves a compliance gate
("can I read this file?"), column profiling (inline for dummy data, or
a local Python script for regulated data), and a schema proposal with
privacy + uniqueness semantics that need dedicated handling. That
belongs in a focused skill rather than being one option in the resource
loop.

When the user asks to create a generic table / custom dataset / onboard
a table from a file, say:

> "Custom dataset creation lives in the `custom-dataset-creation` skill
> — it walks through the file, proposes columns, and handles the
> privacy-locked-at-creation rule. Want me to hand off?"

If they agree, stop the `guided` loop for that turn and invoke the
other skill. The new skill assumes the session + datalake are already
set up (which `guided` has just done), so it picks up cleanly.

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
