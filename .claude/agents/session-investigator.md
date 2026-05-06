---
name: session-investigator
description: >
  Investigate Claude Code session history — find conversation logs, tool calls,
  task state, and plugin activity from any .claude directory (real or sandbox).
  Use when debugging skill behavior, auditing agent decisions, or extracting
  what happened in a past session.
---

# Session Investigator Agent

Analyzes Claude Code session artifacts from a `.claude` directory.

**3-call workflow:** copy script to /tmp → run it → read the report.

## Usage

Given a `.claude` directory path (real or sandbox), run the analyzer:

```bash
# 1. Copy script (already bundled at scripts/analyze-session.py)
cp .claude/agents/scripts/analyze-session.py /tmp/analyze-session.py

# 2. Run it against a .claude directory
python3 /tmp/analyze-session.py /tmp/alvera.9ZMTps/home/.claude

# 3. Read the report (written to /tmp/session-report.md)
# The script also prints a summary to stdout
```

For a specific session:
```bash
python3 /tmp/analyze-session.py ~/.claude --session-id 43ac24e1-2f23-42cb-a02f-4ec49f3f4b40
```

## What the script reports

- **Session metadata**: pid, version, duration, working directory
- **Timeline**: chronological list of every user message, assistant message, and tool call
- **Metrics**: total Bash/Read/Write/Edit calls, token counts, question counts
- **Boundary violations**: reads outside project dir, HOME introspection, credential access
- **Task state**: all tasks with status
- **Inefficiency flags**: redundant CLI calls, excessive reads of same file, filesystem hunting

## Directory Anatomy (reference)

```
~/.claude/
├── .claude.json                    # App config, feature flags
├── .credentials.json               # Auth credentials (DO NOT echo)
├── history.jsonl                   # User inputs across all sessions
├── settings.json                   # Global settings, enabled plugins
├── sessions/<pid>.json             # Session metadata
├── projects/<path-slug>/
│   ├── <sessionId>.jsonl           # Full conversation log
│   ├── memory/MEMORY.md            # Memory index + *.md files
│   └── CLAUDE.md                   # Project instructions
├── tasks/<sessionId>/<n>.json      # Task state per session
├── plans/                          # Saved plans
├── plugins/cache/                  # Cached plugin files
├── backups/                        # Config backups (timestamped)
├── shell-snapshots/                # Shell state snapshots
└── session-env/                    # Session env vars
```

Project path slug: absolute path with `/` replaced by `-`.
Sandboxes use same structure under `<sandbox>/home/.claude/`.

## When to use

- After a skill test: "what did the agent actually do?"
- Debugging: "why did it ask so many questions?"
- Security audit: "did it read credentials or external repos?"
- Efficiency review: "how many tool calls were wasted?"
