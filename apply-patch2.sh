#!/bin/bash

# ==============================================================================
# PATCH 2 — Interactive Hosts File Warning
# Issue: #68 — no warning when cluster size exceeds unique hosts in file
#
# Changes:
# 1. command-handler.js — upfront interactive check after clusterMgr.init()
#    - Warns when cluster size exceeds unique hosts
#    - Shows which hosts would receive duplicate instances
#    - Offers: [1] Enter host manually [2] Continue anyway [3] Abort
#    - Verified host added to hosts file and clusterMgr via addHost()
# 2. cluster-manager.js — addHost() method to add hosts post-init
#
# Usage: ./apply-patch2.sh [path-to-ev-devkit]
# Default: /usr/lib/node_modules/evdevkit
# ==============================================================================

EVDEVKIT_PATH=${1:-/usr/lib/node_modules/evdevkit}
CMD_TARGET="$EVDEVKIT_PATH/index.js"
MGR_TARGET="$EVDEVKIT_PATH/index.js"

echo ""
echo "============================================================"
echo " PATCH 2 — Interactive Hosts File Warning (Issue #68)"
echo "============================================================"
echo " command-handler : $CMD_TARGET"
echo " cluster-manager : $MGR_TARGET"
echo "============================================================"
echo ""

if [ ! -f "$CMD_TARGET" ] || [ ! -f "$MGR_TARGET" ]; then
    echo "❌ ERROR: Target files not found"
    exit 1
fi

if grep -q "Patch2: upfront check" "$CMD_TARGET"; then
    echo "⚠️  Patch 2 already applied."
    exit 0
fi

BACKUP_CMD="$CMD_TARGET.backup-patch2-$(date +%Y%m%d-%H%M%S)"
BACKUP_MGR="$MGR_TARGET.backup-patch2-$(date +%Y%m%d-%H%M%S)"
cp "$CMD_TARGET" "$BACKUP_CMD"
cp "$MGR_TARGET" "$BACKUP_MGR"
echo "✅ Backup command-handler: $BACKUP_CMD"
echo "✅ Backup cluster-manager: $BACKUP_MGR"

CMD_TARGET="$CMD_TARGET" MGR_TARGET="$MGR_TARGET" node << 'JSEOF'
const fs = require('fs');
const cmdTarget = process.env.CMD_TARGET;
const mgrTarget = process.env.MGR_TARGET;

// ==============================================================================
// Change 1 — command-handler.js
// ==============================================================================
let cmd = fs.readFileSync(cmdTarget, 'utf8');
const cmdOriginal = cmd;

const oldCmdStr = '        let result;';

