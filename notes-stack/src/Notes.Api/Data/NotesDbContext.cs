using Microsoft.EntityFrameworkCore;
using Notes.Api.Models;

namespace Notes.Api.Data;

public sealed class NotesDbContext(DbContextOptions<NotesDbContext> options) : DbContext(options)
{
  public DbSet<Note> Notes => Set<Note>();

  protected override void OnModelCreating(ModelBuilder modelBuilder)
  {
    var note = modelBuilder.Entity<Note>();

    note.Property(item => item.Title)
      .HasMaxLength(160)
      .IsRequired();

    note.Property(item => item.Description)
      .HasMaxLength(2000)
      .IsRequired();

    note.HasData(
      new Note
      {
        Id = 1,
        Title = "Plan the cluster migration",
        Description = "Validate the compose stack locally, then convert the services to Kubernetes manifests."
      },
      new Note
      {
        Id = 2,
        Title = "Keep the note model small",
        Description = "The first iteration only needs id, title, and description."
      });
  }
}
