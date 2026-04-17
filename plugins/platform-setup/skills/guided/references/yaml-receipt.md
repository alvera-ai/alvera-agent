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

datalakes:                             # only populated if the skill created one
  - name: Prime Production
    slug: prime-prod
    data_domain: healthcare
    timezone: America/New_York
    pool_size: 10
    # DB config per role: host / port / name / schema / auth_method /
    # enable_ssl recorded verbatim; credentials always as placeholders.
    unregulated_db_writer:
      host: db.internal
      port: 5432
      name: alvera_unreg
      schema: public
      auth_method: password
      enable_ssl: true
      user: $ALVERA_UNREG_W_USER        # placeholder, never resolved
      pass: $ALVERA_UNREG_W_PASS        # placeholder, never resolved
    # ...repeat for unregulated_db_reader, regulated_data_db_writer,
    # regulated_data_db_reader...

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
connected_apps: []
agentic_workflows: []
interoperability_contracts: []
data_activation_clients: []
```

### Connected app shape (when present)

```yaml
connected_apps:
  - name: Acme Portal
    mode: managed                          # or self_hosted
    description: Patient-facing portal
    repo_url: https://github.com/acme/portal
    urls:
      - url: https://portal.acme.com
        is_primary: true
        label: Production
    cloudflare_pages_config:
      account_id: $CF_ACCOUNT_ID           # placeholder, never resolved
      api_token: $CF_API_TOKEN             # placeholder, never resolved
      github_auth_method: github_app
      production_branch: main
```

## Rules

- **Append-only per turn.** Never rewrite earlier sections. New entries go
  at the end of their list.
- **Reference by name, not id.** Ids are runtime; names are stable across
  environments.
- **Secrets are placeholders.** `$AWS_ACCESS_KEY_ID`, `$ALVERA_API_KEY`,
  DB `user`/`pass` fields, etc. — never the resolved value. If the user
  supplied a literal at conversation time, write `<set at runtime>`.
- The YAML is a **receipt**, not a config file. The API is the source of
  truth. When the user asks "what do I have?", call `list` endpoints —
  do not read the YAML.
