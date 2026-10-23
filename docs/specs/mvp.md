# Memento – zadání MVP

Jednoduchá nativní macOS aplikace pro sledování času na úkolech. Žádný backend, žádné účty, žádná synchronizace. Data zůstávají lokálně na Macu. Na konci měsíce vygeneruje PDF výkaz hodin pro každý projekt podle jeho hodinové sazby.

## Technologie

- Swift 5.10+, SwiftUI, cílová verze macOS 27 (Golden Gate) a novější
- Perzistence: SwiftData (lokální úložiště v Application Support)
- Generování PDF: SwiftUI `ImageRenderer` do PDF kontextu (bez knihoven třetích stran)
- Xcode projekt generovat přes **XcodeGen** (`project.yml`), `.xcodeproj` needitovat ručně a necommitovat
- Build a testy spouštět z CLI: `xcodegen generate && xcodebuild -scheme Memento build test`
- Bez externích závislostí

## Forma aplikace

Aplikace má dvě části:

1. **Menu bar** (`MenuBarExtra`) – hlavní ovládání během dne
   - Ikona v liště; když běží časovač, vedle ikony je vidět uplynulý čas (`1:23`)
   - Po kliknutí: aktuálně běžící úkol + tlačítko Stop, seznam posledních 5 úkolů pro rychlé spuštění, tlačítko „Otevřít Memento“, Ukončit
2. **Hlavní okno** – správa projektů, úkolů, záznamů a export

Aplikace se nezobrazuje v Docku (`LSUIElement = YES`), hlavní okno se otevírá z menu baru.

## Datový model

**Project**
- `id: UUID`
- `name: String` (povinné, unikátní)
- `client: String?` (název klienta do PDF)
- `hourlyRate: Decimal` (Kč/h, povinné, ≥ 0)
- `currency: String` (výchozí „CZK“)
- `isArchived: Bool`
- `createdAt: Date`
- vztah: `tasks: [Task]`

**Task**
- `id: UUID`
- `name: String` (povinné)
- `isArchived: Bool`
- `createdAt: Date`
- vztahy: `project: Project`, `entries: [TimeEntry]`

**TimeEntry**
- `id: UUID`
- `start: Date`
- `end: Date?` (nil = právě běží)
- `note: String?`
- vztah: `task: Task`
- vypočtené: `duration: TimeInterval`

Mazání: smazání projektu smaže jeho úkoly a záznamy (cascade), ale jen po potvrzení. Preferovaná akce je archivace.

## Funkce

### Časovač
- V jeden okamžik může běžet **nejvýše jeden** časovač. Spuštění dalšího úkolu automaticky ukončí běžící záznam.
- Běžící záznam je uložen hned při startu (`end = nil`), takže přežije ukončení aplikace, pád i restart Macu. Po spuštění aplikace časovač pokračuje.
- Zobrazení uplynulého času se aktualizuje každou sekundu, ukládá se pouze start a konec.

### Projekty a úkoly
- Vytvoření, úprava a archivace projektu (název, klient, sazba, měna)
- Vytvoření, úprava a archivace úkolu v rámci projektu
- Archivované položky se nezobrazují v menu baru ani při výběru, ale zůstávají v historii a exportech

### Záznamy času
- Seznam záznamů seskupený po dnech (nejnovější nahoře), u každého dne součet
- Ruční přidání záznamu (úkol, datum, od–do) pro případ, že jsem zapomněl píchnout
- Úprava a smazání záznamu
- Validace: konec musí být po začátku, záznamy jednoho uživatele se nesmí překrývat (při překryvu zobrazit chybu)
- Záznam přes půlnoc je povolen; pro účely měsíčního výkazu se počítá do dne a měsíce, ve kterém **začal**

### Měsíční export do PDF
- Výběr měsíce (výchozí: aktuální, rychlá volba „minulý měsíc“)
- Výběr projektů k exportu (výchozí: všechny projekty, které mají v daném měsíci záznamy)
- Vygeneruje **jedno PDF pro každý projekt**, uloží je do složky zvolené přes `NSOpenPanel`
- Název souboru: `{rok}-{měsíc}_{název-projektu}.pdf`, např. `2026-10_digi-sprava.pdf` (slug bez diakritiky)
- Po exportu otevřít složku ve Finderu

**Obsah PDF (A4, na výšku):**
1. Hlavička: „Výkaz práce“, název projektu, klient (pokud je vyplněn), období (např. „říjen 2026“)
2. Tabulka po úkolech: název úkolu, počet hodin
3. Detailní tabulka záznamů: datum, úkol, poznámka, od–do, trvání
4. Souhrn: celkem hodin, hodinová sazba, **celková částka**
5. Patička: datum vygenerování, číslo stránky

Formátování:
- Hodiny zobrazovat desetinně na 2 místa (`12,50 h`), české formátování čísel a data (`cs_CZ`)
- Částka v měně projektu, např. `18 750,00 Kč`
- Částka se počítá z přesného součtu sekund, zaokrouhlení až na konci (na haléře)
- Delší tabulka se musí správně rozdělit na více stránek

### Nastavení
- Výchozí sazba pro nové projekty
- Zaokrouhlování záznamů v exportu: žádné / na 5 / 15 / 30 minut nahoru (výchozí: žádné). Uložená data se nikdy nezaokrouhlují, jen výpočet v exportu.
- Jméno a IČO dodavatele (volitelné, zobrazí se v hlavičce PDF)
- Spustit při přihlášení (`SMAppService`)

## Architektura

- Oddělit výpočetní logiku od UI: služba pro agregaci výkazu (`ReportBuilder`) dostane záznamy a vrátí čistou strukturu (úkoly, hodiny, částky). PDF renderer pouze vykresluje hotová data.
- Logiku časovače (start/stop/přepnutí) mít v samostatné třídě, ne ve view
- Peníze počítat v `Decimal`, nikdy v `Double`
- Čas vždy ukládat jako `Date`, převod na lokální čas (Europe/Prague) až při zobrazení a agregaci

## Testy (XCTest)

Povinně pokrýt unit testy:
- Výpočet hodin a částky v `ReportBuilder` (včetně zaokrouhlování)
- Záznam přes půlnoc a přes přelom měsíce
- Přechod letního/zimního času (záznam v noci, kdy se mění čas)
- Spuštění druhého časovače ukončí první
- Validace překrývajících se záznamů
- Slug názvu souboru (diakritika, mezery, speciální znaky)

## Mimo rozsah MVP

Neimplementovat: synchronizaci, iCloud, iOS verzi, účty, týmy, fakturaci a DPH, detekci nečinnosti, grafy a statistiky, štítky, import z jiných nástrojů, notifikace, export do CSV.

## Kritéria dokončení

- [ ] Aplikace se sestaví z CLI bez varování a všechny testy projdou
- [ ] Jde vytvořit projekt se sazbou a úkol, spustit a zastavit časovač z menu baru
- [ ] Běžící časovač přežije ukončení a znovuspuštění aplikace
- [ ] Jde ručně přidat, upravit a smazat záznam
- [ ] Export za měsíc vytvoří správné PDF pro každý projekt a čísla v PDF sedí s testy
- [ ] Rozhraní je v češtině

## Postup pro Claude Code

1. Nejdřív `project.yml`, datový model a `ReportBuilder` s testy
2. Pak logika časovače s testy
3. Pak menu bar UI, hlavní okno a nakonec PDF export
4. Po každém kroku spustit build a testy, commitovat po funkčních celcích
