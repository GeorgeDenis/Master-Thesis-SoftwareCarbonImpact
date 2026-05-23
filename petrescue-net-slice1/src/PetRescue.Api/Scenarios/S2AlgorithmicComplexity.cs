// Scenarios/S2AlgorithmicComplexity.cs

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
/// S2 - Algorithmic complexity. Given a list of N target microchip codes,
/// count how many exist in the database.
///
/// Baseline: All DB codes loaded into a List&lt;string&gt;. For each input, .Contains() walks
/// the list. Time complexity O(N*M).
///
/// Optimized: Same DB codes loaded into a HashSet&lt;string&gt;. Lookup is amortized O(1),
/// total O(N+M).
/// </summary>
public record MicrochipBatch(List<string> Codes);

public static class S2AlgorithmicComplexity
{
    public static void MapS2(this IEndpointRouteBuilder app)
    {
        app.MapPost("/api/s2/microchip-match", async (MicrochipBatch input, PetRescueContext db) =>
        {
            var allCodes = await db.Animals
                .AsNoTracking()
                .Select(a => a.MicrochipCode)
                .ToListAsync();

            int found = 0;
            if (Toggles.S2Optimized)
            {
                var index = new HashSet<string>(allCodes);
                foreach (var c in input.Codes)
                {
                    if (index.Contains(c)) found++;
                }
            }
            else
            {
                // Baseline: O(N) list scan per input.
                foreach (var c in input.Codes)
                {
                    if (allCodes.Contains(c)) found++;
                }
            }

            return Results.Ok(new { totalInputs = input.Codes.Count, dbSize = allCodes.Count, found });
        });
    }
}
