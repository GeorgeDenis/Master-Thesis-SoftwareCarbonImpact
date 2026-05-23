import os
import random
import sys

from decouple import config
from faker import Faker
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '01_monolith_start')))
from models import Shelter, Animal, Adopter, MedicalRecord

POSTGRES_USER = config("POSTGRES_USER")
POSTGRES_PASS = config("POSTGRES_PASS")
POSTGRES_DB = config("POSTGRES_DB")
POSTGRES_HOST = config("POSTGRES_HOST")

SQLALCHEMY_DATABASE_URL = f"postgresql+psycopg2://{POSTGRES_USER}:{POSTGRES_PASS}@{POSTGRES_HOST}:5432/{POSTGRES_DB}"
engine = create_engine(SQLALCHEMY_DATABASE_URL)


Session = sessionmaker(bind=engine)
session = Session()
fake = Faker()


def generate_data():
    shelters = []
    for _ in range(10):
        shelter = Shelter(
            name=fake.company() + " Animal Rescue",
            location=fake.city()
        )
        shelters.append(shelter)
    session.add_all(shelters)
    session.commit()
    print("10 Shelters generated.")

    adopters = []
    for _ in range(1000):
        adopter = Adopter(
            name=fake.name(),
            email=fake.unique.email(),
        )
        adopters.append(adopter)
    session.add_all(adopters)
    session.commit()
    print("1.000 Adopters generated.")

    animals = []
    species_list = ["Dog", "Cat", "Rabbit", "Parrot"]
    statuses = ["Available", "Adopted", "Sick"]

    shelter_ids = [s.id for s in shelters]

    for i in range(10000):
        animal = Animal(
            name=fake.first_name(),
            species=random.choice(species_list),
            microchip_code=fake.unique.uuid4(),
            status=random.choice(statuses),
            shelter_id=random.choice(shelter_ids)
        )
        animals.append(animal)

    session.add_all(animals)
    session.commit()
    print("10.000 Animals generated.")

    medical_records = []
    diseases = ["Parvovirus", "Rabies Vaccine", "Flea Treatment", "Broken Leg", "Routine Checkup"]
    animal_ids = [a.id for a in session.query(Animal).all()]

    for _ in range(30000):
        record = MedicalRecord(
            animal_id=random.choice(animal_ids),
            disease=random.choice(diseases),
            treatment=fake.sentence(),
            visit_date=fake.date_between(start_date='-2y', end_date='today')
        )
        medical_records.append(record)

    session.add_all(medical_records)
    session.commit()
    print("30.000 Medical records generated.")

    print("DB initialized.")


if __name__ == "__main__":
    generate_data()
