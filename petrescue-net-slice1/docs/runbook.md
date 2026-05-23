# Runbook: Local 3-run Measurement Experiment

This is the step-by-step protocol you follow to produce a clean dataset of 3 runs per cell, locally, before any cloud work.

The total wall-clock time is roughly **2.5 hours** for the full sweep (5 scenarios × 2 configurations × 3 loads × 3 runs = 90 cells, at ~150 seconds each).

If you want to validate the pipeline first, run a **smoke test** of one cell, which takes ~3 minutes. See section 4.

---

## 0. Pre-flight checklist

Before you start, verify these are installed and on PATH. Pin versions where it matters.

| Tool | Minimum version | Verify with |
|---|---|---|
| Docker + Compose | recent | `docker compose version` |
| .NET SDK | 8.0 | `dotnet --version` |
| Python | 3.10+ | `python3 --version` |
| Apache JMeter | 5.6+ | `jmeter -v` |
| `jq` | any | `jq --version` |
| `psql` client | 14+ | `psql --version` |
| `curl` | any | `curl --version` |

If anything is missing, install it first. Do not proceed until all eight commands return cleanly.

---

## 1. One-time setup

These steps only need to be done once per machine.

### 1.1 Start Postgres and Redis

```bash
cd /path/to/petrescue-net
docker compose up -d
docker compose ps      # both should show "healthy"
```

### 1.2 Create the schema and seed data

```bash
psql -h localhost -U petrescue -d petrescue -f sql/00_schema.sql
psql -h localhost -U petrescue -d petrescue -f sql/01_seed.sql
```

Password is `petrescue` (set in `docker-compose.yml`). Use `PGPASSWORD=petrescue` in front of the commands to avoid the prompt, or put it in `~/.pgpass`.

Verify the seed:

```bash
PGPASSWORD=petrescue psql -h localhost -U petrescue -d petrescue \
  -c "SELECT COUNT(*) FROM animals, medical_records, shelters;"
```

You should see 5000, 1000, and 50.

### 1.3 Generate the S2 and S4 auxiliary files

```bash
bash scripts/prepare_data.sh
ls -la /tmp/petrescue_*
```

You should see `petrescue_microchips.txt` (~12 MB) and `petrescue_s2_body.json` (~600 KB).

### 1.4 Set up the sidecar's virtualenv

```bash
cd sidecar
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cd ..
```

---

## 2. The 4-terminal layout

You will need **four terminals**, each pinned to its job.

| Terminal | Job | Command |
|---|---|---|
| T1 | Docker + monitoring | already done; leave `docker compose ps` if you want to watch |
| T2 | Sidecar | `cd sidecar && source .venv/bin/activate && python sidecar.py` |
| T3 | API | `cd src/PetRescue.Api && dotnet run -c Release` (env vars vary per config) |
| T4 | Orchestrator | `cd scripts && ./run_experiment.sh ...` |

Keep them open and labelled. You will be switching between T3 and T4 several times.

---

## 3. The full measurement run

The protocol is two passes — one with the baseline API, one with the optimized API. Each pass produces its own CSV. You concatenate them at the end.

### 3.1 Pass 1: Baseline

**Terminal 2:** Start the sidecar (leave it running).

```bash
cd sidecar
source .venv/bin/activate
python sidecar.py
# you should see: Running on http://127.0.0.1:5055
```

**Terminal 3:** Start the API with all toggles OFF (baseline).

```bash
cd src/PetRescue.Api
unset OPTIMIZE_S1_EAGER OPTIMIZE_S2_HASHSET OPTIMIZE_S3_INDEX OPTIMIZE_S4_MMAP OPTIMIZE_S5_CACHE
dotnet run -c Release
# wait for: "Now listening on: http://0.0.0.0:5000"
```

Verify in another shell:

```bash
curl -s http://localhost:5000/health | jq
# you should see all toggles=false
```

**Terminal 4:** Drop the S3 index (so baseline measurements run without it), then start the orchestrator.

```bash
cd scripts
PGPASSWORD=petrescue psql -h localhost -U petrescue -d petrescue \
  -f ../sql/02_index_drop.sql

./run_experiment.sh \
  --runs 3 \
  --configs baseline \
  --output ../results/local_baseline_$(date +%Y%m%d_%H%M%S).csv
```

This runs **45 cells** (5 scenarios × 3 loads × 3 runs). It takes about 1h15.

**Watch for:**

- The first cell's `[cell] result: requests=...` line. If `requests` is 0 or `errors` is high, stop and investigate (`tail -200 results/jtl_*/s1_baseline_10u_r1.log` will show JMeter's view of the world).
- Memory pressure on the host. `htop` in a fifth terminal is your friend.

### 3.2 Pass 2: Optimized

**Terminal 3:** Stop the API (`Ctrl-C`). Restart it with all toggles ON.

```bash
cd src/PetRescue.Api
OPTIMIZE_S1_EAGER=1 \
OPTIMIZE_S2_HASHSET=1 \
OPTIMIZE_S3_INDEX=1 \
OPTIMIZE_S4_MMAP=1 \
OPTIMIZE_S5_CACHE=1 \
dotnet run -c Release
```

