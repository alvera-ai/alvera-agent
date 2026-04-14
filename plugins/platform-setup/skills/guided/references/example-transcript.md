# Reference transcript

A typical end-to-end conversation, from cold start to first resource.
The skill drives the `alvera` CLI; the user runs `alvera login`
themselves so the password never enters the conversation.

```
USER: I want to set up Acme on Alvera.

AGENT: Before we start, I need:
  1. Profile name — default `default`. Use a named one if you juggle envs.
  2. Tenant slug — which tenant?
  3. Base URL — default https://admin.alvera.ai, override?
  4. Emit infra.yaml receipt? (default yes)

USER: profile=default, tenant=acme, default URL, yes receipt.

AGENT: [runs: alvera --profile default whoami]
       → hasSessionToken: false.

       Please run this in your own terminal (the password prompt will
       be hidden, and I won't see it):

         alvera --profile default login \
           --base-url https://admin.alvera.ai \
           --tenant acme \
           --email <your-email>

       Tell me when you're done.

USER: done.

AGENT: [runs: alvera --profile default whoami]
       → hasSessionToken: true, expiresAt: 2026-04-14T16:35:00Z, tenant: acme.

       [runs: alvera --profile default ping]
       → ok.

       [runs: alvera --profile default datalakes list acme]
       Tenant 'acme' has 1 datalake: 'acme-health'. I'll operate on
       that. What's next? You can set up a:
         - data source
         - tool
         - generic table
         - action status updater
         - AI agent
         - connected app

USER: A data source for our EMR.

AGENT: Got it. I'll need:
       - name (human-readable)
       - uri (e.g. our-emr:acme)
       - description (optional)
       - is this the tenant's primary data source? (default no)

USER: Acme EMR, our-emr:acme, "Acme EMR system", yes primary.

AGENT: [runs: alvera --profile default data-sources list acme-health acme]
       No collisions. Creating data source **Acme EMR** in datalake
       'acme-health':
         - uri: our-emr:acme
         - description: "Acme EMR system"
         - status: active
         - primary data source: yes
       Proceed? (y/n)

USER: y

AGENT: [runs: alvera --profile default data-sources create acme-health acme \
              --body '{"name":"Acme EMR","uri":"our-emr:acme",...}']
       Created data source 'Acme EMR' (id: 7f3a-...).
       Appended to infra.yaml.
       What's next? (data source / tool / generic table / action status
       updater / AI agent / connected app — or "done")

USER: A manual upload tool for it.

AGENT: I'll create a tool attached to 'Acme EMR'. I need:
       - name
       - intent (default: data_exchange)
       - status (default: active)

USER: "Acme Manual Upload", defaults are fine.

AGENT: Creating tool **Acme Manual Upload**:
         - intent: data_exchange
         - status: active
         - attached to data source: Acme EMR
         - kind: manual_upload
       Proceed? (y/n)

USER: y

AGENT: [runs: alvera --profile default tools create acme \
              --body-file /tmp/tool.json]
       Created tool 'Acme Manual Upload' (id: 9b2e-...).
       Appended to infra.yaml.
       What's next? (data source / tool / generic table / action status
       updater / AI agent / connected app — or "done")
```

Notes on style:
- **Always list the options when asking "what's next?"**. After every
  successful create (and at the initial prompt), repeat the inline
  menu — data source / tool / generic table / action status updater /
  AI agent / connected app — plus a "done" escape. Users shouldn't
  have to remember the catalogue.
- **Confirm in plain language, not JSON.** Bullet list the fields
  humans care about (name, uri, linked resources, status) — not
  `datalake_id` UUIDs or other plumbing. JSON is for the file the
  CLI reads, not for the chat.
- Fall back to JSON only when the user explicitly asks ("show me the
  JSON", "show the full body").
- Always report the returned id from the CLI's stdout JSON.
- Always state which file was updated.
- Keep prompts compact — bullet lists, not paragraphs.
- Inline `--body '<json>'` is fine for tiny payloads; switch to
  `--body-file` (writing to a tempfile) when the JSON has nested
  objects, embedded quotes, or values you'd rather keep out of shell
  history.
- Substitute `npx -p @alvera-ai/platform-sdk alvera` for the bare
  `alvera` if the user hasn't installed it globally.
