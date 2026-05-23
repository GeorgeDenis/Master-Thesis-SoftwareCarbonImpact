#!/usr/bin/env bash
# scripts/prepare_data.sh
# Generate the auxiliary input files that S2 and S4 need.
#   - /tmp/petrescue_microchips.txt    1,000,000 lines for the S4 file-scan
#   - /tmp/petrescue_s2_body.json      a JSON request body with 20,000 microchip codes for S2
#
# These are large but compressible-friendly text files. Total ~30 MB on disk.

set -euo pipefail

MICROCHIP_FILE="${MICROCHIP_FILE:-/tmp/petrescue_microchips.txt}"
S2_BODY="${S2_BODY:-/tmp/petrescue_s2_body.json}"
SEED="${SEED:-42}"

echo "[prepare_data] target file:  $MICROCHIP_FILE"
echo "[prepare_data] target body:  $S2_BODY"

# 1M-line file. We include exactly one CHIP-TARGET-MARKER somewhere late in the file
# so the baseline path scans most of it.
python3 - <<EOF
import random
random.seed($SEED)
N = 1_000_000
target_line = N - 1000   # marker placed ~near the end
with open("$MICROCHIP_FILE", "w") as f:
    for i in range(N):
        if i == target_line:
            f.write("CHIP-TARGET-MARKER\n")
        else:
            f.write(f"MC-{i:08d}\n")
print(f"wrote {N:,} lines to $MICROCHIP_FILE")
EOF

# JSON body for S2. We include 20,000 microchip codes, half of which match the seed data,
# half of which are misses. This forces the baseline list-scan to walk the whole list.
python3 - <<EOF
import json, random
random.seed($SEED + 1)
hits = [f"MC-{n:08d}" for n in random.sample(range(1, 10000), 5000)]
# we want ~20k inputs. Half hits (5000 unique hits, plus 5000 dupes), half misses.
hits_repeat = hits * 2   # 10000 total hits (with duplicates)
misses = [f"MC-{99000000 + i:08d}" for i in range(10000)]
codes = hits_repeat + misses
random.shuffle(codes)
with open("$S2_BODY", "w") as f:
    json.dump({"codes": codes}, f)
print(f"wrote S2 body with {len(codes):,} codes to $S2_BODY")
EOF

echo "[prepare_data] done."
