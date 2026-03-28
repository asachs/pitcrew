#!/usr/bin/env bash
# release.sh — Merge a completed worker's worktree into main
# Handles conflict escalation: clean → auto-merge, text conflict → retry with model,
# semantic conflict → create escalation bead for PAI/Opus
#
# Usage: release.sh <bead-id> <repo-path>

set -euo pipefail

BEAD_ID="${1:?Usage: release.sh <bead-id> <repo-path>}"
REPO_PATH="${2:?Usage: release.sh <bead-id> <repo-path>}"

BD="${PITCREW_BD:-$(command -v bd 2>/dev/null || echo "$HOME/go/bin/bd")}"
if [ -d "$REPO_PATH/.beads" ]; then BEADS_DIR="$REPO_PATH"; else BEADS_DIR="${PITCREW_LANE:-$REPO_PATH}"; fi
BAYS_DIR="${PITCREW_BAYS:-$HOME/bays}"
WORKTREE="$BAYS_DIR/$BEAD_ID"
BRANCH="worker/$BEAD_ID"

echo "═══ Release: $BEAD_ID ═══"

# ── Verify worktree exists and has commits ─────────────────────────
if [ ! -d "$WORKTREE" ]; then
  echo "ERROR: Worktree not found at $WORKTREE"
  exit 1
fi

cd "$WORKTREE"
COMMIT_COUNT=$(git log main.."$BRANCH" --oneline 2>/dev/null | wc -l)
if [ "$COMMIT_COUNT" -eq 0 ]; then
  echo "No commits to merge. Cleaning up."
  cd "$REPO_PATH"
  git worktree remove "$WORKTREE" --force 2>/dev/null || true
  git branch -D "$BRANCH" 2>/dev/null || true
  exit 0
fi

echo "Merging $COMMIT_COUNT commit(s) from $BRANCH..."

# ── Scrutineering: run verification before merge ───────────────────
# If the project has a .pitcrew-verify script, run it in the worktree.
# Fails here = mechanic's work doesn't pass checks = don't merge.
if [ -f "$REPO_PATH/.pitcrew-verify" ]; then
  echo "Running scrutineering (.pitcrew-verify)..."
  cd "$WORKTREE"
  if bash "$REPO_PATH/.pitcrew-verify" 2>&1; then
    echo "✓ Scrutineering passed"
  else
    echo "✗ RED FLAG: Scrutineering failed — mechanic's work doesn't pass verification"
    echo "  Log: run 'cd $WORKTREE && bash $REPO_PATH/.pitcrew-verify' to see failures"

    # Create escalation bead — don't merge broken code
    cd "${PITCREW_LANE:-$HOME/pitlane}"
    ORIGINAL_TITLE=$($BD show "$BEAD_ID" --format json 2>/dev/null | jq -r '.[0].title // .title // "unknown"')
    $BD create \
      --title "FAILED SCRUTINEERING: $BEAD_ID ($ORIGINAL_TITLE)" \
      --body "Mechanic's work in branch $BRANCH failed verification. Worktree: $WORKTREE. Re-dispatch or fix manually." \
      --label "escalation" \
      --label "verification-failed" \
      2>/dev/null || true

    exit 2
  fi
fi

# ── Tier 0: Try clean merge (fast-forward or no-conflict) ─────────
cd "$REPO_PATH"
git checkout main 2>/dev/null

# Try fast-forward first (cleanest path)
if git merge --ff-only "$BRANCH" 2>/dev/null; then
  echo "✓ Green flag: fast-forward merge"
  git worktree remove "$WORKTREE" --force 2>/dev/null || true
  git branch -D "$BRANCH" 2>/dev/null || true
  exit 0
fi

# Try regular merge
if git merge --no-commit "$BRANCH" 2>/dev/null; then
  git commit -m "Merge $BRANCH: $(git log -1 --format='%s' "$BRANCH")"
  echo "✓ Green flag: clean merge"
  git worktree remove "$WORKTREE" --force 2>/dev/null || true
  git branch -D "$BRANCH" 2>/dev/null || true
  exit 0
fi

# ── Tier 1: Text-only conflict — try rebase ────────────────────────
echo "Conflict detected. Trying rebase..."
git merge --abort 2>/dev/null || true

cd "$WORKTREE"
if git rebase main 2>/dev/null; then
  cd "$REPO_PATH"
  git merge --ff-only "$BRANCH" 2>/dev/null && {
    echo "✓ Yellow flag: resolved via rebase"
    git worktree remove "$WORKTREE" --force 2>/dev/null || true
    git branch -D "$BRANCH" 2>/dev/null || true
    exit 0
  }
fi

# Rebase failed, abort it
cd "$WORKTREE"
git rebase --abort 2>/dev/null || true

# ── Tier 2: Semantic conflict — escalate to PAI ───────────────────
echo "✗ Red flag: radioing crew chief for resolution"

# Get the conflict details
cd "$REPO_PATH"
DIFF_MAIN=$(git diff main.."$BRANCH" --stat 2>/dev/null)
CONFLICT_FILES=$(git merge --no-commit "$BRANCH" 2>&1 | grep "CONFLICT" || true)
git merge --abort 2>/dev/null || true

# Get the original task
cd "$BEADS_DIR"
ORIGINAL_TITLE=$($BD show "$BEAD_ID" --format json 2>/dev/null | jq -r '.title // "unknown"')

# Create escalation bead
ESCALATION_BODY="## Merge Conflict Escalation

**Original task:** $BEAD_ID — $ORIGINAL_TITLE
**Branch:** $BRANCH
**Worktree:** $WORKTREE

### Conflicts
\`\`\`
$CONFLICT_FILES
\`\`\`

### Changes in worker branch
\`\`\`
$DIFF_MAIN
\`\`\`

### Resolution needed
Review both the main branch and worker branch changes. Resolve the conflict
by either:
1. Manually merging in the worktree and committing
2. Rebasing the worker branch with conflict resolution
3. Rejecting the worker's changes if they're incompatible

After resolving, run:
  cd $REPO_PATH && git merge $BRANCH
  release.sh $BEAD_ID $REPO_PATH  # to cleanup
"

$BD create \
  --title "ESCALATION: Merge conflict for $BEAD_ID ($ORIGINAL_TITLE)" \
  --body "$ESCALATION_BODY" \
  --label "escalation" \
  --label "conflict" \
  --label "tier-2" \
  2>/dev/null || echo "WARNING: Could not create escalation bead"

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  ESCALATION: Merge conflict needs PAI/Opus resolution   ║"
echo "║  Branch: $BRANCH"
echo "║  Worktree: $WORKTREE"
echo "║  Conflicts: $CONFLICT_FILES"
echo "╚══════════════════════════════════════════════════════════╝"

exit 2  # Exit code 2 = escalation needed
