import json
import mmap
import os
from collections import defaultdict

from database import SessionLocal
from domain_shelter.schemas import CreateShelterSchema, CreateAnimalSchema
from domain_shelter.models import Shelter, Animal
from exceptions import NotFoundException
from redis_client import redis_client

FILE_PATH = os.environ.get("PETRESCUE_MICROCHIP_FILE", "/tmp/petrescue_microchips.txt")
TARGET_CHIP = "CHIP-TARGET-MARKER"

CACHE_KEY = "petrescue:s5:heavy-statistics"
CACHE_TTL_SECONDS = 60


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


def verify_microchips_inefficient(incoming_codes):
    session = SessionLocal()

    db_chips_list = [a.microchip_code for a in session.query(Animal).all()]

    found_count = 0

    for chip in incoming_codes:
        if chip in db_chips_list:
            found_count += 1

    return {"totalInputs": len(incoming_codes), "dbSize": len(db_chips_list), "found": found_count}


def verify_microchips_efficient(incoming_codes):
    session = SessionLocal()

    db_chips_set = {a.microchip_code for a in session.query(Animal).all()}

    found_count = 0

    for chip in incoming_codes:
        if chip in db_chips_set:
            found_count += 1

    return {"totalInputs": len(incoming_codes), "dbSize": len(db_chips_set), "found": found_count}


def process_file_legacy():
    if not os.path.exists(FILE_PATH):
        return {"error": "File not found"}

    found = False
    bytes_scanned = 0
    with open(FILE_PATH, "r") as f:
        all_lines = f.readlines()

    for line in all_lines:
        bytes_scanned += len(line)
        if TARGET_CHIP in line:
            found = True
            break

    return {"found": found, "bytesScanned": bytes_scanned, "mmap": False}


def process_file_optimized():
    if not os.path.exists(FILE_PATH):
        return {"error": "File not found"}

    found = False
    bytes_scanned = 0
    with open(FILE_PATH, "rb") as f:
        with mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ) as mm:
            target_bytes = TARGET_CHIP.encode('utf-8')
            pos = mm.find(target_bytes)
            if pos != -1:
                found = True
                bytes_scanned = pos + len(target_bytes)
            else:
                bytes_scanned = mm.size()

    return {"found": found, "bytesScanned": bytes_scanned, "mmap": True}


def generate_heavy_statistics():
    session = SessionLocal()

    animals = session.query(Animal).all()

    stats = defaultdict(int)
    for animal in animals:
        visit_count = len(animal.medical_records)
        stats[animal.species] += visit_count

    return dict(stats)


def dashboard_stats_legacy():
    data = generate_heavy_statistics()

    return {
        "source": "db",
        "stats": data
    }


def dashboard_stats_optimized():
    cached = redis_client.get(CACHE_KEY)
    if cached is not None:
        data = json.loads(cached)
        return {"source": "cache", "stats": data}

    data = generate_heavy_statistics()
    redis_client.setex(CACHE_KEY, CACHE_TTL_SECONDS, json.dumps(data))
    return {"source": "db", "stats": data}
