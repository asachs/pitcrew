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

## Global Operation

Pitcrew works on any git repo without per-repo configuration:

- **Auto-init**: Beads DB initializes automatically on first use (`bd init` runs if no `.beads/` exists)
- **Auto-context**: Mechanics detect project context in priority order: `.pitcrew` > `CLAUDE.md` (first 200 lines) > auto-detected language (Nix, JS/TS, Rust, Go, Clojure, Python)
- **Global lessons**: `~/.claude/pitcrew-lessons` applies to all repos alongside repo-local `.pitcrew-lessons`
- **Smart DB resolution**: Scripts prefer `.beads/` in the repo over `PITCREW_LANE` env var — no conflicts when working across multiple projects
- **Think-tag stripping**: MiniMax M2.5 reasoning traces (`<think>...</think>`) are automatically stripped from output

## Two Environments

Pitcrew runs in two environments — choose the one that matches your setup, or use both.

### CLI Environment (Claude Code / PAI / terminal)

Shell scripts that dispatch mechanics via direct API calls or Aider. Orchestrated by your frontier model in an interactive session.

```
You (in Claude Code / terminal)
  → tools/pitstop-auto.sh     (one-command: decompose + dispatch + merge)
  → tools/mechanic-lite.sh    (3-6s, curl + jq)
  → tools/mechanic.sh         (30s, via Aider)
  → tools/pitstop.sh          (parallel dispatch + live monitor)
  → tools/release.sh          (merge with conflict escalation)
```

**Best for:** Claude Code users, PAI users, CI pipelines, anyone comfortable in a terminal.

### GitHub Copilot Environment (MCP server)

An MCP server that exposes bay management and beads integration as tools for the GitHub Copilot CLI agent. The crew chief agent instructions live in `.github/agents/pitcrew.md`.

```
Copilot CLI (crew chief)
  → MCP tools: create_bay, list_bays, release_bay, cleanup_bays, create_pit_call, list_pit_calls, claim_pit_call, close_pit_call, timing_screen, load_context, add_lesson
  → Background tasks: dispatches mechanics via Copilot's task(mode="background")
```

**Best for:** GitHub Copilot CLI users, VS Code with Copilot agent mode.

### Key Differences

| | CLI | Copilot |
|---|---|---|
| Crew chief | Your frontier model (interactive) | Copilot CLI agent (`.github/agents/`) |
| Mechanic dispatch | Shell scripts (bash) | MCP tools + background tasks |
| Mechanic models | MiniMax M2.5 via API / Aider | Claude Haiku/Sonnet via Copilot |
| Bay prefix | `~/bays/{bead-id}` | `~/bays/pit-{bead-id}` |
| Project context | `.pitcrew` file | `.pitcrew` file (shared) |
| Verification | `.pitcrew-verify` script | `.pitcrew-verify` script (shared) |
| Lessons | `.pitcrew-lessons` (auto-injected) | `.pitcrew-lessons` (auto-appended) |
| Add lesson | `tools/lesson.sh` | Crew chief appends directly |

Both environments share the same Beads coordination, `.pitcrew` context, `.pitcrew-verify` gate, and `.pitcrew-lessons` feedback loop. You can use them interchangeably on the same project.

## Mechanic Modes (CLI)

### `mechanic-lite.sh` (recommended)
Direct API call via curl. No dependencies beyond curl + jq + git + bd. Runs anywhere — containers, CI, your laptop. **3-6 seconds per mechanic.**

