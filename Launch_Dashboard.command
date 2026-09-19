#!/bin/bash
#=============================================================================
# Launch_Dashboard.command - macOS Desktop Finder Launcher
# Double-click this file directly in macOS Finder to open the Dashboard!
#=============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

echo "================================================================================"
echo "       SYNCHRONOUS FIFO RTL VERIFICATION & REGRESSION STUDIO"
echo "================================================================================"
echo " Starting local verification dashboard server..."
echo " Project root: $DIR"
echo "================================================================================"

if command -v python3 >/dev/null 2>&1; then
    python3 scripts/dashboard_server.py
elif [ -f "/opt/homebrew/bin/python3" ]; then
    /opt/homebrew/bin/python3 scripts/dashboard_server.py
elif [ -f "/usr/local/bin/python3" ]; then
    /usr/local/bin/python3 scripts/dashboard_server.py
else
    echo "[ERROR] python3 not found. Please ensure Python 3.9+ is installed."
    read -p "Press enter to exit..."
    exit 1
fi
