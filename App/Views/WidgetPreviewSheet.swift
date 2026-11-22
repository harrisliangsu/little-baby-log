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
                        Text(language == .zh ? "固定尺寸里的已选项目" : "Selected items at widget size")
                            .font(.subheadline.weight(.semibold))
                        densitySample(count: 1, size: .small, width: 158, height: 158, identifier: "widget-sample-small-1")
                        densitySample(count: 2, size: .small, width: 158, height: 158, identifier: "widget-sample-small-2")
                        densitySample(count: 6, size: .small, width: 158, height: 158, identifier: "widget-sample-small-6")
                        densitySample(count: 4, size: .medium, width: 338, height: 158, identifier: "widget-sample-medium-4")
                        densitySample(count: 6, size: .medium, width: 338, height: 158, identifier: "widget-sample-medium-6")
                        densitySample(count: 6, size: .large, width: 338, height: 354, identifier: "widget-sample-large-6")
                        densitySample(count: 6, size: .small, width: 158, height: 158, identifier: "widget-sample-dark-6")
                            .environment(\.colorScheme, .dark)
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

    /// Point sizes are the tighter iPhone Home Screen widget bounds, not a lock-screen family.
    private func densitySample(count: Int, size: WidgetSize, width: CGFloat, height: CGFloat, identifier: String) -> some View {
        let cards = Array(HomeCard.allCases.prefix(count))
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var care = CareRollup()
        care.lastFormulaAt = now.addingTimeInterval(-90)
        care.lastFormulaML = 1250
        care.today.formulaML = 1250
        care.today.formulaCount = 3
        care.lastSleepAt = now.addingTimeInterval(-3600)
        care.today.sleepSeconds = (12 * 60 + 40) * 60
        care.today.sleepCount = 1
        care.lastWetAt = now.addingTimeInterval(-600)
        care.today.wetCount = 4
        let model = WidgetBoard.face(
            babyName: "贝贝",
            care: care,
            recent: [],
            reminder: nil,
            cards: cards,
            size: size,
            language: .zh,
            volume: .milliliters,
            now: now
        )
        return CareBoardFace(face: model, size: size, destination: nil, marksSizeIdentifier: false)
            .padding(8)
            .frame(width: width, height: height, alignment: .topLeading)
            .clipped()
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(identifier)
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
