import SwiftUI

/// Barevná paleta hlavního okna. Volba se ukládá jako `rawValue` do `SettingsKey.palette`.
enum Palette: String, CaseIterable, Identifiable {
    case travertine
    case standard
    case forest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .travertine: "Travertin"
        case .standard: "Systémový"
        case .forest: "Les"
        }
    }

    var detail: String {
        switch self {
        case .travertine: "Teplé pískové tóny a hnědý inkoust podle ikony aplikace."
        case .standard: "Systémový vzhled macOS."
        case .forest: "Uklidňující tmavě zelené tóny."
        }
    }

    var theme: Theme {
        switch self {
        case .travertine: .travertine
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
    /// Barva textu; `nil` = systémová.
    var ink: Color?
    /// Dekorativní pozadí.
    var scene = Scene.none

    enum Scene { case none, pixelForest, sundial }

    static let standard = Theme(
        accent: .accentColor, background: nil, sidebar: nil,
        surface: AnyShapeStyle(.background.secondary), colorScheme: nil,
        chart: [.blue, .green, .orange, .purple, .pink, .teal, .yellow, .indigo],
        secondaryAccent: .teal
    )

    /// Travertin: paleta ikony (pískový kámen, hnědý inkoust, bronz a terakota).
    static let travertine = Theme(
        accent: Color(red: 0.60, green: 0.36, blue: 0.20),
        background: Color(red: 0.902, green: 0.863, blue: 0.765),
        sidebar: Color(red: 0.796, green: 0.741, blue: 0.616),
        surface: AnyShapeStyle(Color(red: 0.953, green: 0.925, blue: 0.855)),
        colorScheme: .light,
        chart: [
            Color(red: 0.65, green: 0.31, blue: 0.20), Color(red: 0.78, green: 0.60, blue: 0.27),
            Color(red: 0.43, green: 0.45, blue: 0.27), Color(red: 0.35, green: 0.30, blue: 0.22),
            Color(red: 0.36, green: 0.49, blue: 0.54), Color(red: 0.62, green: 0.44, blue: 0.40),
            Color(red: 0.58, green: 0.55, blue: 0.40), Color(red: 0.47, green: 0.33, blue: 0.20),
        ],
        secondaryAccent: Color(red: 0.43, green: 0.45, blue: 0.27),
        ink: Color(red: 0.227, green: 0.188, blue: 0.133),
        scene: .sundial
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
        scene: .pixelForest
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
            .foregroundStyle(theme.ink ?? Color.primary)
            .toolbarBackgroundVisibility(theme.background == nil ? .automatic : .hidden, for: .windowToolbar)
    }
}
