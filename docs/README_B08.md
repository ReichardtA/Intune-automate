# B-08 Vertikale — Architektur-Nachweis

Diese Mini-Projektmappe zeigt die komplette „Vertikale" für **einen** Kontrollpunkt
(**B-08 – Defender Antivirus: Echtzeitschutz**) und beweist, dass das Konzept aus dem
Konzeptpapier trägt: **Katalog-Datensatz (Daten) → geprüftes Snippet → erzeugtes, sicheres
PowerShell-Skript**.

## Inhalt

```
hardening-generator/
  catalog/
    B-08_defender-av-realtime.json   # der Katalog-Datensatz (die "Daten")
    catalog.schema.json              # JSON-Schema fuer alle kuenftigen Eintraege
  generated-example/
    Set-M365Hardening_B-08.ps1       # das Skript, das die App fuer B-08 ausgeben wuerde
  README_B08.md                      # dieses Dokument
```

## Daten → Skript: die Abbildung

Jedes Feld des erzeugten Skripts stammt aus dem Katalog-Datensatz. Der Generator (später die
WPF-App) füllt nur noch Platzhalter wie `{{timestamp}}`.

| Katalog-Feld | Wirkung im erzeugten Skript |
|---|---|
| `naming.policyName` | Name des Profils (`4S-Defender-AV-Baseline`) + „aktualisieren statt doppelt anlegen" |
| `requiredScopes` | `Connect-MgGraph -Scopes …` (Least Privilege – nur was B-08 braucht) |
| `graph.resource` + `graph.createBody` | der POST-Payload (unten 1:1 verifiziert) |
| `graph.readback` | die read-only **Vorschau** (Ist → Soll) |
| `safeMode.assignment = unassigned` | Profil wird **ohne Zuweisung** erzeugt |
| `revert.strategy = restoreFromBackup` | Backup vor Änderung + `-Mode Revert` |
| `riskClass = A` | normal wählbar (bei B wäre nur die sichere Form wählbar, bei C gesperrt) |

## Das erzeugte Skript

Drei Modi, **sicher per Default**:

- `-Mode Preview` (Standard) — **liest nur**, zeigt Ist-Wert vs. Soll-Wert, ändert nichts.
- `-Mode Apply` — sichert ein bestehendes Profil als JSON, ersetzt es sauber (kein Duplikat),
  legt das Profil **unassigned** an.
- `-Mode Revert` — stellt aus dem jüngsten Backup den vorigen Zustand wieder her (bzw. löscht,
  wenn vorher keins existierte).

Eingebaute Leitplanken:
- **Break-Glass-Sperre:** `-BreakGlassUpn` übergeben; meldet sich ein solches Konto an, bricht
  das Skript ab.
- **Unassigned:** es werden nie Zuweisungen gesetzt — scharfer Rollout bleibt manuell.
- **Backup + Revert** bei jedem `Apply`.
- Least-Privilege-Scope (`DeviceManagementConfiguration.ReadWrite.All`).

### Ausführen (Beispiele)

```powershell
# 1) Nur ansehen, was passieren würde (schreibt nichts):
.\Set-M365Hardening_B-08.ps1 -BreakGlassUpn "break.glass@kunde.onmicrosoft.com"

# 2) Anwenden (legt das Profil unassigned an, mit Backup):
.\Set-M365Hardening_B-08.ps1 -Mode Apply -BreakGlassUpn "break.glass@kunde.onmicrosoft.com"

# 3) Zurückrollen:
.\Set-M365Hardening_B-08.ps1 -Mode Revert
```

## Vor Produktivnutzung im Test-Tenant verifizieren

Ich konnte hier Syntax und JSON-Serialisierung prüfen, aber **nicht gegen einen echten Tenant**:

- `settingDefinitionId` und Choice-Value (`…allowrealtimemonitoring` / `…_1`) an einem
  Test-Tenant gegenprüfen (Intune → Settings Catalog, Einstellung exportieren).
- `technologies`: `mdm,microsoftSense` erzeugt ein Endpoint-Security-AV-Profil; falls ein reines
  Settings-Catalog-Profil gewünscht ist, auf `mdm` reduzieren.
- Prüfen, ob `Apply` wie erwartet anlegt und die **Assessment-Prüfung B-08** das Profil danach
  als „Erledigt" liest (schließt den Kreis prüfen→setzen→prüfen).

## Klasse B / C – zur Einordnung

- **Klasse B** (z. B. B-16 ASR): gleicher Aufbau, aber `safeMode.mode = audit` und ein
  `ui.warnText`; die scharfe Form ist nicht wählbar.
- **Klasse C** (z. B. CA scharf): `ui.locked = true` → in der Oberfläche ausgegraut, kein Skript
  erzeugbar, nur Hinweis.

## Nächste Schritte

1. **Test-Tenant-Validierung** von B-08 (siehe oben) – danach ist die Vertikale „grün".
2. **WPF-App-Skelett**: Fensterliste der Katalog-Einträge (nach Tier/Workload gruppiert),
   Klasse-B gelb mit Hinweis, Klasse-C ausgegraut, Break-Glass-Eingabe, „Skript erzeugen".
3. **Multi-Setting-Generator**: aus N gewählten Einträgen **ein** Skript bündeln — Scopes
   vereinen, nach Abhängigkeiten ordnen, gemeinsames Backup/Revert, ein Vorschau-Block.
4. Danach die restlichen **A-Einträge der B-Sektion** in den Katalog aufnehmen, dann die
   **B-Klasse** (Audit-Modus).

## Status

Syntax (PowerShell-Parser) geprüft · JSON + Schema valide · `$DesiredBody`→Graph-JSON 1:1
verifiziert · Live-Test im Tenant ausstehend.
