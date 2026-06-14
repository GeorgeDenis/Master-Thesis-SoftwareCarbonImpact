import os
import csv
import glob
import numpy as np
from collections import defaultdict

try:
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    import matplotlib.ticker as ticker
except ImportError:
    print("Installing matplotlib...")
    import subprocess
    subprocess.check_call(["pip3", "install", "matplotlib"])
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    import matplotlib.ticker as ticker

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
BASE_DIR = os.path.join(PROJECT_ROOT, "downloaded_results")
OUT_DIR = SCRIPT_DIR
os.makedirs(OUT_DIR, exist_ok=True)

COLORS = {
    'flask_baseline':    '#2166ac',
    'flask_optimized':   '#92c5de',
    'net_baseline':      '#b2182b',
    'net_optimized':     '#f4a582',
}

LABELS = {
    'flask_baseline':    'Flask Baseline',
    'flask_optimized':   'Flask Optimized',
    'net_baseline':      '.NET Baseline',
    'net_optimized':     '.NET Optimized',
}

SCENARIO_TITLES = {
    's1': 'S1 — ORM Overhead (N+1 Queries)',
    's2': 'S2 — Algorithmic Complexity (List vs. Set)',
    's3': 'S3 — Missing Database Index',
    's4': 'S4 — Synchronous File I/O',
    's5': 'S5 — Uncached Aggregation (Redis)',
}

INSTANCE_LABELS = {'m7i': 'm7i-flex\n(8GB, 100% CPU)', 'c7i': 'c7i-flex\n(4GB, 50% CPU)', 't3': 't3.small\n(2GB RAM)'}

def load_data():
    """Load all CSV data into nested dict: data[runtime][instance][scenario][config][users] = [runs...]"""
    data = defaultdict(lambda: defaultdict(lambda: defaultdict(lambda: defaultdict(lambda: defaultdict(list)))))

    for runtime in ["flask", "net"]:
        runtime_dir = os.path.join(BASE_DIR, runtime)
        if not os.path.exists(runtime_dir):
            continue
        for instance in ["m7i", "c7i", "t3"]:
            instance_dir = os.path.join(runtime_dir, instance)
            if not os.path.exists(instance_dir):
                continue
            csv_files = glob.glob(os.path.join(instance_dir, "*.csv"))
            for csv_path in csv_files:
                with open(csv_path, "r") as f:
                    reader = csv.DictReader(f)
                    for row in reader:
                        scenario = row["scenario"]
                        config = row["config"]
                        users = int(row["users"])
                        reqs = float(row["requests_total"])
                        errs = float(row["errors"])

                        if errs >= reqs and reqs > 0:
                            continue

                        emissions_mg = float(row["co2_kg"]) * 1_000_000
                        duration = float(row["duration_s"])
                        good_reqs = reqs - errs
                        if good_reqs > 0:
                            co2_per_req = emissions_mg / good_reqs
                        else:
                            continue

                        data[runtime][instance][scenario][config][users].append({
                            "duration": duration,
                            "reqs": reqs,
                            "errs": errs,
                            "emissions_mg": emissions_mg,
                            "co2_per_req": co2_per_req,
                        })
    return data

def avg_co2_per_req(data, runtime, instance, scenario, config, users):
    """Get average CO2/req for a specific cell. Returns None if no data."""
    runs = data[runtime][instance][scenario][config][users]
    if not runs:
        return None
    return np.mean([r["co2_per_req"] for r in runs])

def run_count(data, runtime, instance, scenario, config, users):
    """Get number of valid runs for a specific cell."""
    return len(data[runtime][instance][scenario][config][users])

def avg_co2_per_req_values(data, runtime, instance, scenario, config, users):
    """Get list of CO2/req values for CV calculation."""
    runs = data[runtime][instance][scenario][config][users]
    if not runs:
        return []
    return [r["co2_per_req"] for r in runs]

def smart_label(val):
    """Format a value label with appropriate precision."""
    if val >= 100:
        return f'{val:.0f}'
    elif val >= 1:
        return f'{val:.2f}'
    elif val >= 0.01:
        return f'{val:.3f}'
    else:
        return f'{val:.4f}'

