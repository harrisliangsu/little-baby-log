import SwiftUI
import BabyLogKit

struct OnboardingView: View {
    let onCreate: (String, Date) -> Void

    @Environment(\.appTheme) private var theme
    @Environment(\.uiLanguage) private var language

    @State private var name = ""
    @State private var birthDate = Date.now
    @FocusState private var nameFocused: Bool

    private var latestBirthDate: Date {
        Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now
    }

    private var trimmedName: String {
        let live = (LiveFieldText.text(identifier: "baby-name") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !live.isEmpty { return live }
        return name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func begin() {
        let typed = trimmedName
        guard !typed.isEmpty else { return }
        Haptics.success()
        onCreate(typed, birthDate)
    }

    var body: some View {
        NavigationStack {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        KindIcon(kind: .sleep, size: 52)
                        KindIcon(kind: .breastfeed, size: 52)
                        KindIcon(kind: .diaper, size: 52)
                    }
                    Text(UICopy.t(.welcome, language))
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 32)

                VStack(spacing: 0) {
                    TextField(UICopy.t(.babyName, language), text: $name)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .focused($nameFocused)
                        .font(.title3)
                        .padding(16)
                        .accessibilityIdentifier("baby-name")
                    Divider()
                    DatePicker(
                        UICopy.t(.birthday, language),
                        selection: $birthDate,
                        in: ...latestBirthDate,
                        displayedComponents: .date
                    )
                    .font(.title3)
                    .padding(16)
                }
                .background(theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                Button(action: begin) label: {
                    Text(UICopy.t(.startTracking, language))
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .themedOnColor()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(trimmedName.isEmpty)
                .accessibilityIdentifier("start-tracking")
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(theme.background)
        .themedForeground()
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Button(action: begin) {
                    Text(UICopy.t(.startTracking, language))
                        .frame(minWidth: 88, minHeight: 44)
                }
                .disabled(trimmedName.isEmpty)
                .accessibilityIdentifier("start-tracking-key")
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        }
    }
}

#Preview {
    OnboardingView { _, _ in }
}
