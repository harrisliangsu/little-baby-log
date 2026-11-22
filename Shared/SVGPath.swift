import SwiftUI

/// Draws one bundled Phosphor regular SVG. The file stays in the app; nothing is downloaded at runtime.
struct BundledIcon: View {
    var name: String
    var color: Color

    var body: some View {
        if let path = BundledIcon.path(named: name) {
            path.fill(color)
        } else {
            Circle().stroke(color, lineWidth: 1.5)
        }
    }

    static func path(named name: String) -> Path? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "svg", subdirectory: "Icons")
                ?? Bundle.main.url(forResource: name, withExtension: "svg") else { return nil }
        guard let text = try? String(contentsOf: url),
              let match = text.range(of: #"d="([^"]+)""#, options: .regularExpression) else { return nil }
        let raw = text[match]
        let d = raw.dropFirst(3).dropLast()
        return SVGPath(String(d)).path()
    }
}

struct SVGPath {
    var source: String

    func path() -> Path {
        var path = Path()
        let tokens = SVGPath.tokens(source)
        var index = 0
        var command: Character = "M"
        var current = CGPoint.zero
        var start = CGPoint.zero
        var cubicControl = CGPoint.zero
        var quadControl = CGPoint.zero

        func number() -> CGFloat? {
            guard index < tokens.count else { return nil }
            if let value = Double(tokens[index]) {
                index += 1
                return CGFloat(value)
            }
            return nil
        }
        func point(relative: Bool) -> CGPoint? {
            guard let x = number(), let y = number() else { return nil }
            return relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
        }

        while index < tokens.count {
            if tokens[index].count == 1, let letter = tokens[index].first, letter.isLetter {
                command = letter
                index += 1
            }
            let relative = command.isLowercase
            switch command.lowercased().first {
            case "m":
                guard let next = point(relative: relative) else { return path }
                path.move(to: next)
                current = next
                start = next
                command = relative ? "l" : "L"
            case "l":
                guard let next = point(relative: relative) else { return path }
                path.addLine(to: next)
                current = next
            case "h":
                guard let x = number() else { return path }
                current.x = relative ? current.x + x : x
                path.addLine(to: current)
            case "v":
                guard let y = number() else { return path }
                current.y = relative ? current.y + y : y
                path.addLine(to: current)
            case "c":
                guard let c1 = point(relative: relative), let c2 = point(relative: relative), let end = point(relative: relative) else { return path }
                path.addCurve(to: end, control1: c1, control2: c2)
                cubicControl = c2
                current = end
            case "s":
                guard let c2 = point(relative: relative), let end = point(relative: relative) else { return path }
                let c1 = CGPoint(x: 2 * current.x - cubicControl.x, y: 2 * current.y - cubicControl.y)
                path.addCurve(to: end, control1: c1, control2: c2)
                cubicControl = c2
                current = end
            case "q":
                guard let control = point(relative: relative), let end = point(relative: relative) else { return path }
                path.addQuadCurve(to: end, control: control)
                quadControl = control
                current = end
            case "t":
                guard let end = point(relative: relative) else { return path }
                let control = CGPoint(x: 2 * current.x - quadControl.x, y: 2 * current.y - quadControl.y)
                path.addQuadCurve(to: end, control: control)
                quadControl = control
                current = end
            case "a":
                guard let rx = number(), let ry = number(), let _ = number(), let large = number(), let sweep = number(), let end = point(relative: relative) else { return path }
                path.addArcApproximation(from: current, to: end, rx: rx, ry: ry, large: large != 0, sweep: sweep != 0)
                current = end
            case "z":
                path.closeSubpath()
                current = start
            default:
                index += 1
            }
            cubicControl = command.lowercased() == "c" || command.lowercased() == "s" ? cubicControl : current
        }
        return path
    }

    private static func tokens(_ source: String) -> [String] {
        var tokens: [String] = []
        var number = ""
        func flush() {
            if !number.isEmpty { tokens.append(number); number = "" }
        }
        for character in source {
            if character.isLetter {
                flush()
                tokens.append(String(character))
            } else if character == "-" && !number.isEmpty && number.last != "e" {
                flush()
                number.append(character)
            } else if character == "," || character.isWhitespace {
                flush()
            } else {
                number.append(character)
            }
        }
        flush()
        return tokens
    }
}

private extension Path {
    mutating func addArcApproximation(from start: CGPoint, to end: CGPoint, rx: CGFloat, ry: CGFloat, large: Bool, sweep: Bool) {
        let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = max(1, hypot(dx, dy))
        let bend: CGFloat = (large == sweep ? -1 : 1) * min(rx, ry) * 0.35
        let control = CGPoint(x: mid.x + (-dy / length) * bend, y: mid.y + (dx / length) * bend)
        addQuadCurve(to: end, control: control)
    }
}
