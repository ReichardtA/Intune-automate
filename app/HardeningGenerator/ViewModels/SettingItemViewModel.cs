using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using HardeningGenerator.Models;

namespace HardeningGenerator.ViewModels;

/// <summary>Zeilen-ViewModel fuer eine Einstellung in der Liste.</summary>
public class SettingItemViewModel : INotifyPropertyChanged
{
    public CatalogEntry Entry { get; }

    /// <summary>Einzeln waehlbare Unterpunkte (nur bei ui.subSelectable + graph.readbacks), z. B. ASR-Regeln.</summary>
    public ObservableCollection<SubItemViewModel> SubItems { get; } = new();
    public bool HasSubItems => SubItems.Count > 0;

    private bool _bulkUpdate;

    public SettingItemViewModel(CatalogEntry entry)
    {
        Entry = entry;
        if (entry.Ui.SubSelectable && entry.Graph.Readbacks is { Length: > 1 } rbs)
        {
            foreach (var rb in rbs)
            {
                if (string.IsNullOrWhiteSpace(rb.SettingDefinitionId)) continue;
                var title = string.IsNullOrWhiteSpace(rb.Title) ? rb.SettingDefinitionId! : rb.Title!;
                SubItems.Add(new SubItemViewModel(this, rb.SettingDefinitionId!, title));
            }
        }
    }

    private bool? _isSelected = false;
    /// <summary>true = gewaehlt (bei Unterpunkten: alle), false = nicht gewaehlt, null = teilweise.</summary>
    public bool? IsSelected
    {
        get => _isSelected;
        set
        {
            if (!HasSubItems)
            {
                var v = value == true;
                if (_isSelected != v) { _isSelected = v; OnPropertyChanged(); }
                return;
            }
            // Klick auf "teilweise" waehlt ALLE Unterpunkte (statt alle abzuwaehlen)
            var target = (_isSelected == null && value != true) ? true : value;
            if (target == null) return; // "teilweise" ergibt sich nur aus den Unterpunkten
            _bulkUpdate = true;
            foreach (var s in SubItems) s.IsSelected = target.Value;
            _bulkUpdate = false;
            RecalcFromSubItems(force: true);
        }
    }

    /// <summary>Wird von den Unterpunkten aufgerufen; leitet den Zustand des Hauptpunkts ab.</summary>
    internal void RecalcFromSubItems(bool force = false)
    {
        if (_bulkUpdate) return;
        var n = SubItems.Count(s => s.IsSelected);
        bool? v = n == 0 ? false : (n == SubItems.Count ? true : null);
        if (force || _isSelected != v) { _isSelected = v; OnPropertyChanged(nameof(IsSelected)); }
        OnPropertyChanged(nameof(SubSummary));
    }

    /// <summary>Ueberschrift des Ausklapp-Bereichs, z. B. "Einzeln waehlen (12 von 19)".</summary>
    public string SubSummary => HasSubItems
        ? $"Einzeln waehlen ({SubItems.Count(s => s.IsSelected)} von {SubItems.Count})"
        : "";

    /// <summary>Gehoert ins Skript (ganz oder teilweise gewaehlt und waehlbar).</summary>
    public bool IsIncluded => IsSelected != false && CanSelect;

    /// <summary>Gewaehlte settingDefinitionIds der Unterpunkte; null, wenn es keine Unterpunkte gibt.</summary>
    public HashSet<string>? SelectedSubDefIds => HasSubItems
        ? SubItems.Where(s => s.IsSelected).Select(s => s.DefId).ToHashSet(StringComparer.OrdinalIgnoreCase)
        : null;

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

/// <summary>Ein einzeln waehlbarer Unterpunkt (z. B. eine ASR-Regel).</summary>
public class SubItemViewModel : INotifyPropertyChanged
{
    private readonly SettingItemViewModel _parent;
    public string DefId { get; }
    public string Title { get; }

    public SubItemViewModel(SettingItemViewModel parent, string defId, string title)
    {
        _parent = parent; DefId = defId; Title = title;
    }

    private bool _isSelected;
    public bool IsSelected
    {
        get => _isSelected;
        set
        {
            if (_isSelected == value) return;
            _isSelected = value;
            OnPropertyChanged();
            _parent.RecalcFromSubItems();
        }
    }

    public event PropertyChangedEventHandler? PropertyChanged;
    private void OnPropertyChanged([CallerMemberName] string? name = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}
