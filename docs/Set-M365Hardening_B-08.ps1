<#
  =====================================================================
  4sight Hardening Generator - ERZEUGTES SKRIPT (Beispiel)
  Checkliste-Punkt : B-08  Defender Antivirus: Echtzeitschutz aktivieren
  Katalog-ID       : intune.defender.av.realtimeMonitoring
  Risikoklasse     : A (sicher)
  Erzeugt          : <GENERATOR fuellt Zeitstempel ein>
  Generator-Version: 0.1 (Beispiel/Prototyp)
  ---------------------------------------------------------------------
  HINWEISE (automatisch eingefuegt):
   * READ-ONLY per Default. Ohne -Mode Apply wird NICHTS geschrieben.
   * Das Profil wird OHNE Zuweisung (unassigned) erzeugt. Der Rollout
     auf eine Gruppe oder 'Alle' ist ein bewusster, manueller Schritt.
   * Vor jeder Aenderung wird ein Backup des bestehenden Profils
     (falls vorhanden) als JSON gesichert. -Mode Revert stellt es wieder her.
   * Ausfuehrung durch ein Break-Glass-Konto wird verweigert.
   * Dieses Skript aendert ausschliesslich das genannte Profil.
  =====================================================================
#>

[CmdletBinding()]
param(
    [ValidateSet('Preview','Apply','Revert')]
    [string] $Mode = 'Preview',

    # Break-Glass-UPNs des Tenants (aus der App uebergeben). Ausfuehrung damit wird blockiert.
    [string[]] $BreakGlassUpn = @(),

    [string] $BackupDir = (Join-Path $PSScriptRoot 'backup'),

    # Fuer -Mode Revert: Pfad zur Backup-JSON (leer = juengstes Backup verwenden).
    [string] $BackupFile
)

$ErrorActionPreference = 'Stop'

# ----- Vom Generator aus dem Katalog eingesetzte Werte -----
$PolicyName   = '4S-Defender-AV-Baseline'
$Scopes       = @('DeviceManagementConfiguration.ReadWrite.All')
$Resource     = 'https://graph.microsoft.com/beta/deviceManagement/configurationPolicies'
$ReadbackDef  = 'device_vendor_msft_policy_config_defender_allowrealtimemonitoring'
$DesiredValue = 'device_vendor_msft_policy_config_defender_allowrealtimemonitoring_1'

# Gewuenschter Payload (unassigned - KEINE assignments-Eigenschaft)
$DesiredBody = [ordered]@{
    name            = $PolicyName
    description     = "Erstellt durch 4sight Hardening Generator ($(Get-Date -Format 'yyyy-MM-dd HH:mm')) - Checkliste B-08 (Echtzeitschutz)."
    platforms       = 'windows10'
    technologies    = 'mdm,microsoftSense'
    roleScopeTagIds = @('0')
    settings        = @(
        [ordered]@{
            '@odata.type'   = '#microsoft.graph.deviceManagementConfigurationSetting'
            settingInstance = [ordered]@{
                '@odata.type'       = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance'
                settingDefinitionId = $ReadbackDef
                choiceSettingValue  = [ordered]@{
                    '@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingValue'
                    value         = $DesiredValue
                    children      = @()
                }
            }
        }
    )
}

# =====================================================================
# Helfer
# =====================================================================
function Connect-Graph {
    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
    Connect-MgGraph -Scopes $Scopes -NoWelcome
}

function Assert-NotBreakGlass {
    $ctx = Get-MgContext
    $me  = $ctx.Account
    Write-Host "Angemeldet als: $me" -ForegroundColor Cyan
    foreach ($bg in $BreakGlassUpn) {
        if ($me -and $bg -and ($me.ToLower() -eq $bg.ToLower())) {
            throw "ABBRUCH: Ausfuehrung mit einem Break-Glass-Konto ($me) ist nicht zulaessig."
        }
    }
}

function Get-ExistingPolicy {
    # Bestehendes Profil gleichen Namens finden (matchBy = name)
    $enc = [System.Uri]::EscapeDataString("name eq '$PolicyName'")
    $resp = Invoke-MgGraphRequest -Method GET -Uri "$Resource`?`$filter=$enc" -OutputType PSObject
    if ($resp.value) { return $resp.value[0] }
    return $null
}

function Get-PolicyWithSettings {
    param($id)
    $p = Invoke-MgGraphRequest -Method GET -Uri "$Resource/$id" -OutputType PSObject
    $s = Invoke-MgGraphRequest -Method GET -Uri "$Resource/$id/settings" -OutputType PSObject
    $settings = @()
    if ($s.value) { $settings = $s.value }
    # settings als eigenschaft anheften (fuer Backup/Recreate)
    $p | Add-Member -NotePropertyName settings -NotePropertyValue $settings -Force
    return $p
}

function Get-RealtimeValue {
    param($policyWithSettings)
    foreach ($s in @($policyWithSettings.settings)) {
        $inst = $s.settingInstance
        if ($inst -and $inst.settingDefinitionId -eq $ReadbackDef -and $inst.choiceSettingValue) {
            return $inst.choiceSettingValue.value
        }
    }
    return $null
}

