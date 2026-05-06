# YAML receipt

Always emit. Append to `./alvera-<tenant-slug>.yaml` after each
successful create. The filename includes the tenant slug so multiple
tenants produce separate receipts.

## Shape

```yaml
tenant:
  slug: <tenant_slug_from_bootstrap>

datalakes:
  - name: Prime Production
    slug: prime-prod
    data_domain: healthcare
    timezone: America/New_York
    pool_size: 10
    unregulated_db_writer:
      host: db.internal
      port: 5432
      name: alvera_unreg
      schema: public
      auth_method: password
      enable_ssl: true
      user: $ALVERA_UNREG_W_USER
      pass: $ALVERA_UNREG_W_PASS

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
    data_source: Acme EMR
    variables: {}
    secrets: {}

generic_tables:
  - title: Patients
    name: patients
    description: Patient demographics from EMR
    data_domain: healthcare
    datalake: prime-health
    columns:
      - name: first_name
        title: First Name
        type: string
        description: Patient's first name
        privacy_requirement: redact_only
        is_required: true
        is_unique: true
        is_array: false

action_status_updaters: []
ai_agents: []
connected_apps: []
agentic_workflows: []
interoperability_contracts: []
data_activation_clients: []
```

## Rules

- **Append-only per turn.** Never rewrite earlier sections.
- **Reference by name, not id.** Ids are runtime; names are stable.
- **Secrets are placeholders.** `$AWS_ACCESS_KEY_ID`, `$ALVERA_API_KEY`,
  DB `user`/`pass` fields — never the resolved value. If the user
  supplied a literal, write `<set at runtime>`.
- The YAML is a **receipt**, not a config file. The API is the source
  of truth. When the user asks "what do I have?", call `list` endpoints.
- **Filename convention:** `alvera-<tenant-slug>.yaml`. If tenant slug
  is `acme-health`, the file is `alvera-acme-health.yaml`.
