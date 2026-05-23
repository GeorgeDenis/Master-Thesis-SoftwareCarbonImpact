// Entities/Adoption.cs

using System;

namespace PetRescue.Api.Entities;

public class Adoption
{
    public int Id { get; set; }
    public int AnimalId { get; set; }
    public int AdopterId { get; set; }
    public DateTime AdoptionDate { get; set; }

    public virtual Animal? Animal { get; set; }
    public virtual Adopter? Adopter { get; set; }
}
