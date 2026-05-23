from database import Base
from sqlalchemy import Column, Integer, String, ForeignKey
from sqlalchemy.orm import relationship


class Shelter(Base):
    __tablename__ = 'shelters'

    id = Column(Integer, primary_key=True)
    name = Column(String(255), nullable=False)
    location = Column(String(255), nullable=False)

    animals = relationship("Animal", back_populates="shelter")


class Animal(Base):
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
