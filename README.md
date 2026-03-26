# Pitcrew

**Parallel AI coding agents, coordinated like an F1 pit stop.**

A crew chief (your frontier model) decomposes features into pit calls, dispatches mechanics (cheap models via Aider or direct API) to separate bays (git worktrees), and releases them back to the track (merges to main). When a mechanic hits trouble, they radio the crew chief.

```
Crew Chief (Claude / GPT / your frontier model)
│
├── Pit Call 1 → Mechanic → Bay A → backend change
├── Pit Call 2 → Mechanic → Bay B → frontend change
├── Pit Call 3 → Mechanic → Bay C → API handler
└── Pit Call 4 → Mechanic → Bay D → tests
                                     │
                          Release ← merge all bays to main
```

## Why

An F1 pit crew changes four tyres, adjusts the front wing, and tops up in under 2 seconds. They don't do it with one person — they do it with 20 people working in parallel on different parts of the same car.

Pitcrew does the same with code. Your frontier model is the crew chief — it understands the whole project. The mechanics are cheap models doing bounded tasks. Beads coordinate the work. Git worktrees isolate the bays. Merges release the car.

**Cost**: ~$0.002 per mechanic. A 10-call pit stop costs ~$0.02.

## Two Mechanic Modes

### `mechanic-lite.sh` (recommended)
Direct API call via curl. No dependencies beyond curl + jq + git + bd. Runs anywhere — containers, CI, your laptop. **3-6 seconds per mechanic.**

