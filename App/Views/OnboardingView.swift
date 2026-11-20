import SwiftUI
import BabyLogKit

struct OnboardingView: View {
    let onCreate: (String, Date) -> Void

    @Environment(\.appTheme) private var theme

    @State private var name = ""
    @State private var birthDate = Date.now
    @FocusState private var nameFocused: Bool

    private var latestBirthDate: Date {
        Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        KindIcon(kind: .sleep, size: 52)
                        KindIcon(kind: .breastfeed, size: 52)
                        KindIcon(kind: .diaper, size: 52)
                    }
                    Text("欢迎使用宝宝小记")
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                    Text("亲喂、奶粉、尿布和睡眠，点一下就记下来。免费、离线可用，iCloud 可以以后再开。")
                        .font(.body)
                        .foregroundStyle(theme.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 32)

                VStack(spacing: 0) {
                    TextField("宝宝名字", text: $name)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .focused($nameFocused)
                        .font(.title3)
                        .padding(16)
                        .accessibilityIdentifier("baby-name")
                    Divider()
                    DatePicker(
                        "生日",
                        selection: $birthDate,
                        in: ...latestBirthDate,
                        displayedComponents: .date
                    )
                    .font(.title3)
                    .padding(16)
                }
                .background(theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                Button {
                    Haptics.success()
                    onCreate(trimmedName, birthDate)
                } label: {
                    Text("开始记录")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .themedOnColor()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(trimmedName.isEmpty)
                .accessibilityIdentifier("start-tracking")

                Text("如果另一位照顾者邀请了你，在这台手机上打开邀请。iCloud 同步后，宝宝会出现在这里。没登录 iCloud 也可以先在本地记。")
                    .font(.footnote)
                    .foregroundStyle(theme.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(theme.background)
        .themedForeground()
    }
}

#Preview {
    OnboardingView { _, _ in }
}
