# platform-setup

Claude Code plugin for conversationally provisioning Alvera platform
resources via [`@alvera-ai/platform-sdk`](https://www.npmjs.com/package/@alvera-ai/platform-sdk).

## Skills

### `guided` — `/platform-setup:guided`

Conversationally provision data sources, tools, generic tables, action
status updaters, and AI agents for a tenant + datalake that already
exist. The skill:

- Asks the user for credentials and target datalake once, up front.
- Elicits resource fields conversationally — no YAML input required.
- Validates enums and required fields *before* any API call.
- Lists existing resources before creating to detect collisions.
- Confirms destructive operations explicitly.
- Emits an `infra.yaml` receipt as it goes (opt-in at start).
- Refuses out-of-scope operations (tenant create, runtime ops, etc.).

See [`skills/guided/SKILL.md`](./skills/guided/SKILL.md) for the full
behavior contract.

## Install

```
/plugin marketplace add alvera-ai/alvera-agent
/plugin install platform-setup@alvera-agent
```
