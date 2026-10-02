import CoreGraphics
import Foundation

// MARK: - Federn für die Kamera

/// Kritisch gedämpfte Feder (SmoothDamp). Läuft weich an und weich aus, schwingt nicht über
/// und verhält sich bei jeder Bildrate gleich. `smoothTime` ist grob die Zeit, bis das Ziel
/// zu gut der Hälfte erreicht ist; nach der doppelten Zeit sind es rund 90 %.
struct SmoothSpring {
    private(set) var value: CGFloat
    private(set) var velocity: CGFloat = 0

    init(_ value: CGFloat) {
        self.value = value
    }

    @discardableResult
    mutating func update(to target: CGFloat, smoothTime: CGFloat, dt: CGFloat) -> CGFloat {
        guard dt > 0 else { return value }
        let omega = 2 / max(0.0001, smoothTime)
        let x = omega * dt
        let decay = 1 / (1 + x + 0.48 * x * x + 0.235 * x * x * x)
        let change = value - target
        let temp = (velocity + omega * change) * dt
        velocity = (velocity - omega * temp) * decay
        value = target + (change + temp) * decay
        return value
    }

    /// Sofort auf einen Wert setzen, ohne Restbewegung.
    mutating func snap(to v: CGFloat) {
        value = v
        velocity = 0
    }
}

/// Feder für Winkel (Bogenmaß), nimmt immer den kürzeren Weg.
struct SmoothAngle {
    private var spring: SmoothSpring

    init(_ angle: CGFloat) {
        spring = SmoothSpring(angle)
    }

    var value: CGFloat { spring.value }

    @discardableResult
    mutating func update(to target: CGFloat, smoothTime: CGFloat, dt: CGFloat) -> CGFloat {
        // Ziel auf die Umdrehung des aktuellen Werts holen
        let d = (target - spring.value).remainder(dividingBy: 2 * CGFloat.pi)
        return spring.update(to: spring.value + d, smoothTime: smoothTime, dt: dt)
    }

    mutating func snap(to angle: CGFloat) {
        spring.snap(to: angle)
    }
}

/// Bildratenunabhängiges exponentielles Annähern, Ersatz für `x += (t - x) * min(1, dt * rate)`.
func smoothApproach(_ value: CGFloat, _ target: CGFloat, rate: CGFloat, dt: CGFloat) -> CGFloat {
    value + (target - value) * (1 - exp(-rate * dt))
}
