# Scaffold templates

Architecture mirrors `sfphg-ops-hub` conventions: postgrest-js for
queries, TanStack Table for rendering, Tailwind v4 for styling, jose
for JWT generation. Trimmed to single-page throwaway scope.

## File tree

```
<table>-explorer/
├── .env.local             # VITE_PGRST_* — chmod 600, gitignored
├── .env.local.example     # same keys, empty, safe to commit
├── .gitignore
├── README.md
├── index.html
├── package.json
├── vite.config.js
└── src/
    ├── main.jsx
    ├── index.css           # Tailwind v4 import
    ├── postgrest.js        # client wrapper: JWT gen + postgrest-js
    ├── DataTable.jsx       # TanStack React Table wrapper
    └── App.jsx             # page: search + table + pagination
```

**Write order:** `.gitignore` → `.env.local.example` → `.env.local`
(chmod 600) → the rest.

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
VITE_PGRST_JWT_SECRET=
VITE_PGRST_TABLE=
VITE_PGRST_ROLE=postgres
```

## `.env.local` (chmod 600)

```
VITE_PGRST_URL=<from user>
VITE_PGRST_SCHEMA=<from user>
VITE_PGRST_JWT_SECRET=<from user>
VITE_PGRST_TABLE=<from user>
VITE_PGRST_ROLE=postgres
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
    "@supabase/postgrest-js": "^2.99.0",
    "@tanstack/react-table": "^8.21.0",
    "clsx": "^2.1.0",
    "jose": "^6.0.0",
    "react": "^18.3.0",
    "react-dom": "^18.3.0",
    "tailwind-merge": "^3.0.0"
  },
  "devDependencies": {
    "@tailwindcss/vite": "^4.1.0",
    "@vitejs/plugin-react": "^4.3.0",
    "tailwindcss": "^4.1.0",
    "vite": "^5.4.0"
  }
}
```

## `vite.config.js`

```js
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";

export default defineConfig({
  plugins: [react(), tailwindcss()],
});
```

## `index.html`

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title><table> explorer</title>
  </head>
  <body class="bg-gray-50 text-gray-900">
    <div id="root"></div>
    <script type="module" src="/src/main.jsx"></script>
  </body>
</html>
```

## `src/index.css`

```css
@import "tailwindcss";
```

## `src/main.jsx`

```jsx
import React from "react";
import ReactDOM from "react-dom/client";
import App from "./App.jsx";
import "./index.css";

ReactDOM.createRoot(document.getElementById("root")).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
);
```

## `src/postgrest.js`

Client wrapper — generates a short-lived JWT from the secret on each
call, then returns a configured postgrest-js client. Mirrors the
`alvera-client.server.ts` pattern from sfphg-ops-hub.

```js
import { PostgrestClient } from "@supabase/postgrest-js";
import { SignJWT } from "jose";

const URL = import.meta.env.VITE_PGRST_URL;
const SCHEMA = import.meta.env.VITE_PGRST_SCHEMA;
const SECRET = import.meta.env.VITE_PGRST_JWT_SECRET;
const ROLE = import.meta.env.VITE_PGRST_ROLE || "postgres";

const encoder = new TextEncoder();

async function generateJWT() {
  return new SignJWT({ role: ROLE })
    .setProtectedHeader({ alg: "HS256" })
    .setExpirationTime("1h")
    .sign(encoder.encode(SECRET));
}

export async function createClient() {
  const token = await generateJWT();
  return new PostgrestClient(URL, {
    schema: SCHEMA,
    headers: { Authorization: `Bearer ${token}` },
  });
}
```

## `src/DataTable.jsx`

Generic TanStack React Table wrapper — sortable headers, no-results
state. Mirrors `sfphg-ops-hub/app/components/ui/data-table.tsx`.

```jsx
import {
  useReactTable,
  getCoreRowModel,
  flexRender,
} from "@tanstack/react-table";
import { clsx } from "clsx";
import { twMerge } from "tailwind-merge";

function cn(...inputs) {
  return twMerge(clsx(inputs));
}

export function DataTable({ columns, data, noResultsMessage = "No rows.", onSort, sortState }) {
  const table = useReactTable({
    data,
    columns,
    getCoreRowModel: getCoreRowModel(),
    manualSorting: true,
    state: { sorting: sortState },
    onSortingChange: onSort,
  });

  return (
    <div className="overflow-hidden rounded-md border border-gray-200">
      <table className="w-full border-collapse text-sm">
        <thead className="bg-gray-100">
          {table.getHeaderGroups().map((hg) => (
            <tr key={hg.id}>
              {hg.headers.map((h) => (
                <th
                  key={h.id}
                  className={cn(
                    "px-3 py-2 text-left text-xs font-medium uppercase tracking-wide text-gray-500",
                    h.column.getCanSort() && "cursor-pointer select-none hover:text-gray-900"
                  )}
                  onClick={h.column.getToggleSortingHandler()}
                >
                  {flexRender(h.column.columnDef.header, h.getContext())}
                  {{ asc: " ↑", desc: " ↓" }[h.column.getIsSorted()] ?? ""}
                </th>
              ))}
            </tr>
          ))}
        </thead>
        <tbody>
          {table.getRowModel().rows.length ? (
            table.getRowModel().rows.map((row) => (
              <tr key={row.id} className="border-t border-gray-100 hover:bg-gray-50">
                {row.getVisibleCells().map((cell) => (
                  <td key={cell.id} className="px-3 py-2 font-mono text-xs">
                    {flexRender(cell.column.columnDef.cell, cell.getContext())}
                  </td>
                ))}
              </tr>
            ))
          ) : (
            <tr>
              <td colSpan={columns.length} className="px-3 py-8 text-center text-gray-400">
                {noResultsMessage}
              </td>
            </tr>
          )}
        </tbody>
      </table>
    </div>
  );
}
```

