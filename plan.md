# Alvera AI — Platform Setup Agent — Plan

## Premise

Outcome-driven, conversational provisioning of Alvera platform resources.
The user describes a business goal; the skill derives the full dependency
chain, gap-analyses against existing resources, and provisions everything
in the correct order.

**Top-down design, bottom-up execution.**

**Anti-requirement:** no YAML input. The conversation is the input; the YAML
is an *output* receipt.

**Tenant is assumed pre-created** (admin-only operation).

## Architecture overhaul (v0.2.0)

### What changed

**Before (v0.1.0):** Plugin `platform-setup` with 5 separate skills:
`guided`, `custom-dataset-creation`, `DAC-upload`,
`agentic-workflow-creation`, `query-datasets`. Bottom-up flow: user picks
resource type → creates one → picks next → builds layers upward.

**After (v0.2.0):** Plugin `alvera-ai` with 1 skill `guided`. Top-down
flow: user describes outcome → skill derives dependency chain → gap
analysis → provisions in order.

### Why

- Users think in outcomes ("send review SMS"), not resources ("create an
  SMS tool, then create a workflow").
- Five skills meant five entry points and hand-offs between them.
  One skill with internal sub-flows is simpler.
- The old `guided` was a resource menu — pick one, create it, loop.
  The new `guided` is an outcome orchestrator.

### What merged

| Old skill | Became |
|-----------|--------|
| `guided` (resource loop) | Rewritten as top-down orchestrator |
| `custom-dataset-creation` | Merged into `references/data-pipeline.md` |
| `DAC-upload` | Merged into `references/data-pipeline.md` |
| `agentic-workflow-creation` | Merged into `references/workflows.md` |
| `query-datasets` | Merged into `references/query.md` |

### New structure

```
plugins/alvera-ai/
├── .claude-plugin/
│   └── plugin.json
├── README.md
├── hooks/
└── skills/
    └── guided/
        ├── SKILL.md              # top-down orchestrator
        └── references/
            ├── outcomes.md       # outcome → dependency chain catalog
            ├── resources.md      # per-resource elicitation tables
            ├── guardrails.md     # non-negotiable rules
            ├── scope.md          # in/out boundary
            ├── cli-cheatsheet.md # CLI command surface
            ├── data-pipeline.md  # file → table → template → upload
            ├── workflows.md      # templates, liquid vars, execution
            ├── query.md          # PostgREST explorer scaffold
            ├── yaml-receipt.md   # receipt format
            └── example-transcript.md
```

## Scope

### In — customer-exposed resources

| Resource                | Ops                              |
|-------------------------|----------------------------------|
| Data sources            | list, create, update             |
| Tools                   | list, get, create, update, delete|
| Generic tables          | list, create                     |
| Action status updaters  | list, create, update             |
| AI agents               | list, get, create, update, delete|
| Datalakes               | list, get, create, upload-link   |
| Connected apps          | list, get, create, update, sync-routes |
| Agentic workflows       | list, get, create, update, delete, execute, run |
| Interop contracts       | list, get, create, update, delete, run |
| Data activation clients | list, get, create, update, delete, run-manually, ingest, ingest-file |
| Datasets                | search, metadata (read-only)     |
| Ping                    | health check                     |

### Out

- PostgREST (internal)
- Sessions (admin seeding path)
- Tenant create (admin-only)
- Datalake create (provisioned per tenant) — now **in scope** for the skill
- MDM verify, connected app page management

## Architecture decisions

### SDK: `@alvera-ai/platform-sdk` (npm package) — shipped

Published under `@alvera-ai/*`. Typed params mean the LLM sees required
fields naturally through completions.

### No CLI (yet)

Agents that execute code call the SDK directly. CLI duplicates surface area
with no new use case today.

### Packaging: neutral markdown first

Generic agent playbook (plain `.md`) that any LLM can consume as context.

### Single skill

One entry point (`/alvera-ai:guided`) handles all resource types. Complex
sub-flows (data pipeline, workflow creation, query scaffolding) live as
reference files loaded on demand — not separate skills the user must
invoke.

## User journey (top-down)

**Bootstrap (once per session):**
1. Ask for tenant slug, API key, base URL.
2. Ask "emit an `infra.yaml` receipt as we go?" (default: yes).

**Per-outcome loop:**
1. Ask "what are you trying to achieve?" — open-ended.
2. Match to an outcome pattern from the catalog.
3. Derive the dependency chain (e.g. workflow → tool → data source → datalake).
4. List existing resources → gap analysis → show plan.
5. Provision in dependency order (bottom-up execution).
   - Each step: elicit missing fields → confirm → create → append receipt.
   - Complex sub-flows (data pipeline, workflows) follow dedicated reference docs.
6. Report what was created. Loop: "What else do you want to achieve?"

**Discovery:**
- "What do I have?" → call `list` endpoints. API is source of truth.

## Outcome catalog

| Outcome | Dependency chain |
|---------|-----------------|
| Send review SMS | workflow → SMS tool → data source → datalake |
| Onboard data from file | DAC → interop contract → generic table → data source → tool → datalake |
| Create AI agent | AI agent → tool → data source → datalake |
| Build automation | workflow → tools → AI agents → data source → datalake |
| Set up connected app | connected app → datalake |
| Push data from external | DAC → tool → data source → datalake |
| Query / verify data | explorer scaffold (no platform resources) |
| Status tracking | status updater → tool → data source → datalake |

## Guardrails

- **List before create** — check for name collisions. No implicit upsert.
- **Confirm destructives** — tool/agent delete requires explicit "yes delete `<name>`".
- **Secrets handling** — env var names preferred; never write resolved secrets to YAML.
- **Dependency ordering** — surface gaps, offer to create dependencies first.
- **Enum validation at conversation time** — reject invalid values using SDK types.
- **Scope refusal** — agent declines anything outside the allow-listed resources.
- **Read-only by default for discovery** — `list` / `get` are free; writes require confirmation.

## Build order

1. **Extract + publish `@alvera-ai/platform-sdk`** — ✅ **done.**
2. **Write the agent playbook** as a Claude Code plugin skill — ✅ **done** (v0.1.0).
3. **Overhaul to outcome-driven, single-skill architecture** — ✅ **done** (v0.2.0).
   - Plugin renamed `platform-setup` → `alvera-ai`.
   - Five skills merged into one `guided` skill.
   - Bottom-up resource loop replaced by top-down outcome orchestrator.
   - Reference files consolidated: data-pipeline.md, workflows.md, query.md.
4. **Live-test** — pressure-test against a real tenant.
5. **Defer** — CLI, MCP server packaging, additional runtime ops.

## SDK — shipped

- **Package:** [`@alvera-ai/platform-sdk`](https://www.npmjs.com/package/@alvera-ai/platform-sdk)
- **Auth:** `X-API-Key` only (admin session path removed)
- **Surface:** `ping`, `datalakes`, `dataSources`, `tools`,
  `genericTables`, `actionStatusUpdaters`, `aiAgents`, `connectedApps`,
  `agenticWorkflows`, `interopContracts`, `dataActivationClients`

## Skill — shipped (v0.2.0)

- **Plugin:** `alvera-ai`
- **Skill:** `guided` (invoked as `/alvera-ai:guided`)
- **Install flow:**
  ```
  /plugin marketplace add alvera-ai/alvera-agent
  /plugin install alvera-ai@alvera-agent
  /alvera-ai:guided
  ```
- **Pattern:** outcome-driven orchestrator with reference files for
  complex sub-flows (data pipeline, workflows, query scaffolding).
