---
name: query-datasets
description: >
  Scaffold a throwaway Vite + React explorer app in the user's cwd for
  querying a PostgREST endpoint. The app takes a free-form PostgREST filter
  string (e.g. `first_name=eq.John&limit=20`) and renders results in a table.
  Designed for quick row-level verification after data activation or ad-hoc
  querying of a generic table. Use when the user says "let me query X",
  "verify rows landed", "scaffold an explorer for table Y", or similar.
  Independently invokable — does not require a prior skill. Elicits
  PostgREST base URL, schema name (Accept-Profile), JWT (secret), and
  target table name. Does NOT run `npm install` for the user, does NOT
  commit code, does NOT auto-open a browser — just writes files.
---

# Query datasets (PostgREST + React)

Scaffolds a minimal Vite + React app at `./<table>-explorer/` in the
user's current working directory. The app is a single-file UI: a
filter input, a "Run" button, a results table. JWT sits in
`.env.local` (chmod 600, gitignored) — never in source, never echoed.

Purpose: **verification, not production**. Users running this skill are
usually checking that rows landed after a `/DAC-upload`, or poking at a
generic table from `/custom-dataset-creation`. It is not a BI tool.

## Prerequisites

- A running PostgREST endpoint fronting the target Postgres.
- A JWT the user can generate (their own role claim — don't ask them
  to give you a high-privilege token; a read-only role is plenty).
- A target table name (the `name` from a generic table, usually a
  snake_case identifier like `patients`).

None of the three are checkable by the skill — if the user gets them
wrong, the app will surface the PostgREST error verbatim on Run.

## Workflow

1. **Elicit four fields in a single prompt:**

   > "I need four things to scaffold the explorer:
   >   1. **PostgREST base URL** (no trailing slash, e.g.
   >      `https://api.prime-health.example`).
   >   2. **Schema name** — PostgREST's multi-schema selector, sent
   >      as the `Accept-Profile` header. If PostgREST fronts one
   >      schema only, it's that schema's name (typically
   >      `public`, `unregulated`, or a named schema from the
   >      datalake).
   >   3. **JWT** for Bearer auth. This is a secret — I'll write it
   >      to `.env.local` (chmod 600, gitignored). Don't worry, I
   >      won't echo it back.
   >   4. **Table name** to query (e.g. `patients`).
   > Ready when you are."

2. **Pick a directory.** Default: `./<table>-explorer/` in the user's
   cwd. If it already exists and is non-empty, stop and ask
   (overwrite / pick a different name / skip). Never silently
   overwrite. If `table` has characters outside `[a-z0-9_-]`,
   normalise to kebab-case for the directory name but keep the
   original as the query target.

3. **Confirm the plan** — plain-language recap:

   > "I'll write:
   >   - ./patients-explorer/package.json, vite.config.js,
   >     index.html, src/{main,App}.jsx, README.md
   >   - ./patients-explorer/.gitignore (excludes node_modules,
   >     dist, .env.local)
   >   - ./patients-explorer/.env.local (chmod 600) with:
   >       VITE_PGRST_URL=https://api.prime-health.example
   >       VITE_PGRST_SCHEMA=unregulated
   >       VITE_PGRST_TABLE=patients
   >       VITE_PGRST_JWT=<your JWT>
   >   - ./patients-explorer/.env.local.example (same keys, blank,
   >     safe to commit)
   >
   > Proceed? (y/n)"

4. **Scaffold.** Write every file from the templates in
   `references/scaffold.md`. Write `.gitignore` **before** `.env.local`
   so if the user runs `git add` mid-scaffold the JWT doesn't get
   staged. `chmod 600 .env.local` immediately after write.

5. **Tell the user how to run it.** Do not run `npm install` yourself
   — the user may use `pnpm` / `yarn` / `bun`, and their toolchain
   (asdf / nvm / rtx) is theirs.

   > "Generated ./patients-explorer/. Run:
   >
   >   cd patients-explorer && npm install && npm run dev
   >
   > Open the URL Vite prints. Type PostgREST filter syntax into the
   > input and hit Run. Examples:
   >   - `limit=20` — first 20 rows
   >   - `first_name=eq.John&limit=20` — exact match
   >   - `dob=gte.1990-01-01&order=dob.desc` — range + order
   >
   > PostgREST reference:
   > https://postgrest.org/en/stable/references/api/tables_views.html
   >
   > JWT is in `.env.local` — gitignored, do not commit. Rotate if it
   > leaks. Another explorer, or done?"

## Hard constraints

- **JWT is secret.** Write to `.env.local`, never to source, never to
  a receipt file, never echo it back to the user (not even a prefix —
  don't confirm "got the JWT starting with eyJhbGc..."). Silent
  acknowledgement, write, move on.
- **`.gitignore` before `.env.local`.** The order of writes matters.
- **Don't run `npm install`.** That's the user's call. Scaffold and
  stop.
- **Don't auto-open a browser.** Print the run command and let Vite
  print the URL.
- **No NL-to-SQL.** The filter input takes literal PostgREST syntax.
  If the user wants "show me patients born after 1990", translate it
  back to them as `dob=gte.1990-01-01` in chat — don't bake a prompt
  into the app.
- **One table per explorer.** The app is hard-coded to
  `VITE_PGRST_TABLE`. If the user wants multiple tables, run the skill
  multiple times (different directories).
- **Don't persist anywhere outside the scaffold.** No global config,
  no `infra.yaml` entry. If the user wants to record that an explorer
  exists, they can commit the scaffold (minus `.env.local`).

## References

- `references/scaffold.md` — every file that gets written, verbatim
- `references/example-transcript.md` — reference dialog
