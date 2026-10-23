using System.IO;
using System.Text;
using System.Windows;
using HardeningGenerator.Services;
using HardeningGenerator.ViewModels;
using Microsoft.Win32;

namespace HardeningGenerator;

public partial class MainWindow : Window
{
    private readonly MainViewModel _vm;

    public MainWindow()
    {
        InitializeComponent();

        var catalogDir = ResolveCatalogDir();
        var entries = CatalogLoader.Load(catalogDir, out var errors);

        _vm = new MainViewModel(entries);
        DataContext = _vm;

        if (entries.Count == 0)
            _vm.Status = $"Kein Katalog geladen aus '{catalogDir}'. " + string.Join(" | ", errors);
        else
            _vm.Status = $"{entries.Count} Einstellung(en) geladen.";
    }

    /// <summary>Katalogordner neben der EXE, mit Entwickler-Fallback.</summary>
    private static string ResolveCatalogDir()
    {
        var candidates = new[]
        {
            Path.Combine(AppContext.BaseDirectory, "catalog"),
            Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "catalog"),
            Path.Combine(Directory.GetCurrentDirectory(), "catalog")
        };
        foreach (var c in candidates)
        {
            var full = Path.GetFullPath(c);
            if (Directory.Exists(full)) return full;
        }
        return Path.Combine(AppContext.BaseDirectory, "catalog");
    }

    private void GenerateButton_Click(object sender, RoutedEventArgs e)
    {
        var selected = _vm.SelectedEntries();
        if (selected.Count == 0)
        {
            _vm.Status = "Nichts gewaehlt. Bitte mindestens eine (nicht gesperrte) Einstellung ankreuzen.";
            return;
        }

        var script = ScriptGenerator.Generate(selected, _vm.BreakGlassList);

        var dlg = new SaveFileDialog
        {
            Title = "Erzeugtes Skript speichern",
            Filter = "PowerShell-Skript (*.ps1)|*.ps1",
            FileName = "Set-M365Hardening.ps1"
        };
        if (dlg.ShowDialog() != true)
        {
            _vm.Status = "Speichern abgebrochen.";
            return;
        }

        try
        {
            // UTF-8 mit BOM (fuer Windows PowerShell 5.1 korrekte Umlaute)
            File.WriteAllText(dlg.FileName, script, new UTF8Encoding(true));
            _vm.Status = $"Skript erzeugt: {dlg.FileName}  ({selected.Count} Einstellung(en))";
        }
        catch (Exception ex)
        {
            _vm.Status = "Fehler beim Speichern: " + ex.Message;
        }
    }
}
