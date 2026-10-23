using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using HardeningGenerator.Models;

namespace HardeningGenerator.Services;

/// <summary>
/// Erzeugt aus den gewaehlten Katalog-Eintraegen EIN PowerShell-Skript
/// (Modi Preview/Apply/Revert, Break-Glass-Sperre, Backup, unassigned).
/// Eintraege mit gleicher ProfileGroup.Id werden in EIN gemeinsames Profil zusammengefasst.
/// Klasse-C-/gesperrte Eintraege werden grundsaetzlich nie erzeugt.
/// </summary>
public static class ScriptGenerator
{
    private const string GraphBase = "https://graph.microsoft.com/beta";

    public static string Generate(IEnumerable<CatalogEntry> selected, IEnumerable<string> breakGlass)
    {
        // Sicherheitsnetz: niemals Klasse C oder gesperrte Eintraege erzeugen
        var entries = selected
            .Where(e => !e.Ui.Locked && !string.Equals(e.RiskClass, "C", StringComparison.OrdinalIgnoreCase))
            .ToList();

        var ts = DateTime.Now.ToString("yyyy-MM-dd HH:mm");
        var scopes = entries.SelectMany(e => e.RequiredScopes).Distinct(StringComparer.OrdinalIgnoreCase).ToList();
        var bg = breakGlass.Where(b => !string.IsNullOrWhiteSpace(b)).ToList();

        // Nach ProfileGroup.Id bündeln; Eintraege ohne Gruppe bleiben eigenstaendig
        var groups = new List<List<CatalogEntry>>();
        var byGroupId = new Dictionary<string, List<CatalogEntry>>(StringComparer.OrdinalIgnoreCase);
        foreach (var e in entries)
        {
            var gid = e.ProfileGroup?.Id;
            if (!string.IsNullOrWhiteSpace(gid))
            {
                if (!byGroupId.TryGetValue(gid!, out var list))
                {
                    list = new List<CatalogEntry>();
                    byGroupId[gid!] = list;
                    groups.Add(list);
                }
                list.Add(e);
            }
            else
            {
                groups.Add(new List<CatalogEntry> { e });
            }
        }

        var sb = new StringBuilder();

        // ---------- Kopf ----------
        sb.AppendLine("<#");
        sb.AppendLine("  =====================================================================");
        sb.AppendLine("  4sight Hardening Generator - ERZEUGTES SKRIPT");
        sb.AppendLine($"  Erzeugt         : {ts}");
        sb.AppendLine($"  Profile         : {groups.Count}  (aus {entries.Count} Einstellung(en))");
        foreach (var g in groups)
        {
            var f = g[0];
            var pn = ProfileName(f);
            sb.AppendLine($"     - {pn}: {string.Join(", ", g.Select(x => x.ChecklistNr))}");
        }
        sb.AppendLine("  ---------------------------------------------------------------------");
        sb.AppendLine("  HINWEISE:");
        sb.AppendLine("   * READ-ONLY per Default. Ohne -Mode Apply wird NICHTS geschrieben.");
        sb.AppendLine("   * Alle Profile werden OHNE Zuweisung (unassigned) erzeugt.");
        sb.AppendLine("   * Vor jeder Aenderung Backup; -Mode Revert stellt den Vorzustand wieder her.");
        sb.AppendLine("   * Ausfuehrung durch ein Break-Glass-Konto wird verweigert.");
        sb.AppendLine("   * Re-Run ersetzt das jeweilige 4S-Profil (loeschen+neu); eine ggf. gesetzte");
        sb.AppendLine("     Zuweisung geht dabei verloren (In-Place-Update folgt spaeter).");
        sb.AppendLine("  =====================================================================");
        sb.AppendLine("#>");
        sb.AppendLine();

        // ---------- param ----------
        sb.AppendLine("[CmdletBinding()]");
        sb.AppendLine("param(");
        sb.AppendLine("  [ValidateSet('Preview','Apply','Revert')][string]$Mode = 'Preview',");
        sb.AppendLine($"  [string[]]$BreakGlassUpn = @({string.Join(",", bg.Select(SingleQuote))}),");
        sb.AppendLine("  [string]$BackupDir = (Join-Path $PSScriptRoot 'backup'),");
        sb.AppendLine("  [switch]$SkipSatisfied");
        sb.AppendLine(")");
        sb.AppendLine("$ErrorActionPreference = 'Stop'");
        sb.AppendLine($"$Scopes = @({string.Join(",", scopes.Select(SingleQuote))})");
        sb.AppendLine();

        // ---------- $Settings (ein Eintrag je Profil) ----------
        sb.AppendLine("$Settings = @(");
        foreach (var g in groups)
        {
            var first = g[0];
            var policyName = ProfileName(first);
            var resource = GraphBase + first.Graph.Resource;
            var title = ProfileTitle(first);
            var nr = string.Join("+", g.Select(x => x.ChecklistNr));
            var bodyJson = BuildMergedBody(g, policyName, title, ts);

            sb.AppendLine("  [pscustomobject]@{");
            sb.AppendLine($"    Nr         = {SingleQuote(nr)}");
            sb.AppendLine($"    Title      = {SingleQuote(title)}");
            sb.AppendLine($"    PolicyName = {SingleQuote(policyName)}");
            sb.AppendLine($"    Resource   = {SingleQuote(resource)}");
            sb.AppendLine("    Checks     = @(");
            foreach (var e in g)
            {
                var defId = e.Graph.Readback?.SettingDefinitionId ?? "";
                var desired = e.Graph.Readback?.DesiredValue ?? "";
                sb.AppendLine($"      [pscustomobject]@{{ Nr = {SingleQuote(e.ChecklistNr)}; Title = {SingleQuote(e.Title)}; ReadbackDef = {SingleQuote(defId)}; DesiredValue = {SingleQuote(desired)} }}");
            }
            sb.AppendLine("    )");
            sb.AppendLine("    BodyJson   = @'");
            sb.AppendLine(bodyJson);
            sb.AppendLine("'@");
            sb.AppendLine("  }");
        }
        sb.AppendLine(")");
        sb.AppendLine();

        sb.AppendLine(LogicBlock);
        return sb.ToString();
    }

