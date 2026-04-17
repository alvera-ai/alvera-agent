# Reference transcripts

## Full automated flow — new DAC + contract from scratch

```
USER: /DAC-upload ./emr-patients-export.csv

AGENT: [runs: alvera --profile default datalakes list]
       → [{"slug":"prime-medical-datalake"}]

       One datalake: `prime-medical-datalake`.

       [runs: alvera --profile default data-activation-clients list
              prime-medical-datalake]
       → []   (no DACs exist)

       No DACs on this datalake. I'll create one for you.

       [runs: alvera --profile default tools list]
       → [{"id":"7f3a-...","name":"Acme Manual Upload","intent":"data_exchange"}]

       [runs: alvera --profile default data-sources list prime-medical-datalake]
       → [{"id":"9b2e-...","name":"Acme EMR","uri":"our-emr:acme"}]

       Auto-detected:
         - tool: Acme Manual Upload (data_exchange)
         - data source: Acme EMR (our-emr:acme)

       [reads headers: head -n 1 ./emr-patients-export.csv]
       → patient_id,first_name,last_name,dob,gender,phone,email,active,source_uri

       [writes /tmp/alvera-scan.py, runs: python3 /tmp/alvera-scan.py
        ./emr-patients-export.csv]
       → {
           "row_count": 1247,
           "scanned": 100,
           "columns": {
             "dob": {"detected_format":"MM/DD/YY","needs_fix":true},
             "gender": {"unique_values":["Female","Male","Other"],"needs_downcase":true},
             "active": {"unique_values":["true","false"]}
           }
         }

       Anti-pattern scan (first 100 of 1,247 rows):
         - `dob`: dates in MM/DD/YY format → will convert to YYYY-MM-DD
         - `gender`: capitalised values → will `| downcase`
         - `active`: has "false" values → will add a filter to skip
           inactive patients

       What resource type does this file map to? (patient, appointment,
       or other?)

USER: patient

AGENT: [runs: alvera --profile default interop create prime-medical-datalake
              --body '{"name":"Patient Identity","resource_type":"patient",
              "template_config":{"type":"identity"},
              "mdm_input_config":{"type":"identity"}}']
       → slug: patient-identity

       [runs: alvera --profile default interop metadata
              prime-medical-datalake patient-identity]
       → (markdown describing patient FHIR fields)

       Proposed column mapping:

         Source column   → FHIR field        Transform
         ─────────────────────────────────────────────────
         patient_id      → identifier[0]     system: urn:our-emr:acme
         first_name      → name[0].given[0]  —
         last_name       → name[0].family    —
         dob             → birth_date        MM/DD/YY → YYYY-MM-DD
         gender          → gender            | downcase
         phone           → telecom[0]        system: phone
         email           → telecom[1]        system: email
         source_uri      → source_uri        —

       Filter: skip rows where `active == "false"`
       MDM: resolve by patient_id (system: urn:our-emr:acme)

       Proceed with this mapping? (y/n)

USER: y

AGENT: [writes template to /tmp/interop-contract.json]
       [runs: alvera --profile default interop update
              prime-medical-datalake patient-identity
              --body-file /tmp/interop-contract.json]
       → updated (slug: patient-identity, type: custom)
       [rm /tmp/interop-contract.json]

       Contract created. Running sandbox test...

       [runs: head -n 2 ./emr-patients-export.csv | python3 -c "
        import csv,json,sys; r=csv.DictReader(sys.stdin);
        print(json.dumps(next(r)))" |
        alvera --profile default interop run
        prime-medical-datalake patient-identity --body-file -]
       → {
           "stage": "completed",
           "filter_result": "pass",
           "transformed": {
             "active": true,
             "identifier": [{"system":"urn:our-emr:acme","value":"P-001"}],
             "name": [{"use":"official","family":"Smith","given":["John"]}],
             "gender": "male",
             "birth_date": "1985-03-15",
             "telecom": [
               {"system":"phone","value":"+1-555-0123","use":"home"},
               {"system":"email","value":"john@example.com","use":"home"}
             ],
             "source_uri": "emr.acme.com"
           },
           "mdm_input": {
             "identifiers": [{"system":"urn:our-emr:acme","value":"P-001"}],
             "family_name": "Smith",
             "given_name": "John"
           }
         }

       Sandbox test passed:
         - birth_date correctly converted: `1985-03-15` (was MM/DD/YY)
         - gender correctly downcased: `male`
         - MDM identifiers present

       Now creating the DAC...

       [runs: alvera --profile default data-activation-clients create
              prime-medical-datalake
              --body '{"name":"EMR Patient Ingest",
              "description":"Accepts EMR patient CSV, transforms via FHIR contract",
              "tool_id":"7f3a-...","data_source_id":"9b2e-...",
              "tool_call":{"tool_call_type":"manual_upload"},
              "interoperability_contract_ids":["<patient-identity-id>"]}']
       → slug: emr-patient-ingest

       Uploading:
         - file: `./emr-patients-export.csv` (1,247 rows, 0.4 MiB)
         - content type: `text/csv`
         - datalake: `prime-medical-datalake`
         - DAC: `emr-patient-ingest` (manual_upload)
         - contract: `patient-identity` (patient, custom template)
         - anti-patterns fixed: dob (MM/DD/YY → YYYY-MM-DD),
           gender (downcase), inactive rows (filtered)
         - sandbox test: passed

       Proceed? (y/n)

USER: y

AGENT: [runs: alvera --profile default datalakes upload-link
              prime-medical-datalake emr-patients-export.csv
              --content-type text/csv]
       → key: api-ingest/f2c9.../uploads/a1b2c3d4.csv

       [runs: curl --fail --show-error --silent -X PUT
              -H "Content-Type: text/csv"
              --upload-file ./emr-patients-export.csv "<signed url>"]
       → 200 OK

       [runs: alvera --profile default data-activation-clients
              ingest-file prime-medical-datalake emr-patient-ingest
              api-ingest/f2c9.../uploads/a1b2c3d4.csv]
       → batch_id: 550e8400-e29b-41d4-a716-446655440000
         jobs_count: 1

       Uploaded and queued.
         - key: api-ingest/f2c9.../uploads/a1b2c3d4.csv
         - batch_id: 550e8400-...
         - jobs_count: 1

       Processing runs async. To verify rows landed, run
       `/query-datasets` and query the `patients` table.

       Another file, or done?
```

