<#
  Export-IntuneConfigPolicy.ps1
  -----------------------------------------------------------------
  READ-ONLY Hilfswerkzeug zum Autoren neuer Katalog-Eintraege:
  exportiert die EXAKTE settings-JSON eines Settings-Catalog-Profils
  (settingDefinitionId + Choice-Values), so wie Graph sie liefert.

  Verwendung:
    # 1) Alle Profile auflisten:
    .\Export-IntuneConfigPolicy.ps1 -List
    # 2) Ein Profil exportieren:
    .\Export-IntuneConfigPolicy.ps1 -Name "TEMP-ASR-Export" -OutFile asr.json

  Berechtigung: DeviceManagementConfiguration.Read.All (nur lesen).
#>
[CmdletBinding()]
param(
    [string] $Name,
    [switch] $List,
    [string] $OutFile,
    [string] $TenantId
)

$ErrorActionPreference = 'Stop'
Import-Module Microsoft.Graph.Authentication -ErrorAction Stop

$scopes = @('DeviceManagementConfiguration.Read.All')
if ($TenantId) { Connect-MgGraph -Scopes $scopes -TenantId $TenantId -NoWelcome }
else { Connect-MgGraph -Scopes $scopes -NoWelcome }

$base = 'https://graph.microsoft.com/beta/deviceManagement/configurationPolicies'

function Get-AllPolicies {
    $items = @()
    $next = "$base`?`$top=100"
    while ($next) {
        $r = Invoke-MgGraphRequest -Method GET -Uri $next -OutputType PSObject
        if ($r.value) { $items += $r.value }
        if ($r.PSObject.Properties.Name -contains '@odata.nextLink') { $next = $r.'@odata.nextLink' } else { $next = $null }
    }
    return $items
}

if ($List -or -not $Name) {
    Write-Host "`nVorhandene Settings-Catalog-Profile:`n" -ForegroundColor Cyan
    Get-AllPolicies | Sort-Object name | ForEach-Object { Write-Host ("  {0,-45} [{1}]" -f $_.name, $_.id) }
    if (-not $Name) {
        Write-Host "`nTipp: -Name '<Profilname>' exportiert dessen settings als JSON." -ForegroundColor Yellow
        try { Disconnect-MgGraph -ErrorAction SilentlyContinue -WarningAction SilentlyContinue 3>$null | Out-Null } catch {}
        return
    }
}

$pol = Get-AllPolicies | Where-Object { $_.name -eq $Name } | Select-Object -First 1
if (-not $pol) { throw "Profil '$Name' nicht gefunden. Mit -List die Namen pruefen." }

$settings = Invoke-MgGraphRequest -Method GET -Uri "$base/$($pol.id)/settings" -OutputType PSObject

$export = [ordered]@{
    name            = $pol.name
    platforms       = $pol.platforms
    technologies    = $pol.technologies
    roleScopeTagIds = $pol.roleScopeTagIds
    settings        = @($settings.value)
}
$json = $export | ConvertTo-Json -Depth 40

if ($OutFile) {
    $json | Set-Content -Path $OutFile -Encoding UTF8
    Write-Host "Geschrieben: $OutFile" -ForegroundColor Green
} else {
    $json
}

try { Disconnect-MgGraph -ErrorAction SilentlyContinue -WarningAction SilentlyContinue 3>$null | Out-Null } catch {}
