#!/usr/bin/env bash
# Hirey Hi installer for Claude Code
#
# Drops three SKILL.md files into ~/.claude/skills/ and bootstraps an
# anonymous Hi agent identity at ~/.config/hi/credentials.json. After this
# runs, any Claude Code session can immediately use Hi via direct REST
# calls — no plugin install, no `/mcp` panel, no browser OAuth.
#
# Usage:
#   curl -sSL https://hi.hirey.ai/v1/install.sh | bash
#
# Env overrides:
#   HI_BASE          — Hi platform base URL (default: https://hi.hirey.ai)
#   SKILLS_REF       — git ref to pull SKILL.md from (default: master)
#   SKILLS_DIR       — install destination (default: ~/.claude/skills)
#   CREDS_DIR        — credentials destination (default: ~/.config/hi)
#   HI_CHANNEL_CODE  — referrer/invite code from a Hi owner page or invite link;
#                      stamped onto agents.metadata_json.channel_code so the
#                      admin panel can attribute this install to whoever sent
#                      the visitor here. Optional — empty registers anonymously.
#
# Idempotent: re-running is safe — overwrites skills with the latest
# pinned ref, keeps credentials file if it's valid (just refreshes token).

set -euo pipefail

VERSION="0.2.1"
HI_BASE="${HI_BASE:-https://hi.hirey.ai}"
SKILLS_DIR="${SKILLS_DIR:-$HOME/.claude/skills}"
CREDS_DIR="${CREDS_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/hi}"
CREDS_FILE="$CREDS_DIR/credentials.json"
SKILLS_REPO="hirey-ai/hirey-claude-plugin"
SKILLS_REF="${SKILLS_REF:-master}"
RAW_BASE="https://raw.githubusercontent.com/$SKILLS_REPO/$SKILLS_REF/plugins/hirey-hi"

CYAN='\033[1;36m'; GREEN='\033[1;32m'; RED='\033[1;31m'; DIM='\033[2m'; NC='\033[0m'

step() { printf "${CYAN}▶${NC} %s\n" "$1"; }
ok()   { printf "${GREEN}✓${NC} %s\n" "$1"; }
fail() { printf "${RED}✗${NC} %s\n" "$1" >&2; exit 1; }

# ─── Preflight ───────────────────────────────────────────────────────────
for bin in curl jq mkdir; do
  command -v "$bin" >/dev/null 2>&1 || fail "$bin not found in PATH. The Claude installer needs curl + jq.
   Install it, then re-run:
     macOS:          brew install $bin
     Debian/Ubuntu:  sudo apt-get install -y $bin
     Fedora/RHEL:    sudo dnf install -y $bin"
done

# ─── Host-mismatch self-check ────────────────────────────────────────────
# This script ONLY installs the Claude Code shape (SKILL.md drops into
# ~/.claude/skills/). It does NOT register a Hermes plugin, does NOT call
# the Codex marketplace, does NOT register an OpenClaw plugin. If an AI
# agent running inside Hermes / Codex / OpenClaw blindly curl-pipes this
# URL because `/v1/install.sh` *looks* generic (no `claude` in the path),
# the install used to silently succeed-ish: write files into ~/.claude/
# that the actual host can't see. The result was a "Hi seems installed
# but my agent has no hi_* tools" mystery for hours.
#
# Detect this: if the user's PATH has a non-Claude host binary AND has
# no `claude` binary, refuse + point at the matching host-specific install.
# `HI_FORCE_INSTALL=1` opts out for the rare user who deliberately wants
# the Claude shape inside another host (e.g. dual-installed environments).
if [[ "${HI_FORCE_INSTALL:-0}" != "1" ]] && ! command -v claude >/dev/null 2>&1; then
  if command -v hermes >/dev/null 2>&1; then
    fail "Hermes detected in PATH but no 'claude' binary — this is the Claude installer.
   Run instead:
     curl -fsSL https://hi.hirey.ai/v1/install/hermes.sh | bash
   Override with HI_FORCE_INSTALL=1 if you really want the Claude skill shape here."
  fi
  if command -v openclaw >/dev/null 2>&1; then
    fail "OpenClaw detected in PATH but no 'claude' binary — this is the Claude installer.
   Run instead:
     openclaw plugins install clawhub:hirey
   Override with HI_FORCE_INSTALL=1 if you really want the Claude skill shape here."
  fi
  if command -v codex >/dev/null 2>&1; then
    fail "Codex detected in PATH but no 'claude' binary — this is the Claude installer.
   Run instead:
     codex plugin marketplace add hirey-ai/hirey-codex-plugin
   Override with HI_FORCE_INSTALL=1 if you really want the Claude skill shape here."
  fi
fi

step "Installing Hirey Hi skill (v${VERSION}) from ${SKILLS_REPO}@${SKILLS_REF}"

# ─── 1. Drop skill markdown into ~/.claude/skills/ ───────────────────────
mkdir -p "$SKILLS_DIR"
for name in hi-onboard hi-use hi-events; do
  mkdir -p "$SKILLS_DIR/$name"
  curl -fsSL "$RAW_BASE/skills/$name/SKILL.md" -o "$SKILLS_DIR/$name/SKILL.md" \
    || fail "Failed to download $name SKILL.md"
done

