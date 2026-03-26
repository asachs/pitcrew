#!/usr/bin/env bash
# timing.sh — Pitcrew timing screen: show bead status, worker logs, cost tracking
#
# Usage: timing.sh [--verbose]

set -euo pipefail

BD="$HOME/go/bin/bd"
BEADS_DIR="$HOME/beads"
VERBOSE="${1:-}"

cd "$BEADS_DIR"

echo "╔══════════════════════════════════════════════════════════╗"
echo "║                 PIT CREW TIMING                          ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# Bead summary
OPEN=$($BD list --status open --format json 2>/dev/null | jq 'length' 2>/dev/null || echo 0)
IN_PROG=$($BD list --status in_progress --format json 2>/dev/null | jq 'length' 2>/dev/null || echo 0)
CLOSED=$($BD list --status closed --format json 2>/dev/null | jq 'length' 2>/dev/null || echo 0)
BLOCKED=$($BD list --status blocked --format json 2>/dev/null | jq 'length' 2>/dev/null || echo 0)

echo "  Beads:  ○ $OPEN open  ◐ $IN_PROG in_progress  ● $BLOCKED blocked  ✓ $CLOSED closed"
echo ""

# Active worktrees
echo "  Worktrees:"
if [ -d "$HOME/worktrees" ]; then
  for wt in "$HOME/worktrees"/beads-*/ 2>/dev/null; do
    [ -d "$wt" ] || continue
    BEAD=$(basename "$wt")
    BRANCH=$(cd "$wt" && git branch --show-current 2>/dev/null || echo "?")
    COMMITS=$(cd "$wt" && git log main..HEAD --oneline 2>/dev/null | wc -l || echo 0)
    echo "    $BEAD ($BRANCH) — $COMMITS commit(s)"
  done
else
  echo "    (none)"
fi
echo ""

# Token usage from worker logs
echo "  Token Usage (from worker logs):"
TOTAL_SENT=0
TOTAL_RECV=0
TOTAL_COST=0
for log in /tmp/worker-beads-*.log 2>/dev/null; do
  [ -f "$log" ] || continue
  BEAD=$(basename "$log" .log | sed 's/worker-//')
  TOKENS=$(grep -o "Tokens: [0-9.k]*k* sent, [0-9.k]*k* received" "$log" 2>/dev/null | tail -1 || true)
  if [ -n "$TOKENS" ]; then
    # Parse token counts (handle k suffix)
    SENT=$(echo "$TOKENS" | grep -o '[0-9.]*k* sent' | grep -o '[0-9.]*k*' | head -1)
    RECV=$(echo "$TOKENS" | grep -o '[0-9.]*k* received' | grep -o '[0-9.]*k*' | head -1)

    # Convert k to actual numbers
    SENT_NUM=$(echo "$SENT" | sed 's/k/*1000/' | bc 2>/dev/null || echo 0)
    RECV_NUM=$(echo "$RECV" | sed 's/k/*1000/' | bc 2>/dev/null || echo 0)

    # Cost estimate (MiniMax M2.5: $0.30/M input, $1.20/M output)
    COST=$(echo "scale=6; ($SENT_NUM * 0.00000030) + ($RECV_NUM * 0.00000120)" | bc 2>/dev/null || echo "?")

    echo "    $BEAD: ${SENT} in / ${RECV} out ≈ \$${COST}"

    TOTAL_SENT=$((TOTAL_SENT + ${SENT_NUM:-0}))
    TOTAL_RECV=$((TOTAL_RECV + ${RECV_NUM:-0}))
  fi
done

if [ "$TOTAL_SENT" -gt 0 ] 2>/dev/null; then
  TOTAL_COST=$(echo "scale=4; ($TOTAL_SENT * 0.00000030) + ($TOTAL_RECV * 0.00000120)" | bc 2>/dev/null || echo "?")
  echo ""
  echo "    Total: ${TOTAL_SENT} in / ${TOTAL_RECV} out ≈ \$${TOTAL_COST}"
fi
echo ""

# Recent bead activity
if [ "$VERBOSE" = "--verbose" ]; then
  echo "  Recent Beads:"
  $BD list 2>&1 | head -20
  echo ""
fi

# Cache stats from API responses
echo "  Cache: MiniMax auto-caches shared prefixes."
echo "         Repeated context (repo maps) should hit cache at \$0.03/M vs \$0.30/M."
echo ""
