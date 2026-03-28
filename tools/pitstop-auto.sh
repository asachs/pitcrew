#!/usr/bin/env bash
# pitstop-auto.sh — Auto-decompose a task into beads and run a pit stop
#
# Usage: pitstop-auto.sh <repo-path> "task description"
#
# Uses the crew chief model (Sonnet via Anthropic API) to decompose a task
# into independent beads, then dispatches mechanics via pitstop.sh.

set -euo pipefail

REPO_PATH="${1:?Usage: pitstop-auto.sh <repo-path> \"task description\"}"
TASK="${2:?Usage: pitstop-auto.sh <repo-path> \"task description\"}"

BD="${PITCREW_BD:-$(command -v bd 2>/dev/null || echo "$HOME/go/bin/bd")}"
BEADS_DIR="${PITCREW_LANE:-$HOME/pitlane}"
BAYS_DIR="${PITCREW_BAYS:-$HOME/bays}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
API_KEY="${ANTHROPIC_API_KEY:-}"
CHIEF_MODEL="${PITCREW_CHIEF_MODEL:-claude-sonnet-4-6}"

if [ -z "$API_KEY" ]; then
  echo "ERROR: ANTHROPIC_API_KEY required for auto-decomposition"
  exit 1
fi

# Auto-init beads DB if not present
cd "$REPO_PATH"
if ! $BD list --status open --format ids >/dev/null 2>&1; then
  $BD init --quiet 2>/dev/null || true
fi

# Get repo context
REPO_NAME=$(basename "$REPO_PATH")
FILE_TREE=$(cd "$REPO_PATH" && git ls-files 2>/dev/null | head -80 || find . -maxdepth 3 -type f | head -80)
CLAUDE_MD=""
if [ -f "$REPO_PATH/CLAUDE.md" ]; then
  CLAUDE_MD=$(head -100 "$REPO_PATH/CLAUDE.md")
fi
PITCREW_CTX=""
if [ -f "$REPO_PATH/.pitcrew" ]; then
  PITCREW_CTX=$(cat "$REPO_PATH/.pitcrew")
fi

# Ask crew chief to decompose
SYSTEM="You are a Pitcrew crew chief. Decompose a coding task into independent beads (work units) that can be executed in parallel by simple coding agents.

Each bead should:
- Touch at most 1-2 files
- Be completable independently (no dependencies between beads)
- Have a clear title and detailed body with acceptance criteria
- Include file: labels for target files

Respond with ONLY a JSON array of beads. No markdown fences. No explanation.

Format:
[
  {\"title\": \"short action title\", \"body\": \"detailed spec with acceptance criteria\", \"labels\": [\"file:path/to/file.ext\"]},
  ...
]

If the task cannot be parallelized (single file, sequential steps), return a single-element array."

USER_MSG="REPOSITORY: $REPO_NAME

${CLAUDE_MD:+PROJECT CONTEXT (CLAUDE.md):
$CLAUDE_MD

}${PITCREW_CTX:+PITCREW CONTEXT:
$PITCREW_CTX

}FILE TREE:
$FILE_TREE

TASK TO DECOMPOSE:
$TASK"

echo ""
echo "  Crew Chief ($CHIEF_MODEL) analyzing task..."

RESPONSE=$(curl -s --max-time 60 "https://api.anthropic.com/v1/messages" \
  -H "x-api-key: $API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "Content-Type: application/json" \
  -d "$(jq -n \
    --arg model "$CHIEF_MODEL" \
    --arg system "$SYSTEM" \
    --arg user "$USER_MSG" \
    '{model: $model, max_tokens: 4096, system: $system, messages: [{role: "user", content: $user}]}')")

# Extract content
CONTENT=$(echo "$RESPONSE" | jq -r '.content[0].text // empty')

if [ -z "$CONTENT" ]; then
  ERROR=$(echo "$RESPONSE" | jq -r '.error.message // "unknown error"')
  echo "  ERROR: Crew chief failed: $ERROR"
  exit 1
fi

# Strip markdown fences if present
CONTENT=$(echo "$CONTENT" | sed '/^```[a-z]*$/d' | sed '/^```$/d')

# Validate JSON
if ! echo "$CONTENT" | jq '.' >/dev/null 2>&1; then
  echo "  ERROR: Crew chief returned invalid JSON"
  echo "  Response: $CONTENT"
  exit 1
fi

BEAD_COUNT=$(echo "$CONTENT" | jq 'length')
echo "  Decomposed into $BEAD_COUNT bead(s)"
echo ""

# Create beads
BEAD_IDS=()
cd "$BEADS_DIR" 2>/dev/null || cd "$REPO_PATH"

for i in $(seq 0 $((BEAD_COUNT - 1))); do
  TITLE=$(echo "$CONTENT" | jq -r ".[$i].title")
  BODY=$(echo "$CONTENT" | jq -r ".[$i].body")
  LABELS=$(echo "$CONTENT" | jq -r ".[$i].labels[]?" 2>/dev/null || true)

  LABEL_ARGS=""
  for L in $LABELS; do
    LABEL_ARGS="$LABEL_ARGS --label $L"
  done

  RESULT=$($BD create --title "$TITLE" --body "$BODY" $LABEL_ARGS 2>&1)
  BEAD_ID=$(echo "$RESULT" | grep -o '[a-z0-9_-]*-[a-z0-9]*' | head -1 || echo "")

  if [ -n "$BEAD_ID" ]; then
    BEAD_IDS+=("$BEAD_ID")
    echo "  Created: $BEAD_ID — $TITLE"
  else
    echo "  WARNING: Failed to create bead: $TITLE"
    echo "  $RESULT"
  fi
done

if [ ${#BEAD_IDS[@]} -eq 0 ]; then
  echo "  ERROR: No beads created"
  exit 1
fi

echo ""

# Dispatch via pitstop
exec "$SCRIPT_DIR/pitstop.sh" "$REPO_PATH" "${BEAD_IDS[@]}"
