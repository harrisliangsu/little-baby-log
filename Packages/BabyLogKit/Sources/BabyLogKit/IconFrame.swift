import CoreGraphics
import Foundation

/// Phosphor paths are drawn in a 256-point box. Fitting that box into the view
/// keeps the stroke inside the icon instead of painting the raw coordinates.
public struct IconPlacement: Equatable, Sendable {
    public static let viewBox: CGFloat = 256

    public var scale: CGFloat
    public var originX: CGFloat
    public var originY: CGFloat

    public static func fitting(into width: CGFloat, height: CGFloat, viewBox: CGFloat = viewBox) -> IconPlacement {
        let side = max(viewBox, 1)
        let scale = min(max(width, 0), max(height, 0)) / side
        let drawn = side * scale
        return IconPlacement(
            scale: scale,
            originX: (width - drawn) / 2,
            originY: (height - drawn) / 2
        )
    }

    public func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: originX + x * scale, y: originY + y * scale)
    }

    /// Every corner of the source box lands inside the destination, including a zero-size box.
    public func viewBoxFits(width: CGFloat, height: CGFloat, viewBox: CGFloat = viewBox) -> Bool {
        let corners = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: viewBox, y: 0),
            CGPoint(x: 0, y: viewBox),
            CGPoint(x: viewBox, y: viewBox),
        ]
        return corners.allSatisfy { corner in
            let placed = point(corner.x, corner.y)
            return placed.x >= -0.01 && placed.y >= -0.01
                && placed.x <= width + 0.01 && placed.y <= height + 0.01
        }
    }
}
