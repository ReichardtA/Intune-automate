using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Windows.Data;
using HardeningGenerator.Models;

namespace HardeningGenerator.ViewModels;

public class MainViewModel : INotifyPropertyChanged
{
    public ObservableCollection<SettingItemViewModel> Settings { get; }

    /// <summary>Nach Workload gruppierte Sicht fuer die ListView.</summary>
    public ICollectionView GroupedSettings { get; }

    public MainViewModel(IEnumerable<CatalogEntry> entries)
    {
        Settings = new ObservableCollection<SettingItemViewModel>(
            entries.Select(e => new SettingItemViewModel(e)));

        var cvs = new CollectionViewSource { Source = Settings };
        cvs.GroupDescriptions.Add(new PropertyGroupDescription(nameof(SettingItemViewModel.Workload)));
        cvs.SortDescriptions.Add(new SortDescription(nameof(SettingItemViewModel.Workload), ListSortDirection.Ascending));
        cvs.SortDescriptions.Add(new SortDescription(nameof(SettingItemViewModel.Nr), ListSortDirection.Ascending));
        GroupedSettings = cvs.View;
    }

    private string _breakGlass = "";
    public string BreakGlass
    {
        get => _breakGlass;
        set { _breakGlass = value; OnPropertyChanged(); }
    }

    private string _status = "Bereit.";
    public string Status
    {
        get => _status;
        set { _status = value; OnPropertyChanged(); }
    }

    public string[] BreakGlassList =>
        (BreakGlass ?? "").Split(new[] { ',', ';', ' ', '\n', '\r', '\t' },
            StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);

    public List<CatalogEntry> SelectedEntries() =>
        Settings.Where(s => s.IsIncluded).Select(s => s.Entry).ToList();

    /// <summary>Teilauswahl je Eintrag mit Unterpunkten (Eintrags-Id -> gewaehlte settingDefinitionIds).</summary>
    public Dictionary<string, HashSet<string>> SubSelection() =>
        Settings.Where(s => s.IsIncluded && s.HasSubItems)
                .ToDictionary(s => s.Entry.Id, s => s.SelectedSubDefIds!);

    public event PropertyChangedEventHandler? PropertyChanged;
    private void OnPropertyChanged([CallerMemberName] string? name = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}
