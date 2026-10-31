import SwiftUI

/// Ciferník sluneční hodiny podle ikony aplikace: dva prstence, hodinové rysky, římské číslice
/// na světových stranách a gnómon. Stín gnómonu obchází ciferník podle `progress` (0…1, po směru hodin
/// od dvanáctky) a oblouk u okraje ukazuje uplynulou část.
struct SundialDial: View {
    var progress: Double
    var arc: Color
    var ink: Color
    var face: AnyShapeStyle?

    private static let numerals: [(angle: Double, text: String)] = [(-90, "XII"), (0, "III"), (90, "VI"), (180, "IX")]

    var body: some View {
        ZStack {
            if let face { Circle().fill(face) }
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(size.width, size.height) / 2

                // Oblouk uplynulé části.
                if progress > 0 {
                    var done = Path()
                    done.addArc(center: center, radius: radius - 5, startAngle: .degrees(-90),
                                endAngle: .degrees(-90 + 360 * progress), clockwise: false)
                    context.stroke(done, with: .color(arc), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                }
                // Vnější a vnitřní prstenec.
                for (r, width) in [(radius - 1, 1.5), (radius * 0.66, 1.0)] {
                    context.stroke(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
                                   with: .color(ink.opacity(0.55)), lineWidth: width)
                }
                // Hodinové rysky, na světových stranách silnější.
                for hour in 0..<12 {
                    let angle = Angle.degrees(Double(hour) * 30 - 90).radians
                    let major = hour % 3 == 0
                    var tick = Path()
                    tick.move(to: point(center, angle, radius * (major ? 0.5 : 0.56)))
                    tick.addLine(to: point(center, angle, radius * 0.66))
                    context.stroke(tick, with: .color(ink.opacity(major ? 0.9 : 0.55)), lineWidth: major ? 2.5 : 1.2)
                }
                // Římské číslice mezi prstenci.
                for numeral in Self.numerals {
                    let spot = point(center, Angle.degrees(numeral.angle).radians, radius * 0.82)
                    context.draw(
                        Text(numeral.text).font(.system(size: radius * 0.17, weight: .bold, design: .serif)).foregroundColor(ink),
                        at: spot
                    )
                }
                // Stín gnómonu.
                let angle = Angle.degrees(-90 + 360 * progress).radians
                let side = angle + .pi / 2
                var shadow = Path()
                shadow.move(to: point(center, side, 4))
                shadow.addLine(to: point(center, side + .pi, 4))
                shadow.addLine(to: point(center, angle, radius * 0.9))
                shadow.closeSubpath()
                context.fill(shadow, with: .color(ink.opacity(0.65)))
                // Gnómon.
                context.fill(Path(CGRect(x: center.x - 4.5, y: center.y - 6, width: 9, height: 12)), with: .color(ink))
            }
        }
        .accessibilityHidden(true)
    }

    private func point(_ center: CGPoint, _ angle: Double, _ distance: Double) -> CGPoint {
        CGPoint(x: center.x + cos(angle) * distance, y: center.y + sin(angle) * distance)
    }
}
