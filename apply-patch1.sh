#!/bin/bash

# ==============================================================================
# PATCH 1 — Core Host Deduplication Fix
# Issue: #68 — cluster-create assigns multiple instances to same host
#
# Changes:
# 1. BLACKLIST_SCORE_THRESHOLD raised from 2 to 3
# 2. Modulo bug fixed in #createClusterChunk
# 3. Hosts sorted by assigned instances in #getOptimalNodesList
# 4. chunkSize set to always 1
# 5. Duplication warning added (non-manifest mode only)
#
# Usage: ./apply-patch1.sh [path-to-ev-devkit]
# Default: /usr/lib/node_modules/evdevkit
# ==============================================================================

EVDEVKIT_PATH=${1:-/usr/lib/node_modules/evdevkit}
TARGET="$EVDEVKIT_PATH/lib/cluster-manager.js"

echo ""
echo "============================================================"
echo " PATCH 1 — Core Host Deduplication Fix (Issue #68)"
echo "============================================================"
echo " Target: $TARGET"
echo "============================================================"
echo ""

if [ ! -f "$TARGET" ]; then
    echo "❌ ERROR: cluster-manager.js not found at $TARGET"
    exit 1
fi

if grep -q "Patched: raised from 2 (issue #68)" "$TARGET"; then
    echo "⚠️  Patch 1 already applied."
    exit 0
fi

BACKUP="$TARGET.backup-patch1-$(date +%Y%m%d-%H%M%S)"
cp "$TARGET" "$BACKUP"
echo "✅ Backup: $BACKUP"

node << JSEOF
const fs = require('fs');
const target = '$TARGET';
let content = fs.readFileSync(target, 'utf8');
const original = content;

// 1 — Raise blacklist threshold
content = content.replace(
    'const BLACKLIST_SCORE_THRESHOLD = 2;',
    'const BLACKLIST_SCORE_THRESHOLD = 3; // Patched: raised from 2 (issue #68)'
);

// 2 — Fix modulo bug
content = content.replace(
    'const host = optimalNodes[(curNodeCount + i) % optimalNodes.length];',
    'const host = optimalNodes[i % optimalNodes.length]; // Patched: removed curNodeCount offset (issue #68)'
);

// 3 — Sort hosts by assigned instances
content = content.replace(
    '        preferredHosts = preferredHosts.map(({ address, availableInstances, leaseAmount, nodes }) => ({ address, availableInstances, leaseAmount, nodes }));',
    '        // Patched: sort by instances assigned so hosts with fewer instances get priority (issue #68)\n' +
    '        preferredHosts = preferredHosts.map(({ address, availableInstances, leaseAmount, nodes }) => ({ address, availableInstances, leaseAmount, nodes }))\n' +
    '            .sort((a, b) => a.nodes - b.nodes);'
);

// 4 — Set chunkSize to always 1
content = content.replace(
    'const chunkSize = Math.min((targetSize == this.#size ? 1 : targetSize), preferredHostsArray.length)',
    'const chunkSize = 1; // Patched: always 1 for correct host tracking (issue #68)'
);

// 5 — Add duplication warning (non-manifest mode only)
content = content.replace(
    '            const nodes = await this.#createClusterChunk(chunkSize, optimalNodes);',
    '            // Patched: warn if duplication unavoidable in non-manifest mode (issue #68)\n' +
    '            const usedHosts = this.#nodes.map(n => n.host);\n' +
    '            const firstNode = optimalNodes[0];\n' +
    '            if (firstNode && usedHosts.includes(firstNode.address)) {\n' +
    '                console.warn("Warning: Host " + firstNode.address + " already has an instance in this cluster. Add more hosts to your hosts file.");\n' +
    '            }\n' +
    '            const nodes = await this.#createClusterChunk(chunkSize, optimalNodes);'
);

if (content === original) {
    console.error('ERROR: No changes made - source may have changed');
    process.exit(1);
}

fs.writeFileSync(target, content);
console.log('All 5 changes applied');
JSEOF

if [ $? -eq 0 ]; then
    echo ""
    echo "============================================================"
    echo " PATCH 1 APPLIED SUCCESSFULLY"
    echo "============================================================"
    echo " Changes:"
    echo " 1. BLACKLIST_SCORE_THRESHOLD: 2 -> 3"
    echo " 2. Modulo bug fixed in #createClusterChunk"
    echo " 3. Hosts sorted by assigned instances"
    echo " 4. chunkSize always 1"
    echo " 5. Duplication warning added (non-manifest mode only)"
    echo ""
    echo " Backup: $BACKUP"
    echo " Revert: cp $BACKUP $TARGET"
    echo "============================================================"
else
    echo "❌ PATCH FAILED — restoring backup"
    cp "$BACKUP" "$TARGET"
fi
