from datetime import datetime
from sqlalchemy import Column, Integer, String, Date, ForeignKey
from sqlalchemy.orm import relationship
from database import Base


class Adopter(Base):
    __tablename__ = "adopters"

    id = Column(Integer, primary_key=True)
    name = Column(String(255), nullable=False)
    email = Column(String(255), unique=True, nullable=False)

    adoptions = relationship("Adoption", back_populates="adopter")

class Adoption(Base):
    __tablename__ = "adoptions"

    id = Column(Integer, primary_key=True)
    animal_id = Column(Integer, ForeignKey('animals.id'), nullable=False)
    adopter_id = Column(Integer, ForeignKey('adopters.id'), nullable=False)
    adoption_date = Column(Date, default=datetime.utcnow())

    animal = relationship("Animal", back_populates="adoptions")
    adopter = relationship("Adopter", back_populates="adoptions")
