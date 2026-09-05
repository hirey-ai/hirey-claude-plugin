#!/usr/bin/env bash
# Hirey Hi installer for Claude Code
#
# Drops four SKILL.md files into ~/.claude/skills/ and bootstraps an
# anonymous Hi agent identity at ~/.config/hi/credentials.json. After this
# runs, any Claude Code session can immediately use Hi via direct REST
# calls — no plugin install, no `/mcp` panel, no browser OAuth.
#
# Usage:
#   curl -fsSL --connect-timeout 5 --max-time 30 https://hi.hirey.ai/v1/install/claude.sh | bash
#
# Env overrides:
#   HI_BASE          — Hi platform base URL (default: https://hi.hirey.ai)
#   SKILLS_REF       — git ref to pull SKILL.md from (default: master)
#   SKILLS_DIR       — install destination (default: ~/.claude/skills)
#   CREDS_DIR        — credentials destination (default: ~/.config/hi)
#   HI_CHANNEL_CODE  — unsupported by the current API; a supplied value stops
#                      fresh registration instead of silently losing attribution.
#
# Idempotent: re-running is safe — overwrites skills with the latest
# pinned ref, keeps credentials file if it's valid (just refreshes token).

set -euo pipefail
# Credential and temporary files must never be readable by other users.
umask 077

VERSION="0.2.6"
HI_BASE_EXPLICIT="${HI_BASE+x}"
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
     curl -fsSL --connect-timeout 5 --max-time 30 https://hi.hirey.ai/v1/install/hermes.sh | bash
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
STAGE_DIR=$(mktemp -d "$SKILLS_DIR/.hirey-stage.XXXXXX")
CRED_TMP=""
LOCK_OWNED=0
cleanup() {
  [ -z "$CRED_TMP" ] || rm -f "$CRED_TMP"
  rm -rf "$STAGE_DIR"
  if [ "$LOCK_OWNED" = 1 ]; then rmdir "$LOCK_DIR" 2>/dev/null || true; fi
}
trap cleanup EXIT
for name in hi-onboard hi-use hi-events hi-repair; do
  mkdir -p "$STAGE_DIR/$name"
  curl -fsSL --connect-timeout 5 --max-time 30 "$RAW_BASE/skills/$name/SKILL.md" -o "$STAGE_DIR/$name/SKILL.md" \
    || fail "Failed to download $name SKILL.md"
done

# Reference doc that the skills link to (lazy-loaded by Claude).
mkdir -p "$STAGE_DIR/hi-onboard/reference"
curl -fsSL --connect-timeout 5 --max-time 30 "$RAW_BASE/reference/api.md" -o "$STAGE_DIR/hi-onboard/reference/api.md" \
  || fail "Failed to download reference doc; installed skills unchanged"

# Download every file before replacing any installed skill.
for name in hi-onboard hi-use hi-events hi-repair; do
  mkdir -p "$SKILLS_DIR/$name"
  mv "$STAGE_DIR/$name/SKILL.md" "$SKILLS_DIR/$name/SKILL.md"
done
mkdir -p "$SKILLS_DIR/hi-onboard/reference"
mv "$STAGE_DIR/hi-onboard/reference/api.md" "$SKILLS_DIR/hi-onboard/reference/api.md"

ok "Skills installed at $SKILLS_DIR"
printf "    ${DIM}- hi-onboard, hi-use, hi-events, hi-repair${NC}\n"

# ─── 2. Bootstrap anonymous identity if not already set up ───────────────
step "Bootstrapping anonymous Hi identity"
mkdir -p "$CREDS_DIR" && chmod 700 "$CREDS_DIR"
LOCK_DIR="$CREDS_DIR/.register.lock"
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if mkdir "$LOCK_DIR" 2>/dev/null; then LOCK_OWNED=1; break; fi
  sleep 1
done
[ "$LOCK_OWNED" = 1 ] || fail "hi_register_busy: installation or token refresh is already running"
# Keep the same lock through credential re-read and token refresh: refreshing a
# pending token invalidates the previous bearer for this shared installation.
HI_BASE="${HI_BASE%/}"
if [ -s "$CREDS_FILE" ]; then
  STORED_BASE=$(jq -er '.platform_base_url // empty | select(type == "string" and length > 0)' "$CREDS_FILE" 2>/dev/null || true)
  if [ -n "$STORED_BASE" ]; then
    STORED_BASE="${STORED_BASE%/}"
    if [ -n "$HI_BASE_EXPLICIT" ] && [ "$HI_BASE" != "$STORED_BASE" ]; then
      fail "hi_credential_host_mismatch: explicit HI_BASE differs from stored credential host; no credential request sent"
    fi
    HI_BASE="$STORED_BASE"
  fi
