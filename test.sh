#!/usr/bin/env bash
# test.sh — End-to-end smoke test for Pitcrew
#
# Creates a throwaway repo, runs a full pitstop cycle, verifies output,
# cleans up. Exit 0 = pass, exit 1 = fail.
#
# Usage: ./test.sh
#
# Requires: MINIMAX_API_KEY set, bd on PATH or at ~/go/bin/bd

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

PITCREW_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_DIR=$(mktemp -d "/tmp/pitcrew-test-XXXXXX")
BD="${PITCREW_BD:-$(command -v bd 2>/dev/null || echo "$HOME/go/bin/bd")}"
PASS=0
FAIL=0

cleanup() {
  # Clean up worktrees, test dir, logs
  cd "$TEST_DIR" 2>/dev/null && git worktree prune 2>/dev/null || true
  rm -rf "$TEST_DIR"
  rm -rf "${PITCREW_BAYS:-$HOME/bays}"/pitcrew-smoke-* 2>/dev/null || true
  rm -f /tmp/pitcrew-pitcrew-smoke-*.log 2>/dev/null || true
  rm -f /tmp/pitcrew-release-pitcrew-smoke-*.log 2>/dev/null || true
}
trap cleanup EXIT

assert() {
  local name="$1" condition="$2"
  if eval "$condition"; then
    printf "  ${GREEN}✓${RESET}  %s\n" "$name"
    PASS=$((PASS + 1))
  else
    printf "  ${RED}✗${RESET}  %s\n" "$name"
    FAIL=$((FAIL + 1))
  fi
}

printf "\n${BOLD}Pitcrew Smoke Test${RESET}\n"
printf "${DIM}Test repo: %s${RESET}\n\n" "$TEST_DIR"

# ── Preflight ─────────────────────────────────────────────────────────

printf "${DIM}Preflight checks...${RESET}\n\n"

assert "bd binary exists" "[ -x \"\$BD\" ] || command -v bd >/dev/null 2>&1"
assert "MINIMAX_API_KEY set" "[ -n \"\${MINIMAX_API_KEY:-}\" ]"
assert "git available" "command -v git >/dev/null 2>&1"
assert "curl available" "command -v curl >/dev/null 2>&1"
assert "jq available" "command -v jq >/dev/null 2>&1"

if [ "$FAIL" -gt 0 ]; then
  printf "\n${RED}Preflight failed. Fix dependencies and retry.${RESET}\n\n"
  exit 1
fi

# ── Create test repo ──────────────────────────────────────────────────

printf "\n${DIM}Creating test repo...${RESET}\n\n"

cd "$TEST_DIR"
git init -b main >/dev/null 2>&1
git config user.email "test@pitcrew.dev"
git config user.name "Pitcrew Test"

mkdir -p src

cat > src/alpha.ts << 'EOF'
export function greet(name: string): string {
  return "hello " + name;
}
EOF

cat > src/beta.ts << 'EOF'
export function farewell(name: string): string {
  return "goodbye " + name;
}
EOF

git add -A && git commit -m "Initial: two files" >/dev/null 2>&1
assert "test repo created" "[ -d .git ]"

# ── Init beads ────────────────────────────────────────────────────────

$BD init --quiet 2>/dev/null || true
assert "beads initialized" "[ -d .beads ]"

# ── Create beads ──────────────────────────────────────────────────────

printf "\n${DIM}Creating beads...${RESET}\n\n"

# bd create outputs: "✓ Created issue: {id} — {title}"
# Extract the ID from that line
B1_OUT=$($BD create --title "Add JSDoc to greet function" \
  --body "Add a JSDoc comment above the greet function in src/alpha.ts describing what it does. Keep the function unchanged." \
  --label "file:src/alpha.ts" 2>&1)
B1=$(echo "$B1_OUT" | grep "Created issue:" | sed 's/.*Created issue: //' | cut -d' ' -f1)

B2_OUT=$($BD create --title "Add JSDoc to farewell function" \
  --body "Add a JSDoc comment above the farewell function in src/beta.ts describing what it does. Keep the function unchanged." \
  --label "file:src/beta.ts" 2>&1)
B2=$(echo "$B2_OUT" | grep "Created issue:" | sed 's/.*Created issue: //' | cut -d' ' -f1)

assert "bead 1 created" "[ -n \"$B1\" ]"
assert "bead 2 created" "[ -n \"$B2\" ]"

