from sqlalchemy import text

from database import SessionLocal
from domain_medical.models import MedicalRecord
from domain_medical.schemas import CreateMedicalSchema
from domain_shelter.services import find_animal_by_id
from exceptions import NotFoundException
from toggles import s3_optimized


def add_medical(medical: CreateMedicalSchema):
    animal = find_animal_by_id(medical.animal_id)

    if not animal:
        raise NotFoundException(f"Animal with id {medical.animal_id} not found")

    session = SessionLocal()

    new_medical = MedicalRecord(
        animal_id=medical.animal_id,
        disease=medical.disease,
        treatment=medical.treatment
    )

    session.add(new_medical)
    session.commit()

    return {
        "message": "Medical record added successfully",
        "id": new_medical.id
    }


def fetch_all_medicals():
    medical_records = SessionLocal.query(MedicalRecord).all()

    projected = []
    for m in medical_records:
        animal_name = m.animal.name if m.animal else "(unknown)"
        projected.append({
            "id": m.id,
            "disease": m.disease,
            "treatment": m.treatment,
            "AnimalName": animal_name
        })

    return {"count": len(projected), "sample": projected[:3]}


def fetch_all_medicals_optimized():
    session = SessionLocal()

    query = text("""
                 SELECT m.id,
                        m.animal_id,
                        m.disease,
                        m.treatment,
                        m.visit_date,
                        a.name as animal_name
                 FROM medical_records m
                          JOIN animals a ON m.animal_id = a.id;
                 """)

    result_proxy = session.execute(query)

    projected = []
    for row in result_proxy:
        projected.append({
            "id": row.id,
            "disease": row.disease,
            "treatment": row.treatment,
            "AnimalName": row.animal_name
        })

    return {"count": len(projected), "sample": projected[:3]}


def search_disease_heavy_load():
    session = SessionLocal()
    target_disease = "Parvovirus"
    iteration_count = 500

    total_found = 0

    query = text("SELECT COUNT(*) FROM medical_records WHERE disease = :disease")

    for _ in range(iteration_count):
        result = session.execute(query, {"disease": target_disease}).scalar()
        total_found += result

    return {
        "iterations": iteration_count,
        "disease": target_disease,
        "total": total_found,
        "indexed": s3_optimized()
    }
