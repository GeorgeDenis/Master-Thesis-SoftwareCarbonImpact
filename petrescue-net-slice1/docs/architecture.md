# PetRescue.NET — Architecture and Measurement Protocol (Slice 1)

This document explains how the project is laid out, what each piece measures, and the exact protocol for producing a clean dataset of 3 runs per cell.

## 1. The system under test

A single ASP.NET Core 8 Web API named `PetRescue.Api`. It uses Entity Framework Core 8 with the Npgsql provider for PostgreSQL, and `Microsoft.Extensions.Caching.StackExchangeRedis` for the S5 cache path.

Five endpoints, one per scenario:

| Scenario | Endpoint | Method | What it does |
|---|---|---|---|
| S1 | `/api/s1/medical-records` | GET | Returns all medical records with the animal's name. Baseline triggers N+1 lazy loading. Optimized uses `Include()`. |
| S2 | `/api/s2/microchip-match` | POST | Counts how many of 20,000 input microchip codes exist in the database. Baseline uses `List<string>.Contains`. Optimized uses `HashSet<string>`. |
| S3 | `/api/s3/disease-search` | GET | Issues 500 identical `WHERE disease = 'Parvovirus'` queries. Baseline runs without an index. Optimized adds a B-tree index. |
| S4 | `/api/s4/file-search` | GET | Linear scan of a 1M-line file for a target marker. Baseline uses `File.ReadAllLines`. Optimized uses `MemoryMappedFile`. |
| S5 | `/api/s5/heavy-statistics` | GET | Computes `GROUP BY species, COUNT(visits)`. Baseline hits the DB every request. Optimized uses Redis with a 60-second sliding TTL. |

Each scenario has a **toggle** controlled by an environment variable (`OPTIMIZE_S1_EAGER`, `OPTIMIZE_S2_HASHSET`, etc.). The same binary serves both the baseline and the optimized configuration. The only exception is S3, where the toggle is informational and the actual change is a SQL-level index that the orchestrator applies or drops between runs.

This single-binary-with-toggles design is deliberate. It eliminates an entire class of "are you sure the difference isn't just a different build?" objections from reviewers.

## 2. Why this is a defensible measurement methodology

A reviewer will ask three questions of any energy-measurement paper. The protocol below answers each one before they ask.

### "How do you know your measurements aren't noise?"

We run each cell **N times** (3 in slice 1, 5–10 later). The orchestrator records every run as a separate row in the output CSV. Slice 5 computes mean and standard deviation; if SD is small relative to the mean, the measurement is stable. If not, we increase N.

### "How do you know one configuration didn't get lucky?"

We **randomize the cell execution order**. A naive sweep would run all 3 repeats of `s1_baseline_10u` consecutively, exposing them all to the same momentary thermal or background-load state. The orchestrator instead shuffles all cells with a fixed seed (`srand(42)`) before executing. This converts systematic bias into random noise that the standard deviation captures.

### "How do you know energy measurements are clean?"

Three layers:

1. **Warm-up phase, 30 seconds, discarded.** Eliminates JIT compilation, connection-pool fill, page-cache warm, and TCP slow-start artifacts. The CodeCarbon tracker is not running during this window.
2. **Measurement phase, 60 seconds, recorded.** Single global CodeCarbon tracker, started immediately before, stopped immediately after. Whole-host measurement mode, not process-specific, because virtualization typically obscures per-process accounting.
3. **Cool-down phase, 60 seconds, idle.** Restores thermal state so the next cell starts from a comparable baseline.

The CodeCarbon tracker is decoupled into a separate Python sidecar service (see §4). The .NET application has no knowledge of it. This is the right design because measurement and workload should be independent processes for the same reason that an instrument shouldn't be wired into the experiment it observes.

## 3. The data layer

Postgres 16 in Docker. Schema in `sql/00_schema.sql`. Seed in `sql/01_seed.sql` (5,000 animals, 1,000 medical records, deterministic via `setseed(0.42)`).

The S3 index lives in two separate files: `02_index_apply.sql` and `02_index_drop.sql`. The orchestrator runs the appropriate one before each S3 cell.

Redis 7 in Docker, used only by the S5 optimized path.

## 4. The CodeCarbon sidecar

`sidecar/sidecar.py` is a 100-line Flask service. It exposes:

| Endpoint | Method | Purpose |
|---|---|---|
| `/health` | GET | Liveness check. |
| `/status` | GET | Whether a tracker is currently running. |
| `/start` | POST | Start a new CodeCarbon `EmissionsTracker`. Body: `{"experiment_name": "..."}`. |
| `/stop` | POST | Stop the current tracker. Returns CO₂-equivalent in kg and CodeCarbon's internal fields. |

CodeCarbon writes a CSV row per `(experiment_name)` into `sidecar/emissions/<experiment_name>.csv`. Each `/stop` appends one row. The orchestrator reads the last row to extract energy and CO₂.

The sidecar runs single-threaded (`threaded=False` in Flask) on purpose: only one experiment runs at a time, and we want zero concurrency in the measurement layer.

### Why a sidecar rather than in-process .NET measurement?

There is no first-class CodeCarbon-equivalent on .NET. Writing a native C# RAPL reader is feasible but a year of work to get right, and not portable to AWS Free Tier (guest access to RAPL is blocked anyway). Running CodeCarbon as a sidecar gives us:

