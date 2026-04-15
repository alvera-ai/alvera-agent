# Chat mode — curl + markdown rendering

One query, results rendered as a markdown table in the conversation.
No files written, no state persisted. JWT touches disk only inside a
chmod-600 tempfile consumed by `curl` and `rm`'d immediately.

## The curl call

```bash
HDR=$(mktemp /tmp/pgrst-hdr.XXXXXX)
chmod 600 "$HDR"
trap 'rm -f "$HDR"' EXIT INT TERM

cat > "$HDR" <<EOF
Authorization: Bearer $JWT
Accept-Profile: $SCHEMA
Accept: application/json
EOF

URL_FULL="${URL}/${TABLE}${FILTER:+?$FILTER}"

curl --fail --show-error --silent \
  -H "@$HDR" \
  "$URL_FULL"
```

Why the tempfile:

- `curl -H "Authorization: Bearer $JWT"` puts the JWT in process args
  (visible via `ps`) and shell history (`set -o history`). Not fine
  even locally.
- `curl -H @/path/to/file` reads headers from the file — never
  appears in `ps`.
- `chmod 600` limits read to the owner.
- `trap ... EXIT INT TERM` guarantees removal on normal exit, Ctrl-C,
  and `SIGTERM`. Do **not** rely on a trailing `rm` line — a `set -e`
  failure between mktemp and rm would skip it.

Never:

- `echo $JWT` (to stdout or anywhere).
- `export JWT=...` and then rely on `envsubst` or similar — that
  leaves the var in the shell's env for the rest of the session and
  inherited subprocesses.
- Pass the JWT inline in any argument that later gets logged.

## Failure modes

Curl exits non-zero → surface stderr to the user verbatim. Common
causes and what to say:

| Status / message                          | Likely cause                                             | Re-elicit  |
|-------------------------------------------|----------------------------------------------------------|------------|
| `401 Unauthorized`                        | JWT expired / wrong role / wrong secret                  | JWT        |
| `401 JWT expired`                         | Token past `exp`                                         | JWT        |
| `403 permission denied for ...`           | Role can't read the table / schema                       | schema, JWT |
| `404 Not Found`                           | Table doesn't exist in that schema, or URL typo          | URL, schema, table |
| `406 Not Acceptable`                      | `Accept-Profile` schema doesn't exist                    | schema     |
| connection refused / timeout              | Wrong URL, PostgREST not running                         | URL        |

Do not retry on 401/403 with a different guess — the user has to fix
the input.

## Rendering

Input: PostgREST response, a JSON array of row objects.

- Columns: `Object.keys(rows[0])` — order as returned by PostgREST
  (matches the column order in the query's `select`, or table
  definition order if no explicit select).
- Rows: cap at 50. If `rows.length > 50`, trim and append a trailing
  note: `showing first 50 of 1,234 matched (add &limit=N to the filter
  to override)`.
- Cell values:
  - `null` → `—` (em dash).
  - Objects / arrays → `JSON.stringify(value)`.
  - Strings with pipe chars → escape the pipes as `\|` so the
    markdown table doesn't break.
  - Long strings (> 120 chars) → truncate with an ellipsis and a
    character count: `"... (234 chars total)"`.

Output template:

```markdown
**`<table>`** · `<url>` · schema `<schema>` · filter `<filter or "none">`

| col_a | col_b | col_c |
|---|---|---|
| val | val | val |

`n` rows.
```

If the response is an empty array:

```markdown
**`<table>`** · filter `<filter>` — no rows matched.
```

## Iteration

After rendering, ask:

> "Another filter (give me the string), switch to scaffold mode for a
> local app, or done?"

If the user gives another filter → re-run `curl` with same URL /
schema / JWT / table, new filter. Do not re-elicit those four. Do
**not** cache the JWT in memory as a variable that persists across
turns — re-read it from the tempfile each run, and re-write the
tempfile if the `trap`'s already cleaned it up.

Actually — simpler: keep the tempfile alive across iterations within
the same skill invocation. Only remove it when the user signals
"done" or switches to scaffold mode. Trap on `EXIT INT TERM` is still
the guarantee; iteration just means the skill process doesn't exit
between queries.

If the user says "scaffold" → jump to scaffold-mode step 3b. Reuse
the URL / schema / JWT / table from the already-elicited values.
Don't ask again. Confirm the directory name and proceed.

## One-line sanity check

Before the first query, a cheap liveness ping — hit `${URL}/` (the
root) and check for PostgREST's JSON schema response. If the root
returns 401/404, the URL is wrong or the JWT can't see the schema
root; tell the user before they waste a query. Skip this if it would
take more than ~1s.