fi
printf '%s' "$HI_BASE" | jq -Re 'test("^https://[A-Za-z0-9.-]+(:[0-9]+)?$|^http://(localhost|127\\.0\\.0\\.1|\\[::1\\])(:[0-9]+)?$")' >/dev/null 2>&1 \
  || fail "hi_credential_host_insecure: use HTTPS or explicit loopback HTTP only"

# Helper: does the creds file already hold a usable client_id?
creds_have_client_id() { [ -s "$CREDS_FILE" ] && [ -n "$(jq -er 'select((.client_id | type == "string" and length > 0) and (.client_secret | type == "string" and length > 0)) | .client_id' "$CREDS_FILE" 2>/dev/null)" ]; }

# CRITICAL (identity durability): re-registering when a creds file EXISTS but is merely
# unreadable / corrupt / wrong-HOME silently mints a NEW Hi agent and ORPHANS the user's
# real identity (their listings, credits, phone-bound workspace). Audit found 204/216 prod
# agents are orphans, largely from exactly this. So: register ONLY when the file is truly
# ABSENT. A present-but-unusable file is a LOUD error the user must resolve explicitly —
# orphaning must never be silent/accidental.
if [ -e "$CREDS_FILE" ] && ! [ -r "$CREDS_FILE" ]; then
  fail "Credentials exist but are not readable: $CREDS_FILE
   Refusing to register a NEW Hi identity — that would orphan your existing agent + data.
   Fix it:  chmod 600 \"$CREDS_FILE\"   (or, to deliberately start fresh: rm it, then re-run)"
fi
if [ -e "$CREDS_FILE" ] && ! creds_have_client_id; then
  fail "Credentials exist but have no valid client_id (corrupt/empty): $CREDS_FILE
   Refusing to silently register a NEW Hi identity — that would orphan your existing agent + data.
   If this file is junk:  rm \"$CREDS_FILE\"  then re-run.  Otherwise restore it from backup."
fi

if ! [ -e "$CREDS_FILE" ]; then
  # Serialize concurrent installers: two Claude sessions racing on a fresh machine would
  # otherwise each mint a separate agent. mkdir is an atomic cross-process mutex.
  if creds_have_client_id; then
    ok "Existing credentials at $CREDS_FILE — keeping agent_id=$(jq -r .agent_id "$CREDS_FILE")"
  else
    [ ! -e "$CREDS_DIR/.registration-pending.json" ] || fail "hi_registration_outcome_unknown: preserve pending marker and reconcile the previous attempt; do not register again"
    [ -z "${HI_CHANNEL_CODE:-}" ] || fail "hi_channel_attribution_unsupported: current installation API does not accept referral metadata"
    # The server does not provide registration idempotency. Persist a non-secret
    # fence BEFORE sending; an ambiguous response must never mint another Agent.
    printf '%s\n' '{"status":"outcome_unknown","host":"claude"}' > "$CREDS_DIR/.registration-pending.json"
    REG_BODY=$(jq -n --arg version "$VERSION" '{agent_type:"claude",display_name:"Claude Code (Hirey skill)",client_version:$version}')
    REG=$(curl -fsS --connect-timeout 5 --max-time 30 -X POST "$HI_BASE/v1/agents/api-keys" \
      -H 'content-type: application/json' \
      --data "$REG_BODY") \
      || fail "hi_registration_outcome_unknown: API-key creation failed; preserve pending marker and reconcile before retry"

    printf '%s' "$REG" | jq -e '
      (.error == null) and (.agent_id | type == "string" and length > 0) and .status == "pending"
      and (.api_key | type == "string" and test("^hi_ak_[A-Za-z0-9_-]+$"))
    ' >/dev/null 2>&1 || { echo "hi_register_failed: invalid registration response; credentials unchanged" >&2; exit 1; }
    CRED_TMP=$(mktemp "$CREDS_DIR/.credentials.XXXXXX")
    printf '%s' "$REG" | jq -e --arg base "$HI_BASE" '
      (.api_key | ltrimstr("hi_ak_") | gsub("-";"+") | gsub("_";"/") | @base64d | fromjson) as $key
      | if ($key.v != 1 or ($key.id | type != "string" or length == 0) or ($key.secret | type != "string" or length == 0)) then error("invalid key") else {
      client_id:          $key.id,
      client_secret:      $key.secret,
      agent_id:           .agent_id,
      status: .status,
      issuer:             $base,
      audience:           "hirey-hi",
      token_url:          ($base + "/oauth/token"),
      platform_base_url:  $base,
      access_token:           null,
      access_token_issued_at: 0,
      access_token_expires_in: 0
    } end' > "$CRED_TMP" 2>/dev/null || fail "hi_register_failed: invalid credential envelope; reconcile pending attempt"
    mv "$CRED_TMP" "$CREDS_FILE"
    CRED_TMP=""
    rm -f "$CREDS_DIR/.registration-pending.json"
    ok "Anonymous agent registered: $(jq -r .agent_id "$CREDS_FILE")"
  fi
