#!/bin/bash

# ==============================================================================
# PATCH 3 — Manifest Support
# Issue: #68 — add explicit host:instance mapping via --manifest flag
#
# Changes:
# 1. command-handler.js — add --manifest option to cluster-create
# 2. cluster-manager.js — respect manifest mode
#
# Usage: ./apply-patch3.sh [path-to-ev-devkit]
# Default: /usr/lib/node_modules/evdevkit
# ==============================================================================

EVDEVKIT_PATH=${1:-/usr/lib/node_modules/evdevkit}
CMD_TARGET="$EVDEVKIT_PATH/lib/command-handler.js"
MGR_TARGET="$EVDEVKIT_PATH/lib/cluster-manager.js"

echo ""
echo "============================================================"
echo " PATCH 3 — Manifest Support (Issue #68)"
echo "============================================================"
echo " command-handler : $CMD_TARGET"
echo " cluster-manager : $MGR_TARGET"
echo "============================================================"
echo ""

if [ ! -f "$CMD_TARGET" ] || [ ! -f "$MGR_TARGET" ]; then
    echo "❌ ERROR: Target files not found"
    exit 1
fi

if grep -q "Patch3: manifest mode" "$CMD_TARGET"; then
    echo "⚠️  Patch 3 already applied."
    exit 0
fi

BACKUP_CMD="$CMD_TARGET.backup-patch3-$(date +%Y%m%d-%H%M%S)"
BACKUP_MGR="$MGR_TARGET.backup-patch3-$(date +%Y%m%d-%H%M%S)"
cp "$CMD_TARGET" "$BACKUP_CMD"
cp "$MGR_TARGET" "$BACKUP_MGR"
echo "✅ Backup command-handler: $BACKUP_CMD"
echo "✅ Backup cluster-manager: $BACKUP_MGR"

node << JSEOF
const fs = require('fs');
const cmdTarget = '$CMD_TARGET';
const mgrTarget = '$MGR_TARGET';

// ==============================================================================
// Change 1 — command-handler.js
// ==============================================================================
let cmd = fs.readFileSync(cmdTarget, 'utf8');
const cmdOriginal = cmd;

// 1a — Add --manifest option
cmd = cmd.replace(
    "    .option('--recover [recover]', 'Recover from if there are failed cluster creations.')",
    "    .option('--recover [recover]', 'Recover from if there are failed cluster creations.')\n" +
    "    .option('--manifest [manifest]', 'JSON manifest file for explicit host:instance mapping (overrides hosts-file-path)')"
);

// 1b — Skip hosts file requirement if manifest provided
cmd = cmd.replace(
    "        if (!hostsFilePath || !fs.existsSync(hostsFilePath))\n            throw 'Preferred Host file path does not exist.';",
    "        // Patch3: manifest mode — skip hosts file requirement if manifest provided (issue #68)\n" +
    "        if (options?.manifest) {\n" +
    "            if (!fs.existsSync(options.manifest))\n" +
    "                throw 'Manifest file path does not exist.';\n" +
    "        } else if (!hostsFilePath || !fs.existsSync(hostsFilePath)) {\n" +
    "            throw 'Preferred Host file path does not exist.';\n" +
    "        }"
);

// 1c — Process manifest and pass manifestMode to ClusterManager
cmd = cmd.replace(
    "        clusterMgr = new ClusterManager(clusterSpec);\n        await clusterMgr.init(preferredHostsArray);",
    "        // Patch3: process manifest file if provided (issue #68)\n" +
    "        let manifestMode = false;\n" +
    "        if (options?.manifest) {\n" +
    "            try {\n" +
    "                const manifestData = JSON.parse(fs.readFileSync(options.manifest, 'UTF-8'));\n" +
    "                if (!Array.isArray(manifestData))\n" +
    "                    throw 'Manifest must be a JSON array.';\n" +
    "                for (const entry of manifestData) {\n" +
    "                    if (!entry.address || !entry.instances || entry.instances < 1)\n" +
    "                        throw 'Each manifest entry must have address and instances > 0.';\n" +
    "                }\n" +
    "                preferredHostsArray = manifestData.flatMap(entry =>\n" +
    "                    Array(entry.instances).fill(entry.address)\n" +
    "                );\n" +
    "                clusterSpec.size = manifestData.reduce((sum, e) => sum + e.instances, 0);\n" +
    "                manifestMode = true;\n" +
    "                console.log('Manifest mode: ' + manifestData.length + ' hosts, ' + clusterSpec.size + ' total nodes.');\n" +
    "                manifestData.forEach(e => console.log('  ' + e.address + ' -> ' + e.instances + ' node(s)'));\n" +
    "                console.log('');\n" +
    "            } catch (err) {\n" +
    "                throw 'Invalid manifest file: ' + err;\n" +
    "            }\n" +
    "        }\n\n" +
    "        clusterMgr = new ClusterManager(clusterSpec, manifestMode);\n" +
    "        await clusterMgr.init(preferredHostsArray);"
);

