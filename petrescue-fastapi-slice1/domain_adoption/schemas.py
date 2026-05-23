from pydantic import BaseModel, Field


class AddAdopterSchema(BaseModel):
    name: str = Field(default=None)
    email: str = Field(default=None)

class AddAdoptionSchema(BaseModel):
    animal_id: int = Field(default=None)
    adopter_id: int = Field(default=None)
