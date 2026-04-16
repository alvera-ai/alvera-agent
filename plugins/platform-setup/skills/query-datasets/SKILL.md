---
name: query-datasets
description: >
  Query a PostgREST-fronted Alvera datalake, with two modes: (a) **chat mode** —
  run one query against a free-form PostgREST filter (e.g.
  `first_name=eq.John&limit=20`) and render the results as a markdown table
  directly in the conversation; or (b) **scaffold mode** — write a throwaway
  Vite + React explorer at `./<table>-explorer/` in the user's cwd so they can
  keep poking. Chat mode doubles as a compliance gate: if the user picks it,
  they're confirming the data is OK for me to see. Use when the user says
  "query X", "verify rows", "show me rows from Y", "scaffold an explorer",
  etc. Independently invokable. Elicits PostgREST base URL, schema
  (Accept-Profile), JWT (secret — never echoed, never persisted beyond
  `.env.local` in scaffold mode and a chmod 600 tempfile in chat mode), and
  table name. After scaffolding, runs `npm install` + `npm run dev` in the
  background and hands the user the URL Vite prints. Never auto-opens a
  browser.
---

# Query datasets (PostgREST)

Two modes, one skill. The user picks which at invocation:

- **(a) Chat mode** — skill runs one PostgREST query, renders results
  as a markdown table in the conversation. Good for quick verification
  of dummy / shareable data.
- **(b) Scaffold mode** — skill writes a minimal Vite + React app at
  `./<table>-explorer/` in the user's cwd. Good for regulated data the
  model shouldn't see, or for iterative poking.

Picking chat mode is an implicit compliance affirmation: the user is
saying "these rows are OK for you to see". If the data is regulated
(PHI, PII, BAA-covered), pick scaffold mode.

Purpose either way: **verification, not production**. Users running
this skill are checking rows landed after `/DAC-upload` or poking at a
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

1. **Pick the mode** — ask first, one question:

   > "Two modes:
   >
   >   **(a) Chat** — I run one query and show you the results here as
   >   a markdown table. Fastest for a spot check. By choosing this
   >   you're confirming the data is OK for me to see in chat — don't
   >   pick it for PHI / PII / BAA-covered rows.
   >
   >   **(b) Scaffold** — I write a local Vite + React app at
   >   `./<table>-explorer/`. You run it, you query, rows stay on your
   >   machine. Pick this for regulated data, or if you want to keep
   >   poking beyond one query.
   >
   > Which?"

   Don't default. Don't infer. Wait for `(a)` or `(b)`. Re-ask if the
   answer is ambiguous.

2. **Elicit fields in a single prompt** (both modes share fields 1–4;
   chat mode asks a 5th):

   > "I need:
   >   1. **PostgREST base URL** (no trailing slash, e.g.
   >      `https://api.prime-health.example`).
   >   2. **Schema name** — PostgREST's multi-schema selector, sent
   >      as the `Accept-Profile` header (typically `public`,
   >      `unregulated`, or a named datalake schema).
   >   3. **JWT** for Bearer auth. Secret — I won't echo it back.
   >   4. **Table name** to query (e.g. `patients`).
   >   5. *(chat mode only)* **Filter** — PostgREST syntax like
   >      `first_name=eq.John&limit=20`. Blank = first 20 rows via
   >      `limit=20`."

### Chat mode (a)

3a. **Run the query** via `curl` with a chmod 600 header tempfile so
    the JWT doesn't land in shell history / `ps`. Full procedure:
    `references/chat-query.md`.

    ```bash
    HDR=$(mktemp /tmp/pgrst-hdr.XXXXXX) && chmod 600 "$HDR"
    printf 'Authorization: Bearer %s\nAccept-Profile: %s\nAccept: application/json\n' \
      "$JWT" "$SCHEMA" > "$HDR"
    curl --fail --show-error --silent \
      -H "@$HDR" \
      "${URL}/${TABLE}${FILTER:+?$FILTER}"
    rm -f "$HDR"
    ```

    `rm` the header file on both success and failure (use `trap`).

4a. **Render results as a markdown table** in the chat — columns from
    `Object.keys(rows[0])`, `null`s rendered as `—`, nested objects
    JSON-stringified. Cap at the first 50 rows; if more, say "showing
    first 50 of N". Never render the raw PostgREST response as a JSON
    blob in chat unless the user asks.

5a. **Offer next steps:**

    > "Run another query (give me a filter), switch to scaffold mode
    > for a local app, or done?"

    If the user says "scaffold", jump to step 3b with the already-
    elicited URL/schema/JWT/table. Don't re-elicit — just reconfirm.