    private static string ProfileName(CatalogEntry first) =>
        (first.ProfileGroup != null && !string.IsNullOrWhiteSpace(first.ProfileGroup.Id))
            ? first.ProfileGroup.PolicyName
            : first.Naming.PolicyName;

    private static string ProfileTitle(CatalogEntry first) =>
        (first.ProfileGroup != null && !string.IsNullOrWhiteSpace(first.ProfileGroup.Id))
            ? (first.ProfileGroup.Title ?? first.ProfileGroup.PolicyName)
            : first.Title;

    /// <summary>Fuehrt die settings[] aller Gruppen-Eintraege in EINEN Body zusammen.</summary>
    private static string BuildMergedBody(List<CatalogEntry> group, string policyName, string title, string ts)
    {
        var bodyObj = JsonNode.Parse(group[0].Graph.CreateBody.GetRawText())!.AsObject();

        var settings = new JsonArray();
        foreach (var e in group)
        {
            var eb = JsonNode.Parse(e.Graph.CreateBody.GetRawText())!.AsObject();
            if (eb["settings"] is JsonArray arr)
            {
                foreach (var node in arr)
                {
                    if (node != null) settings.Add(node.DeepClone());
                }
            }
        }

        bodyObj["name"] = policyName;
        bodyObj["description"] =
            $"Erstellt durch 4sight Hardening Generator ({ts}) - {title} [{string.Join(", ", group.Select(g => g.ChecklistNr))}].";
        bodyObj["settings"] = settings;

        var json = bodyObj.ToJsonString(new JsonSerializerOptions { WriteIndented = true });
        return json.Replace("{{policyName}}", policyName).Replace("{{timestamp}}", ts);
    }

    private static string SingleQuote(string s) => "'" + (s ?? "").Replace("'", "''") + "'";

