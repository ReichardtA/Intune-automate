<#
.SYNOPSIS
    Liest die allgemeinen M365-Sicherheitseinstellungen (Business Premium) aus und schreibt
    Ist-Wert + Status pro Kontrollpunkt zurueck in die Excel-Checkliste
    "M365_BusinessPremium_Sicherheit_Checkliste".

.DESCRIPTION
    READ-ONLY. Das Skript nimmt KEINE Aenderungen am Tenant vor. Es verbindet sich mit
    Microsoft Graph, Exchange Online, Security & Compliance (IPPS) und dem DNS und wertet
    die im Blatt "Auslese-Mapping" als auslesbar markierten Punkte automatisch aus.
    Ergebnis wird ueber das Modul ImportExcel in das Blatt "Checkliste" geschrieben:
        Spalte H (Ist-Wert / Konfiguriert)  <- Auswertungstext + Zeitstempel
        Spalte I (Status)                   <- Erledigt | Teilweise | Offen | n.a.
    Alle anderen Blaetter, Formatierungen und die Spalte J (Bemerkung) bleiben unveraendert.

    Punkte ohne automatischen Check (Sektion E, organisatorische Punkte) werden mit einem
    Hinweis in Spalte H markiert; ihr Status bleibt unveraendert.

.REQUIREMENTS
    PowerShell 7+ (empfohlen) unter Windows (Resolve-DnsName fuer SPF/DMARC).
    Module:  Microsoft.Graph, ExchangeOnlineManagement, ImportExcel
        Install-Module Microsoft.Graph, ExchangeOnlineManagement, ImportExcel -Scope CurrentUser

.PERMISSIONS (nur lesend)
    Graph (delegiert oder Applikation):
        Directory.Read.All, Policy.Read.All, RoleManagement.Read.Directory,
        Organization.Read.All, SecurityEvents.Read.All,
        DeviceManagementConfiguration.Read.All, DeviceManagementManagedDevices.Read.All,
        SharePointTenantSettings.Read.All, Application.Read.All
    Exchange Online / Security & Compliance:
        Rolle "Global Reader" bzw. "View-Only Configuration" / "Security Reader".

.PARAMETER ChecklistPath
    Pfad zur Excel-Checkliste (Eingabe).

.PARAMETER OutputPath
    Zielpfad. Standard: <Checkliste>_ausgewertet_<yyyyMMdd-HHmm>.xlsx (Original bleibt erhalten).

.PARAMETER InPlace
    Schreibt direkt in die Eingabedatei statt in eine Kopie.

.PARAMETER TenantId
    Tenant (GUID oder Domaene). Bei App-only zwingend.

.PARAMETER AppOnly
    App-only-Authentifizierung (MSP / unbeaufsichtigt) statt interaktiv.

.PARAMETER ClientId, CertificateThumbprint
    Fuer App-only benoetigt (App-Registrierung + Zertifikat).

.PARAMETER Skip*
    Einzelne Engines ueberspringen (z. B. -SkipCompliance, wenn IPPS nicht verbunden werden soll).

.EXAMPLE
    # Ein Tenant, interaktiv:
    .\Invoke-M365SecurityAssessment.ps1 -ChecklistPath .\Checkliste.xlsx

.EXAMPLE
    # MSP / app-only:
    .\Invoke-M365SecurityAssessment.ps1 -ChecklistPath .\Checkliste.xlsx `
        -AppOnly -TenantId contoso.onmicrosoft.com -ClientId <appid> -CertificateThumbprint <thumb>

.NOTES
    Erstellt als Begleitwerkzeug zur Sicherheits-Dokumentation. Erweiterbar: neuer Check =
    ein Eintrag in $Checks (Key = Nr., Engine, Run-Scriptblock, der New-CheckResult zurueckgibt).
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $ChecklistPath,
    [string] $OutputPath,
    [switch] $InPlace,
    [string] $TenantId,
    [switch] $AppOnly,
    [string] $ClientId,
    [string] $CertificateThumbprint,
    [switch] $SkipGraph,
    [switch] $SkipExchange,
    [switch] $SkipCompliance,
    [switch] $SkipDns,
    [string[]] $Domains   # optionale DNS-Domaenenliste; sonst aus Exchange (Get-AcceptedDomain)
)

$ErrorActionPreference = 'Stop'

# Ergebnis-Container: Status muss einem der Dropdown-Werte entsprechen oder $null (=unveraendert lassen)
function New-CheckResult {
    param([string]$Ist, [string]$Status)
    if ([string]::IsNullOrWhiteSpace($Status)) { $Status = $null }
    [pscustomobject]@{ Ist = $Ist; Status = $Status }
}

# ------------------------------------------------------------------ Module pruefen
function Assert-Modules {
    $needed = @('ImportExcel')
    if (-not $SkipGraph)      { $needed += 'Microsoft.Graph.Authentication' }
    if (-not $SkipExchange -or -not $SkipCompliance) { $needed += 'ExchangeOnlineManagement' }
    foreach ($m in $needed) {
        if (-not (Get-Module -ListAvailable -Name $m)) {
            throw "Modul '$m' fehlt. Bitte installieren:  Install-Module $m -Scope CurrentUser"
        }
    }
}

# ------------------------------------------------------------------ Verbindungen
$script:Connected = @{ Graph=$false; EXO=$false; SCC=$false; DNS=$false }

function Connect-Engines {
    # ---- Microsoft Graph ----
    if (-not $SkipGraph) {
        $scopes = @(
            'Directory.Read.All','Policy.Read.All','RoleManagement.Read.Directory',
            'Organization.Read.All','SecurityEvents.Read.All',
            'DeviceManagementConfiguration.Read.All','DeviceManagementManagedDevices.Read.All',
            'SharePointTenantSettings.Read.All','Application.Read.All'
        )
        try {
            Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
            if ($AppOnly) {
                if (-not ($TenantId -and $ClientId -and $CertificateThumbprint)) {
                    throw 'App-only erfordert -TenantId, -ClientId und -CertificateThumbprint.'
                }
                Connect-MgGraph -TenantId $TenantId -ClientId $ClientId `
                    -CertificateThumbprint $CertificateThumbprint -NoWelcome
            } else {
                $p = @{ Scopes = $scopes; NoWelcome = $true }
                if ($TenantId) { $p['TenantId'] = $TenantId }
                Connect-MgGraph @p
            }
            $script:Connected.Graph = $true
            Write-Host "  [+] Microsoft Graph verbunden." -ForegroundColor Green
        } catch { Write-Warning "Graph-Verbindung fehlgeschlagen: $($_.Exception.Message)" }
    }

    # ---- Exchange Online ----
    if (-not $SkipExchange) {
        try {
            Import-Module ExchangeOnlineManagement -ErrorAction Stop
            if ($AppOnly) {
                Connect-ExchangeOnline -AppId $ClientId -Organization $TenantId `
                    -CertificateThumbprint $CertificateThumbprint -ShowBanner:$false
            } else {
                Connect-ExchangeOnline -ShowBanner:$false
            }
            $script:Connected.EXO = $true
            Write-Host "  [+] Exchange Online verbunden." -ForegroundColor Green
        } catch { Write-Warning "Exchange-Online-Verbindung fehlgeschlagen: $($_.Exception.Message)" }
    }

    # ---- Security & Compliance (IPPS) ----
    if (-not $SkipCompliance) {
        try {
            Import-Module ExchangeOnlineManagement -ErrorAction Stop
            if ($AppOnly) {
                Connect-IPPSSession -AppId $ClientId -Organization $TenantId `
                    -CertificateThumbprint $CertificateThumbprint -ShowBanner:$false
            } else {
                Connect-IPPSSession
            }
            $script:Connected.SCC = $true
            Write-Host "  [+] Security & Compliance verbunden." -ForegroundColor Green
        } catch { Write-Warning "Security-&-Compliance-Verbindung fehlgeschlagen: $($_.Exception.Message)" }
    }

    if (-not $SkipDns) {
        $script:Connected.DNS = [bool](Get-Command Resolve-DnsName -ErrorAction SilentlyContinue)
        if (-not $script:Connected.DNS) { Write-Warning 'Resolve-DnsName nicht verfuegbar (Windows noetig) - DNS-Checks werden uebersprungen.' }
    }
}

