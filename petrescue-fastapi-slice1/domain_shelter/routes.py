import uuid

from decouple import config
from flask import Blueprint, request
from flask import jsonify
from pydantic import ValidationError

from domain_shelter.schemas import CreateShelterSchema, CreateAnimalSchema
from domain_shelter.services import fetch_all_shelters, verify_microchips_inefficient, process_file_legacy, \
    dashboard_stats_legacy, add_shelter, fetch_all_animals, add_animal, verify_microchips_efficient, \
    process_file_optimized
from exceptions import NotFoundException

shelter_bp = Blueprint('shelter', __name__, url_prefix="/api/shelter")

MOCK_INCOMING_CHIPS = [str(uuid.uuid4()) for _ in range(20000)]

IS_OPTIMIZED = config("IS_OPTIMIZED")


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


@shelter_bp.route('/s2/microchip-match', methods=['GET'])
# @measure_emissions(project_name="1_Algorithm_List_O_N")
def check_chips_legacy():
    if IS_OPTIMIZED:
        return jsonify(verify_microchips_efficient(MOCK_INCOMING_CHIPS)), 200
    else:
        return jsonify(verify_microchips_inefficient(MOCK_INCOMING_CHIPS)), 200


@shelter_bp.route('/s4/file-search', methods=['GET'])
# @measure_emissions(project_name="Legacy_Readlines")
def import_legacy():
    if IS_OPTIMIZED:
        return jsonify(process_file_optimized()), 200
    else:
        return jsonify(process_file_legacy()), 200


@shelter_bp.route('/s5/heavy-statistics', methods=['GET'])
# @measure_emissions(project_name="Without_Cache")
def get_stats_legacy():
    result = dashboard_stats_legacy()
    return jsonify(result), 200
