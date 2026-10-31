import SwiftUI

/// Barevná paleta hlavního okna. Volba se ukládá jako `rawValue` do `SettingsKey.palette`.
enum Palette: String, CaseIterable, Identifiable {
    case standard
    case forest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: "Výchozí"
        case .forest: "Les"
        }
    }

    var detail: String {
        switch self {
        case .standard: "Systémový vzhled macOS."
        case .forest: "Uklidňující tmavě zelené tóny."
        }
    }

    var theme: Theme {
        switch self {
        case .standard: .standard
        case .forest: .forest
        }
    }
}

struct Theme {
    var accent: Color
    /// `nil` = systémové pozadí.
    var background: Color?
    var sidebar: Color?
    var surface: AnyShapeStyle
    var colorScheme: ColorScheme?
    /// Barvy sérií v grafech (projekty v čase).
    var chart: [Color]
    var secondaryAccent: Color
    /// Animované pixelartové pozadí.
    var pixelScene = false

    static let standard = Theme(
        accent: .accentColor, background: nil, sidebar: nil,
        surface: AnyShapeStyle(.background.secondary), colorScheme: nil,
        chart: [.blue, .green, .orange, .purple, .pink, .teal, .yellow, .indigo],
        secondaryAccent: .teal
    )

    static let forest = Theme(
        accent: Color(red: 0.51, green: 0.78, blue: 0.62),
        background: Color(red: 0.075, green: 0.137, blue: 0.106),
        sidebar: Color(red: 0.059, green: 0.106, blue: 0.082),
        surface: AnyShapeStyle(Color(red: 0.118, green: 0.208, blue: 0.161)),
        colorScheme: .dark,
        chart: [
            Color(red: 0.51, green: 0.78, blue: 0.62), Color(red: 0.36, green: 0.62, blue: 0.55),
            Color(red: 0.69, green: 0.78, blue: 0.45), Color(red: 0.28, green: 0.50, blue: 0.38),
            Color(red: 0.80, green: 0.74, blue: 0.55), Color(red: 0.55, green: 0.72, blue: 0.78),
            Color(red: 0.42, green: 0.58, blue: 0.30), Color(red: 0.73, green: 0.85, blue: 0.75),
        ],
        secondaryAccent: Color(red: 0.36, green: 0.62, blue: 0.55),
        pixelScene: true
    )
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme.standard
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

extension View {
    /// Použije paletu na celý strom: tón, schéma, pozadí a skryté systémové pozadí posuvných oblastí.
    func themed(_ theme: Theme) -> some View {
        self
            .environment(\.theme, theme)
            .tint(theme.accent)
            .preferredColorScheme(theme.colorScheme)
            .scrollContentBackground(theme.background == nil ? .automatic : .hidden)
    }
}