### `mechanic.sh`
Uses [Aider](https://aider.chat) for the coding agent. More capable (repo-map, multi-file edits) but requires Python and takes ~30 seconds. Better for complex tasks.

## Prerequisites

**CLI environment:**
- [Beads](https://github.com/steveyegge/beads) (`bd` CLI) — work coordination
  ```bash
  go install github.com/steveyegge/beads/cmd/bd@latest
  # or download binary from https://github.com/steveyegge/beads/releases
  ```
- Git 2.25+ (worktree support)
- curl + jq (for mechanic-lite)
- [Aider](https://aider.chat) (optional, only for mechanic.sh — `pip install aider-chat`)
- A model API key — at minimum `MINIMAX_API_KEY` for mechanics
- `ANTHROPIC_API_KEY` (optional, for `pitstop-auto.sh` crew chief decomposition)

**Copilot environment:**
- [GitHub Copilot CLI](https://docs.github.com/en/copilot/github-copilot-in-the-cli) with agent mode
- Node.js 18+ (for MCP server)
- [Beads](https://github.com/steveyegge/beads) (`bd` CLI)

## Quick Start

```bash
# 1. Clone
git clone https://github.com/asachs/pitcrew
cd pitcrew

# 2. Set your API keys
export MINIMAX_API_KEY="sk-..."          # for mechanics
export ANTHROPIC_API_KEY="sk-ant-..."    # for pitstop-auto crew chief (optional)

# 3. One-command pit stop (auto-decomposes task into beads)
./tools/pitstop-auto.sh ~/my-project "add try-catch error handling to all route files"

# Or manually:
# 4. Create beads
cd ~/my-project
bd init  # auto-runs on first use, but can be explicit
bd create --title "Add error handling to users route" --label "file:src/routes/users.ts"
bd create --title "Add error handling to posts route" --label "file:src/routes/posts.ts"

# 5. Run pit stop
./tools/pitstop.sh ~/my-project bead-id-1 bead-id-2

# 6. Check the timing screen
./tools/timing.sh
```

**No per-repo setup needed.** Works on any git repo. Context auto-detected from `.pitcrew` > `CLAUDE.md` > language detection.

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

Theme colours — use the palette object, not string names:
  CORRECT: colors.brand[400], colors.red[500], '#fff'
  WRONG:   colors.primary, colors.error, 'brand-600'
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
| `tools/pitstop-auto.sh` | **One-command pit stop** — auto-decompose + dispatch | 20-60s | Anthropic API key, bd, jq, curl |
| `tools/mechanic-lite.sh` | Mechanic (direct API) | 3-6s | curl, jq, git, bd |
| `tools/mechanic.sh` | Mechanic (via Aider) | ~30s | Python, Aider, bd, git |
| `tools/pitstop.sh` | Pit stop with manual beads | — | mechanic-lite, bd, jq |
| `tools/release.sh` | Merge bay to main | instant | git, bd |
| `tools/timing.sh` | Status dashboard | instant | bd |
| `tools/lesson.sh` | Add lesson (repo-local or `--global`) | instant | — |

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
| `PITCREW_LANE` | Beads repo path (default: repo path if `.beads/` exists, else `~/pitlane`) |
| `PITCREW_BAYS` | Worktree directory (default: `~/bays`) |
| `PITCREW_MODEL` | Default model (default: `openai/MiniMax-M2.5`) |
| `PITCREW_TIMEOUT` | Mechanic timeout in seconds (default: 300) |
| `PITCREW_GLOBAL_LESSONS` | Global lessons file (default: `~/.claude/pitcrew-lessons`) |
| `PITCREW_CHIEF_MODEL` | Model for pitstop-auto decomposition (default: `claude-sonnet-4-6`) |
| `ANTHROPIC_API_KEY` | Required for `pitstop-auto.sh` crew chief decomposition |

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

## Copilot Setup

### 1. Install the MCP server

```bash
cd mcp && npm install && npm run build
```

### 2. Configure Copilot

The `.mcp.json` in `mcp/` registers the Pitcrew MCP server. Copy it to your project root or Copilot config directory.

### 3. Agent instructions

The crew chief agent instructions are at `.github/agents/pitcrew.md`. Copilot loads these automatically when you invoke the Pitcrew agent.

### 4. Model hierarchy (Copilot)

| Role | Model | Responsibility |
|------|-------|----------------|
| Crew Chief | `claude-opus-4.6` | Decompose, review, resolve conflicts, merge |
| Mechanic | `claude-haiku-4.5` | Bounded single-file edits (background tasks) |
| Senior Mechanic | `claude-sonnet-4.6` | Complex multi-file tasks (≤5 files) |
| Investigator | `claude-haiku-4.5` | Read-only parallel analysis |

### MCP Tools

| Tool | Description |
|------|-------------|
| `create_bay` | Create a git worktree (bay) for a pit call |
| `list_bays` | List all active bays with status |
| `release_bay` | Merge bay to main and clean up |
| `cleanup_bays` | Remove all pit worktrees and branches |
| `create_pit_call` | Create a new pit call (bead) for tracking |
| `list_pit_calls` | List all pit calls with their status |
| `claim_pit_call` | Claim a pit call (set to in_progress) |
| `close_pit_call` | Close a completed pit call |
| `timing_screen` | Show pit stop status dashboard |
| `load_context` | Load `.pitcrew` and `.pitcrew-lessons` for prompt injection |
| `add_lesson` | Add a lesson learned to `.pitcrew-lessons` |

## Self-Improvement (.pitcrew-lessons)

The `.pitcrew-lessons` file captures mistakes encountered during pit stops. Each lesson is automatically appended to mechanic prompts to prevent recurrence.

```
LESSON: Git CRLF config causes merge failures on Windows → Always run git config core.autocrlf false in the worktree.
LESSON: Mechanic output wrapped in markdown fences breaks file writes → Strip ``` lines from model output before writing.
```

The crew chief adds lessons when a pit stop encounters a new class of error. Future mechanics benefit automatically.

## PAI Integration

Works as a skill in [PAI](https://github.com/danielmiessler/Personal_AI_Infrastructure):

```bash
cp -r skill/ ~/.claude/skills/Pitcrew/
```

## Project Structure

```
pitcrew/
├── tools/                        ← CLI environment
│   ├── pitstop-auto.sh           ← One-command: describe task → dispatch → merge
│   ├── mechanic-lite.sh          ← Direct API mechanic (3-6s)
│   ├── mechanic.sh               ← Aider-based mechanic (30s)
│   ├── pitstop.sh                ← Pit stop with manual beads
│   ├── release.sh                ← Merge bay to main
│   ├── lesson.sh                 ← Add lesson (--global or repo-local)
│   └── timing.sh                 ← Status dashboard
│
├── mcp/                          ← Copilot environment
│   ├── src/index.ts              ← MCP server (bay + beads tools)
│   ├── .mcp.json                 ← Copilot MCP config
│   ├── package.json
│   ├── package-lock.json
│   ├── tsconfig.json
│   └── start.js                  ← MCP server entry point
│
├── .github/agents/
│   └── pitcrew.md                ← Copilot crew chief instructions
│
├── skill/                        ← PAI skill package
│   ├── SKILL.md                  ← Skill definition
│   └── Tools/                    ← CLI tools (mirrored)
│
├── examples/
│   └── parallel-pitstop.md       ← Walkthrough example
│
├── .pitcrew-lessons              ← Self-improvement lessons
├── .gitignore
├── setup.sh                      ← Install dependencies + first-use config
├── test.sh                       ← End-to-end smoke test
├── LICENSE
└── README.md
```

### Shared files (used by both environments)

These live in **your project repo**, not in pitcrew:

| File | Purpose | Used by |
|------|---------|---------|
| `.pitcrew` | Project context injected into mechanic prompts | CLI + Copilot |
| `.pitcrew-verify` | Pre-merge verification script | CLI + Copilot |
| `.pitcrew-lessons` | Accumulated lessons injected into mechanic prompts | CLI + Copilot |

## Inspired By

- [Gastown](https://github.com/steveyegge/gastown) — Steve Yegge's "Kubernetes for AI coding agents"
- [Beads](https://github.com/steveyegge/beads) — Git-backed distributed issue tracking
- [PAI](https://github.com/danielmiessler/Personal_AI_Infrastructure) — Daniel Miessler's Personal AI Infrastructure
- [Aider](https://aider.chat) — AI pair programming in the terminal

## License

MIT