## Existing DAC — anti-pattern warning on template

```
USER: /DAC-upload ./appointments.csv emr-patient-ingest

AGENT: [runs: alvera --profile default datalakes list]
       → [{"slug":"prime-medical-datalake"}]

       [runs: alvera --profile default data-activation-clients list
              prime-medical-datalake]
       → [{"slug":"emr-patient-ingest",
           "interoperability_contract_ids":["<id>"]}]

       DAC found: `emr-patient-ingest`.

       [reads headers: head -n 1 ./appointments.csv]
       → appt_id,appt_status,appt_date,appt_time,duration,
         visit_type,patient_mrn,patient_first_name,
         patient_last_name,source_uri

       [runs scanner]
       → {
           "columns": {
             "appt_date": {"detected_format":"MM/DD/YYYY","needs_fix":true},
             "appt_status": {"unique_values":["Scheduled","Completed",
               "Cancelled","No-Show"],"needs_mapping":true}
           }
         }

       [runs: alvera --profile default interop get
              prime-medical-datalake <contract-slug>]
       → resource_type: patient, template_config uses {{ msg.patient_id }}

       Two issues:

       1. **Wrong contract.** The DAC's contract is for `patient`
          resources, but this file has appointment columns
          (`appt_id`, `appt_status`, `appt_date`). You need an
          `appointment` contract.

       2. **Anti-patterns detected:**
          - `appt_date`: MM/DD/YYYY format → needs YYYY-MM-DD
          - `appt_status`: Scheduled/Completed/Cancelled/No-Show →
            needs FHIR mapping (booked/fulfilled/cancelled/noshow)

       Want me to create an appointment contract with the correct
       mapping and update the DAC? (y/n)

USER: yes, create a new DAC for appointments

AGENT: [creates appointment interop contract with template fixes]
       [sandbox tests]
       [creates new DAC: appointment-ingest]
       [proceeds with upload]
       ...
```

## Notes on style

- **Hands-off by default.** Auto-detect everything possible before
  asking. The user should only need to confirm y/n at key decision
  points.
- **Show the mapping table, not raw Liquid.** The template is an
  implementation detail — the user cares about "does `dob` become
  `birth_date` in YYYY-MM-DD format?"
- **Surface anti-pattern findings as a compact list.** Don't dump the
  full scanner JSON — summarise what was found and what will be fixed.
- **Sandbox test is non-negotiable** for new or modified contracts.
  Show the transformed output so the user can verify fields.
- **One prompt, one confirmation.** Don't ask for inputs one at a time.
  Batch what you've resolved and what you still need into a single
  message.
- **Elide the signed URL.** Never print the full presigned URL.
- **Single file per run.** Batch = loop.
- **Hand off downstream.** After a successful queue, point at
  `/query-datasets` and stop.