# ------------------------------------------------------------------ Graph-Helfer + Cache
$script:Cache = @{}
function Invoke-Graph {
    param([string]$Uri)
    if ($Uri -notmatch '^https://') { $Uri = "https://graph.microsoft.com/$Uri" }
    Invoke-MgGraphRequest -Method GET -Uri $Uri -OutputType PSObject
}
function Get-GraphCollection {
    param([string]$Uri)
    $items = @(); $next = $Uri
    while ($next) {
        $r = Invoke-Graph $next
        if ($r.PSObject.Properties.Name -contains 'value') { $items += $r.value } else { $items += $r }
        if ($r.PSObject.Properties.Name -contains '@odata.nextLink') { $next = $r.'@odata.nextLink' } else { $next = $null }
    }
    ,$items
}
function Get-Cached { param([string]$Key,[scriptblock]$Get)
    if (-not $script:Cache.ContainsKey($Key)) { $script:Cache[$Key] = & $Get }
    $script:Cache[$Key]
}
function Get-CAPolicies { Get-Cached 'ca' { Get-GraphCollection 'v1.0/identity/conditionalAccess/policies' } }
function Get-EnabledCA   { Get-CAPolicies | Where-Object { $_.state -eq 'enabled' } }

# kleine Bewertungshilfe
function Resolve-Status {
    param([bool]$Ok, [bool]$Partial)
    if ($Ok) { 'Erledigt' } elseif ($Partial) { 'Teilweise' } else { 'Offen' }
}

# ==================================================================
#  CHECK-REGISTRY   ( Key = Nr. ; Engine ; Run = Scriptblock -> New-CheckResult )
# ==================================================================
$Checks = [ordered]@{}
function Register { param($Nr,$Engine,$Run) $Checks[$Nr] = @{ Engine=$Engine; Run=$Run } }

# ---------------- 0 Grundlagen ----------------
Register '0-01' 'Graph' {
    $skus = Get-Cached 'skus' { Get-GraphCollection 'v1.0/subscribedSkus' }
    $bp = $skus | Where-Object { $_.skuPartNumber -in @('SPB','O365_BUSINESS_PREMIUM','Microsoft_365_Business_Premium') }
    if ($bp) {
        $c = ($bp | ForEach-Object { [int]$_.consumedUnits } | Measure-Object -Sum).Sum
        $e = ($bp | ForEach-Object { [int]$_.prepaidUnits.enabled } | Measure-Object -Sum).Sum
        New-CheckResult "Business Premium: $c von $e Lizenzen zugewiesen (SkuPartNumber SPB)" (Resolve-Status ($c -gt 0) $false)
    } else {
        New-CheckResult "Keine Business-Premium-SKU (SPB) gefunden. Vorhandene SKUs: $(( $skus.skuPartNumber ) -join ', ')" 'Offen'
    }
}
Register '0-03' 'Graph' {
    $roles = Get-GraphCollection 'v1.0/directoryRoles'
    $ga = $roles | Where-Object { $_.displayName -eq 'Global Administrator' -or $_.displayName -eq 'Globaler Administrator' }
    if (-not $ga) { return New-CheckResult 'Rolle Global Administrator nicht aktiviert/gefunden.' 'Teilweise' }
    $members = Get-GraphCollection "v1.0/directoryRoles/$($ga.id)/members"
    $n = @($members).Count
    New-CheckResult "$n Global Admin(s)." (Resolve-Status ($n -ge 1 -and $n -le 4) ($n -gt 4))
}
Register '0-05' 'Graph' {
    $org = (Get-Cached 'org' { Get-GraphCollection 'v1.0/organization' })[0]
    $tech = @($org.technicalNotificationMails) -join ', '
    $sec  = @($org.securityComplianceNotificationMails) -join ', '
    $ok = [bool]$tech
    New-CheckResult "Technical: '$tech' | Security: '$sec'" (Resolve-Status $ok $false)
}
Register '0-08' 'Graph' {
    $ss = (Get-GraphCollection 'v1.0/security/secureScores?$top=1')[0]
    if (-not $ss) { return New-CheckResult 'Kein Secure Score abrufbar.' 'Teilweise' }
    $pct = [math]::Round(($ss.currentScore / [math]::Max($ss.maxScore,1))*100,1)
    New-CheckResult "Secure Score: $($ss.currentScore)/$($ss.maxScore) ($pct %) am $($ss.createdDateTime). Zielwert manuell vereinbaren." 'Teilweise'
}

