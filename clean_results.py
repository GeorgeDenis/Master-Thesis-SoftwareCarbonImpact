import os
import pandas as pd
import glob

def clean_csvs(root_dir="downloaded_results"):
    csv_files = glob.glob(f"{root_dir}/**/*.csv", recursive=True)
    
    for file_path in csv_files:
        try:
            df = pd.read_csv(file_path)
            
            # The teacher's signature for a connection refused flood:
            # ~900k-1M cereri, 100% erori, ~15.000 rps.
            # So we only drop rows that are 100% errors AND have an absurdly high request count/throughput.
            # A "real collapse" (e.g. 80 requests, 80 errors, taking 23 seconds) will be kept!
            
            initial_count = len(df)
            
            # Condition for "flood": 100% errors AND more than 10,000 requests
            is_flood = (df['errors'] == df['requests_total']) & (df['requests_total'] > 10000)
            
            df_cleaned = df[~is_flood]
            final_count = len(df_cleaned)
            
            if initial_count != final_count:
                print(f"Cleaned {initial_count - final_count} ghost 'flood' rows from {file_path}")
                # Overwrite with cleaned data
                df_cleaned.to_csv(file_path, index=False)
            
        except Exception as e:
            print(f"Error processing {file_path}: {e}")

if __name__ == "__main__":
    clean_csvs()
    print("CSV cleaning complete!")
