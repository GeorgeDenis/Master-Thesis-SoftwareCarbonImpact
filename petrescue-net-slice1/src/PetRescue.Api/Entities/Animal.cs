// Entities/Animal.cs

using System.Collections.Generic;

namespace PetRescue.Api.Entities;

public class Animal
{
    public int Id { get; set; }
    public string Name { get; set; } = "";
    public string Species { get; set; } = "";
    public string MicrochipCode { get; set; } = "";
    public string Status { get; set; } = "Available";
    public int ShelterId { get; set; }

    // Virtual navigation properties enable EF Core lazy-loading proxies.
    // This is exactly what produces the N+1 query pattern in S1.
    public virtual Shelter? Shelter { get; set; }
    public virtual ICollection<MedicalRecord> MedicalRecords { get; set; } = new List<MedicalRecord>();
    public virtual ICollection<Adoption> Adoptions { get; set; } = new List<Adoption>();
}
