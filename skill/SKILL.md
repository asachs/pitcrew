# Pitcrew — Parallel AI Coding, F1 Style

Crew chief decomposes features into pit calls, dispatches mechanics (MiniMax M2.5 via direct API or Aider) to bays (git worktrees), releases back to track (merges to main), radios for help on conflicts. Two mechanic modes: `mechanic-lite.sh` (3-6s, curl only) and `mechanic.sh` (30s, via Aider). Use `pitstop.sh` for full pit stop with live output.

## When to Use

USE WHEN: "pitcrew", "pit stop", "run mechanics", "parallel build", "swarm", "fan out", "dispatch workers", or when a task spans multiple platforms/files that can be worked on independently.

DO NOT USE for single-file changes or tasks that require sequential reasoning.

## Architecture

```
Crew Chief (Opus) ── decomposes into pit calls (Beads)
    │
    ├── Mechanic (MiniMax M2.5) ── Bay A ── pit call 1
    ├── Mechanic (MiniMax M2.5) ── Bay B ── pit call 2
    ├── Mechanic (MiniMax M2.5) ── Bay C ── pit call 3
    └── ...

    Release ── merge bays to main, radio on conflicts
```

## Prerequisites

- `~/go/bin/bd` — Beads CLI
- `aider` — Coding agent
- `~/beads/` or `~/pitlane/` — Beads repo
- `MINIMAX_API_KEY` env var

## Workflows

### 1. Strategy (Decompose)

Break a feature into independent pit calls:

1. Analyse the feature, identify independent work units
2. For each, create a Bead:
   - Clear title (what to do)
   - Body with detailed spec, acceptance criteria, relevant files
   - Labels: `file:path/to/file` for each relevant file
3. Mark dependencies between calls

**Rules:**
- Each call should be completable with ≤200K context
- Each call should touch at most 3-5 files
- Maximise parallelism — minimise dependencies

### 2. Box Box (Dispatch)

Send mechanics to their bays:

```bash
# Single mechanic (lite — direct API, 3-6s)
~/.claude/skills/Pitcrew/Tools/mechanic-lite.sh <bead-id> <repo-path>

# Single mechanic (via Aider — 30s, more capable)
~/.claude/skills/Pitcrew/Tools/mechanic.sh <bead-id> <repo-path>

# Full pit stop with live output (uses mechanic-lite)
~/.claude/skills/Pitcrew/Tools/pitstop.sh <repo-path> <bead-id> [<bead-id> ...]

# Or manual parallel dispatch
for CALL in $(bd list --status open --format ids); do
  ~/.claude/skills/Pitcrew/Tools/mechanic-lite.sh "$CALL" /path/to/repo &
done
wait
```

### 3. Timing Screen (Monitor)

```bash
~/.claude/skills/Pitcrew/Tools/timing.sh
```

Shows: call status, active bays, token usage, costs.

### 4. Release (Merge)

```bash
~/.claude/skills/Pitcrew/Tools/release.sh <bead-id> <repo-path>
```

**Radio protocol (conflict escalation):**
- **Green flag** — clean merge, auto-release
- **Yellow flag** — text conflict, try rebase
- **Red flag** — semantic conflict, radio crew chief (Opus resolves)
- **Black flag** — architectural clash, human decides

### 5. Scrutineering (Verify)

After all bays released:
1. Run type checker / compiler
2. Run tests
3. Review combined diff
4. Report summary

## Tools

| Tool | Role | Purpose |
|------|------|---------|
| `Tools/mechanic-lite.sh` | Mechanic (fast) | Direct API call, 3-6s, curl only |
| `Tools/mechanic.sh` | Mechanic (full) | Via Aider, 30s, multi-file capable |
| `Tools/pitstop.sh` | Full pit stop | Dispatch + monitor + release with live output |
| `Tools/release.sh` | Release | Merge worktree with conflict escalation |
| `Tools/timing.sh` | Timing screen | Status dashboard |

## Beads CLI Quick Reference

```bash
bd create --title "..." --body "..." --label "file:src/foo.ts"
bd list --status open
bd show <bead-id> --format json
bd update <bead-id> --status closed --comment "..."
```

## Environment Variables

| Var | Required | Default |
|-----|----------|---------|
| `MINIMAX_API_KEY` | Yes (for API mechanics) | — |
| `OPENROUTER_API_KEY` | Alternative | — |
| `OPENAI_API_BASE` | No | `https://api.minimax.io/v1` |

## Cost per Pit Stop

| Mechanics | Model | Est. Cost |
|-----------|-------|-----------|
| 3-5 calls | MiniMax M2.5 | ~$0.01-0.05 |
| 5-10 calls | MiniMax M2.5 | ~$0.05-0.15 |
| 10-20 calls | MiniMax M2.5 | ~$0.15-0.50 |
| Conflict resolution | Opus (Max sub) | $0 (flat rate) |
