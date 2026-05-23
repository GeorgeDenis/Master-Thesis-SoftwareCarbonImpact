// Scenarios/S1OrmScenario.cs

using System.Collections.Generic;
using System.Linq;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Routing;
using Microsoft.EntityFrameworkCore;
using PetRescue.Api.Data;
using PetRescue.Api.Infrastructure;

namespace PetRescue.Api.Scenarios;

/// <summary>
/// S1 - Object-Relational Mapping overhead (N+1 query problem).
///
/// Baseline: Fetch all medical records with no Include(). Then access record.Animal.Name
/// on each row, which triggers EF Core lazy-loading proxies to issue one SELECT per animal.
/// On a dataset with hundreds of distinct animals, this produces hundreds of round-trips.
///
/// Optimized: Use Include(r => r.Animal) so the rows arrive in a single JOIN-backed query.
/// </summary>
public static class S1OrmScenario
{
    public static void MapS1(this IEndpointRouteBuilder app)
    {
        app.MapGet("/api/s1/medical-records", async (PetRescueContext db) =>
        {
            if (Toggles.S1Optimized)
            {
                // Optimized: eager loading via JOIN.
                var rows = await db.MedicalRecords
                    .Include(r => r.Animal)
                    .AsNoTracking()
                    .ToListAsync();

                var projected = rows.Select(r => new
                {
                    r.Id,
                    r.Disease,
                    r.Treatment,
                    AnimalName = r.Animal!.Name
                }).ToList();

                return Results.Ok(new { count = projected.Count, sample = projected.Take(3) });
            }
            else
            {
                // Baseline: lazy loading. Accessing r.Animal on each row triggers an extra SELECT.
                var rows = db.MedicalRecords.ToList();
                var projected = new List<object>(rows.Count);
                foreach (var r in rows)
                {
                    // This .Animal access is the N+1. EF Core issues a new query per row.
                    var animalName = r.Animal?.Name ?? "(unknown)";
                    projected.Add(new { r.Id, r.Disease, r.Treatment, AnimalName = animalName });
                }
                return Results.Ok(new { count = projected.Count, sample = projected.Take(3) });
            }
        });
    }
}
