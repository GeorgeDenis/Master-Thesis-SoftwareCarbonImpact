from flask import Blueprint, request
from flask import jsonify
from pydantic import ValidationError

from domain_shelter.schemas import CreateShelterSchema, CreateAnimalSchema
from domain_shelter.services import (
    fetch_all_shelters, verify_microchips_inefficient, process_file_legacy,
    dashboard_stats_legacy, add_shelter, fetch_all_animals, add_animal,
    verify_microchips_efficient, process_file_optimized, dashboard_stats_optimized,
)
from exceptions import NotFoundException
from toggles import s2_optimized, s4_optimized, s5_optimized

shelter_bp = Blueprint('shelter', __name__, url_prefix="/api/shelter")


@shelter_bp.route('', methods=['GET'])
def get_all_shelters():
    result = fetch_all_shelters()
    return jsonify(result), 200


@shelter_bp.route('', methods=['POST'])
def post_shelter():
    data = request.get_json()

    try:
        valid_shelter_data = CreateShelterSchema(**data)
    except ValidationError as e:
        return jsonify({"error": e.errors()}), 400

    result = add_shelter(valid_shelter_data)

    return jsonify(result), 201


@shelter_bp.route('/animal', methods=['GET'])
def get_all_animals():
    result = fetch_all_animals()
    return jsonify(result), 200


@shelter_bp.route('/animal', methods=['POST'])
def post_animal():
    data = request.get_json()

    try:
        valid_animal_data = CreateAnimalSchema(**data)
    except ValidationError as e:
        return jsonify({"error": e.errors()}), 400

    try:
        result = add_animal(valid_animal_data)
        return jsonify(result), 201
    except NotFoundException as e:
        return jsonify({"error": e.message}), 404


@shelter_bp.route('/s2/microchip-match', methods=['POST'])
def check_chips():
    """
    S2 – Algorithmic complexity.
    Accepts POST with JSON body: { "codes": ["MC-00000001", ...] }
    Matches .NET S2 POST /api/s2/microchip-match contract.
    """
    data = request.get_json(silent=True) or {}
    codes = data.get("codes", [])

    if s2_optimized():
        return jsonify(verify_microchips_efficient(codes)), 200
    else:
        return jsonify(verify_microchips_inefficient(codes)), 200


@shelter_bp.route('/s4/file-search', methods=['GET'])
def import_legacy():
    if s4_optimized():
        return jsonify(process_file_optimized()), 200
    else:
        return jsonify(process_file_legacy()), 200


@shelter_bp.route('/s5/heavy-statistics', methods=['GET'])
def get_stats():
    if s5_optimized():
        result = dashboard_stats_optimized()
    else:
        result = dashboard_stats_legacy()
    return jsonify(result), 200
