import SwiftUI

/// Nenápadné pozadí pro paletu Travertin: hodinové paprsky sluneční hodiny z pravého dolního rohu
/// a dlouhý stín gnómonu. Statické; s `shadowProgress` (0…1) se stín otáčí přes hodinové paprsky
/// jako na skutečných sluneční hodinách (využívá to plovoucí okno Pomodora).
struct SundialBackground: View {
    var shadowProgress: Double?

    var body: some View {
        Canvas { context, size in
            let ink = Color(red: 0.227, green: 0.188, blue: 0.133)
            let origin = CGPoint(x: size.width * 1.02, y: size.height * 1.04)
            let reach = hypot(size.width, size.height) * 1.1

            // Hodinové paprsky po 15° (jen ty, které míří do okna).
            for i in 0...12 {
                let angle = Angle.degrees(180 + Double(i) * 7.5)
                var ray = Path()
                ray.move(to: origin)
                ray.addLine(to: CGPoint(x: origin.x + cos(angle.radians) * reach,
                                        y: origin.y + sin(angle.radians) * reach))
                context.stroke(ray, with: .color(ink.opacity(i % 2 == 0 ? 0.07 : 0.04)),
                               lineWidth: i % 2 == 0 ? 2 : 1)
            }
            // Soustředné kruhy ciferníku.
            for radius in [0.28, 0.45, 0.62].map({ $0 * min(size.width, size.height) * 1.2 }) {
                let circle = Path(ellipseIn: CGRect(x: origin.x - radius, y: origin.y - radius,
                                                    width: radius * 2, height: radius * 2))
                context.stroke(circle, with: .color(ink.opacity(0.05)), lineWidth: 1.5)
            }
            // Dlouhý stín.
            let shadowAngle = Angle.degrees(shadowProgress.map { 180 + 90 * min(1, max(0, $0)) } ?? 205).radians
            let tip = CGPoint(x: origin.x + cos(shadowAngle) * reach * 0.55,
                              y: origin.y + sin(shadowAngle) * reach * 0.55)
            var shadow = Path()
            shadow.move(to: CGPoint(x: origin.x + 14, y: origin.y - 22))
            shadow.addLine(to: CGPoint(x: origin.x - 14, y: origin.y + 22))
            shadow.addLine(to: tip)
            shadow.closeSubpath()
            context.fill(shadow, with: .color(ink.opacity(0.06)))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
