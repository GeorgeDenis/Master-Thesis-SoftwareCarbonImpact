from datetime import datetime
from sqlalchemy import Column, Integer, String, Date, ForeignKey
from sqlalchemy.orm import relationship
from database import Base


class MedicalRecord(Base):
    __tablename__ = 'medical_records'

    id = Column(Integer, primary_key=True)
    animal_id = Column(Integer, ForeignKey('animals.id'), nullable=False)
    disease = Column(String(255), nullable=False)
    treatment = Column(String(255))
    visit_date = Column(Date, default=datetime.utcnow)

    animal = relationship("Animal", back_populates="medical_records")