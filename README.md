# evdevkit-issue68-fix

Fix and enhancements for `evdevkit cluster-create` relating to [issue #68](https://github.com/EvernodeXRPL/ev-devkit/issues/68).

## Background

`cluster-create` contains two bugs in the cluster allocation logic that cause
multiple instances to be assigned to the same host, with the third host (and beyond)
in the hosts file receiving zero instances regardless of available slots.

**Root cause 1 — chunkSize bug:**
On the second iteration of `createCluster()`, `chunkSize` is set to `targetSize`
(e.g. 2) rather than 1. This causes `#getOptimalNodesList` to allocate 2 instances
across only the first 2 hosts, meaning the third host never gets a turn.

**Root cause 2 — modulo offset bug:**
In `#createClusterChunk`, the host selection uses:

```
optimalNodes[(curNodeCount + i) % optimalNodes.length]
```

The `curNodeCount` offset causes the index to wrap incorrectly, assigning a
second instance back to the first host instead of moving to the next.

Both bugs compound — the result is instance 2 and 3 both land on host 1, and
host 3 is never used. This causes weakly-connected or 0-peer consensus failures
since two instances on the same host cannot peer with each other.

**Common misconception — price sort is not the cause:**
The hosts file IS sorted by lease amount in `#getOptimalNodesList`, but only
when `--evr-limit` is passed. Without that flag, `evrBalance` is `null` and
the sort never executes. Price plays no role in host selection in normal usage.
This was incorrectly identified as the root cause in
[EvernodeXRPL/evernode-sdk#95](https://github.com/EvernodeXRPL/evernode-sdk/issues/95).
The correct root cause is documented in
[EvernodeXRPL/ev-devkit#68](https://github.com/EvernodeXRPL/ev-devkit/issues/68).

## Contents

| Script | Type | Description |
| --- | --- | --- |
| `apply-patch1.sh` | Bug fix | Core deduplication fix — corrects host assignment logic |
| `apply-patch2.sh` | Feature | Interactive warning when cluster size exceeds unique hosts |
| `apply-patch3.sh` | Feature | Manifest support — define exact host:instance layout |
| `revert-all.sh` | Utility | Reverts all changes back to original |

## Requirements

* evdevkit installed globally (`npm i evdevkit -g`)
* Node.js v20+

## Important — evdevkit Package Structure

evdevkit is distributed as a **bundled package**. All source code is compiled
into a single `index.js` file — there is no `lib/cluster-manager.js` or
`lib/command-handler.js` in the installed package.

The patch scripts target `index.js` directly. The `cluster-manager.js.original`
and `command-handler.js.original` files in this repository are provided as
reference only — they show the original unbundled source for the sections being
patched, not files that exist in your installation.

## Install Path

Scripts default to `/usr/lib/node_modules/evdevkit` — the standard Linux npm
global path. The actual target file patched is `index.js` inside that directory.

To find your evdevkit path:

```
npm root -g
```

This returns the global node_modules directory. Your evdevkit will be at
`<npm root -g>/evdevkit`. If different from the default, pass it as an argument:

```
./apply-patch1.sh /your/path/to/evdevkit
```

To verify the correct file will be targeted before applying:

```
ls $(npm root -g)/evdevkit/index.js
```

## Usage

```
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

Fixes 5 issues in the bundled `index.js`:

1. `BLACKLIST_SCORE_THRESHOLD` raised from 2 to 3
2. Modulo bug fixed — `optimalNodes[i % optimalNodes.length]` (removed `curNodeCount` offset)
3. Hosts sorted by instances already assigned — fewer instances get priority
4. `chunkSize` always set to 1 for correct host tracking
5. Warning added when duplication is unavoidable

## Patch 2 — Interactive Warning

Adds an upfront check after `clusterMgr.init()`:

* Fires when cluster size exceeds unique hosts in the hosts file
* Shows which hosts would receive duplicate instances
* Offers three options:
  + `[1]` Enter a host address manually
  + `[2]` Continue anyway
  + `[3]` Abort

Also adds `addHost()` method to `ClusterManager` for adding hosts post-init.

## Patch 3 — Manifest Support

Adds `--manifest` flag to `cluster-create`.

Manifest format:

```
[
  {"address": "rHostA...", "instances": 2},
  {"address": "rHostB...", "instances": 1},
  {"address": "rHostC...", "instances": 1}
]
```

Usage:

```
evdevkit cluster-create 4 ./contract /usr/bin/node ./hosts.txt \
  --manifest manifest.json \
  -a index.js \
  -m 3
```

* Cluster size is calculated automatically from manifest totals
* Hosts file is still required but ignored when manifest is provided
* Patch 2 warning is suppressed in manifest mode
* Exact host order is preserved — no sorting applied

## Finding Available Hosts

Before deploying, verify your chosen hosts have sufficient funds to transact
acquisition, available slots and sufficient capacity. Poor host selection is a
leading cause of cluster failures.

**Option 1 — Use the Evernode Host Discovery website:**

Visit [api.onledger.net](https://api.onledger.net) to browse and filter active
hosts by reputation, available slots, RAM, country, and lease cost.

**Option 2 — Query the API directly:**

```
# Get hosts with at least 1 available slot, sorted by reputation
curl "https://api.onledger.net/hosts?active=true&minSlots=1&minRep=200&sortBy=hostReputation&sortDir=desc&limit=20"
```

**Option 3 — Check specific hosts via Node.js before deploying:**

```js
const evernode = require('/usr/lib/node_modules/evdevkit/node_modules/evernode-js-client');

async function checkHosts(addresses) {
    await evernode.Defaults.useNetwork('mainnet');
    const registry = await evernode.HookClientFactory.create(evernode.HookTypes.registry);
    await registry.connect();

    for (const addr of addresses) {
        const h = await registry.getHostInfo(addr);
        console.log(
            addr.slice(0, 10) +
            ' active:' + h?.active +
            ' available:' + (h?.maxInstances - h?.activeInstances) +
            ' rep:' + h?.hostReputation
        );
    }

    await registry.disconnect();
}

checkHosts([
    'rHostA...',
    'rHostB...',
    'rHostC...'
]).catch(console.error);
```

Run with:

```
node check-hosts.js
```

A host is suitable if:

* `active: true`
* `available` >= number of instances you plan to deploy to it
* reputation score > 200 (max 252)

## Hosts File

A hosts file is required by `evdevkit cluster-create` in all modes. It is a
plain text file with one XRPL host address per line:

```
rnpkkEEMDSYAg1G6eHWF66kKjrKoAqMbtV
rfmpN9NadH6fKSqKrHEsBvXGoK3Gjewd5h
rGrA1StQTrjiAbxgxJdEVkPgY3k3BosFBn
```

A natural place to store it is alongside your contract directory:

```
my-project/
├── contract/
├── hosts.txt
└── manifest.json
```

Pass it to `cluster-create` as the `hosts-file-path` argument:

```
evdevkit cluster-create 3 ./contract /usr/bin/node ./hosts.txt -a index.js -m 3
```

**In manifest mode** — the hosts file is still required as a positional
argument but its contents are ignored. The manifest defines the actual host
layout. You can pass any valid hosts file as a placeholder.

## Manifest File

The manifest JSON file can be stored anywhere — pass the full path via
`--manifest`. A natural place is alongside your contract and hosts file:

```
my-project/
├── contract/
├── hosts.txt           ← placeholder (required but ignored in manifest mode)
└── manifest.json       ← defines exact host:instance layout
```

Example manifest deploying 4 instances across 3 hosts:

```json
[
  {"address": "rnpkkEEMDSYAg1G6eHWF66kKjrKoAqMbtV", "instances": 2},
  {"address": "rfmpN9NadH6fKSqKrHEsBvXGoK3Gjewd5h", "instances": 1},
  {"address": "rGrA1StQTrjiAbxgxJdEVkPgY3k3BosFBn", "instances": 1}
]
```

The cluster size is automatically calculated from the manifest totals — in the
above example that is 4 instances. The `cluster-create` size argument is ignored
in manifest mode.

Full example command:

```
evdevkit cluster-create 4 ./contract /usr/bin/node ./hosts.txt \
  --manifest ./manifest.json \
  -a index.js \
  -m 3
```

## Revert

```
# Revert all patches
./revert-all.sh

# With custom path
./revert-all.sh /your/path/to/evdevkit
```

Each patch script also prints its specific revert command on completion, e.g.:

```
Revert: cp /usr/lib/node_modules/evdevkit/index.js.backup-patch1-20260425-233526 /usr/lib/node_modules/evdevkit/index.js
```

## Status

Tested on evdevkit **v0.7.21** on Linux (Parrot OS / Ubuntu).

Confirmed working: 3-node cluster-create deploying to 3 unique hosts with no
duplication after patch 1 applied.

> **Note on package structure:** evdevkit v0.7.21 (and likely all versions) is
> distributed as a bundled npm package — all source code is compiled into a
> single `index.js`. The patch scripts have been updated to target this file
> directly. If you are on an older version of evdevkit where `lib/cluster-manager.js`
> exists as a separate file, pass your evdevkit path explicitly and the scripts
> will find the correct target automatically.

Awaiting broader community testing before submitting PR to EvernodeXRPL/ev-devkit.

## Related

* [EvernodeXRPL/ev-devkit issue #68](https://github.com/EvernodeXRPL/ev-devkit/issues/68)
* [Evernode Host Discovery API](https://api.onledger.net)
* [Evernode Cluster Manager](https://github.com/rippleitinnz/evernode-cluster-manager)
