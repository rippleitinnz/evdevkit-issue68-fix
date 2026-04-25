# evdevkit-issue68-fix

Fix and enhancements for `evdevkit cluster-create` relating to [issue #68](https://github.com/EvernodeXRPL/ev-devkit/issues/68).

## Background

`cluster-create` contains a modulo bug in `#createClusterChunk` that causes
multiple nodes to be assigned to the same host when the cluster size exceeds
the number of optimal hosts. This results in nodes that cannot peer with each
other, causing weakly-connected or 0-peer consensus failures.

## Contents

| Script | Type | Description |
|--------|------|-------------|
| `apply-patch1.sh` | Bug fix | Core deduplication fix — corrects host assignment logic |
| `apply-patch2.sh` | Feature | Interactive warning when cluster size exceeds unique hosts |
| `apply-patch3.sh` | Feature | Manifest support — define exact host:instance layout |
| `revert-all.sh` | Utility | Reverts all changes back to original |

## Requirements

- evdevkit installed globally (`npm i evdevkit -g`)
- Node.js v20+

## Install Path

Scripts default to `/usr/lib/node_modules/evdevkit` — the standard Linux npm global path.

To find your evdevkit path:
```bash
npm root -g
```

If different, pass it as an argument to each script:
```bash
./apply-patch1.sh /your/path/to/evdevkit
```

## Usage

```bash
# Apply all (recommended)
./apply-patch1.sh
./apply-patch2.sh
./apply-patch3.sh

# Apply fix only
./apply-patch1.sh

# Apply fix + manifest support (no interactive warning)
./apply-patch1.sh
./apply-patch3.sh

# Revert everything
./revert-all.sh
```

Each script is independent — apply any combination in any order.
Each script creates a timestamped backup before modifying any file.

## Patch 1 — Core Deduplication Fix

Fixes 5 issues in `cluster-manager.js`:

1. `BLACKLIST_SCORE_THRESHOLD` raised from 2 to 3
2. Modulo bug fixed — `optimalNodes[i % optimalNodes.length]` (removed `curNodeCount` offset)
3. Hosts sorted by nodes already assigned — fewer nodes get priority
4. `chunkSize` always set to 1 for correct host tracking
5. Warning added when duplication is unavoidable

## Patch 2 — Interactive Warning

Adds an upfront check in `command-handler.js` after `clusterMgr.init()`:

- Fires when cluster size exceeds unique hosts in the hosts file
- Shows which hosts would receive duplicate instances
- Offers three options:
  - `[1]` Enter a host address manually
  - `[2]` Continue anyway
  - `[3]` Abort

Also adds `addHost()` method to `ClusterManager` for adding hosts post-init.

## Patch 3 — Manifest Support

Adds `--manifest` flag to `cluster-create` in `command-handler.js`.

Manifest format:
```json
[
  {"address": "rHostA...", "instances": 2},
  {"address": "rHostB...", "instances": 1},
  {"address": "rHostC...", "instances": 1}
]
```

Usage:
```bash
evdevkit cluster-create 4 ./contract /usr/bin/node ./hosts.txt \
  --manifest manifest.json \
  -a index.js \
  -m 3
```

- Cluster size is calculated automatically from manifest totals
- Hosts file is still required but ignored when manifest is provided
- Patch 2 warning is suppressed in manifest mode
- Exact host order is preserved — no sorting applied

## Revert

```bash
# Revert all patches
./revert-all.sh

# With custom path
./revert-all.sh /your/path/to/evdevkit
```

## Status

Tested on evdevkit v0.6.5-beta on Linux (Ubuntu/Parrot).
Awaiting broader community testing before submitting PR to EvernodeXRPL/ev-devkit.

## Related

- [EvernodeXRPL/ev-devkit issue #68](https://github.com/EvernodeXRPL/ev-devkit/issues/68)
- [Evernode Host Discovery API](https://api.onledger.net)
