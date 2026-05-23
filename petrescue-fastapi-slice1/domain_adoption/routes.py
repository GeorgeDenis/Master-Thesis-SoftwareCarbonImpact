from flask import Blueprint, jsonify, request
from pydantic import ValidationError

from domain_adoption.schemas import AddAdopterSchema, AddAdoptionSchema
from domain_adoption.services import fetch_all_adopters, add_adopter, add_adoption
from exceptions import AdopterAlreadyExists, NotFoundException, AnimalCantBeAdopted

adoption_bp = Blueprint('adoption', __name__, url_prefix="/api/adoption")


@adoption_bp.route('/adopter', methods=['GET'])
def get_all_adopters():
    result = fetch_all_adopters()
    return jsonify(result), 200


@adoption_bp.route('/adopter', methods=['POST'])
def post_adopter():
    data = request.get_json()

    try:
        valid_adopter_data = AddAdopterSchema(**data)
    except ValidationError as e:
        return jsonify({"error": e.errors()}), 400
    try:
        result = add_adopter(valid_adopter_data)
    except AdopterAlreadyExists as e:
        return jsonify({"error": e.message}), 409

    return jsonify(result), 201


@adoption_bp.route('', methods=['POST'])
def post_adoption():
    data = request.get_json()
    try:
        valid_adoption_data = AddAdoptionSchema(**data)
    except ValidationError as e:
        return jsonify({"error": e.errors()}), 400

    try:
        result = add_adoption(valid_adoption_data)
    except NotFoundException as e:
        return jsonify({"error": e.message}), 404
    except AnimalCantBeAdopted as e:
        return jsonify({"error": e.message}), 409

    return jsonify(result), 201
