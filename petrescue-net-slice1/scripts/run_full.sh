#!/usr/bin/env bash
# scripts/run_full.sh
#
# Single entry point for the PetRescue .NET Slice 1 experiment.
# This is the ONE command you run after SSH-ing into the VM.
#
# Usage:
#   ./scripts/run_full.sh
#   ./scripts/run_full.sh --cpulimit 50
#   ./scripts/run_full.sh --configs baseline --scenarios s1,s2 --loads 10,50 --runs 1
#   ./scripts/run_full.sh --configs baseline,optimized --scenarios s1,s2,s3,s4,s5 --loads 10,50,80 --runs 3

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

# ---------- defaults --------------------------------------------------------
CPULIMIT=""
CONFIGS="baseline,optimized"
SCENARIOS="s1,s2,s3,s4,s5"
LOADS="10,50,80"
RUNS="3"

# ---------- parse args ------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --cpulimit)  CPULIMIT="$2"; shift 2 ;;
        --configs)   CONFIGS="$2"; shift 2 ;;
        --scenarios) SCENARIOS="$2"; shift 2 ;;
        --loads)     LOADS="$2"; shift 2 ;;
        --runs)      RUNS="$2"; shift 2 ;;
        -h|--help)
            sed -n '1,14p' "$0"; exit 0 ;;
        *) echo "[run_full] unknown arg: $1"; exit 1 ;;
    esac
done

# Split CONFIGS into an array
IFS=',' read -r -a CONFIG_ARRAY <<< "$CONFIGS"

SIDECAR_PID_FILE="/tmp/sidecar.pid"

echo ""
echo "================================================================"
echo "[run_full] PetRescue .NET Slice 1 — Full Experiment"
echo "================================================================"
echo "[run_full] configs:   ${CONFIG_ARRAY[*]}"
echo "[run_full] scenarios: $SCENARIOS"
echo "[run_full] loads:     $LOADS"
echo "[run_full] runs:      $RUNS"
echo "[run_full] cpulimit:  ${CPULIMIT:-none}"
echo ""

# Record start time
SECONDS=0

# ---------- 1. Bootstrap ----------------------------------------------------
echo "[run_full] === Step 1: Bootstrap ==="
bash "$SCRIPT_DIR/bootstrap.sh"

# ---------- 2. Start sidecar ------------------------------------------------
echo ""
echo "[run_full] === Step 2: Starting sidecar ==="

# Kill any existing sidecar first
if [[ -f "$SIDECAR_PID_FILE" ]]; then
    OLD_PID=$(cat "$SIDECAR_PID_FILE")
    if sudo kill -0 "$OLD_PID" 2>/dev/null; then
        echo "[run_full] killing existing sidecar (PID $OLD_PID)..."
        sudo kill "$OLD_PID" 2>/dev/null || true
        sleep 2
    fi
    rm -f "$SIDECAR_PID_FILE"
fi

sudo "$PROJECT_ROOT/sidecar/.venv/bin/python" "$PROJECT_ROOT/sidecar/sidecar.py" \
    > /tmp/sidecar.log 2>&1 &
SIDECAR_PID=$!
echo "$SIDECAR_PID" > "$SIDECAR_PID_FILE"
echo "[run_full] sidecar PID: $SIDECAR_PID"

# Wait for sidecar health
echo "[run_full] waiting for sidecar health..."
MAX_ATTEMPTS=30
for i in $(seq 1 $MAX_ATTEMPTS); do
    if curl -sf http://localhost:5055/health > /dev/null 2>&1; then
        echo "[run_full] sidecar healthy (attempt $i/$MAX_ATTEMPTS)"
        break
    fi
    if [[ $i -eq $MAX_ATTEMPTS ]]; then
        echo "[run_full] ERROR: sidecar not healthy after ${MAX_ATTEMPTS}s"
        echo "[run_full] check /tmp/sidecar.log for errors"
        sudo kill "$SIDECAR_PID" 2>/dev/null || true
        rm -f "$SIDECAR_PID_FILE"
        exit 1
    fi
    sleep 1
done

# ---------- 3. Run experiment for each config --------------------------------
TOTAL_CONFIGS=${#CONFIG_ARRAY[@]}
CONFIG_NUM=0

for config in "${CONFIG_ARRAY[@]}"; do
    CONFIG_NUM=$((CONFIG_NUM + 1))
    echo ""
    echo "================================================================"
    echo "[run_full] === Config $CONFIG_NUM/$TOTAL_CONFIGS: $config ==="
    echo "================================================================"

    # --- Start the API with the right config ---
    START_API_ARGS=(--config "$config")
    if [[ -n "$CPULIMIT" ]]; then
        START_API_ARGS+=(--cpulimit "$CPULIMIT")
    fi
    bash "$SCRIPT_DIR/start_api.sh" "${START_API_ARGS[@]}"

    # --- Handle S3 index state for this config ---
    # If scenarios include s3, set the correct index state.
    # For baseline: ensure index is DROPPED
    # For optimized: ensure index is APPLIED
    if echo "$SCENARIOS" | grep -q "s3"; then
        if [[ "$config" == "optimized" ]]; then
            echo "[run_full] applying S3 index for optimized config..."
            PGPASSWORD=petrescue psql -h localhost -p 5433 -U petrescue -d petrescue -q \
                -f sql/02_index_apply.sql
        else
            echo "[run_full] dropping S3 index for baseline config..."
            PGPASSWORD=petrescue psql -h localhost -p 5433 -U petrescue -d petrescue -q \
                -f sql/02_index_drop.sql
        fi
    fi

    # --- Run the experiment for this config ---
    echo "[run_full] running experiment for config=$config..."
    bash "$SCRIPT_DIR/run_experiment.sh" \
        --configs "$config" \
        --scenarios "$SCENARIOS" \
        --loads "$LOADS" \
        --runs "$RUNS" \
        --plan-dir "$PROJECT_ROOT/jmeter"

    # --- Stop the API ---
    bash "$SCRIPT_DIR/start_api.sh" --stop
done

# ---------- 4. Stop sidecar -------------------------------------------------
echo ""
echo "[run_full] === Cleanup ==="
echo "[run_full] stopping sidecar..."
if [[ -f "$SIDECAR_PID_FILE" ]]; then
    SIDECAR_PID=$(cat "$SIDECAR_PID_FILE")
    sudo kill "$SIDECAR_PID" 2>/dev/null || true
    rm -f "$SIDECAR_PID_FILE"
    echo "[run_full] sidecar stopped"
else
    echo "[run_full] no sidecar pidfile found"
fi

# ---------- 5. Final summary ------------------------------------------------
ELAPSED=$SECONDS
ELAPSED_MIN=$((ELAPSED / 60))
ELAPSED_SEC=$((ELAPSED % 60))

echo ""
echo "================================================================"
echo "[run_full] EXPERIMENT COMPLETE"
echo "================================================================"
echo "[run_full] total time: ${ELAPSED_MIN}m ${ELAPSED_SEC}s"
echo "[run_full] results directory: $PROJECT_ROOT/results/"
echo ""

# List CSV files
if ls "$PROJECT_ROOT/results/"*.csv 1>/dev/null 2>&1; then
    echo "[run_full] CSV files:"
    ls -lh "$PROJECT_ROOT/results/"*.csv
else
    echo "[run_full] no CSV files found in results/"
fi

echo ""
echo "[run_full] done!"
