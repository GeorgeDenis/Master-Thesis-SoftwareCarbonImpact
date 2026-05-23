# PetRescue.NET — Slice 1: Monolith + Local Measurements

This is the .NET port of the PetRescue carbon-footprint study. Slice 1 covers:

1. An ASP.NET Core 10 Web API exposing five endpoints, each isolating one well-known software anti-pattern.
2. A PostgreSQL schema and seed data, run via Docker.
3. A Python sidecar service running **CodeCarbon** to measure host-level energy and CO₂.
4. JMeter test plans for five scenarios × three load levels.
5. An orchestration script that runs the full matrix N times and produces a single tidy CSV ready for statistical analysis.

The goal at this stage is **3 runs per cell, executed locally, producing one clean CSV**. Variance, statistical tests, and cloud deployment come in later slices.

## Prerequisites

| Tool | Version | Why |
|---|---|---|
| .NET SDK | 10.0+ | Build the API |
| Docker + Docker Compose | recent | Postgres, Redis |
| Python | 3.10+ | CodeCarbon sidecar |
| Apache JMeter | 5.6+ | Load generation |
| `jq` | any | CSV/JSON post-processing in the orchestrator |

## Quick start

```bash
# 1. Start Postgres + Redis
docker compose up -d

# 2. Apply schema + seed
psql -h localhost -U petrescue -d petrescue -f sql/00_schema.sql
psql -h localhost -U petrescue -d petrescue -f sql/01_seed.sql

# 3. Start the CodeCarbon sidecar (in its own terminal)
cd sidecar && python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python sidecar.py

# 4. Start the API (in its own terminal)
cd src/PetRescue.Api
dotnet run -c Release

# 5. Run the full experiment matrix, N=3
cd scripts
./run_experiment.sh --runs 3 --output ../results/local_$(date +%Y%m%d_%H%M%S).csv
```

The final CSV in `results/` is what gets fed into the statistical analysis in slice 5.

## Layout

See `docs/architecture.md` for the full layout, scenario-to-endpoint mapping, and measurement protocol.

## What this slice does NOT do

- No microservices (slice 2)
- No AWS, no Terraform (slice 3)
- No statistics beyond raw mean (slice 5)
- No paper (slice 7)

Slice 1 produces **clean, raw measurements** with a methodology that the later slices can build on without rework.
