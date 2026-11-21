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
                    if let baby = snapshot?.babies.first {
                        let resolved = snapshot?.resolvedLanguage ?? language
                        let volume = snapshot?.volumeUnit ?? .milliliters
                        CareSummaryView(baby: baby, language: resolved)
                            .padding(16)
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        face(baby, size: .small, language: resolved, volume: volume)
                        face(baby, size: .medium, language: resolved, volume: volume)
                        face(baby, size: .large, language: resolved, volume: volume)
                        face(baby, size: .small, language: resolved, volume: volume)
                            .padding(8)
                            .background(Color(.systemBackground))
                            .environment(\.colorScheme, .dark)
                            .environment(\.dynamicTypeSize, .accessibility3)
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("widget-face-check")
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

    private func face(_ baby: WidgetSnapshot.BabySummary, size: WidgetSize, language: ResolvedLanguage, volume: VolumeUnit) -> some View {
        let model = WidgetFace.make(
            baby: baby,
            cards: [.formula, .wet, .dirty],
            size: size,
            language: language,
            volume: volume,
            now: .now,
            missingBaby: false
        )
        return CareBoardFace(face: model, size: size, destination: nil)
            .padding(12)
            .frame(minHeight: size == .large ? 280 : 140)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