# ---------------- A Entra ID ----------------
Register 'A-01' 'Graph' {
    $sd = Invoke-Graph 'v1.0/policies/identitySecurityDefaultsEnforcementPolicy'
    $caCount = @(Get-EnabledCA).Count
    $ok = (-not $sd.isEnabled) -and ($caCount -gt 0)
    New-CheckResult "Security Defaults isEnabled=$($sd.isEnabled); aktive CA-Richtlinien: $caCount" (Resolve-Status $ok ($caCount -gt 0))
}
Register 'A-04' 'Graph' {
    $hit = Get-EnabledCA | Where-Object {
        ($_.conditions.users.includeUsers -contains 'All') -and
        ($_.grantControls.builtInControls -contains 'mfa' -or $_.grantControls.authenticationStrength)
    }
    New-CheckResult ("MFA-fuer-alle-Richtlinie(n): " + (($hit.displayName) -join '; ')) (Resolve-Status ([bool]$hit) $false)
}
Register 'A-05' 'Graph' {
    $hit = Get-EnabledCA | Where-Object {
        $_.conditions.users.includeRoles -and
        ($_.grantControls.builtInControls -contains 'mfa' -or $_.grantControls.authenticationStrength)
    }
    New-CheckResult ("Admin-MFA-Richtlinie(n): " + (($hit.displayName) -join '; ')) (Resolve-Status ([bool]$hit) $false)
}
Register 'A-06' 'Graph' {
    $hit = Get-EnabledCA | Where-Object {
        ($_.conditions.clientAppTypes -contains 'exchangeActiveSync' -or $_.conditions.clientAppTypes -contains 'other') -and
        ($_.grantControls.builtInControls -contains 'block')
    }
    New-CheckResult ("Legacy-Block-Richtlinie(n): " + (($hit.displayName) -join '; ')) (Resolve-Status ([bool]$hit) $false)
}
Register 'A-07' 'Graph' {
    $hit = Get-EnabledCA | Where-Object { $_.grantControls.builtInControls -contains 'compliantDevice' -or $_.grantControls.builtInControls -contains 'domainJoinedDevice' }
    New-CheckResult ("Geraete-Compliance-Richtlinie(n): " + (($hit.displayName) -join '; ')) (Resolve-Status ([bool]$hit) $false)
}
Register 'A-09' 'Graph' {
    $loc = Get-GraphCollection 'v1.0/identity/conditionalAccess/namedLocations'
    New-CheckResult ("Benannte Standorte: $(@($loc).Count) ($((($loc.displayName) -join ', ')))") (Resolve-Status ($null -ne $loc -and @($loc).Count -gt 0) $false)
}
Register 'A-11' 'Graph' {
    $ro = Get-CAPolicies | Where-Object { $_.state -eq 'enabledForReportingButNotEnforced' }
    New-CheckResult ("Report-only-Richtlinien: $(@($ro).Count)") 'Teilweise'
}
Register 'A-12' 'Graph' {
    $mgd = Get-CAPolicies | Where-Object { $_.templateId }
    New-CheckResult ("Microsoft-managed/Template-CA-Richtlinien: $(@($mgd).Count). Bewusste Sichtung dokumentieren.") 'Teilweise'
}
Register 'A-16' 'Graph' {
    $domains = Get-Cached 'domains' { Get-GraphCollection 'v1.0/domains' }
    $bad = $domains | Where-Object { $_.passwordValidityPeriodInDays -and $_.passwordValidityPeriodInDays -lt 100000 }
    $ok = -not $bad
    New-CheckResult ("Domaenen mit Ablauf < 'nie': " + (($bad.id) -join ', ')) (Resolve-Status $ok $false)
}
Register 'A-17' 'Graph' {
    $ap = Get-Cached 'authpol' { Invoke-Graph 'v1.0/policies/authorizationPolicy' }
    New-CheckResult ("allowInvitesFrom = $($ap.allowInvitesFrom)") (Resolve-Status ($ap.allowInvitesFrom -in @('adminsAndGuestInviters','none')) ($ap.allowInvitesFrom -eq 'adminsGuestInvitersAndAllMembers'))
}
Register 'A-18' 'Graph' {
    $ap = Get-Cached 'authpol' { Invoke-Graph 'v1.0/policies/authorizationPolicy' }
    $assigned = @($ap.defaultUserRolePermissions.permissionGrantPoliciesAssigned) -join ', '
    New-CheckResult ("Zugewiesene User-Consent-Policies: $assigned") (Resolve-Status ($assigned -notmatch 'ManagePermissionGrantsForSelf.microsoft-user-default-legacy') $false)
}
Register 'A-19' 'Graph' {
    $ap = Get-Cached 'authpol' { Invoke-Graph 'v1.0/policies/authorizationPolicy' }
    $apps = $ap.defaultUserRolePermissions.allowedToCreateApps
    $tenants = $ap.defaultUserRolePermissions.allowedToCreateTenants
    New-CheckResult ("allowedToCreateApps=$apps; allowedToCreateTenants=$tenants") (Resolve-Status ((-not $apps) -and (-not $tenants)) ((-not $apps) -or (-not $tenants)))
}
Register 'A-13' 'Graph' { New-CheckResult 'In Business Premium NICHT enthalten (Entra ID P2 / Defender-Suite-Add-on erforderlich).' 'n.a.' }

