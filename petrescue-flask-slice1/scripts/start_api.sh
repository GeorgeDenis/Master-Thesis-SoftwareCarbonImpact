#!/usr/bin/env bash
# scripts/start_api.sh
#
# Start or stop the Flask API with the correct toggle environment variables.
#
# Usage:
#   bash scripts/start_api.sh --config baseline [--cpulimit 50] [--pidfile /tmp/flask_api.pid]
#   bash scripts/start_api.sh --config optimized --cpulimit 50
#   bash scripts/start_api.sh --stop [--pidfile /tmp/flask_api.pid]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

# ---------- defaults --------------------------------------------------------
CONFIG=""
CPULIMIT=""
PIDFILE="/tmp/flask_api.pid"
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
if [[ "$STOP_MODE" == "true" ]]; then
    echo "[start_api] stopping Flask API..."
    if [[ -f "$PIDFILE" ]]; then
        PID=$(cat "$PIDFILE")
        if kill -0 "$PID" 2>/dev/null; then
            # Kill child processes first (e.g. the python process under cpulimit)
            pkill -P "$PID" 2>/dev/null || true
            kill "$PID" 2>/dev/null || true
            # Wait briefly for process to exit
            for i in $(seq 1 10); do
                if ! kill -0 "$PID" 2>/dev/null; then
                    break
                fi
                sleep 0.5
            done
            # Force kill if still alive
            if kill -0 "$PID" 2>/dev/null; then
                kill -9 "$PID" 2>/dev/null || true
                pkill -9 -P "$PID" 2>/dev/null || true
            fi
            echo "[start_api] killed PID $PID"
        else
            echo "[start_api] PID $PID not running"
        fi
        rm -f "$PIDFILE"
    else
        echo "[start_api] no pidfile found at $PIDFILE"
    fi
    exit 0
fi

# ---------- validate config -------------------------------------------------
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
    export OPTIMIZE_S1_EAGER=false
    export OPTIMIZE_S2_HASHSET=false
    export OPTIMIZE_S3_INDEX=false
    export OPTIMIZE_S4_MMAP=false
    export OPTIMIZE_S5_CACHE=false
    echo "[start_api] config=baseline (all toggles OFF)"
else
    export OPTIMIZE_S1_EAGER=true
    export OPTIMIZE_S2_HASHSET=true
    export OPTIMIZE_S3_INDEX=true
    export OPTIMIZE_S4_MMAP=true
    export OPTIMIZE_S5_CACHE=true
    echo "[start_api] config=optimized (all toggles ON)"
fi

# ---------- start the API ---------------------------------------------------
echo "[start_api] starting Flask API..."

if [[ -n "$CPULIMIT" ]]; then
    echo "[start_api] wrapping with cpulimit -l $CPULIMIT"
    cpulimit -l "$CPULIMIT" -- "$PROJECT_ROOT/.venv/bin/python" app.py < /dev/null > /tmp/flask_api.log 2>&1 &
else
    "$PROJECT_ROOT/.venv/bin/python" app.py < /dev/null > /tmp/flask_api.log 2>&1 &
fi

API_PID=$!
echo "$API_PID" > "$PIDFILE"
echo "[start_api] PID=$API_PID written to $PIDFILE"

# ---------- wait for health -------------------------------------------------
echo "[start_api] waiting for API health on http://localhost:5000/health ..."
MAX_WAIT=30
for i in $(seq 1 $MAX_WAIT); do
    if curl -sf http://localhost:5000/health > /dev/null 2>&1; then
        echo "[start_api] API is healthy (attempt $i/$MAX_WAIT)"
        # Print the active toggles for verification
        curl -sf http://localhost:5000/health | python3 -c "
import sys, json
d = json.load(sys.stdin)
toggles = d.get('toggles', {})
print('[start_api] active toggles:', json.dumps(toggles, indent=2))
" 2>/dev/null || true
        exit 0
    fi
    if ! kill -0 "$API_PID" 2>/dev/null; then
        echo "[start_api] ERROR: API process exited prematurely. Log:"
        tail -20 /tmp/flask_api.log 2>/dev/null || true
        rm -f "$PIDFILE"
        exit 1
    fi
    sleep 1
done

echo "[start_api] ERROR: API did not become healthy after ${MAX_WAIT}s"
echo "[start_api] last log lines:"
tail -20 /tmp/flask_api.log 2>/dev/null || true
exit 1
