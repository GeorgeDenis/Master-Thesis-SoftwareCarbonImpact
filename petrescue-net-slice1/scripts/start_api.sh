#!/usr/bin/env bash
# scripts/start_api.sh
#
# Starts (or stops) the PetRescue .NET API with the correct toggle env vars.
#
# Usage:
#   start_api.sh --config baseline [--cpulimit 50] [--pidfile /tmp/dotnet_api.pid]
#   start_api.sh --config optimized [--cpulimit 50]
#   start_api.sh --stop [--pidfile /tmp/dotnet_api.pid]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

CONFIG=""
CPULIMIT=""
PIDFILE="/tmp/dotnet_api.pid"
STOP_MODE=false

# ---------- parse args ------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --config)   CONFIG="$2"; shift 2 ;;
        --cpulimit) CPULIMIT="$2"; shift 2 ;;
        --pidfile)  PIDFILE="$2"; shift 2 ;;
        --stop)     STOP_MODE=true; shift ;;
        -h|--help)
            sed -n '1,12p' "$0"; exit 0 ;;
        *) echo "[start_api] unknown arg: $1"; exit 1 ;;
    esac
done

# ---------- stop mode -------------------------------------------------------
if [[ "$STOP_MODE" == true ]]; then
    echo "[start_api] stopping API..."
    if [[ -f "$PIDFILE" ]]; then
        PID=$(cat "$PIDFILE")
        if kill -0 "$PID" 2>/dev/null; then
            # Kill child processes first, then the main process
            pkill -P "$PID" 2>/dev/null || true
            kill "$PID" 2>/dev/null || true
            # Wait for the process to actually exit
            for _i in $(seq 1 10); do
                if ! kill -0 "$PID" 2>/dev/null; then
                    break
                fi
                sleep 1
            done
            # Force kill if still alive
            if kill -0 "$PID" 2>/dev/null; then
                kill -9 "$PID" 2>/dev/null || true
                pkill -9 -P "$PID" 2>/dev/null || true
            fi
            echo "[start_api] process $PID stopped"
        else
            echo "[start_api] PID $PID not running"
        fi
        rm -f "$PIDFILE"
    else
        echo "[start_api] no pidfile found at $PIDFILE"
    fi
    exit 0
fi

# ---------- validate --------------------------------------------------------
if [[ -z "$CONFIG" ]]; then
    echo "[start_api] ERROR: --config is required (baseline|optimized)"
    exit 1
fi

if [[ "$CONFIG" != "baseline" && "$CONFIG" != "optimized" ]]; then
    echo "[start_api] ERROR: --config must be 'baseline' or 'optimized', got '$CONFIG'"
    exit 1
fi

# ---------- set toggle env vars ---------------------------------------------
if [[ "$CONFIG" == "baseline" ]]; then
    echo "[start_api] config=baseline — all optimizations OFF"
    export OPTIMIZE_S1_EAGER=false
    export OPTIMIZE_S2_HASHSET=false
    export OPTIMIZE_S3_INDEX=false
    export OPTIMIZE_S4_MMAP=false
    export OPTIMIZE_S5_CACHE=false
elif [[ "$CONFIG" == "optimized" ]]; then
    echo "[start_api] config=optimized — all optimizations ON"
    export OPTIMIZE_S1_EAGER=true
    export OPTIMIZE_S2_HASHSET=true
    export OPTIMIZE_S3_INDEX=true
    export OPTIMIZE_S4_MMAP=true
    export OPTIMIZE_S5_CACHE=true
fi

# ---------- kill any existing API process -----------------------------------
if [[ -f "$PIDFILE" ]]; then
    OLD_PID=$(cat "$PIDFILE")
    if kill -0 "$OLD_PID" 2>/dev/null; then
        echo "[start_api] killing existing API process $OLD_PID..."
        pkill -P "$OLD_PID" 2>/dev/null || true
        kill "$OLD_PID" 2>/dev/null || true
        sleep 2
    fi
    rm -f "$PIDFILE"
fi

# ---------- start the API ---------------------------------------------------
cd "$PROJECT_ROOT"

DOTNET_CMD="dotnet src/PetRescue.Api/bin/Release/net10.0/PetRescue.Api.dll --urls http://0.0.0.0:8080"

if [[ -n "$CPULIMIT" ]]; then
    echo "[start_api] starting with cpulimit=${CPULIMIT}%..."
    cpulimit -l "$CPULIMIT" -- $DOTNET_CMD > /tmp/dotnet_api.log 2>&1 &
else
    echo "[start_api] starting without cpulimit..."
    $DOTNET_CMD > /tmp/dotnet_api.log 2>&1 &
fi

API_PID=$!
echo "$API_PID" > "$PIDFILE"
echo "[start_api] API PID: $API_PID (pidfile: $PIDFILE)"

# ---------- wait for health -------------------------------------------------
echo "[start_api] waiting for API health..."
MAX_ATTEMPTS=30
for i in $(seq 1 $MAX_ATTEMPTS); do
    if curl -sf http://localhost:8080/health > /dev/null 2>&1; then
        echo "[start_api] API healthy (attempt $i/$MAX_ATTEMPTS)"
        exit 0
    fi
    # Check if process died
    if ! kill -0 "$API_PID" 2>/dev/null; then
        echo "[start_api] ERROR: API process died. Check /tmp/dotnet_api.log"
        rm -f "$PIDFILE"
        exit 1
    fi
    sleep 1
done

echo "[start_api] ERROR: API not healthy after ${MAX_ATTEMPTS}s. Check /tmp/dotnet_api.log"
# Kill the process since it's unhealthy
pkill -P "$API_PID" 2>/dev/null || true
kill "$API_PID" 2>/dev/null || true
rm -f "$PIDFILE"
exit 1
