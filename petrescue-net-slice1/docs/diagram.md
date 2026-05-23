# System Layout (Slice 1)

```
                          ┌──────────────────────────────┐
                          │  Orchestrator (bash)         │
                          │  scripts/run_experiment.sh   │
                          └──────────────┬───────────────┘
                                         │
              ┌──────────────────────────┼──────────────────────────┐
              │                          │                          │
              ▼                          ▼                          ▼
   ┌──────────────────┐       ┌──────────────────┐       ┌──────────────────┐
   │   JMeter         │       │  CodeCarbon      │       │  Postgres / Redis│
   │   petrescue.jmx  │──HTTP─▶  Sidecar (Flask) │       │  Docker compose  │
   │   (load gen.)    │       │  /start /stop    │       │                  │
   └────────┬─────────┘       └────────┬─────────┘       └────────┬─────────┘
            │                          │                          ▲
            ▼                          ▼                          │
   ┌─────────────────────────────────────────────────────────────────────┐
   │                  ASP.NET Core 8 - PetRescue.Api                    │
   │                                                                     │
   │   /api/s1/medical-records   <- S1: N+1 ORM      / Eager .Include() │
   │   /api/s2/microchip-match   <- S2: List.Contains/ HashSet.Contains │
   │   /api/s3/disease-search    <- S3: No index    / B-tree index     │
   │   /api/s4/file-search       <- S4: ReadAllLines/ MemoryMappedFile  │
   │   /api/s5/heavy-statistics  <- S5: No cache    / Redis cache       │
   │                                                                     │
   │   Toggle via env: OPTIMIZE_S{1..5}_*                                │
   └─────────────────────────────────────────────────────────────────────┘
```

## Three measurement layers, separated by concern

1. **Load layer** — JMeter, drives concurrent users at the API.
2. **Application layer** — ASP.NET Core does the work.
3. **Energy layer** — CodeCarbon, running as a Python sidecar, measures the whole host.

The orchestrator coordinates the three: warm-up, start tracker, measure, stop tracker, cool-down, repeat.
