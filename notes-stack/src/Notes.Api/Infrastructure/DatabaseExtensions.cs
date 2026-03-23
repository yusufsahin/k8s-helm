using Microsoft.EntityFrameworkCore;
using Notes.Api.Data;

namespace Notes.Api.Infrastructure;

public static class DatabaseExtensions
{
  public static async Task ApplyDatabaseMigrationsAsync(this WebApplication app)
  {
    using var scope = app.Services.CreateScope();
    var db = scope.ServiceProvider.GetRequiredService<NotesDbContext>();
    var logger = scope.ServiceProvider.GetRequiredService<ILoggerFactory>().CreateLogger("DatabaseStartup");

    for (var attempt = 1; attempt <= 10; attempt++)
    {
      try
      {
        await db.Database.MigrateAsync();
        return;
      }
      catch (Exception ex) when (attempt < 10)
      {
        logger.LogWarning(ex, "Database migration attempt {Attempt} failed. Retrying...", attempt);
        await Task.Delay(TimeSpan.FromSeconds(Math.Min(attempt * 2, 10)));
      }
    }

    await db.Database.MigrateAsync();
  }
}
