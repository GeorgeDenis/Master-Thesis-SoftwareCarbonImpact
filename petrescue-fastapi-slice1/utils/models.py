from datetime import datetime

from flask_sqlalchemy import SQLAlchemy
from sqlalchemy import Column, Integer, String, Date, ForeignKey
from sqlalchemy.orm import relationship

db = SQLAlchemy()

class Adopter(db.Model):
    __tablename__ = "adopters"

    id = Column(Integer, primary_key=True)
    name = Column(String(255), nullable=False)
    email = Column(String(255), unique=True, nullable=False)

    adoptions = relationship("Adoption", back_populates="adopter")


class Adoption(db.Model):
    __tablename__ = "adoptions"

    id = Column(Integer, primary_key=True)
    animal_id = Column(Integer, ForeignKey('animals.id'), nullable=False)
    adopter_id = Column(Integer, ForeignKey('adopters.id'), nullable=False)
    adoption_date = Column(Date, default=datetime.utcnow())

    animal = relationship("Animal", back_populates="adoptions")
    adopter = relationship("Adopter", back_populates="adoptions")


class MedicalRecord(db.Model):
    __tablename__ = 'medical_records'

    id = Column(Integer, primary_key=True)
    animal_id = Column(Integer, ForeignKey('animals.id'), nullable=False)
    disease = Column(String(255), nullable=False)
    treatment = Column(String(255))
    visit_date = Column(Date, default=datetime.utcnow)

    animal = relationship("Animal", back_populates="medical_records")


class Shelter(db.Model):
    __tablename__ = 'shelters'

    id = Column(Integer, primary_key=True)
    name = Column(String(255), nullable=False)
    location = Column(String(255), nullable=False)

    animals = relationship("Animal", back_populates="shelter")

class Animal(db.Model):
    __tablename__ = 'animals'

    id = Column(Integer, primary_key=True)
    name = Column(String(255), nullable=False)
    species = Column(String(255), nullable=False)
    microchip_code = Column(String(100), nullable=False)
    status = Column(String(50), default="Available")

    shelter_id = Column(Integer, ForeignKey('shelters.id'), nullable=False)

    shelter = relationship("Shelter", back_populates="animals")
    medical_records = relationship("MedicalRecord", back_populates="animal")
    adoptions = relationship("Adoption", back_populates="animal")