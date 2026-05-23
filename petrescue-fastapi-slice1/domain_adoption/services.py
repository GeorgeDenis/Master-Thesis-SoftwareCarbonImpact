from database import SessionLocal
from domain_adoption.models import Adopter, Adoption
from domain_adoption.schemas import AddAdopterSchema, AddAdoptionSchema
from domain_shelter.services import find_animal_by_id
from exceptions import AdopterAlreadyExists, NotFoundException, AnimalCantBeAdopted


def find_adopter_by_email(email):
    session = SessionLocal()
    adopter = session.query(Adopter).filter(Adopter.email == email).first()

    return adopter


def find_adopter_by_id(id):
    session = SessionLocal()
    adopter = session.query(Adopter).filter(Adopter.id == id).first()

    return adopter


def fetch_all_adopters():
    session = SessionLocal()

    adopters = session.query(Adopter).all()
    result = [{"id": a.id, "name": a.name, "email": a.email} for a in adopters]

    return result


def add_adopter(adopter: AddAdopterSchema):
    result = find_adopter_by_email(adopter.email)
    if result:
        raise AdopterAlreadyExists(f"Adopter with email {adopter.email} already exists.")

    session = SessionLocal()

    new_adopter = Adopter(
        name=adopter.name,
        email=adopter.email,
    )

    session.add(new_adopter)
    session.commit()

    return {
        "message": "Adopter added successfully",
        "id": new_adopter.id
    }


def add_adoption(adoption: AddAdoptionSchema):
    adopter = find_adopter_by_id(adoption.adopter_id)
    if not adopter:
        raise NotFoundException(f"Adopter with id {adoption.adopter_id} not found")

    animal = find_animal_by_id(adoption.animal_id)
    if not animal:
        raise NotFoundException(f"Animal with id {adoption.animal_id} not found")

    if animal.status != 'Available':
        raise AnimalCantBeAdopted(f"Animal with id {animal.id} can't be adopted.")

    session = SessionLocal()
    new_adoption = Adoption(
        animal_id=adoption.animal_id,
        adopter_id=adopter.id,
    )
    animal.status = 'Adopted'

    session.add_all([new_adoption, animal])
    session.commit()

    return {
        "message": "Adoption added successfully",
        "id": new_adoption.id
    }
