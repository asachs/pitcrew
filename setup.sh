#!/usr/bin/env bash
# setup.sh — Install Pitcrew dependencies and configure for first use
#
# Usage: ./setup.sh [--pai]
#   --pai    Also install as a PAI/Claude Code skill

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

PITCREW_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_PAI=false
[ "${1:-}" = "--pai" ] && INSTALL_PAI=true

printf "\n${BOLD}Pitcrew Setup${RESET}\n\n"

PASS=0
FAIL=0
WARN=0

check() {
  local name="$1" status="$2" msg="$3"
  if [ "$status" = "ok" ]; then
    printf "  ${GREEN}✓${RESET}  %s — %s\n" "$name" "$msg"
    PASS=$((PASS + 1))
  elif [ "$status" = "warn" ]; then
    printf "  ${YELLOW}!${RESET}  %s — %s\n" "$name" "$msg"
    WARN=$((WARN + 1))
  else
    printf "  ${RED}✗${RESET}  %s — %s\n" "$name" "$msg"
    FAIL=$((FAIL + 1))
  fi
}

# ── Check core dependencies ──────────────────────────────────────────

printf "${DIM}Checking dependencies...${RESET}\n\n"

# bash
if bash --version >/dev/null 2>&1; then
  check "bash" "ok" "$(bash --version | head -1 | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+')"
else
  check "bash" "fail" "not found"
fi

# git (need 2.25+ for worktrees)
if command -v git >/dev/null 2>&1; then
  GIT_VER=$(git --version | grep -o '[0-9]\+\.[0-9]\+')
  GIT_MAJOR=$(echo "$GIT_VER" | cut -d. -f1)
  GIT_MINOR=$(echo "$GIT_VER" | cut -d. -f2)
  if [ "$GIT_MAJOR" -gt 2 ] || { [ "$GIT_MAJOR" -eq 2 ] && [ "$GIT_MINOR" -ge 25 ]; }; then
    check "git" "ok" "v$GIT_VER (worktree support)"
  else
    check "git" "fail" "v$GIT_VER — need 2.25+ for worktree support"
  fi
else
  check "git" "fail" "not found — install git 2.25+"
fi

# curl
if command -v curl >/dev/null 2>&1; then
  check "curl" "ok" "$(curl --version | head -1 | cut -d' ' -f1-2)"
else
  check "curl" "fail" "not found — required for mechanic-lite.sh"
fi

# jq
if command -v jq >/dev/null 2>&1; then
  check "jq" "ok" "$(jq --version 2>&1)"
else
  check "jq" "fail" "not found — install: brew install jq / apt install jq"
fi

# bd (beads CLI)
if command -v bd >/dev/null 2>&1; then
  check "bd" "ok" "$(bd --version 2>&1 | head -1)"
elif [ -f "$HOME/go/bin/bd" ]; then
  check "bd" "ok" "$($HOME/go/bin/bd --version 2>&1 | head -1) (at ~/go/bin/bd)"
else
  check "bd" "fail" "not found — install: go install github.com/steveyegge/beads/cmd/bd@latest"

  # Try to install if Go is available
  if command -v go >/dev/null 2>&1; then
    printf "\n  ${YELLOW}→${RESET} Go found. Installing bd...\n"
    if go install github.com/steveyegge/beads/cmd/bd@latest 2>/dev/null; then
      check "bd (auto-installed)" "ok" "$($HOME/go/bin/bd --version 2>&1 | head -1)"
      FAIL=$((FAIL - 1))  # undo the fail count
    else
      printf "    ${RED}Auto-install failed.${RESET} Download from https://github.com/steveyegge/beads/releases\n"
    fi
  fi
fi

# aider (optional)
if command -v aider >/dev/null 2>&1; then
  check "aider" "ok" "$(aider --version 2>&1 | head -1) (optional — for mechanic.sh)"
else
  check "aider" "warn" "not found (optional — only needed for mechanic.sh, not mechanic-lite.sh)"
fi

# ── Check API keys ───────────────────────────────────────────────────

printf "\n${DIM}Checking API keys...${RESET}\n\n"

if [ -n "${MINIMAX_API_KEY:-}" ]; then
  check "MINIMAX_API_KEY" "ok" "set (${#MINIMAX_API_KEY} chars)"
else
  check "MINIMAX_API_KEY" "fail" "not set — required for mechanics. Get one at https://platform.minimax.io"
fi

if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
  check "ANTHROPIC_API_KEY" "ok" "set (for pitstop-auto.sh crew chief)"
else
  check "ANTHROPIC_API_KEY" "warn" "not set (optional — only needed for pitstop-auto.sh)"
fi

# ── Create directories ───────────────────────────────────────────────

printf "\n${DIM}Setting up directories...${RESET}\n\n"

BAYS_DIR="${PITCREW_BAYS:-$HOME/bays}"
mkdir -p "$BAYS_DIR"
check "bays dir" "ok" "$BAYS_DIR"

# ── Make scripts executable ──────────────────────────────────────────

chmod +x "$PITCREW_DIR"/tools/*.sh 2>/dev/null || true
chmod +x "$PITCREW_DIR"/skill/Tools/*.sh 2>/dev/null || true
check "scripts" "ok" "executable"

# ── PAI skill installation ───────────────────────────────────────────

if [ "$INSTALL_PAI" = true ]; then
  printf "\n${DIM}Installing PAI skill...${RESET}\n\n"

  SKILL_DIR="${HOME}/.claude/skills/Pitcrew"
  mkdir -p "$SKILL_DIR/Tools" "$SKILL_DIR/Workflows"
  cp "$PITCREW_DIR/skill/SKILL.md" "$SKILL_DIR/"
  cp "$PITCREW_DIR/skill/Tools/"*.sh "$SKILL_DIR/Tools/"
  chmod +x "$SKILL_DIR/Tools/"*.sh
  check "PAI skill" "ok" "installed to $SKILL_DIR"
fi

# ── Summary ──────────────────────────────────────────────────────────

printf "\n"
if [ "$FAIL" -eq 0 ]; then
  printf "${GREEN}${BOLD}Ready!${RESET} ${PASS} checks passed"
  [ "$WARN" -gt 0 ] && printf ", ${YELLOW}${WARN} warnings${RESET}"
  printf "\n\n"
  printf "  ${DIM}Quick start:${RESET}\n"
  printf "  ${BOLD}%s/tools/pitstop-auto.sh /path/to/repo \"your task\"${RESET}\n" "$PITCREW_DIR"
  printf "\n"
else
  printf "${RED}${BOLD}${FAIL} check(s) failed.${RESET} Fix the issues above and re-run setup.sh\n\n"
  exit 1
fi
