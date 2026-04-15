# Reference transcript

Two short end-to-end runs — one compliant (path b), one regulated
(path c). Both on an existing datalake `prime-health`.

## Compliant path (user reads-OK)

```
USER: I want to onboard a patients table from ./patients.csv.

AGENT: Quick question before I touch the file: is this sample
       **(a) dummy / synthetic**, **(b) real data you're OK sharing
       with me**, or **(c) real data I must not see** (PHI / PII under
       HIPAA, or covered by a BAA)? (a) or (b) I'll read directly;
       (c) I'll generate a local script and only the column shape
       comes back to me.

USER: (b) — it's anonymised test data from our staging EMR.

AGENT: [reads patients.csv, profiles first 1000 of 1234 rows]

       Proposed table **patients** (domain healthcare, sampled 1000 /
       1234 rows):

         - first_name (string, required, redact_only) — "Patient's first name"
         - last_name  (string, required, redact_only) — "Patient's last name"
         - dob        (date,   required, redact_only) — "Date of birth"
         - mrn        (string, required, unique, tokenize) — "Medical record number"
         - email      (string, optional, redact_only) — "Contact email"

       Notes:
         - `privacy_requirement` is locked at creation — review now,
           changing later means recreating the table.
         - Only `mrn` is unique → single-column key. No composite.
         - Original headers "First Name"/"Last Name" normalised to
           snake_case.

       Proceed? (y/n)  — or "show the full body" for JSON.

USER: y

AGENT: [runs: alvera --profile default generic-tables list prime-health]
       No collision.

       [writes /tmp/gt-1718000000.json, chmod 600]
       [runs: alvera --profile default generic-tables create prime-health \
                     --body-file /tmp/gt-1718000000.json]
       [rm /tmp/gt-1718000000.json]

       Created generic table **patients** (id: 7f3a-...).
       `privacy_requirement` is now locked on all five columns.
       Appended to infra.yaml under `generic_tables`.

       Another dataset, or done?
```

## Regulated path (user says don't read the file)

```
USER: I need to onboard a claims table from ./claims_2024.ndjson.

AGENT: Is this sample **(a) dummy**, **(b) real data you're OK sharing
       with me**, or **(c) real data I must not see** (PHI / PII, BAA)?

USER: (c). Real claims, HIPAA-covered.

AGENT: Got it — I won't read the file. I'll write a standalone Python
       script (stdlib only, no pip install). Run it on your machine,
       paste the JSON output here, and I'll build the schema from that.

       [writes ./alvera-profile.py]

       Run:
         python3 alvera-profile.py ./claims_2024.ndjson

       Paste the JSON output here. I won't see row content — only the
       summary. Delete the script after, or keep it for the next
       dataset.

USER: [pastes]
      {
        "format": "ndjson",
        "row_count": 48291,
        "sampled": 1000,
        "columns": [
          {"original_name":"claim_id","suggested_name":"claim_id",
           "inferred_type":"string","null_rate":0.0,"cardinality":"unique",
           "min_length":12,"max_length":12,"looks_sensitive":false},
          {"original_name":"patient_mrn","suggested_name":"patient_mrn",
           "inferred_type":"string","null_rate":0.0,"cardinality":"high",
           "min_length":8,"max_length":16,"looks_sensitive":false},
          {"original_name":"diagnosis_codes","suggested_name":"diagnosis_codes",
           "inferred_type":"string","null_rate":0.02,"cardinality":"medium",
           "min_length":3,"max_length":240,"looks_sensitive":false}
        ]
      }

AGENT: Proposed table **claims_2024** (domain healthcare, 48291 rows,
       1000 sampled):

         - claim_id        (string, required, unique, tokenize) — "Unique claim identifier"
         - patient_mrn     (string, required,         tokenize) — "Patient MRN (foreign key)"
         - diagnosis_codes (string, optional,        redact_only, array) — "Pipe-separated ICD codes"

       Notes:
         - Only `claim_id` is unique — single-column key.
         - `privacy_requirement` is locked at creation. Review now.
         - `diagnosis_codes` looks array-like (long, pipe-separated) but
           the file has it as a plain string. Keeping as string for now;
           you can parse it on the interop side.

       Proceed? (y/n)

USER: can you change diagnosis_codes privacy to tokenize?

AGENT: Sure — `diagnosis_codes` → privacy_requirement: tokenize.
       Updated:

         - diagnosis_codes (string, optional, tokenize) — "Pipe-separated ICD codes"

       Proceed now? (y/n)

USER: y

AGENT: [list — no collision]
       [writes /tmp/gt-..., chmod 600]
       [runs: alvera --profile default generic-tables create prime-health \
                     --body-file /tmp/gt-...json]
       [rm]

       Created generic table **claims_2024** (id: 9b2e-...).
       Appended to infra.yaml.
       Another dataset, or done?
```

## Notes on style

- **One compliance question, three choices.** Don't split. Don't infer.
- **Plain-language recap only.** JSON on explicit request.
- **Always flag the locked-at-creation rule** before asking "Proceed?".
- **Always state composite semantics** when more than one column has
  `is_unique: true`.
- **No cross-selling.** This skill creates one dataset per invocation —
  don't append a "what's next? (data source / tool / ...)" menu. That
  belongs to `guided`. Ask only "another dataset, or done?".
