# YAML receipt

If the user opted in at bootstrap, append to `./infra.yaml` after each
successful create. The schema mirrors the internal Alvera contract shape
so the file can be reused by other Alvera tooling.

## Shape

```yaml
tenant:
  slug: <tenant_slug_from_bootstrap>

datalake:
  slug: <datalake_slug_chosen_at_bootstrap>

data_sources:
  - name: Acme EMR
    uri: our-emr:acme
    description: Acme EMR system
    status: active
    is_default: true

tools:
  - name: Acme Manual Upload
    intent: data_exchange
    status: active
    type: manual_upload
    data_source: Acme EMR        # name reference, not id
    variables: {}
    secrets: {}                  # $ENV_NAME placeholders only

generic_tables: []
action_status_updaters: []
ai_agents: []
```

## Rules

- **Append-only per turn.** Never rewrite earlier sections. New entries go
  at the end of their list.
- **Reference by name, not id.** Ids are runtime; names are stable across
  environments.
- **Secrets are placeholders.** `$AWS_ACCESS_KEY_ID`, `$ALVERA_API_KEY`,
  etc. — never the resolved value. If the user supplied a literal at
  conversation time, write `<set at runtime>`.
- The YAML is a **receipt**, not a config file. The API is the source of
  truth. When the user asks "what do I have?", call `list` endpoints —
  do not read the YAML.
