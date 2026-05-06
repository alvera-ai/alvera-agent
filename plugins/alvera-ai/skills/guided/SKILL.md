---
name: guided
description: >
  Outcome-driven Alvera platform provisioning. The user describes a business
  goal ("send review SMS after appointments", "onboard patient data from CSV",
  "create an AI agent for claim triage") and the skill derives the full
  dependency chain, checks what already exists, and provisions everything in
  the correct order — bottom-up execution, top-down design. Handles all
  resource types: datalakes, data sources, tools, generic tables (with
  compliance gate and column profiling), AI agents, agentic workflows (with
  templates and dry-run testing), connected apps, interop contracts, data
  activation clients, file ingestion (anti-pattern detection, Liquid template
  generation, sandbox testing), and PostgREST explorer scaffolding. Drives
  the `alvera` CLI from `@alvera-ai/platform-sdk`. Auth is session-based —
  the user runs `alvera login` themselves. Emits an `alvera-<tenant-slug>.yaml` receipt.
  Use when the user says anything about setting up, provisioning, onboarding,
  creating, or configuring Alvera platform resources.
---

# Alvera AI — Guided Setup

Outcome-driven provisioning. The user describes what they want to achieve;
the skill derives what's needed, checks what exists, and builds in order.

**Top-down design, bottom-up execution:**
- User: "I want to send review SMS after appointments"
- Skill: derives → datalake → data source → SMS tool → workflow
- Skill: checks → datalake exists, data source exists, tool missing, workflow missing
- Skill: provisions in order → tool → workflow → done

## Workflow

### Step 1: Planning (outcome elicitation)

Ask the user what they want to achieve — not what resource to create.

> "What are you trying to set up? Describe the goal — e.g.
> 'send review SMS after appointments', 'onboard patient data from a CSV',
> 'create an AI agent for triage', 'build an appointment reminder workflow',
> 'push data from a file'. Or name a specific resource if you know what you need."

Match the outcome to a dependency chain using `references/outcomes.md`.

If the outcome maps to a known chain, derive the plan. If the user names a
specific resource directly, treat it as a single-resource outcome (minimal
chain). If the outcome is ambiguous, ask one clarifying question and proceed.

### Step 2: Bootstrap

Auto-detect first, ask only what's missing. Returning users should not
re-answer questions the CLI already knows.

**Bootstrap sequence (run silently, no questions):**

1. **CLI resolution** — `alvera --version` or
   `npx -p @alvera-ai/platform-sdk alvera --version`. If both fail, hand
   the user `npm install -g @alvera-ai/platform-sdk` and stop.
   See `references/cli-cheatsheet.md`.
2. **Check default profile** — `alvera whoami`. If it returns a valid
   session (profile, tenant, email, token), present it:
   > "Found existing session: profile `default`, tenant `acme-health`,
   > logged in as user@example.com. Proceed with this? (y/n)"
   If yes, skip to datalake. If no, ask which profile or tenant to use.
3. **No session** — if `whoami` fails or shows no token:
   - Check if `alvera configure` has been run (profile exists but no session).
     If yes: "Please run `alvera login` to authenticate."
   - If no profile at all: ask for tenant slug and base URL (default
     `https://admin.alvera.ai`), run configure, then ask user to login.
4. **Tool not set up** — if the user hasn't set up their Alvera platform
   account yet, direct them to https://alvera.ai and stop.
5. **Pick datalake** — `alvera datalakes list`. If one exists, use it
   (tell the user which). If multiple, ask which. If none, offer to create.

Receipt: always emit `alvera-<tenant-slug>.yaml` — don't ask.

**Only ask questions the CLI can't answer.** A returning user with a
valid session and one datalake should reach Step 3 with zero prompts.

If no datalake exists, offer to create one:

**Option A (preferred): Provision Postgres via Neon** — use the Neon API
to create a project and get connection details in a single call. See
`references/neon-project.md` for the full API surface, response shape,
and mapping to Alvera datalake DB role fields. Requires `NEON_API_KEY`
env var. One API call returns host, port, database, role, and password.

**Option B: Use `alvera init infra-setup`** — generates a `.env` with all
datalake fields (name, data domain, timezone, pool size, 4 DB roles, 2
storage variants). Fill it out, then create the datalake from those values.

After obtaining connection details, create the datalake on Alvera via
`alvera datalakes create` per `references/resources.md` → Datalake.
All four Alvera roles (regulated/unregulated × reader/writer) can reuse
the same Neon connection unless the user needs isolation.

Session state to retain: `profile`, `tenantSlug`, `datalakeSlug`,
`datalakeId`, `baseUrl`.

**Context switching:** If the user says "now do this for a different
datalake" or "switch to tenant X", re-run the relevant bootstrap checks
(whoami, datalakes list) and update session state. Never silently use
stale state from a previous datalake/tenant.

### Step 3: Gap analysis

For each resource in the derived chain, check if it already exists:

```bash
alvera --profile <p> <resource> list ...   # per resource type
```

Present the gap analysis:

> "To achieve **review SMS after appointments**, I need:
>   ✓ Datalake `acme-health` — exists
>   ✓ Data source `appointments` — exists
>   ✗ SMS tool — missing
>   ✗ Review workflow — missing
>
> I'll create the missing resources in this order:
>   1. SMS tool (depends on: data source ✓)
>   2. Review workflow (depends on: SMS tool, data source ✓)
>
> Proceed? (y/n)"