    // Logik faithful zu Set-M365Hardening_B-08.ps1, generalisiert ueber $Settings (mit .Checks je Profil).
    private const string LogicBlock = """
# =====================================================================
# Helfer
# =====================================================================
function Connect-Graph {
    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
    Connect-MgGraph -Scopes $Scopes -NoWelcome
}
function Assert-NotBreakGlass {
    $me = (Get-MgContext).Account
    Write-Host "Angemeldet als: $me" -ForegroundColor Cyan
    foreach ($bg in $BreakGlassUpn) {
        if ($me -and $bg -and ($me.ToLower() -eq $bg.ToLower())) {
            throw "ABBRUCH: Ausfuehrung mit einem Break-Glass-Konto ($me) ist nicht zulaessig."
        }
    }
}
function Get-ExistingPolicy { param($Resource,$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return $null }
    $enc = [System.Uri]::EscapeDataString("name eq '$Name'")
    $resp = Invoke-MgGraphRequest -Method GET -Uri "$Resource`?`$filter=$enc" -OutputType PSObject
    if ($resp.value) { return $resp.value[0] }
    return $null
}
function Get-PolicyWithSettings { param($Resource,$Id)
    $p = Invoke-MgGraphRequest -Method GET -Uri "$Resource/$Id" -OutputType PSObject
    $s = Invoke-MgGraphRequest -Method GET -Uri "$Resource/$Id/settings" -OutputType PSObject
    $settings = @(); if ($s.value) { $settings = $s.value }
    $p | Add-Member -NotePropertyName settings -NotePropertyValue $settings -Force
    return $p
}
function Get-SettingValueFromPolicy { param($Pol,$DefId)
    foreach ($s in @($Pol.settings)) {
        $inst = $s.settingInstance
        if ($inst -and $inst.settingDefinitionId -eq $DefId -and $inst.choiceSettingValue) {
            return $inst.choiceSettingValue.value
        }
    }
    return $null
}
# ---- 'Bereits erfuellt?' : Index ueber ALLE configurationPolicies (einmalig, gecached) ----
$script:CfgIndex = $null
function Get-ConfigPolicyIndex { param($Resource)
    if ($script:CfgIndex -ne $null) { return $script:CfgIndex }
    $index = @{}
    $pols = @()
    $next = "$Resource`?`$top=100"
    while ($next) {
        $resp = Invoke-MgGraphRequest -Method GET -Uri $next -OutputType PSObject
        if ($resp.value) { $pols += $resp.value }
        if ($resp.PSObject.Properties.Name -contains '@odata.nextLink') { $next = $resp.'@odata.nextLink' } else { $next = $null }
    }
    foreach ($p in $pols) {
        try { $s = Invoke-MgGraphRequest -Method GET -Uri "$Resource/$($p.id)/settings" -OutputType PSObject } catch { continue }
        foreach ($si in @($s.value)) {
            $inst = $si.settingInstance
            if ($inst -and $inst.settingDefinitionId -and $inst.choiceSettingValue) {
                $def = $inst.settingDefinitionId
                if (-not $index.ContainsKey($def)) { $index[$def] = @() }
                $index[$def] += [pscustomobject]@{ Name = $p.name; Value = $inst.choiceSettingValue.value }
            }
        }
    }
    $script:CfgIndex = $index
    return $index
}
function Get-SatisfiedByDef { param($Resource,$DefId,$Desired,$OwnName)
    if (($Resource -notlike '*configurationPolicies') -or (-not $DefId) -or (-not $Desired)) { return @() }
    $idx = Get-ConfigPolicyIndex $Resource
    if (-not $idx.ContainsKey($DefId)) { return @() }
    return @($idx[$DefId] | Where-Object { $_.Value -eq $Desired -and $_.Name -ne $OwnName })
}
function Backup-One { param($Pol,$Nr,$Name)
    if (-not (Test-Path $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir | Out-Null }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $safe = ($Nr -replace '[^0-9A-Za-z\-]', '_')
    $file = Join-Path $BackupDir "$safe`_$Name`_$stamp.json"
    if ($Pol) { $Pol | ConvertTo-Json -Depth 30 | Set-Content -Path $file -Encoding UTF8 }
    else { @{ existed = $false; policyName = $Name } | ConvertTo-Json | Set-Content -Path $file -Encoding UTF8 }
    Write-Host "  Backup: $file" -ForegroundColor Green
}
function New-One { param($Resource,$BodyJson)
    $new = Invoke-MgGraphRequest -Method POST -Uri $Resource -Body $BodyJson -ContentType 'application/json' -OutputType PSObject
    Write-Host "  Angelegt (UNASSIGNED): id $($new.id)" -ForegroundColor Green
}
function Remove-One { param($Resource,$Id)
    Invoke-MgGraphRequest -Method DELETE -Uri "$Resource/$Id" | Out-Null
    Write-Host "  Geloescht: id $Id" -ForegroundColor Yellow
}
function Do-Preview { param($s)
    Write-Host "`n[$($s.Nr)] $($s.Title)  ($($s.PolicyName))" -ForegroundColor Cyan
    $ex = Get-ExistingPolicy $s.Resource $s.PolicyName
    $full = $null
    if ($ex) { $full = Get-PolicyWithSettings $s.Resource $ex.id }
    foreach ($c in $s.Checks) {
        $sat = Get-SatisfiedByDef $s.Resource $c.ReadbackDef $c.DesiredValue $s.PolicyName
        $cur = if ($full) { Get-SettingValueFromPolicy $full $c.ReadbackDef } else { $null }
        $curTxt = if ($cur) { $cur } else { '-' }
        Write-Host "   - [$($c.Nr)] $($c.Title): Ist(eigenes)=$curTxt | Soll=$($c.DesiredValue)"
        if ($sat.Count -gt 0) {
            Write-Host "       bereits erfuellt durch: $((@($sat | ForEach-Object { $_.Name })) -join ', ')" -ForegroundColor Green
        }
    }
    if ($ex) { Write-Host "  -> Apply wuerde '$($s.PolicyName)' ersetzen (Backup zuvor)." -ForegroundColor Yellow }
    else { Write-Host "  -> Apply wuerde '$($s.PolicyName)' NEU anlegen (unassigned)." -ForegroundColor Yellow }
}
function Do-Apply { param($s)
    Write-Host "`n[$($s.Nr)] $($s.Title)  ($($s.PolicyName))" -ForegroundColor Cyan
    if ($SkipSatisfied) {
        $allSat = $true
        foreach ($c in $s.Checks) {
            $sat = Get-SatisfiedByDef $s.Resource $c.ReadbackDef $c.DesiredValue $s.PolicyName
            if ($sat.Count -eq 0) { $allSat = $false; break }
        }
        if ($allSat) { Write-Host "  -> uebersprungen: alle Einstellungen bereits erfuellt (-SkipSatisfied)." -ForegroundColor Yellow; return }
    }
    $ex = Get-ExistingPolicy $s.Resource $s.PolicyName
    if ($ex) {
        $full = Get-PolicyWithSettings $s.Resource $ex.id
        Backup-One $full $s.Nr $s.PolicyName
        Remove-One $s.Resource $ex.id
    } else {
        Backup-One $null $s.Nr $s.PolicyName
    }
    New-One $s.Resource $s.BodyJson
}
function Do-Revert { param($s)
    Write-Host "`n[$($s.Nr)] $($s.Title)  ($($s.PolicyName))" -ForegroundColor Cyan
    $safe = ($s.Nr -replace '[^0-9A-Za-z\-]', '_')
    $bf = Get-ChildItem -Path $BackupDir -Filter "$safe`_*$($s.PolicyName)*.json" -ErrorAction SilentlyContinue |
          Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $ex = Get-ExistingPolicy $s.Resource $s.PolicyName
    if ($ex) { Remove-One $s.Resource $ex.id }
    if (-not $bf) { Write-Host "  Kein Backup gefunden - nur entfernt." -ForegroundColor Yellow; return }
    $backup = Get-Content $bf.FullName -Raw | ConvertFrom-Json
    if ($backup.PSObject.Properties.Name -contains 'existed' -and $backup.existed -eq $false) {
        Write-Host "  Vorher kein Profil -> wiederhergestellt (geloescht)." -ForegroundColor Green; return
    }
    $restore = [ordered]@{
        name            = $backup.name
        description     = $backup.description
        platforms       = $backup.platforms
        technologies    = $backup.technologies
        roleScopeTagIds = $backup.roleScopeTagIds
        settings        = $backup.settings
    }
    Invoke-MgGraphRequest -Method POST -Uri $s.Resource -Body ($restore | ConvertTo-Json -Depth 30) -ContentType 'application/json' | Out-Null
    Write-Host "  Wiederhergestellt." -ForegroundColor Green
}

# =====================================================================
# Ablauf
# =====================================================================
Connect-Graph
Assert-NotBreakGlass
Write-Host "`nModus: $Mode  |  Profile: $($Settings.Count)" -ForegroundColor Cyan
switch ($Mode) {
  'Preview' { foreach ($s in $Settings) { Do-Preview $s }; Write-Host "`nNichts geaendert. Zum Anwenden: -Mode Apply" -ForegroundColor Cyan }
  'Apply'   { foreach ($s in $Settings) { Do-Apply  $s }; Write-Host "`nFertig. Profile sind UNASSIGNED - Zuweisung bewusst manuell." -ForegroundColor Green }
  'Revert'  { foreach ($s in $Settings) { Do-Revert $s } }
}
try { Disconnect-MgGraph -ErrorAction SilentlyContinue -WarningAction SilentlyContinue 3>$null | Out-Null } catch {}
""";
}