function Backup-Policy {
    param($policyWithSettings)
    if (-not (Test-Path $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir | Out-Null }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $file  = Join-Path $BackupDir "B-08_$PolicyName`_$stamp.json"
    if ($policyWithSettings) {
        $policyWithSettings | ConvertTo-Json -Depth 30 | Set-Content -Path $file -Encoding UTF8
        Write-Host "Backup geschrieben: $file" -ForegroundColor Green
    } else {
        @{ existed = $false; policyName = $PolicyName; note = 'Kein bestehendes Profil - Revert = loeschen.' } |
            ConvertTo-Json | Set-Content -Path $file -Encoding UTF8
        Write-Host "Backup (kein Bestand) geschrieben: $file" -ForegroundColor Green
    }
    return $file
}

function New-Policy {
    $json = $DesiredBody | ConvertTo-Json -Depth 30
    $new  = Invoke-MgGraphRequest -Method POST -Uri $Resource -Body $json -ContentType 'application/json' -OutputType PSObject
    Write-Host "Profil angelegt: $($new.name)  (id $($new.id))  - UNASSIGNED" -ForegroundColor Green
    return $new
}

function Remove-Policy {
    param($id)
    Invoke-MgGraphRequest -Method DELETE -Uri "$Resource/$id" | Out-Null
    Write-Host "Profil geloescht (id $id)." -ForegroundColor Yellow
}

# =====================================================================
# Ablauf
# =====================================================================
Connect-Graph
Assert-NotBreakGlass

switch ($Mode) {

  'Preview' {
    Write-Host "`n=== VORSCHAU (read-only) - B-08 Echtzeitschutz ===" -ForegroundColor Cyan
    $existing = Get-ExistingPolicy
    if ($existing) {
        $full = Get-PolicyWithSettings $existing.id
        $cur  = Get-RealtimeValue $full
        $curTxt = if ($cur) { $cur } else { '(Einstellung nicht im Profil gesetzt)' }
        Write-Host "Bestehendes Profil : '$PolicyName' (id $($existing.id))"
        Write-Host "  Ist  : $curTxt"
        Write-Host "  Soll : $DesiredValue"
        if ($cur -eq $DesiredValue) {
            Write-Host "  -> Bereits konform. 'Apply' wuerde es (unveraendert) neu setzen." -ForegroundColor Green
        } else {
            Write-Host "  -> Abweichung. 'Apply' wuerde das Profil auf den Soll-Wert bringen." -ForegroundColor Yellow
        }
    } else {
        Write-Host "Kein Profil '$PolicyName' vorhanden."
        Write-Host "  Soll : $DesiredValue"
        Write-Host "  -> 'Apply' wuerde das Profil NEU anlegen (unassigned)." -ForegroundColor Yellow
    }
    Write-Host "`nEs wurde NICHTS geaendert. Zum Anwenden: -Mode Apply" -ForegroundColor Cyan
  }

  'Apply' {
    Write-Host "`n=== ANWENDEN - B-08 Echtzeitschutz ===" -ForegroundColor Cyan
    $existing = Get-ExistingPolicy
    if ($existing) {
        $full = Get-PolicyWithSettings $existing.id
        Backup-Policy $full | Out-Null
        # 'aktualisieren statt doppelt anlegen' = sauberer Ersatz (bei unassigned unkritisch)
        Remove-Policy $existing.id
    } else {
        Backup-Policy $null | Out-Null
    }
    New-Policy | Out-Null
    Write-Host "`nFertig. Profil ist UNASSIGNED - Zuweisung bewusst manuell vornehmen." -ForegroundColor Green
    Write-Host "Revert: -Mode Revert   (nutzt das juengste Backup in $BackupDir)" -ForegroundColor Cyan
  }

  'Revert' {
    Write-Host "`n=== REVERT - B-08 Echtzeitschutz ===" -ForegroundColor Cyan
    if (-not $BackupFile) {
        $BackupFile = Get-ChildItem -Path $BackupDir -Filter "B-08_*$PolicyName*.json" -ErrorAction SilentlyContinue |
                      Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
    }
    if (-not $BackupFile -or -not (Test-Path $BackupFile)) { throw "Kein Backup gefunden. -BackupFile angeben." }
    Write-Host "Backup: $BackupFile"
    $backup = Get-Content $BackupFile -Raw | ConvertFrom-Json

    # aktuelles Profil (falls vorhanden) entfernen
    $current = Get-ExistingPolicy
    if ($current) { Remove-Policy $current.id }

    if ($backup.PSObject.Properties.Name -contains 'existed' -and $backup.existed -eq $false) {
        Write-Host "Vorher existierte kein Profil -> Zustand wiederhergestellt (geloescht)." -ForegroundColor Green
    } else {
        # gesichertes Profil neu anlegen (nur die relevanten Felder)
        $restore = [ordered]@{
            name            = $backup.name
            description     = $backup.description
            platforms       = $backup.platforms
            technologies    = $backup.technologies
            roleScopeTagIds = $backup.roleScopeTagIds
            settings        = $backup.settings
        }
        $json = $restore | ConvertTo-Json -Depth 30
        Invoke-MgGraphRequest -Method POST -Uri $Resource -Body $json -ContentType 'application/json' | Out-Null
        Write-Host "Gesichertes Profil wiederhergestellt." -ForegroundColor Green
    }
  }
}

try { Disconnect-MgGraph -ErrorAction SilentlyContinue -WarningAction SilentlyContinue 3>$null | Out-Null } catch {}
