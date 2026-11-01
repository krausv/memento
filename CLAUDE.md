# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Projekt

Memento je nativní macOS menu bar aplikace (SwiftUI + SwiftData, macOS 26+, bez externích závislostí) pro sledování času na úkolech a měsíční PDF výkazy po projektech. Úplné zadání MVP včetně „mimo rozsah“ je v `docs/specs/mvp.md` – před přidáním funkcí si ho přečti. Jazyk UI, komentářů a commitů je čeština.

## Build a testy

Xcode projekt se generuje z `project.yml` přes XcodeGen. `Memento.xcodeproj` a `Memento/Info.plist` jsou v `.gitignore` – needitovat ručně, po změně `project.yml` nebo přidání/odebrání souborů znovu vygenerovat.

```
xcodegen generate
xcodebuild -scheme Memento build
xcodebuild -scheme Memento test
xcodebuild -scheme Memento test -only-testing:MementoTests/ReportBuilderTests/testNazevMetody   # jeden test
```

Lint není nastaven.

## Vydání a aktualizace

- Vydání: `git tag v0.2.0 && git push --tags` spustí `.github/workflows/release.yml` (testy → import Developer ID → `scripts/make-dmg.sh` → podepsané a notarizované `Memento.dmg` přiložené k GitHub Release). Verze aplikace se bere z tagu, číslo buildu z čísla běhu. Potřebné secrety jsou popsané v hlavičce workflow.
- Lokálně: `scripts/make-dmg.sh` (bez Developer ID podepíše ad-hoc; `SIGN_IDENTITY=-` vynutí ad-hoc, `VERSION=0.2.0` přepíše verzi z `project.yml`).
- Aplikace si denně přes GitHub API (`releases/latest`) zjišťuje novější verzi (`Logic/UpdateChecker`, `UpdateStore`) a jen nabídne stažení – položka v pravém menu a Nastavení › Aktualizace. Verze v `Info.plist` jde z `MARKETING_VERSION` v `project.yml`; před vydáním ji tam zvyš, ať lokální buildy nehlásí starší verzi.

## Architektura

- `Models/Models.swift` – SwiftData modely `Project` → `TimeEntry` (cascade mazání) a `Tag` (M:N se záznamem). Žádné úkoly: popis práce je volná `TimeEntry.note`. `TimeEntry.end == nil` znamená běžící záznam.
- `Logic/` – čistá logika oddělená od UI (hlavní testovaná vrstva):
  - `TimerController` (`@MainActor @Observable`) – start/stop/přepnutí; běžící záznam se ukládá hned při startu, takže přežije restart. Čas injektovatelný přes `clock` pro testy.
  - `ReportBuilder` – z záznamů vytvoří čistou strukturu výkazu (hodiny, částky, zaokrouhlení). Záznam patří do měsíce, ve kterém **začal**.
  - `EntryValidator` (konec po začátku, žádné překryvy), `FileNaming` (slug názvu PDF), `Formatting` (`CzFormat`, cs_CZ), `Calendar+Prague` (agregace vždy v Europe/Prague), `AppSettings`.
  - `Budget` – `BudgetStatus` (čerpání limitu hodin projektu), `BudgetMonitor` (periodická kontrola + upozornění, vytváří se jen mimo testy) a tenká vrstva `Notifications`.
  - `Billing` – `Billing.totals` (fakturované částky po měnách, počítané jako ve výkazu; používá obrazovka Záznamy).
  - `Stats` – `StatsBuilder` (agregace pro sekci Přehled; skutečné časy, ne zaokrouhlené jako ve výkazu).
  - `Reminders` – `ReminderPolicy` (čistá funkce: kdy připomenout) a `ReminderScheduler` (minutový tick + probuzení Macu).
  - `Pomodoro` – `PomodoroPolicy` (čistý stavový automat fází práce / krátká / dlouhá pauza) a `PomodoroScheduler` (sekundový tick, vázaný na běžící časovač, oznámení s akcemi). Dva nezávislé režimy: oznámení a vizuální časovač (`Views/PomodoroPanel.swift` – plovoucí `NSPanel` s `SundialDial`; schovává se při fullscreenu jiné aplikace).
  - `Backup` – verzovaný JSON export/import (`BackupService`); při změně modelu zvaž bump `Backup.currentVersion` a doplň DTO. `AutoBackup` – plánovač automatických záloh do zvolené složky (maže jen soubory vzoru `memento-auto-*.json`).
- `PDF/` – `ReportPaginator` rozdělí data na stránky, `ReportPageView` je SwiftUI stránka A4, `PDFExporter` renderuje přes `ImageRenderer` do PDF kontextu. Renderer jen vykresluje hotová data z `ReportBuilder`.
- `Views/` + `MementoApp.swift` – `StatusItemController` (vlastní `NSStatusItem`: levý dvojklik start/stop, levý klik poznámka, pravé tlačítko menu; spravuje i okna přes AppKit, SwiftUI scéna je prázdná) a hlavní okno (projekty, záznamy, export, nastavení). Aplikace je `LSUIElement` (bez ikony v Docku).

## Konvence

- Peníze vždy `Decimal`, nikdy `Double`; zaokrouhlení až na konci z přesného součtu sekund.
- Ukládají se skutečné časy (`Date`); zaokrouhlování z nastavení platí jen ve výpočtu exportu.
- Testy (`MementoTests/`, XCTest) míří na logiku v `Logic/` a `PDF/ReportPaginator`, ne na views.