if [ -z "$B1" ] || [ -z "$B2" ]; then
  printf "\n${RED}Could not create beads. Aborting.${RESET}\n\n"
  exit 1
fi

printf "  ${DIM}Bead 1: %s${RESET}\n" "$B1"
printf "  ${DIM}Bead 2: %s${RESET}\n" "$B2"

# ── Run pitstop ───────────────────────────────────────────────────────

printf "\n${DIM}Running pitstop (2 parallel mechanics)...${RESET}\n\n"

START=$(date +%s)
"$PITCREW_DIR/tools/pitstop.sh" "$TEST_DIR" "$B1" "$B2" 2>&1 | tail -20
END=$(date +%s)
ELAPSED=$((END - START))

printf "\n"
assert "pitstop completed" "true"  # if we got here, it didn't crash
assert "completed in <60s" "[ $ELAPSED -lt 60 ]"

# ── Verify results ────────────────────────────────────────────────────

printf "\n${DIM}Verifying results...${RESET}\n\n"

# Check mechanic logs exist and have content
assert "mechanic 1 log has content" "[ -s /tmp/pitcrew-$B1.log ]"
assert "mechanic 2 log has content" "[ -s /tmp/pitcrew-$B2.log ]"

# Check that mechanics reported success
assert "mechanic 1 succeeded" "grep -q 'Mechanic done' /tmp/pitcrew-$B1.log 2>/dev/null"
assert "mechanic 2 succeeded" "grep -q 'Mechanic done' /tmp/pitcrew-$B2.log 2>/dev/null"

# Check files were actually modified (either on main or in worktrees)
cd "$TEST_DIR"
ALPHA_CHANGED=false
BETA_CHANGED=false

# Check main branch
if grep -q 'JSDoc\|@param\|@returns\|\*\*\|/\*\*' src/alpha.ts 2>/dev/null; then
  ALPHA_CHANGED=true
fi
if grep -q 'JSDoc\|@param\|@returns\|\*\*\|/\*\*' src/beta.ts 2>/dev/null; then
  BETA_CHANGED=true
fi

# If not on main, check worktrees
if [ "$ALPHA_CHANGED" = false ]; then
  BAYS_DIR="${PITCREW_BAYS:-$HOME/bays}"
  for bay in "$BAYS_DIR"/$B1 "$BAYS_DIR"/$B2; do
    [ -d "$bay" ] && grep -q 'JSDoc\|@param\|@returns\|\*\*\|/\*\*' "$bay/src/alpha.ts" 2>/dev/null && ALPHA_CHANGED=true
  done
fi
if [ "$BETA_CHANGED" = false ]; then
  BAYS_DIR="${PITCREW_BAYS:-$HOME/bays}"
  for bay in "$BAYS_DIR"/$B1 "$BAYS_DIR"/$B2; do
    [ -d "$bay" ] && grep -q 'JSDoc\|@param\|@returns\|\*\*\|/\*\*' "$bay/src/beta.ts" 2>/dev/null && BETA_CHANGED=true
  done
fi

assert "alpha.ts was modified (JSDoc added)" "$ALPHA_CHANGED"
assert "beta.ts was modified (JSDoc added)" "$BETA_CHANGED"

# Check no think tags leaked
assert "no <think> tags in alpha.ts" "! grep -q '<think>' src/alpha.ts 2>/dev/null"
assert "no <think> tags in beta.ts" "! grep -q '<think>' src/beta.ts 2>/dev/null"

# Check beads were closed
OPEN_COUNT=$($BD list --status open --format json 2>/dev/null | jq 'length' 2>/dev/null || echo "?")
assert "all beads closed" "[ \"$OPEN_COUNT\" = \"0\" ]"

# ── Summary ───────────────────────────────────────────────────────────

printf "\n"
if [ "$FAIL" -eq 0 ]; then
  printf "${GREEN}${BOLD}ALL %d TESTS PASSED${RESET} in %ds\n\n" "$PASS" "$ELAPSED"
  exit 0
else
  printf "${RED}${BOLD}%d FAILED${RESET}, ${GREEN}%d passed${RESET} in %ds\n\n" "$FAIL" "$PASS" "$ELAPSED"
  printf "${DIM}Test repo preserved at: %s${RESET}\n" "$TEST_DIR"
  trap - EXIT  # don't clean up on failure
  exit 1
fi
