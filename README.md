# alvera-platform-infra

Claude Code marketplace for Alvera platform plugins.

## What's here

| Plugin                                | Skills                            | What it does |
|---------------------------------------|-----------------------------------|--------------|
| [`platform-setup`](./plugins/platform-setup) | [`guided`](./plugins/platform-setup/skills/guided/SKILL.md) | Conversationally provision Alvera platform resources (data sources, tools, generic tables, action status updaters, AI agents) for an existing tenant. |

## Install

In Claude Code:

```
/plugin marketplace add alvera-ai/alvera-platform-infra
/plugin install platform-setup@alvera-platform-infra
```

Then invoke a skill from this plugin with:

```
/platform-setup:guided
```

## What this is not

- Not a tenant or datalake provisioner — those are admin operations.
- Not a runtime tool — no dataset search, workflow execution, or data
  ingestion. This is for *setup* only.

## Underlying SDK

The `platform-setup` plugin drives [`@alvera-ai/platform-sdk`](https://www.npmjs.com/package/@alvera-ai/platform-sdk).
The skill will install the SDK in your project if needed.

## License

MIT
