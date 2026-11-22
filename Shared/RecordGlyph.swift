import SwiftUI

/// Original line marks. Phosphor's spiral and half-drop were not clear enough for stool or a diaper change.
struct RecordGlyph: View {
    var name: String
    var color: Color

    var body: some View {
        switch name {
        case "dirty-mark":
            DirtyMark().fill(color)
        case "diaper-mark":
            DiaperMark().fill(color)
        default:
            BundledIcon(name: name, color: color)
        }
    }
}

private struct DirtyMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        path.addEllipse(in: CGRect(x: w * 0.18, y: h * 0.34, width: w * 0.42, height: h * 0.42))
        path.addEllipse(in: CGRect(x: w * 0.40, y: h * 0.22, width: w * 0.40, height: h * 0.40))
        return path
    }
}

private struct DiaperMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        path.move(to: CGPoint(x: w * 0.22, y: h * 0.28))
        path.addLine(to: CGPoint(x: w * 0.78, y: h * 0.28))
        path.addQuadCurve(to: CGPoint(x: w * 0.70, y: h * 0.78), control: CGPoint(x: w * 0.92, y: h * 0.62))
        path.addQuadCurve(to: CGPoint(x: w * 0.30, y: h * 0.78), control: CGPoint(x: w * 0.50, y: h * 0.92))
        path.addQuadCurve(to: CGPoint(x: w * 0.22, y: h * 0.28), control: CGPoint(x: w * 0.08, y: h * 0.62))
        path.closeSubpath()
        return path
    }
}