if (cmd === cmdOriginal) {
    console.error('ERROR: No changes made to command-handler.js');
    process.exit(1);
}

fs.writeFileSync(cmdTarget, cmd);
console.log('command-handler.js patched successfully');

// ==============================================================================
// Change 2 — cluster-manager.js
// ==============================================================================
let mgr = fs.readFileSync(mgrTarget, 'utf8');
const mgrOriginal = mgr;

// 2a — Add #manifestMode field
mgr = mgr.replace(
    '    #size;',
    '    #size;\n    #manifestMode; // Patch3: true when using manifest file (issue #68)'
);

// 2b — Update constructor signature and store manifestMode
mgr = mgr.replace(
    '    constructor(options = {}) {\n        this.#size = options.size || 3;',
    '    constructor(options = {}, manifestMode = false) {\n        this.#size = options.size || 3;\n        this.#manifestMode = manifestMode; // Patch3: store manifest mode flag (issue #68)'
);

// 2c — In manifest mode return next host directly by position
mgr = mgr.replace(
    '    #getOptimalNodesList(targetSize, preferredHostsArray) {\n' +
    '        const hosts = Object.values(this.#hosts).filter((host) => host.blacklistScore < BLACKLIST_SCORE_THRESHOLD &&\n' +
    '            host.maxInstances > host.activeInstances);\n\n' +
    '        let preferredHosts = preferredHostsArray.map(ph => hosts.find(h => h.address === ph)).filter(h => h);',
    '    #getOptimalNodesList(targetSize, preferredHostsArray) {\n' +
    '        const hosts = Object.values(this.#hosts).filter((host) => host.blacklistScore < BLACKLIST_SCORE_THRESHOLD &&\n' +
    '            host.maxInstances > host.activeInstances);\n\n' +
    '        // Patch3: in manifest mode return next host directly by position (issue #68)\n' +
    '        if (this.#manifestMode) {\n' +
    '            const allHosts = Object.values(this.#hosts).filter(host => host.blacklistScore < BLACKLIST_SCORE_THRESHOLD);\n' +
    '            const usedCount = this.#nodes.length;\n' +
    '            const nextAddress = preferredHostsArray[usedCount];\n' +
    '            const nextHost = allHosts.find(h => h.address === nextAddress);\n' +
    '            if (!nextHost) return [];\n' +
    '            return [Object.assign({}, nextHost, { leaseAmount: nextHost.leaseAmount || 0 })];\n' +
    '        }\n\n' +
    '        let preferredHosts = preferredHostsArray.map(ph => hosts.find(h => h.address === ph)).filter(h => h);'
);

// 2d — Skip sort in manifest mode
mgr = mgr.replace(
    '        // Patched: sort by nodes assigned so hosts with fewer nodes get priority (issue #68)\n' +
    '        preferredHosts = preferredHosts.map(({ address, availableInstances, leaseAmount, nodes }) => ({ address, availableInstances, leaseAmount, nodes }))\n' +
    '            .sort((a, b) => a.nodes - b.nodes);',
    '        // Patched: sort by nodes assigned so hosts with fewer nodes get priority (issue #68)\n' +
    '        // Patch3: skip sort in manifest mode — use exact order specified (issue #68)\n' +
    '        preferredHosts = preferredHosts.map(({ address, availableInstances, leaseAmount, nodes }) => ({ address, availableInstances, leaseAmount, nodes }))\n' +
    '            .sort((a, b) => a.nodes - b.nodes);'
);

if (mgr === mgrOriginal) {
    console.error('ERROR: No changes made to cluster-manager.js');
    process.exit(1);
}

fs.writeFileSync(mgrTarget, mgr);
console.log('cluster-manager.js patched successfully');
JSEOF

if [ $? -eq 0 ]; then
    echo ""
    echo "============================================================"
    echo " PATCH 3 APPLIED SUCCESSFULLY"
    echo "============================================================"
    echo " Changes:"
    echo " 1. --manifest option added to cluster-create"
    echo " 2. Manifest JSON read, validated and expanded"
    echo " 3. Cluster size auto-calculated from manifest totals"
    echo " 4. manifestMode bypasses sort-by-nodes logic"
    echo " 5. Manifest mode uses exact position ordering"
    echo ""
    echo " Usage:"
    echo "   evdevkit cluster-create <size> <contract> <bin> <hosts> --manifest manifest.json"
    echo ""
    echo " Manifest format:"
    echo '   [{"address":"rHostA...","instances":2},{"address":"rHostB...","instances":1}]'
    echo ""
    echo " Backup command-handler: $BACKUP_CMD"
    echo " Backup cluster-manager: $BACKUP_MGR"
    echo "============================================================"
else
    echo "❌ PATCH FAILED — restoring backups"
    cp "$BACKUP_CMD" "$CMD_TARGET"
    cp "$BACKUP_MGR" "$MGR_TARGET"
fi
