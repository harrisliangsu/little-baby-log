import SwiftUI
import BabyLogKit

/// A running sleep or nursing timer with a live clock.
struct ActiveTimerRow: View {
    @ObservedObject var event: LogEvent
    @Environment(\.appTheme) private var theme
    @Environment(\.uiLanguage) private var language
    let onWake: () -> Void
    let onOpen: () -> Void

    private var isNursing: Bool { event.kind == .breastfeed }

    var body: some View {
        HStack(spacing: 14) {
            KindIcon(kind: event.kind, size: 52)

            VStack(alignment: .leading, spacing: 2) {
                Text(isNursing ? (language == .zh ? "亲喂" : "Nursing") : (language == .zh ? "睡眠中" : "Sleeping"))
                    .font(.subheadline)
                    .foregroundStyle(theme.secondary)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(DurationFormat.clock(elapsed(at: context.date)))
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(theme.secondary)
            }

            Spacer(minLength: 8)

            Button {
                if isNursing { onOpen() } else { onWake() }
            } label: {
                Text(isNursing ? (language == .zh ? "打开" : "Open") : (language == .zh ? "醒来" : "Wake up"))
                    .font(.headline)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(minWidth: 72)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .themedOnColor()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(theme.color(for: event.kind))
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            if isNursing { onOpen() }
        }
    }

    private func elapsed(at now: Date) -> TimeInterval {
        if isNursing {
            return event.totalBreastSeconds(at: now)
        }
        return event.duration(at: now)
    }

    private var subtitle: String {
        if isNursing {
            if let side = event.activeSide {
                let name = side.title
                return language == .zh ? "\(name)进行中" : "\(name) side running"
            }
            return language == .zh ? "已暂停" : "Paused"
        }
        if let start = event.startDate {
            let clock = start.formatted(
                Date.FormatStyle(date: .omitted, time: .shortened)
                    .locale(Locale(identifier: language == .zh ? "zh-Hans" : "en"))
            )
            return language == .zh ? "从 \(clock)" : "Since \(clock)"
        }
        return ""
    }
}
