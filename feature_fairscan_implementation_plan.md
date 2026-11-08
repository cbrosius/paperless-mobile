# Feature Implementation Plan: External Scan-to-PDF Intent (FairScan Integration)

## 1. Kontext & Zielsetzung
Ziel dieses Features ist die Integration des impliziten Android-Intents `org.fairscan.app.action.SCAN_TO_PDF` (eingeführt von **FairScan**) als experimentelle Scan-Option in `paperless-mobile`. 

**Warum dieses Feature?**
* Bietet insbesondere auf Google-freien Android-Systemen (z. B. GrapheneOS) und im `fdroid`-Flavor einen nahtlosen, KI-gestützten In-App-Dokumentenscan ohne Abhängigkeit von den Google Play Services (ML Kit Document Scanner).
* Da der FairScan-Intent aktuell als *experimental* eingestuft ist, wird die Funktion als generischer **"External Scan-to-PDF Intent (Experimental)"** implementiert und über einen Opt-In-Schalter in den App-Einstellungen gesteuert.

## 2. Kritische Architektur-Vorgaben (Agent Constraints)
1. **Ephemeral URI Lifecycle (WICHTIG):** Laut FairScan-Spezifikation hat die zurückgegebene `content://`-URI (`intent.data`) nur eine sehr kurze Lebensdauer und wird von FairScan zeitnah gelöscht. Der native Android-Handler (`MainActivity.kt`) **muss** den `InputStream` der URI **sofort** in `onActivityResult` / `ActivityResultCallback` öffnen und in eine temporäre Datei im internen `cacheDir` von `paperless-mobile` kopieren. An den Flutter/Dart-Layer wird ausschließlich der lokale Dateipfad (`String`) der Kopie übergeben.
2. **Android 11+ Package Visibility:** Damit `packageManager.resolveActivity` prüfen kann, ob FairScan (oder eine kompatible App) installiert ist, muss die Intent-Action zwingend im `<queries>`-Block der `AndroidManifest.xml` deklariert werden.
3. **Plattform-Guard:** Das Feature und die zugehörige UI-Einstellung dürfen nur unter Android (`Platform.isAndroid`) aktiv bzw. sichtbar sein.
4. **FVM & Codegen:** Alle Flutter/Dart-Befehle in dieser Umgebung müssen über `fvm` ausgeführt werden (`fvm flutter ...`, `fvm dart ...`).

---

## 3. Milestones & Arbeitspakete (Work Packages)

### Milestone 1: Codebase-Analyse & Worktree-Setup
- [ ] **WP 1.1: Git Worktree prüfen / anlegen**
  - Sicherstellen, dass auf einem sauberen Feature-Branch (z. B. `feat/external-scan-to-pdf-intent`) basierend auf dem aktuellen `upstream/main` (bzw. dem aktiven Haupt-Entwicklungsbranch) gearbeitet wird.
- [ ] **WP 1.2: Bestehende Scanner- & Settings-Architektur analysieren**
  - Untersuche die bestehende Scanner-Abstraktion (z. B. `DocumentScanner`, Upload-Routing nach Scan-Abschluss).
  - Untersuche die Struktur der App-Einstellungen (State-Management, Persistenz via Hive/SharedPreferences/Cubit, UI-Screen für Settings).
  - Prüfe `android/app/src/main/AndroidManifest.xml` und `MainActivity.kt` auf bestehende `MethodChannel`-Implementierungen und Activity-Basisklassen (`FlutterActivity` vs. `FlutterFragmentActivity`).

---

### Milestone 2: Android Native Layer (`AndroidManifest.xml` & Kotlin Bridge)
- [ ] **WP 2.1: Package Visibility in `AndroidManifest.xml` erweitern**
  - Datei: `android/app/src/main/AndroidManifest.xml`
  - Füge innerhalb des `<queries>`-Elements folgenden Intent-Filter hinzu:
    ```xml
    <intent>
        <action android:name="org.fairscan.app.action.SCAN_TO_PDF" />
    </intent>
    ```
