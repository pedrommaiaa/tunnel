#!/usr/bin/env bash
set -euo pipefail

SKILL_NAME="tunnel"
SKILL_DIR="$HOME/.claude/skills/$SKILL_NAME"
STATE_DIR="$HOME/.tunnel-manager"
REPO_URL="https://raw.githubusercontent.com/pedromaia/claude-tunnel/main"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[+]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[x]${NC} $1"; }

echo ""
echo "  claude-tunnel installer"
echo "  ───────────────────────"
echo ""

# 1. Check if Claude Code is installed
if [ ! -d "$HOME/.claude" ]; then
    error "~/.claude not found. Install Claude Code first: https://claude.com/claude-code"
    exit 1
fi

# 2. Create skill directory
mkdir -p "$SKILL_DIR"
info "Created skill directory: $SKILL_DIR"

# 3. Download or copy SKILL.md
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/skill/SKILL.md" ]; then
    # Local install (cloned repo)
    cp "$SCRIPT_DIR/skill/SKILL.md" "$SKILL_DIR/SKILL.md"
    info "Installed skill from local source"
else
    # Remote install (curl pipe)
    curl -fsSL "$REPO_URL/skill/SKILL.md" -o "$SKILL_DIR/SKILL.md"
    info "Downloaded skill from GitHub"
fi

# 4. Create state directory
mkdir -p "$STATE_DIR"
info "Created state directory: $STATE_DIR"

# 5. Check prerequisites
echo ""
MISSING=0

if command -v cloudflared &>/dev/null; then
    info "cloudflared found: $(cloudflared --version 2>&1 | head -1)"
else
    warn "cloudflared not found. Install it:"
    echo "    brew install cloudflare/cloudflare/cloudflared"
    MISSING=1
fi

if command -v caddy &>/dev/null; then
    info "caddy found: $(caddy version 2>&1 | head -1)"
else
    warn "caddy not found. Install it:"
    echo "    brew install caddy"
    MISSING=1
fi

# 6. Done
echo ""
if [ $MISSING -eq 0 ]; then
    info "Installation complete!"
else
    warn "Installation complete (install missing dependencies above)."
fi

echo ""
echo "  Usage: open Claude Code and type /tunnel"
echo ""
echo "  Commands:"
echo "    /tunnel configure   First-time setup"
echo "    /tunnel up          Start tunnel"
echo "    /tunnel down        Stop tunnel"
echo "    /tunnel status      Check tunnel health"
echo ""
