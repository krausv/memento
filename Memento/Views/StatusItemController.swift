import AppKit
import Observation
import SwiftData
import SwiftUI

/// Ikona v liště. MenuBarExtra nerozliší levé a pravé kliknutí, proto vlastní NSStatusItem:
/// levý dvojklik spustí / zastaví časovač, levý jednoduchý klik otevře poznámku, pravé tlačítko menu.
@MainActor
final class StatusItemController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let timer: TimerController
    private let container: ModelContainer
    private let updates: UpdateStore
    private var mainWindow: NSWindow?
    private var noteWindow: NSWindow?
    private var pendingSingleClick: DispatchWorkItem?
    private var lastLeftClick: TimeInterval?

    init(timer: TimerController, container: ModelContainer, updates: UpdateStore) {
        self.timer = timer
        self.container = container
        self.updates = updates
        super.init()
        if let button = item.button {
            button.image = Self.menuBarIcon()
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        observeTimer()
    }

    // MARK: Popisek

    /// Překreslí popisek a znovu se přihlásí k odběru změn (každou sekundu mění `timer.now`).
    private func observeTimer() {
        withObservationTracking {
            updateLabel()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeTimer() }
        }
    }

    private func updateLabel() {
        guard let button = item.button else { return }
        if timer.runningEntry != nil {
            button.attributedTitle = NSAttributedString(
                string: " " + timer.totalElapsedText,
                attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)]
            )
        } else {
            button.attributedTitle = NSAttributedString(string: "")
        }
    }

    // MARK: Kliknutí

    @objc private func clicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
        } else {
            handleLeftClick()
        }
    }

    /// Jednoduchý klik (poznámka) se musí o dobu dvojkliku zpozdit, aby ho druhý klik mohl zrušit;
    /// jinak by se před zastavením časovače vždy na chvíli otevřelo okno s poznámkou.
    private func handleLeftClick() {
        // `clickCount` u tlačítka ve stavové liště nedorazí spolehlivě, dvojklik proto poznáme podle času sami.
        let now = ProcessInfo.processInfo.systemUptime
        let isDouble = lastLeftClick.map { now - $0 <= NSEvent.doubleClickInterval } ?? false
        pendingSingleClick?.cancel()
        pendingSingleClick = nil
        lastLeftClick = isDouble ? nil : now
        switch isDouble {
        case false:
            guard timer.runningEntry != nil else { return }
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, let running = self.timer.runningEntry else { return }
                    self.showNoteWindow(for: running)
                }
            }
            pendingSingleClick = work
            DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval, execute: work)
        case true:
            if timer.runningEntry != nil {
                try? timer.stop()
            } else if (try? timer.startDefault()) == nil {
                showMainWindow()
            }
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        if let running = timer.runningEntry {
            menu.addItem(label("\(running.project?.name ?? "Projekt") · \(timer.totalElapsedText)"))
            menu.addItem(ActionItem("Poznámka…") { [weak self] in self?.showNoteWindow(for: running) })
            menu.addItem(ActionItem("Stop") { [weak self] in try? self?.timer.stop() })
        } else {
            menu.addItem(label("Časovač neběží"))
            if let last = timer.lastResumableEntry(), let project = last.project {
                let title = timer.continuesNote(of: last)
                    ? "Pokračovat: " + Self.summary(of: last, in: project)
                    : "Spustit: " + project.name
                menu.addItem(ActionItem(title) { [weak self] in
                    _ = try? self?.timer.resumeLast()
                })
            }
        }

        menu.addItem(.separator())
        let projects = timer.selectableProjects()
        if projects.isEmpty {
            menu.addItem(label("Nejdřív vytvoř projekt v okně Memento"))
        } else {
            menu.addItem(label("Spustit projekt"))
            for project in projects {
                menu.addItem(ActionItem(project.name) { [weak self] in _ = try? self?.timer.start(project) })
            }
        }

        if let release = updates.available {
            menu.addItem(.separator())
            if updates.isInstalling {
                menu.addItem(label("Aktualizuji na \(release.version)…"))
            } else {
                menu.addItem(ActionItem("Aktualizovat na \(release.version) a restartovat") { [weak self] in self?.updates.startUpdate() })
            }
        }

        menu.addItem(.separator())
        menu.addItem(ActionItem("Otevřít Memento") { [weak self] in self?.showMainWindow() })
        menu.addItem(ActionItem("Ukončit", key: "q") { NSApp.terminate(nil) })

        // Menu se k položce připojí jen na dobu zobrazení, jinak by pohlcovalo i levé kliknutí.
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    /// „Projekt – první řádek poznámky“, zkrácené, aby menu nebylo široké.
    private static func summary(of entry: TimeEntry, in project: Project) -> String {
        let firstLine = entry.note?.components(separatedBy: .newlines).first?
            .replacingOccurrences(of: BulletText.marker, with: "")
            .trimmingCharacters(in: .whitespaces) ?? ""
        let text = firstLine.isEmpty ? project.name : "\(project.name) – \(firstLine)"
        return text.count > 50 ? String(text.prefix(49)) + "…" : text
    }

    private func label(_ title: String) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        menuItem.isEnabled = false
        return menuItem
    }

    // MARK: Okna

    func showMainWindow() {
        if mainWindow == nil {
            let root = MainWindow()
                .environment(timer)
                .environment(updates)
                .modelContainer(container)
                .frame(minWidth: 760, minHeight: 480)
            let host = NSHostingController(rootView: root)
            // Okno nesmí sledovat ideální velikost obsahu (Nastavení má ~1400 pt), jinak by se roztahovalo.
            host.sizingOptions = []
            let window = NSWindow(contentViewController: host)
            window.contentMinSize = NSSize(width: 760, height: 480)
            window.title = "Memento"
            // Průhledné záhlaví: obsah okna (barva a pozadí palety) sahá až pod titulek.
            window.styleMask.insert(.fullSizeContentView)
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 900, height: 580))
            window.setFrameAutosaveName("MementoMainWindow")
            // Okno aplikace bez ikony v Docku (accessory) se po přepnutí plochy chovalo špatně:
            // zmizela systémová horní lišta. Po dobu otevřeného okna je aplikace proto běžná
            // a po zavření se vrací do režimu bez ikony v Docku.
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
                MainActor.assumeIsolated { _ = NSApp.setActivationPolicy(.accessory) }
            }
            mainWindow = window
        }
        NSApp.setActivationPolicy(.regular)
        present(mainWindow)
    }

    func showNoteForRunningEntry() {
        if let running = timer.runningEntry { showNoteWindow(for: running) }
    }

    private func showNoteWindow(for entry: TimeEntry) {
        noteWindow?.close()
        let root = QuickNoteView(entry: entry) { [weak self] in self?.noteWindow?.close() }
            .environment(timer)
            .modelContainer(container)
        let window = NSWindow(contentViewController: NSHostingController(rootView: root))
        window.title = "Poznámka"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.center()
        noteWindow = window
        present(window)
    }

    private func present(_ window: NSWindow?) {
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    /// Šablonová ikona sluneční hodiny pro menu bar: kruh, gnómon a stín.
    private static func menuBarIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setStroke(); NSColor.black.setFill()
            let ring = NSBezierPath(ovalIn: NSRect(x: 1.5, y: 1.5, width: 15, height: 15))
            ring.lineWidth = 1.5; ring.stroke()
            let shadow = NSBezierPath()
            shadow.move(to: NSPoint(x: 8.2, y: 10)); shadow.line(to: NSPoint(x: 9.8, y: 8))
            shadow.line(to: NSPoint(x: 14, y: 4.2)); shadow.close(); shadow.fill()
            NSBezierPath(rect: NSRect(x: 6.6, y: 9.6, width: 2.6, height: 3.4)).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Memento"
        return image
    }
}

private final class ActionItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, key: String = "", handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: key)
        target = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func fire() { handler() }
}
