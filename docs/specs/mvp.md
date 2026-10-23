# Memento – zadání MVP

Jednoduchá nativní macOS aplikace pro sledování času na projektech. Žádný backend, žádné účty, žádná synchronizace. Data zůstávají lokálně na Macu. Na konci měsíce vygeneruje PDF výkaz hodin pro každý projekt podle jeho hodinové sazby.

## Technologie

- Swift 5.10+, SwiftUI, cílová verze macOS 27 (Golden Gate) a novější
- UI používá design system Liquid Glass (standardní prvky ho přebírají od systému, vlastní prvky `glassEffect` / `.glass` tlačítka)
- Perzistence: SwiftData (lokální úložiště v Application Support)
- Generování PDF: SwiftUI `ImageRenderer` do PDF kontextu (bez knihoven třetích stran)
- Xcode projekt generovat přes **XcodeGen** (`project.yml`), `.xcodeproj` needitovat ručně a necommitovat
- Build a testy spouštět z CLI: `xcodegen generate && xcodebuild -scheme Memento build test`
- Bez externích závislostí

## Forma aplikace

Aplikace má dvě části:

1. **Ikona v liště** (`NSStatusItem`, ne `MenuBarExtra`, protože ten nerozliší levé a pravé tlačítko) – hlavní ovládání během dne
   - Ikona s časovačem; když běží časovač, vedle ikony je vidět uplynulý čas (`1:23`)
   - **Levý dvojklik, časovač neběží:** spustí časovač (navázání na poslední záznam, jinak naposledy použitý nearchivovaný projekt; bez projektů otevře hlavní okno)
   - **Levý dvojklik, časovač běží:** časovač zastaví
   - **Levý jednoduchý klik, časovač běží:** otevře malé okno s poznámkou k běžícímu záznamu (⌘↩ uloží); otevře se se zpožděním o dobu dvojkliku, aby ho druhý klik mohl zrušit. Při neběžícím časovači nedělá nic
   - **Pravé tlačítko (nebo Ctrl+klik):** menu s běžícím projektem, Poznámka…, Stop, seznamem projektů (naposledy použité první) pro spuštění, „Otevřít Memento“, Ukončit
2. **Hlavní okno** – správa projektů, záznamů a export

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
- vztah: `entries: [TimeEntry]`

**TimeEntry**
- `id: UUID`
- `start: Date`
- `end: Date?` (nil = právě běží)
- `note: String?` (volný, i víceřádkový popis práce; nahrazuje úkoly, v UI se automaticky odrážkuje)
- vztah: `project: Project`
- vypočtené: `duration: TimeInterval`

Úkoly se nepoužívají – popis práce nese poznámka záznamu.

Mazání: smazání projektu smaže jeho záznamy (cascade), ale jen po potvrzení. Preferovaná akce je archivace.

## Funkce

### Časovač
- V jeden okamžik může běžet **nejvýše jeden** časovač. Spuštění časovače na jiném projektu automaticky ukončí běžící záznam.
- Běžící záznam je uložen hned při startu (`end = nil`), takže přežije ukončení aplikace, pád i restart Macu. Po spuštění aplikace časovač pokračuje.
- Zobrazení uplynulého času se aktualizuje každou sekundu, ukládá se pouze start a konec.

### Projekty
- Vytvoření, úprava a archivace projektu (název, klient, sazba, měna)
- Archivované projekty se nezobrazují v menu baru ani při výběru, ale zůstávají v historii a exportech

### Záznamy času
- Seznam záznamů seskupený po dnech (nejnovější nahoře), u každého dne součet
- Ruční přidání záznamu (projekt, datum, od–do, poznámka) pro případ, že jsem zapomněl píchnout
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
2. Detailní tabulka záznamů: datum, poznámka, od–do, trvání (řádek se přizpůsobí délce poznámky)
3. Souhrn: celkem hodin, hodinová sazba, **celková částka**
4. Patička: datum vygenerování, číslo stránky

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

