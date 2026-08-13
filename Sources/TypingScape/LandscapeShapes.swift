import SwiftUI

/// Hand-drawn vector silhouettes for the "basic shape" and "landscape"
/// presets — no photo/Vision pipeline involved, so these are always crisp
/// and instant, unlike the photo-derived presets.
struct TriangleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct StarShape: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = min(rect.width, rect.height) / 2
        let innerRadius = outerRadius * 0.42
        var points: [CGPoint] = []
        for i in 0..<10 {
            let angle = Double(i) * .pi / 5 - .pi / 2
            let r = i % 2 == 0 ? outerRadius : innerRadius
            points.append(CGPoint(x: center.x + CGFloat(cos(angle)) * r, y: center.y + CGFloat(sin(angle)) * r))
        }
        var path = Path()
        path.move(to: points[0])
        for point in points.dropFirst() { path.addLine(to: point) }
        path.closeSubpath()
        return path
    }
}

/// Single-peak mountain silhouette, jagged but continuously widening from
/// peak to base on both sides — the earlier version placed its "shoulders"
/// close to the peak, so most of the lower body ended up nearly full-width
/// (a pointy hat on a rectangle) instead of a real taper.
struct MountainIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var path = Path()
        path.move(to: CGPoint(x: 0, y: h))
        path.addLine(to: CGPoint(x: w * 0.10, y: h * 0.82))
        path.addLine(to: CGPoint(x: w * 0.22, y: h * 0.88))
        path.addLine(to: CGPoint(x: w * 0.33, y: h * 0.68))
        path.addLine(to: CGPoint(x: w * 0.43, y: h * 0.74))
        path.addLine(to: CGPoint(x: w * 0.50, y: h * 0.12))
        path.addLine(to: CGPoint(x: w * 0.58, y: h * 0.60))
        path.addLine(to: CGPoint(x: w * 0.68, y: h * 0.52))
        path.addLine(to: CGPoint(x: w * 0.78, y: h * 0.76))
        path.addLine(to: CGPoint(x: w * 0.90, y: h * 0.84))
        path.addLine(to: CGPoint(x: w, y: h))
        path.closeSubpath()
        return path
    }
}

/// Simple pitched-roof house pictogram.
struct HouseShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let roofY = h * 0.42
        var path = Path()
        path.move(to: CGPoint(x: w * 0.5, y: 0))
        path.addLine(to: CGPoint(x: w, y: roofY))
        path.addLine(to: CGPoint(x: w * 0.85, y: roofY))
        path.addLine(to: CGPoint(x: w * 0.85, y: h))
        path.addLine(to: CGPoint(x: w * 0.15, y: h))
        path.addLine(to: CGPoint(x: w * 0.15, y: roofY))
        path.addLine(to: CGPoint(x: 0, y: roofY))
        path.closeSubpath()
        return path
    }
}

/// A winding vertical band standing in for a river.
struct RiverShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let band = w * 0.28
        var path = Path()
        path.move(to: CGPoint(x: w * 0.5 - band / 2, y: 0))
        path.addCurve(
            to: CGPoint(x: w * 0.3, y: h * 0.5),
            control1: CGPoint(x: w * 0.15, y: h * 0.2), control2: CGPoint(x: w * 0.15, y: h * 0.35)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.5 - band / 2, y: h),
            control1: CGPoint(x: w * 0.5, y: h * 0.65), control2: CGPoint(x: w * 0.85, y: h * 0.8)
        )
        path.addLine(to: CGPoint(x: w * 0.5 + band / 2, y: h))
        path.addCurve(
            to: CGPoint(x: w * 0.7, y: h * 0.5),
            control1: CGPoint(x: w * 0.85 + band / 2, y: h * 0.8), control2: CGPoint(x: w * 0.5 + band, y: h * 0.65)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.5 + band / 2, y: 0),
            control1: CGPoint(x: w * 0.15 + band, y: h * 0.35), control2: CGPoint(x: w * 0.15 + band, y: h * 0.2)
        )
        path.closeSubpath()
        return path
    }
}

/// A wavy horizon with solid fill below it, standing in for the sea. `phase`
/// staggers each of the 4 humps a quarter-cycle apart, so animating it
/// upward over time makes the crests rise and fall in sequence — a wave
/// visibly rolling through — rather than the whole horizon pulsing at once.
struct SeaShape: Shape {
    var phase: Double = 0

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let waterline = h * 0.4
        let amplitude = h * 0.14
        var path = Path()
        path.move(to: CGPoint(x: 0, y: waterline))
        let waveCount = 4
        let waveWidth = w / CGFloat(waveCount)
        for i in 0..<waveCount {
            let startX = CGFloat(i) * waveWidth
            let crestHeight = amplitude * CGFloat(sin(phase + Double(i) * .pi / 2))
            path.addCurve(
                to: CGPoint(x: startX + waveWidth, y: waterline),
                control1: CGPoint(x: startX + waveWidth * 0.25, y: waterline - crestHeight),
                control2: CGPoint(x: startX + waveWidth * 0.75, y: waterline + crestHeight)
            )
        }
        path.addLine(to: CGPoint(x: w, y: h))
        path.addLine(to: CGPoint(x: 0, y: h))
        path.closeSubpath()
        return path
    }
}
