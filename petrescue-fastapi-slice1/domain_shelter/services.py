import mmap
import os

from sqlalchemy import text

from database import SessionLocal
from domain_shelter.schemas import CreateShelterSchema, CreateAnimalSchema
from domain_shelter.models import Shelter, Animal
from exceptions import NotFoundException


def find_shelter_by_id(shelter_id: int):
    session = SessionLocal()
    shelter = session.query(Shelter).filter(Shelter.id == shelter_id).first()
    if not shelter:
        raise NotFoundException(f"Shelter with id {shelter_id} not found.")
    return shelter


def find_animal_by_id(animal_id: int):
    session = SessionLocal()
    animal = session.query(Animal).filter(Animal.id == animal_id).first()

    return animal


def add_shelter(shelter: CreateShelterSchema):
    session = SessionLocal()

    new_shelter = Shelter(
        name=shelter.name,
        location=shelter.location,
    )

    session.add(new_shelter)
    session.commit()

    return {
        "message": "Shelter added successfully",
        "id": new_shelter.id
    }


def fetch_all_shelters():
    session = SessionLocal()

    shelters = session.query(Shelter).all()
    result = [{"id": s.id, "name": s.name, "location": s.location} for s in shelters]

    return result


def add_animal(animal: CreateAnimalSchema):
    find_shelter_by_id(animal.shelter_id)

    session = SessionLocal()

    new_animal = Animal(
        name=animal.name,
        species=animal.species,
        microchip_code=animal.microchip_code,
        shelter_id=animal.shelter_id,
    )

    session.add(new_animal)
    session.commit()

    return {
        "message": "Animal added successfully",
        "id": new_animal.id
    }


def fetch_all_animals():
    session = SessionLocal()

    animals = session.query(Animal).all()
    result = [{"id": a.id, "name": a.name, "species": a.species, "microchip_code": a.microchip_code, "status": a.status,
               "shelter_id": a.shelter_id}
              for a in animals]
    return result


def verify_microchips_inefficient(microchip_data):
    session = SessionLocal()

    db_chips_list = [a.microchip_code for a in session.query(Animal).all()]

    found_count = 0

    for chip in microchip_data:
        if chip in db_chips_list:
            found_count += 1

    return {"found": found_count, "total_checked": len(microchip_data)}

def verify_microchips_efficient(microchip_data):
    session = SessionLocal()

    db_chips_set = {a.microchip_code for a in session.query(Animal).all()}

    found_count = 0

    for chip in microchip_data:
        if chip in db_chips_set:
            found_count += 1

    return {"found": found_count, "total_checked": len(microchip_data)}

FILE_PATH = "large_microchips.csv"
TARGET_CHIP = "FIND_ME_SPECIAL_CHIP_999"


def process_file_legacy():
    if not os.path.exists(FILE_PATH):
        return {"error": "File not found"}

    found = False
    with open(FILE_PATH, "r") as f:
        all_lines = f.readlines()

    for line in all_lines:
        if TARGET_CHIP in line:
            found = True
            break

    return {"status": "success", "found": found, "method": "readlines"}

def process_file_optimized():
    if not os.path.exists(FILE_PATH):
        return {"error": "File not found"}

    found = False
    with open(FILE_PATH, "rb") as f:
        with mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ) as mm:
            target_bytes = TARGET_CHIP.encode('utf-8')

            if mm.find(target_bytes) != -1:
                found = True

    return {"status": "success", "found": found, "method": "mmap"}


def generate_heavy_statistics():
    session = SessionLocal()

    query = text("""
                 SELECT a.species, COUNT(m.id) as total_visits
                 FROM animals a
                          LEFT JOIN medical_records m ON a.id = m.animal_id
                 GROUP BY a.species
                 """)

    result_proxy = session.execute(query)

    stats = {row.species: row.total_visits for row in result_proxy}
    return stats


def dashboard_stats_legacy():
    data = generate_heavy_statistics()

    return {
        "cache_hit": False,
        "data": data
    }

IN_MEMORY_CACHE = {}

def dashboard_stats_optimized():
    results = []
    cache_hits = False

    if "dashboard_report" in IN_MEMORY_CACHE:
        data = IN_MEMORY_CACHE["dashboard_report"]
        cache_hits = True
        results.append(data)
    else:
        data = generate_heavy_statistics()
        IN_MEMORY_CACHE["dashboard_report"] = data
        results.append(data)

    return {"cache_hits": cache_hits, "data": data}