When everything already exists, tell the user and ask if they want to
create something additional or adjust.

### Step 4: Execute plan

Provision resources in dependency order. For each:

1. **List** existing to detect collisions (guardrails: no silent upsert).
2. **Elicit** missing fields per `references/resources.md`.
3. **Confirm** in plain language (bullets, not JSON).
4. **Create** via CLI (`references/cli-cheatsheet.md`).
5. **Append** to `alvera-<tenant-slug>.yaml` if receipt enabled (`references/yaml-receipt.md`).
6. **Move** to next resource in the chain.

Complex sub-flows handled inline:

- **Data pipeline** (file → table → upload): follow `references/data-pipeline.md`
  for compliance gate, column profiling, table creation, anti-pattern scan,
  interop template generation, sandbox test, and upload.
- **Workflow creation** (template or custom): follow `references/workflows.md`
  for template selection, custom build, draft creation, dry-run test, log
  interpretation, and promotion to live.
- **Query/inspect data**: follow `references/query.md` for dataset search.
- **Connected app setup**: run `alvera init connected-app` to generate a
  `.env` with `ALVERA_BASE_URL`, `ALVERA_TENANT`, `ALVERA_DATALAKE`, and
  `ALVERA_CONNECTED_APP`. User fills values, app reads from env.

**Fallback: `alvera raw`** — if a CLI command fails or the needed endpoint
isn't wrapped by the SDK yet, use:

```bash
alvera raw <METHOD> <path> [--body <json>] [--body-file <path>] [--no-parse]
```

This sends an authenticated HTTP request directly. Use it to unblock
provisioning when a specific command errors out — then report the raw
response to the user.

After the chain is complete, report what was created.

### Step 5: Loop

> "Done — review SMS workflow is live. What else do you want to achieve?"

Continue until the user says done. On done, suggest `alvera logout`.

## Stance: be proactive

Assume forward progress. Default to the positive action, confirm with y/n.
Don't present long menus when one path is obvious.

- Resolve everything possible before asking.
- When only one option exists, use it and tell the user.
- Anti-pattern scans and sandbox tests run automatically.
- When the user agrees, move immediately — don't re-confirm.

**Fast-path vs confirmation-required:**

| Action | Speed |
|--------|-------|
| Resource creation (non-destructive) | Confirm once with bullet summary, then create |
| Anti-pattern scan, sandbox test | Run automatically, no confirmation |
| Dry-run workflow test | Run automatically after draft creation |
| Delete a resource | Require `yes delete <name>` exactly |
| Promote workflow to live | Require explicit y/n |
| `sync-routes` on connected app | Require explicit y/n |
| Update existing resource | Show old → new diff, require y/n |

## Hard constraints

Read on first user interaction:

- `references/scope.md` — what is in/out of scope, with refusal language.

Read on first create or update:

- `references/guardrails.md` — non-negotiable rules: no silent upsert,
  destructive confirmations, secrets handling, dependency ordering,
  read-before-write for updates, partial chain failure recovery.
- `references/updates.md` — per-resource mutability rules (which fields
  are locked at creation).

Read on errors:

- `references/errors.md` — error catalog with causes and recovery steps.

## CLI

`alvera` from [`@alvera-ai/platform-sdk`](https://www.npmjs.com/package/@alvera-ai/platform-sdk)
(>= 0.8.0). Two invocation forms:

```bash
npx -p @alvera-ai/platform-sdk alvera <command>   # zero-install
alvera <command>                                    # if installed globally
```

Auth is session-based, stored AWS-CLI-style under `~/.alvera-ai/`.
User runs `alvera login` in their own shell. Skill never sees the password.

Key commands beyond resource CRUD:

```bash
alvera init connected-app   # generate .env for app integration
alvera init infra-setup     # generate .env for datalake infrastructure
alvera raw <METHOD> <path>  # authenticated HTTP escape hatch
```

## References

- `references/outcomes.md` — outcome → dependency chain catalog
- `references/resources.md` — per-resource field elicitation rules
- `references/updates.md` — per-resource mutability rules for updates
- `references/guardrails.md` — non-negotiable rules
- `references/errors.md` — error catalog with causes and recovery steps
- `references/scope.md` — allowed/refused operations
- `references/cli-cheatsheet.md` — CLI command surface (incl. batch ops, init)
- `references/data-pipeline.md` — file → table → template → upload flow
- `references/workflows.md` — workflow templates, liquid variables, execution
- `references/query.md` — dataset search, inspection, and post-provisioning monitoring
- `references/yaml-receipt.md` — emitted YAML schema and rules
- `references/neon-project.md` — Neon API for Postgres provisioning (datalake DB backend)
- `references/example-transcript.md` — reference end-to-end conversations
- `scripts/alvera-profile.py` — column profiling script (used by data-pipeline)
- `scripts/alvera-scan.py` — anti-pattern scanner script (used by data-pipeline)
- `templates/review-sms.json` — Template A: Review SMS Workflow body
- `templates/cahps-survey.json` — Template B: CAHPS Survey Workflow body
- `templates/minimal-scaffold.json` — Template C: minimal workflow scaffold
