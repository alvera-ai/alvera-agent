# alvera-ai

Outcome-driven Alvera platform provisioning via
[`@alvera-ai/platform-sdk`](https://www.npmjs.com/package/@alvera-ai/platform-sdk).

## How it works

Instead of asking "what resource do you want to create?", this plugin asks
**"what are you trying to achieve?"** and derives the full dependency chain
automatically.

Example: "I want to send review SMS after appointments" → the skill works
backwards: workflow needs an SMS tool, which needs a data source, which
needs a datalake. It checks what exists, provisions what's missing in
dependency order, and tests along the way.

## Handles everything in one skill

- Datalakes, data sources, tools, AI agents, connected apps
- Generic tables with compliance gate and column profiling
- Data ingestion with anti-pattern detection and Liquid template generation
- Agentic workflows with production templates, dry-run testing, and promotion
- PostgREST explorer scaffolding for data verification
- Action status updaters, interop contracts, data activation clients

## Install

```
/plugin marketplace add alvera-ai/alvera-agent
/plugin install alvera-ai@alvera-agent
```

Then invoke:

```
/alvera-ai:guided
```

## What this is not

- Not a tenant or datalake provisioner — those are admin operations.
- Not a runtime tool — no dataset search, workflow execution monitoring,
  or data ingestion outside of setup context.

## License

MIT
