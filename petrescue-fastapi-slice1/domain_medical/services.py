from sqlalchemy import text

from database import SessionLocal
from domain_medical.models import MedicalRecord
from domain_medical.schemas import CreateMedicalSchema
from domain_shelter.services import find_animal_by_id
from exceptions import NotFoundException


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

    result = [{"id": m.id,
               "animal_id": m.animal_id,
               "disease": m.disease,
               "treatment": m.treatment,
               "visit_date": m.visit_date.isoformat() if m.visit_date else None,
               "animal_name": m.animal.name} for m in medical_records]
    return result

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
                          JOIN animals a ON m.animal_id = a.id LIMIT 1000;
                 """)

    result_proxy = session.execute(query)

    result = []
    for row in result_proxy:
        result.append({
            "id": row.id,
            "animal_id": row.animal_id,
            "disease": row.disease,
            "treatment": row.treatment,
            "visit_date": row.visit_date.isoformat() if row.visit_date else None,
            "animal_name": row.animal_name
        })

    return result


def search_disease_heavy_load():
    session = SessionLocal()
    target_disease = "Parvovirus"

    total_found = 0

    query = text("SELECT COUNT(*) FROM medical_records WHERE disease = :disease")

    for _ in range(500):
        result = session.execute(query, {"disease": target_disease}).scalar()
        total_found += result

    return {"searches_performed": 500, "records_found": total_found}
