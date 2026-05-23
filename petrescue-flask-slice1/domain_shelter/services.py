import json
import mmap
import os

from sqlalchemy import text

from database import SessionLocal
from domain_shelter.schemas import CreateShelterSchema, CreateAnimalSchema
from domain_shelter.models import Shelter, Animal
from exceptions import NotFoundException
from redis_client import redis_client

# ---------------------------------------------------------------------------
# S4 – File I/O configuration
# Matches .NET: env var PETRESCUE_MICROCHIP_FILE, target marker CHIP-TARGET-MARKER
# ---------------------------------------------------------------------------
FILE_PATH = os.environ.get("PETRESCUE_MICROCHIP_FILE", "/tmp/petrescue_microchips.txt")
TARGET_CHIP = "CHIP-TARGET-MARKER"

# ---------------------------------------------------------------------------
# S5 – Redis cache configuration
# Matches .NET: key prefix "petrescue:", cache key "s5:heavy-statistics", TTL 60s
# ---------------------------------------------------------------------------
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


# ---------------------------------------------------------------------------
# S2 – Algorithmic complexity (List vs HashSet lookup)
# Now accepts a list of codes from the POST body, matching the .NET contract.
# ---------------------------------------------------------------------------

def verify_microchips_inefficient(incoming_codes):
    """Baseline: O(N*M) – list scan per input code."""
    session = SessionLocal()

    db_chips_list = [a.microchip_code for a in session.query(Animal).all()]

    found_count = 0

    for chip in incoming_codes:
        if chip in db_chips_list:
            found_count += 1

    return {"totalInputs": len(incoming_codes), "dbSize": len(db_chips_list), "found": found_count}


def verify_microchips_efficient(incoming_codes):
    """Optimized: O(N+M) – HashSet lookup per input code."""
    session = SessionLocal()

    db_chips_set = {a.microchip_code for a in session.query(Animal).all()}

    found_count = 0

    for chip in incoming_codes:
        if chip in db_chips_set:
            found_count += 1

    return {"totalInputs": len(incoming_codes), "dbSize": len(db_chips_set), "found": found_count}


# ---------------------------------------------------------------------------
# S4 – File I/O (ReadAllLines vs mmap)
# ---------------------------------------------------------------------------

def process_file_legacy():
    """Baseline: File.ReadAllLines() equivalent – loads entire file into memory."""
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
    """Optimized: memory-mapped file scan – avoids loading into the heap."""
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


# ---------------------------------------------------------------------------
# S5 – Uncached repeated aggregation (DB every time vs Redis cache)
# ---------------------------------------------------------------------------

def generate_heavy_statistics():
    """Compute the GROUP BY aggregation against the database."""
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
    """Baseline: hits the DB every time. No caching."""
    data = generate_heavy_statistics()

    return {
        "source": "db",
        "stats": data
    }


def dashboard_stats_optimized():
    """
    Optimized: Redis-backed cache with 60-second sliding expiration.
    Matches .NET IDistributedCache with key "petrescue:s5:heavy-statistics".
    """
    cached = redis_client.get(CACHE_KEY)
    if cached is not None:
        data = json.loads(cached)
        return {"source": "cache", "stats": data}

    data = generate_heavy_statistics()
    redis_client.setex(CACHE_KEY, CACHE_TTL_SECONDS, json.dumps(data))
    return {"source": "db", "stats": data}
