# Reference transcript

A typical end-to-end conversation, from cold start to first resource.

```
USER: I want to set up Acme on Alvera.

AGENT: Before we start, I need:
  1. Tenant slug — what's the slug?
  2. API key — paste it here, I won't store it.
  3. Base URL — default https://admin.alvera.ai, override?
  4. Emit infra.yaml receipt? (default yes)

USER: slug=acme, key=sk_live_xxx, default URL, yes receipt.

AGENT: [calls api.ping(), then api.datalakes.list('acme')]
       Connected. Tenant 'acme' has 1 datalake: 'acme-health'. I'll
       operate on that. What do you want to set up?

USER: A data source for our EMR.

AGENT: Got it. I'll need:
       - name (human-readable)
       - uri (e.g. our-emr:acme)
       - description (optional)
       - is this the tenant's primary data source? (default no)

USER: Acme EMR, our-emr:acme, "Acme EMR system", yes primary.

AGENT: [calls api.dataSources.list('acme', 'acme-health')]
       No collisions. I'll create:
         {
           name: "Acme EMR",
           uri: "our-emr:acme",
           description: "Acme EMR system",
           status: "active",
           is_default: true
         }
       in datalake 'acme-health'. Confirm? (y/n)

USER: y

AGENT: [calls api.dataSources.create('acme', 'acme-health', {...})]
       Created data source 'Acme EMR' (id: 7f3a-...).
       Appended to infra.yaml.
       What's next?

USER: A manual upload tool for it.

AGENT: I'll create a tool attached to 'Acme EMR'. I need:
       - name
       - intent (default: data_exchange)
       - status (default: active)

USER: "Acme Manual Upload", defaults are fine.

AGENT: I'll create:
         {
           name: "Acme Manual Upload",
           intent: "data_exchange",
           status: "active",
           datalake_id: "<acme-health id>",
           data_source_id: "7f3a-...",
           body: { __type__: "manual_upload" }
         }
       Confirm? (y/n)

USER: y

AGENT: [calls api.tools.create(...)]
       Created tool 'Acme Manual Upload' (id: 9b2e-...).
       Appended to infra.yaml.
       What's next?
```

Notes on style:
- Always echo the exact body before calling create.
- Always report the returned id.
- Always state which file was updated.
- Keep prompts compact — bullet lists, not paragraphs.
