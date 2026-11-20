import SwiftUI

/// Evergreen's mascot: a round, friendly pine with a happy face, rosy cheeks
/// and a pair of running shoes. Drawn in code on a 100 × 130 grid so it stays
/// crisp at any size. Used for the app mark, the Welcome art and the week's
/// progress, where each finished workout fills a tier from the bottom up.
struct PineBuddy: View {
    enum Pose { case standing, running, cheering, walking }

    var pose: Pose = .standing
    /// Tiers filled, bottom up (0–3). nil fills all three.
    var filled: Int? = nil
    /// Where the walk cycle is, -1…1 (walking only).
    var stride: Double = 0

    var body: some View {
        Canvas { context, size in
            let s = min(size.width / 100, size.height / 130)
            context.translateBy(x: (size.width - 100 * s) / 2, y: (size.height - 130 * s) / 2)
            context.scaleBy(x: s, y: s)
            if pose == .walking {
                // A small bob on each step and a slight lean into the stride.
                context.translateBy(x: 0, y: -abs(stride) * 2.5)
                context.translateBy(x: 50, y: 100)
                context.rotate(by: .degrees(stride * 3))
                context.translateBy(x: -50, y: -100)
            }
            draw(in: &context)
        }
        .aspectRatio(100 / 130, contentMode: .fit)
        .accessibilityHidden(true)
    }

    // MARK: Drawing

    private static let leaf = Color(red: 0.36, green: 0.67, blue: 0.51)
    private static let line = Color(red: 0.09, green: 0.29, blue: 0.23)
    private static let trunk = Color(red: 0.55, green: 0.37, blue: 0.25)
    private static let blush = Color(red: 0.96, green: 0.62, blue: 0.62)
    private static let shoe = Color(red: 0.95, green: 0.47, blue: 0.36)

    private func draw(in context: inout GraphicsContext) {
        let stroke = StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round)

        // Legs and shoes sit behind the trunk.
        for leg in legs {
            var path = Path()
            path.move(to: leg.hip)
            path.addLine(to: leg.foot)
            context.stroke(path, with: .color(Self.line), style: stroke)
            drawShoe(at: leg.foot, angle: leg.shoeAngle, in: &context)
        }

        // Trunk.
        let trunk = Path(roundedRect: CGRect(x: 44, y: 88, width: 12, height: 12), cornerRadius: 2)
        context.fill(trunk, with: .color(Self.trunk))
        context.stroke(trunk, with: .color(Self.line), style: stroke)

        // Arms, behind the tiers.
        for arm in arms {
            var path = Path()
            path.move(to: arm.0)
            path.addQuadCurve(to: arm.2, control: arm.1)
            context.stroke(path, with: .color(Self.line), style: stroke)
            context.fill(Path(ellipseIn: CGRect(x: arm.2.x - 2.6, y: arm.2.y - 2.6, width: 5.2, height: 5.2)),
                         with: .color(Self.line))
        }

        // Tiers, bottom first so the upper ones overlap.
        let tiers: [(tip: CGFloat, base: CGFloat, half: CGFloat, scallops: Int)] = [
            (46, 92, 42, 5), (24, 68, 32, 4), (4, 42, 22, 3),
        ]
        for (index, tier) in tiers.enumerated() {
            let path = tierPath(tip: tier.tip, base: tier.base, half: tier.half, scallops: tier.scallops)
            let solid = filled.map { index < $0 } ?? true
            context.fill(path, with: .color(solid ? Self.leaf : Theme.surface))
            context.stroke(path, with: .color(Self.line), style: stroke)
        }

        // Face, on the bottom tier.
        for x in [40.0, 60.0] {
            context.fill(Path(ellipseIn: CGRect(x: x - 3.4, y: 74, width: 6.8, height: 7.4)), with: .color(Self.line))
            context.fill(Path(ellipseIn: CGRect(x: x - 1.6, y: 75.2, width: 2.4, height: 2.4)), with: .color(.white))
        }
        for x in [31.0, 69.0] {
            context.fill(Path(ellipseIn: CGRect(x: x - 4.5, y: 81, width: 9, height: 5)), with: .color(Self.blush.opacity(0.85)))
        }
        var smile = Path()
        smile.addArc(center: CGPoint(x: 50, y: 81), radius: 4.5,
                     startAngle: .degrees(20), endAngle: .degrees(160), clockwise: false)
        context.stroke(smile, with: .color(Self.line), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
    }

