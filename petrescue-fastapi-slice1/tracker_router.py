from codecarbon import EmissionsTracker
from flask import Blueprint, jsonify, request

tracker_bp = Blueprint('tracker', __name__, url_prefix="/api/tracker")

active_tracker = None


@tracker_bp.route('/start', methods=['POST'])
def start_tracker():
    global active_tracker

    if active_tracker is not None:
        return jsonify({"message": "The sensor is already running!"}), 400

    data = request.get_json(silent=True) or {}
    experiment_name = data.get("experiment_name", "Unknown_test")

    active_tracker = EmissionsTracker(project_name=experiment_name, output_file=f"{experiment_name}.csv")
    active_tracker.start()

    return jsonify({"message": "CodeCarbon sensor started successfully."}), 200


@tracker_bp.route('/stop', methods=['POST'])
def stop_tracker():
    global active_tracker

    if active_tracker is None:
        return jsonify({"message": "The sensor is not started"}), 400

    emissions_kg = active_tracker.stop()
    active_tracker = None

    return jsonify({
        "message": "Sensor stopped successfully.",
        "emissions_kg": emissions_kg
    }), 200