const newCmdStr =
    '\n' +
    '        // Patch2: upfront check — warn if cluster size exceeds unique hosts (issue #68)\n' +
    '        if (!options?.manifest && preferredHostsArray.length < size) {\n' +
    '            const needed = size - preferredHostsArray.length;\n' +
    '            const counts = {};\n' +
    '            const simulated = [...preferredHostsArray];\n' +
    '            for (let x = 0; x < needed; x++) simulated.push(preferredHostsArray[x % preferredHostsArray.length]);\n' +
    '            for (const h of simulated) counts[h] = (counts[h] || 0) + 1;\n' +
    '            const duplicates = Object.entries(counts).filter(([, c]) => c > 1);\n' +
    '\n' +
    "            console.warn(' WARNING: Cluster size (' + size + ') exceeds unique hosts in hosts file (' + preferredHostsArray.length + ').');\n" +
    '            if (duplicates.length > 0) {\n' +
    "                console.warn('   The following hosts will receive more than one instance:');\n" +
    '                for (const [addr, count] of duplicates)\n' +
    "                    console.warn('   - ' + addr + ' (would receive ' + count + ' instances)');\n" +
    '            }\n' +
    "            console.warn('   Tip: Use api.onledger.net/hosts to find available host addresses.');\n" +
    '\n' +
    '            let resolved = false;\n' +
    '            while (!resolved) {\n' +
    '                const answer = await questionSync(\n' +
    "                    '   Options:\\n' +\n" +
    "                    '   [1] Enter a host address manually\\n' +\n" +
    "                    '   [2] Continue anyway - I accept the risks\\n' +\n" +
    "                    '   [3] Abort\\n' +\n" +
    "                    '   Choice (1/2/3): '\n" +
    '                );\n' +
    '\n' +
    "                if (answer.trim() === '1') {\n" +
    "                    const hostAddr = (await questionSync('   Enter host address: ')).trim();\n" +
    '                    if (!hostAddr) {\n' +
    "                        console.warn('   No address entered. Try again.');\n" +
    '                        continue;\n' +
    '                    }\n' +
    '                    const added = await clusterMgr.addHost(hostAddr);\n' +
    '                    if (!added) {\n' +
    "                        console.warn('   Host is not active, not found, or has no available slots. Try again.');\n" +
    '                    } else {\n' +
    '                        preferredHostsArray.push(hostAddr);\n' +
    "                        const currentContent = fs.readFileSync(hostsFilePath, 'UTF-8');\n" +
    "                        const separator = currentContent.endsWith('\\n') ? '' : '\\n';\n" +
    "                        fs.appendFileSync(hostsFilePath, separator + hostAddr + '\\n');\n" +
    "                        console.log('   Added host ' + hostAddr + ' to hosts file.');\n" +
    '                        resolved = preferredHostsArray.length >= size;\n' +
    "                        if (!resolved) console.warn('   Still need ' + (size - preferredHostsArray.length) + ' more unique host(s).\\n');\n" +
    '                    }\n' +
    "                } else if (answer.trim() === '2') {\n" +
    "                    console.warn('   Continuing with duplicate host assignments...\\n');\n" +
    '                    resolved = true;\n' +
    "                } else if (answer.trim() === '3') {\n" +
    "                    console.log('   Aborting. Update your hosts file and retry.');\n" +
    '                    return;\n' +
    '                } else {\n' +
    "                    console.warn('   Invalid choice. Please enter 1, 2 or 3.');\n" +
    '                }\n' +
    '            }\n' +
    '        }\n' +
    '        // End Patch2\n' +
    '        let result;';

if (!cmd.includes(oldCmdStr)) {
    console.error('ERROR: Could not find insertion point in command-handler.js');
    process.exit(1);
}

cmd = cmd.replace(oldCmdStr, newCmdStr);
fs.writeFileSync(cmdTarget, cmd);
console.log('command-handler.js patched successfully');

// ==============================================================================
// Change 2 — cluster-manager.js — addHost() method
// ==============================================================================
let mgr = fs.readFileSync(mgrTarget, 'utf8');
const mgrOriginal = mgr;

mgr = mgr.replace(
    '    getTenantAddress() {',
    '    async addHost(hostAddress) {\n' +
    '        // Patch2: add a host to the cluster manager after init (issue #68)\n' +
    '        const hostInfo = await this.#evernodeMgr.getHostInfo(hostAddress);\n' +
    '        if (!hostInfo || !hostInfo.active || hostInfo.maxInstances <= hostInfo.activeInstances)\n' +
    '            return false;\n' +
    '        hostInfo.blacklistScore = 0;\n' +
    '        this.#hosts[hostAddress] = hostInfo;\n' +
    '        return true;\n' +
    '    }\n\n' +
    '    getTenantAddress() {'
);

if (mgr === mgrOriginal) {
    console.error('ERROR: Could not find getTenantAddress in cluster-manager.js');
    process.exit(1);
}

fs.writeFileSync(mgrTarget, mgr);
console.log('cluster-manager.js patched successfully');
JSEOF

if [ $? -eq 0 ]; then
    echo ""
    echo "============================================================"
    echo " PATCH 2 APPLIED SUCCESSFULLY"
    echo "============================================================"
    echo " Changes:"
    echo " 1. Interactive warning when cluster size > unique hosts"
    echo " 2. Shows which hosts would receive duplicate instances"
    echo " 3. Options: enter host manually, continue, or abort"
    echo " 4. addHost() method added to ClusterManager"
    echo ""
    echo " Backup command-handler: $BACKUP_CMD"
    echo " Backup cluster-manager: $BACKUP_MGR"
    echo "============================================================"
else
    echo "❌ PATCH FAILED — restoring backups"
    cp "$BACKUP_CMD" "$CMD_TARGET"
    cp "$BACKUP_MGR" "$MGR_TARGET"
fi
