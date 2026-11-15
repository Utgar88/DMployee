# DMployee

Android-App als Dungeon-Master-Hilfstool (D&D 5e SRD). DM-only, offline-first, später Google-Sync. Vorgänger "DMHelper" ist verworfen.

## Dokumentation

Alle Dokumentation und das Projektwissen liegen im Obsidian-Vault `/home/dpillich/Dokumente/Documents/Second_Brain`. Dessen `CLAUDE.md` ist bindend, wenn hier dokumentiert wird. Nicht im Code-Ordner dokumentieren.

- Projektstand: `02 Projekte/DMployee.md`
- Tägliche Fortschritte: `97 Daily Notes/YYYY-MM-DD.md`
- Technische Erkenntnisse: `04 Ressourcen/`
- Bei Projektänderungen (erstellt, pausiert, abgeschlossen): `02 Projekte/!Projektübersicht.md` mitsynchronisieren
- Vault auf Deutsch, Code/Funktionen/Variablen auf Englisch. Vor Löschen/Überschreiben im Vault fragen.

## Stack

- Flutter 3.50 / Dart 3.14, Android-first (Plattform: nur android)
- SQLite via `sqflite`, SRD-Daten lokal gebundelt (keine API-Abhängigkeit)
- Package-Name: `dmployee`, Org: `de.dpillich`

## Umgebung (Linux Mint)

- Flutter: `~/development/flutter` (PATH: `export PATH=$HOME/development/flutter/bin:$PATH`)
- Android SDK: `~/Android/Sdk`, JDK 21: `~/Android/jdk/jdk-21`
- Befehle: `flutter analyze`, `flutter test`, `flutter run`

## Arbeitsweise

- Claude führt die Entwicklung, Dirk testet und gibt Feedback.
- Einstieg: Würfler (Kern-Logik zuerst ohne UI), dann Kampf-Engine. Danach Charaktere, Compendium, Session-View.
- Logik von UI trennen.
- Nach Änderungen `flutter analyze` und `flutter test` ausführen.

## Git

- Repo: `git@github.com:Utgar88/DMployee.git`, Branch `main`, Push per SSH.
- Dirk hat dauerhaft freigegeben: nach jedem grünen Schritt (`flutter analyze` und `flutter test` ohne Befund) eigenständig committen und pushen, ohne Rückfrage.
- Nie mit roten Tests committen. Kein Force-Push und kein Umschreiben der Historie ohne Rückfrage.
- Commit-Nachrichten auf Deutsch, kurz, mit dem Was und Warum.

## Testgetriebene Entwicklung (verbindlich)

- Reihenfolge: erst der Test (rot), dann die Implementierung (grün), dann aufräumen. Kein Produktivcode ohne vorher geschriebenen, fehlschlagenden Test.
- Tests sind Teil des Repos und werden mit committet: `test/` spiegelt die Struktur von `lib/` (z.B. `lib/dice/dice_roller.dart` -> `test/dice/dice_roller_test.dart`).
- Tests müssen für Dirk lesbar sein: `group`/`test`-Beschreibungen auf Deutsch als ganze Sätze, die das erwartete Verhalten benennen (z.B. "2W6+3 liefert Werte zwischen 5 und 15"). Code bleibt Englisch.
- Zufall ist injizierbar (`Random` als Parameter), damit Tests deterministisch sind.
- Jedes Modul bekommt im Vault in `02 Projekte/DMployee.md` einen Abschnitt, welche Testdatei welches Verhalten abdeckt.
- Bugfix beginnt immer mit einem Test, der den Fehler reproduziert.
- Wichtige Entscheidungen und Stand nach der Arbeit in den Vault übertragen.