# ---------------- B Intune (ueberwiegend Vorhandensein/Anzahl) ----------------
function Get-IntuneConfigPolicies { Get-Cached 'intuneCfg' { Get-GraphCollection 'beta/deviceManagement/configurationPolicies' } }

# ---- Settings-Catalog-Auslesung (Wert-Prüfung) ----
function ValTail { param($v)
    if ($null -eq $v) { return 'n/a' }
    if ($v -is [System.Array]) { return (($v | ForEach-Object { ($_ -split '_')[-1] }) -join ',') }
    return (($v -split '_')[-1])
}
function Add-SettingInstance { param($inst, $map)
    if (-not $inst) { return }
    $defId = $inst.settingDefinitionId
    $names = $inst.PSObject.Properties.Name
    if (($names -contains 'choiceSettingValue') -and $inst.choiceSettingValue) {
        if ($defId) { $map[$defId] = $inst.choiceSettingValue.value }
        foreach ($c in @($inst.choiceSettingValue.children)) { Add-SettingInstance $c $map }
    }
    elseif (($names -contains 'simpleSettingValue') -and $inst.simpleSettingValue) {
        if ($defId) { $map[$defId] = $inst.simpleSettingValue.value }
    }
    elseif ($names -contains 'choiceSettingCollectionValue') {
        foreach ($v in @($inst.choiceSettingCollectionValue)) {
            if ($defId) { if ($map.ContainsKey($defId)) { $map[$defId] = @($map[$defId]) + $v.value } else { $map[$defId] = @($v.value) } }
            foreach ($c in @($v.children)) { Add-SettingInstance $c $map }
        }
    }
    elseif ($names -contains 'groupSettingCollectionValue') {
        foreach ($g in @($inst.groupSettingCollectionValue)) {
            foreach ($c in @($g.children)) { Add-SettingInstance $c $map }
        }
    }
    elseif ($names -contains 'simpleSettingCollectionValue') {
        if ($defId) { $map[$defId] = @($inst.simpleSettingCollectionValue.value) }
    }
}
function Get-CPSettingsMap { param($id)
    Get-Cached "cpset_$id" {
        $m = @{}
        try {
            $settings = Get-GraphCollection "beta/deviceManagement/configurationPolicies/$id/settings"
            foreach ($s in $settings) { Add-SettingInstance $s.settingInstance $m }
        } catch {}
        $m
    }
}
function Get-MergedSettings { param($policies)
    $m = @{}
    foreach ($p in @($policies)) {
        $pm = Get-CPSettingsMap $p.id
        foreach ($k in $pm.Keys) { $m[$k] = $pm[$k] }
    }
    $m
}
function Get-SettingValue { param($map, $pattern)
    foreach ($k in $map.Keys) { if ($k -like $pattern) { return $map[$k] } }
    return $null
}
function Get-CPByFamily { param($family, $nameRegex)
    $all = Get-IntuneConfigPolicies
    $hit = $all | Where-Object { $_.templateReference -and $_.templateReference.templateFamily -eq $family }
    if (-not $hit -and $nameRegex) { $hit = $all | Where-Object { $_.name -match $nameRegex } }
    @($hit | Where-Object { $_ })
}
Register 'B-01' 'Graph' {
    $m = Get-GraphCollection 'beta/policies/mobileDeviceManagementPolicies'
    $win = $m | Where-Object { $_.displayName -match 'Microsoft Intune' -and $_.displayName -notmatch 'Enrollment' }
    if (-not $win) { $win = $m | Where-Object { $_.displayName -match 'Microsoft Intune' } }
    $scope = ($win | Select-Object -First 1).appliesTo
    New-CheckResult ("MDM-Autoregistrierung appliesTo = $scope") (Resolve-Status ($scope -eq 'all') ($scope -eq 'selected'))
}
Register 'B-04' 'Graph' {
    $cp = Get-Cached 'compliance' { Get-GraphCollection 'v1.0/deviceManagement/deviceCompliancePolicies' }
    $win = $cp | Where-Object { $_.'@odata.type' -match 'windows10CompliancePolicy' }
    New-CheckResult ("Windows-Konformitaetsrichtlinien: $(@($win).Count) (gesamt $(@($cp).Count))") (Resolve-Status ([bool]$win) $false)
}
Register 'B-06' 'Graph' {
    $s = Invoke-Graph 'v1.0/deviceManagement/settings'
    New-CheckResult ("secureByDefault = $($s.secureByDefault)") (Resolve-Status ($s.secureByDefault -eq $true) $false)
}
Register 'B-08' 'Graph' {
    $pol = Get-CPByFamily 'endpointSecurityAntivirus' 'Antivirus|Defender'
    if (-not $pol) { return New-CheckResult 'Kein Antivirus-Endpoint-Security-Profil gefunden.' 'Offen' }
    $map = Get-MergedSettings $pol
    $rt = Get-SettingValue $map '*allowrealtimemonitoring*'
    $bm = Get-SettingValue $map '*allowbehaviormonitoring*'
    $cp = Get-SettingValue $map '*allowcloudprotection*'
    if ($null -eq $rt -and $null -eq $bm -and $null -eq $cp) {
        return New-CheckResult ("$(@($pol).Count) AV-Profil(e); Einzelwerte nicht eindeutig lesbar (evtl. Baseline/Intent) - im Profil pruefen.") 'Teilweise'
    }
    $on = ("$rt" -match '_1$')
    New-CheckResult ("Echtzeitschutz=$(ValTail $rt); Verhaltensueberwachung=$(ValTail $bm); Cloud=$(ValTail $cp) (1=Ein)") (Resolve-Status $on $true)
}
Register 'B-16' 'Graph' {
    $pol = Get-CPByFamily 'endpointSecurityAttackSurfaceReduction' 'ASR|Angriffs|Attack Surface'
    if (-not $pol) { return New-CheckResult 'Kein ASR-Profil gefunden.' 'Offen' }
    $map = Get-MergedSettings $pol
    $rules = @(); foreach ($k in $map.Keys) { if ($k -like '*asr*' -or $k -like '*attacksurfacereductionrules*') { $rules += ,@($k, $map[$k]) } }
    if ($rules.Count -eq 0) { return New-CheckResult ("$(@($pol).Count) ASR-Profil(e); Regelwerte nicht eindeutig lesbar - im Profil pruefen.") 'Teilweise' }
    $block = @($rules | Where-Object { "$($_[1])" -match 'block|_1$' }).Count
    New-CheckResult ("ASR-Regeln gesetzt: $($rules.Count), davon Block: $block") (Resolve-Status ($block -ge 8) ($block -gt 0))
}
Register 'B-18' 'Graph' {
    $pol = Get-CPByFamily 'endpointSecurityFirewall' 'Firewall'
    if (-not $pol) { return New-CheckResult 'Kein Firewall-Profil gefunden.' 'Offen' }
    $map = Get-MergedSettings $pol
    $en = @(); foreach ($k in $map.Keys) { if ($k -like '*enablefirewall*') { $en += $map[$k] } }
    if ($en.Count -eq 0) { return New-CheckResult ("$(@($pol).Count) Firewall-Profil(e); EnableFirewall nicht eindeutig lesbar - im Profil pruefen.") 'Teilweise' }
    $on = @($en | Where-Object { "$_" -match '_1$|true' }).Count
    New-CheckResult ("EnableFirewall je Profil (Ein): $on/$($en.Count) [$(@($en | ForEach-Object { ValTail $_ }) -join ', ')]") (Resolve-Status ($on -eq $en.Count) ($on -gt 0))
}
Register 'B-19' 'Graph' {
    $pol = Get-CPByFamily 'endpointSecurityFirewall' 'Firewall'
    if (-not $pol) { return New-CheckResult 'Kein Firewall-Profil gefunden.' 'Offen' }
    $map = Get-MergedSettings $pol
    $in = @(); foreach ($k in $map.Keys) { if ($k -like '*defaultinboundaction*') { $in += $map[$k] } }
    if ($in.Count -eq 0) { return New-CheckResult 'DefaultInboundAction nicht eindeutig lesbar - im Profil pruefen.' 'Teilweise' }
    $block = @($in | Where-Object { "$_" -match '_1$|block' }).Count
    New-CheckResult ("DefaultInboundAction: $(@($in | ForEach-Object { ValTail $_ }) -join ', '); Block: $block/$($in.Count) (1=Block)") (Resolve-Status ($block -eq $in.Count) ($block -gt 0))
}
Register 'B-21' 'Graph' {
    $pol = Get-CPByFamily 'endpointSecurityDiskEncryption' 'BitLocker|Disk Encryption|Verschluess|Encryption'
    if (-not $pol) { return New-CheckResult 'Kein Datentraegerverschluesselungs-Profil gefunden.' 'Offen' }
    $map = Get-MergedSettings $pol
    $enc = @(); foreach ($k in $map.Keys) { if ($k -like '*encryptionmethod*') { $enc += $map[$k] } }
    if ($enc.Count -eq 0) { return New-CheckResult ("$(@($pol).Count) Profil(e); Verschluesselungsmethode nicht eindeutig lesbar - im Profil pruefen.") 'Teilweise' }
    $xts = @($enc | Where-Object { "$_" -match 'xtsaes256|256' }).Count
    New-CheckResult ("Verschluesselungsmethode(n): $(@($enc | ForEach-Object { ValTail $_ }) -join ', '); XTS-AES-256: $xts/$($enc.Count)") (Resolve-Status ($xts -ge 1) $true)
}
Register 'B-26' 'Graph' { New-CheckResult 'Credential Guard: Lizenzberechtigung (Windows Enterprise/Education) manuell pruefen - bei reiner Business Premium i. d. R. n.a.' 'n.a.' }
Register 'B-33' 'Graph' {
    try {
        $mde = Invoke-Graph 'v1.0/deviceManagement/microsoftDefenderForEndpointSettings' 2>$null
    } catch { $mde = $null }
    if ($null -ne $mde) {
        $mdeState = if ($mde.PSObject.Properties.Name -contains 'onboardingState' -and $mde.onboardingState) { $mde.onboardingState } else { $mde.microsoftDefenderForEndpointAttachEnabled }
        New-CheckResult ("MDE-Connectorstatus: $mdeState") 'Teilweise'
    } else {
        New-CheckResult 'MDE-Connector: Status im Portal (Endpunkte > Erweiterte Funktionen) verifizieren.' 'Teilweise'
    }
}

