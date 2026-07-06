import SwiftUI
import UIKit

/// Postmark's design language: a philatelist's desk at night. Deep green
/// baize under a warm lamp pool, cream stamp mounts with real perforations,
/// catalog monospace, and cancellation-ink red. Nothing shared with any
/// sibling app.
enum PostmarkTheme {
    // MARK: Palette
    static let baize = Color(red: 0.071, green: 0.208, blue: 0.169)
    static let baizeDeep = Color(red: 0.043, green: 0.133, blue: 0.106)
    static let lamp = Color(red: 1.0, green: 0.894, blue: 0.678)
    static let cream = Color(red: 0.957, green: 0.929, blue: 0.863)
    static let creamDeep = Color(red: 0.894, green: 0.851, blue: 0.761)
    static let ink = Color(red: 0.153, green: 0.141, blue: 0.11)
    static let inkSoft = Color(red: 0.153, green: 0.141, blue: 0.11).opacity(0.58)
    /// Cancellation ink.
    static let red = Color(red: 0.71, green: 0.22, blue: 0.18)
    static let gilt = Color(red: 0.788, green: 0.635, blue: 0.325)

    // MARK: Type — serif headings, catalog monospace for data rows.
    static func heading(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
    static func catalog(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    static func text(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}

enum PostmarkHaptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    /// The cancellation thunk.
    static func cancel() { UIImpactFeedbackGenerator(style: .heavy).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}

/// Scale-press feedback.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Perforated stamp shape

/// A rectangle with semicircular perforation notches punched along every
/// edge, like a postage stamp. Even-odd fill: outer rect minus notch circles.
struct PerforatedRect: Shape {
    var notchRadius: CGFloat = 4.5
    var notchSpacing: CGFloat = 15

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addRect(rect)

        func punch(along edge: [CGPoint]) {
            for center in edge {
                p.addEllipse(in: CGRect(
                    x: center.x - notchRadius, y: center.y - notchRadius,
                    width: notchRadius * 2, height: notchRadius * 2
                ))
            }
        }

        func spots(from: CGFloat, to: CGFloat) -> [CGFloat] {
            let length = to - from
            let count = max(Int(length / notchSpacing), 1)
            let step = length / CGFloat(count)
            return (0...count).map { from + CGFloat($0) * step }
        }

        punch(along: spots(from: rect.minX, to: rect.maxX).map { CGPoint(x: $0, y: rect.minY) })
        punch(along: spots(from: rect.minX, to: rect.maxX).map { CGPoint(x: $0, y: rect.maxY) })
        punch(along: spots(from: rect.minY, to: rect.maxY).map { CGPoint(x: rect.minX, y: $0) })
        punch(along: spots(from: rect.minY, to: rect.maxY).map { CGPoint(x: rect.maxX, y: $0) })
        return p
    }
}

extension View {
    /// Clips to a perforated stamp edge and fills the paper behind it.
    func stampMount(paper: Color = PostmarkTheme.cream) -> some View {
        self
            .background(paper)
            .clipShape(PerforatedRect(), style: FillStyle(eoFill: true))
    }
}

// MARK: - Backdrop

/// Deep green baize under a hanging desk lamp. The lamp pool sways almost
/// imperceptibly, like the lamp is on a long cord.
struct BaizeBackdrop: View {
    var intensity: Double = 1

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [PostmarkTheme.baize, PostmarkTheme.baizeDeep],
                startPoint: .top, endPoint: .bottom
            )

            TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let swayX = sin(t * 0.31) * 14
                let swayY = cos(t * 0.23) * 8
                RadialGradient(
                    colors: [
                        PostmarkTheme.lamp.opacity(0.34 * intensity),
                        PostmarkTheme.lamp.opacity(0.10 * intensity),
                        .clear,
                    ],
                    center: .init(x: 0.5, y: 0.18),
                    startRadius: 30, endRadius: 470
                )
                .offset(x: swayX, y: swayY)
                .blendMode(.plusLighter)
            }

            RadialGradient(
                colors: [.clear, PostmarkTheme.baizeDeep.opacity(0.7)],
                center: .center, startRadius: 170, endRadius: 560
            )
        }
        .ignoresSafeArea()
    }
}
