using System.ComponentModel;
using System.Runtime.CompilerServices;
using HardeningGenerator.Models;

namespace HardeningGenerator.ViewModels;

/// <summary>Zeilen-ViewModel fuer eine Einstellung in der Liste.</summary>
public class SettingItemViewModel : INotifyPropertyChanged
{
    public CatalogEntry Entry { get; }

    public SettingItemViewModel(CatalogEntry entry) => Entry = entry;

    private bool _isSelected;
    public bool IsSelected
    {
        get => _isSelected;
        set { if (_isSelected != value) { _isSelected = value; OnPropertyChanged(); } }
    }

    public string Nr => Entry.ChecklistNr;
    public string Title => Entry.Title;
    public string Tier => Entry.Tier;
    public string Workload => Entry.Workload;
    public string RiskClass => (Entry.RiskClass ?? "A").ToUpperInvariant();

    /// <summary>Klasse C oder ui.locked -> nicht waehlbar.</summary>
    public bool CanSelect => !Entry.Ui.Locked
                             && Entry.Ui.Selectable
                             && !string.Equals(RiskClass, "C", StringComparison.OrdinalIgnoreCase);

    /// <summary>Hinweis in der Liste: Warntext, sonst SafeMode-Note.</summary>
    public string Hint => Entry.Ui.WarnText ?? Entry.SafeMode.Note ?? "";

    public string RiskLabel => RiskClass switch
    {
        "A" => "A - sicher",
        "B" => "B - sichere Form",
        "C" => "C - gesperrt",
        _   => RiskClass
    };

    public event PropertyChangedEventHandler? PropertyChanged;
    private void OnPropertyChanged([CallerMemberName] string? name = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}