def generate_scenario_chart(data, scenario, filename):
    """Grouped bar chart: Baseline vs Optimized, Flask & .NET, all 3 instances, 80 users."""
    fig, ax = plt.subplots(figsize=(12, 6))

    instances = ['m7i', 'c7i', 't3']
    groups = ['flask_baseline', 'flask_optimized', 'net_baseline', 'net_optimized']
    configs = [('flask', 'baseline'), ('flask', 'optimized'), ('net', 'baseline'), ('net', 'optimized')]

    x = np.arange(len(instances))
    width = 0.18
    offsets = [-1.5, -0.5, 0.5, 1.5]

    has_missing = False
    max_val = 0

    for i, (group_key, (runtime, config)) in enumerate(zip(groups, configs)):
        values = []
        for inst in instances:
            v = avg_co2_per_req(data, runtime, inst, scenario, config, 80)
            if v is None:
                values.append(0)
                has_missing = True
            else:
                values.append(v)
                max_val = max(max_val, v)

        bars = ax.bar(x + offsets[i] * width, values, width,
                      label=LABELS[group_key], color=COLORS[group_key],
                      edgecolor='white', linewidth=0.5)

        for j, (bar, val) in enumerate(zip(bars, values)):
            if val > 0:
                label_text = smart_label(val)
                y_pos = bar.get_height()
                ax.text(bar.get_x() + bar.get_width()/2., y_pos,
                       label_text, ha='center', va='bottom', fontsize=7, rotation=45)
            else:
                ax.text(bar.get_x() + bar.get_width()/2., max_val * 0.01,
                       '✗', ha='center', va='bottom', fontsize=10, color='red', fontweight='bold')

    if max_val > 0:
        vals_nonzero = []
        for runtime, config in configs:
            for inst in instances:
                v = avg_co2_per_req(data, runtime, inst, scenario, config, 80)
                if v and v > 0:
                    vals_nonzero.append(v)
        if vals_nonzero and max(vals_nonzero) / max(min(vals_nonzero), 0.0001) > 50:
            ax.set_yscale('log')
            ax.yaxis.set_major_formatter(ticker.ScalarFormatter())
            ax.yaxis.get_major_formatter().set_scientific(False)

    ax.set_xlabel('Hardware Profile', fontsize=12)
    ax.set_ylabel('CO₂ per Successful Request (mg)', fontsize=12)
    ax.set_title(f'{SCENARIO_TITLES[scenario]}\nBaseline vs. Optimized — 80 Concurrent Users', fontsize=13, fontweight='bold')
    ax.set_xticks(x)
    ax.set_xticklabels([INSTANCE_LABELS[i] for i in instances], fontsize=10)
    ax.legend(loc='upper left', fontsize=9)
    ax.grid(axis='y', alpha=0.3)

    if has_missing:
        ax.annotate('✗ = Ghost run (dropped)', xy=(0.98, 0.02), xycoords='axes fraction',
                    ha='right', va='bottom', fontsize=9, color='red',
                    bbox=dict(boxstyle='round,pad=0.3', facecolor='lightyellow', edgecolor='red', alpha=0.8))

    plt.tight_layout()
    filepath = os.path.join(OUT_DIR, filename)
    plt.savefig(filepath, dpi=200, bbox_inches='tight')
    plt.close()
    print(f"  Saved: {filepath}")

