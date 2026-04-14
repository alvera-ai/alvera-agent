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

## Hard prerequisite: a provisioned datalake

**Before anything else**, the target tenant must have at least one
datalake. Every resource this skill creates is scoped to a datalake; with
zero datalakes there is nothing to operate on. Datalake provisioning is
admin-only and out of scope here. If the user isn't sure, the
`datalakes list` step below will tell us — and if it returns empty, stop
and refuse with the verbatim message in that section.

## Auth, briefly

The `alvera` CLI handles credentials. The skill never collects the
password and never shells out to `alvera login` itself — the user runs
that one command in their own terminal so the password never enters
Claude's context or process arg list.

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
- `hasSessionToken: false`, expired, or wrong tenant → tell the user to
  run **in their own terminal**:

  ```bash
  alvera --profile <name> login \
    --base-url <baseUrl> \
    --tenant <tenantSlug> \
    --email <email>
  ```

  The CLI will prompt for the password (hidden input, not echoed). Wait
  for the user to confirm before continuing. Do **not** pass
  `--password` on the command line — it would land in shell history and
  in Claude's view of the command. Do not set `ALVERA_PASSWORD` either.

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

- **Zero datalakes** → refuse:
  > "This tenant has no datalakes provisioned. A datalake must exist
  > before resources can be added — ask your Alvera admin to provision one."
- **One** → use it automatically, tell the user the slug.
- **More than one** → ask which to operate on. Remember for the session.

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
