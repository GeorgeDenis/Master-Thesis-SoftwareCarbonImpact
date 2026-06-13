# Master Thesis: Software Carbon Impact 🌍⚡

This repository contains the infrastructure, application code, and orchestration scripts for measuring the software carbon intensity and energy efficiency of different backend architectures (.NET vs Python/Flask) under various performance anti-patterns and resource constraints.

## 🏗 Architecture

The experiment matrix evaluates two software stacks across three distinct hardware environments, creating 6 identical Virtual Machines (VMs).

### Software Slices
1. **`.NET 10 API` (`petrescue-net-slice1`)**: A highly concurrent, asynchronous web server (Kestrel) paired with Entity Framework Core.
2. **`Python Flask` (`petrescue-flask-slice1`)**: A synchronous web server running via Werkzeug/Gunicorn paired with SQLAlchemy.

### Hardware Environments
The VMs are provisioned in AWS via Terraform:
- **`m7i-flex.large`**: 8GB RAM, 2 vCPUs (Baseline/Full Speed)
- **`c7i-flex.large`**: 4GB RAM, 2 vCPUs (Artificially throttled to 50% CPU using `cpulimit` to simulate CPU starvation)
- **`t3.small`**: 2GB RAM, 2 vCPUs (Naturally memory-constrained to induce Swap Thrashing)

### The Scenarios
Each API contains 5 anti-pattern scenarios. They are tested under both a **baseline** (anti-pattern active) and **optimized** (anti-pattern fixed) configuration, at three user loads (10, 50, 80 concurrent users).
- **S1**: Object-Relational Mapping Overhead (N+1 Queries vs Eager Loading)
- **S2**: Algorithmic Complexity (O(N^2) lists vs O(1) HashSets)
- **S3**: Missing Database Indexes
- **S4**: File I/O (Streaming vs Memory-Mapped buffering)
- **S5**: Uncached Aggregations (Recomputing vs Redis Caching)

---

## 🚀 How to Replicate the Experiments

### Step 1: Deploy Infrastructure
1. Ensure you have the AWS CLI configured and Terraform installed.
2. Generate an SSH keypair for the VMs:
   ```bash
   ssh-keygen -t rsa -b 4096 -f ~/.ssh/petrescue_oci
   ```
3. Deploy the VMs:
   ```bash
   cd terraform-infrastructure
   terraform init
   terraform apply
   ```
4. Terraform will output the public IP addresses and exact SSH commands for all 6 VMs. 

### Step 2: Run the Experiments
SSH into each of the 6 VMs and clone/sync this repository. 
Because the experiments push the VMs to catastrophic failure (OOM and CPU starvation), your SSH connection *will* drop. You **must** run the orchestrator inside `tmux`!

**For the `m7i` (Full Speed) and `t3` (Memory Constrained) VMs:**
```bash
tmux new -s experiment
cd Master-Thesis-SoftwareCarbonImpact/petrescue-<net|flask>-slice1
bash scripts/run_full.sh
```

**For the `c7i` (CPU Throttled) VMs:**
```bash
tmux new -s experiment
cd Master-Thesis-SoftwareCarbonImpact/petrescue-<net|flask>-slice1
bash scripts/run_full.sh --cpulimit 50
```
*Press `Ctrl+B` then `D` to safely detach from tmux.*

**What `run_full.sh` automates:**
- `bootstrap.sh`: Installs dependencies, sets up a 4GB Swap file, boots Postgres/Redis, populates the 40,000-row seed database.
- `start_api.sh`: Starts the API on the correct port (8080 or 5000) with the correct configuration toggles.
- `sidecar.py`: Tracks precise carbon and energy emissions using CodeCarbon via a background daemon.
- `run_experiment.sh`: Randomizes the execution order of all 45 JMeter test combinations to eliminate thermal bias. Automatically handles Out-Of-Memory (OOM) JVM crashes gracefully.

### Step 3: Harvest and Clean the Data
Once the 2-hour experiments finish on all 6 VMs, you can download and clean the data locally from your laptop.

1. **Download the CSVs:**
   Run the download script from the root of this repository. It will `scp` all the results from the VMs into a local `downloaded_results/` folder:
   ```bash
   ./download_results.sh
   ```

2. **Clean "Ghost" Runs:**
   When the APIs crash completely, JMeter gets flooded with "Connection Refused" responses, generating fake high-throughput rows with 100% errors. Run the cleanup script to permanently filter out these ghosts while keeping legitimate timeouts:
   ```bash
   python3 clean_results.py
   ```

3. **Analyze Variance (CV):**
   Ensure your data is statistically sound by checking the Coefficient of Variation across the 3 runs for each cell:
   ```bash
   python3 analyze_cv.py
   ```

---