- Oddělit výpočetní logiku od UI: služba pro agregaci výkazu (`ReportBuilder`) dostane záznamy a vrátí čistou strukturu (záznamy, hodiny, částky). PDF renderer pouze vykresluje hotová data.
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

Neimplementovat: synchronizaci, iCloud, iOS verzi, účty, týmy, fakturaci a DPH, detekci nečinnosti, import z jiných nástrojů, export do CSV.

## Plánovaná rozšíření

Po MVP, v tomto pořadí (každé samostatný celek s vlastními testy):

1. **Rychlé navázání** – pokračovat v projektu s poslední poznámkou jedním kliknutím (hotovo)
   - `TimerController.resumeLast()` spustí projekt posledního záznamu a zkopíruje jeho poznámku, pokud skončil před méně než 2 hodinami (starší záznam spustí stejný projekt bez poznámky); nearchivovaný projekt, jinak se přeskočí na starší záznam
   - Levý dvojklik na ikonu při neběžícím časovači navazuje na poslední záznam; v pravém menu je položka „Pokračovat: projekt – poznámka“ (u starého záznamu „Spustit: projekt“); v seznamu záznamů akce „Pokračovat“
2. **Zálohování** (hotovo) – export a import do verzovaného JSON (`BackupV1`: projekty, záznamy, štítky, nastavení), ne kopie souboru SwiftData. Import ve dvou režimech: sloučit podle UUID (projekt se stejným názvem se mapuje na existující, druhý běžící záznam se přeskočí, nastavení se nemění) / nahradit vše včetně nastavení (s potvrzením); kontrola verze a konzistence (nejvýše jeden běžící záznam). Ovládání v Nastavení › Záloha. Automatická záloha (Nastavení › Automatická záloha): zapíná se volbou složky; četnost denně / týdně (výchozí týdně), ponechá posledních N záloh (výchozí 10). `AutoBackupScheduler` kontroluje po startu, po probuzení Macu a jednou za hodinu, zda je záloha na řadě (od poslední úspěšné uplynul interval), a zapisuje `memento-auto-RRRR-MM-DD-HHmm.json` ve stejném formátu jako ruční export. Mazání starých záloh se týká jen souborů přesně tohoto vzoru, ostatní soubory ve složce se nikdy nemažou. Při selhání (např. chybějící složka) se chyba zobrazí v Nastavení a jednou se pošle oznámení; čas poslední úspěšné zálohy se zachová. Nastavení automatické zálohy není součástí zálohy (cesta je místní). Tlačítko „Zálohovat teď“
3. **Štítky** (hotovo) – `Tag` (název, barva) ve vztahu M:N se záznamem (ne s projektem); výběr ve formuláři záznamu a v okně poznámky, filtr v Záznamech, správa v Nastavení; názvy jsou unikátní bez ohledu na velikost písmen a diakritiku; smazání štítku ho jen odebere ze záznamů; při navázání se kopírují spolu s poznámkou (jen u čerstvého záznamu); jsou součástí zálohy (nepovinná pole, formát zůstává ve verzi 1); v PDF se nezobrazují
4. **Cíle a limity** (hotovo) – `Project.budgetHours` a období (celkem / měsíčně); čistá funkce `BudgetStatus` počítá včetně běžícího záznamu a se zaokrouhlením z exportu; ukazatel postupu v projektu; upozornění při 80 % a po překročení (`BudgetMonitor` kontroluje každých 30 s a po startu/stopu časovače; poslední oznámená úroveň a období se ukládají v projektu, takže se neopakuje; zvýšení limitu nebo nový měsíc u měsíčního limitu upozornění znovu aktivuje, úprava limitu a obnova ze zálohy stávající čerpání neoznamují); zaokrouhlení z exportu se počítá; limit je součástí zálohy; systémová oznámení (`UserNotifications`) se povolují při prvním nastavení limitu
   - **Měsíční cíl fakturace** (`Project.targetAmount`, volitelný, v měně projektu): `TargetStatus` porovnává částku za aktuální měsíc (sazba × čas se zaokrouhlením z exportu, počítaná stejně jako ve výkazu, včetně běžícího záznamu) s cílem: **pod hranicí** (< 98 % cíle), **na hranici** (±2 % cíle) a **nad hranicí** (> 102 %). V řádku projektu je ukazatel a rozdíl („chybí 7 300 Kč“ / „+1 200 Kč“). Upozornění přijde po dosažení a po překročení cíle, jednou za měsíc; cíl je součástí zálohy
