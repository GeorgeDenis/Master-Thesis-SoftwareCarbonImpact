from flask import Blueprint, jsonify, request
from pydantic import ValidationError

from domain_medical.schemas import CreateMedicalSchema
from domain_medical.services import fetch_all_medicals, search_disease_heavy_load, add_medical, \
    fetch_all_medicals_optimized
from exceptions import NotFoundException
from toggles import s1_optimized

medical_bp = Blueprint('medical', __name__, url_prefix="/api/medical")


@medical_bp.route('/s1/medical-records', methods=['GET'])
def get_all_medicals():
    if s1_optimized():
        return jsonify(fetch_all_medicals_optimized()), 200
    else:
        return jsonify(fetch_all_medicals()), 200


@medical_bp.route('', methods=['POST'])
def post_medical():
    data = request.get_json()

    try:
        valid_medical_data = CreateMedicalSchema(**data)
    except ValidationError as e:
        return jsonify({"error": e.errors()}), 400

    try:
        result = add_medical(valid_medical_data)
        return jsonify(result), 201
    except NotFoundException as e:
        return jsonify({"error": e.message}), 404


@medical_bp.route('/s3/disease-search', methods=['GET'])
def search_disease_endpoint():
    result = search_disease_heavy_load()
    return jsonify(result), 200
