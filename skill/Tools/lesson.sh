#!/usr/bin/env bash
# lesson.sh — Add a lesson to .pitcrew-lessons after a pit stop problem
#
# Usage: lesson.sh <repo-path> "what went wrong → what to do instead"
#
# Example:
#   lesson.sh ~/src/myproject "Model renamed hyphens to underscores → Add 'do NOT change naming conventions' to .pitcrew context"

set -euo pipefail

REPO_PATH="${1:?Usage: lesson.sh <repo-path> \"lesson text\"}"
LESSON="${2:?Usage: lesson.sh <repo-path> \"lesson text\"}"

LESSONS_FILE="$REPO_PATH/.pitcrew-lessons"

# Create the file if it doesn't exist
if [ ! -f "$LESSONS_FILE" ]; then
  cat > "$LESSONS_FILE" << 'EOF'
# Pitcrew Lessons Learned
#
# Each lesson prevents the same mistake from happening again.
# Automatically injected into every mechanic's prompt.
#
# Format: LESSON: <what went wrong> → <what to do instead>
EOF
fi

# Append the lesson
echo "" >> "$LESSONS_FILE"
echo "LESSON: $LESSON" >> "$LESSONS_FILE"

echo "Added lesson to $LESSONS_FILE"
echo "  LESSON: $LESSON"