Verify:

```bash
curl -s http://localhost:5000/health | jq
# you should see all toggles=true
```

**Terminal 4:** Apply the S3 index (so optimized measurements have it), then run.

```bash
cd scripts
PGPASSWORD=petrescue psql -h localhost -U petrescue -d petrescue \
  -f ../sql/02_index_apply.sql

./run_experiment.sh \
  --runs 3 \
  --configs optimized \
  --output ../results/local_optimized_$(date +%Y%m%d_%H%M%S).csv
```

Another ~1h15.

### 3.3 Combine the results

```bash
cd results
# Keep the header from the first file, append the data rows from the second.
head -1 local_baseline_*.csv > local_combined_$(date +%Y%m%d).csv
tail -n +2 -q local_baseline_*.csv local_optimized_*.csv \
  >> local_combined_$(date +%Y%m%d).csv

# Sanity check
wc -l local_combined_*.csv     # should be 91 lines (header + 90 rows)
```

This is the file slice 5 reads.

---

## 4. Smoke test: validate the pipeline in 3 minutes

Before committing to the full sweep, run one cell end-to-end to verify everything connects.

```bash
cd scripts
./run_experiment.sh \
  --runs 1 \
  --scenarios s5 \
  --configs baseline \
  --loads 10 \
  --warmup-s 5 \
  --measure-s 15 \
  --cooldown-s 5 \
  --output /tmp/smoke.csv

cat /tmp/smoke.csv
```

You should see exactly two lines — header plus one data row. The data row should have non-zero `requests_total`, `p95_ms`, `throughput_rps`, `energy_kwh`, and `co2_per_req_mg`.

If any of those is zero, fix it before doing the long run. The four most common failures:

1. **`requests_total = 0`** — JMeter couldn't reach the API. Check `--api-url` and that the API is actually listening.
2. **`energy_kwh = 0`** — the sidecar didn't track. Check sidecar terminal output and `sidecar/emissions/` for a CSV.
3. **`errors > 0`** — the API returned 500s. Check API logs.
4. **JMeter exits immediately** — usually a missing file (`/tmp/petrescue_s2_body.json` for S2). Re-run `prepare_data.sh`.

---

## 5. What you have at the end

A 90-row CSV in `results/` that looks like this (truncated for width):

```
timestamp_utc,           scenario, config,    users, run, p95_ms, energy_kwh, co2_per_req_mg
2026-05-16T13:00:42Z,    s1,       baseline,  10,    1,   542.0,  0.000412,   1.234
2026-05-16T13:02:51Z,    s1,       baseline,  10,    2,   538.0,  0.000408,   1.221
2026-05-16T13:05:00Z,    s1,       baseline,  10,    3,   551.0,  0.000419,   1.247
...
```

This is what slice 5 turns into a statistical report. Until then, you can already eyeball whether the variance is sane:

```bash
python3 - <<'EOF'
import csv, statistics as s
from collections import defaultdict
groups = defaultdict(list)
with open("results/local_combined_*.csv".replace("*", "20260516")) as f:  # adjust filename
    for r in csv.DictReader(f):
        key = (r["scenario"], r["config"], r["users"])
        groups[key].append(float(r["co2_per_req_mg"]))
print(f"{'scenario':<6} {'config':<10} {'users':<6} {'mean_mg':>8} {'sd_mg':>8} {'cv':>6}")
for k, vs in sorted(groups.items()):
    if len(vs) < 2: continue
    m = s.mean(vs); sd = s.stdev(vs); cv = sd/m if m else 0
    print(f"{k[0]:<6} {k[1]:<10} {k[2]:<6} {m:>8.3f} {sd:>8.3f} {cv:>6.1%}")
EOF
```

If CV (coefficient of variation = SD / mean) is under ~15% for most cells, the data is publishable. If it's above 30% in many cells, you need more repeats — bump N=3 to N=5 or N=10 before moving on to cloud.

---

## 6. Common pitfalls

| Symptom | Likely cause | Fix |
|---|---|---|
| Sidecar `409: tracker already running` | Previous run interrupted | `curl -X POST http://localhost:5055/stop` once, then continue |
| Postgres connection refused | Pool exhausted | Increase `Maximum Pool Size` in `Program.cs` connection string, or wait and retry |
| S4 returns `found=false` always | `/tmp/petrescue_microchips.txt` missing or empty | re-run `prepare_data.sh`, restart the API |
| S5 returns `source=db` even when optimized | Redis not reachable | `docker compose ps` should show `petrescue-redis` healthy |
| Wildly varying p99 latencies between repeats | Thermal throttle / background load | Close other apps, increase `--cooldown-s` to 120, re-run |
| `energy_kwh` is mysteriously zero | CodeCarbon couldn't access hardware sensors | Check sidecar logs. On macOS/M-series, this means TDP fallback — expected, and recorded in CodeCarbon's CSV under `cpu_power` |

When in doubt, re-run the smoke test in section 4 to verify the pipeline before assuming the data is bad.
