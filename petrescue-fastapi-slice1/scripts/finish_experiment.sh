#!/usr/bin/env bash
# Waits for the optimized run to finish (45 rows), then combines CSVs and prints CV analysis.
set -euo pipefail

RESULTS_DIR="/results"
BASELINE_CSV="$RESULTS_DIR/local_baseline_20260516_180946.csv"
OPTIMIZED_CSV="$RESULTS_DIR/local_optimized_20260517_004644.csv"
COMBINED_CSV="$RESULTS_DIR/local_combined_$(date +%Y%m%d).csv"
DONE_MARKER="/tmp/experiment_done.txt"

echo "[finish] waiting for optimized run to complete (need 46 lines in CSV)..."

while true; do
    if [[ -f "$OPTIMIZED_CSV" ]]; then
        lines=$(wc -l < "$OPTIMIZED_CSV")
        echo "[finish] $(date '+%H:%M:%S') optimized CSV lines: $lines / 46"
        if [[ "$lines" -ge 46 ]]; then
            echo "[finish] optimized run complete!"
            break
        fi
    else
        echo "[finish] $(date '+%H:%M:%S') optimized CSV not yet created"
    fi
    sleep 60
done

# Combine
echo "[finish] combining CSVs..."
head -1 "$BASELINE_CSV" > "$COMBINED_CSV"
tail -n +2 "$BASELINE_CSV" >> "$COMBINED_CSV"
tail -n +2 "$OPTIMIZED_CSV" >> "$COMBINED_CSV"
total_lines=$(wc -l < "$COMBINED_CSV")
echo "[finish] combined CSV: $COMBINED_CSV ($total_lines lines, expected 91)"

# CV analysis
echo "[finish] running CV analysis..."
python3 - <<EOF
import csv, statistics as s
from collections import defaultdict

groups = defaultdict(list)
with open("$COMBINED_CSV") as f:
    for r in csv.DictReader(f):
        key = (r["scenario"], r["config"], r["users"])
        groups[key].append(float(r["co2_per_req_mg"]))

print(f"{'scenario':<6} {'config':<10} {'users':<6} {'mean_mg':>8} {'sd_mg':>8} {'cv':>7}  {'n':>3}")
print("-" * 58)
for k, vs in sorted(groups.items()):
    m = s.mean(vs)
    sd = s.stdev(vs) if len(vs) > 1 else 0.0
    cv = sd / m if m else 0
    flag = " *** HIGH CV" if cv > 0.30 else (" * check" if cv > 0.15 else "")
    print(f"{k[0]:<6} {k[1]:<10} {k[2]:<6} {m:>8.3f} {sd:>8.3f} {cv:>7.1%}  {len(vs):>3}{flag}")
EOF

echo "[finish] all done. Results in: $COMBINED_CSV"
echo "[finish] $(date)" | tee "$DONE_MARKER"
