#!/usr/bin/env bash
# mechanic.sh — Launch an Aider worker on a beads task in a git worktree
#
# Usage: mechanic.sh <bead-id> <repo-path> [--model minimax/MiniMax-M2.5] [--timeout 600]
#
# Environment:
#   MINIMAX_API_KEY — MiniMax API key (required unless using local model)
#   OPENAI_API_BASE — Override API base URL (default: https://api.minimax.io/v1)

set -euo pipefail

BEAD_ID="${1:?Usage: mechanic.sh <bead-id> <repo-path> [--model MODEL] [--timeout SECONDS]}"
REPO_PATH="${2:?Usage: mechanic.sh <bead-id> <repo-path> [--model MODEL] [--timeout SECONDS]}"
MODEL="${3:-openai/MiniMax-M2.5}"
TIMEOUT="${4:-600}"

BD="${PITCREW_BD:-$(command -v bd 2>/dev/null || echo "$HOME/go/bin/bd")}"
if [ -d "$REPO_PATH/.beads" ]; then BEADS_DIR="$REPO_PATH"; else BEADS_DIR="${PITCREW_LANE:-$REPO_PATH}"; fi
WORKTREE_DIR="${PITCREW_BAYS:-$HOME/bays}"

# ── Extract bead spec ──────────────────────────────────────────────
cd "$BEADS_DIR"
BEAD_JSON=$($BD show "$BEAD_ID" --format json 2>/dev/null)
if [ -z "$BEAD_JSON" ]; then
  echo "ERROR: Bead $BEAD_ID not found"
  exit 1
fi

TITLE=$(echo "$BEAD_JSON" | jq -r '.[0].title // .title // "untitled"')
BODY=$(echo "$BEAD_JSON" | jq -r '.[0].description // .description // ""')
FILES=$(echo "$BEAD_JSON" | jq -r '(.[0].labels // .labels // [])[]' | grep '^file:' | sed 's/^file://' || true)

echo "═══ Mechanic: $BEAD_ID ═══"
echo "Task: $TITLE"
echo "Model: $MODEL"

# ── Create worktree ────────────────────────────────────────────────
BRANCH="worker/$BEAD_ID"
WORKTREE="$WORKTREE_DIR/$BEAD_ID"
mkdir -p "$WORKTREE_DIR"

cd "$REPO_PATH"
git worktree add "$WORKTREE" -b "$BRANCH" 2>/dev/null || {
  # Branch may already exist from a retry
  git worktree add "$WORKTREE" "$BRANCH" 2>/dev/null || {
    echo "ERROR: Failed to create worktree"
    $BD update "$BEAD_ID" --status blocked --comment "Worktree creation failed" 2>/dev/null
    exit 1
  }
}

# ── Update bead status ─────────────────────────────────────────────
cd "$BEADS_DIR"
$BD update "$BEAD_ID" --status in_progress 2>/dev/null || true

# ── Build the prompt ───────────────────────────────────────────────
# Load project context: .pitcrew > CLAUDE.md > auto-detect
PITCREW_CONTEXT=""
if [ -f "$REPO_PATH/.pitcrew" ]; then
  PITCREW_CONTEXT=$(cat "$REPO_PATH/.pitcrew")
elif [ -f "$REPO_PATH/CLAUDE.md" ]; then
  PITCREW_CONTEXT="Project context (from CLAUDE.md):
