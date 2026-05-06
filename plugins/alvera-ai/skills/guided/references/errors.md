# Error catalog

Common CLI errors, their causes, and recovery steps.

## HTTP errors

| Code | Common cause | Recovery |
|------|-------------|----------|
| `400` | Malformed request body (bad JSON, wrong types) | Surface error message. Fix the body and re-run. |
| `401` | Session expired or missing | Ask user to re-run `alvera login` for this profile. |
| `403` | Insufficient permissions for this tenant/resource | Verify tenant slug, check user role with admin. |
| `404` | Resource not found (wrong ID/slug, wrong datalake) | Verify ID/slug with `list`. Check datalake scope. |
| `409` | Name collision (resource already exists) | Run `list` to show existing. Ask: update, rename, or skip. |
| `422` | Validation failure (invalid Liquid, missing required field, enum mismatch) | Surface the `errors` array verbatim. Re-elicit the rejected field. Note valid values from the error for this session. |
| `429` | Rate limit exceeded | Wait 30 seconds, then retry once with user confirmation. |
| `500` | Server error | Try `alvera raw GET <path>` to verify API health. Retry once if user agrees. If persistent, stop and suggest contacting support. |
| `502/503` | API temporarily unavailable | Wait 60 seconds, retry once. If still failing, suggest trying later. |
| `504` | Gateway timeout (large payload or slow operation) | Retry once. For large uploads, verify file size is reasonable. |

## CLI-specific errors

| Error | Cause | Recovery |
|-------|-------|----------|
| `alvera: command not found` | CLI not installed | `npm install -g @alvera-ai/platform-sdk` or use `npx` prefix. |
| `alvera: profile "X" not found` | Missing or misconfigured profile | Run `alvera configure` to set up the profile. |
| `alvera: no session token` | Never logged in for this profile | Ask user to run `alvera login`. |
| `alvera: session expired` | Token TTL exceeded | Ask user to re-run `alvera login`. |
| `ECONNREFUSED` / `ETIMEDOUT` | Network issue or wrong base URL | Check `--profile` base URL. Verify network. Try `alvera ping`. |
| `SyntaxError: Unexpected token` | Invalid JSON in `--body` | Switch to `--body-file` with a tempfile. Check for unescaped quotes. |

## Liquid template errors (422 on workflow/interop create)

| Symptom | Cause | Fix |
|---------|-------|-----|
| `Unknown tag` | Typo in Liquid tag name | Check `{% %}` tags against Liquid reference. |
| `Liquid syntax error` | Unclosed tags, missing `end*` | Match every `{% if %}` with `{% endif %}`, every `{% for %}` with `{% endfor %}`. |
| `undefined variable` | Variable not available at this stage | Check variable availability table in `workflows.md`. Filter stage has fewer variables than action stage. |
| Template outputs nothing | Logic never reaches `true` | Trace each condition. Common: wrong `source_uri`, stale date cutoff, missing MDM data. |

## Partial chain failures

When a multi-resource chain fails midway (e.g., tool created, workflow creation fails):

1. **Don't clean up automatically.** The successfully created resources are valid.
2. **Surface what succeeded and what failed.** Show the exact error.
3. **Fix the failing resource.** Re-elicit the rejected fields.
4. **Retry from the failed step** — not from the beginning.
5. **If the user wants to abandon,** ask whether to delete the orphaned resources or leave them for later.
