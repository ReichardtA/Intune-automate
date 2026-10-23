using System.IO;
using System.Text.Json;
using HardeningGenerator.Models;

namespace HardeningGenerator.Services;

public static class CatalogLoader
{
    private static readonly JsonSerializerOptions Options = new()
    {
        PropertyNameCaseInsensitive = true
    };

    /// <summary>Laedt alle *.json aus dem Katalogordner (ausser dem Schema).</summary>
    public static List<CatalogEntry> Load(string directory, out List<string> errors)
    {
        errors = new List<string>();
        var result = new List<CatalogEntry>();

        if (!Directory.Exists(directory))
        {
            errors.Add($"Katalogordner nicht gefunden: {directory}");
            return result;
        }

        foreach (var file in Directory.GetFiles(directory, "*.json").OrderBy(f => f))
        {
            var name = Path.GetFileName(file);
            if (name.StartsWith("catalog.schema", StringComparison.OrdinalIgnoreCase))
                continue;

            try
            {
                var entry = JsonSerializer.Deserialize<CatalogEntry>(File.ReadAllText(file), Options);
                if (entry != null && !string.IsNullOrWhiteSpace(entry.Id))
                    result.Add(entry);
                else
                    errors.Add($"Leer/ungueltig: {name}");
            }
            catch (Exception ex)
            {
                errors.Add($"{name}: {ex.Message}");
            }
        }

        return result;
    }
}
