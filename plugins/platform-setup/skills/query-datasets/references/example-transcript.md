# Reference transcript

```
USER: /query-datasets — I want to see if patient rows landed

AGENT: I need four things:
         1. PostgREST base URL
         2. Schema name (Accept-Profile header)
         3. JWT secret (HS256) — the app generates short-lived tokens
            from it. Goes to .env.local, never echoed.
         4. Table name to query

USER: url=http://localhost:3002, schema=regulated,
      secret=local-jwt-secret-min-32-chars-for-hs256-alg,
      table=regulated_patients

AGENT: [silent — no secret echo]

       I'll scaffold ./regulated_patients-explorer/ and start it:
         - Vite + React + Tailwind + postgrest-js + TanStack Table
         - JWT secret in .env.local (chmod 600, gitignored)
         - npm install && npm run dev after scaffolding

       Proceed? (y/n)

USER: y

AGENT: [mkdir regulated_patients-explorer]
       [write .gitignore]
       [write .env.local.example]
       [write .env.local; chmod 600]
       [write package.json, vite.config.js, index.html, README.md,
        src/{main,index.css,postgrest,DataTable,App}.jsx]

       [cd regulated_patients-explorer && npm install]
       → added 186 packages in 6s

       [npm run dev  (background)]
       → VITE v5.4.0  ready in 212ms
         Local: http://localhost:5173/

       Started — **http://localhost:5173**

       Open it in a browser. The app has:
         - Search bar (debounced, filters across text columns)
         - Sortable column headers (click to toggle)
         - Pagination (20 rows per page)
         - Error display (PostgREST errors render verbatim)

       JWT rotates per-request (1h expiry from your secret).
       Dev server runs in the background. .env.local is gitignored.

       Another explorer, or done?

USER: done

AGENT: Dev server still running in the background — it'll shut down
       when you close this session, or kill it manually with
       `kill $(lsof -ti:5173)`. Done.
```

## Notes on style

- **No chat-mode queries.** The skill never queries PostgREST itself.
  All data stays in the user's browser → their PostgREST endpoint.
  This is a deliberate safety choice: if the data is regulated, the
  model never sees it.
- **Be proactive.** Scaffold, install, start. Hand the user a URL.
- **Silent on the JWT secret.** Never prefix-echo, never repeat back.
- **`.gitignore` before `.env.local`.** Write order matters.
- **One table per explorer.** Re-run the skill for more tables.
