# DMployee

Android-App als Hilfstool für Dungeon Master. Ziel: Reibung aus Pen-&-Paper-Sessions nehmen, damit Runden schnell laufen und die Regeln im Hintergrund bleiben.

- Regelsystem: D&D 5e (SRD), später erweiterbar
- Nur für den DM, offline-first
- Sync (Google) ist für später vorgesehen

## Status

In Entwicklung. Stand Zero: leeres Flutter-Grundgerüst, noch keine Funktionen.

## Geplante Module

| Modul | Beschreibung |
|---|---|
| Würfler | Alle gängigen Würfel, Modifier, Vorteil/Nachteil, Saving Throws |
| Kampf-Engine | Initiative-Tracker, Angriff, Treffer, Schaden, Zustände, Buffs |
| Charaktere | Attribute, HP, AC, Klasse, Zauberslots, Ausrüstung |
| Compendium | Zauber, Items, Monster aus gebundelter SRD-Datenbank |
| Session-View | Aktive Charaktere und Encounter in einer Übersicht |

Reihenfolge: Würfler, dann Kampf-Engine, danach der Rest.

## Technik

- Flutter / Dart, Android-first
- SQLite über `sqflite`
- SRD-Daten lokal gebundelt, keine API-Abhängigkeit

## Entwicklung

Voraussetzungen: Flutter SDK (stable), Android SDK, JDK 21.

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

## Tests

Das Projekt wird testgetrieben entwickelt: erst der Test, dann die Implementierung.

- Tests liegen unter `test/` und spiegeln die Struktur von `lib/`
- Testbeschreibungen sind deutsche Sätze, die das erwartete Verhalten benennen
- `flutter test` führt alle Tests aus

## Lizenz

Noch nicht festgelegt.