### `mechanic.sh`
Uses [Aider](https://aider.chat) for the coding agent. More capable (repo-map, multi-file edits) but requires Python and takes ~30 seconds. Better for complex tasks.

## Prerequisites

- [Beads](https://github.com/steveyegge/beads) (`bd` CLI) — work coordination
- Git 2.25+ (worktree support)
- curl + jq (for mechanic-lite)
- [Aider](https://aider.chat) (optional, for mechanic.sh)
- A model API key (MiniMax, OpenRouter, DeepSeek, or local via Ollama)

## Quick Start

```bash
# 1. Clone
git clone https://github.com/asachs/pitcrew
cd pitcrew

# 2. Set up the pit lane (Beads repo)
mkdir -p ~/pitlane && cd ~/pitlane && bd init

# 3. Set your mechanic's API key
export MINIMAX_API_KEY="sk-..."

# 4. Make a pit call
cd ~/pitlane
bd create \
  --title "Add email field to user schema" \
  --body "Edit src/schema.sql. Add email VARCHAR(255) NOT NULL to the users table." \
  --label "file:src/schema.sql"

# 5. Send a mechanic
./tools/mechanic-lite.sh beads-abc ~/my-project

# 6. Release back to track
./tools/release.sh beads-abc ~/my-project

# 7. Check the timing screen
./tools/timing.sh
```

## Full Pit Stop (parallel)

```bash
# One command — dispatches all mechanics, monitors, releases
./tools/pitstop.sh ~/my-project beads-abc beads-def beads-ghi

# Or manually:
for CALL in $(bd list --status open --format ids); do
  ./tools/mechanic-lite.sh "$CALL" ~/my-project &
done
wait

for CALL in $(bd list --status closed --format ids); do
  ./tools/release.sh "$CALL" ~/my-project
done
```

## Project Context (.pitcrew file)

Place a `.pitcrew` file in your project root to give mechanics context:

```
You are a coding agent for an e-commerce platform.
Tech stack: Python/FastAPI backend (api/), Next.js frontend (web/).
Conventions: snake_case in Python, camelCase in TypeScript.
```

This is injected into every mechanic's system prompt. MiniMax auto-caches shared prefixes for ~10x cheaper input on batched calls.

### Writing Good .pitcrew Context

The `.pitcrew` file should include **CORRECT/WRONG examples** for patterns the model tends to get wrong. From real-world testing:

```
CRITICAL conventions you MUST follow:

Datomic keys use BRACKET NOTATION:
  CORRECT: vehicle['vehicle/make']
  WRONG:   vehicle.make

API responses are typed and returned directly:
  CORRECT: const data = await api.get<{ items: Item[] }>('/items'); data.items
  WRONG:   response.data.items

Theme colours:
  CORRECT: colors.chassis[400], colors.red[500], '#fff'
  WRONG:   colors.primary, colors.error, 'chassis-600'
```

Without these examples, mechanics consistently make the same systematic errors. With them: zero errors.

## Pre-merge Verification (.pitcrew-verify)

Place a `.pitcrew-verify` script in your project root. It runs in the bay before merging:

```bash
#!/bin/bash
# Only check files that changed
if git diff main..HEAD --name-only | grep -q "^web/"; then
  cd web && npx tsc --noEmit
fi
```

Failed verification creates an escalation bead instead of merging broken code.

## Tools

| Tool | Role | Speed | Deps |
|------|------|-------|------|
| `tools/mechanic-lite.sh` | Mechanic (direct API) | 3-6s | curl, jq, git |
| `tools/mechanic.sh` | Mechanic (via Aider) | ~30s | Python, Aider |
| `tools/pitstop.sh` | Full pit stop with live view | — | mechanic-lite |
| `tools/release.sh` | Merge bay to main | instant | git |
| `tools/timing.sh` | Status dashboard | instant | bd |

## Conflict Escalation (Radio Protocol)

| Flag | Situation | Action |
|------|-----------|--------|
| Green | Clean merge | Auto-release |
| Yellow | Text conflict | Try rebase |
| Red | Semantic conflict | Radio crew chief (escalation bead) |
| Black | Architectural clash | Human decision |

## Mechanic Configuration

```bash
# MiniMax direct (default — best quality per dollar)
export MINIMAX_API_KEY="sk-..."
./tools/mechanic-lite.sh beads-abc ~/project

# OpenRouter
export OPENROUTER_API_KEY="sk-or-..."
./tools/mechanic.sh beads-abc ~/project "openrouter/minimax/minimax-m2.5"

# DeepSeek (cheaper for simple tasks)
export OPENAI_API_BASE="https://api.deepseek.com/v1"
./tools/mechanic-lite.sh beads-abc ~/project "deepseek-coder"

# Local via Ollama (free, sequential)
export OPENAI_API_BASE="http://localhost:11434/v1"
./tools/mechanic-lite.sh beads-abc ~/project "qwen2.5-coder:32b"
```

## Environment Variables

| Var | Purpose |
|-----|---------|
| `MINIMAX_API_KEY` | MiniMax API key (default provider) |
| `OPENROUTER_API_KEY` | OpenRouter key (alternative) |
| `OPENAI_API_BASE` | Custom API base URL |
| `PITCREW_BD` | Path to `bd` binary (default: autodetect) |
| `PITCREW_LANE` | Beads repo path (default: `~/pitlane`) |
| `PITCREW_BAYS` | Worktree directory (default: `~/bays`) |
| `PITCREW_MODEL` | Default model (default: `MiniMax-M2.5`) |
| `PITCREW_TIMEOUT` | Mechanic timeout in seconds (default: 300) |

## Prompt Engineering Lessons

From testing with MiniMax M2.5 across 3 prompt iterations:

| Iteration | Errors | Cost | Fix |
|-----------|--------|------|-----|
| v1 (basic prompt) | 7 | $0.001 | — |
| v2 (added CORRECT/WRONG examples) | 5 | $0.003 | Bracket notation fixed, theme errors remained |
| v3 (added theme colour examples) | 0 | $0.003 | All errors eliminated |

**Key findings:**
- CORRECT/WRONG examples in `.pitcrew` eliminate systematic errors
- Constraint prompts ("do NOT") work better than instruction prompts ("please do")
- Include "WHAT DONE LOOKS LIKE" so the mechanic knows when to stop
- `max_tokens: 16384` — don't choke the model (we learned this the hard way)
- A $0.002 improvement in prompt quality saves all rework cost

Patterns adopted from [Gastown](https://github.com/steveyegge/gastown):
- **Scrutineering** — pre-merge verification via `.pitcrew-verify`
- **Persistence-before-close** — git commit before bead status update
- **Hard time gate** — mechanic stops if blocked >2 minutes
- **Separation of concerns** — mechanics never merge their own work

## Real-World Results

Building a mobile app (11 React Native screens):

| Metric | Value |
|--------|-------|
| Screens built by mechanics | 10 of 11 |
| Screens built by crew chief | 1 (VehicleDetail — 400 lines) |
| Total mechanic cost | $0.02 |
| Time per mechanic (lite) | 3-6 seconds |
| Time per mechanic (Aider) | 25-30 seconds |
| Prompt iterations to zero errors | 3 |
| MiniMax M2.5 vs Opus quality (after v3 prompt) | Equivalent |

The VehicleDetail experiment: same 400-line screen built by both crew chief (Opus) and mechanic (MiniMax M2.5). Feature parity. Zero errors from the mechanic. Cost: $0.008 vs $0 (Max sub). The assumption that complex screens need a frontier model was wrong.

## PAI Integration

Works as a skill in [PAI](https://github.com/danielmiessler/Personal_AI_Infrastructure):

```bash
cp -r skill/ ~/.claude/skills/Pitcrew/
```

## Inspired By

- [Gastown](https://github.com/steveyegge/gastown) — Steve Yegge's "Kubernetes for AI coding agents"
- [Beads](https://github.com/steveyegge/beads) — Git-backed distributed issue tracking
- [PAI](https://github.com/danielmiessler/Personal_AI_Infrastructure) — Daniel Miessler's Personal AI Infrastructure
- [Aider](https://aider.chat) — AI pair programming in the terminal

## License

MIT
