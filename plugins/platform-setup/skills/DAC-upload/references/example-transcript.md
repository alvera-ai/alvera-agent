# Reference transcript

```
USER: /DAC-upload

AGENT: I need three things to upload:
         1. The **data-activation-client slug** (e.g. acme-emr-dac).
         2. The **file path** to upload (CSV or NDJSON only).
         3. Optional: a **tenant slug** if your profile doesn't default
            to the right one.

USER: dac=acme-emr-dac, file=./patients-2026-04-13.ndjson, tenant=acme

AGENT: [stat ./patients-2026-04-13.ndjson → 48291 lines, 12.4 MiB]
       [extension .ndjson → content-type application/x-ndjson]

       Uploading:
         - file: ./patients-2026-04-13.ndjson (48,291 lines, 12.4 MiB)
         - content type: application/x-ndjson
         - DAC: acme-emr-dac
         - tenant: acme

       Proceed? (y/n)

USER: y

AGENT: [runs: alvera --profile default data-activation-clients upload-link \
              acme-emr-dac patients-2026-04-13.ndjson acme \
              --content-type application/x-ndjson]
       → key: api-ingest/f2c9.../uploads/1a2b3c4d.ndjson
         (url elided — signed, short-lived)

       [runs: curl --fail --show-error --silent -X PUT \
              -H "Content-Type: application/x-ndjson" \
              --upload-file ./patients-2026-04-13.ndjson \
              "<signed url>"]
       → 200 OK

       [runs: alvera --profile default data-activation-clients ingest-file \
              acme-emr-dac api-ingest/f2c9.../uploads/1a2b3c4d.ndjson acme]
       → batch_id: 550e8400-e29b-41d4-a716-446655440000
         jobs_count: 1

       Uploaded and queued.
         - key: api-ingest/f2c9.../uploads/1a2b3c4d.ndjson
         - batch_id: 550e8400-e29b-41d4-a716-446655440000
         - jobs_count: 1

       Processing runs async server-side. To verify rows landed, run
       /query-datasets and query the `patients` table.

       Another file, or done?
```

## Failure example (content-type mismatch)

```
AGENT: [upload-link → ct=application/x-ndjson, url=..., key=...]
       [curl -X PUT -H "Content-Type: text/csv" --upload-file ... <url>]
       → HTTP 403
         <Error><Code>SignatureDoesNotMatch</Code>
         <Message>The request signature we calculated does not match
         the signature you provided.</Message></Error>

       The PUT failed with SignatureDoesNotMatch. The presigned URL was
       signed for content type `application/x-ndjson`, but the curl
       request sent `text/csv`. That's almost always a mismatch between
       the file extension and the header. Let me re-check the file
       extension and retry from step 1 — confirm the file is actually
       `.ndjson` and not a renamed `.csv`?
```

## Notes on style

- **One prompt, three fields.** Don't ask for the slug, then the file,
  then the tenant in separate turns.
- **Elide the signed URL.** Never print the full presigned URL — even
  though it's short-lived, it carries auth.
- **Single file per run.** Batch = loop, not a single multi-file call.
- **Hand off downstream, don't sprawl.** After a successful queue,
  point at `/query-datasets` and stop.
