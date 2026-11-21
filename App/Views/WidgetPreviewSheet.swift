import BabyLogKit
import SwiftUI

struct WidgetPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.uiLanguage) private var language
    @State private var snapshot: WidgetSnapshot?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(language == .zh ? "这是主屏幕小组件读到的同一份记录，不是示例数据。" : "This is the same record the Home Screen widget reads. It is not sample data.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let baby = snapshot?.babies.first {
                        CareSummaryView(baby: baby, language: snapshot?.resolvedLanguage ?? .zh)
                            .padding(16)
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    } else {
                        Text(Zh.emptyBaby)
                            .accessibilityIdentifier("widget-summary")
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(language == .zh ? "小组件" : "Widget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(language == .zh ? "完成" : "Done") { dismiss() }
                        .accessibilityIdentifier("close-widget-preview")
                }
            }
            .onAppear(perform: reload)
        }
    }

    private func reload() {
        WidgetSnapshotWriter.shared.refresh()
        guard let url = AppGroup.snapshotURL else {
            snapshot = nil
            return
        }
        snapshot = WidgetSnapshot.read(from: url)
    }
}