- The same instrument we used in Python, so cross-language comparisons are clean.
- Whole-host measurement mode, which is what matters at the cloud-instance scale.
- Reuse of CodeCarbon's grid-intensity database and TDP fallback logic.

The cost is ~one Python process per host. On a t3.micro with 1 GB RAM, this is a real but small overhead (~50 MB resident).

## 5. The orchestrator

`scripts/run_experiment.sh` is the single entry point. Its job:

1. Preflight: verify .NET API is up, sidecar is up, JMeter is on PATH.
2. Generate the full cell list: scenarios × configs × loads × repeats.
3. Shuffle the list with a fixed seed.
4. For each cell:
   1. Apply or drop the S3 index if the scenario is S3.
   2. Run JMeter warm-up (30 s, low load).
   3. Hit `/start` on the sidecar.
   4. Run JMeter measurement (60 s, target load).
   5. Hit `/stop` on the sidecar.
   6. Parse the JMeter JTL: total requests, errors, p50/p95/p99, throughput.
   7. Parse the CodeCarbon CSV: duration, energy in kWh, CO₂ in kg.
   8. Compute CO₂ per request in mg.
   9. Append one tidy row to the output CSV.
   10. Sleep 60 s.

The output CSV has exactly these columns, in this order:

```
timestamp_utc, scenario, config, users, run, duration_s,
requests_total, errors,
p50_ms, p95_ms, p99_ms, throughput_rps,
energy_kwh, co2_kg, co2_per_req_mg
```

This is the **tidy format** that pandas, R, and any statistical tool consume without preprocessing. One row per observation. No wide tables, no merged cells, no human-friendly formatting. Slice 5 reads this file directly.

## 6. Toggling configurations between runs

The orchestrator does **not** automatically restart the .NET API to flip the env-var toggles. The simplest workflow for slice 1 is:

1. Decide which configuration to run first (e.g., all baselines).
2. Start the API with the appropriate `OPTIMIZE_*` env vars unset (baseline) or set (optimized).
3. Run the orchestrator with `--configs baseline` only.
4. Stop the API, change env vars, restart.
5. Run the orchestrator with `--configs optimized` only.
6. Concatenate the two CSVs.

This sounds clunky but it's correct: it prevents any chance of the API being in a half-toggled state mid-run, and it keeps the API process identical across all cells of one config. Slice 2 will introduce a more automated restart protocol; for now, manual is safer.

## 7. Minimum viable execution for "3 runs per cell"

The fastest path to a defensible 3-run dataset:

```bash
# One terminal: Docker
docker compose up -d
psql -h localhost -U petrescue -d petrescue -f sql/00_schema.sql
psql -h localhost -U petrescue -d petrescue -f sql/01_seed.sql
bash scripts/prepare_data.sh

# Second terminal: sidecar
cd sidecar && python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python sidecar.py

# Third terminal: baseline API
cd src/PetRescue.Api
dotnet run -c Release

# Fourth terminal: orchestrator (baseline)
cd scripts
./run_experiment.sh --runs 3 --configs baseline --output ../results/baseline.csv

# Stop the API. Restart with the optimized env vars set:
OPTIMIZE_S1_EAGER=1 OPTIMIZE_S2_HASHSET=1 OPTIMIZE_S3_INDEX=1 \
OPTIMIZE_S4_MMAP=1 OPTIMIZE_S5_CACHE=1 \
    dotnet run -c Release

# Fourth terminal: orchestrator (optimized)
./run_experiment.sh --runs 3 --configs optimized --output ../results/optimized.csv
```

That gives you two CSVs, 45 rows each. Concatenate them into `results/local_$(date +%Y%m%d).csv` and slice 5 takes over.

## 8. What can go wrong in slice 1, and what to do about it

- **JMeter can't connect to the API.** The default base URL is `http://localhost:5000`. If you changed `appsettings.json` or used `dotnet run --urls`, pass `--api-url` to the orchestrator and the matching `-JbaseUrl=...` is already plumbed through.
- **CodeCarbon refuses to start on macOS.** The library prints a warning and falls back to TDP estimation. This is expected. Slice 5 reports it as a known threat to construct validity.
- **Postgres rejects connections under high load.** The compose file sets `max_connections=300`. The API connection pool defaults to 200. If you see connection refused, the order of failure is usually: API pool exhausted before Postgres limit. Increase the pool size in `Program.cs` if needed.
- **S4 file isn't there.** `prepare_data.sh` writes to `/tmp/petrescue_microchips.txt`. If `/tmp` is wiped between sessions (some systems do this), re-run the script.
- **Tracker already running on `/start`.** Means the previous run was interrupted before `/stop`. Hit `curl -X POST http://localhost:5055/stop` once to clear state, then resume.

## 9. What you have at the end of slice 1

- A working .NET monolith with five anti-patterns and five matched optimizations.
- A sidecar-based measurement layer that's language-agnostic and reusable in cloud.
- 90 tidy CSV rows (5 scenarios × 2 configs × 3 loads × 3 runs) per execution.
- A reproducible methodology that you can paste, almost verbatim, into Section III of the paper.

What you do not yet have, and where slices 2–7 take you:

- Slice 2: microservice version of the same scenarios.
- Slice 3: Terraform + CI pipeline to AWS.
- Slice 4: same orchestrator running against the cloud deployment.
- Slice 5: statistical analysis (mean ± SD, Mann-Whitney U, Cliff's delta).
- Slice 6: IEEE / INISTA paper skill.
- Slice 7: the paper itself.
