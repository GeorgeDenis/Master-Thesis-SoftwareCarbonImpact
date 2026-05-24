#!/usr/bin/env bash
# scripts/run_experiment.sh
#
# Slice 1 orchestrator. Runs the full experimental matrix locally:
#   scenarios x configurations x load_levels x repeats
#
# Default matrix:
#   scenarios:      s1 s2 s3 s4 s5
#   configurations: baseline optimized
#   load_levels:    10 50 80   (concurrent users)
#   repeats:        3            (per cell)
#
# Total runs by default: 5 * 2 * 3 * 3 = 90 cells.
# At ~150 s per cell (30 warm-up + 60 measure + 60 cool-down), that is ~3.75 hours.
# Override --runs to 1 first to validate end-to-end before committing the full sweep.
#
# Outputs a single tidy CSV with one row per cell:
#   timestamp, scenario, config, users, run, duration_s, requests_total, errors,
#   p50_ms, p95_ms, p99_ms, throughput_rps, energy_kwh, co2_kg, co2_per_req_mg
#
# Prerequisites checked at startup: dotnet, jmeter, jq, sidecar reachable, API reachable.

set -euo pipefail
# shopt -s lastpipe  # Not needed for this script; commented out for zsh compatibility

# ---------- defaults --------------------------------------------------------
RUNS=3
SCENARIOS=(s1 s2 s3 s4 s5)
CONFIGS=(baseline optimized)
LOADS=(10 50 80)
WARMUP_S=30
MEASURE_S=60
COOLDOWN_S=60
API_URL="${API_URL:-http://localhost:5000}"
SIDECAR_URL="${SIDECAR_URL:-http://localhost:5055}"
RESULTS_DIR="${RESULTS_DIR:-$(pwd)/results}"
JMETER_BIN="${JMETER_BIN:-jmeter}"
JMETER_PLAN_DIR="${JMETER_PLAN_DIR:-$(pwd)/../jmeter}"
OUTPUT_CSV=""
RESTART_API_BETWEEN_CONFIGS=true

# ---------- parse args ------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --runs) RUNS="$2"; shift 2 ;;
        --output) OUTPUT_CSV="$2"; shift 2 ;;
        --scenarios) IFS=, read -r -a SCENARIOS <<< "$2"; shift 2 ;;
        --loads) IFS=, read -r -a LOADS <<< "$2"; shift 2 ;;
        --configs) IFS=, read -r -a CONFIGS <<< "$2"; shift 2 ;;
        --measure-s) MEASURE_S="$2"; shift 2 ;;
        --warmup-s) WARMUP_S="$2"; shift 2 ;;
        --cooldown-s) COOLDOWN_S="$2"; shift 2 ;;
        --api-url) API_URL="$2"; shift 2 ;;
        --sidecar-url) SIDECAR_URL="$2"; shift 2 ;;
        --plan-dir) JMETER_PLAN_DIR="$2"; shift 2 ;;
        -h|--help)
            sed -n '1,40p' "$0"; exit 0 ;;
        *) echo "Unknown arg: $1"; exit 1 ;;
    esac
done

mkdir -p "$RESULTS_DIR"
if [[ -z "$OUTPUT_CSV" ]]; then
    OUTPUT_CSV="$RESULTS_DIR/local_$(date +%Y%m%d_%H%M%S).csv"
fi
JTL_DIR="$RESULTS_DIR/jtl_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$JTL_DIR"

# ---------- preflight -------------------------------------------------------
echo "[orchestrator] preflight..."
command -v "$JMETER_BIN" >/dev/null || { echo "jmeter not found"; exit 2; }
command -v jq >/dev/null            || { echo "jq not found"; exit 2; }
command -v curl >/dev/null          || { echo "curl not found"; exit 2; }
curl -sf "$API_URL/health" >/dev/null      || { echo "API not reachable at $API_URL"; exit 2; }
curl -sf "$SIDECAR_URL/health" >/dev/null  || { echo "Sidecar not reachable at $SIDECAR_URL"; exit 2; }
for _s in "${SCENARIOS[@]}"; do
    [[ -f "$JMETER_PLAN_DIR/${_s}.jmx" ]] || { echo "JMeter plan not found: $JMETER_PLAN_DIR/${_s}.jmx"; exit 2; }
done

