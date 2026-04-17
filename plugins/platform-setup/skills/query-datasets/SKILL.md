---
name: query-datasets
description: >
  Scaffold a local Vite + React explorer app for querying an Alvera datalake
  via PostgREST. Uses `@supabase/postgrest-js` for query building,
  `@tanstack/react-table` for sortable/paginated data tables, Tailwind CSS v4
  for styling, and `jose` for client-side JWT generation. Data never leaves
  the user's machine — the app runs locally and queries PostgREST directly,
  so there is no compliance concern around the skill reading sensitive rows.
  Use when the user says "query X", "verify rows", "show me rows from Y",
  "scaffold an explorer", or similar. Independently invokable — does not
  require a prior skill. Elicits PostgREST base URL, JWT secret (not the JWT
  itself — the app generates short-lived tokens from it), schema
  (Accept-Profile), and table name. After scaffolding, runs `npm install` +
  `npm run dev` and hands the user the URL Vite prints.
---

# Query datasets (PostgREST explorer)

Scaffolds a local Vite + React app at `./<table>-explorer/` in the
user's cwd. The app queries PostgREST directly from the browser —
**data never enters the conversation**. This eliminates any compliance
concern: regulated, PHI, BAA-covered data is fine because the skill
never sees a single row.

Purpose: **verification after data activation, or ad-hoc querying**.
Not a BI tool.

## Stack (mirrors `sfphg-ops-hub` conventions)

| Concern        | Library                         | Notes                             |
|----------------|---------------------------------|-----------------------------------|
| Build          | Vite 5                          | Fast dev server, HMR              |
| UI             | React 18 + Tailwind CSS v4      | `@tailwindcss/vite` plugin, no config file |
| Data table     | `@tanstack/react-table`         | Sortable headers, pagination      |
| PostgREST      | `@supabase/postgrest-js`        | `.from().select().order().range()` |
| JWT            | `jose`                          | HS256, 1h expiry, generated in-app from secret |
| Utilities      | `clsx`, `tailwind-merge`        | Class name merging                |

## Prerequisites

- A running PostgREST endpoint fronting the target Postgres.
- The **JWT secret** (HS256) — the app generates short-lived tokens
  from it, so we need the secret, not a pre-minted token. The secret
  goes into `.env.local` (chmod 600, gitignored).
- A target table name.

## Workflow

1. **Elicit four fields in a single prompt:**

   > "I need:
   >   1. **PostgREST base URL** (no trailing slash).
   >   2. **Schema name** — PostgREST's `Accept-Profile` header
   >      (typically `regulated`, `unregulated`, or `public`).
   >   3. **JWT secret** (HS256) — the app will generate short-lived
   >      tokens from it. Secret — goes to `.env.local`, never echoed.
   >   4. **Table name** to query (e.g. `regulated_patients`)."

2. **Pick a directory.** Default: `./<table>-explorer/`. If it exists
   and is non-empty, stop and ask (overwrite / rename / skip).

3. **Confirm.**

   > "I'll scaffold ./patients-explorer/ and start it:
   >   - Vite + React + Tailwind + postgrest-js + TanStack Table
   >   - JWT secret in .env.local (chmod 600, gitignored)
   >   - `npm install && npm run dev` after scaffolding
   >
   > Proceed? (y/n)"

4. **Scaffold.** Write files per `references/scaffold.md`. Order:
   `.gitignore` → `.env.local.example` → `.env.local` (chmod 600) →
   everything else.

5. **Install and start.**

   ```bash
   cd <dir> && npm install     # foreground
   npm run dev                 # background
   ```

   Wait for Vite's `Local:` line, surface the URL:

   > "Started — **http://localhost:5173**
   >
   > Open it in a browser. The app has:
   >   - Search bar (debounced, filters across text columns)
   >   - Sortable column headers (click to toggle)
   >   - Pagination (20 rows per page)
   >   - Error display (PostgREST errors render verbatim)
   >
   > Dev server runs in the background. JWT rotates per-request
   > (1h expiry from your secret). `.env.local` is gitignored.
   >
   > Another explorer, or done?"

## Stance: be proactive

Scaffold and start. Don't dump files and stop. The user invoked this
skill to see an explorer — give them a running one.

## Hard constraints

- **No chat-mode queries.** The skill never queries PostgREST itself
  and never renders data rows in the conversation. All data stays in
  the user's browser → their PostgREST. This is a deliberate safety
  choice: if the data is regulated, the model never sees it.
- **JWT secret is secret.** Write to `.env.local` only. Never echo,
  never log, never write to `infra.yaml`. The app generates tokens
  from it via `jose` (HS256, 1h expiry) — the secret never leaves
  the user's machine.
- **`.gitignore` before `.env.local`.** Write order matters.
- **Run the dev server.** `npm install` foreground, `npm run dev`
  background, surface Vite's URL. Default to `npm`; respect
  `pnpm` / `yarn` / `bun` if the user named one.
- **Don't auto-open a browser.** Surface the URL.
- **Don't paper over a failed `npm install`.** Surface stderr, stop.
- **One table per explorer.** Multiple tables → run the skill again
  (separate directories).

## References

- `references/scaffold.md` — file templates (architecture + code)
- `references/example-transcript.md` — reference dialog
