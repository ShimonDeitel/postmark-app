import SwiftUI

/// The red circular date-stamp cancellation that thunks onto a saved find:
/// double circle, POSTMARK arc text stand-in, date line, and wavy killer
/// bars trailing right. Scale/rotate it in at the call site.
struct CancellationMark: View {
    var date: Date = .now
    var diameter: CGFloat = 96

    var body: some View {
        HStack(spacing: -6) {
            ZStack {
                Circle()
                    .strokeBorder(PostmarkTheme.red, lineWidth: 3)
                Circle()
                    .strokeBorder(PostmarkTheme.red, lineWidth: 1.5)
                    .padding(7)
                VStack(spacing: 2) {
                    Text("POSTMARK")
                        .font(.system(size: diameter * 0.11, weight: .bold, design: .monospaced))
                        .tracking(1)
                    Rectangle()
                        .frame(width: diameter * 0.5, height: 1)
                    Text(date.formatted(.dateTime.day().month(.abbreviated).year()))
                        .font(.system(size: diameter * 0.10, weight: .semibold, design: .monospaced))
                    Rectangle()
                        .frame(width: diameter * 0.5, height: 1)
                    Text("IDENTIFIED")
                        .font(.system(size: diameter * 0.09, weight: .medium, design: .monospaced))
                        .tracking(1.5)
                }
                .foregroundStyle(PostmarkTheme.red)
            }
            .frame(width: diameter, height: diameter)

            KillerBars()
                .stroke(PostmarkTheme.red, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .frame(width: diameter * 0.85, height: diameter * 0.5)
        }
        .opacity(0.92)
    }
}

/// The wavy lines that trail a circular date stamp.
private struct KillerBars: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let waves = 4
        for i in 0..<waves {
            let y = rect.minY + rect.height * CGFloat(i) / CGFloat(waves - 1)
            p.move(to: CGPoint(x: rect.minX, y: y))
            let steps = 24
            for s in 1...steps {
                let x = rect.minX + rect.width * CGFloat(s) / CGFloat(steps)
                let phase = CGFloat(s) / CGFloat(steps) * .pi * 3
                p.addLine(to: CGPoint(x: x, y: y + sin(phase) * 2.5))
            }
        }
        return p
    }
}

/// A translucent perforation-gauge ruler that sweeps the photo while the
/// identification runs: the philatelist's tool at work.
struct GaugeSweepView: View {
    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let progress = 0.5 + 0.42 * sin(t * 0.9)
                let y = geo.size.height * progress

                ZStack(alignment: .top) {
                    // Scanned strip above the ruler gets a faint tint.
                    Rectangle()
                        .fill(PostmarkTheme.lamp.opacity(0.08))
                        .frame(height: y)
                        .frame(maxHeight: .infinity, alignment: .top)

                    ruler(width: geo.size.width)
                        .position(x: geo.size.width / 2, y: y)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func ruler(width: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(PostmarkTheme.cream.opacity(0.85))
                .frame(width: width * 0.94, height: 30)
                .shadow(color: PostmarkTheme.baizeDeep.opacity(0.5), radius: 8, y: 3)
            HStack(spacing: 5) {
                ForEach(0..<40, id: \.self) { i in
                    Rectangle()
                        .fill(PostmarkTheme.ink.opacity(i % 5 == 0 ? 0.75 : 0.4))
                        .frame(width: 1.2, height: i % 5 == 0 ? 14 : 8)
                }
            }
            Text("GAUGE 11½")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(PostmarkTheme.red.opacity(0.85))
                .offset(y: 9)
        }
    }
}