# ---------------- C Defender (E-Mail per EXO) ----------------
Register 'C-10' 'EXO' {
    $eop = Get-EOPProtectionPolicyRule -ErrorAction SilentlyContinue
    $atp = Get-ATPProtectionPolicyRule -ErrorAction SilentlyContinue
    $states = @()
    if ($eop) { $states += "EOP-Preset: $($eop.State)" }
    if ($atp) { $states += "ATP-Preset: $($atp.State)" }
    if (-not $states) { $states = @('Keine Preset-Regeln gefunden') }
    $on = ($eop.State -eq 'Enabled') -or ($atp.State -eq 'Enabled')
    New-CheckResult ($states -join ' | ') (Resolve-Status $on $false)
}
Register 'C-12' 'EXO' {
    $p = Get-SafeAttachmentPolicy -ErrorAction SilentlyContinue
    $on = $p | Where-Object { $_.Enable -eq $true }
    New-CheckResult ("Safe-Attachment-Policies aktiv: $(@($on).Count)/$(@($p).Count); Aktionen: $((($p.Action) | Select-Object -Unique) -join ', ')") (Resolve-Status ([bool]$on) $false)
}
Register 'C-13' 'EXO' {
    $p = Get-SafeLinksPolicy -ErrorAction SilentlyContinue
    $on = $p | Where-Object { $_.EnableSafeLinksForEmail -eq $true -or $_.IsEnabled -eq $true }
    New-CheckResult ("Safe-Links-Policies: $(@($p).Count), davon aktiv: $(@($on).Count)") (Resolve-Status ([bool]$on) $false)
}
Register 'C-14' 'EXO' {
    $p = Get-AntiPhishPolicy -ErrorAction SilentlyContinue
    $spoof = $p | Where-Object { $_.EnableSpoofIntelligence -eq $true }
    $imp = $p | Where-Object { $_.EnableTargetedUserProtection -eq $true -or $_.EnableTargetedDomainsProtection -eq $true -or $_.EnableOrganizationDomainsProtection -eq $true }
    $ok = ((@($spoof).Count) -eq (@($p).Count)) -and ((@($p).Count) -gt 0)
    New-CheckResult ("Spoof-Intelligence aktiv: $(@($spoof).Count)/$(@($p).Count); Impersonation-Schutz konfiguriert in: $(@($imp).Count) Policies") (Resolve-Status $ok ([bool]$spoof))
}
Register 'C-15' 'EXO' {
    $p = Get-AntiPhishPolicy -ErrorAction SilentlyContinue
    $on = $p | Where-Object { $_.EnableMailboxIntelligence -eq $true }
    New-CheckResult ("Mailbox-Intelligence aktiv in: $(@($on).Count)/$(@($p).Count) Policies") (Resolve-Status ([bool]$on) $false)
}
Register 'C-16' 'EXO' {
    $p = Get-HostedContentFilterPolicy -ErrorAction SilentlyContinue
    $detail = ($p | ForEach-Object { "{0}: HCSpam={1}, Phish={2}, HCPhish={3}, Bulk-Thr={4}" -f $_.Identity, $_.HighConfidenceSpamAction, $_.PhishSpamAction, $_.HighConfidencePhishAction, $_.BulkThreshold }) -join ' | '
    $good = $p | Where-Object { $_.HighConfidencePhishAction -match 'Quarantine' -and $_.PhishSpamAction -match 'Quarantine' }
    $ok = ((@($good).Count) -eq (@($p).Count)) -and ((@($p).Count) -gt 0)
    New-CheckResult $detail (Resolve-Status $ok ([bool]$good))
}
Register 'C-17' 'EXO' {
    $p = Get-MalwareFilterPolicy -ErrorAction SilentlyContinue
    $on = $p | Where-Object { $_.EnableFileFilter -eq $true }
    New-CheckResult ("Common Attachment Filter aktiv in: $(@($on).Count)/$(@($p).Count)") (Resolve-Status ([bool]$on) $false)
}
Register 'C-18' 'EXO' {
    $a = Get-AtpPolicyForO365 -ErrorAction SilentlyContinue
    New-CheckResult ("EnableATPForSPOTeamsODB = $($a.EnableATPForSPOTeamsODB)") (Resolve-Status ($a.EnableATPForSPOTeamsODB -eq $true) $false)
}
Register 'C-19' 'EXO' {
    $p = Get-HostedOutboundSpamFilterPolicy -ErrorAction SilentlyContinue
    $modes = ($p.AutoForwardingMode | Select-Object -Unique) -join ', '
    $blocked = -not ($p | Where-Object { $_.AutoForwardingMode -eq 'On' })
    New-CheckResult ("Outbound AutoForwardingMode: $modes") (Resolve-Status $blocked $false)
}
Register 'C-20' 'EXO' {
    $c = Get-HostedConnectionFilterPolicy -ErrorAction SilentlyContinue
    New-CheckResult ("IPAllowList-Eintraege: $(@($c.IPAllowList).Count); EnableSafeList=$($c.EnableSafeList)") 'Teilweise'
}
Register 'C-21' 'EXO' {
    $p = Get-HostedContentFilterPolicy -ErrorAction SilentlyContinue
    $on = $p | Where-Object { $_.PhishZapEnabled -eq $true -and $_.SpamZapEnabled -eq $true }
    New-CheckResult ("ZAP (Phish & Spam) aktiv in: $(@($on).Count)/$(@($p).Count)") (Resolve-Status ([bool]$on) $false)
}
Register 'C-22' 'EXO' {
    $q = Get-QuarantinePolicy -ErrorAction SilentlyContinue
    New-CheckResult ("Quarantaene-Richtlinien: $(@($q).Count)") (Resolve-Status ((@($q).Count) -gt 0) $false)
}
Register 'C-23' 'EXO' {
    $r = Get-ReportSubmissionPolicy -ErrorAction SilentlyContinue
    New-CheckResult ("Report-Submission aktiv: EnableReportToMicrosoft=$($r.EnableReportToMicrosoft)") (Resolve-Status ([bool]$r) $false)
}