else
  ok "Existing credentials at $CREDS_FILE — keeping agent_id=$(jq -r .agent_id "$CREDS_FILE")"
fi

# ─── 3. Mint or refresh access token (5-min skew) ────────────────────────
NOW=$(date +%s)
ISSUED_AT=$(jq '.access_token_issued_at // 0' "$CREDS_FILE")
EXPIRES_IN=$(jq '.access_token_expires_in // 0' "$CREDS_FILE")
EXP_AT=$(( ISSUED_AT + EXPIRES_IN - 300 ))

if [ "${HI_FORCE_TOKEN_REFRESH:-0}" = 1 ] || [ "$NOW" -ge "$EXP_AT" ]; then
  CID=$(jq -r .client_id "$CREDS_FILE")
  CSEC=$(jq -r .client_secret "$CREDS_FILE")
  AUD=$(jq -r .audience "$CREDS_FILE")
  TOK=$(curl -fsS --connect-timeout 5 --max-time 30 -X POST "$HI_BASE/oauth/token" \
    --data-urlencode "grant_type=client_credentials" \
    --data-urlencode "client_id=$CID" --data-urlencode "client_secret=$CSEC" --data-urlencode "audience=$AUD") \
    || fail "Token endpoint unreachable"
  printf '%s' "$TOK" | jq -e '(.access_token | type == "string" and length > 0) and (.expires_in | type == "number" and . > 0)' >/dev/null 2>&1 \
    || fail "hi_token_refresh_failed: invalid token response; existing credentials preserved"
  CRED_TMP=$(mktemp "$CREDS_DIR/.credentials.XXXXXX")
  jq --argjson tok "$TOK" --arg now "$NOW" '
    .access_token            = $tok.access_token
    | .access_token_issued_at  = ($now | tonumber)
    | .access_token_expires_in = $tok.expires_in
  ' "$CREDS_FILE" > "$CRED_TMP"
  mv "$CRED_TMP" "$CREDS_FILE"
  CRED_TMP=""
  ok "Access token refreshed (expires in $(jq -r .access_token_expires_in "$CREDS_FILE")s)"
else
  ok "Cached token still valid"
fi

AGENT_ID=$(jq -r .agent_id "$CREDS_FILE")

# ─── 4. Done ─────────────────────────────────────────────────────────────
echo
printf "${GREEN}✓${NC} Hirey Hi is ready (agent_id=${GREEN}%s${NC})\n" "$AGENT_ID"
echo
echo "  Skills installed at: $SKILLS_DIR/hi-{onboard,use,events,repair}/"
echo "  Credentials at:      $CREDS_FILE (mode 600)"
echo
echo "  Now ask Claude things like:"
echo "    \"find me a founder in San Francisco\""
echo "    \"post a listing for a fintech cofounder in SF\""
echo "    \"any replies from yesterday's SF pairings?\""
echo
printf "  ${DIM}Skills auto-load via live change detection — no restart needed.${NC}\n"
echo
printf "  ${DIM}To uninstall the skills (KEEPS your Hi identity — a reinstall reuses the SAME agent):${NC}\n"
printf "      rm -rf $SKILLS_DIR/hi-{onboard,use,events,repair}\n"
printf "  ${DIM}To ALSO erase your Hi identity (next install will register a brand-new agent): rm -rf $CREDS_DIR${NC}\n"
