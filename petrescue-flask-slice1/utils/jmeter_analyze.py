import pandas as pd

file_list = [
    'Baseline_10_ORM_Legacy_1.csv', 'Baseline_50_ORM_Legacy_1.csv', 'Baseline_80_ORM_Legacy_1.csv',
    'Baseline_10_Without_Index_1.csv', 'Baseline_50_Without_Index_1.csv', 'Baseline_80_Without_Index_1.csv',
    'Baseline_10_Algorithm_List_O_N_1.csv','Baseline_50_Algorithm_List_O_N_1.csv','Baseline_80_Algorithm_List_O_N_1.csv'
]


def analyze(filename):
    df = pd.read_csv(f'results/{filename}')

    start_time = df['timeStamp'].min()

    warmup_end = start_time + 30000
    measurement_end = warmup_end + 60000

    valid_requests = df[(df['timeStamp'] >= warmup_end) &
                        (df['timeStamp'] <= measurement_end) &
                        (df['success'] == True)]

    total_requests = len(valid_requests)

    print(f"Requests for {filename} completed in the measurement window: {total_requests}")


for file in file_list:
    analyze(file)