# ---------------- D Purview / Exchange / DNS ----------------
Register 'D-01' 'EXO' {
    $c = Get-AdminAuditLogConfig -ErrorAction SilentlyContinue
    New-CheckResult ("UnifiedAuditLogIngestionEnabled = $($c.UnifiedAuditLogIngestionEnabled)") (Resolve-Status ($c.UnifiedAuditLogIngestionEnabled -eq $true) $false)
}
Register 'D-02' 'EXO' {
    $o = Get-Cached 'orgconfig' { Get-OrganizationConfig }
    New-CheckResult ("AuditDisabled = $($o.AuditDisabled) (False = Auditing aktiv)") (Resolve-Status ($o.AuditDisabled -eq $false) $false)
}
Register 'D-03' 'EXO' {
    $t = Get-TransportConfig -ErrorAction SilentlyContinue
    New-CheckResult ("SmtpClientAuthenticationDisabled (Tenant) = $($t.SmtpClientAuthenticationDisabled)") (Resolve-Status ($t.SmtpClientAuthenticationDisabled -eq $true) $false)
}
Register 'D-04' 'EXO' {
    $p = Get-HostedOutboundSpamFilterPolicy -ErrorAction SilentlyContinue
    $blocked = -not ($p | Where-Object { $_.AutoForwardingMode -eq 'On' })
    New-CheckResult ("Outbound AutoForwardingMode: $((($p.AutoForwardingMode) | Select-Object -Unique) -join ', ')") (Resolve-Status $blocked $false)
}
Register 'D-06' 'EXO' {
    $e = Get-ExternalInOutlook -ErrorAction SilentlyContinue
    New-CheckResult ("External Sender Identification Enabled = $($e.Enabled)") (Resolve-Status ($e.Enabled -eq $true) $false)
}
Register 'D-08' 'DNS' {
    $doms = Get-AssessDomains
    if (-not $doms) { return New-CheckResult 'Keine (nicht-onmicrosoft) Domaenen ermittelt - ggf. -Domains angeben.' 'Teilweise' }
    $lines = foreach ($d in $doms) {
        $txt = (Resolve-DnsName -Type TXT -Name $d -ErrorAction SilentlyContinue).Strings -join ' '
        "{0}: {1}" -f $d, ($(if($txt -match 'v=spf1'){'SPF vorhanden'}else{'KEIN SPF'}))
    }
    $ok = -not [bool]($lines -match 'KEIN SPF')
    $partial = [bool]($lines -match 'SPF vorhanden')
    New-CheckResult (($lines -join ' | ')) (Resolve-Status $ok $partial)
}
Register 'D-09' 'EXO' {
    $d = Get-DkimSigningConfig -ErrorAction SilentlyContinue
    $on = $d | Where-Object { $_.Enabled -eq $true }
    New-CheckResult ("DKIM aktiviert fuer: " + (($on.Domain) -join ', ') + " ($(@($on).Count)/$(@($d).Count))") (Resolve-Status ((@($on).Count) -eq (@($d).Count) -and (@($d).Count) -gt 0) ([bool]$on))
}
Register 'D-10' 'DNS' {
    $doms = Get-AssessDomains
    if (-not $doms) { return New-CheckResult 'Keine (nicht-onmicrosoft) Domaenen ermittelt - ggf. -Domains angeben.' 'Teilweise' }
    $lines = foreach ($d in $doms) {
        $rec = (Resolve-DnsName -Type TXT -Name "_dmarc.$d" -ErrorAction SilentlyContinue).Strings -join ' '
        $pol = if ($rec -match 'p=(none|quarantine|reject)') { $Matches[1] } else { 'KEIN DMARC' }
        "{0}: p={1}" -f $d, $pol
    }
    $ok = (-not [bool]($lines -match 'KEIN DMARC')) -and (-not [bool]($lines -match 'p=none'))
    $partial = [bool]($lines -match 'p=none')
    New-CheckResult (($lines -join ' | ')) (Resolve-Status $ok $partial)
}
Register 'D-11' 'Graph' {
    $s = Get-Cached 'spo' { Invoke-Graph 'v1.0/admin/sharepoint/settings' }
    New-CheckResult ("SharingCapability = $($s.sharingCapability); DomainRestrictionMode = $($s.sharingDomainRestrictionMode)") (Resolve-Status ($s.sharingCapability -in @('disabled','existingExternalUserSharingOnly')) ($s.sharingCapability -eq 'externalUserSharingOnly'))
}
Register 'D-12' 'Graph' {
    $s = Get-Cached 'spo' { Invoke-Graph 'v1.0/admin/sharepoint/settings' }
    New-CheckResult ("SharingCapability = $($s.sharingCapability); DomainRestrictionMode = $($s.sharingDomainRestrictionMode)") 'Teilweise'
}
Register 'D-16' 'SCC' {
    $l = Get-Label -ErrorAction SilentlyContinue
    New-CheckResult ("Vertraulichkeitsbezeichnungen: $(@($l).Count)") (Resolve-Status ((@($l).Count) -gt 0) $false)
}
Register 'D-17' 'SCC' {
    $p = Get-DlpCompliancePolicy -ErrorAction SilentlyContinue
    New-CheckResult ("DLP-Richtlinien: $(@($p).Count)") (Resolve-Status ((@($p).Count) -gt 0) $false)
}
Register 'D-18' 'SCC' {
    $p = Get-RetentionCompliancePolicy -ErrorAction SilentlyContinue
    New-CheckResult ("Aufbewahrungsrichtlinien: $(@($p).Count)") (Resolve-Status ((@($p).Count) -gt 0) $false)
}

