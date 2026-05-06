# Neon project provisioning

Use the Neon API (`https://console.neon.tech/api/v2`) to provision a
Postgres database. A single `POST /projects` call returns **all**
connection details — no follow-up calls needed.

## Prerequisites

- `NEON_API_KEY` env var must be set (personal or org API key).
- Skill does **not** manage the API key. User must provide it or
  set the env var themselves.

## Create project

```bash
curl -s 'https://console.neon.tech/api/v2/projects' \
  -H 'Accept: application/json' \
  -H "Authorization: Bearer $NEON_API_KEY" \
  -H 'Content-Type: application/json' \
  -d '{
  "project": {
    "name": "<project_name>"
  }
}' | jq
```

### Optional request fields

| Field                              | Default           | Notes                                  |
|------------------------------------|-------------------|----------------------------------------|
| `name`                             | auto-generated    | Max 64 chars                           |
| `region_id`                        | `aws-us-east-1`   | e.g. `aws-us-east-2`, `aws-ap-southeast-1` |
| `pg_version`                       | `17`              | 14, 15, 16, or 17                      |
| `branch.name`                      | `main`            | Default branch name                    |
| `database.name`                    | `neondb`          | Default database                       |
| `role.name`                        | `<db>_owner`      | Default role                           |
| `default_endpoint_settings`        | 0.25 CU           | Autoscaling min/max, suspend timeout   |

Full request body example with all options:

```bash
curl -s 'https://console.neon.tech/api/v2/projects' \
  -H 'Accept: application/json' \
  -H "Authorization: Bearer $NEON_API_KEY" \
  -H 'Content-Type: application/json' \
  -d '{
  "project": {
    "name": "my-project",
    "region_id": "aws-us-east-2",
    "pg_version": 17,
    "default_endpoint_settings": {
      "autoscaling_limit_min_cu": 0.25,
      "autoscaling_limit_max_cu": 1
    }
  }
}' | jq
```

## Response — what you get back

The response is a single JSON object. Extract these top-level keys:

### `connection_uris[]` — ready-made connection strings

| Path                                  | Example                                              |
|---------------------------------------|------------------------------------------------------|
| `.connection_uris[0].connection_uri`  | `postgresql://neondb_owner:npg_xxx@ep-xxx.neon.tech/neondb?sslmode=require` |
| `.connection_uris[0].connection_parameters.database` | `neondb`                |
| `.connection_uris[0].connection_parameters.role`     | `neondb_owner`         |
| `.connection_uris[0].connection_parameters.password` | `npg_Se0ECYqaJ5jA`     |
| `.connection_uris[0].connection_parameters.host`     | `ep-xxx.c-2.us-east-1.aws.neon.tech` |
| `.connection_uris[0].connection_parameters.pooler_host` | `ep-xxx-pooler.c-2.us-east-1.aws.neon.tech` |

### `roles[]` — database roles

| Path              | Example            |
|-------------------|--------------------|
| `.roles[0].name`  | `neondb_owner`     |
| `.roles[0].password` | `npg_Se0ECYqaJ5jA` |

### `databases[]` — databases

| Path               | Example    |
|--------------------|------------|
| `.databases[0].name` | `neondb` |
| `.databases[0].owner_name` | `neondb_owner` |

### `endpoints[]` — compute endpoints

| Path                      | Example                                  |
|---------------------------|------------------------------------------|
| `.endpoints[0].host`      | `ep-xxx.c-2.us-east-1.aws.neon.tech`    |
| `.endpoints[0].id`        | `ep-cool-darkness-123456`                |
| `.endpoints[0].type`      | `read_write`                             |

### `branch` — default branch

| Path           | Example                        |
|----------------|--------------------------------|
| `.branch.id`   | `br-gentle-salad-ad7v90qq`     |
| `.branch.name` | `main`                         |

### `project` — project metadata

| Path               | Example                       |
|--------------------|-------------------------------|
| `.project.id`      | `ep-cool-darkness-123456`     |
| `.project.name`    | `myproject`                   |
| `.project.region_id` | `aws-us-east-1`             |
| `.project.pg_version` | `17`                       |

## Extraction pattern

```bash
RESP=$(curl -s 'https://console.neon.tech/api/v2/projects' \
  -H 'Accept: application/json' \
  -H "Authorization: Bearer $NEON_API_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"project":{"name":"my-project"}}')

NEON_HOST=$(echo "$RESP" | jq -r '.connection_uris[0].connection_parameters.host')
NEON_ROLE=$(echo "$RESP" | jq -r '.roles[0].name')
NEON_PASS=$(echo "$RESP" | jq -r '.roles[0].password')
NEON_DB=$(echo "$RESP" | jq -r '.databases[0].name')
NEON_PROJECT_ID=$(echo "$RESP" | jq -r '.project.id')

# Variables are now set — use them in --body-file.
# NEVER echo $NEON_PASS to stdout.
```

## Mapping to Alvera datalake fields

When creating a datalake via `alvera datalakes create`, map Neon
response fields to datalake DB role fields:

| Alvera field                | Neon source                                        |
|-----------------------------|----------------------------------------------------|
| `<role>_host`               | `.connection_uris[0].connection_parameters.host`   |
| `<role>_port`               | `5432` (Neon default, or from connection URI)      |
| `<role>_name`               | `.databases[0].name`                               |
| `<role>_schema`             | `public`                                           |
| `<role>_auth_method`        | `password`                                         |
| `<role>_enable_ssl`         | `true` (Neon requires SSL)                         |
| `<role>_user`               | `.roles[0].name`                                   |
| `<role>_pass`               | `.roles[0].password` (treat as secret)             |

All four Alvera roles (regulated/unregulated × reader/writer) can use
the **same** Neon connection if a single project is sufficient.

## Secrets handling

- `.roles[0].password` and `.connection_uris[0].connection_uri` contain
  plaintext credentials.
- Follow `guardrails.md` rules: prefer env var names over literals.
- Never echo resolved passwords. Never write them to the YAML receipt.
- Use `--body-file` with a tempfile (chmod 600, rm after) when passing
  credentials to `alvera datalakes create`.

## Delete project

```bash
curl -s -X DELETE "https://console.neon.tech/api/v2/projects/<project_id>" \
  -H 'Accept: application/json' \
  -H "Authorization: Bearer $NEON_API_KEY" | jq
```

Recoverable within 7 days via `POST /projects/{project_id}/recover`.

## List projects

```bash
curl -s 'https://console.neon.tech/api/v2/projects' \
  -H 'Accept: application/json' \
  -H "Authorization: Bearer $NEON_API_KEY" | jq '.projects[] | {id, name, region_id}'
```
