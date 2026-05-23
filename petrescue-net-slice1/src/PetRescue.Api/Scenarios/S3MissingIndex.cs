// Scenarios/S3MissingIndex.cs

using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Routing;
using Microsoft.EntityFrameworkCore;
using PetRescue.Api.Data;
using PetRescue.Api.Infrastructure;

namespace PetRescue.Api.Scenarios;

/// <summary>
/// S3 - Missing database index on medical_records.disease.
///
/// Both the baseline and optimized paths execute the same SQL. The difference is the
/// presence of an index on disease, created (or dropped) by the SQL scripts in /sql.
///
/// The OPTIMIZE_S3_INDEX environment variable is informational here: it tells the
/// orchestrator which configuration is in effect. The actual change is at the DB level.
/// </summary>
public static class S3MissingIndex
{
    private const int IterationCount = 500;
    private const string TargetDisease = "Parvovirus";

    public static void MapS3(this IEndpointRouteBuilder app)
    {
        app.MapGet("/api/s3/disease-search", async (PetRescueContext db) =>
        {
            int total = 0;
            for (int i = 0; i < IterationCount; i++)
            {
                // FromSqlRaw used deliberately so EF Core does not auto-cache the compiled query plan
                // in a way that would mask the index effect we want to measure.
                var count = await db.MedicalRecords
                    .FromSqlRaw("SELECT * FROM medical_records WHERE disease = {0}", TargetDisease)
                    .AsNoTracking()
                    .CountAsync();
                total += count;
            }
            return Results.Ok(new
            {
                iterations = IterationCount,
                disease = TargetDisease,
                total,
                indexed = Toggles.S3Optimized
            });
        });
    }
}