# ------------------------------------------------------------------ Domaenen fuer DNS
function Get-AssessDomains {
    Get-Cached 'assessDomains' {
        if ($Domains) { return $Domains }
        if ($script:Connected.EXO) {
            try { return (Get-AcceptedDomain | Where-Object { $_.DomainName -notlike '*.onmicrosoft.com' }).DomainName } catch {}
        }
        @()
    }
}

# ==================================================================
#  HAUPTLAUF
# ==================================================================
Assert-Modules

if (-not (Test-Path $ChecklistPath)) { throw "Checkliste nicht gefunden: $ChecklistPath" }
$__item = Get-Item -LiteralPath $ChecklistPath
if ($__item.PSIsContainer) {
    throw "-ChecklistPath zeigt auf einen Ordner ('$ChecklistPath'). Bitte den vollstaendigen Pfad zur .xlsx-Datei angeben, z. B. '$ChecklistPath\M365_BusinessPremium_Sicherheit_Checkliste_v1.2.xlsx'."
}
if ($__item.Extension -ne '.xlsx') {
    throw "-ChecklistPath muss auf eine .xlsx-Datei zeigen (aktuell: '$($__item.Extension)')."
}
if ($InPlace) {
    $OutputPath = $ChecklistPath
} elseif (-not $OutputPath) {
    $dir  = Split-Path -Parent (Resolve-Path $ChecklistPath)
    $base = [IO.Path]::GetFileNameWithoutExtension($ChecklistPath)
    $OutputPath = Join-Path $dir ("{0}_ausgewertet_{1}.xlsx" -f $base, (Get-Date -Format 'yyyyMMdd-HHmm'))
    Copy-Item $ChecklistPath $OutputPath -Force
}

