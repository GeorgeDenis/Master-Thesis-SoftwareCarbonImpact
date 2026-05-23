// Entities/Shelter.cs

using System.Collections.Generic;

namespace PetRescue.Api.Entities;

public class Shelter
{
    public int Id { get; set; }
    public string Name { get; set; } = "";
    public string Location { get; set; } = "";

    // Virtual to enable lazy loading proxies. This is part of the anti-pattern S1.
    public virtual ICollection<Animal> Animals { get; set; } = new List<Animal>();
}