5. **Notifikace** (hotovo; `UserNotifications`) – tři druhy, všechny v Nastavení › Připomínky a ve výchozím stavu vypnuté:
   - „Neběží časovač“: v pracovní době (pracovní dny + od–do, jedno nastavení pro všechny dny; výchozí Po–Pá 9–17). Nejvýš jednou za hodinu, ne dříve než 15 minut po zastavení a jen když existuje nearchivovaný projekt. Akce v oznámení „Spustit časovač“ (`TimerController.startDefault`: navázání, jinak poslední projekt)
   - „Běží příliš dlouho“: po N hodinách (výchozí 8, 1–24), jednou za záznam, i mimo pracovní dobu. Akce „Zastavit“
   - „Chybí poznámka“: časovač běží aspoň N minut (výchozí 15, krok 5) a záznam nemá žádnou poznámku (prázdné odrážky se nepočítají); jednou za záznam, i mimo pracovní dobu. Akce „Doplnit poznámku“ i klik na oznámení otevře okno s poznámkou. Přednost má upozornění na dlouhý běh
   - Čistá funkce `ReminderPolicy.evaluate`; `ReminderScheduler` ji vyhodnocuje jednou za minutu a po probuzení Macu. Stav posledního upozornění je jen v paměti. Nastavení je součástí zálohy. Sdílí vrstvu `Notifications` s limity
6. **Grafy a statistiky** (hotovo) – sekce „Přehled“ ve Swift Charts s přepínačem týden / měsíc / rok a procházením období (týden začíná v pondělí). `StatsBuilder` (čistá logika, bez SwiftData) počítá ze **skutečných časů** (bez zaokrouhlení z exportu): sloupcový graf hodin v čase (po dnech, u roku po měsících) rozdělený podle projektů, součty podle projektů a podle štítků (záznam s víc štítky se počítá ke každému, bez štítku do „Bez štítku“), dlaždice Celkem / Průměr za den s prací / Počet záznamů / Srovnání s předchozím obdobím. Záznam patří do dne a měsíce, ve kterém začal; běžící záznam se počítá do teď. Pokud mají projekty měsíční cíl fakturace, přibude karta „Cíl fakturace“: u týdne a měsíce stav (pod / na / nad hranicí, ukazatel, rozdíl) za měsíc zvoleného období, u roku sloupce měsíčních částek obarvené podle polohy a přerušovaná čára cíle (jen do aktuálního měsíce); částky se počítají se zaokrouhlením z exportu stejně jako u projektu. Ostatní částky se v přehledu nezobrazují

## Kritéria dokončení

- [ ] Aplikace se sestaví z CLI bez varování a všechny testy projdou
- [ ] Jde vytvořit projekt se sazbou, spustit a zastavit časovač z menu baru
- [ ] Běžící časovač přežije ukončení a znovuspuštění aplikace
- [ ] Jde ručně přidat, upravit a smazat záznam
- [ ] Export za měsíc vytvoří správné PDF pro každý projekt a čísla v PDF sedí s testy
- [ ] Rozhraní je v češtině

## Postup pro Claude Code

1. Nejdřív `project.yml`, datový model a `ReportBuilder` s testy
2. Pak logika časovače s testy
3. Pak menu bar UI, hlavní okno a nakonec PDF export
4. Po každém kroku spustit build a testy, commitovat po funkčních celcích
