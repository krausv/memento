import SwiftUI

/// Pixelartové pozadí pro paletu Les: siluety borovic, světlušky a padající listí.
/// Vše se kreslí na hrubou mřížku (`cell`), jen 8× za vteřinu, aby to bylo nenápadné a levné.
struct PixelForestBackground: View {
    private static let cell: CGFloat = 4

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.125)) { timeline in
            Canvas(rendersAsynchronously: true) { context, size in
                draw(&context, size: size, time: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let cell = Self.cell
        let cols = Int(size.width / cell), rows = Int(size.height / cell)
        guard cols > 0, rows > 0 else { return }

        func rect(_ x: Int, _ y: Int, _ w: Int = 1, _ h: Int = 1) -> CGRect {
            CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: CGFloat(w) * cell, height: CGFloat(h) * cell)
        }

        // Stromy: dvě vrstvy (vzdálenější tmavší) z pevného semínka, takže se nehýbou.
        var far = Path(), near = Path(), trunks = Path()
        var seed: UInt64 = 0x9E37_79B9
        func next(_ range: Int) -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int((seed >> 33) % UInt64(range))
        }
        var x = -2
        while x < cols + 2 {
            let height = 10 + next(14)
            let isNear = next(3) == 0
            let baseY = rows - (isNear ? 0 : 3)
            for r in 0..<height {
                let half = r / 2 + (r % 4 == 3 ? 1 : 0)
                let row = rect(x - half, baseY - height - 2 + r, half * 2 + 1)
                if isNear { near.addRect(row) } else { far.addRect(row) }
            }
            trunks.addRect(rect(x, baseY - 2, 1, 2))
            x += 3 + next(5)
        }
        context.fill(far, with: .color(Color(red: 0.09, green: 0.17, blue: 0.13).opacity(0.9)))
        context.fill(near, with: .color(Color(red: 0.07, green: 0.13, blue: 0.10)))
        context.fill(trunks, with: .color(Color(red: 0.12, green: 0.09, blue: 0.07)))

        // Světlušky: pomalé kličkování, pulzující jas.
        for i in 0..<7 {
            let f = Double(i)
            let px = (sin(time * 0.07 + f * 2.1) * 0.5 + 0.5) * Double(cols) + sin(time * 0.4 + f) * 4
            let py = (cos(time * 0.05 + f * 1.3) * 0.5 + 0.5) * Double(rows) * 0.8 + cos(time * 0.3 + f * 2) * 3
            let glow = max(0, sin(time * 0.9 + f * 1.7))
            guard glow > 0.3 else { continue }
            let cx = Int(px), cy = Int(py)
            let color = Color(red: 0.82, green: 0.93, blue: 0.55)
            context.fill(Path(rect(cx, cy)), with: .color(color.opacity(0.12 + glow * 0.25)))
            if glow > 0.9 {
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    context.fill(Path(rect(cx + dx, cy + dy)), with: .color(color.opacity(0.07)))
                }
            }
        }

        // Listí: šikmý pád s kolísáním do stran.
        for i in 0..<4 {
            let f = Double(i)
            let speed = 0.9 + f.truncatingRemainder(dividingBy: 3) * 0.5
            let fall = (time * speed + f * 17).truncatingRemainder(dividingBy: Double(rows + 6))
            let lx = Int(f * 37.0.truncatingRemainder(dividingBy: Double(cols)) + sin(time * 0.6 + f) * 5 + fall * 0.4) % cols
            let ly = Int(fall) - 3
            let tone = i % 2 == 0 ? Color(red: 0.55, green: 0.72, blue: 0.40) : Color(red: 0.78, green: 0.70, blue: 0.40)
            context.fill(Path(rect(lx, ly, 2, 1)), with: .color(tone.opacity(0.22)))
        }
    }
}
