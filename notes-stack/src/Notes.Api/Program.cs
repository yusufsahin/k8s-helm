using Microsoft.AspNetCore.Http.HttpResults;
using Microsoft.EntityFrameworkCore;
using Notes.Api.Contracts;
using Notes.Api.Data;
using Notes.Api.Infrastructure;
using Notes.Api.Models;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddProblemDetails();
builder.Services.AddOpenApi();
builder.Services.AddDbContext<NotesDbContext>(options =>
  options.UseNpgsql(builder.Configuration.GetConnectionString("DefaultConnection")));
builder.Services.AddHealthChecks().AddDbContextCheck<NotesDbContext>("database");

var app = builder.Build();

app.UseExceptionHandler();

if (app.Environment.IsDevelopment())
{
  app.MapOpenApi();
}

var notes = app.MapGroup("/api/notes").WithTags("Notes");

notes.MapGet("/", async Task<Ok<IReadOnlyList<NoteResponse>>> (NotesDbContext db, CancellationToken cancellationToken) =>
{
  var items = await db.Notes
    .AsNoTracking()
    .OrderByDescending(note => note.Id)
    .Select(note => new NoteResponse(note.Id, note.Title, note.Description))
    .ToListAsync(cancellationToken);

  return TypedResults.Ok<IReadOnlyList<NoteResponse>>(items);
});

notes.MapGet("/{id:int}", async Task<Results<Ok<NoteResponse>, NotFound>> (int id, NotesDbContext db, CancellationToken cancellationToken) =>
{
  var note = await db.Notes
    .AsNoTracking()
    .Where(item => item.Id == id)
    .Select(item => new NoteResponse(item.Id, item.Title, item.Description))
    .SingleOrDefaultAsync(cancellationToken);

  return note is null
    ? TypedResults.NotFound()
    : TypedResults.Ok(note);
});

notes.MapPost("/", async Task<Results<Created<NoteResponse>, ValidationProblem>> (NoteRequest request, NotesDbContext db, CancellationToken cancellationToken) =>
{
  var errors = ValidateNote(request);
  if (errors is not null)
  {
    return TypedResults.ValidationProblem(errors);
  }

  var note = new Note
  {
    Title = request.Title.Trim(),
    Description = request.Description.Trim()
  };

  db.Notes.Add(note);
  await db.SaveChangesAsync(cancellationToken);

  var response = new NoteResponse(note.Id, note.Title, note.Description);
  return TypedResults.Created($"/api/notes/{note.Id}", response);
});

notes.MapPut("/{id:int}", async Task<Results<Ok<NoteResponse>, NotFound, ValidationProblem>> (int id, NoteRequest request, NotesDbContext db, CancellationToken cancellationToken) =>
{
  var errors = ValidateNote(request);
  if (errors is not null)
  {
    return TypedResults.ValidationProblem(errors);
  }

  var note = await db.Notes.SingleOrDefaultAsync(item => item.Id == id, cancellationToken);
  if (note is null)
  {
    return TypedResults.NotFound();
  }

  note.Title = request.Title.Trim();
  note.Description = request.Description.Trim();
  await db.SaveChangesAsync(cancellationToken);

  return TypedResults.Ok(new NoteResponse(note.Id, note.Title, note.Description));
});

notes.MapDelete("/{id:int}", async Task<Results<NoContent, NotFound>> (int id, NotesDbContext db, CancellationToken cancellationToken) =>
{
  var note = await db.Notes.SingleOrDefaultAsync(item => item.Id == id, cancellationToken);
  if (note is null)
  {
    return TypedResults.NotFound();
  }

  db.Notes.Remove(note);
  await db.SaveChangesAsync(cancellationToken);
  return TypedResults.NoContent();
});

app.MapHealthChecks("/health");

await app.ApplyDatabaseMigrationsAsync();

app.Run();

static Dictionary<string, string[]>? ValidateNote(NoteRequest request)
{
  var errors = new Dictionary<string, string[]>();

  if (string.IsNullOrWhiteSpace(request.Title))
  {
    errors["title"] = ["Title is required."];
  }
  else if (request.Title.Trim().Length > 160)
  {
    errors["title"] = ["Title must be 160 characters or fewer."];
  }

  if (string.IsNullOrWhiteSpace(request.Description))
  {
    errors["description"] = ["Description is required."];
  }
  else if (request.Description.Trim().Length > 2000)
  {
    errors["description"] = ["Description must be 2000 characters or fewer."];
  }

  return errors.Count == 0 ? null : errors;
}
