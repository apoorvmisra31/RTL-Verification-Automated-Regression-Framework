#!/usr/bin/env bash
#=============================================================================
# launch_dashboard.sh - One-Click Launcher for RTL Verification Studio
#=============================================================================

set -e

# Resolve script directory (project root)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "================================================================================"
echo "   STARTING RTL VERIFICATION & AUTOMATED REGRESSION STUDIO"
echo "================================================================================"

# Verify Python 3 is available
if ! command -v python3 >/dev/null 2>&1; then
    echo "[ERROR] python3 is required but was not found in PATH."
    exit 1
fi

# Pass any command-line options directly to the dashboard server
exec python3 scripts/dashboard_server.py "$@"