echo "[orchestrator] output CSV:  $OUTPUT_CSV"
echo "[orchestrator] JTL dir:     $JTL_DIR"
echo "[orchestrator] scenarios:   ${SCENARIOS[*]}"
echo "[orchestrator] configs:     ${CONFIGS[*]}"
echo "[orchestrator] loads:       ${LOADS[*]}"
echo "[orchestrator] repeats:     $RUNS"

# ---------- write CSV header ------------------------------------------------
echo "timestamp_utc,scenario,config,users,run,duration_s,requests_total,errors,p50_ms,p95_ms,p99_ms,throughput_rps,energy_kwh,co2_kg,co2_per_req_mg" > "$OUTPUT_CSV"

# ---------- helpers ---------------------------------------------------------
apply_config_for_scenario() {
    local scenario="$1" config="$2"
    # S3 needs a DB-level toggle; the others are environment-variable toggles for the API.
    # For local slice 1 we assume the API has been restarted with the right env when needed.
    # The orchestrator only handles the DB index toggle here.
    if [[ "$scenario" == "s3" ]]; then
        if [[ "$config" == "optimized" ]]; then
            PGPASSWORD=petrescue psql -h localhost -p 5433 -U petrescue -d petrescue -q -f "$(dirname "$0")/../sql/02_index_apply.sql"
        else
            PGPASSWORD=petrescue psql -h localhost -p 5433 -U petrescue -d petrescue -q -f "$(dirname "$0")/../sql/02_index_drop.sql"
        fi
    fi
}

compute_percentiles_from_jtl() {
    # JMeter JTL CSV format with field names. We pull 'elapsed' (response time in ms)
    # and 'success'. Then compute total, errors, p50/p95/p99, throughput.
    local jtl="$1"
    local duration_s="$2"
    # Use Python for the math; jq cannot do percentiles natively.
    python3 - <<EOF
import csv
import sys
import statistics as stats

rows = []
errors = 0
with open("$jtl", newline="") as f:
    reader = csv.DictReader(f)
    for r in reader:
        try:
            e = float(r["elapsed"])
        except Exception:
            continue
        rows.append(e)
        if r.get("success", "true") != "true":
            errors += 1

total = len(rows)
if total == 0:
    print("0,0,0,0,0,0")
    sys.exit(0)

rows_sorted = sorted(rows)
def pct(p):
    k = max(0, min(total - 1, int(round(p/100.0 * (total - 1)))))
    return rows_sorted[k]

p50 = pct(50)
p95 = pct(95)
p99 = pct(99)
throughput = total / $duration_s if $duration_s > 0 else 0.0
print(f"{total},{errors},{p50:.1f},{p95:.1f},{p99:.1f},{throughput:.3f}")
EOF
}

