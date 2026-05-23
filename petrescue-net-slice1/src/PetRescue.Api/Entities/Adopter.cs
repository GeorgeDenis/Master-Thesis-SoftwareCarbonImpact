// Entities/Adopter.cs

using System.Collections.Generic;

namespace PetRescue.Api.Entities;

public class Adopter
{
    public int Id { get; set; }
    public string Name { get; set; } = "";
    public string Email { get; set; } = "";

    public virtual ICollection<Adoption> Adoptions { get; set; } = new List<Adoption>();
}
