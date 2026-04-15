# Reference transcript

```
USER: /query-datasets

AGENT: I need four things to scaffold the explorer:
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

       Generated ./patients-explorer/. Run:

         cd patients-explorer && npm install && npm run dev

       Open the URL Vite prints. Type PostgREST filter syntax into the
       input and hit Run. Examples:
         limit=20
         first_name=eq.John&limit=20
         dob=gte.1990-01-01&order=dob.desc

       PostgREST reference:
       https://postgrest.org/en/stable/references/api/tables_views.html

       JWT is in .env.local — gitignored, do not commit. Rotate if it
       leaks. Another explorer, or done?
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
  with eyJ..."). Acknowledge in the abstract, write, move on.
- **`.gitignore` before `.env.local`.** Write order matters.
- **Don't run `npm install`.** Scaffold + instructions. Stop.
- **Don't try to guess the schema.** If the user's not sure, tell them
  it's usually `public` or matches a named schema from their datalake
  setup.
- **One table per explorer.** Re-run for more tables. Different
  directories. Simple.
