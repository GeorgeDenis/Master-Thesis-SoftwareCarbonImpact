#!/usr/bin/env bash
# scripts/run_full.sh
#
# Single entry point for the full experiment pipeline.
# The ONE command you run after SSH-ing into the VM.
#
# Usage:
#   bash scripts/run_full.sh
#   bash scripts/run_full.sh --cpulimit 50
#   bash scripts/run_full.sh --configs baseline,optimized --scenarios s1,s2,s3 --loads 10,50 --runs 1
#
# Flow:
#   1. bootstrap.sh    (idempotent setup)
#   2. Start sidecar   (CodeCarbon energy tracker)
#   3. For each config:
#      a. start_api.sh --config $config [--cpulimit N]
#      b. Apply/drop S3 index if needed
#      c. run_experiment.sh --configs $config [--scenarios ...] [--loads ...] [--runs ...]
#      d. start_api.sh --stop
#   4. Stop sidecar
#   5. Print summary

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

# ---------- defaults --------------------------------------------------------
CPULIMIT=""
CONFIGS="baseline,optimized"
SCENARIOS=""
LOADS=""
RUNS=""

# ---------- parse args ------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --cpulimit)  CPULIMIT="$2"; shift 2 ;;
        --configs)   CONFIGS="$2"; shift 2 ;;
        --scenarios) SCENARIOS="$2"; shift 2 ;;
        --loads)     LOADS="$2"; shift 2 ;;
        --runs)      RUNS="$2"; shift 2 ;;
        -h|--help)
            sed -n '1,20p' "$0"; exit 0 ;;
        *) echo "[run_full] unknown arg: $1"; exit 1 ;;
    esac
done

IFS=',' read -r -a CONFIG_ARRAY <<< "$CONFIGS"

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║        PetRescue Flask Slice 1 — Full Experiment        ║"
echo "╠══════════════════════════════════════════════════════════╣"
echo "║  configs:   ${CONFIGS}"
echo "║  scenarios: ${SCENARIOS:-s1,s2,s3,s4,s5 (default)}"
echo "║  loads:     ${LOADS:-10,50,80 (default)}"
echo "║  runs:      ${RUNS:-3 (default)}"
echo "║  cpulimit:  ${CPULIMIT:-none}"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

SECONDS=0

# ---------- 1. Bootstrap ----------------------------------------------------
echo "[run_full] ===== STEP 1: Bootstrap ====="
bash "$SCRIPT_DIR/bootstrap.sh"

# ---------- 2. Start sidecar ------------------------------------------------
echo ""
echo "[run_full] ===== STEP 2: Start CodeCarbon sidecar ====="

# Kill any leftover sidecar
if [[ -f /tmp/sidecar.pid ]]; then
    OLD_PID=$(cat /tmp/sidecar.pid)
    sudo kill "$OLD_PID" 2>/dev/null || true
    rm -f /tmp/sidecar.pid
    sleep 1
fi

echo "[run_full] starting sidecar (sudo required for energy readings)..."
sudo "$PROJECT_ROOT/sidecar/.venv/bin/python" "$PROJECT_ROOT/sidecar/sidecar.py" \
    > /tmp/sidecar.log 2>&1 &
SIDECAR_PID=$!
echo "$SIDECAR_PID" > /tmp/sidecar.pid
echo "[run_full] sidecar PID=$SIDECAR_PID"

# Wait for sidecar health
echo "[run_full] waiting for sidecar health on http://localhost:5055/health ..."
MAX_WAIT=30
SIDECAR_HEALTHY=false
for i in $(seq 1 $MAX_WAIT); do
    if curl -sf http://localhost:5055/health > /dev/null 2>&1; then
        echo "[run_full] sidecar is healthy (attempt $i/$MAX_WAIT)"
        SIDECAR_HEALTHY=true
        break
    fi
    sleep 1
done

if [[ "$SIDECAR_HEALTHY" != "true" ]]; then
    echo "[run_full] ERROR: sidecar did not become healthy after ${MAX_WAIT}s"
    echo "[run_full] sidecar log:"
    tail -20 /tmp/sidecar.log 2>/dev/null || true
    exit 1
fi

# ---------- 3. Run experiment per config ------------------------------------
for config in "${CONFIG_ARRAY[@]}"; do
    echo ""
    echo "[run_full] ═══════════════════════════════════════════════"
    echo "[run_full]  CONFIG: $config"
    echo "[run_full] ═══════════════════════════════════════════════"
    echo ""

    # 3a. Start the API with correct toggles
    START_API_ARGS=(--config "$config")
    if [[ -n "$CPULIMIT" ]]; then
        START_API_ARGS+=(--cpulimit "$CPULIMIT")
    fi
    echo "[run_full] starting API: ${START_API_ARGS[*]}"
    bash "$SCRIPT_DIR/start_api.sh" "${START_API_ARGS[@]}"

    # 3b. S3 index toggling (DB-level optimization)
    if [[ "$config" == "optimized" ]]; then
        echo "[run_full] applying S3 index for optimized config..."
        PGPASSWORD=petrescue psql -h localhost -p 5433 -U petrescue -d petrescue -q \
            -f "$PROJECT_ROOT/sql/02_index_apply.sql"
    else
        echo "[run_full] dropping S3 index for baseline config..."
        PGPASSWORD=petrescue psql -h localhost -p 5433 -U petrescue -d petrescue -q \
            -f "$PROJECT_ROOT/sql/02_index_drop.sql"
    fi

    # 3c. Run experiment for this config
    EXPERIMENT_ARGS=(--configs "$config")
    if [[ -n "$SCENARIOS" ]]; then
        EXPERIMENT_ARGS+=(--scenarios "$SCENARIOS")
    fi
    if [[ -n "$LOADS" ]]; then
        EXPERIMENT_ARGS+=(--loads "$LOADS")
    fi
    if [[ -n "$RUNS" ]]; then
        EXPERIMENT_ARGS+=(--runs "$RUNS")
    fi
    EXPERIMENT_ARGS+=(--plan-dir "$PROJECT_ROOT/jmeter")

    echo "[run_full] running experiment: ${EXPERIMENT_ARGS[*]}"
    bash "$SCRIPT_DIR/run_experiment.sh" "${EXPERIMENT_ARGS[@]}"

    # 3d. Stop the API
    echo "[run_full] stopping API..."
    bash "$SCRIPT_DIR/start_api.sh" --stop
    sleep 2
done

# ---------- 4. Stop sidecar -------------------------------------------------
echo ""
echo "[run_full] ===== STEP 4: Stop sidecar ====="
if [[ -f /tmp/sidecar.pid ]]; then
    SIDECAR_PID=$(cat /tmp/sidecar.pid)
    echo "[run_full] killing sidecar PID=$SIDECAR_PID"
    sudo kill "$SIDECAR_PID" 2>/dev/null || true
    rm -f /tmp/sidecar.pid
else
    echo "[run_full] no sidecar pidfile found"
fi

# ---------- 5. Summary ------------------------------------------------------
ELAPSED=$SECONDS
HOURS=$((ELAPSED / 3600))
MINUTES=$(( (ELAPSED % 3600) / 60 ))
SECS=$((ELAPSED % 60))

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║                  EXPERIMENT COMPLETE                    ║"
echo "╠══════════════════════════════════════════════════════════╣"
echo "║  Total time:  ${HOURS}h ${MINUTES}m ${SECS}s"
echo "║  Results dir: $PROJECT_ROOT/results/"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "[run_full] CSV files:"
ls -la "$PROJECT_ROOT/results/"*.csv 2>/dev/null || echo "  (no CSV files found)"
echo ""
echo "[run_full] done."
