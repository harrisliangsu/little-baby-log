import UIKit

enum LiveFieldText {
    /// The characters currently drawn in the field, including while it still has focus.
    /// Nil when that field is not on screen.
    @MainActor
    static func text(identifier: String) -> String? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for window in scenes.flatMap(\.windows) {
            if let text = find(identifier: identifier, in: window) {
                return text
            }
        }
        return nil
    }

    /// SwiftUI can draw the digits while `UITextField.text` is still empty. The accessibility value is what is on screen.
    @MainActor
    private static func find(identifier: String, in view: UIView) -> String? {
        if view.accessibilityIdentifier == identifier {
            let drawn = (view as? UITextField)?.text ?? firstTextField(in: view)?.text ?? ""
            if !drawn.isEmpty { return drawn }
            let spoken = view.accessibilityValue ?? ""
            if !spoken.isEmpty { return spoken }
            return drawn
        }
        for child in view.subviews {
            if let found = find(identifier: identifier, in: child) {
                return found
            }
        }
        return nil
    }

    @MainActor
    private static func firstTextField(in view: UIView) -> UITextField? {
        if let field = view as? UITextField { return field }
        for child in view.subviews {
            if let found = firstTextField(in: child) { return found }
        }
        return nil
    }
}
