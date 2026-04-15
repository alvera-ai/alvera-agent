# Scaffold templates

Every file written by the skill. Copy verbatim, substituting
placeholders marked `<like_this>`.

## File tree

```
<table>-explorer/
├── .env.local             # VITE_PGRST_* — chmod 600, gitignored
├── .env.local.example     # same keys, empty, safe to commit
├── .gitignore             # node_modules, dist, .env.local
├── README.md              # 10-line usage blurb
├── index.html
├── package.json
├── vite.config.js
└── src/
    ├── main.jsx
    └── App.jsx
```

**Write order:** `.gitignore` → `.env.local.example` → `.env.local`
(chmod 600 immediately) → the rest. Writing `.gitignore` first means a
mistakenly-running `git add .` during scaffold won't stage the JWT.

## `.gitignore`

```
node_modules
dist
.env.local
.DS_Store
```

## `.env.local.example`

```
VITE_PGRST_URL=
VITE_PGRST_SCHEMA=
VITE_PGRST_JWT=
VITE_PGRST_TABLE=
```

## `.env.local` (chmod 600 after write)

```
VITE_PGRST_URL=<from user>
VITE_PGRST_SCHEMA=<from user>
VITE_PGRST_TABLE=<from user>
VITE_PGRST_JWT=<from user>
```

## `package.json`

```json
{
  "name": "<table>-explorer",
  "private": true,
  "version": "0.0.0",
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "preview": "vite preview"
  },
  "dependencies": {
    "react": "^18.3.0",
    "react-dom": "^18.3.0"
  },
  "devDependencies": {
    "@vitejs/plugin-react": "^4.3.0",
    "vite": "^5.4.0"
  }
}
```

## `vite.config.js`

```js
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({ plugins: [react()] });
```

## `index.html`

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title><table> — PostgREST explorer</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.jsx"></script>
  </body>
</html>
```

## `src/main.jsx`

```jsx
import React from 'react';
import ReactDOM from 'react-dom/client';
import App from './App.jsx';

ReactDOM.createRoot(document.getElementById('root')).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
);
```

## `src/App.jsx`

The whole app. Filter input → PostgREST fetch → results table. No
fallbacks, no swallowing — errors render verbatim. If `VITE_PGRST_*`
env vars are missing, render a setup warning and stop (better than a
confusing 401).

```jsx
import { useState } from 'react';

const URL = import.meta.env.VITE_PGRST_URL;
const SCHEMA = import.meta.env.VITE_PGRST_SCHEMA;
const JWT = import.meta.env.VITE_PGRST_JWT;
const TABLE = import.meta.env.VITE_PGRST_TABLE;

const MISSING = [
  !URL && 'VITE_PGRST_URL',
  !SCHEMA && 'VITE_PGRST_SCHEMA',
  !JWT && 'VITE_PGRST_JWT',
  !TABLE && 'VITE_PGRST_TABLE',
].filter(Boolean);

async function runQuery(filter) {
  const qs = filter.trim();
  const url = `${URL}/${TABLE}${qs ? `?${qs}` : ''}`;
  const res = await fetch(url, {
    headers: {
      Authorization: `Bearer ${JWT}`,
      'Accept-Profile': SCHEMA,
      Accept: 'application/json',
    },
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`${res.status} ${res.statusText} — ${text}`);
  return JSON.parse(text);
}

export default function App() {
  const [filter, setFilter] = useState('limit=20');
  const [rows, setRows] = useState([]);
  const [error, setError] = useState(null);
  const [loading, setLoading] = useState(false);

  if (MISSING.length) {
    return (
      <main style={{ fontFamily: 'system-ui', padding: 24 }}>
        <h1>Setup incomplete</h1>
        <p>Missing env vars in <code>.env.local</code>:</p>
        <ul>{MISSING.map((v) => <li key={v}><code>{v}</code></li>)}</ul>
        <p>Fill them in, then restart <code>npm run dev</code>.</p>
      </main>
    );
  }

  async function onRun(e) {
    e.preventDefault();
    setLoading(true);
    setError(null);
    try { setRows(await runQuery(filter)); }
    catch (err) { setError(err.message); setRows([]); }
    finally { setLoading(false); }
  }

  const cols = rows.length ? Object.keys(rows[0]) : [];

  return (
    <main style={{ fontFamily: 'system-ui, sans-serif', padding: 24, maxWidth: 1200, margin: '0 auto' }}>
      <h1 style={{ margin: 0 }}>{TABLE}</h1>
      <p style={{ color: '#666', marginTop: 4 }}>
        {URL} · schema <code>{SCHEMA}</code>
      </p>

      <form onSubmit={onRun} style={{ display: 'flex', gap: 8, margin: '16px 0' }}>
        <input
          value={filter}
          onChange={(e) => setFilter(e.target.value)}
          placeholder="PostgREST filter, e.g. first_name=eq.John&limit=20"
          style={{ flex: 1, padding: 8, fontFamily: 'ui-monospace, monospace' }}
        />
        <button type="submit" disabled={loading} style={{ padding: '8px 16px' }}>
          {loading ? 'Running…' : 'Run'}
        </button>
      </form>

      {error && (
        <pre style={{ background: '#fee', border: '1px solid #c00', padding: 12, whiteSpace: 'pre-wrap' }}>
          {error}
        </pre>
      )}

      {!error && rows.length > 0 && (
        <div style={{ overflowX: 'auto', border: '1px solid #ddd' }}>
          <table style={{ borderCollapse: 'collapse', width: '100%' }}>
            <thead style={{ background: '#f5f5f5' }}>
              <tr>{cols.map((c) => <th key={c} style={{ padding: 8, textAlign: 'left', borderBottom: '1px solid #ddd' }}>{c}</th>)}</tr>
            </thead>
            <tbody>
              {rows.map((r, i) => (
                <tr key={i}>
                  {cols.map((c) => (
                    <td key={c} style={{ padding: 8, borderBottom: '1px solid #eee', fontFamily: 'ui-monospace, monospace', fontSize: 12 }}>
                      {r[c] == null ? <span style={{ color: '#999' }}>null</span> : typeof r[c] === 'object' ? JSON.stringify(r[c]) : String(r[c])}
                    </td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
          <p style={{ color: '#666', padding: 8 }}>{rows.length} row{rows.length === 1 ? '' : 's'}</p>
        </div>
      )}

      {!error && !loading && rows.length === 0 && (
        <p style={{ color: '#666' }}>No rows yet. Enter a filter and hit Run.</p>
      )}
    </main>
  );
}
```

## `README.md`

```md
# <table> explorer

Throwaway local tool for querying the `<table>` table via PostgREST.
Not production.

## Run

    npm install
    npm run dev

Open the URL Vite prints. Type PostgREST filter syntax into the input
and hit Run.

## Filter examples

    limit=20                              # first 20 rows
    first_name=eq.John&limit=20           # exact match
    dob=gte.1990-01-01&order=dob.desc     # range + order

PostgREST reference:
<https://postgrest.org/en/stable/references/api/tables_views.html>

## Config

Values in `.env.local`. The JWT there is sensitive — do not commit
this file. Rotate the token if it leaks.
```
