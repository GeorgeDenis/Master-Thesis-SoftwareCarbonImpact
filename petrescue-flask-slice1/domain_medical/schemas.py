from pydantic import BaseModel


class CreateMedicalSchema(BaseModel):
    animal_id: int
    disease: str
    treatment: str
