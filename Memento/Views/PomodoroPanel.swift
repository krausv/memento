import AppKit
import SwiftUI

/// Plovoucí okno s vizuálním časovačem Pomodora: kruhový ukazatel fáze, zbývající čas a tlačítka.
struct PomodoroTimerView: View {
    let scheduler: PomodoroScheduler
    @AppStorage(SettingsKey.palette) private var paletteRaw = Palette.travertine.rawValue

    private var theme: Theme { (Palette(rawValue: paletteRaw) ?? .travertine).theme }

    private var ink: Color { theme.ink ?? .primary }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let state = scheduler.state {
                content(state, now: context.date, settings: scheduler.currentSettings)
            }
        }
        .environment(\.theme, theme)
        .tint(theme.accent)
        .foregroundStyle(ink)
        .frame(width: PomodoroPanelController.size.width, height: PomodoroPanelController.size.height)
        .background { background }
    }

    /// Stejné pozadí jako hlavní okno (barva palety a její scéna) v zaoblené kartě; paleta bez vlastního pozadí dostane sklo.
    @ViewBuilder
    private var background: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        if let base = theme.background {
            ZStack {
                base
                scene
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(ink.opacity(0.2), lineWidth: 1))
        } else {
            Color.clear.glassEffect(.regular, in: shape)
        }
    }

    @ViewBuilder
    private var scene: some View {
        switch theme.scene {
        case .sundial: SundialBackground()
        case .pixelForest: PixelForestBackground()
        case .none: EmptyView()
        }
    }

    private func content(_ state: PomodoroState, now: Date, settings: PomodoroSettings) -> some View {
        let remaining = PomodoroPolicy.remaining(state, now: now, settings: settings)
        let color = state.phase.isBreak ? theme.secondaryAccent : theme.accent
        return VStack(spacing: 6) {
            SundialDial(progress: PomodoroPolicy.progress(state, now: now, settings: settings),
                        arc: color, ink: ink, face: theme.surface)
                .frame(width: 132, height: 132)

            Text(Self.clock(remaining))
                .font(.system(size: 30, weight: .semibold, design: .serif))
                .monospacedDigit()
                .padding(.top, 4)
            Text(Self.title(state).uppercased())
                .font(.system(size: 10, weight: .semibold, design: .serif))
                .tracking(1.5)
                .foregroundStyle(ink.opacity(0.65))

            dots(state, cycles: max(1, settings.cyclesBeforeLongBreak), color: color)
                .padding(.vertical, 4)

            VStack(spacing: 6) { buttons(state) }
                .frame(height: 62, alignment: .top)
        }
        .padding(16)
    }

    private func dots(_ state: PomodoroState, cycles: Int, color: Color) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<cycles, id: \.self) { index in
                let done = index < state.completed
                let current = index == state.completed && state.phase == .work
                Circle()
                    .fill(done ? color : .clear)
                    .overlay(Circle().stroke(done || current ? color : ink.opacity(0.4), lineWidth: current ? 2 : 1))
                    .frame(width: 10, height: 10)
            }
        }
        .accessibilityLabel("Dokončeno pomodor v sérii: \(state.completed) z \(cycles)")
    }

    @ViewBuilder
    private func buttons(_ state: PomodoroState) -> some View {
        let actions = PomodoroPolicy.availableActions(state)
        if actions.contains(.startNext) {
            Button(state.phase == .work ? "Spustit pauzu" : "Spustit pomodoro") { scheduler.perform(.startNext) }
                .buttonStyle(.borderedProminent)
        }
        HStack(spacing: 6) {
            if actions.contains(.snooze) {
                Button("+\(Int(PomodoroPolicy.snooze / 60)) min") { scheduler.perform(.snooze) }
            }
            if actions.contains(.skipBreak) {
                Button("Přeskočit pauzu") { scheduler.perform(.skipBreak) }
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    static func title(_ state: PomodoroState) -> String {
        switch (state.phase, state.awaiting) {
        case (.work, false): "Práce"
        case (.work, true): "Hotovo"
        case (.shortBreak, false): "Pauza"
        case (.longBreak, false): "Dlouhá pauza"
        case (_, true): "Pauza skončila"
        }
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

/// Drží plovoucí panel: ukáže ho, když běží cyklus a je zapnutý vizuální režim, jinak ho schová.
@MainActor
final class PomodoroPanelController {
    static let size = CGSize(width: 190, height: 330)

    private let scheduler: PomodoroScheduler
    private var panel: NSPanel?
    private var wanted = false
    private var checker: Timer?

    init(scheduler: PomodoroScheduler) {
        self.scheduler = scheduler
        observe()
        // Přepnutí plochy nebo aplikace může okno přivést na fullscreen plochu nebo z ní pryč.
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
        // Fullscreen se dá zapnout i bez přepnutí plochy (např. video v prohlížeči), proto i pravidelná kontrola.
        let checker = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(checker, forMode: .common)
        self.checker = checker
    }

    private func observe() {
        withObservationTracking {
            wanted = scheduler.showsVisual
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.observe()
                self?.refresh()
            }
        }
        refresh()
    }

    /// Okno je vidět, jen když cyklus běží a na jeho obrazovce není nic ve fullscreenu.
    private func refresh() {
        guard wanted else {
            panel?.orderOut(nil)
            return
        }
        let panel = makePanelIfNeeded()
        let screen = panel.screen ?? NSScreen.main
        if let screen, Self.hasFullscreenWindow(on: screen) {
            if panel.isVisible { panel.orderOut(nil) }
        } else {
            // Opakované zobrazení je neškodné a přesune okno na právě aktivní plochu.
            panel.orderFrontRegardless()
        }
    }

    /// Okno jiné aplikace přes celou obrazovku včetně místa pod menu lištou = fullscreen.
    /// Okna se čtou bez oprávnění k nahrávání obrazovky (potřebujeme jen PID a rozměry).
    static func hasFullscreenWindow(on screen: NSScreen) -> Bool {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return false }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let f = screen.frame
        // CoreGraphics má počátek vlevo nahoře na hlavní obrazovce, AppKit vlevo dole.
        let target = CGRect(x: f.minX, y: primaryHeight - f.maxY, width: f.width, height: f.height)
        let me = ProcessInfo.processInfo.processIdentifier
        return windows.contains { window in
            guard (window[kCGWindowLayer as String] as? Int) == 0,
                  (window[kCGWindowOwnerPID as String] as? Int32) != me,
                  let dict = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict) else { return false }
            return abs(bounds.minX - target.minX) < 1 && abs(bounds.minY - target.minY) < 1
                && abs(bounds.width - target.width) < 1 && abs(bounds.height - target.height) < 1
        }
    }

    private func makePanelIfNeeded() -> NSPanel {
        if let panel { return panel }
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        // Okno nepatří na všechny plochy (to by na fullscreen ploše probliklo, než ho schováme),
        // ale při zobrazení se přesune na aktivní plochu – až když jsme ověřili, že tam není fullscreen.
        panel.collectionBehavior = [.moveToActiveSpace]
        panel.contentView = NSHostingView(rootView: PomodoroTimerView(scheduler: scheduler))
        // Poslední polohu si okno pamatuje; poprvé se položí do pravého horního rohu.
        if !panel.setFrameAutosaveName("MementoPomodoroPanel"), let screen = NSScreen.main {
            let area = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: area.maxX - Self.size.width - 24, y: area.maxY - Self.size.height - 24))
        }
        self.panel = panel
        return panel
    }
}
