import SwiftUI

/// A soft organic blob that slowly morphs, breathes, and shifts its
/// internal gradient. The centre stays solid; the rim fades and glows
/// so the silhouette never reads as a hard cut. All motion is
/// deterministic (sine/cosine driven) so the shape never jitters.
struct TangentOrb: View {
    /// When true the orb renders a single static frame.
    var reduceMotion: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 40.0, paused: reduceMotion)) { context in
            let time = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate * 1.2
            orb(at: time)
        }
    }

    @ViewBuilder
    private func orb(at time: TimeInterval) -> some View {
        let shape = OrbShape(time: time, deformation: reduceMotion ? 0 : 1)
        let breathing = reduceMotion ? 1 : 1 + 0.018 * sin(time * 0.45)
        let gradientCenter = UnitPoint(
            x: 0.5 + (reduceMotion ? 0 : 0.07 * sin(time * 0.13 + 1.0)),
            y: 0.44 + (reduceMotion ? 0 : 0.07 * cos(time * 0.11))
        )
        let skyCenter = UnitPoint(
            x: 0.32 + (reduceMotion ? 0 : 0.05 * cos(time * 0.09)),
            y: 0.3 + (reduceMotion ? 0 : 0.05 * sin(time * 0.08 + 2.0))
        )

        GeometryReader { proxy in
            let radius = min(proxy.size.width, proxy.size.height) / 2

            ZStack {
                shape
                    .fill(Color.tangentPurple.opacity(0.42))
                    .blur(radius: radius * 0.16)
                    .scaleEffect(1.1)

                shape
                    .fill(Color.tangentLilac.opacity(0.42))
                    .blur(radius: radius * 0.07)
                    .scaleEffect(1.03)

                // Solid through the centre, then a longer fade so the rim
                // never reads as a hard cut.
                shape
                    .fill(
                        RadialGradient(
                            gradient: Gradient(stops: [
                                .init(color: .tangentLilac, location: 0),
                                .init(color: .tangentPurple, location: 0.48),
                                .init(color: .tangentPurple.opacity(0.92), location: 0.7),
                                .init(color: .tangentPurple.opacity(0.45), location: 0.88),
                                .init(color: .tangentPurple.opacity(0.12), location: 0.97),
                                .init(color: .tangentPurple.opacity(0), location: 1),
                            ]),
                            center: gradientCenter,
                            startRadius: 0,
                            endRadius: radius
                        )
                    )
                    .overlay {
                        shape.fill(
                            RadialGradient(
                                colors: [Color.tangentSky.opacity(0.12), .clear],
                                center: skyCenter,
                                startRadius: 0,
                                endRadius: radius * 0.85
                            )
                        )
                    }
                    .blur(radius: radius * 0.02)
            }
        }
        .scaleEffect(breathing)
        .accessibilityHidden(true)
    }
}

/// A closed blob outline built from a small set of perimeter points whose
/// radii oscillate with slow, individually phased sine waves. Points are
/// joined with Catmull-Rom derived cubic Béziers so edges stay smooth.
private struct OrbShape: Shape {
    var time: TimeInterval
    /// 0 disables deformation entirely (Reduce Motion), 1 is full (subtle) motion.
    var deformation: Double

    /// One entry per perimeter point: (speed rad/s, phase rad, amplitude as
    /// a fraction of the base radius). Low frequencies, small amplitudes.
    private static let waves: [(speed: Double, phase: Double, amplitude: Double)] = [
        (0.31, 0.0, 0.11),
        (0.43, 1.1, 0.096),
        (0.27, 2.4, 0.12),
        (0.51, 3.2, 0.09),
        (0.37, 4.5, 0.105),
        (0.47, 5.3, 0.094),
        (0.29, 0.7, 0.115),
    ]

    func path(in rect: CGRect) -> Path {
        let points = perimeterPoints(in: rect)
        let count = points.count

        var path = Path()
        path.move(to: points[0])
        for index in 0..<count {
            let p0 = points[(index - 1 + count) % count]
            let p1 = points[index]
            let p2 = points[(index + 1) % count]
            let p3 = points[(index + 2) % count]
            let control1 = CGPoint(
                x: p1.x + (p2.x - p0.x) / 6,
                y: p1.y + (p2.y - p0.y) / 6
            )
            let control2 = CGPoint(
                x: p2.x - (p3.x - p1.x) / 6,
                y: p2.y - (p3.y - p1.y) / 6
            )
            path.addCurve(to: p2, control1: control1, control2: control2)
        }
        path.closeSubpath()
        return path
    }

    private func perimeterPoints(in rect: CGRect) -> [CGPoint] {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        // Leave headroom so the deformed blob never clips its frame.
        let baseRadius = min(rect.width, rect.height) / 2 * 0.80
        let count = Self.waves.count

        return Self.waves.enumerated().map { index, wave in
            let angle = 2 * .pi * Double(index) / Double(count)
            // Two harmonics per point for an organic, non-repetitive feel.
            let primary = wave.amplitude * sin(time * wave.speed + wave.phase)
            let secondary = wave.amplitude * 0.65 * sin(time * wave.speed * 0.63 + wave.phase * 2)
            let radius = baseRadius * (1 + deformation * (primary + secondary))
            return CGPoint(
                x: center.x + radius * cos(angle),
                y: center.y + radius * sin(angle)
            )
        }
    }
}

#Preview("Animated") {
    TangentOrb(reduceMotion: false)
        .frame(width: 220, height: 220)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.tangentWash)
}

#Preview("Reduce Motion") {
    TangentOrb(reduceMotion: true)
        .frame(width: 220, height: 220)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.tangentWash)
}
