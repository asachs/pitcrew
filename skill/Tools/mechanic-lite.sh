#!/usr/bin/env bash
# mechanic-lite.sh — Lightweight mechanic that calls the model API directly
# No Aider dependency — just curl + jq + git. Runs anywhere.
#
# Usage: mechanic-lite.sh <bead-id> <repo-path> [model] [timeout]

set -euo pipefail

BEAD_ID="${1:?Usage: mechanic-lite.sh <bead-id> <repo-path> [model] [timeout]}"
REPO_PATH="${2:?Usage: mechanic-lite.sh <bead-id> <repo-path> [model] [timeout]}"
# Strip provider prefix if present (openai/MiniMax-M2.5 → MiniMax-M2.5)
RAW_MODEL="${3:-MiniMax-M2.5}"
MODEL="${RAW_MODEL##*/}"
TIMEOUT="${4:-120}"

BD="${PITCREW_BD:-$(command -v bd 2>/dev/null || echo "$HOME/go/bin/bd")}"
# Beads DB: prefer repo path if it has .beads/, else try PITCREW_LANE
if [ -d "$REPO_PATH/.beads" ]; then BEADS_DIR="$REPO_PATH"; else BEADS_DIR="${PITCREW_LANE:-$REPO_PATH}"; fi
WORKTREE_DIR="${PITCREW_BAYS:-$HOME/bays}"
API_BASE="${OPENAI_API_BASE:-https://api.minimax.io/v1}"
API_KEY="${MINIMAX_API_KEY:-${OPENAI_API_KEY:-}}"

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
  git worktree add "$WORKTREE" "$BRANCH" 2>/dev/null || {
    echo "ERROR: Failed to create worktree"
    exit 1
  }
}

# ── Update bead status ─────────────────────────────────────────────
cd "$BEADS_DIR"
$BD update "$BEAD_ID" --status in_progress 2>/dev/null || true

# ── Read the target file ───────────────────────────────────────────
cd "$WORKTREE"
FILE_CONTENT=""
TARGET_FILE=""
if [ -n "$FILES" ]; then
  TARGET_FILE=$(echo "$FILES" | head -1)
  if [ -f "$TARGET_FILE" ]; then
    FILE_CONTENT=$(cat "$TARGET_FILE")
  fi
fi

# ── Load project context + lessons ────────────────────────────────
PITCREW_CONTEXT=""
if [ -f "$REPO_PATH/.pitcrew" ]; then
  PITCREW_CONTEXT=$(cat "$REPO_PATH/.pitcrew")
elif [ -f "$REPO_PATH/CLAUDE.md" ]; then
  # Auto-generate context from CLAUDE.md
  PITCREW_CONTEXT="Project context (from CLAUDE.md):
$(head -200 "$REPO_PATH/CLAUDE.md")"
else
  # Auto-detect from repo structure
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

SYSTEM="${PITCREW_CONTEXT:-You are a coding agent. Complete only the task assigned to you.}
${PITCREW_LESSONS:+
LESSONS FROM PREVIOUS PIT STOPS (avoid these mistakes):
$PITCREW_LESSONS}

RULES:
- ONLY modify the file specified. Do not touch other files.
- Match existing code style exactly.
- Do NOT refactor, rename, or reformat anything outside the task scope.
- Do NOT add comments explaining what you changed.
- If blocked, say BLOCKED: and explain why.

OUTPUT FORMAT:
Respond with ONLY the complete new file content. No markdown fences. No explanations.
Start your response with the first line of the file."

USER_MSG="TASK: $TITLE

DETAILS:
$BODY

TARGET FILE: $TARGET_FILE"

if [ -n "$FILE_CONTENT" ]; then
  USER_MSG="$USER_MSG

CURRENT FILE CONTENT:
$FILE_CONTENT"
else
  USER_MSG="$USER_MSG

This is a NEW file. Create it from scratch."
fi

# ── Call model API ─────────────────────────────────────────────────
echo "Calling $MODEL..."

RESPONSE=$(curl -s --max-time "$TIMEOUT" "$API_BASE/chat/completions" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d "$(jq -n \
    --arg model "$MODEL" \
    --arg system "$SYSTEM" \
    --arg user "$USER_MSG" \
    '{model: $model, messages: [{role: "system", content: $system}, {role: "user", content: $user}], max_tokens: 16384}')")

# Extract content
CONTENT=$(echo "$RESPONSE" | jq -r '.choices[0].message.content // empty')
ERROR=$(echo "$RESPONSE" | jq -r '.error.message // .message // empty')

if [ -z "$CONTENT" ]; then
  echo "ERROR: No response from model. $ERROR"
  cd "$BEADS_DIR"
  $BD update "$BEAD_ID" --status blocked --comment "Model returned no content: $ERROR" 2>/dev/null || true
  exit 1
fi

# Check for BLOCKED response
if echo "$CONTENT" | head -1 | grep -q "^BLOCKED:"; then
  echo "BLOCKED: $(echo "$CONTENT" | head -3)"
  cd "$BEADS_DIR"
  $BD update "$BEAD_ID" --status blocked --comment "$CONTENT" 2>/dev/null || true
  exit 1
fi

# ── Strip model artifacts from output ─────────────────────────────
# Remove <think>...</think> blocks (MiniMax M2.5 reasoning traces)
CONTENT=$(echo "$CONTENT" | sed '/<think>/,/<\/think>/d')
# Remove markdown fences
CONTENT=$(echo "$CONTENT" | sed '/^```[a-z]*$/d' | sed '/^```$/d')

# ── Write the file ─────────────────────────────────────────────────
cd "$WORKTREE"

if [ -n "$TARGET_FILE" ]; then
  mkdir -p "$(dirname "$TARGET_FILE")"
  echo "$CONTENT" > "$TARGET_FILE"
fi

# Get token usage
SENT=$(echo "$RESPONSE" | jq -r '.usage.prompt_tokens // 0')
RECV=$(echo "$RESPONSE" | jq -r '.usage.completion_tokens // 0')

# ── Commit ─────────────────────────────────────────────────────────
CHANGES=$(git status --porcelain | wc -l)
if [ "$CHANGES" -gt 0 ]; then
  git add -A
  git commit -m "[$BEAD_ID] $TITLE

Automated mechanic commit via Pitcrew.
Model: $MODEL"

  cd "$BEADS_DIR"
  $BD update "$BEAD_ID" --status closed --comment "Done. $CHANGES file(s). Tokens: ${SENT}in/${RECV}out." 2>/dev/null || true
  echo "✓ Mechanic done: $CHANGES file(s) changed (Tokens: ${SENT} sent, ${RECV} received)"
else
  cd "$BEADS_DIR"
  $BD update "$BEAD_ID" --status closed --comment "No changes needed." 2>/dev/null || true
  echo "✓ Mechanic done: no changes needed"
fi