def generate_load_scaling_chart(data, scenario, filename):
    """Line chart: CO₂/req at 10/50/80 users across all 3 instances (m7i, c7i, t3), baseline only.
    Annotates data points with run counts when < 3 valid runs."""
    fig, ax = plt.subplots(figsize=(10, 6))

    users_list = [10, 50, 80]
    lines = [
        ('flask', 'm7i', '--', 'o', COLORS['flask_baseline'], 'Flask — m7i'),
        ('flask', 'c7i', ':', '*', COLORS['flask_baseline'], 'Flask — c7i'),
        ('flask', 't3', '-', 's', COLORS['flask_baseline'], 'Flask — t3'),
        ('net', 'm7i', '--', '^', COLORS['net_baseline'], '.NET — m7i'),
        ('net', 'c7i', ':', 'X', COLORS['net_baseline'], '.NET — c7i'),
        ('net', 't3', '-', 'D', COLORS['net_baseline'], '.NET — t3'),
    ]

    max_val = 0
    min_val = float('inf')
    for runtime, instance, linestyle, marker, color, label in lines:
        values = []
        valid_users = []
        run_counts = []
        for u in users_list:
            v = avg_co2_per_req(data, runtime, instance, scenario, 'baseline', u)
            if v is not None:
                values.append(v)
                valid_users.append(u)
                run_counts.append(run_count(data, runtime, instance, scenario, 'baseline', u))
                max_val = max(max_val, v)
                min_val = min(min_val, v)

        if values:
            ax.plot(valid_users, values, linestyle=linestyle, marker=marker,
                   color=color, label=label, linewidth=2, markersize=8)
            for u, v, n in zip(valid_users, values, run_counts):
                label_text = smart_label(v)
                if n < 3:
                    label_text += f'\n(N={n})'
                
                y_offset = 8 if runtime == 'flask' else -15
                ax.annotate(label_text, (u, v), textcoords="offset points",
                          xytext=(0, y_offset), ha='center', fontsize=8)

    if min_val > 0 and max_val / min_val > 20:
        ax.set_yscale('log')

    ax.set_xlabel('Concurrent Users', fontsize=12)
    ax.set_ylabel('CO₂ per Successful Request (mg) — Baseline', fontsize=12)
    ax.set_title(f'{SCENARIO_TITLES[scenario]}\nLoad Scaling: Baseline CO₂/Request (m7i vs. c7i vs. t3)', fontsize=13, fontweight='bold')
    ax.set_xticks(users_list)
    ax.legend(fontsize=10, loc='center left', bbox_to_anchor=(1, 0.5))
    ax.grid(alpha=0.3)

    plt.tight_layout()
    filepath = os.path.join(OUT_DIR, filename)
    plt.savefig(filepath, dpi=200, bbox_inches='tight')
    plt.close()
    print(f"  Saved: {filepath}")

def avg_metric(data, runtime, instance, scenario, config, users, metric_func):
    """Helper to average any derived metric across runs."""
    runs = data[runtime][instance][scenario][config][users]
    if not runs:
        return None
    return np.mean([metric_func(r) for r in runs])

def generate_markdown_tables(data, filename):
    """Generates markdown tables containing rich operational data for each scenario at 80 users."""
    filepath = os.path.join(OUT_DIR, filename)
    with open(filepath, 'w') as f:
        f.write("# Chapter 3 Data Tables\n\n")
        f.write("Averages across 3 runs for **80 concurrent users**. Ghost runs (100% failure rate) are excluded.\n\n")

        for scenario in ['s1', 's2', 's3', 's4', 's5']:
            f.write(f"### {SCENARIO_TITLES[scenario]}\n\n")
            f.write("| Instance | Configuration | Runtime | Avg Duration (s) | Avg Succ. Reqs | Avg Total CO₂ (mg) | CO₂/Req (mg) |\n")
            f.write("|---|---|---|---|---|---|---|\n")

            for inst in ['m7i', 'c7i', 't3']:
                for config in ['baseline', 'optimized']:
                    for runtime in ['flask', 'net']:
                        runs = data[runtime][inst][scenario][config][80]
                        if not runs:
                            f.write(f"| {inst} | {config} | {runtime} | `Ghost Run` | `0` | `-` | `-` |\n")
                            continue

                        duration = np.mean([r["duration"] for r in runs])
                        succ_reqs = np.mean([r["reqs"] - r["errs"] for r in runs])
                        total_co2 = np.mean([r["emissions_mg"] for r in runs])
                        co2_per_req = np.mean([r["co2_per_req"] for r in runs])

                        f.write(f"| {inst} | {config} | {runtime} | {duration:.1f} | {succ_reqs:.0f} | {total_co2:.1f} | **{smart_label(co2_per_req)}** |\n")
            f.write("\n")
    print(f"\nMarkdown tables saved to: {filepath}")

