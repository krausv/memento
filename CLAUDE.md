# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Projekt

Memento je nativní macOS menu bar aplikace (SwiftUI + SwiftData, macOS 27+, bez externích závislostí) pro sledování času na úkolech a měsíční PDF výkazy po projektech. Úplné zadání MVP včetně „mimo rozsah“ je v `docs/specs/mvp.md` – před přidáním funkcí si ho přečti. Jazyk UI, komentářů a commitů je čeština.

## Build a testy

Xcode projekt se generuje z `project.yml` přes XcodeGen. `Memento.xcodeproj` a `Memento/Info.plist` jsou v `.gitignore` – needitovat ručně, po změně `project.yml` nebo přidání/odebrání souborů znovu vygenerovat.

```
xcodegen generate
xcodebuild -scheme Memento build
xcodebuild -scheme Memento test
xcodebuild -scheme Memento test -only-testing:MementoTests/ReportBuilderTests/testNazevMetody   # jeden test
```

Lint není nastaven.

## Architektura

- `Models/Models.swift` – SwiftData modely `Project` → `TimeEntry` (cascade mazání). Žádné úkoly: popis práce je volná `TimeEntry.note`. `TimeEntry.end == nil` znamená běžící záznam.
- `Logic/` – čistá logika oddělená od UI (hlavní testovaná vrstva):
  - `TimerController` (`@MainActor @Observable`) – start/stop/přepnutí; běžící záznam se ukládá hned při startu, takže přežije restart. Čas injektovatelný přes `clock` pro testy.
  - `ReportBuilder` – z záznamů vytvoří čistou strukturu výkazu (hodiny, částky, zaokrouhlení). Záznam patří do měsíce, ve kterém **začal**.
  - `EntryValidator` (konec po začátku, žádné překryvy), `FileNaming` (slug názvu PDF), `Formatting` (`CzFormat`, cs_CZ), `Calendar+Prague` (agregace vždy v Europe/Prague), `AppSettings`.
- `PDF/` – `ReportPaginator` rozdělí data na stránky, `ReportPageView` je SwiftUI stránka A4, `PDFExporter` renderuje přes `ImageRenderer` do PDF kontextu. Renderer jen vykresluje hotová data z `ReportBuilder`.
- `Views/` + `MementoApp.swift` – `MenuBarExtra` jako hlavní ovládání a hlavní okno (projekty, záznamy, export, nastavení). Aplikace je `LSUIElement` (bez ikony v Docku).

## Konvence

- Peníze vždy `Decimal`, nikdy `Double`; zaokrouhlení až na konci z přesného součtu sekund.
- Ukládají se skutečné časy (`Date`); zaokrouhlování z nastavení platí jen ve výpočtu exportu.
- Spec v `docs/specs/mvp.md` ještě popisuje úkoly (`Task`); platí model bez úkolů výše.
- Testy (`MementoTests/`, XCTest) míří na logiku v `Logic/` a `PDF/ReportPaginator`, ne na views.
