# M365 Security Assessment – Kurzanleitung

`Invoke-M365SecurityAssessment.ps1` liest die allgemeinen Sicherheitseinstellungen eines
Microsoft-365-Business-Premium-Tenants aus und schreibt **Ist-Wert** und **Status** je
Kontrollpunkt zurück in die Excel-Checkliste (Blatt „Checkliste", Spalten H und I).

**Read-only:** Das Skript verändert nichts im Tenant. Es liest ausschließlich.

## 1. Voraussetzungen

Windows PowerShell 5.1 **oder** PowerShell 7 (unter Windows, wegen `Resolve-DnsName` für
SPF/DMARC). Das Skript ist für beide kompatibel und UTF-8-codiert (mit BOM, damit Umlaute
in 5.1 korrekt sind). Einmalig die Module installieren:

```powershell
Install-Module Microsoft.Graph, ExchangeOnlineManagement, ImportExcel -Scope CurrentUser
```

## 2. Berechtigungen (nur lesend)

- **Graph:** Directory.Read.All, Policy.Read.All, RoleManagement.Read.Directory,
  Organization.Read.All, SecurityEvents.Read.All, DeviceManagementConfiguration.Read.All,
  DeviceManagementManagedDevices.Read.All, SharePointTenantSettings.Read.All, Application.Read.All
- **Exchange Online / Security & Compliance:** Rolle **Global Reader** deckt fast alles ab;
  ergänzend **Security Reader** / **View-Only Configuration**.

Beim ersten interaktiven Lauf fragt Graph die Einwilligung für die Lese-Scopes ab.

## 3. Ausführen

**Ein Tenant, interaktiv** (empfohlen für den Einstieg):

```powershell
.\Invoke-M365SecurityAssessment.ps1 -ChecklistPath .\M365_BusinessPremium_Sicherheit_Checkliste_v1.2.xlsx
```

Es entsteht eine Kopie `..._ausgewertet_<Datum-Uhrzeit>.xlsx` (Original bleibt unverändert).
Mit `-InPlace` wird direkt in die Datei geschrieben.

**MSP / unbeaufsichtigt (app-only)** – nur ein anderer Connect-Block, gleiche Checks:

```powershell
.\Invoke-M365SecurityAssessment.ps1 -ChecklistPath .\Checkliste.xlsx `
    -AppOnly -TenantId contoso.onmicrosoft.com -ClientId <App-ID> -CertificateThumbprint <Thumbprint>
```

Dafür einmalig eine App-Registrierung mit den obigen **Application**-Berechtigungen + Zertifikat
anlegen und Admin-Consent erteilen; für Exchange/IPPS die App als Dienstprinzipal mit
Exchange-Leserolle hinterlegen.

Nützliche Schalter: `-SkipCompliance`, `-SkipExchange`, `-SkipGraph`, `-SkipDns`,
`-Domains contoso.de,contoso.at` (DNS-Domänen manuell vorgeben).

## 4. Was das Skript schreibt

| Spalte | Inhalt |
|---|---|
| **H – Ist-Wert** | Auswertungstext mit Zeitstempel, z. B. `[Auto 2026-09-10 14:05] Security Defaults isEnabled=False; aktive CA-Richtlinien: 6` |
| **I – Status** | `Erledigt` · `Teilweise` · `Offen` · `n.a.` (passt zum vorhandenen Dropdown) |

Spalte **J (Bemerkung)** und alle anderen Blätter bleiben unangetastet.
Am Ende gibt es eine Konsolen-Zusammenfassung (Anzahl je Status).

## 5. Abdeckung

- **53 Kontrollpunkte** werden aktiv geprüft (Entra, EOP/Defender-for-Office, Exchange/Purview,
  DNS und Intune – inkl. echter Wert-Prüfung für AV-Echtzeitschutz, ASR-Block, Firewall und BitLocker
  über den Settings-Catalog).
- Die übrigen Punkte (Sektion E „Betrieb & Nachweisführung", Intune-Detailwerte im Settings-Catalog,
  Defender-Endpoint-Feineinstellungen) markiert das Skript mit einem Hinweis in Spalte H und lässt
  den Status unverändert → **manuell prüfen**.
- Details, welche Nr. wie auslesbar ist, stehen im Excel-Blatt **„Auslese-Mapping"**.

## 6. Erweitern

Ein neuer Check ist ein Eintrag in der Registry im Skript:

```powershell
Register 'B-12' 'Graph' {
    # ... Werte lesen ...
    New-CheckResult "Ist-Wert-Text" (Resolve-Status $ok $partial)
}
```

`Engine` ist `Graph`, `EXO`, `SCC` oder `DNS`. Fehlt zu einer Nr. ein Eintrag, wird sie
automatisch als „manuell prüfen" behandelt. So lässt sich die Abdeckung schrittweise erhöhen,
ohne die Struktur zu ändern.

## 7. Hinweise

- Intune-Settings-Catalog-Profile werden zunächst auf **Vorhandensein/Anzahl** geprüft
  (Status oft `Teilweise`), weil die Einzelwerte tief in den Settings verschachtelt sind – ein
  guter erster Erweiterungspunkt.
- Defender-for-Endpoint-Feineinstellungen (EDR Block Mode, AIR) sind per API nur eingeschränkt
  lesbar; im Zweifel im Portal gegenprüfen.
- Das Skript trennt die Verbindungen (Graph/Exchange) am Ende automatisch.
