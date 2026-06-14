#!/usr/bin/env python3
"""
CodeCarbon sidecar service.

This is a small, deliberately minimal HTTP service whose only job is to wrap
CodeCarbon's EmissionsTracker behind two endpoints that JMeter (or the
orchestration script) can hit before and after a test window.

It is intentionally language-agnostic. The .NET application under test does not
import or know about this service. Measurement is at the host level, which is
the correct granularity for a single-tenant test machine.

Endpoints:
    POST /start            Start tracking. Body: { "experiment_name": "...", "tags": {...} }
    POST /stop             Stop tracking. Returns the emissions row as JSON.
    GET  /status           Whether a tracker is currently running.
    GET  /health           Liveness check.

Output:
    A CSV file per run, written to ./emissions/<experiment_name>.csv,
    appended-to if it already exists. Schema follows CodeCarbon's default.

Run:
    python sidecar.py
"""
import os
import threading
import datetime as dt
from pathlib import Path

from flask import Flask, request, jsonify
from codecarbon import EmissionsTracker

app = Flask(__name__)

OUTPUT_DIR = Path(os.environ.get("CODECARBON_OUTPUT_DIR", "./emissions")).resolve()
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

_tracker_lock = threading.Lock()
_tracker: EmissionsTracker | None = None
_current_experiment: str | None = None
_started_at_utc: str | None = None


@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "ok", "output_dir": str(OUTPUT_DIR)})


@app.route("/status", methods=["GET"])
def status():
    with _tracker_lock:
        return jsonify({
            "running": _tracker is not None,
            "experiment_name": _current_experiment,
            "started_at_utc": _started_at_utc
        })


@app.route("/start", methods=["POST"])
def start():
    global _tracker, _current_experiment, _started_at_utc
    with _tracker_lock:
        if _tracker is not None:
            return jsonify({"error": "tracker already running",
                            "experiment_name": _current_experiment}), 409

        payload = request.get_json(silent=True) or {}
        experiment_name = payload.get("experiment_name", "unnamed_experiment")
        output_file = f"{experiment_name}.csv"

        _tracker = EmissionsTracker(
            project_name=experiment_name,
            output_dir=str(OUTPUT_DIR),
            output_file=output_file,
            measure_power_secs=1,
            tracking_mode="machine",
            log_level="warning",
            save_to_file=True,
        )
        _tracker.start()
        _current_experiment = experiment_name
        _started_at_utc = dt.datetime.now(dt.timezone.utc).isoformat()
        return jsonify({
            "ok": True,
            "experiment_name": experiment_name,
            "output_file": str(OUTPUT_DIR / output_file),
            "started_at_utc": _started_at_utc
        })


@app.route("/stop", methods=["POST"])
def stop():
    global _tracker, _current_experiment, _started_at_utc
    with _tracker_lock:
        if _tracker is None:
            return jsonify({"error": "no tracker running"}), 409

        emissions_kg = _tracker.stop()
        details = {}
        for attr in ("final_emissions_data", "_total_energy", "_total_cpu_energy",
                     "_total_gpu_energy", "_total_ram_energy"):
            if hasattr(_tracker, attr):
                v = getattr(_tracker, attr)
                if hasattr(v, "__dict__"):
                    details[attr] = {k: str(val) for k, val in vars(v).items()}
                else:
                    details[attr] = str(v)

        result = {
            "ok": True,
            "experiment_name": _current_experiment,
            "started_at_utc": _started_at_utc,
            "stopped_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
            "emissions_kg": emissions_kg,
            "details": details
        }
        _tracker = None
        _current_experiment = None
        _started_at_utc = None
        return jsonify(result)


if __name__ == "__main__":
    port = int(os.environ.get("CODECARBON_SIDECAR_PORT", "5055"))
    app.run(host="127.0.0.1", port=port, threaded=False)
