# Pitcrew — Parallel AI Coding, F1 Style

Crew chief decomposes features into pit calls, dispatches mechanics (MiniMax M2.5 via direct API or Aider) to bays (git worktrees), releases back to track (merges to main), radios for help on conflicts. Two mechanic modes: `mechanic-lite.sh` (3-6s, curl only) and `mechanic.sh` (30s, via Aider). Use `pitstop.sh` for full pit stop with live output. Use `pitstop-auto.sh` for one-command task decomposition and dispatch.

## Quick Start

```bash
# One command — decompose a task and run mechanics in parallel
~/.claude/skills/Pitcrew/Tools/pitstop-auto.sh /path/to/any/repo "add feature X"

# Or manually create beads and dispatch
~/.claude/skills/Pitcrew/Tools/pitstop.sh /path/to/repo bead-id-1 bead-id-2
```

No per-repo setup needed. Works on any git repository out of the box.

## When to Use

USE WHEN: "pitcrew", "pit stop", "run mechanics", "parallel build", "swarm", "fan out", "dispatch workers", or when a task spans multiple platforms/files that can be worked on independently.

DO NOT USE for single-file changes or tasks that require sequential reasoning.

Works on **any git repo** without per-repo configuration. Context is auto-detected from `.pitcrew`, `CLAUDE.md`, or repo structure (language detection). Beads DB is auto-initialized on first use.

## Architecture

```
Crew Chief (Opus or Sonnet) ── decomposes into pit calls (Beads)
    |
    +-- Mechanic (MiniMax M2.5) -- Bay A -- pit call 1
    +-- Mechanic (MiniMax M2.5) -- Bay B -- pit call 2
    +-- Mechanic (MiniMax M2.5) -- Bay C -- pit call 3
    +-- ...

    Release -- merge bays to main, radio on conflicts
```

## Global Operation

Pitcrew works on any repo without manual setup:

- **Auto-init**: Beads DB is initialized automatically if not present (pitstop.sh, pitstop-auto.sh)
- **Auto-context**: Mechanics pick up context in priority order: `.pitcrew` > `CLAUDE.md` (first 200 lines) > auto-detected language hint (Nix, JS/TS, Rust, Go, Clojure, Python)
- **Global lessons**: Lessons in `~/.claude/pitcrew-lessons` are injected into every mechanic prompt across all repos, alongside any repo-local `.pitcrew-lessons`
- **Consistent paths**: All scripts use `PITCREW_LANE` (beads dir), `PITCREW_BAYS` (worktrees dir), `PITCREW_BD` (bd binary) with sensible defaults

## Prerequisites

- `~/go/bin/bd` — Beads CLI (or set `PITCREW_BD`)
- `aider` — Coding agent (only for mechanic.sh, not needed for mechanic-lite.sh)
- `MINIMAX_API_KEY` env var (for mechanics)
- `ANTHROPIC_API_KEY` env var (for pitstop-auto.sh crew chief decomposition)

## Workflows

### 1. Auto Pit Stop (Recommended)

One command: describe the task, Pitcrew decomposes and dispatches.

```bash
~/.claude/skills/Pitcrew/Tools/pitstop-auto.sh /path/to/repo "add dark mode toggle to settings page"
```

The crew chief (Sonnet) analyzes the repo, decomposes the task into parallel beads, creates them, and dispatches mechanics via pitstop.sh.

### 2. Strategy (Manual Decompose)

Break a feature into independent pit calls manually:

1. Analyse the feature, identify independent work units
2. For each, create a Bead:
   - Clear title (what to do)
   - Body with detailed spec, acceptance criteria, relevant files
   - Labels: `file:path/to/file` for each relevant file
3. Mark dependencies between calls

**Rules:**
- Each call should be completable with <=200K context
- Each call should touch at most 3-5 files
- Maximise parallelism — minimise dependencies

### 3. Box Box (Dispatch)

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

### 4. Timing Screen (Monitor)

```bash
~/.claude/skills/Pitcrew/Tools/timing.sh
```

Shows: call status, active bays, token usage, costs.

### 5. Release (Merge)

```bash
~/.claude/skills/Pitcrew/Tools/release.sh <bead-id> <repo-path>
```

**Radio protocol (conflict escalation):**
- **Green flag** — clean merge, auto-release
- **Yellow flag** — text conflict, try rebase
- **Red flag** — semantic conflict, radio crew chief (Opus resolves)
- **Black flag** — architectural clash, human decides

### 6. Scrutineering (Verify)

After all bays released:
1. Run type checker / compiler
2. Run tests
3. Review combined diff
4. Report summary

### 7. Lessons

```bash
# Add a repo-local lesson
~/.claude/skills/Pitcrew/Tools/lesson.sh /path/to/repo "Model renamed hyphens to underscores -> Add naming constraint to context"

# Add a global lesson (applies to ALL repos)
~/.claude/skills/Pitcrew/Tools/lesson.sh --global "Always preserve existing import style"
```

## Tools

| Tool | Role | Purpose |
|------|------|---------|
| `Tools/pitstop-auto.sh` | Auto pit stop | Decompose task + dispatch + monitor + release |
| `Tools/mechanic-lite.sh` | Mechanic (fast) | Direct API call, 3-6s, curl only |
| `Tools/mechanic.sh` | Mechanic (full) | Via Aider, 30s, multi-file capable |
| `Tools/pitstop.sh` | Full pit stop | Dispatch + monitor + release with live output |
| `Tools/release.sh` | Release | Merge worktree with conflict escalation |
| `Tools/timing.sh` | Timing screen | Status dashboard |
| `Tools/lesson.sh` | Lessons | Record lessons (repo-local or --global) |

## Beads CLI Quick Reference

```bash
bd create --title "..." --body "..." --label "file:src/foo.ts"
bd list --status open
bd show <bead-id> --format json
bd update <bead-id> --status closed --comment "..."
```

## Environment Variables

| Var | Required | Default | Purpose |
|-----|----------|---------|---------|
| `MINIMAX_API_KEY` | Yes (for mechanics) | — | MiniMax API key for mechanic models |
| `ANTHROPIC_API_KEY` | Yes (for pitstop-auto) | — | Anthropic API key for crew chief decomposition |
| `OPENROUTER_API_KEY` | Alternative | — | OpenRouter API key (alternative to MiniMax) |
| `OPENAI_API_BASE` | No | `https://api.minimax.io/v1` | Override API base URL |
| `PITCREW_BD` | No | `bd` in PATH or `~/go/bin/bd` | Path to Beads CLI binary |
| `PITCREW_LANE` | No | `~/pitlane` | Beads database directory |
| `PITCREW_BAYS` | No | `~/bays` | Git worktrees directory |
| `PITCREW_MODEL` | No | `openai/MiniMax-M2.5` | Model for mechanics |
| `PITCREW_CHIEF_MODEL` | No | `claude-sonnet-4-6` | Model for crew chief (pitstop-auto) |
| `PITCREW_GLOBAL_LESSONS` | No | `~/.claude/pitcrew-lessons` | Global lessons file path |
| `PITCREW_TIMEOUT` | No | `300` | Mechanic timeout in seconds |

## Cost per Pit Stop

| Mechanics | Model | Est. Cost |
|-----------|-------|-----------|
| 3-5 calls | MiniMax M2.5 | ~$0.01-0.05 |
| 5-10 calls | MiniMax M2.5 | ~$0.05-0.15 |
| 10-20 calls | MiniMax M2.5 | ~$0.15-0.50 |
| Auto-decompose | Sonnet (crew chief) | ~$0.01-0.03 |
| Conflict resolution | Opus (Max sub) | $0 (flat rate) |
