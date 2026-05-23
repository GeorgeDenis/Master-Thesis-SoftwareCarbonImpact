import os
import pandas as pd

def analyze_averaged_runs(base_filename, num_runs=3):
    all_runs_data = []

    for i in range(1, num_runs + 1):
        path = f'../{base_filename}_{i}.csv'

        if not os.path.exists(path):
            continue

        df = pd.read_csv(path)

        df['duration_s'] = df['duration']
        df['emissions_mg'] = df['emissions'] * 1_000_000

        df_run_total = df.groupby('project_name').agg({
            'duration_s': 'sum',
            'emissions_mg': 'sum',
        }).reset_index()

        df_run_total['project_name'] = base_filename

        all_runs_data.append(df_run_total)

    if not all_runs_data:
        return

    combined_df = pd.concat(all_runs_data)

    df_final_average = combined_df.groupby('project_name').agg({
        'duration_s': 'mean',
        'emissions_mg': 'mean',
    }).reset_index()

    print(f"\nLoad testing AVERAGE results ({len(all_runs_data)} runs):")
    print(df_final_average)

files = [
    'Baseline_10_Algorithm_List_O_N', 'Baseline_50_Algorithm_List_O_N', 'Baseline_80_Algorithm_List_O_N',
    'Baseline_10_ORM_Legacy', 'Baseline_50_ORM_Legacy', 'Baseline_80_ORM_Legacy',
    'Baseline_10_Legacy_Readlines', 'Baseline_50_Legacy_Readlines', 'Baseline_80_Legacy_Readlines',
    'Baseline_10_Without_Cache', 'Baseline_50_Without_Cache', 'Baseline_80_Without_Cache',
    'Baseline_10_Without_Index', 'Baseline_50_Without_Index', 'Baseline_80_Without_Index'
]

for file in files:
    analyze_averaged_runs(file)
