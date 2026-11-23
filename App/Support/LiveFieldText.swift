import UIKit

enum LiveFieldText {
    /// The characters currently drawn in the field, including while it still has focus.
    /// Nil when that field is not on screen.
    @MainActor
    static func text(identifier: String) -> String? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for window in scenes.flatMap(\.windows) {
            if let field = find(identifier: identifier, in: window) {
                return field.text ?? ""
            }
        }
        return nil
    }

    @MainActor
    private static func find(identifier: String, in view: UIView) -> UITextField? {
        if view.accessibilityIdentifier == identifier {
            if let field = view as? UITextField { return field }
            if let field = firstTextField(in: view) { return field }
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
