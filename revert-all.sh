#!/bin/bash

# ==============================================================================
# REVERT ALL PATCHES
# Restores cluster-manager.js and command-handler.js to original unpatched state
#
# Usage: ./revert-all.sh [path-to-ev-devkit]
# Default: /usr/lib/node_modules/evdevkit
# ==============================================================================

EVDEVKIT_PATH=${1:-/usr/lib/node_modules/evdevkit}
PATCHES_DIR="$(dirname "$0")"
CMD_TARGET="$EVDEVKIT_PATH/lib/command-handler.js"
MGR_TARGET="$EVDEVKIT_PATH/lib/cluster-manager.js"
CMD_ORIGINAL="$PATCHES_DIR/command-handler.js.original"
MGR_ORIGINAL="$PATCHES_DIR/cluster-manager.js.original"

echo ""
echo "============================================================"
echo " REVERT ALL PATCHES"
echo "============================================================"

if [ ! -f "$CMD_ORIGINAL" ] || [ ! -f "$MGR_ORIGINAL" ]; then
    echo "❌ Original files not found in patches directory"
    exit 1
fi

cp "$MGR_ORIGINAL" "$MGR_TARGET"
echo "✅ cluster-manager.js restored to original"

cp "$CMD_ORIGINAL" "$CMD_TARGET"
echo "✅ command-handler.js restored to original"

echo "============================================================"
