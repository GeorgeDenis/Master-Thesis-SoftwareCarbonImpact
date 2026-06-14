# Chapter 3 Data Tables

Averages across 3 runs for **80 concurrent users**. Ghost runs (100% failure rate) are excluded.

### S1 — ORM Overhead (N+1 Queries)

| Instance | Configuration | Runtime | Avg Duration (s) | Avg Succ. Reqs | Avg Total CO₂ (mg) | CO₂/Req (mg) |
|---|---|---|---|---|---|---|
| m7i | baseline | flask | 536.6 | 80 | 2574.9 | **32.19** |
| m7i | baseline | net | 241.4 | 80 | 1158.5 | **14.48** |
| m7i | optimized | flask | 71.3 | 625 | 342.0 | **0.548** |
| m7i | optimized | net | 79.8 | 172 | 383.1 | **2.23** |
| c7i | baseline | flask | 4336.2 | 80 | 20141.8 | **252** |
| c7i | baseline | net | 2473.7 | 79 | 11490.4 | **145** |
| c7i | optimized | flask | 73.7 | 488 | 342.2 | **0.702** |
| c7i | optimized | net | 90.3 | 91 | 419.4 | **4.65** |
| t3 | baseline | flask | `Ghost Run` | `0` | `-` | `-` |
| t3 | baseline | net | 1759.5 | 32 | 19678.9 | **615** |
| t3 | optimized | flask | 75.8 | 411 | 847.5 | **2.06** |
| t3 | optimized | net | 1129.8 | 62 | 12635.7 | **211** |

### S2 — Algorithmic Complexity (List vs. Set)

| Instance | Configuration | Runtime | Avg Duration (s) | Avg Succ. Reqs | Avg Total CO₂ (mg) | CO₂/Req (mg) |
|---|---|---|---|---|---|---|
| m7i | baseline | flask | 113.9 | 95 | 546.4 | **5.74** |
| m7i | baseline | net | 87.8 | 182 | 421.1 | **2.32** |
| m7i | optimized | flask | 66.7 | 2201 | 320.2 | **0.146** |
| m7i | optimized | net | 65.0 | 5567 | 311.9 | **0.056** |
| c7i | baseline | flask | 134.2 | 80 | 623.2 | **7.79** |
| c7i | baseline | net | 121.7 | 104 | 565.2 | **5.42** |
| c7i | optimized | flask | 67.4 | 1599 | 313.0 | **0.196** |
| c7i | optimized | net | 65.0 | 2265 | 301.9 | **0.133** |
| t3 | baseline | flask | 218.8 | 80 | 2446.9 | **30.59** |
| t3 | baseline | net | 121.4 | 76 | 1358.2 | **18.55** |
| t3 | optimized | flask | 69.9 | 1247 | 781.4 | **0.627** |
| t3 | optimized | net | 67.9 | 2765 | 759.9 | **0.275** |

### S3 — Missing Database Index

| Instance | Configuration | Runtime | Avg Duration (s) | Avg Succ. Reqs | Avg Total CO₂ (mg) | CO₂/Req (mg) |
|---|---|---|---|---|---|---|
| m7i | baseline | flask | 83.5 | 110 | 400.6 | **3.65** |
| m7i | baseline | net | 84.4 | 100 | 404.9 | **4.09** |
| m7i | optimized | flask | 69.9 | 338 | 335.2 | **0.992** |
| m7i | optimized | net | 72.6 | 265 | 348.2 | **1.32** |
| c7i | baseline | flask | 80.2 | 99 | 372.5 | **3.78** |
| c7i | baseline | net | 81.9 | 100 | 380.7 | **3.82** |
| c7i | optimized | flask | 69.3 | 348 | 322.1 | **0.926** |
| c7i | optimized | net | 71.5 | 238 | 332.0 | **1.39** |
| t3 | baseline | flask | `Ghost Run` | `0` | `-` | `-` |
| t3 | baseline | net | 145.6 | 80 | 1628.6 | **20.36** |
| t3 | optimized | flask | 84.1 | 227 | 941.1 | **4.15** |
| t3 | optimized | net | 86.6 | 160 | 968.3 | **6.05** |

### S4 — Synchronous File I/O

| Instance | Configuration | Runtime | Avg Duration (s) | Avg Succ. Reqs | Avg Total CO₂ (mg) | CO₂/Req (mg) |
|---|---|---|---|---|---|---|
| m7i | baseline  flask | 71.0 | 672 | 340.7 | **0.507** |
| m7i | baseline | net | 70.6 | 512 | 338.9 | **0.662** |
| m7i | optimized | flask | 64.0 | 7453 | 307.1 | **0.041** |
| m7i | optimized | net | 64.6 | 2735 | 310.1 | **0.114** |
| c7i | baseline | flask | 75.0 | 462 | 348.5 | **0.754** |
| c7i | baseline | net | 81.0 | 199 | 376.3 | **1.90** |
| c7i | optimized | flask | 64.3 | 5352 | 298.5 | **0.056** |
| c7i | optimized | net | 64.2 | 705 | 298.3 | **0.424** |
| t3 | baseline | flask | `Ghost Run` | `0` | `-` | `-` |
| t3 | baseline | net | 77.1 | 200 | 862.5 | **4.33** |
| t3 | optimized | flask | 65.6 | 4384 | 733.3 | **0.167** |
| t3 | optimized | net | 67.2 | 1211 | 751.8 | **0.628** |

### S5 — Uncached Aggregation (Redis)

| Instance | Configuration | Runtime | Avg Duration (s) | Avg Succ. Reqs | Avg Total CO₂ (mg) | CO₂/Req (mg) |
|---|---|---|---|---|---|---|
| m7i | baseline | flask | 63.9 | 5625 | 306.5 | **0.055** |
| m7i | baseline | net | 63.6 | 6175 | 305.4 | **0.049** |
| m7i | optimized | flask | 63.5 | 60448 | 304.7 | **0.0050** |
| m7i | optimized | net | 63.3 | 382058 | 303.7 | **0.0008** |
| c7i | baseline | flask | 63.8 | 5410 | 296.6 | **0.055** |
| c7i | baseline | net | 63.7 | 6321 | 295.7 | **0.047** |
| c7i | optimized | flask | 63.6 | 42516 | 295.4 | **0.0069** |
| c7i | optimized | net | 63.5 | 188481 | 295.2 | **0.0016** |
| t3 | baseline | flask | 65.4 | 3420 | 731.1 | **0.214** |
| t3 | baseline | net | 65.2 | 3467 | 728.9 | **0.210** |
| t3 | optimized | flask | 64.7 | 32992 | 723.9 | **0.022** |
| t3 | optimized | net | 65.0 | 151449 | 727.5 | **0.0048** |

