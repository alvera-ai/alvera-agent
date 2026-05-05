# alvera-agent

Claude Code marketplace for Alvera platform plugins.

## What's here

| Plugin | Skill | What it does |
|--------|-------|--------------|
| [`alvera-ai`](./plugins/alvera-ai) | [`guided`](./plugins/alvera-ai/skills/guided/SKILL.md) | Outcome-driven provisioning: user describes a business goal, the skill derives the full dependency chain, gap-analyses, and provisions everything in order. Handles all resource types in a single skill. |

## How it works

**Top-down design, bottom-up execution.** The user says "I want to send
review SMS after appointments" and the skill derives: workflow → SMS tool →
data source → datalake. It checks what exists, provisions what's missing,
and tests along the way.

All resource types handled in one skill: datalakes, data sources, tools,
generic tables (with compliance gate), AI agents, workflows (with templates),
connected apps, interop contracts, data activation clients, file uploads,
and PostgREST explorers.

## Install

In Claude Code:

```
/plugin marketplace add alvera-ai/alvera-agent
/plugin install alvera-ai@alvera-agent
```

Then invoke:

```
/alvera-ai:guided
```

## Underlying SDK

The plugin drives [`@alvera-ai/platform-sdk`](https://www.npmjs.com/package/@alvera-ai/platform-sdk).

## License

MIT
