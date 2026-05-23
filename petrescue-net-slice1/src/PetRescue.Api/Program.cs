// Program.cs

using System;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using PetRescue.Api.Data;
using PetRescue.Api.Infrastructure;
using PetRescue.Api.Scenarios;

var builder = WebApplication.CreateBuilder(args);

// ----- Configuration -------------------------------------------------------
var pgConnection = Environment.GetEnvironmentVariable("PETRESCUE_PG")
    ?? "Host=localhost;Port=5433;Database=petrescue;Username=petrescue;Password=petrescue;Pooling=true;Maximum Pool Size=200";

var redisConnection = Environment.GetEnvironmentVariable("PETRESCUE_REDIS")
    ?? "localhost:6379";

var microchipFilePath = Environment.GetEnvironmentVariable("PETRESCUE_MICROCHIP_FILE")
    ?? "/tmp/petrescue_microchips.txt";

// ----- Services ------------------------------------------------------------
builder.Services.AddDbContext<PetRescueContext>(opt =>
{
    opt.UseNpgsql(pgConnection);
    // Lazy-loading proxies are required so the S1 N+1 anti-pattern can fire.
    opt.UseLazyLoadingProxies();
});

builder.Services.AddStackExchangeRedisCache(opt =>
{
    opt.Configuration = redisConnection;
    opt.InstanceName = "petrescue:";
});

builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

var app = builder.Build();

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

// ----- Health + toggles introspection --------------------------------------
app.MapGet("/health", () => Results.Ok(new
{
    status = "ok",
    toggles = new
    {
        S1_Optimized = Toggles.S1Optimized,
        S2_Optimized = Toggles.S2Optimized,
        S3_Optimized = Toggles.S3Optimized,
        S4_Optimized = Toggles.S4Optimized,
        S5_Optimized = Toggles.S5Optimized
    },
    microchipFile = microchipFilePath
}));

// ----- Scenario endpoints --------------------------------------------------
app.MapS1();
app.MapS2();
app.MapS3();
app.MapS4(microchipFilePath);
app.MapS5();

app.Run();