- [ ] **WP 2.2: MethodChannel & ActivityResult-Handling in Kotlin implementieren**
  - Datei: `android/app/src/main/kotlin/.../MainActivity.kt` (oder dedizierter Handler, falls im Projekt üblich).
  - Channel-Name: `de.astubenbord.paperless_mobile/external_scanner` (an bestehendes Namensschema im Projekt anpassen).
  - Methode 1: `isExternalScannerAvailable`
    - Erstellt `Intent("org.fairscan.app.action.SCAN_TO_PDF")`.
    - Prüft via `packageManager.resolveActivity(intent, 0) != null`, ob eine passende App installiert ist, und gibt `Boolean` zurück.
  - Methode 2: `startExternalScan`
    - Speichert das ausstehende `MethodChannel.Result` (Schutz gegen parallele Aufrufe einbauen).
    - Startet `Intent("org.fairscan.app.action.SCAN_TO_PDF")`.
    - Wertet das Ergebnis aus:
      - Bei `Activity.RESULT_CANCELED`: Gibt `null` über `result.success(null)` zurück (regulärer Abbruch durch den Nutzer).
      - Bei `Activity.RESULT_OK`: Liest `data?.data` (URI) aus. Öffnet sofort `contentResolver.openInputStream(uri)` und kopiert die Bytes in eine neue Datei unter ` File(cacheDir, "external_scan_${System.currentTimeMillis()}.pdf")`.
      - Gibt den absoluten Pfad (`tempFile.absolutePath`) via `result.success(path)` an Flutter zurück.
      - Bei Exceptions (z. B. `IOException` oder fehlende URI trotz `RESULT_OK`): Gibt `result.error("SCAN_ERROR", e.message, null)` zurück.

---

### Milestone 3: Dart Service Layer & State Management (Settings)
- [ ] **WP 3.1: Dart Wrapper für den External Scanner erstellen**
  - Erstelle einen Service/Helper (z. B. `ExternalScannerService`), der den `MethodChannel` kapselt:
    - `Future<bool> isAvailable()` (gibt auf Nicht-Android-Plattformen sofort `false` zurück).
    - `Future<File?> scanDocument()` (ruft `startExternalScan` auf und gibt bei einem validen Pfad ein `File`-Objekt zurück, bei Abbruch `null`).
- [ ] **WP 3.2: Persistente Einstellung hinzufügen**
  - Erweitere das Einstellungs-Modell der App um ein neues Feld, z. B. `bool useExternalScanToPdfIntent` (Default: `false`).
  - Falls Code-Generierung (Freezed / JsonSerializable / Hive) für die Settings genutzt wird, führe `fvm dart run build_runner build --delete-conflicting-outputs` aus.
- [ ] **WP 3.3: Fallback-Logik absichern**
  - Wenn `useExternalScanToPdfIntent == true` in den Einstellungen gespeichert ist, der Nutzer FairScan aber zwischenzeitlich deinstalliert hat (`isAvailable() == false`), soll beim Klick auf den Scan-Button entweder sauber auf den Standard-Scanner zurückgefallen oder eine verständliche Fehlermeldung/Snackbar angezeigt werden, statt mit einer unbehandelten Exception abzustürzen.

---

### Milestone 4: UI-Integration, Upload-Flow & Lokalisierung
- [ ] **WP 4.1: Lokalisierung (`l10n`) ergänzen**
  - Dateien: `lib/l10n/app_en.arb` und `lib/l10n/app_de.arb` (sowie ggf. weitere Basis-ARBs).
  - Neue Keys hinzufügen (Namen an Projektkonvention anpassen):
    - Einstellungstitel (EN): `"Use external PDF scanner (Experimental)"`
    - Einstellungstitel (DE): `"Externen PDF-Scanner verwenden (Experimentell)"`
    - Einstellungsbeschreibung (EN): `"Uses the SCAN_TO_PDF intent (e.g., FairScan) to scan documents directly into a PDF."`
    - Einstellungsbeschreibung (DE): `"Nutzt den SCAN_TO_PDF-Intent (z. B. FairScan), um Dokumente direkt als PDF zu scannen."`
    - Hinweis falls keine kompatible App installiert ist (EN): `"No compatible scanner app (such as FairScan) found on this device."`
    - Hinweis falls keine kompatible App installiert ist (DE): `"Keine kompatible Scanner-App (wie FairScan) auf diesem Gerät gefunden."`
  - Sprachdateien generieren: `fvm flutter gen-l10n`
