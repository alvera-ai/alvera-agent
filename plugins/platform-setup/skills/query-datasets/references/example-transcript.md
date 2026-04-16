# Reference transcript

## Chat mode (a) — quick query, render in chat

```
USER: /query-datasets — show me 5 patients from last month

AGENT: Two modes:

         (a) Chat — I run one query and show results here as a
             markdown table. Picking this confirms the data is OK for
             me to see (so: dummy or shareable data, not PHI / BAA).
         (b) Scaffold — I write a local Vite + React app at
             ./<table>-explorer/. You run it, rows stay on your
             machine. Pick this for regulated data or iterative
             poking.

       Which?

USER: (a) — it's synthetic test data

AGENT: I need:
         1. PostgREST base URL
         2. Schema name (Accept-Profile)
         3. JWT (secret — silent on receive)
         4. Table name
         5. Filter (PostgREST syntax, or blank for limit=20)

USER: url=https://api.prime-health.example, schema=unregulated,
      jwt=eyJhbGciOi..., table=patients,
      filter=created_at=gte.2026-03-15&limit=5&order=created_at.desc

AGENT: [silent — no JWT echo]
       [mktemp /tmp/pgrst-hdr.XXXX, chmod 600, trap rm on EXIT/INT/TERM]
       [curl --fail --silent -H @<tempfile> "<url>/patients?<filter>"]

       **`patients`** · `https://api.prime-health.example` · schema
       `unregulated` · filter `created_at=gte.2026-03-15&limit=5&order=created_at.desc`

       | id | first_name | last_name | dob | created_at |
       |---|---|---|---|---|
       | 9f2c… | Sarah | Chen | 1988-03-14 | 2026-04-12T09:14:03Z |
       | 1ab7… | Miguel | Alvarez | 1974-11-02 | 2026-04-10T15:40:11Z |
       | 3d8e… | — | Johnson | 1991-07-22 | 2026-04-08T12:01:58Z |
       | 77ab… | Priya | Patel | 1983-01-30 | 2026-04-05T08:22:44Z |
       | cc91… | — | — | — | 2026-03-20T19:05:00Z |

       5 rows.

       Another filter (give me the string), switch to scaffold mode
       for a local app, or done?

USER: done

AGENT: [trap fires — /tmp/pgrst-hdr.XXXX removed]
       Cleaned up the JWT tempfile. Done.
```

## Chat mode — 401

```
USER: (a) same url/schema/table, jwt=eyJhbGciOi...<expired>,
      filter=limit=5

AGENT: [curl → exit 22]
       curl: (22) The requested URL returned error: 401
       {"message":"JWT expired","code":"PGRST301"}

       Token's expired. Give me a fresh JWT and I'll retry (same URL,
       schema, table, filter).
```

## Scaffold mode (b) — local explorer

```
USER: /query-datasets

AGENT: Two modes: (a) chat, (b) scaffold. Which?

USER: (b) — it's real PHI

AGENT: I need four things:
         1. PostgREST base URL (no trailing slash).
         2. Schema name (sent as Accept-Profile header).
         3. JWT for Bearer auth (secret — goes to .env.local,
            gitignored).
         4. Table name to query.

USER: url=https://api.prime-health.example, schema=unregulated,
      jwt=eyJhbGciOi..., table=patients

AGENT: [silent acknowledgement of JWT — don't echo or prefix]

       I'll write:
         - ./patients-explorer/package.json, vite.config.js,
           index.html, src/{main,App}.jsx, README.md
         - ./patients-explorer/.gitignore (excludes node_modules,
           dist, .env.local)
         - ./patients-explorer/.env.local (chmod 600) with:
             VITE_PGRST_URL=https://api.prime-health.example
             VITE_PGRST_SCHEMA=unregulated
             VITE_PGRST_TABLE=patients
             VITE_PGRST_JWT=<your JWT>
         - ./patients-explorer/.env.local.example (same keys, blank,
           safe to commit)

       Proceed? (y/n)

USER: y

AGENT: [mkdir patients-explorer]
       [write .gitignore]
       [write .env.local.example]
       [write .env.local; chmod 600]
       [write package.json, vite.config.js, index.html, README.md,
        src/main.jsx, src/App.jsx]

       [cd patients-explorer && npm install]
       → added 142 packages in 8s

       [npm run dev  (background)]
       → VITE v5.4.0  ready in 187 ms
         Local:   http://localhost:5173/

       Scaffolded and started ./patients-explorer/ —
       **http://localhost:5173**

       Open it in a browser. Filter examples:
         limit=20
         first_name=eq.John&limit=20
         dob=gte.1990-01-01&order=dob.desc

       Dev server is running in the background — say `stop` to kill
       it, or just leave it. JWT is in .env.local (gitignored). Another
       explorer, or done?
```

## Natural-language filter translation (on request)

```
USER: how do I show patients born after 1990?

AGENT: PostgREST filter for that:
         dob=gte.1990-01-01&order=dob.asc

       Paste that into the input and hit Run. If you want most recent
       first, swap `asc` → `desc`.
```

Translating NL → PostgREST filters in chat is fine — it's a cheap
lookup. Baking it into the app would require either an LLM backend
(adds complexity) or a hardcoded phrasebook (rots). Keep it in the
conversation.

## Notes on style

- **Silent on the JWT.** Never prefix-echo it ("got the JWT starting
  with eyJ..."). Acknowledge in the abstract, write / use, move on.
- **Mode first, fields second.** The (a)/(b) question gates everything
  else. Don't start eliciting URLs before you know which mode.
- **`.gitignore` before `.env.local`** (scaffold mode). Write order
  matters.
- **Tempfile trap** (chat mode). `trap 'rm -f "$HDR"' EXIT INT TERM`
  — not a trailing `rm`. Must survive Ctrl-C.
- **Run the dev server after scaffolding** (scaffold mode). Be
  proactive: `npm install` (foreground), `npm run dev` (background),
  capture Vite's `Local:` URL, hand it over. Don't dump a shell
  command and stop.
- **Don't try to guess the schema.** If the user's not sure, tell them
  it's usually `public` or matches a named schema from their datalake
  setup.
- **Cap chat output at 50 rows.** Say "showing first 50 of N" if
  truncated.
- **One table, one invocation.** Re-run the skill for more tables.
