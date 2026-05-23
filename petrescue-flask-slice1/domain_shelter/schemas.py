from pydantic import BaseModel


class CreateShelterSchema(BaseModel):
    name: str
    location: str


class CreateAnimalSchema(BaseModel):
    name: str
    species: str
    microchip_code: str
    shelter_id: int
