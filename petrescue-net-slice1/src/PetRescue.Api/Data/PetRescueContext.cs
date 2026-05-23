// Data/PetRescueContext.cs
using Microsoft.EntityFrameworkCore;
using PetRescue.Api.Entities;

namespace PetRescue.Api.Data;

public class PetRescueContext : DbContext
{
    public PetRescueContext(DbContextOptions<PetRescueContext> options) : base(options) { }

    public DbSet<Shelter> Shelters => Set<Shelter>();
    public DbSet<Animal> Animals => Set<Animal>();
    public DbSet<MedicalRecord> MedicalRecords => Set<MedicalRecord>();
    public DbSet<Adopter> Adopters => Set<Adopter>();
    public DbSet<Adoption> Adoptions => Set<Adoption>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<Shelter>(b =>
        {
            b.ToTable("shelters");
            b.HasKey(x => x.Id);
            b.Property(x => x.Id).HasColumnName("id");
            b.Property(x => x.Name).HasColumnName("name").HasMaxLength(255).IsRequired();
            b.Property(x => x.Location).HasColumnName("location").HasMaxLength(255).IsRequired();
        });

        modelBuilder.Entity<Animal>(b =>
        {
            b.ToTable("animals");
            b.HasKey(x => x.Id);
            b.Property(x => x.Id).HasColumnName("id");
            b.Property(x => x.Name).HasColumnName("name").HasMaxLength(255).IsRequired();
            b.Property(x => x.Species).HasColumnName("species").HasMaxLength(255).IsRequired();
            b.Property(x => x.MicrochipCode).HasColumnName("microchip_code").HasMaxLength(100).IsRequired();
            b.Property(x => x.Status).HasColumnName("status").HasMaxLength(50).HasDefaultValue("Available");
            b.Property(x => x.ShelterId).HasColumnName("shelter_id");
            b.HasOne(x => x.Shelter).WithMany(x => x.Animals).HasForeignKey(x => x.ShelterId);
        });

        modelBuilder.Entity<MedicalRecord>(b =>
        {
            b.ToTable("medical_records");
            b.HasKey(x => x.Id);
            b.Property(x => x.Id).HasColumnName("id");
            b.Property(x => x.AnimalId).HasColumnName("animal_id");
            b.Property(x => x.Disease).HasColumnName("disease").HasMaxLength(255).IsRequired();
            b.Property(x => x.Treatment).HasColumnName("treatment").HasMaxLength(255).IsRequired();
            b.Property(x => x.VisitDate).HasColumnName("visit_date");
            b.HasOne(x => x.Animal).WithMany(x => x.MedicalRecords).HasForeignKey(x => x.AnimalId);
            // Note: no index on Disease in the baseline. The SQL migration adds it
            // only when the OPTIMIZE_S3_INDEX environment variable is set.
        });

        modelBuilder.Entity<Adopter>(b =>
        {
            b.ToTable("adopters");
            b.HasKey(x => x.Id);
            b.Property(x => x.Id).HasColumnName("id");
            b.Property(x => x.Name).HasColumnName("name").HasMaxLength(255).IsRequired();
            b.Property(x => x.Email).HasColumnName("email").HasMaxLength(255).IsRequired();
        });

        modelBuilder.Entity<Adoption>(b =>
        {
            b.ToTable("adoptions");
            b.HasKey(x => x.Id);
            b.Property(x => x.Id).HasColumnName("id");
            b.Property(x => x.AnimalId).HasColumnName("animal_id");
            b.Property(x => x.AdopterId).HasColumnName("adopter_id");
            b.Property(x => x.AdoptionDate).HasColumnName("adoption_date");
            b.HasOne(x => x.Animal).WithMany(x => x.Adoptions).HasForeignKey(x => x.AnimalId);
            b.HasOne(x => x.Adopter).WithMany(x => x.Adoptions).HasForeignKey(x => x.AdopterId);
        });
    }
}
