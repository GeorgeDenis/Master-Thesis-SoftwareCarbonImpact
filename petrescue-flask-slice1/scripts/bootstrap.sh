#!/usr/bin/env bash
# scripts/bootstrap.sh
#
# Idempotent setup script for the Flask slice experiment VM.
# Safe to run multiple times — every step checks before acting.
#
# Usage:  bash scripts/bootstrap.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

echo "[bootstrap] project root: $PROJECT_ROOT"

# ---------- 1. System dependencies ------------------------------------------
echo "[bootstrap] checking system dependencies..."

for pkg_cmd in jq java cpulimit; do
    if ! command -v "$pkg_cmd" &>/dev/null; then
        echo "[bootstrap] installing missing package for: $pkg_cmd"
        case "$pkg_cmd" in
            java) sudo apt-get update -qq && sudo apt-get install -y default-jre ;;
            *)    sudo apt-get update -qq && sudo apt-get install -y "$pkg_cmd" ;;
        esac
    else
        echo "[bootstrap] $pkg_cmd already installed"
    fi
done

# psql is needed for DB operations
if ! command -v psql &>/dev/null; then
    echo "[bootstrap] installing postgresql-client..."
    sudo apt-get update -qq && sudo apt-get install -y postgresql-client
else
    echo "[bootstrap] psql already installed"
fi

# ---------- 2. JMeter -------------------------------------------------------
JMETER_VERSION="5.6.3"
JMETER_HOME="/opt/apache-jmeter-${JMETER_VERSION}"

if ! command -v jmeter &>/dev/null; then
    echo "[bootstrap] installing JMeter ${JMETER_VERSION}..."
    if [[ ! -d "$JMETER_HOME" ]]; then
        cd /tmp
        wget -q "https://archive.apache.org/dist/jmeter/binaries/apache-jmeter-${JMETER_VERSION}.tgz" \
            -O "apache-jmeter-${JMETER_VERSION}.tgz"
        sudo tar -xzf "apache-jmeter-${JMETER_VERSION}.tgz" -C /opt/
        rm -f "apache-jmeter-${JMETER_VERSION}.tgz"
        cd "$PROJECT_ROOT"
    fi
    sudo ln -sf "${JMETER_HOME}/bin/jmeter" /usr/local/bin/jmeter
    echo "[bootstrap] JMeter installed at $JMETER_HOME"
else
    echo "[bootstrap] JMeter already installed: $(command -v jmeter)"
fi

# ---------- 3. Docker containers --------------------------------------------
echo "[bootstrap] starting Docker containers..."
docker compose up -d

# ---------- 4. Wait for Postgres to be healthy ------------------------------
echo "[bootstrap] waiting for Postgres on port 5433..."
MAX_ATTEMPTS=30
for i in $(seq 1 $MAX_ATTEMPTS); do
    if pg_isready -h localhost -p 5433 -U petrescue &>/dev/null; then
        echo "[bootstrap] Postgres is ready (attempt $i/$MAX_ATTEMPTS)"
        break
    fi
    if [[ $i -eq $MAX_ATTEMPTS ]]; then
        echo "[bootstrap] ERROR: Postgres did not become ready after $MAX_ATTEMPTS attempts"
        exit 1
    fi
    echo "[bootstrap] waiting for Postgres... ($i/$MAX_ATTEMPTS)"
    sleep 2
done

# ---------- 5. Schema -------------------------------------------------------
echo "[bootstrap] running 00_schema.sql..."
PGPASSWORD=petrescue psql -h localhost -p 5433 -U petrescue -d petrescue -q -f sql/00_schema.sql

# ---------- 6. Seed data ----------------------------------------------------
echo "[bootstrap] running 01_seed.sql..."
PGPASSWORD=petrescue psql -h localhost -p 5433 -U petrescue -d petrescue -q -f sql/01_seed.sql

# ---------- 7. Drop S3 index (start in baseline state) ----------------------
echo "[bootstrap] dropping S3 index (baseline state)..."
PGPASSWORD=petrescue psql -h localhost -p 5433 -U petrescue -d petrescue -q -f sql/02_index_drop.sql

# ---------- 8. Generate auxiliary data files ---------------------------------
echo "[bootstrap] generating data files via prepare_data.sh..."
bash "$SCRIPT_DIR/prepare_data.sh"

# ---------- 9. Sidecar venv -------------------------------------------------
if [[ ! -d "$PROJECT_ROOT/sidecar/.venv" ]]; then
    echo "[bootstrap] creating sidecar venv..."
    cd "$PROJECT_ROOT/sidecar"
    python3 -m venv .venv
    .venv/bin/pip install --quiet -r requirements.txt
    cd "$PROJECT_ROOT"
else
    echo "[bootstrap] sidecar venv already exists"
fi

# ---------- 10. Main app venv -----------------------------------------------
if [[ ! -d "$PROJECT_ROOT/.venv" ]]; then
    echo "[bootstrap] creating main app venv..."
    python3 -m venv .venv
    .venv/bin/pip install --quiet -r requirements.txt
else
    echo "[bootstrap] main app venv already exists"
fi

# ---------- 11. Swap file (t3.small safety) ---------------------------------
if swapon --show | grep -q '/swapfile'; then
    echo "[bootstrap] swap already active"
else
    if [[ -f /swapfile ]]; then
        echo "[bootstrap] /swapfile exists but not active, activating..."
        sudo chmod 600 /swapfile
        sudo mkswap /swapfile
        sudo swapon /swapfile
    else
        echo "[bootstrap] creating 4GB swap file..."
        sudo fallocate -l 4G /swapfile
        sudo chmod 600 /swapfile
        sudo mkswap /swapfile
        sudo swapon /swapfile
    fi
    echo "[bootstrap] swap activated"
fi

echo ""
echo "[bootstrap] ============================================"
echo "[bootstrap] Bootstrap complete!"
echo "[bootstrap] ============================================"