### Scaffold mode (b)

3b. **Pick a directory.** Default: `./<table>-explorer/` in the user's
    cwd. If it already exists and is non-empty, stop and ask
    (overwrite / pick a different name / skip). Never silently
    overwrite. If `table` has characters outside `[a-z0-9_-]`,
    normalise to kebab-case for the directory name but keep the
    original as the query target.

4b. **Confirm the plan** — plain-language recap:

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

5b. **Scaffold.** Write every file from the templates in
    `references/scaffold.md`. Write `.gitignore` **before** `.env.local`
    so if the user runs `git add` mid-scaffold the JWT doesn't get
    staged. `chmod 600 .env.local` immediately after write.

6b. **Install and start the dev server.** Be proactive — the user
    invoked scaffold mode to get a running explorer, not a folder of
    files to read a `npm install` command out of. From inside the
    scaffold directory:

    ```bash
    npm install           # foreground, fails fast if registry is unreachable
    npm run dev           # background (Bash tool: run_in_background: true)
    ```

    Then tail the dev server's stdout until Vite prints its "Local:"
    line (usually within 1–2 seconds), capture that URL, and surface
    it. If the user already said they use `pnpm` / `yarn` / `bun`,
    use that instead — default to `npm` if they haven't specified.

    Announce:

    > "Scaffolded and started ./patients-explorer/ —
    > **http://localhost:5173** (or whatever Vite picked).
    >
    > Open it in a browser. Filter syntax examples:
    >   - `limit=20` — first 20 rows
    >   - `first_name=eq.John&limit=20` — exact match
    >   - `dob=gte.1990-01-01&order=dob.desc` — range + order
    >
    > Dev server is running in the background — say `stop` to kill
    > it, or just leave it.
    >
    > JWT is in `.env.local` — gitignored, do not commit. Rotate if
    > it leaks. Another explorer, or done?"

    If `npm install` fails (no registry access, permission issue,
    lockfile corruption), surface the stderr and stop. Do not
    auto-retry. Do not silently fall back to a different package
    manager. The user fixes the environment, re-runs manually:
    `cd <dir> && npm install && npm run dev`.

## Hard constraints

- **JWT is secret.** Silent acknowledgement on receive — never
  prefix-echo, never repeat back, never write to the YAML receipt.
  - Scaffold mode: JWT goes to `.env.local` (chmod 600, gitignored).
  - Chat mode: JWT goes to a chmod-600 header tempfile under
    `/tmp/`, consumed by `curl -H @<file>`, `rm`'d in a `trap` so it
    goes on success, failure, and interrupt. Never inline via
    `-H "Authorization: Bearer $JWT"` — it lands in `ps` and shell
    history.
- **`.gitignore` before `.env.local`** (scaffold mode). Write order
  matters.
- **Run the dev server after scaffolding** (scaffold mode). The skill
  runs `npm install` in the foreground and `npm run dev` in the
  background, then surfaces the `Local: http://…` URL Vite prints.
  The user invoked scaffold mode to get a running explorer, not to
  manually type three commands. Do not ask permission first. Respect
  a non-default package manager only if the user mentioned one
  (`pnpm` / `yarn` / `bun`); otherwise default to `npm`.
- **Don't auto-open a browser** (scaffold mode). Surface the URL; the
  user opens it.
- **Don't silently paper over a failed `npm install`.** Surface the
  stderr, stop, and hand the user the manual command to retry. No
  auto-fallback to a different package manager, no retries.
- **Chat mode is a compliance opt-in.** If the user picked (a), results
  can legitimately appear in chat. If they hesitate ("maybe?") re-ask
  — don't default to rendering regulated rows just because elicitation
  succeeded.
- **No NL-to-SQL.** The filter input takes literal PostgREST syntax.
  Translating "patients born after 1990" → `dob=gte.1990-01-01` in
  chat is fine (conversational lookup); do not bake an LLM prompt into
  the app or into the chat-mode query path.
- **Cap chat output.** First 50 rows. If more matched, say so in the
  trailing note — don't dump everything.
- **One table per invocation.** Either one chat query (with optional
  follow-ups in the same turn) or one scaffold. Multiple tables → run
  the skill again.
- **Don't persist outside the scaffold or tempfile.** No global
  config, no `infra.yaml` entry, no recording of URLs or schemas
  across sessions.

## References

- `references/chat-query.md` — chat-mode curl flow + markdown rendering rules
- `references/scaffold.md` — scaffold-mode file templates
- `references/example-transcript.md` — reference dialogs for both modes
