using System.Text.Json;
using System.Text.Json.Serialization;

namespace HardeningGenerator.Models;

/// <summary>Ein Katalog-Eintrag = eine waehlbare Einstellung. Spiegelt catalog.schema.json.</summary>
public class CatalogEntry
{
    public string Id { get; set; } = "";
    public string ChecklistNr { get; set; } = "";
    public string Workload { get; set; } = "";
    public string? Category { get; set; }
    public string Title { get; set; } = "";
    public string? Description { get; set; }
    public string Tier { get; set; } = "";

    /// <summary>A = sicher, B = betriebs-/sicherheitskritisch (nur sichere Form), C = aussperr-faehig (gesperrt).</summary>
    public string RiskClass { get; set; } = "A";
    public string? RiskRationale { get; set; }

    public SafeModeInfo SafeMode { get; set; } = new();
    public UiInfo Ui { get; set; } = new();
    public string[] RequiredScopes { get; set; } = System.Array.Empty<string>();
    public NamingInfo Naming { get; set; } = new();

    /// <summary>Optional: mehrere Eintraege mit gleicher Id landen in EINEM gemeinsamen Profil.</summary>
    public ProfileGroupInfo? ProfileGroup { get; set; }

    public GraphInfo Graph { get; set; } = new();
    public RevertInfo? Revert { get; set; }
    public string? VerifyInTestTenant { get; set; }
    public string[]? References { get; set; }
}

public class SafeModeInfo
{
    public string Assignment { get; set; } = "unassigned";
    public string? Mode { get; set; }
    public string? Note { get; set; }
}

public class UiInfo
{
    public bool Selectable { get; set; } = true;
    public bool Locked { get; set; }
    public string? WarnText { get; set; }
}

public class NamingInfo
{
    public string? Prefix { get; set; }
    public string PolicyName { get; set; } = "";
}

public class ProfileGroupInfo
{
    public string Id { get; set; } = "";
    public string PolicyName { get; set; } = "";
    public string? Title { get; set; }
}

public class GraphInfo
{
    public string Resource { get; set; } = "";
    public string? MatchBy { get; set; }

    /// <summary>Roh-JSON des Payloads (mit Platzhaltern {{policyName}}, {{timestamp}}).</summary>
    public JsonElement CreateBody { get; set; }

    public ReadbackInfo? Readback { get; set; }
}

public class ReadbackInfo
{
    public string? SettingDefinitionId { get; set; }
    public string? DesiredValue { get; set; }
}

public class RevertInfo
{
    public string Strategy { get; set; } = "restoreFromBackup";
    public string? Note { get; set; }
}