- [ ] **WP 4.2: Settings-UI erweitern**
  - Füge in den Einstellungen (nur unter Android sichtbar) einen `SwitchListTile` für die neue Option hinzu.
  - Prüfe via `isAvailable()`, ob eine App den Intent auflösen kann. Falls `false`, deaktiviere den Switch (`onChanged: null`) oder zeige den entsprechenden Untertitel-Hinweis an, damit der Nutzer sofort erkennt, dass FairScan installiert sein muss.
- [ ] **WP 4.3: Scan-Aktion & Upload-Pipeline verknüpfen**
  - An der Stelle, an der die App den Dokumentenscan startet:
    - Prüfe, ob `Platform.isAndroid && settings.useExternalScanToPdfIntent && await externalScanner.isAvailable()`.
    - Falls ja: Rufe `externalScanner.scanDocument()` auf.
    - Wenn `File?` == `null` (Nutzer hat abgebrochen): Beende die Aktion lautlos ohne Fehlermeldung.
    - Wenn `File` vorhanden: Übergib die PDF-Datei direkt an denselben Upload-Vorbereitungs-Flow (Pre-Upload-Formular mit Dateiname, Titel, Korrespondent, Dokumenttyp, Tags), der auch für empfangene PDF-Dateien oder abgeschlossene Scans genutzt wird.
  - Stelle sicher, dass die temporäre PDF-Datei aus dem `cacheDir` nach erfolgreichem Upload oder Abbruch des Upload-Dialogs aufgeräumt werden kann.

---

### Milestone 5: Automatisierte Tests & Lokale Verifikation (Quality Gate)
- [ ] **WP 5.1: Unit-Tests für den MethodChannel-Service schreiben**
  - Erstelle eine Testdatei unter `test/` für den `ExternalScannerService`.
  - Nutze `TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler`, um folgende Szenarien zu testen:
    1. `isAvailable()` gibt `true` bzw. `false` korrekt weiter.
    2. `scanDocument()` gibt bei einem Pfad-Ergebnis ein valides `File`-Objekt zurück.
    3. `scanDocument()` gibt bei `null` (Abbruch durch Benutzer) sauber `null` zurück.
    4. `scanDocument()` wirft/behandelt eine `PlatformException` kontrolliert, wenn der native Kopiervorgang fehlschlägt.
- [ ] **WP 5.2: Komplette Verifikations-Pipeline ausführen**
  - Führe nacheinander folgende Befehle aus und behebe sämtliche Warnungen oder Fehler:
    ```powershell
    fvm flutter pub get
    fvm flutter gen-l10n
    fvm dart run build_runner build --delete-conflicting-outputs
    fvm dart format --output=none --set-exit-if-changed .
    fvm flutter analyze
    fvm flutter test
    ```

---

## 4. Definition of Done (Abnahmekriterien für den PR)
- [ ] `AndroidManifest.xml` enthält den `<queries>`-Eintrag für `org.fairscan.app.action.SCAN_TO_PDF`.
- [ ] Der Kotlin-Code kopiert die `content://`-URI unmittelbar im Callback in das App-eigene `cacheDir`, bevor das `MethodChannel.Result` aufgelöst wird.
- [ ] Die Einstellung ist als *Experimentell* gekennzeichnet, in Englisch und Deutsch lokalisiert und nur unter Android sichtbar.
- [ ] Ein abgebrochener Scan in FairScan führt zu keiner Fehlermeldung in `paperless-mobile`.
- [ ] Ein abgeschlossener Scan öffnet unmittelbar die Upload-Maske mit der generierten PDF-Datei.
- [ ] `fvm flutter analyze`, `fvm dart format` und `fvm flutter test` laufen mit Exit-Code `0` durch.