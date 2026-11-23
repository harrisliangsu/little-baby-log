import SwiftUI
import BabyLogKit

/// One bottom bar for the four existing tabs and the voice control.
/// A separate floating button sat on a different material and covered the list.
struct DockBar: View {
    @Environment(\.interfaceStyle) private var interfaceStyle
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Binding var tab: MainTab
    let language: ResolvedLanguage
    let voice: VoiceSession
    let noticeAck: Bool
    let onNotice: () -> Void
    let onBlocked: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            dockTab(.today, Copy.today(language), "sun.max.fill")
            dockTab(.history, language == .zh ? "历史" : "History", "calendar")
            voiceControl
            dockTab(.trends, language == .zh ? "趋势" : "Trends", "chart.bar.fill")
            dockTab(.settings, Copy.settings(language), "gearshape.fill")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(dockBackground)
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    private func dockTab(_ value: MainTab, _ title: String, _ symbol: String) -> some View {
        Button {
            tab = value
        } label: {
            VStack(spacing: 2) {
                Image(systemName: symbol)
                    .font(.body.weight(.semibold))
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(tab == value ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityIdentifier("dock-\(value.id)")
    }

    private var voiceControl: some View {
        Image(systemName: "mic.fill")
            .font(.title2.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 56, height: 56)
            .background(Circle().fill(voice.machine.cancelArmed ? Color.red : Color.accentColor))
            .contentShape(Circle())
            .gesture(hold)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("voice-log")
            .accessibilityLabel(language == .zh ? "按住说话" : "Hold to talk")
    }

    private var hold: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if voice.machine.phase == .idle || voice.machine.phase == .denied {
                    if AIRuntime.access() != .ready {
                        onBlocked()
                    } else if !noticeAck {
                        onNotice()
                    } else {
                        voice.pressDown()
                    }
                }
                voice.move(value.translation.height)
            }
            .onEnded { _ in
                if voice.machine.phase == .holding || voice.machine.phase == .recording {
                    voice.release()
                }
            }
    }

    @ViewBuilder
    private var dockBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        if interfaceStyle == .classic || reduceTransparency {
            shape.fill(Color(.secondarySystemGroupedBackground))
        } else if #available(iOS 26.0, *) {
            shape.fill(.clear)
                .glassEffect(.regular, in: shape)
        } else {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        }
    }
}

enum MainTab: Hashable, Identifiable {
    case today, history, trends, settings
    var id: String {
        switch self {
        case .today: return "today"
        case .history: return "history"
        case .trends: return "trends"
        case .settings: return "settings"
        }
    }
}