Write-Host "`nVerbinde mit den Portalen ..." -ForegroundColor Cyan
Connect-Engines

$stamp = Get-Date -Format 'yyyy-MM-dd HH:mm'
Write-Host "`nFuehre Checks aus ..." -ForegroundColor Cyan
$results = @{}
foreach ($nr in $Checks.Keys) {
    $def = $Checks[$nr]
    if (-not $script:Connected[$def.Engine]) {
        $reason = if ($def.Engine -eq 'DNS') { 'DNS nicht verfuegbar' } else { "$($def.Engine) nicht verbunden" }
        $results[$nr] = New-CheckResult "[Auto $stamp] $reason - manuell pruefen." $null
        continue
    }
    try {
        $res = & $def.Run
        $res.Ist = "[Auto $stamp] " + $res.Ist
        $results[$nr] = $res
        $col = switch ($res.Status) { 'Erledigt' {'Green'} 'Teilweise' {'Yellow'} 'Offen' {'Red'} default {'Gray'} }
        $statusText = if ($res.Status) { $res.Status } else { '-' }
        Write-Host ("  {0,-5} {1,-9} {2}" -f $nr, $statusText, $res.Ist) -ForegroundColor $col
    } catch {
        $results[$nr] = New-CheckResult "[Auto $stamp] Fehler beim Lesen: $($_.Exception.Message)" $null
        Write-Host ("  {0,-5} FEHLER   {1}" -f $nr, $_.Exception.Message) -ForegroundColor Magenta
    }
}

# ------------------------------------------------------------------ Rueckschreiben in Excel
Write-Host "`nSchreibe Ergebnisse in: $OutputPath" -ForegroundColor Cyan
$pkg = Open-ExcelPackage -Path $OutputPath
$ws  = $pkg.Workbook.Worksheets['Checkliste']
if (-not $ws) { Close-ExcelPackage $pkg -NoSave; throw "Blatt 'Checkliste' nicht gefunden." }
$COL_IST = 8; $COL_STATUS = 9
$written = 0; $autoNoStatus = 0; $marked = 0
$nrPattern = '^[0-9A-E]-\d{2}$'
for ($r = 1; $r -le $ws.Dimension.End.Row; $r++) {
    $nr = [string]$ws.Cells[$r, 1].Value
    if ($nr -notmatch $nrPattern) { continue }   # Kopf-/Sektionszeilen ueberspringen
    if ($results.ContainsKey($nr)) {
        # Automatisch geprueft
        $res = $results[$nr]
        $ws.Cells[$r, $COL_IST].Value = $res.Ist
        if ($res.Status) { $ws.Cells[$r, $COL_STATUS].Value = $res.Status; $written++ } else { $autoNoStatus++ }
    }
    else {
        # Kein automatischer Check vorhanden -> explizit vermerken,
        # aber manuell eingetragene Ist-Werte NICHT ueberschreiben
        $cur = [string]$ws.Cells[$r, $COL_IST].Value
        if ([string]::IsNullOrWhiteSpace($cur) -or $cur.StartsWith('[Auto')) {
            $ws.Cells[$r, $COL_IST].Value = "[Auto $stamp] Kein automatischer Check - manuell zu pruefen (siehe Blatt 'Auslese-Mapping')."
            $marked++
        }
    }
}
Close-ExcelPackage $pkg

# ------------------------------------------------------------------ Zusammenfassung
$byStatus = $results.Values | Group-Object Status | Sort-Object Name
Write-Host "`n===== Zusammenfassung =====" -ForegroundColor Cyan
Write-Host ("Checks ausgefuehrt      : {0}" -f $results.Count)
Write-Host ("Status automatisch gesetzt: {0}" -f $written)
Write-Host ("Auto, ohne Status         : {0}" -f $autoNoStatus)
Write-Host ("Manuell-Felder markiert   : {0}" -f $marked)
foreach ($g in $byStatus) { $gname = if ($g.Name) { $g.Name } else { 'manuell/-' }; Write-Host ("  {0,-10} {1}" -f $gname, $g.Count) }
Write-Host ("`nFertig. Datei: {0}" -f $OutputPath) -ForegroundColor Green

# Verbindungen trennen
try { if ($script:Connected.Graph) { Disconnect-MgGraph -ErrorAction SilentlyContinue -WarningAction SilentlyContinue 3>$null | Out-Null } } catch {}
try { if ($script:Connected.EXO -or $script:Connected.SCC) { Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue } } catch {}
