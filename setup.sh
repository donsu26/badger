#!/bin/bash
# Idempotent installer for Local Nagger.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

mkdir -p data launchd bin

if [ ! -d .venv ]; then
    echo "Creating virtualenv..."
    python3 -m venv .venv
fi

echo "Installing dependencies..."
"$DIR/.venv/bin/pip" install --quiet --upgrade pip
"$DIR/.venv/bin/pip" install --quiet -r requirements.txt

if [ ! -f config.yaml ]; then
    echo "Creating config.yaml from config.example.yaml..."
    cp config.example.yaml config.yaml
fi

if [ ! -f data/state.json ]; then
    echo "{}" > data/state.json
fi
touch data/history.jsonl

chmod +x bin/nagger

PLIST_SRC="$DIR/launchd/com.donsu.local-nagger.plist"
PLIST_DST="$HOME/Library/LaunchAgents/com.donsu.local-nagger.plist"
mkdir -p "$HOME/Library/LaunchAgents"

if [ -L "$PLIST_DST" ] || [ -f "$PLIST_DST" ]; then
    echo "Unloading existing launchd agent (if loaded)..."
    launchctl bootout "gui/$(id -u)/com.donsu.local-nagger" 2>/dev/null || true
    rm -f "$PLIST_DST"
fi
ln -s "$PLIST_SRC" "$PLIST_DST"

echo "Loading launchd agent..."
launchctl bootstrap "gui/$(id -u)" "$PLIST_DST"

SKILL_DIR="$HOME/.claude/skills/local-nagger"
if [ ! -f "$SKILL_DIR/SKILL.md" ]; then
    echo "Installing Claude Code skill..."
    mkdir -p "$SKILL_DIR"
    cp "$DIR/claude-skill/SKILL.md" "$SKILL_DIR/SKILL.md"
fi

PATH_LINE='export PATH="$HOME/local-nagger/bin:$PATH"'
if ! grep -qF "$PATH_LINE" "$HOME/.zshrc" 2>/dev/null; then
    echo ""
    echo "Add this line to your ~/.zshrc to use the 'nagger' CLI:"
    echo "  $PATH_LINE"
fi

echo ""
echo "Setup complete. Verifying..."
launchctl list | grep com.donsu.local-nagger || echo "warning: agent not showing in launchctl list yet"
"$DIR/bin/nagger" list
