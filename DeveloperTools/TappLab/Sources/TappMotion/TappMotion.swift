import Foundation
import CoreGraphics

/// Geometry for an app-owned preview. These are view points, never HID deltas.
public struct TappMotion {
    public private(set) var position = CGPoint.zero
    public private(set) var target = CGPoint.zero
    public private(set) var bounds = CGSize.zero
    public private(set) var moving = false
    public let radius: Double = 16

    public init() {}

    public mutating func resize(_ size: CGSize) {
        guard size.width.isFinite, size.height.isFinite,
              size.width > radius * 2, size.height > radius * 2 else {
            bounds = .zero; position = .zero; target = .zero; moving = false
            return
        }
        bounds = size
        // A geometry change invalidates an old target; park in the new centre.
        position = CGPoint(x: size.width / 2, y: size.height / 2)
        target = position
        moving = false
    }

    public mutating func move(to point: CGPoint) {
        guard bounds != .zero, point.x.isFinite, point.y.isFinite else { return }
        target = CGPoint(x: min(bounds.width - radius, max(radius, point.x)),
                         y: min(bounds.height - radius, max(radius, point.y)))
        moving = position != target
    }

    public mutating func park() {
        move(to: CGPoint(x: bounds.width / 2, y: bounds.height / 2))
    }

    public mutating func stop() { target = position; moving = false }

    public mutating func step(seconds: Double) {
        guard moving, seconds.isFinite, seconds > 0 else { return }
        let dx = target.x - position.x, dy = target.y - position.y
        let distance = hypot(dx, dy)
        // Bound frame gaps so returning from a suspended app cannot teleport.
        let stride = min(distance, max(45, min(420, distance * 5)) * min(seconds, 0.05))
        if distance <= 0.5 || stride >= distance {
            position = target; moving = false
        } else {
            position.x += dx / distance * stride
            position.y += dy / distance * stride
        }
    }
}