    /// A soft pine tier: rounded tip, rounded corners and a scalloped hem.
    private func tierPath(tip: CGFloat, base: CGFloat, half: CGFloat, scallops: Int) -> Path {
        Path { p in
            p.move(to: CGPoint(x: 47, y: tip + 5))
            p.addQuadCurve(to: CGPoint(x: 53, y: tip + 5), control: CGPoint(x: 50, y: tip - 1))
            p.addLine(to: CGPoint(x: 50 + half, y: base - 4))
            p.addQuadCurve(to: CGPoint(x: 50 + half - 6, y: base), control: CGPoint(x: 50 + half + 1, y: base + 1))
            // Scallops right to left between the rounded corners.
            let left = 50 - half + 6
            let right = 50 + half - 6
            let width = (right - left) / CGFloat(scallops)
            for i in 0..<scallops {
                let from = right - width * CGFloat(i)
                let to = from - width
                p.addQuadCurve(to: CGPoint(x: to, y: base), control: CGPoint(x: (from + to) / 2, y: base + 6))
            }
            p.addQuadCurve(to: CGPoint(x: 50 - half, y: base - 4), control: CGPoint(x: 50 - half - 1, y: base + 1))
            p.closeSubpath()
        }
    }

    /// A running shoe: a coral upper with a white sole, toe pointing forward.
    private func drawShoe(at foot: CGPoint, angle: Double, in context: inout GraphicsContext) {
        var shoe = context
        shoe.translateBy(x: foot.x, y: foot.y)
        shoe.rotate(by: .degrees(angle))
        let upper = Path { p in
            p.move(to: CGPoint(x: -6, y: 1))
            p.addQuadCurve(to: CGPoint(x: -3, y: -5), control: CGPoint(x: -7, y: -5))
            p.addLine(to: CGPoint(x: 1, y: -5))
            p.addQuadCurve(to: CGPoint(x: 9, y: 1), control: CGPoint(x: 8, y: -3))
            p.closeSubpath()
        }
        let sole = Path(roundedRect: CGRect(x: -7, y: 0.5, width: 17, height: 3.6), cornerRadius: 1.8)
        shoe.fill(upper, with: .color(Self.shoe))
        shoe.fill(sole, with: .color(.white))
        let outline = StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
        shoe.stroke(upper, with: .color(Self.line), style: outline)
        shoe.stroke(sole, with: .color(Self.line), style: outline)
        // Laces.
        var laces = Path()
        laces.move(to: CGPoint(x: -1, y: -4))
        laces.addLine(to: CGPoint(x: 1, y: -1.5))
        laces.move(to: CGPoint(x: 2, y: -4))
        laces.addLine(to: CGPoint(x: 4, y: -1.5))
        shoe.stroke(laces, with: .color(.white), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
    }

    private var legs: [(hip: CGPoint, foot: CGPoint, shoeAngle: Double)] {
        switch pose {
        case .running:
            [(CGPoint(x: 46, y: 99), CGPoint(x: 36, y: 114), 12),
             (CGPoint(x: 54, y: 99), CGPoint(x: 64, y: 110), -18)]
        case .walking:
            [(CGPoint(x: 46, y: 99), CGPoint(x: 44 + stride * 7, y: 116 - max(0, stride) * 3), stride * 10),
             (CGPoint(x: 54, y: 99), CGPoint(x: 56 - stride * 7, y: 116 - max(0, -stride) * 3), -stride * 10)]
        case .standing, .cheering:
            [(CGPoint(x: 46, y: 99), CGPoint(x: 42, y: 116), 0),
             (CGPoint(x: 54, y: 99), CGPoint(x: 58, y: 116), 0)]
        }
    }

    /// Shoulder, bend, hand.
    private var arms: [(CGPoint, CGPoint, CGPoint)] {
        switch pose {
        case .cheering:
            [(CGPoint(x: 22, y: 64), CGPoint(x: 12, y: 60), CGPoint(x: 9, y: 48)),
             (CGPoint(x: 78, y: 64), CGPoint(x: 88, y: 60), CGPoint(x: 91, y: 48))]
        case .running:
            [(CGPoint(x: 22, y: 64), CGPoint(x: 12, y: 66), CGPoint(x: 10, y: 56)),
             (CGPoint(x: 78, y: 64), CGPoint(x: 88, y: 70), CGPoint(x: 92, y: 76))]
        case .walking:
            [(CGPoint(x: 22, y: 64), CGPoint(x: 14, y: 70), CGPoint(x: 12 - stride * 4, y: 78)),
             (CGPoint(x: 78, y: 64), CGPoint(x: 86, y: 70), CGPoint(x: 88 + stride * 4, y: 78))]
        case .standing:
            []
        }
    }
}

/// The pine buddy walking in place, for the home screen. Still under Reduce Motion.
struct WalkingBuddy: View {
    var filled: Int? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            PineBuddy(pose: .standing, filled: filled)
        } else {
            TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                PineBuddy(pose: .walking, filled: filled, stride: sin(t * 2 * .pi * 1.1))
            }
        }
    }
}

#Preview {
    HStack {
        PineBuddy(pose: .standing).frame(height: 160)
        PineBuddy(pose: .running).frame(height: 160)
        PineBuddy(pose: .cheering, filled: 1).frame(height: 160)
    }
    .padding()
    .background(Theme.surface)
}
