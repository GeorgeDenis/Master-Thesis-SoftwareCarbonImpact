#!/usr/bin/env bash
# scripts/bootstrap.sh
#
# Idempotent setup for the PetRescue .NET Slice 1 experiment VM.
# Safe to run multiple times — each step checks if work is already done.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

echo "[bootstrap] project root: $PROJECT_ROOT"

# ---------- 1. System dependencies -----------------------------------------
echo "[bootstrap] checking system dependencies..."
PKGS_TO_INSTALL=()
command -v jq        >/dev/null 2>&1 || PKGS_TO_INSTALL+=(jq)
command -v java      >/dev/null 2>&1 || PKGS_TO_INSTALL+=(default-jre)
command -v cpulimit  >/dev/null 2>&1 || PKGS_TO_INSTALL+=(cpulimit)
command -v psql      >/dev/null 2>&1 || PKGS_TO_INSTALL+=(postgresql-client)

if [[ ${#PKGS_TO_INSTALL[@]} -gt 0 ]]; then
    echo "[bootstrap] installing: ${PKGS_TO_INSTALL[*]}"
    sudo apt-get update -qq
    sudo apt-get install -y "${PKGS_TO_INSTALL[@]}"
else
    echo "[bootstrap] all system packages present"
fi

# ---------- 2. JMeter -------------------------------------------------------
JMETER_VERSION="5.6.3"
JMETER_HOME="/opt/apache-jmeter-${JMETER_VERSION}"

if ! command -v jmeter >/dev/null 2>&1; then
    echo "[bootstrap] installing JMeter ${JMETER_VERSION}..."
    if [[ ! -d "$JMETER_HOME" ]]; then
        wget -q "https://archive.apache.org/dist/jmeter/binaries/apache-jmeter-${JMETER_VERSION}.tgz" \
            -O /tmp/jmeter.tgz
        sudo tar -xzf /tmp/jmeter.tgz -C /opt/
        rm -f /tmp/jmeter.tgz
    fi
    sudo ln -sf "${JMETER_HOME}/bin/jmeter" /usr/local/bin/jmeter
    echo "[bootstrap] JMeter installed: $(jmeter --version 2>&1 | head -1)"
else
    echo "[bootstrap] JMeter already installed"
fi

# ---------- 3. .NET 10 SDK --------------------------------------------------
if ! command -v dotnet >/dev/null 2>&1; then
    echo "[bootstrap] installing .NET 10 SDK..."
    wget -q https://dot.net/v1/dotnet-install.sh -O /tmp/dotnet-install.sh
    chmod +x /tmp/dotnet-install.sh
    sudo /tmp/dotnet-install.sh --channel 10.0 --install-dir /usr/share/dotnet
    sudo ln -sf /usr/share/dotnet/dotnet /usr/local/bin/dotnet
    rm -f /tmp/dotnet-install.sh
    echo "[bootstrap] .NET installed: $(dotnet --version)"
else
    echo "[bootstrap] .NET already installed: $(dotnet --version)"
fi

# ---------- 4. Docker containers --------------------------------------------
echo "[bootstrap] starting Docker containers..."
docker compose up -d

# ---------- 5. Wait for Postgres --------------------------------------------
echo "[bootstrap] waiting for Postgres to be healthy..."
MAX_ATTEMPTS=30
for i in $(seq 1 $MAX_ATTEMPTS); do
    if pg_isready -h localhost -p 5433 -U petrescue >/dev/null 2>&1; then
        echo "[bootstrap] Postgres ready (attempt $i/$MAX_ATTEMPTS)"
        break
    fi
    if [[ $i -eq $MAX_ATTEMPTS ]]; then
        echo "[bootstrap] ERROR: Postgres not ready after $MAX_ATTEMPTS attempts"
        exit 1
    fi
    sleep 2
done

# ---------- 6. Load schema --------------------------------------------------
echo "[bootstrap] loading schema (00_schema.sql)..."
PGPASSWORD=petrescue psql -h localhost -p 5433 -U petrescue -d petrescue -q \
    -f sql/00_schema.sql

# ---------- 7. Seed data ----------------------------------------------------
echo "[bootstrap] seeding data (01_seed.sql)..."
PGPASSWORD=petrescue psql -h localhost -p 5433 -U petrescue -d petrescue -q \
    -f sql/01_seed.sql

# ---------- 8. Drop S3 index (baseline state) --------------------------------
echo "[bootstrap] dropping S3 index (baseline state)..."
PGPASSWORD=petrescue psql -h localhost -p 5433 -U petrescue -d petrescue -q \
    -f sql/02_index_drop.sql

# ---------- 9. Prepare test data files --------------------------------------
echo "[bootstrap] preparing test data files..."
bash scripts/prepare_data.sh

# ---------- 10. Sidecar virtualenv ------------------------------------------
echo "[bootstrap] setting up sidecar virtualenv..."
if [[ ! -d sidecar/.venv ]]; then
    cd sidecar
    python3 -m venv .venv
    .venv/bin/pip install --quiet -r requirements.txt
    cd "$PROJECT_ROOT"
    echo "[bootstrap] sidecar venv created"
else
    echo "[bootstrap] sidecar venv already exists"
fi

# ---------- 11. Build .NET app -----------------------------------------------
echo "[bootstrap] building .NET app..."
cd src/PetRescue.Api
dotnet build -c Release
cd "$PROJECT_ROOT"
echo "[bootstrap] .NET build complete"

# ---------- 12. Swap file (t3.small safety) ----------------------------------
echo "[bootstrap] checking swap..."
if swapon --show | grep -q '/swapfile'; then
    echo "[bootstrap] swap already active"
else
    if [[ ! -f /swapfile ]]; then
        echo "[bootstrap] creating 4GB swap file..."
        sudo fallocate -l 4G /swapfile
        sudo chmod 600 /swapfile
        sudo mkswap /swapfile
    fi
    sudo swapon /swapfile
    echo "[bootstrap] swap enabled"
fi

echo ""
echo "[bootstrap] =========================================="
echo "[bootstrap] Bootstrap complete!"
echo "[bootstrap] =========================================="
