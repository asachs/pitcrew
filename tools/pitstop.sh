#!/run/current-system/sw/bin/bash
# pitstop.sh — Run a full pit stop with live visibility
#
# Usage: pitstop.sh <repo-path> <bead-id> [<bead-id> ...]
#
# Dispatches mechanics, shows live progress, releases on completion.
# This is the "one command" entry point for Pitcrew.

set -euo pipefail

REPO_PATH="${1:?Usage: pitstop.sh <repo-path> <bead-id> [<bead-id> ...]}"
shift
BEADS=("$@")

if [ ${#BEADS[@]} -eq 0 ]; then
  echo "No beads specified"
  exit 1
fi

BD="${PITCREW_BD:-$(command -v bd 2>/dev/null || echo "$HOME/go/bin/bd")}"
BAYS="${PITCREW_BAYS:-$HOME/bays}"
MODEL="${PITCREW_MODEL:-openai/MiniMax-M2.5}"
TIMEOUT="${PITCREW_TIMEOUT:-300}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Colours
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

divider() {
  printf "${DIM}────────────────────────────────────────────────────${RESET}\n"
}

# ── Header ─────────────────────────────────────────────────────────
clear 2>/dev/null || true
printf "\n"
printf "  ${BOLD}🏁 PITCREW${RESET}  ${DIM}— Parallel AI Coding, F1 Style${RESET}\n"
printf "  ${DIM}Repo: ${REPO_PATH}${RESET}\n"
printf "  ${DIM}Model: ${MODEL}${RESET}\n"
printf "  ${DIM}Mechanics: ${#BEADS[@]}${RESET}\n"
printf "\n"
divider

# ── Show pit calls ─────────────────────────────────────────────────
printf "\n  ${BOLD}PIT CALLS${RESET}\n\n"
declare -A BEAD_TITLES
for BEAD in "${BEADS[@]}"; do
  TITLE=$(cd "${PITCREW_LANE:-$HOME/pitlane}" && $BD show "$BEAD" --format json 2>/dev/null | jq -r '.[0].title // .title // "?"' 2>/dev/null || echo "?")
  BEAD_TITLES[$BEAD]="$TITLE"
  printf "  ${CYAN}○${RESET}  ${BOLD}%s${RESET}  %s\n" "$BEAD" "$TITLE"
done
printf "\n"
divider

# ── Dispatch ───────────────────────────────────────────────────────
printf "\n  ${BOLD}BOX BOX${RESET} — Dispatching mechanics...\n\n"

declare -A PIDS
declare -A START_TIMES

for BEAD in "${BEADS[@]}"; do
  START_TIMES[$BEAD]=$(date +%s)
  # Use mechanic-lite (no Aider dependency) if available, fall back to mechanic.sh
  MECHANIC="$SCRIPT_DIR/mechanic-lite.sh"
  [ ! -f "$MECHANIC" ] && MECHANIC="$SCRIPT_DIR/mechanic.sh"
  "$MECHANIC" "$BEAD" "$REPO_PATH" "$MODEL" "$TIMEOUT" > "/tmp/pitcrew-$BEAD.log" 2>&1 &
  PIDS[$BEAD]=$!
  printf "  ${YELLOW}◐${RESET}  ${BOLD}%s${RESET}  dispatched (PID %s)\n" "$BEAD" "${PIDS[$BEAD]}"
done

printf "\n"
divider

# ── Monitor ────────────────────────────────────────────────────────
printf "\n  ${BOLD}TIMING SCREEN${RESET}\n\n"

COMPLETED=0
FAILED=0
TOTAL=${#BEADS[@]}

while [ $((COMPLETED + FAILED)) -lt "$TOTAL" ]; do
  sleep 3

  for BEAD in "${BEADS[@]}"; do
    PID="${PIDS[$BEAD]:-}"
    [ -z "$PID" ] && continue

    if ! kill -0 "$PID" 2>/dev/null; then
      # Process finished
      wait "$PID" 2>/dev/null
      EXIT=$?
      ELAPSED=$(( $(date +%s) - ${START_TIMES[$BEAD]} ))

      # Get token usage from log
      TOKENS=$(grep -o "Tokens: [0-9.k]* sent, [0-9.k]* received" "/tmp/pitcrew-$BEAD.log" 2>/dev/null | tail -1 || echo "")

      if [ $EXIT -eq 0 ]; then
        CHANGES=$(tail -5 "/tmp/pitcrew-$BEAD.log" | grep -o "[0-9]* file(s) changed" || echo "no changes")
        printf "  ${GREEN}✓${RESET}  ${BOLD}%s${RESET}  done in %ds — %s" "$BEAD" "$ELAPSED" "$CHANGES"
        [ -n "$TOKENS" ] && printf " ${DIM}(%s)${RESET}" "$TOKENS"
        printf "\n"
        COMPLETED=$((COMPLETED + 1))
      else
        printf "  ${RED}✗${RESET}  ${BOLD}%s${RESET}  failed in %ds (exit %d)\n" "$BEAD" "$ELAPSED" "$EXIT"
        FAILED=$((FAILED + 1))
      fi

      unset "PIDS[$BEAD]"
    fi
  done
done

printf "\n"
divider

# ── Release ────────────────────────────────────────────────────────
printf "\n  ${BOLD}RELEASE${RESET} — Merging bays to main...\n\n"

MERGED=0
ESCALATED=0

for BEAD in "${BEADS[@]}"; do
  # Skip failed beads
  if [ ! -d "$BAYS/$BEAD" ]; then
    continue
  fi

  "$SCRIPT_DIR/release.sh" "$BEAD" "$REPO_PATH" > "/tmp/pitcrew-release-$BEAD.log" 2>&1
  EXIT=$?

  if [ $EXIT -eq 0 ]; then
    FLAG=$(grep -o "Green flag\|Yellow flag" "/tmp/pitcrew-release-$BEAD.log" || echo "merged")
    printf "  ${GREEN}🟢${RESET}  ${BOLD}%s${RESET}  %s\n" "$BEAD" "$FLAG"
    MERGED=$((MERGED + 1))
  elif [ $EXIT -eq 2 ]; then
    printf "  ${RED}🔴${RESET}  ${BOLD}%s${RESET}  escalated to crew chief\n" "$BEAD"
    ESCALATED=$((ESCALATED + 1))
  else
    printf "  ${YELLOW}⚠${RESET}   ${BOLD}%s${RESET}  release error (see /tmp/pitcrew-release-%s.log)\n" "$BEAD" "$BEAD"
  fi
done

printf "\n"
divider

# ── Summary ────────────────────────────────────────────────────────
TOTAL_ELAPSED=$(( $(date +%s) - ${START_TIMES[${BEADS[0]}]} ))

# Calculate total cost from logs
TOTAL_SENT=0
TOTAL_RECV=0
for BEAD in "${BEADS[@]}"; do
  SENT=$(grep -o "[0-9.]*k sent" "/tmp/pitcrew-$BEAD.log" 2>/dev/null | grep -o "[0-9.]*" | head -1 || echo 0)
  RECV=$(grep -o "[0-9.]*k received" "/tmp/pitcrew-$BEAD.log" 2>/dev/null | grep -o "[0-9.]*" | head -1 || echo 0)
  TOTAL_SENT=$(echo "$TOTAL_SENT + ${SENT:-0}" | bc 2>/dev/null || echo 0)
  TOTAL_RECV=$(echo "$TOTAL_RECV + ${RECV:-0}" | bc 2>/dev/null || echo 0)
done
COST=$(echo "scale=4; ($TOTAL_SENT * 0.30 + $TOTAL_RECV * 1.20) / 1000" | bc 2>/dev/null || echo "?")

printf "\n"
printf "  ${BOLD}PIT STOP COMPLETE${RESET}\n\n"
printf "  Mechanics:   %d dispatched, ${GREEN}%d merged${RESET}, ${RED}%d failed${RESET}, ${YELLOW}%d escalated${RESET}\n" "$TOTAL" "$MERGED" "$FAILED" "$ESCALATED"
printf "  Time:        %ds total\n" "$TOTAL_ELAPSED"
printf "  Tokens:      %.1fk sent, %.1fk received\n" "$TOTAL_SENT" "$TOTAL_RECV"
printf "  Est. cost:   \$%s\n" "$COST"
printf "\n"
