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
- Reihenfolge: Würfler, Log, Kampf-Engine, Charaktere (alle begonnen), danach Compendium, Session-View. Aktueller Stand und nächste Schritte stehen im Vault in `02 Projekte/DMployee.md`.
- Logik von UI trennen.
- Nach Änderungen `flutter analyze` und `flutter test` ausführen.

## Log (verbindlich für alle Module)

- Alles, was im Spiel passiert, wird über `LogRepository.add` als `LogEvent` protokolliert (`lib/log/`).
- Ereignisse speichern Fakten, keine Sätze. Texte und Details erzeugt ausschließlich der `LogFormatter`.
- Würfe immer als `RollRecord` ablegen, Modifier immer mit Herkunft (`Modifier('Stärke', 5)`).
- Neuer Ereignistyp: Unterklasse von `LogEvent` in der Bibliothek `lib/log/log_event.dart` (Datei selbst oder `part` wie `lib/log/combat_events.dart`, da `LogEvent` versiegelt ist), Eintrag in `LogEvent.fromJson`, Fall im `LogFormatter`, Tests in `test/log/`.
- Tests nutzen `InMemoryLogRepository`; SQLite-Tests laufen über `sqflite_common_ffi`.
- Emulator: `MAUI_Emulator_API_36` stürzt mit Vulkan ab. Dauerhaft behoben über `~/.android/advancedFeatures.ini` (`Vulkan = off`); diese Datei nicht entfernen.

## Kampf-Engine

- Regeln liegen in `lib/combat/encounter.dart` (`Encounter`), nicht im Bildschirm. `Encounter` schreibt selbst in den Log.
- Es gelten die 5e-Standardregeln des eingestellten Regelwerks (siehe "Regelwerk"). Sonderregeln kommen später; keine Hausregeln einbauen.
- Jeder Wurf muss auch von Hand eintragbar sein (am Tisch gewürfelt) und wird als `RollRecord` mit `manual: true` protokolliert.
- Werte, die im Kampf wiederholt gebraucht werden, werden beim Kämpfer hinterlegt, nicht pro Aktion neu abgefragt.
- Schaden immer über `Encounter._applyDamage` abziehen (Angriff und direkter Schaden nutzen dieselbe Stelle), damit die Regeln für 0 TP greifen: Monster gehen zu Boden, Spielercharaktere (`isPlayer`) machen Todesrettungswürfe.
- Zustände (`lib/combat/condition.dart`), Effekte/Buffs (`lib/combat/buff.dart`) und Resistenzen (`lib/combat/damage.dart`): Die App wendet nur an, was in jeder Lage gilt. Regeln, die von Abstand oder Sicht abhängen, werden als Hinweis angezeigt und von der Spielleitung eingestellt.
- Dauern zählen am Ende des Zugs des betroffenen Kämpfers herunter (`Encounter._endTurn`); neue Dinge mit Dauer dort einhängen.
- Der Kampfstand wird nach jeder Änderung gespeichert (`EncounterStore`, Tabelle `encounter_state`). Änderungen am Kampf deshalb immer über Methoden von `Encounter` machen, nie direkt an `Combatant` aus dem Bildschirm heraus; neue Felder in `toJson`/`fromJson` aufnehmen.

## Charaktere

- Modell in `lib/characters/` (`Character`, `Ability`). Abgeleitete Werte (Modifikatoren, Übungsbonus, Initiative, Rettungswürfe) werden berechnet, nie gespeichert.
- Ein Charakter im Kampf ist mit seinem Kämpfer verknüpft (`Combatant.characterId`). Den Zustand (TP, temporäre TP, Todesrettungswürfe, stabil, tot) schreibt `Encounter._save` zurück; neue Zustandsfelder dort und in `addCharacter` ergänzen.
- Bogenwerte (Name, RK, maximale TP, Angriffe usw.) ändern sich nur über den Charakterbogen; danach `Encounter.applyCharacter` aufrufen. Beim Löschen `Encounter.forgetCharacter`.
- Klasse bleibt Freitext, bis das Compendium die Klassen liefert; der Trefferwürfel (W6 bis W12) wird deshalb auf dem Bogen gewählt. Erschöpfung ist noch offen und kann jetzt je Regelwerk umgesetzt werden.
- Rasten laufen über `RestService` (`lib/characters/rest.dart`), die Regeln je Regelwerk stehen in `lib/rules/rest_rules.dart` (Quellen: SRD 5.1 "Resting", SRD 5.2 Glossar "Short Rest"/"Long Rest"). Keine Rast während eines laufenden Kampfs. Ist der Charakter noch auf der Kampfliste, übernimmt `Encounter.takeCharacterState` den neuen Zustand (kein Log-Eintrag). Was künftig bei einer Rast zurückkommt (Zauberplätze, Fähigkeiten), wird in `RestService.shortRest`/`longRest` eingehängt.

## Regelwerk

- Wählbar in den Einstellungen (`AppSettings.ruleset`, `lib/settings/`), gespeichert in der Tabelle `settings`. Werte in `lib/rules/ruleset.dart` (`Ruleset`), voreingestellt 2014. Ziel: später alle Regelwerke abbilden.
- Regeln, die sich zwischen den Regelwerken unterscheiden, fragen das eingestellte Regelwerk ab, statt eine Fassung fest einzubauen. Jede solche Regel bekommt Tests für jedes Regelwerk.
- Neues Regelwerk: neuer Wert in `Ruleset`; die gespeicherte `id` eines Werts nie ändern.

## Datenbank

- Eine gemeinsame Datenbank `dmployee.db`, geöffnet über `openAppDatabase` (`lib/storage/app_database.dart`). Strukturänderung: Version erhöhen, Schritt in `_upgrade` ergänzen, `_create` auf denselben Endstand bringen, Test in `test/storage/app_database_test.dart`. Vorhandene Daten dürfen dabei nicht verloren gehen.

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
