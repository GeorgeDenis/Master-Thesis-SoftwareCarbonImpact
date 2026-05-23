// Infrastructure/Toggles.cs

using System;

namespace PetRescue.Api.Infrastructure;

/// <summary>
/// Centralizes the anti-pattern vs optimized toggles.
/// Each scenario can independently be in BASELINE or OPTIMIZED mode.
/// Setting via environment variable lets the same binary serve both configurations.
/// </summary>
public static class Toggles
{
    public static bool S1Optimized => GetBool("OPTIMIZE_S1_EAGER");        // eager .Include() for ORM
    public static bool S2Optimized => GetBool("OPTIMIZE_S2_HASHSET");      // HashSet<> instead of List<>
    public static bool S3Optimized => GetBool("OPTIMIZE_S3_INDEX");        // assumes index has been created via SQL
    public static bool S4Optimized => GetBool("OPTIMIZE_S4_MMAP");         // memory-mapped file access
    public static bool S5Optimized => GetBool("OPTIMIZE_S5_CACHE");        // Redis-backed cache

    private static bool GetBool(string name)
    {
        var v = Environment.GetEnvironmentVariable(name);
        return v is not null &&
            (v.Equals("1", StringComparison.OrdinalIgnoreCase)
             || v.Equals("true", StringComparison.OrdinalIgnoreCase));
    }
}
