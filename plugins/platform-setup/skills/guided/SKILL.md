---
name: guided
description: >
  Conversationally provision Alvera platform resources (data sources, tools, generic tables,
  action status updaters, AI agents) for a tenant that already exists. Use when the user
  wants to set up infrastructure on Alvera, "create a data source", "add a tool", "wire up
  an AI agent", or similar. Drives the @alvera-ai/platform-sdk; never asks the user for a
  YAML file — elicits fields conversationally and emits an infra.yaml receipt. Do NOT use
  for tenant or datalake provisioning (admin-only) or for runtime ops like dataset search
  or workflow execution.
---

# Alvera Platform — Guided Setup

Conversationally provision Alvera platform resources for an existing
tenant + datalake. Conversation is the input; an `infra.yaml` receipt is
the output. The user never writes YAML.

## Workflow

1. **Bootstrap the session** — see `references/bootstrap.md`. Collect
   tenant slug, API key, base URL, receipt preference. Verify
   connectivity with `api.ping()` and pick the target datalake.
2. **Open the resource loop** — ask what the user wants to set up.
3. **Per resource:**
   - **List first** to detect collisions.
   - **Elicit fields** per `references/resources.md` (one section per
     resource type with required, optional, and enum constraints).
   - **Validate enums at conversation time** — never roundtrip to the API
     to discover a bad enum.
   - **Echo the payload** for explicit confirmation.
   - **Call create** via the SDK (`references/sdk-cheatsheet.md`).
   - **Append to `infra.yaml`** if the receipt is enabled
     (`references/yaml-receipt.md`).
4. Loop until the user is done.

## Hard constraints

Read these before any user interaction:

- `references/scope.md` — what is in/out of scope, with refusal language.
- `references/guardrails.md` — non-negotiable rules: no silent upsert,
  destructive confirmations, secrets handling, dependency ordering,
  read-before-write for updates.

## SDK

This skill drives [`@alvera-ai/platform-sdk`](https://www.npmjs.com/package/@alvera-ai/platform-sdk).
Install it in the user's project if missing:

```bash
npm install @alvera-ai/platform-sdk
```

All SDK methods throw on non-2xx. Catch and surface errors verbatim — no
fallbacks, no swallowing.

## References

- `references/scope.md` — allowed/refused operations
- `references/bootstrap.md` — first-turn questions and connectivity checks
- `references/guardrails.md` — non-negotiable rules
- `references/resources.md` — per-resource field elicitation rules
- `references/yaml-receipt.md` — emitted YAML schema and rules
- `references/sdk-cheatsheet.md` — SDK call signatures
- `references/example-transcript.md` — reference end-to-end conversation
