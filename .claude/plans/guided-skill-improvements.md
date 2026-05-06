# Guided Skill Improvements — Post-Sandbox Findings

Based on test session `43ac24e1-2f23-42cb-a02f-4ec49f3f4b40`.

## Problem: Bootstrap is too noisy for returning users

The agent took 6 Bash calls to resolve CLI auth and still ended up asking
questions it could answer itself. A returning user with a valid session should
reach gap analysis with **zero** prompts.

## Improvements

### 1. Simplify auth detection (HIGH)

**Current:** `alvera --version` → fail → install tsx → retry → `whoami` → read config → symlink.

**Fix:** Single call: `alvera whoami 2>&1`. Three outcomes:
- Success → use it, move on
- "not authenticated" / expired → tell user: "Run `alvera login` and let me know when done"
- Command not found → tell user: "Install: `npm i -g @alvera-ai/platform-sdk`"

No HOME introspection, no symlinks, no config file reading, no `--version` checks.
The skill should never `cat ~/.alvera-ai/config` or inspect credential files.

### 2. Don't dump all tasks upfront (MEDIUM)

**Current:** 10 TaskCreate calls before doing anything.

**Fix:** Create tasks lazily — one at a time as you reach each step. The plan
is already communicated in the gap analysis bullet list; duplicating it as
tasks is premature and clutters the conversation.

### 3. Compliance gate should be inline (LOW)

**Current:** Separate task + separate prompt: "Is your CSV (a) synthetic, (b)
shareable real, or (c) PHI?"

**Fix:** Fold into the first interaction. When user provides a file path,
ask ONE compound question:
> "Got it — I'll use `Test Data - NJ_Appointments_Jul2025_Jun2026.csv`.
> Is this synthetic/test data? (y = proceed, n = I'll treat it as PHI
> and won't echo values)"

Don't create a separate task for it.

### 4. Don't investigate HOME directory (HIGH)

**Current:** Agent reads `~/.alvera-ai/config`, `~/.alvera-ai/credentials`,
checks `$HOME`, does `env | grep alvera`.

**Fix:** Never inspect auth files. `alvera whoami` is the single source of
truth. If it works, proceed. If not, tell user to authenticate. The skill
never needs to know WHERE the config lives.

### 5. Datalake detection before asking (MEDIUM)

**Current:** Runs `datalakes list`, gets 0, then asks "what do you want?"

**Fix:** If 0 datalakes and user said "default should be setup":
- Check if user has `.alvera.datalake.env` via `alvera init infra-setup --check` (if available)
- Otherwise, offer to create one immediately with sensible defaults
- Don't just report "none found" and wait — be proactive about the obvious next step

### 6. Single-response gap analysis (LOW)

**Current:** Bootstrap report → pause → gap analysis → pause → ask to proceed.

**Fix:** Combine into one message:
> "Session: profile `default`, tenant `prime` ✓
> Datalake: none — I'll create one.
> After that: tool → data source → 2 contracts → DAC → upload.
> Proceed? (y/n)"

One message. One confirmation. Then go.

## Implementation Checklist

- [x] Update SKILL.md Step 2 (Bootstrap) — reduced to `--version` + `whoami` + `datalakes list`
- [x] Add explicit instruction: "Never read ~/.alvera-ai/ files directly"
- [x] Add instruction: "Create tasks lazily, not upfront"
- [ ] Merge compliance gate into first user interaction (data-pipeline.md change)
- [x] Combine bootstrap report + gap analysis into single message
- [x] Add "if not authenticated" → single instruction, don't investigate why
- [x] Datalake creation uses `alvera init infra-setup` in cwd, not manual JSON
- [x] Filesystem boundaries: whitelist approach (skill dir, cwd, /tmp, user-provided paths)
- [x] Template source is skill's own `templates/` dir or built from profiling
- [x] Add create-body JSON examples to `resources.md` for all 9 resource types
      (datalake, data source, tool×2, generic table, action status updater,
       AI agent, connected app, interop contract, DAC)