def generate_lift_shift_chart(data, filename):
    """Bar chart: S1 baseline CO₂/req across m7i → c7i → t3 for both runtimes."""
    fig, ax = plt.subplots(figsize=(10, 6))

    instances = ['m7i', 'c7i', 't3']
    x = np.arange(len(instances))
    width = 0.3

    flask_vals = []
    net_vals = []
    for inst in instances:
        fv = avg_co2_per_req(data, 'flask', inst, 's1', 'baseline', 80)
        nv = avg_co2_per_req(data, 'net', inst, 's1', 'baseline', 80)
        flask_vals.append(fv if fv else 0)
        net_vals.append(nv if nv else 0)

    bars1 = ax.bar(x - width/2, flask_vals, width, label='Flask Baseline',
                   color=COLORS['flask_baseline'], edgecolor='white')
    bars2 = ax.bar(x + width/2, net_vals, width, label='.NET Baseline',
                   color=COLORS['net_baseline'], edgecolor='white')

    for bars, vals in [(bars1, flask_vals), (bars2, net_vals)]:
        for bar, val in zip(bars, vals):
            if val > 0:
                label = f'{val:.1f}' if val < 100 else f'{val:.0f}'
                ax.text(bar.get_x() + bar.get_width()/2., bar.get_height(),
                       label, ha='center', va='bottom', fontsize=10, fontweight='bold')
            else:
                ax.text(bar.get_x() + bar.get_width()/2., 10,
                       'CRASHED\n(Ghost Run)', ha='center', va='bottom', fontsize=8,
                       color='red', fontweight='bold')

    m7i_net = net_vals[0]
    t3_net = net_vals[2]
    if m7i_net > 0 and t3_net > 0:
        multiplier = t3_net / m7i_net
        ax.annotate(f'{multiplier:.0f}x more\ncarbon',
                   xy=(2.15, t3_net * 0.7), fontsize=12, fontweight='bold',
                   color='red', ha='center',
                   bbox=dict(boxstyle='round,pad=0.4', facecolor='lightyellow', edgecolor='red'))

    ax.set_yscale('log')
    ax.yaxis.set_major_formatter(ticker.ScalarFormatter())
    ax.yaxis.get_major_formatter().set_scientific(False)

    ax.set_xlabel('Hardware Profile (Cloud Instance)', fontsize=12)
    ax.set_ylabel('CO₂ per Successful Request (mg) — Log Scale', fontsize=12)
    ax.set_title('The "Lift and Shift" Danger: S1 (N+1 Queries) Baseline\nCarbon Cost Across Hardware Profiles — 80 Concurrent Users',
                fontsize=13, fontweight='bold')
    ax.set_xticks(x)
    ax.set_xticklabels([INSTANCE_LABELS[i] for i in instances], fontsize=10)
    ax.legend(fontsize=11)
    ax.grid(axis='y', alpha=0.3)

    plt.tight_layout()
    filepath = os.path.join(OUT_DIR, filename)
    plt.savefig(filepath, dpi=200, bbox_inches='tight')
    plt.close()
    print(f"  Saved: {filepath}")

if __name__ == "__main__":
    print("Loading experimental data...")
    data = load_data()

    print("\nGenerating scenario comparison charts (Charts 1-5)...")
    for scenario in ['s1', 's2', 's3', 's4', 's5']:
        generate_scenario_chart(data, scenario, f'chart_{scenario}_comparison.png')

    print("\nGenerating load scaling charts (Charts 6-10)...")
    for scenario in ['s1', 's2', 's3', 's4', 's5']:
        generate_load_scaling_chart(data, scenario, f'chart_{scenario}_load_scaling.png')

    print("\nGenerating Lift & Shift multiplier chart (Chart 8)...")
    generate_lift_shift_chart(data, 'chart_lift_shift_s1.png')

    print("\nGenerating Markdown Data Tables...")
    generate_markdown_tables(data, 'scenario_tables.md')

    print(f"\nAll charts and tables saved to: {OUT_DIR}")
    print("Done.")
