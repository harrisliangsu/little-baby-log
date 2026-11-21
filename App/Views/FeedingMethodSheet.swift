import BabyLogKit
import SwiftUI

/// Widget tap for nursing or formula. The choice does not create a record.
struct FeedingMethodSheet: View {
    var babyName: String
    var onPick: (HomeCard) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.uiLanguage) private var language

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(Copy.forBaby(babyName, language))
                    .font(.headline)
                    .accessibilityIdentifier("composer-baby")
                Button {
                    onPick(.breast)
                } label: {
                    Text(Copy.card(.breast, language))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("feed-choice-breast")
                Button {
                    onPick(.formula)
                } label: {
                    Text(Copy.card(.formula, language))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("feed-choice-formula")
                Spacer()
            }
            .padding(20)
            .navigationTitle(Copy.feedingChoice(language))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language == .zh ? "取消" : "Cancel") { dismiss() }
                        .accessibilityIdentifier("close-feed-method")
                }
            }
            .accessibilityIdentifier("feed-method")
        }
    }
}
