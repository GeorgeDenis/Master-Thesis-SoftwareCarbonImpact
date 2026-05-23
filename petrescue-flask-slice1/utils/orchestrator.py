import subprocess
import time

import requests

server_ip = "127.0.0.1"
server_port = "5000"
tracker_port = "5055"
config = "Baseline"
loads = [10, 50, 80]
repeats = 1

scenarios = {
    "ORM_Legacy": "/api/medical",
    "Without_Index": "/api/medical/search-disease",
    "Algorithm_List_O_N": "api/shelter/microchips"
}

for scenario_name, endpoint_path in scenarios.items():
    for load in loads:
        for run_id in range(1, repeats + 1):
            project_name = f"{config}_{load}_{scenario_name}_{run_id}"
            print(f"\n--- Starting test {project_name} ---")
            result_file = f"results/{project_name}.csv"

            cmd = [
                "jmeter",
                "-n",
                "-t", "master_plan-2.jmx",
                f"-Jserver_ip={server_ip}",
                f"-Jserver_port={server_port}",
                f"-Jthreads={load}",
                f"-Jduration=90",
                f"-Jproject_name={project_name}",
                f"-Jendpoint_path={endpoint_path}",
                "-l", result_file
            ]

            print("[1] Starting JMeter...")
            jmeter_process = subprocess.Popen(cmd)

            print("[2] WARM-UP: Waiting 30 seconds")
            time.sleep(30)

            print("[3] START MEASUREMENT")
            try:
                response = requests.post(
                    f"http://{server_ip}:{tracker_port}/start",
                    json={"experiment_name": project_name}
                )
                if response.status_code == 200:
                    print("CodeCarbon started!")
                else:
                    print(f"Server responded with error: {response.status_code}")
            except Exception as e:
                print(f"Critical error in server: {e}")

            print("[4] MEASURING: We record consumption for 60 seconds...")
            time.sleep(60)

            print("[5] STOP MEASUREMENT")
            try:
                requests.post(f"http://{server_ip}:{tracker_port}/stop")
            except Exception as e:
                print(f"Connection error to CodeCarbon: {e}")

            jmeter_process.wait()

            # print("[6] COOL-DOWN: Test complete. Waiting 60 seconds before the next...")
            # time.sleep(60)

        print("\nAll tests finished successfully!")

