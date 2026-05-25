// Scenarios/S5UncachedAggregation.cs

using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Routing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Distributed;
using PetRescue.Api.Data;
using PetRescue.Api.Infrastructure;

using System.Data;

namespace PetRescue.Api.Scenarios;

/// <summary>
/// S5 - Uncached repeated aggregation.
///
/// Baseline: Every request executes a GROUP BY aggregation against the database.
/// Under concurrent load, identical work is performed by every worker.
///
/// Optimized: A Redis-backed IDistributedCache fronts the result with a 60-second
/// sliding expiration. Only one miss per minute reaches the database; everything
/// else is served from RAM.
/// </summary>
public static class S5UncachedAggregation
{
    private const string CacheKey = "s5:heavy-statistics";
    private static readonly TimeSpan CacheTtl = TimeSpan.FromSeconds(60);

    public static void MapS5(this IEndpointRouteBuilder app)
    {
        app.MapGet("/api/s5/heavy-statistics", async (PetRescueContext db, IDistributedCache cache) =>
        {
            if (Toggles.S5Optimized)
            {
                var cached = await cache.GetStringAsync(CacheKey);
                if (cached is not null)
                {
                    var hit = JsonSerializer.Deserialize<Dictionary<string, long>>(cached)!;
                    return Results.Ok(new { source = "cache", stats = hit });
                }

                var stats = await ComputeAsync(db);
                await cache.SetStringAsync(CacheKey, JsonSerializer.Serialize(stats),
                    new DistributedCacheEntryOptions { SlidingExpiration = CacheTtl });
                return Results.Ok(new { source = "db", stats });
            }
            else
            {
                // Baseline: hits the DB every time.
                var stats = await ComputeAsync(db);
                return Results.Ok(new { source = "db", stats });
            }
        });
    }

    private static async Task<Dictionary<string, long>> ComputeAsync(PetRescueContext db)
    {
        using var command = db.Database.GetDbConnection().CreateCommand();
        command.CommandText = @"
            SELECT a.species, COALESCE(SUM(sub.cnt), 0) AS total
            FROM animals a
            LEFT JOIN (
                SELECT animal_id, COUNT(*) AS cnt
                FROM medical_records
                GROUP BY animal_id
            ) sub ON a.id = sub.animal_id
            GROUP BY a.species";

        await db.Database.OpenConnectionAsync();
        using var reader = await command.ExecuteReaderAsync();
        var result = new Dictionary<string, long>();
        while (await reader.ReadAsync())
        {
            var species = reader.GetString(0);
            var total = reader.GetInt64(1);
            result[species] = total;
        }
        return result;
    }
}
