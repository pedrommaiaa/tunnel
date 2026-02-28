#!/usr/bin/env bash
set -euo pipefail

SKILL_DIR="$HOME/.claude/skills/tunnel"
STATE_DIR="$HOME/.tunnel-manager"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[+]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }

echo ""
echo "  claude-tunnel uninstaller"
echo "  ─────────────────────────"
echo ""

# Stop running processes if state file exists
if [ -f "$STATE_DIR/state.json" ]; then
    CADDY_PID=$(python3 -c "import json; d=json.load(open('$STATE_DIR/state.json')); print(d.get('caddy_pid',''))" 2>/dev/null || true)
    CF_PID=$(python3 -c "import json; d=json.load(open('$STATE_DIR/state.json')); print(d.get('cloudflared_pid',''))" 2>/dev/null || true)

    if [ -n "$CADDY_PID" ] && kill -0 "$CADDY_PID" 2>/dev/null; then
        kill "$CADDY_PID" 2>/dev/null && info "Stopped Caddy (PID $CADDY_PID)"
    fi
    if [ -n "$CF_PID" ] && kill -0 "$CF_PID" 2>/dev/null; then
        kill "$CF_PID" 2>/dev/null && info "Stopped cloudflared (PID $CF_PID)"
    fi
fi

# Remove skill
if [ -d "$SKILL_DIR" ]; then
    rm -rf "$SKILL_DIR"
    info "Removed skill: $SKILL_DIR"
else
    warn "Skill directory not found (already removed?)"
fi

# Ask about state
if [ -d "$STATE_DIR" ]; then
    echo ""
    read -p "  Remove tunnel state (~/.tunnel-manager)? This deletes saved configs. [y/N] " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf "$STATE_DIR"
        info "Removed state directory"
    else
        info "Kept state directory"
    fi
fi

echo ""
info "Uninstall complete."
echo ""
echo "  Note: cloudflared tunnels created in Cloudflare remain active."
echo "  To delete them: cloudflared tunnel delete <tunnel-name>"
echo ""
