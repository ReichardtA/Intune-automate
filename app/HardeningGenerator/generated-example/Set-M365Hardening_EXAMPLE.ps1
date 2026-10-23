<#
#>
[CmdletBinding()]
param([ValidateSet('Preview','Apply','Revert')][string]$Mode='Preview',[string[]]$BreakGlassUpn=@(),[string]$BackupDir=(Join-Path $PSScriptRoot 'backup'),[switch]$SkipSatisfied)
$ErrorActionPreference='Stop'
$Scopes=@('DeviceManagementConfiguration.ReadWrite.All')

$Settings=@(
  [pscustomobject]@{
    Nr='B-08+B-09+B-10+B-11+B-13a+B-13b+B-13c'
    Title='Defender Antivirus - Baseline'
    PolicyName='4S-Defender-AV-Baseline'
    Resource='https://graph.microsoft.com/beta/deviceManagement/configurationPolicies'
    Checks=@(
      [pscustomobject]@{ Nr='B-08'; Title='Defender Antivirus: Echtzeitschutz aktivieren'; ReadbackDef='device_vendor_msft_policy_config_defender_allowrealtimemonitoring'; DesiredValue='device_vendor_msft_policy_config_defender_allowrealtimemonitoring_1' }
      [pscustomobject]@{ Nr='B-09'; Title='Defender Antivirus: Cloud-Schutz aktivieren'; ReadbackDef='device_vendor_msft_policy_config_defender_allowcloudprotection'; DesiredValue='device_vendor_msft_policy_config_defender_allowcloudprotection_1' }
      [pscustomobject]@{ Nr='B-10'; Title='Defender Antivirus: PUA-Schutz = Blockieren'; ReadbackDef='device_vendor_msft_policy_config_defender_puaprotection'; DesiredValue='device_vendor_msft_policy_config_defender_puaprotection_1' }
      [pscustomobject]@{ Nr='B-11'; Title='Defender Antivirus: Verhaltensueberwachung aktivieren'; ReadbackDef='device_vendor_msft_policy_config_defender_allowbehaviormonitoring'; DesiredValue='device_vendor_msft_policy_config_defender_allowbehaviormonitoring_1' }
      [pscustomobject]@{ Nr='B-13a'; Title='Defender Antivirus: Skript-Scan aktivieren'; ReadbackDef='device_vendor_msft_policy_config_defender_allowscriptscanning'; DesiredValue='device_vendor_msft_policy_config_defender_allowscriptscanning_1' }
      [pscustomobject]@{ Nr='B-13b'; Title='Defender Antivirus: Archiv-Scan aktivieren'; ReadbackDef='device_vendor_msft_policy_config_defender_allowarchivescanning'; DesiredValue='device_vendor_msft_policy_config_defender_allowarchivescanning_1' }
      [pscustomobject]@{ Nr='B-13c'; Title='Defender Antivirus: Download-/Anlagen-Scan aktivieren'; ReadbackDef='device_vendor_msft_policy_config_defender_allowioavprotection'; DesiredValue='device_vendor_msft_policy_config_defender_allowioavprotection_1' }
    )
    BodyJson=@'
{
  "name": "4S-Defender-AV-Baseline",
  "description": "... [B-08, B-09, B-10, B-11, B-13a, B-13b, B-13c].",
  "platforms": "windows10",
  "technologies": "mdm,microsoftSense",
  "roleScopeTagIds": [
    "0"
  ],
  "settings": [
    {
      "@odata.type": "#microsoft.graph.deviceManagementConfigurationSetting",
      "settingInstance": {
        "@odata.type": "#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance",
        "settingDefinitionId": "device_vendor_msft_policy_config_defender_allowrealtimemonitoring",
        "choiceSettingValue": {
          "@odata.type": "#microsoft.graph.deviceManagementConfigurationChoiceSettingValue",
          "value": "device_vendor_msft_policy_config_defender_allowrealtimemonitoring_1",
          "children": []
        }
      }
    },
    {
      "@odata.type": "#microsoft.graph.deviceManagementConfigurationSetting",
      "settingInstance": {
        "@odata.type": "#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance",
        "settingDefinitionId": "device_vendor_msft_policy_config_defender_allowcloudprotection",
        "choiceSettingValue": {
          "@odata.type": "#microsoft.graph.deviceManagementConfigurationChoiceSettingValue",
          "value": "device_vendor_msft_policy_config_defender_allowcloudprotection_1",
          "children": []
        }
      }
    },
    {
      "@odata.type": "#microsoft.graph.deviceManagementConfigurationSetting",
      "settingInstance": {
        "@odata.type": "#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance",
        "settingDefinitionId": "device_vendor_msft_policy_config_defender_puaprotection",
        "choiceSettingValue": {
          "@odata.type": "#microsoft.graph.deviceManagementConfigurationChoiceSettingValue",
          "value": "device_vendor_msft_policy_config_defender_puaprotection_1",
          "children": []
        }
      }
    },
    {
      "@odata.type": "#microsoft.graph.deviceManagementConfigurationSetting",
      "settingInstance": {
        "@odata.type": "#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance",
        "settingDefinitionId": "device_vendor_msft_policy_config_defender_allowbehaviormonitoring",
        "choiceSettingValue": {
          "@odata.type": "#microsoft.graph.deviceManagementConfigurationChoiceSettingValue",
          "value": "device_vendor_msft_policy_config_defender_allowbehaviormonitoring_1",
          "children": []
        }
      }
    },
    {
      "@odata.type": "#microsoft.graph.deviceManagementConfigurationSetting",
      "settingInstance": {
        "@odata.type": "#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance",
        "settingDefinitionId": "device_vendor_msft_policy_config_defender_allowscriptscanning",
        "choiceSettingValue": {
          "@odata.type": "#microsoft.graph.deviceManagementConfigurationChoiceSettingValue",
          "value": "device_vendor_msft_policy_config_defender_allowscriptscanning_1",
          "children": []
        }
      }
    },
    {
      "@odata.type": "#microsoft.graph.deviceManagementConfigurationSetting",
      "settingInstance": {
        "@odata.type": "#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance",
        "settingDefinitionId": "device_vendor_msft_policy_config_defender_allowarchivescanning",
        "choiceSettingValue": {
          "@odata.type": "#microsoft.graph.deviceManagementConfigurationChoiceSettingValue",
          "value": "device_vendor_msft_policy_config_defender_allowarchivescanning_1",
          "children": []
        }
      }
    },
    {
      "@odata.type": "#microsoft.graph.deviceManagementConfigurationSetting",
      "settingInstance": {
        "@odata.type": "#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance",
        "settingDefinitionId": "device_vendor_msft_policy_config_defender_allowioavprotection",
        "choiceSettingValue": {
          "@odata.type": "#microsoft.graph.deviceManagementConfigurationChoiceSettingValue",
          "value": "device_vendor_msft_policy_config_defender_allowioavprotection_1",
          "children": []
        }
      }
    }
  ]
}
'@
  }
  [pscustomobject]@{
    Nr='B-12'
    Title='Defender: Netzwerkschutz (Network Protection)'
    PolicyName='4S-Defender-NetworkProtection-Audit'
    Resource='https://graph.microsoft.com/beta/deviceManagement/configurationPolicies'
    Checks=@(
      [pscustomobject]@{ Nr='B-12'; Title='Defender: Netzwerkschutz (Network Protection)'; ReadbackDef='device_vendor_msft_policy_config_defender_enablenetworkprotection'; DesiredValue='device_vendor_msft_policy_config_defender_enablenetworkprotection_2' }
    )
    BodyJson=@'
{
  "name": "4S-Defender-NetworkProtection-Audit",
  "description": "... [B-12].",
  "platforms": "windows10",
  "technologies": "mdm,microsoftSense",
  "roleScopeTagIds": [
    "0"
  ],
  "settings": [
    {
      "@odata.type": "#microsoft.graph.deviceManagementConfigurationSetting",
      "settingInstance": {
        "@odata.type": "#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance",
        "settingDefinitionId": "device_vendor_msft_policy_config_defender_enablenetworkprotection",
        "choiceSettingValue": {
          "@odata.type": "#microsoft.graph.deviceManagementConfigurationChoiceSettingValue",
          "value": "device_vendor_msft_policy_config_defender_enablenetworkprotection_2",
          "children": []
        }
      }
    }
  ]
}
'@
  }
  [pscustomobject]@{
    Nr='B-17'
    Title='Defender: Ueberwachter Ordnerzugriff (Controlled Folder Access)'
    PolicyName='4S-Defender-ControlledFolderAccess-Audit'
    Resource='https://graph.microsoft.com/beta/deviceManagement/configurationPolicies'
    Checks=@(
      [pscustomobject]@{ Nr='B-17'; Title='Defender: Ueberwachter Ordnerzugriff (Controlled Folder Access)'; ReadbackDef='device_vendor_msft_policy_config_defender_enablecontrolledfolderaccess'; DesiredValue='device_vendor_msft_policy_config_defender_enablecontrolledfolderaccess_2' }
    )
    BodyJson=@'
{
  "name": "4S-Defender-ControlledFolderAccess-Audit",
  "description": "... [B-17].",
  "platforms": "windows10",
  "technologies": "mdm,microsoftSense",
  "roleScopeTagIds": [
    "0"
  ],
  "settings": [
    {
      "@odata.type": "#microsoft.graph.deviceManagementConfigurationSetting",
      "settingInstance": {
        "@odata.type": "#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance",
        "settingDefinitionId": "device_vendor_msft_policy_config_defender_enablecontrolledfolderaccess",
        "choiceSettingValue": {
          "@odata.type": "#microsoft.graph.deviceManagementConfigurationChoiceSettingValue",
          "value": "device_vendor_msft_policy_config_defender_enablecontrolledfolderaccess_2",
          "children": []
        }
      }
    }
  ]
}
'@
  }
)

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