run_one_cell() {
    local scenario="$1" config="$2" users="$3" run="$4"
    local cell="${scenario}_${config}_${users}u_r${run}"
    local jtl="$JTL_DIR/${cell}.jtl"
    local exp_name="$cell"

    echo ""
    echo "============================================================"
    echo "[cell] scenario=$scenario config=$config users=$users run=$run"
    echo "============================================================"

    # 1. Warm-up phase: short JMeter run at low load, discarded.
    echo "[cell] warm-up ${WARMUP_S}s..."
    "$JMETER_BIN" -n -t "$JMETER_PLAN_DIR/${scenario}.jmx" \
        -Jusers=3 \
        -JrampUp=1 \
        -Jduration="$WARMUP_S" \
        -JbaseUrl="$API_URL" \
        -JresultFile="/tmp/petrescue_warmup.jtl" \
        > "$JTL_DIR/${cell}_warmup.log" 2>&1

    # 2. Start the CodeCarbon sidecar tracker.
    echo "[cell] starting tracker..."
    curl -sf -X POST "$SIDECAR_URL/start" \
        -H 'Content-Type: application/json' \
        -d "{\"experiment_name\":\"$exp_name\"}" > /dev/null

    local started_at_utc
    started_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # 3. Measurement window: real load test.
    echo "[cell] measuring ${MEASURE_S}s at $users users..."
    "$JMETER_BIN" -n -t "$JMETER_PLAN_DIR/${scenario}.jmx" \
        -Jusers="$users" \
        -JrampUp=5 \
        -Jduration="$MEASURE_S" \
        -JbaseUrl="$API_URL" \
        -JresultFile="$jtl" \
        > "$JTL_DIR/${cell}.log" 2>&1

    # 4. Stop the tracker, capture emissions.
    echo "[cell] stopping tracker..."
    local stop_response
    stop_response=$(curl -sf -X POST "$SIDECAR_URL/stop")
    local emissions_kg
    emissions_kg=$(echo "$stop_response" | jq -r '.emissions_kg // 0')

    # CodeCarbon's CSV is the source of truth for energy. Read the last row of
    # ./emissions/<exp_name>.csv to get duration, energy_consumed, emissions in kWh / kg.
    local cc_csv="$(dirname "$0")/../sidecar/emissions/${exp_name}.csv"
    local duration_s energy_kwh co2_kg
    if [[ -f "$cc_csv" ]]; then
        # CodeCarbon header (varies a little by version, we use python to parse robustly)
        read duration_s energy_kwh co2_kg < <(python3 - <<EOF
import csv
with open("$cc_csv") as f:
    rows = list(csv.DictReader(f))
if not rows:
    print("0 0 0"); raise SystemExit
last = rows[-1]
# Common columns: duration, energy_consumed, emissions
print(last.get("duration", "0"), last.get("energy_consumed", "0"), last.get("emissions", "0"))
EOF
        )
    else
        duration_s=0; energy_kwh=0; co2_kg="$emissions_kg"
    fi

    # 5. Parse the JTL for request stats.
    local stats
    stats=$(compute_percentiles_from_jtl "$jtl" "$duration_s")
    local requests_total errors p50_ms p95_ms p99_ms throughput_rps
    IFS=',' read -r requests_total errors p50_ms p95_ms p99_ms throughput_rps <<< "$stats"

    # Sanitize co2_kg in case CodeCarbon wrote an empty string or NaN to the CSV
    if [[ -z "$co2_kg" || "$co2_kg" == "NaN" || "$co2_kg" == "null" || "$co2_kg" == "None" ]]; then
        co2_kg="0"
    fi

    # 6. Per-request CO2 in mg.
    local co2_per_req_mg
    co2_per_req_mg=$(python3 -c "
try:
    c = float('$co2_kg')
except ValueError:
    c = 0.0
print(f'{(c * 1e6 / max(int($requests_total),1)):.4f}')
")

    # 7. Append a row to the tidy CSV.
    echo "$started_at_utc,$scenario,$config,$users,$run,$duration_s,$requests_total,$errors,$p50_ms,$p95_ms,$p99_ms,$throughput_rps,$energy_kwh,$co2_kg,$co2_per_req_mg" >> "$OUTPUT_CSV"

    echo "[cell] result: requests=$requests_total errors=$errors p95=${p95_ms}ms throughput=${throughput_rps}rps co2=${co2_kg}kg co2/req=${co2_per_req_mg}mg"

    # 8. Cool-down before the next cell.
    echo "[cell] cool-down ${COOLDOWN_S}s..."
    sleep "$COOLDOWN_S"
}

# ---------- run the matrix -------------------------------------------------
# We RANDOMIZE the order of (scenario, config, users, run) tuples to reduce systematic
# bias from thermal drift or background load.

declare -a CELLS
for s in "${SCENARIOS[@]}"; do
    for c in "${CONFIGS[@]}"; do
        for u in "${LOADS[@]}"; do
            for r in $(seq 1 "$RUNS"); do
                CELLS+=("$s|$c|$u|$r")
            done
        done
    done
done

# Shuffle with awk so we don't depend on shuf being available on macOS by default.
echo "[orchestrator] total cells: ${#CELLS[@]}"
CELLS_SHUFFLED=$(printf "%s\n" "${CELLS[@]}" | awk 'BEGIN{srand(42)} {print rand() "\t" $0}' | sort -k1,1 | cut -f2-)

while IFS='|' read -r scenario config users run; do
    [[ -z "$scenario" ]] && continue
    apply_config_for_scenario "$scenario" "$config"
    run_one_cell "$scenario" "$config" "$users" "$run"
done <<< "$CELLS_SHUFFLED"

echo ""
echo "[orchestrator] complete. results: $OUTPUT_CSV"
echo "[orchestrator] cells: $(($(wc -l < "$OUTPUT_CSV") - 1))"
