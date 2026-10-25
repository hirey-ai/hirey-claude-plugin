#!/usr/bin/env bash
# Hirey Hi installer for Claude Code
#
# Installs the hirey-hi plugin from this marketplace with Claude Code's own
# plugin manager. The plugin connects Claude to HiRey's hosted MCP endpoint
# (https://mcp.hirey.ai/mcp) and ships the Hi skills; you sign in once with
# OAuth. Nothing else is written to your machine.
#
# Usage:
#   curl -fsSL --connect-timeout 5 --max-time 30 https://hi.hirey.ai/v1/install/claude.sh | bash
#
# Env overrides:
#   MARKETPLACE_SOURCE — marketplace to add (default: hirey-ai/hirey-claude-plugin)
#   SKILLS_DIR         — where the earlier REST installer put its skills
#                        (default: ~/.claude/skills)
#
# Idempotent: re-running updates the marketplace and the plugin.
#
# Moving from the earlier REST installer (0.2.x): its four skills in
# ~/.claude/skills/hi-{onboard,use,events,repair} would load beside the
# plugin's and give Claude the old REST instructions, so they are moved to
# ~/.claude/skills/.hirey-legacy-<time>/ (nothing is deleted). Its identity
# file ~/.config/hi/credentials.json is left as it is; the plugin does not use it.

set -euo pipefail
umask 077

VERSION="0.3.4"
MARKETPLACE_SOURCE="${MARKETPLACE_SOURCE:-hirey-ai/hirey-claude-plugin}"
MARKETPLACE_NAME="hirey"
PLUGIN="hirey-hi@$MARKETPLACE_NAME"
SKILLS_DIR="${SKILLS_DIR:-$HOME/.claude/skills}"

CYAN='\033[1;36m'; GREEN='\033[1;32m'; RED='\033[1;31m'; DIM='\033[2m'; NC='\033[0m'

step() { printf "${CYAN}▶${NC} %s\n" "$1"; }
ok()   { printf "${GREEN}✓${NC} %s\n" "$1"; }
fail() { printf "${RED}✗${NC} %s\n" "$1" >&2; exit 1; }

# ─── Host check ──────────────────────────────────────────────────────────
# This installs the Claude Code plugin only. An agent running inside another
# host that curl-pipes this URL gets pointed at its own installer instead of
# a "Hi seems installed but my agent has no hi tools" mystery.
if ! command -v claude >/dev/null 2>&1; then
  if command -v hermes >/dev/null 2>&1; then
    fail "Hermes detected in PATH but no 'claude' binary — this is the Claude installer.
   Run instead:
     curl -fsSL --connect-timeout 5 --max-time 30 https://hi.hirey.ai/v1/install/hermes.sh | bash"
  fi
  if command -v openclaw >/dev/null 2>&1; then
    fail "OpenClaw detected in PATH but no 'claude' binary — this is the Claude installer.
   Run instead:
     openclaw plugins install clawhub:hirey"
  fi
  if command -v codex >/dev/null 2>&1; then
    fail "Codex detected in PATH but no 'claude' binary — this is the Claude installer.
   Run instead:
     codex plugin marketplace add hirey-ai/hirey-codex-plugin && codex plugin add hirey-hi@hirey"
  fi
  fail "Claude Code ('claude') not found in PATH. Install Claude Code first: https://code.claude.com
   In the Claude desktop app, claude.ai or on your phone, add HiRey as a connector instead:
     Settings → Connectors → Add custom connector → https://mcp.hirey.ai/mcp"
fi

step "Installing Hirey Hi plugin (v${VERSION}) from ${MARKETPLACE_SOURCE}"

# ─── 1. Marketplace and plugin ───────────────────────────────────────────
if claude plugin marketplace list 2>/dev/null | grep -q "❯ $MARKETPLACE_NAME\$"; then
  claude plugin marketplace update "$MARKETPLACE_NAME" || fail "Could not update the $MARKETPLACE_NAME marketplace"
else
  claude plugin marketplace add "$MARKETPLACE_SOURCE" || fail "Could not add the $MARKETPLACE_SOURCE marketplace"
fi
if claude plugin list 2>/dev/null | grep -q "❯ $PLUGIN\$"; then
  claude plugin update "$PLUGIN" || fail "Could not update $PLUGIN"
else
  claude plugin install "$PLUGIN" || fail "Could not install $PLUGIN"
fi
# Claude Code may install a third-party plugin disabled; `enable` fails on an
# already enabled plugin, so read the status first.
plugin_status() {
  claude plugin list 2>/dev/null | awk -v p="❯ $PLUGIN" '$0 ~ p"$" {found=1; next} found && /Status:/ {print; exit}'
}
if ! plugin_status | grep -q " enabled"; then
  claude plugin enable "$PLUGIN" || fail "Could not enable $PLUGIN"
fi
plugin_status | grep -q " enabled" \
  || fail "$PLUGIN is installed but not enabled; run: claude plugin enable $PLUGIN"
ok "Plugin $PLUGIN installed and enabled"

# ─── 2. Move the earlier REST installer's skills aside ──────────────────
# Only after the plugin is in place, so a failed install leaves them working.
LEGACY=""
for name in hi-onboard hi-use hi-events hi-repair; do
  if [ -f "$SKILLS_DIR/$name/SKILL.md" ] && grep -q "hi.hirey.ai" "$SKILLS_DIR/$name/SKILL.md"; then
    if [ -z "$LEGACY" ]; then
      LEGACY="$SKILLS_DIR/.hirey-legacy-$(date +%Y%m%d%H%M%S)"
      mkdir -p "$LEGACY"
    fi
    mv "$SKILLS_DIR/$name" "$LEGACY/$name"
  fi
done
[ -z "$LEGACY" ] || ok "Earlier REST skills moved to $LEGACY"

# ─── 3. Done ─────────────────────────────────────────────────────────────
echo
echo "  Next, sign in to HiRey once (opens your browser):"
echo "      claude mcp login plugin:hirey-hi:hi"
echo "  or run /mcp inside Claude Code. Then restart Claude Code."
echo
echo "  Then ask Claude things like:"
echo "    \"who did I meet this week?\""
echo "    \"build Pages for the people I met at the conference\""
echo "    \"any replies?\""
echo
printf "  ${DIM}To uninstall: claude plugin uninstall %s${NC}\n" "$PLUGIN"