# Reference doc that the skills link to (lazy-loaded by Claude).
mkdir -p "$SKILLS_DIR/hi-onboard/reference"
curl -fsSL "$RAW_BASE/reference/api.md" -o "$SKILLS_DIR/hi-onboard/reference/api.md" \
  || printf "${DIM}  (skipped optional reference doc — not fatal)${NC}\n"

ok "Skills installed at $SKILLS_DIR"
printf "    ${DIM}- hi-onboard, hi-use, hi-events${NC}\n"

# ─── 2. Bootstrap anonymous identity if not already set up ───────────────
step "Bootstrapping anonymous Hi identity"
mkdir -p "$CREDS_DIR" && chmod 700 "$CREDS_DIR"

if [ ! -f "$CREDS_FILE" ] || [ -z "$(jq -er '.client_id // empty' "$CREDS_FILE" 2>/dev/null)" ]; then
  # Build register body. If HI_CHANNEL_CODE is set, fold it into metadata for
  # owner-page / invite-link attribution. Empty env → no metadata field, register
  # stays fully anonymous like before. jq builds the JSON safely (no shell escaping bugs).
  REG_BODY=$(jq -n --arg channel "${HI_CHANNEL_CODE:-}" '
    {
      display_name: "Claude Code (Hirey skill)",
      agent_kind: "external"
    } + (if ($channel | length) > 0 then { metadata: { channel_code: $channel } } else {} end)
  ')
  REG=$(curl -fsS -X POST "$HI_BASE/v1/agents/register" \
    -H 'content-type: application/json' \
    --data "$REG_BODY") \
    || fail "Failed to register anonymous agent at $HI_BASE/v1/agents/register"

  printf '%s' "$REG" | jq --arg base "$HI_BASE" '{
    client_id:          .auth.client_id,
    client_secret:      .auth.client_secret,
    agent_id:           .agent.agent_id,
    installation_id:    .installation.installation_id,
    issuer:             .auth.issuer,
    audience:           .auth.audience,
    token_url:          .auth.token_url,
    platform_base_url:  $base,
    access_token:           null,
    access_token_issued_at: 0,
    access_token_expires_in: 0
  }' > "$CREDS_FILE"
  chmod 600 "$CREDS_FILE"
  ok "Anonymous agent registered: $(jq -r .agent_id "$CREDS_FILE")"
else
  ok "Existing credentials at $CREDS_FILE — keeping agent_id=$(jq -r .agent_id "$CREDS_FILE")"
fi

# ─── 3. Mint or refresh access token (5-min skew) ────────────────────────
NOW=$(date +%s)
ISSUED_AT=$(jq '.access_token_issued_at // 0' "$CREDS_FILE")
EXPIRES_IN=$(jq '.access_token_expires_in // 0' "$CREDS_FILE")
EXP_AT=$(( ISSUED_AT + EXPIRES_IN - 300 ))

if [ "$NOW" -ge "$EXP_AT" ]; then
  CID=$(jq -r .client_id "$CREDS_FILE")
  CSEC=$(jq -r .client_secret "$CREDS_FILE")
  AUD=$(jq -r .audience "$CREDS_FILE")
  TOK=$(curl -fsS -X POST "$HI_BASE/oauth/token" \
    --data "grant_type=client_credentials&client_id=$CID&client_secret=$CSEC&audience=$AUD") \
    || fail "Token endpoint unreachable"
  [ -n "$(printf '%s' "$TOK" | jq -r '.access_token // empty')" ] \
    || fail "Token endpoint returned no access_token: $TOK"
  jq --argjson tok "$TOK" --arg now "$NOW" '
    .access_token            = $tok.access_token
    | .access_token_issued_at  = ($now | tonumber)
    | .access_token_expires_in = $tok.expires_in
  ' "$CREDS_FILE" > "$CREDS_FILE.tmp" && mv "$CREDS_FILE.tmp" "$CREDS_FILE"
  ok "Access token refreshed (expires in $(jq -r .access_token_expires_in "$CREDS_FILE")s)"
else
  ok "Cached token still valid"
fi

# ─── 4. Activate install (idempotent — no-op if already active) ──────────
TOKEN=$(jq -r .access_token "$CREDS_FILE")
ACT=$(curl -fsS -X POST "$HI_BASE/v1/agents/activate" \
  -H "authorization: Bearer $TOKEN" -H 'content-type: application/json' --data '{}' 2>&1) \
  || fail "Activation failed: $ACT"

AGENT_ID=$(jq -r .agent_id "$CREDS_FILE")

# ─── 5. Done ─────────────────────────────────────────────────────────────
echo
printf "${GREEN}✓${NC} Hirey Hi is ready (agent_id=${GREEN}%s${NC})\n" "$AGENT_ID"
echo
echo "  Skills installed at: $SKILLS_DIR/hi-{onboard,use,events}/"
echo "  Credentials at:      $CREDS_FILE (mode 600)"
echo
echo "  Now ask Claude things like:"
echo "    \"find me 5 backend engineers in Tokyo\""
echo "    \"post a listing for a fintech cofounder\""
echo "    \"any replies to yesterday's pairings?\""
echo
printf "  ${DIM}Skills auto-load via live change detection — no restart needed.${NC}\n"
printf "  ${DIM}To uninstall: rm -rf $SKILLS_DIR/hi-{onboard,use,events} $CREDS_DIR${NC}\n"