$(head -200 "$REPO_PATH/CLAUDE.md")"
else
  LANG_HINT=""
  if ls "$REPO_PATH"/*.nix >/dev/null 2>&1 || ls "$REPO_PATH"/nixos/ >/dev/null 2>&1; then
    LANG_HINT="This is a NixOS/Nix project."
  elif [ -f "$REPO_PATH/package.json" ]; then
    LANG_HINT="This is a JavaScript/TypeScript project."
  elif [ -f "$REPO_PATH/Cargo.toml" ]; then
    LANG_HINT="This is a Rust project."
  elif [ -f "$REPO_PATH/go.mod" ]; then
    LANG_HINT="This is a Go project."
  elif [ -f "$REPO_PATH/deps.edn" ] || [ -f "$REPO_PATH/project.clj" ]; then
    LANG_HINT="This is a Clojure project."
  elif [ -f "$REPO_PATH/pyproject.toml" ] || [ -f "$REPO_PATH/setup.py" ]; then
    LANG_HINT="This is a Python project."
  fi
  PITCREW_CONTEXT="You are a coding agent working on a project. ${LANG_HINT}
Match existing code conventions exactly."
fi

# Load lessons: repo-local first, then global
PITCREW_LESSONS=""
if [ -f "$REPO_PATH/.pitcrew-lessons" ]; then
  PITCREW_LESSONS=$(grep "^LESSON:" "$REPO_PATH/.pitcrew-lessons" 2>/dev/null || true)
fi
GLOBAL_LESSONS="${PITCREW_GLOBAL_LESSONS:-$HOME/.claude/pitcrew-lessons}"
if [ -f "$GLOBAL_LESSONS" ]; then
  GLOBAL_L=$(grep "^LESSON:" "$GLOBAL_LESSONS" 2>/dev/null || true)
  if [ -n "$GLOBAL_L" ]; then
    PITCREW_LESSONS="${PITCREW_LESSONS}
${GLOBAL_L}"
  fi
fi

SYSTEM_PREFIX="${PITCREW_CONTEXT}
${PITCREW_LESSONS:+
LESSONS FROM PREVIOUS PIT STOPS (avoid these mistakes):
$PITCREW_LESSONS}

RULES — follow these exactly:
- ONLY modify files listed in the task. Do not touch other files.
- Match existing code style exactly. If the file uses hyphens, use hyphens. If camelCase, use camelCase.
- Do NOT refactor, rename, reformat, or reorganise anything outside the task scope.
- Do NOT add comments, docstrings, or explanations to code you write.
- Do NOT fix, improve, or clean up code you were not asked to change.
- If you are blocked or unsure for more than 2 minutes, STOP and write a comment in the file explaining what blocked you. Do not guess.

WHAT DONE LOOKS LIKE:
- The specific change described in DETAILS is made
- No other files are modified
- The code compiles / passes type checks
- You are finished. Do not explore further."

PROMPT="${SYSTEM_PREFIX}

TASK: $TITLE

DETAILS:
$BODY"

# ── Launch Aider ───────────────────────────────────────────────────
cd "$WORKTREE"

# Set up API — supports MiniMax direct or OpenRouter
if [ -n "${OPENROUTER_API_KEY:-}" ]; then
  export OPENAI_API_KEY="$OPENROUTER_API_KEY"
  export OPENAI_API_BASE="https://openrouter.ai/api/v1"
elif [ -n "${MINIMAX_API_KEY:-}" ]; then
  export OPENAI_API_KEY="$MINIMAX_API_KEY"
  export OPENAI_API_BASE="${OPENAI_API_BASE:-https://api.minimax.io/v1}"
fi

# Build file list for aider
AIDER_FILES=""
if [ -n "$FILES" ]; then
  AIDER_FILES="$FILES"
fi

echo "Starting Aider in $WORKTREE..."

# Run aider with timeout
timeout "$TIMEOUT" aider \
  --model "$MODEL" \
  --no-auto-commits \
  --yes-always \
  --no-suggest-shell-commands \
  --no-pretty \
  --no-stream \
  --message "$PROMPT" \
  $AIDER_FILES \
  2>&1 | tee "/tmp/worker-$BEAD_ID.log"

EXIT_CODE=${PIPESTATUS[0]}

# ── Handle result ──────────────────────────────────────────────────
cd "$WORKTREE"

if [ $EXIT_CODE -eq 0 ]; then
  # Check if any files changed
  CHANGES=$(git status --porcelain | wc -l)
  if [ "$CHANGES" -gt 0 ]; then
    # Persist to git FIRST — if session dies here, work survives in the worktree
    git add -A
    git commit -m "[$BEAD_ID] $TITLE

Automated mechanic commit via Pitcrew.
Model: $MODEL"

    # THEN update bead status — losing this is recoverable, losing the commit isn't
    cd "$BEADS_DIR"
    $BD update "$BEAD_ID" --status closed --comment "Done. $CHANGES file(s) changed." 2>/dev/null || true
    echo "✓ Mechanic done: $CHANGES file(s) changed"
  else
    cd "$BEADS_DIR"
    $BD update "$BEAD_ID" --status closed --comment "No changes needed." 2>/dev/null || true
    echo "✓ Mechanic done: no changes needed"
  fi
elif [ $EXIT_CODE -eq 124 ]; then
  cd "$BEADS_DIR"
  $BD update "$BEAD_ID" --status blocked --comment "Timed out after ${TIMEOUT}s" 2>/dev/null || true
  echo "✗ Mechanic timed out"
else
  cd "$BEADS_DIR"
  $BD update "$BEAD_ID" --status blocked --comment "Aider exit code: $EXIT_CODE" 2>/dev/null || true
  echo "✗ Mechanic failed (exit $EXIT_CODE)"
fi

echo "Log: /tmp/worker-$BEAD_ID.log"