## `src/App.jsx`

Main page: search input (debounced 300ms), DataTable, pagination. All
state is local (useState) — no routing needed for a throwaway tool.

```jsx
import { useState, useEffect, useRef, useMemo } from "react";
import { createClient } from "./postgrest.js";
import { DataTable } from "./DataTable.jsx";

const TABLE = import.meta.env.VITE_PGRST_TABLE;
const PAGE_SIZE = 20;

function cellRenderer(value) {
  if (value == null) return <span className="text-gray-300">—</span>;
  if (typeof value === "object") return JSON.stringify(value);
  return String(value);
}

export default function App() {
  const [rows, setRows] = useState([]);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(1);
  const [search, setSearch] = useState("");
  const [committed, setCommitted] = useState("");
  const [sorting, setSorting] = useState([]);
  const [error, setError] = useState(null);
  const [loading, setLoading] = useState(false);
  const timerRef = useRef();

  const handleSearch = (val) => {
    setSearch(val);
    clearTimeout(timerRef.current);
    timerRef.current = setTimeout(() => {
      setCommitted(val);
      setPage(1);
    }, 300);
  };

  useEffect(() => {
    let cancelled = false;
    (async () => {
      setLoading(true);
      setError(null);
      try {
        const client = await createClient();
        const from = (page - 1) * PAGE_SIZE;
        const to = from + PAGE_SIZE - 1;

        let query = client
          .from(TABLE)
          .select("*", { count: "exact" })
          .range(from, to);

        if (sorting.length) {
          const s = sorting[0];
          query = query.order(s.id, { ascending: !s.desc });
        }

        if (committed) {
          query = query.or(
            columns
              .filter((c) => c.accessorKey)
              .map((c) => `${c.accessorKey}.ilike.*${committed}*`)
              .join(",")
          );
        }

        const { data, error: err, count } = await query;
        if (cancelled) return;
        if (err) throw new Error(err.message);
        setRows(data || []);
        setTotal(count || 0);
      } catch (e) {
        if (!cancelled) setError(e.message);
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => { cancelled = true; };
  }, [page, sorting, committed]);

  const columns = useMemo(() => {
    if (!rows.length) return [];
    return Object.keys(rows[0]).map((key) => ({
      accessorKey: key,
      header: key,
      cell: ({ getValue }) => cellRenderer(getValue()),
      enableSorting: true,
    }));
  }, [rows]);

  const totalPages = Math.ceil(total / PAGE_SIZE);

  return (
    <main className="mx-auto max-w-screen-xl p-6 space-y-4">
      <div>
        <h1 className="text-xl font-semibold">{TABLE}</h1>
        <p className="text-sm text-gray-500">
          {import.meta.env.VITE_PGRST_URL} · schema{" "}
          <code className="bg-gray-100 px-1 rounded">{import.meta.env.VITE_PGRST_SCHEMA}</code>
        </p>
      </div>

      <div className="relative max-w-sm">
        <input
          type="search"
          placeholder="Search across columns…"
          value={search}
          onChange={(e) => handleSearch(e.target.value)}
          className="w-full rounded-md border border-gray-200 bg-gray-50 px-3 py-2 pl-9 text-sm focus:border-gray-400 focus:outline-none"
        />
        <svg
          className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-gray-400"
          fill="none" stroke="currentColor" viewBox="0 0 24 24"
        >
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
        </svg>
      </div>

      {error && (
        <pre className="rounded-md border border-red-200 bg-red-50 p-3 text-sm text-red-700 whitespace-pre-wrap">
          {error}
        </pre>
      )}

      <DataTable
        columns={columns}
        data={rows}
        sortState={sorting}
        onSort={setSorting}
        noResultsMessage={loading ? "Loading…" : "No rows."}
      />

      <div className="flex items-center justify-between text-sm text-gray-500">
        <span>
          {total.toLocaleString()} row{total === 1 ? "" : "s"}
          {loading && " · loading…"}
        </span>
        <div className="flex gap-2">
          <button
            onClick={() => setPage((p) => Math.max(1, p - 1))}
            disabled={page <= 1}
            className="rounded border px-3 py-1 text-xs disabled:opacity-30"
          >
            Prev
          </button>
          <span className="py-1">
            {page} / {totalPages || 1}
          </span>
          <button
            onClick={() => setPage((p) => Math.min(totalPages, p + 1))}
            disabled={page >= totalPages}
            className="rounded border px-3 py-1 text-xs disabled:opacity-30"
          >
            Next
          </button>
        </div>
      </div>
    </main>
  );
}
```

## `README.md`

```md
# <table> explorer

Local tool for querying the `<table>` table via PostgREST.

## Run

    npm install
    npm run dev

Open the URL Vite prints.

## Config

Values in `.env.local` (gitignored). The JWT secret is sensitive — do
not commit this file. The app generates short-lived JWTs (HS256, 1h)
from the secret on each request.
```

## After scaffolding

- Run `npm install` (foreground) then `npm run dev` (background).
- Wait for Vite's `Local: http://…` line, surface it.
- Remind: JWT secret in `.env.local`, gitignored.
