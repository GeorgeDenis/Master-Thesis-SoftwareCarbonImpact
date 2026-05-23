// Entities/MedicalRecord.cs

using System;

namespace PetRescue.Api.Entities;

public class MedicalRecord
{
    public int Id { get; set; }
    public int AnimalId { get; set; }
    // Deliberately NOT indexed in the baseline. The S3 anti-pattern queries this column.
    public string Disease { get; set; } = "";
    public string Treatment { get; set; } = "";
    public DateTime VisitDate { get; set; }

    public virtual Animal? Animal { get; set; }
}
