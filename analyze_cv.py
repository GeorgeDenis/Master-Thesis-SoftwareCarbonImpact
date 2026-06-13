import csv, statistics as s
import glob
from collections import defaultdict
import os

def analyze_cv(root_dir="downloaded_results"):
    csv_files = glob.glob(f"{root_dir}/**/*.csv", recursive=True)
    if not csv_files:
        print("No CSV files found in downloaded_results/")
        return

    for file_path in csv_files:
        print(f"\n=============================================")
        print(f"Analyzing: {os.path.relpath(file_path)}")
        print(f"=============================================")
        
        groups = defaultdict(list)
        try:
            with open(file_path) as f:
                for r in csv.DictReader(f):
                    key = (r["scenario"], r["config"], r["users"])
                    groups[key].append(float(r["co2_per_req_mg"]))
            
            print(f"{'scenario':<6} {'config':<10} {'users':<6} {'mean_mg':>8} {'sd_mg':>8} {'cv':>7}  {'n':>3}")
            print("-" * 58)
            
            for k, vs in sorted(groups.items(), key=lambda x: (x[0][0], x[0][1] != 'baseline', int(x[0][2]))):
                m = s.mean(vs)
                sd = s.stdev(vs) if len(vs) > 1 else 0.0
                cv = sd / m if m else 0
                flag = " *** HIGH CV" if cv > 0.30 else (" * check" if cv > 0.15 else "")
                print(f"{k[0]:<6} {k[1]:<10} {k[2]:<6} {m:>8.3f} {sd:>8.3f} {cv:>7.1%}  {len(vs):>3}{flag}")
        except Exception as e:
            print(f"Failed to analyze: {e}")

if __name__ == "__main__":
    analyze_cv()
