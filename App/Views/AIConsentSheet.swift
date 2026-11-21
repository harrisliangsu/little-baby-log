import SwiftUI
import BabyLogKit

/// Shows the provider, host, and exact text before anything is sent.
struct AIConsentSheet: View {
    let preview: AISendPreview
    var onApprove: () -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.storedDefault.rawValue

    private var language: ResolvedLanguage {
        (AppLanguage(rawValue: languageRaw) ?? .zhHans).resolved()
    }

    var body: some View {
        NavigationStack {
            List {
                LabeledContent(language == .zh ? "供应商" : "Provider", value: preview.provider.displayName)
                LabeledContent(language == .zh ? "地址" : "Host", value: preview.host)
                Text(preview.removedBabyNames
                     ? (language == .zh ? "宝宝姓名已换成 Baby。" : "Baby names were replaced with Baby.")
                     : (language == .zh ? "这段文字里没有匹配到已保存的宝宝姓名。" : "No saved baby name was found in this text."))
                    .font(.footnote)
                Text(preview.userText)
                    .font(.footnote)
                    .textSelection(.enabled)
                Text(language == .zh
                     ? "发送后由该供应商处理。本应用不声称对方零留存。取消则什么都不发。"
                     : "Sending gives this text to that provider. This app does not claim they keep nothing. Cancel sends nothing.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .navigationTitle(language == .zh ? "确认发送" : "Confirm send")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language == .zh ? "取消" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(language == .zh ? "发送" : "Send") {
                        onApprove()
                        dismiss()
                    }
                }
            }
        }
    }
}
