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

if [ ! -f bin/overlay ] || [ overlay-src/overlay.swift -nt bin/overlay ]; then
    if ! command -v swiftc >/dev/null 2>&1; then
        echo "error: swiftc not found. Install Xcode Command Line Tools with: xcode-select --install" >&2
        exit 1
    fi
    echo "Compiling overlay binary..."
    swiftc -O overlay-src/overlay.swift -o bin/overlay
fi

if [ ! -f bin/calendar-events ] || [ overlay-src/calendar-events.swift -nt bin/calendar-events ]; then
    if ! command -v swiftc >/dev/null 2>&1; then
        echo "error: swiftc not found. Install Xcode Command Line Tools with: xcode-select --install" >&2
        exit 1
    fi
    echo "Compiling calendar-events binary..."
    swiftc -O overlay-src/calendar-events.swift -o bin/calendar-events \
        -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist \
        -Xlinker overlay-src/calendar-events-Info.plist
    codesign --force --sign - bin/calendar-events
fi

if [ ! -f config.yaml ]; then
    echo "Creating config.yaml from config.example.yaml..."
    cp config.example.yaml config.yaml
fi

if [ ! -f data/state.json ]; then
    echo "{}" > data/state.json
fi
if [ ! -f data/calendar_state.json ]; then
    echo "{}" > data/calendar_state.json
fi
touch data/history.jsonl

chmod +x bin/nagger

PLIST_SRC="$DIR/launchd/com.local-nagger.checker.plist.template"
PLIST_DST="$HOME/Library/LaunchAgents/com.local-nagger.checker.plist"
mkdir -p "$HOME/Library/LaunchAgents"

# Clean up the pre-rename agent/plist if present (label changed from
# com.donsu.local-nagger to com.local-nagger.checker).
OLD_PLIST_DST="$HOME/Library/LaunchAgents/com.donsu.local-nagger.plist"
if [ -L "$OLD_PLIST_DST" ] || [ -f "$OLD_PLIST_DST" ]; then
    echo "Removing legacy launchd agent (com.donsu.local-nagger)..."
    launchctl bootout "gui/$(id -u)/com.donsu.local-nagger" 2>/dev/null || true
    rm -f "$OLD_PLIST_DST"
fi

if [ -L "$PLIST_DST" ] || [ -f "$PLIST_DST" ]; then
    echo "Unloading existing launchd agent (if loaded)..."
    launchctl bootout "gui/$(id -u)/com.local-nagger.checker" 2>/dev/null || true
    rm -f "$PLIST_DST"
fi
sed "s|__NAGGER_DIR__|$DIR|g" "$PLIST_SRC" > "$PLIST_DST"

echo "Loading launchd agent..."
launchctl bootstrap "gui/$(id -u)" "$PLIST_DST"

SKILL_DIR="$HOME/.claude/skills/local-nagger"
if [ ! -f "$SKILL_DIR/SKILL.md" ]; then
    echo "Installing Claude Code skill..."
    mkdir -p "$SKILL_DIR"
    cp "$DIR/claude-skill/SKILL.md" "$SKILL_DIR/SKILL.md"
fi

AUTH_JSON=$("$DIR/bin/calendar-events" check-auth 2>/dev/null || echo '{"status":"error"}')
if echo "$AUTH_JSON" | grep -q '"status":"notDetermined"'; then
    echo ""
    echo "Local Nagger wants to read Calendar.app to show meeting reminders."
    echo "Approve the permission prompt that appears now (System Settings > Privacy & Security > Calendars)."
    "$DIR/bin/calendar-events" request-access --timeout 60 >/dev/null || true
fi

PATH_LINE='export PATH="$HOME/local-nagger/bin:$PATH"'
if ! grep -qF "$PATH_LINE" "$HOME/.zshrc" 2>/dev/null; then
    echo ""
    echo "Add this line to your ~/.zshrc to use the 'nagger' CLI:"
    echo "  $PATH_LINE"
fi

echo ""
echo "Meeting reminders (Google Calendar via EventKit) are off by default."
echo "Set 'calendar: { enabled: true }' in config.yaml to turn them on."
echo "Note: rebuilding bin/calendar-events changes its signature, so macOS"
echo "will ask you to re-approve Calendar access after any future rebuild."

echo ""
echo "Setup complete. Verifying..."
launchctl list | grep com.local-nagger.checker || echo "warning: agent not showing in launchctl list yet"
"$DIR/bin/nagger" list
