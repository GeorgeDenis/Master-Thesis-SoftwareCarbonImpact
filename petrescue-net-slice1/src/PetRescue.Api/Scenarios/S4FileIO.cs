// Scenarios/S4FileIO.cs

using System;
using System.IO;
using System.IO.MemoryMappedFiles;
using System.Text;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Routing;
using PetRescue.Api.Infrastructure;

namespace PetRescue.Api.Scenarios;

/// <summary>
/// S4 - Synchronous bulk I/O.
///
/// Baseline: File.ReadAllLines() loads the entire file into the managed heap.
/// On a 1M-line file under concurrent load, each request allocates ~tens of MB.
///
/// Optimized: MemoryMappedFile + a view stream allow scanning the file without
/// pulling its content into the managed heap. The OS-level page cache is shared.
/// </summary>
public static class S4FileIO
{
    private const string TargetChip = "CHIP-TARGET-MARKER";

    public static void MapS4(this IEndpointRouteBuilder app, string microchipFilePath)
    {
        app.MapGet("/api/s4/file-search", () =>
        {
            bool found;
            long bytesScanned = 0;

            if (Toggles.S4Optimized)
            {
                // Optimized: memory-mapped file. Avoids loading the file into the managed heap.
                using var mmf = MemoryMappedFile.CreateFromFile(microchipFilePath, FileMode.Open);
                using var view = mmf.CreateViewStream();
                using var reader = new StreamReader(view, Encoding.ASCII);
                found = false;
                string? line;
                while ((line = reader.ReadLine()) != null)
                {
                    bytesScanned += line.Length;
                    if (line.Contains(TargetChip, StringComparison.Ordinal))
                    {
                        found = true;
                        break;
                    }
                }
            }
            else
            {
                // Baseline: ReadAllLines materializes the whole file as string[].
                var lines = File.ReadAllLines(microchipFilePath);
                found = false;
                foreach (var line in lines)
                {
                    bytesScanned += line.Length;
                    if (line.Contains(TargetChip, StringComparison.Ordinal))
                    {
                        found = true;
                        break;
                    }
                }
            }

            return Results.Ok(new { found, bytesScanned, mmap = Toggles.S4Optimized });
        });
    }
}
