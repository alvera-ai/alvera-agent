# Bootstrap (once per session)

## Step 0: is `alvera` reachable?

Before asking the user anything, make sure the CLI actually runs. Every
subsequent step (`whoami`, `ping`, `datalakes list`, resource CRUD) goes
through `alvera`, so if it's unreachable nothing works.

Try the two invocation forms in order and pin whichever one succeeds as
the prefix for the rest of the session:

```bash
# 1. already installed globally?
alvera --version

# 2. otherwise, run it via npx (first call downloads, later calls cache)
npx -p @alvera-ai/platform-sdk alvera --version
```

- Either works → pin that prefix and move on. Don't mix the two
  mid-conversation; it confuses the transcript.
- Both fail → tell the user to install it:

  ```bash
  npm install -g @alvera-ai/platform-sdk
  # or, if they use pnpm:
  pnpm add -g @alvera-ai/platform-sdk
  ```

  Wait for them to confirm install succeeded, then re-run
  `alvera --version`. Do **not** run the install yourself — host
  toolchain mutation is out of scope.

If `npm` / `pnpm` itself is missing, that's a Node install problem one
level lower — point the user at nvm / rtx / asdf / homebrew / nodejs.org
in a single sentence and stop there. Don't try to diagnose shims.

## Datalake presence

Most resources (data sources, tools, AI agents, connected apps,
generic tables) are datalake-scoped, so we need one before we can
provision anything else. The `datalakes list` step below finds out
whether the tenant has one.

- **Tenant has at least one datalake** → pick one and continue.
- **Zero datalakes** → offer to create one now. Datalake creation takes
  DB credentials (four role pairs × host/port/auth/ssl/schema); handle
  them with care. Full elicitation + secret-handling procedure in
  `references/resources.md` → "Datalake". Do **not** refuse outright;
  that used to be the policy, it isn't anymore.

## Auth

The `alvera` CLI handles credentials. The skill never collects the
password and never shells out to `alvera login` itself.

Two paths depending on the environment:

### Interactive terminal (default)

The user runs `alvera login` in their own shell — the CLI prompts for
the password (hidden input). This is the normal path for local dev.

### VM / Claude Cowork / headless (no interactive TTY)

If the user is in a VM, Claude Cowork session, or any environment
where `alvera login`'s interactive password prompt won't work, direct
them to mint a short-lived API token via the web UI:

> "Visit **`<baseUrl>/app/users/api-tokens`** in a browser, mint a
> short-lived token, then set it in your shell:
>
>   export ALVERA_SESSION_TOKEN=<token>
>
> After that, `alvera whoami` should show your session."

How to detect: check if `alvera login` fails with a TTY error, or if
the user mentions they're in a VM / cowork / container. Don't assume —
try `whoami` first and only suggest this path if no valid session
exists and the user indicates they can't run `login` interactively.

## First-turn questions

Ask in a single prompt:

1. **Profile name** — default `default`. Use a named profile if the user
   juggles multiple environments (e.g. `staging`, `acme-prod`).
2. **Tenant slug** — which tenant to operate on. (May already be the
   profile default; confirm anyway.)
3. **Base URL** — default `https://admin.alvera.ai`. Override only for
   staging/dev.
4. **Emit `infra.yaml` receipt?** — default yes. Human-readable record of
   what got created.

Then check whether the user is already logged in:

```bash
alvera --profile <name> whoami
```

- `hasSessionToken: true` and `expiresAt` in the future → proceed to
  connectivity check.
- `hasSessionToken: false`, expired, or wrong tenant → offer both auth
  paths:

  > "No active session. Two ways to authenticate:
  >
  > **Interactive** (local terminal):
  >
  >     alvera --profile <name> login \
  >       --base-url <baseUrl> \
  >       --tenant <tenantSlug> \
  >       --email <email>
  >
  > **VM / Cowork / headless** (no password prompt):
  >
  >     Visit <baseUrl>/app/users/api-tokens, mint a short-lived
  >     token, then: export ALVERA_SESSION_TOKEN=<token>
  >
  > Tell me when you're done."

  Do **not** pass `--password` on the command line — it would land in
  shell history. Do not set `ALVERA_PASSWORD` either.

## Connectivity check

```bash
alvera --profile <name> ping
```

Non-zero exit → stop. Surface the stderr verbatim. Do not retry.

## Datalake selection

Most resources are scoped to a datalake. List them:

```bash
alvera --profile <name> datalakes list <tenantSlug>
```

(`<tenantSlug>` is optional if the profile has one configured.)

- **Zero datalakes** → offer to create one. Walk the user through the
  "Datalake" section of `resources.md`. Once created, pin its slug for
  the session and continue.
- **One or more** → list them, then ask:

  > "Found N datalake(s):
  >   1. `prime-health` — healthcare, America/New_York
  >   (2. ...)
  >
  > Use one of these, or create a new one?"

  Even with a single datalake, don't auto-pick — the user may want
  to create a fresh one for a new domain or environment. Be proactive
  (assume "use existing" is likely), but let the user override.

## State to retain for the session

- `profile` (default `default`)
- `tenantSlug`
- `datalakeSlug`, `datalakeId`
- `baseUrl` (only if non-default)
- whether the YAML receipt is enabled
- the path to the receipt file (default `./infra.yaml`)

The skill holds no credentials in memory. The session token lives in
`~/.alvera-ai/credentials` (mode 0600) and is read by every CLI
invocation.

## Cleanup (optional but recommended)

When the user signals they're done, suggest they run:

```bash
alvera --profile <name> logout
```

This calls the revoke endpoint and clears the local credentials entry
for that profile. Don't run it for them unless they ask — they may want
to keep the session for follow-up work.
