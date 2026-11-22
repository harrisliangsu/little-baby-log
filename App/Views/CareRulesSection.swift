import SwiftUI
import CoreData
import BabyLogKit

struct CareRulesBabySection: View {
    let babyID: UUID
    let babyName: String
    let showName: Bool
    @Binding var permission: ReminderScheduler.Permission

    @Environment(\.managedObjectContext) private var context
    @Environment(\.appTheme) private var theme
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.storedDefault.rawValue

    @State private var settings: BabyReminderSettings
    @State private var editing: CareRule?
    @State private var draft: CareRule?
    @AppStorage(AIPreferences.enabledKey) private var aiEnabled = false
    @State private var showAIDraft = false

    private let store = ReminderSettingsStore()

    init(babyID: UUID, babyName: String, showName: Bool, permission: Binding<ReminderScheduler.Permission>) {
        self.babyID = babyID
        self.babyName = babyName
        self.showName = showName
        self._permission = permission
        var initial = ReminderSettingsStore().settings(for: babyID)
        let adopted = initial.adoptingRules()
        if adopted != initial {
            ReminderSettingsStore().save(adopted, for: babyID)
            initial = adopted
        }
        self._settings = State(initialValue: initial)
    }

    private var language: ResolvedLanguage {
        (AppLanguage(rawValue: languageRaw) ?? .zhHans).resolved()
    }

    var body: some View {
        Group {
            templateSection
            rulesSection
            napSection
        }
        .onChange(of: settings) { old, new in
            store.save(new, for: babyID)
            Task {
                if new.hasAnythingEnabled, !old.hasAnythingEnabled || permission == .notDetermined {
                    permission = await ReminderScheduler.shared.requestPermissionIfNeeded()
                }
                await ReminderScheduler.shared.refresh()
            }
        }
        .sheet(item: $editing) { rule in
            CareRuleEditor(rule: rule, language: language) { saved in
                if let index = settings.rules.firstIndex(where: { $0.id == saved.id }) {
                    settings.rules[index] = saved
                }
            } onDelete: { id in
                settings.rules.removeAll { $0.id == id }
            }
        }
        .sheet(isPresented: $showAIDraft) {
            if let baby = (try? context.fetch(Baby.lblAllByCreation()))?.first(where: { $0.uuid == babyID }) {
                AIChatView(baby: baby, reminder: true, onReminder: { rule in
                    draft = rule
                })
            }
        }
        .sheet(item: $draft) { rule in
            CareRuleEditor(rule: rule, language: language) { saved in
                settings.rules.append(saved)
            } onDelete: { _ in }
        }
    }

    private var templateSection: some View {
        Section {
            Button {
                add(CareRuleTemplate.feedInterval(minutes: 180, anchor: .start, text: language == .zh ? "喂奶" : "Feed"))
            } label: {
                Label(language == .zh ? "每 3 小时喂奶" : "Feed every 3 hours", systemImage: "heart.fill")
            }
            Button {
                add(CareRuleTemplate.caregiverAfterFeed(delayMinutes: 30, text: language == .zh ? "喝水" : "Drink water"))
            } label: {
                Label(language == .zh ? "喂奶后 30 分钟提醒我喝水" : "30 min after a feed, remind me to drink", systemImage: "drop.fill")
            }
            Button {
                add(CareRuleTemplate.daily(minutesOfDay: 9 * 60, text: language == .zh ? "提醒" : "Reminder"))
            } label: {
                Label(language == .zh ? "每天固定时间" : "Every day at a set time", systemImage: "clock.fill")
            }
            if aiEnabled, AIRuntime.access().maySend {
                Button {
                    showAIDraft = true
                } label: {
                    Label(language == .zh ? "用一句话做提醒草稿" : "Draft a reminder from a sentence", systemImage: "sparkles")
                }
            }
            Button {
                draft = CareRuleTemplate.feedInterval(text: language == .zh ? "喂奶" : "Feed")
            } label: {
                Label(language == .zh ? "自定义一条" : "Custom rule", systemImage: "slider.horizontal.3")
            }
        } header: {
            Text(showName ? babyName : (language == .zh ? "简单模板" : "Templates"))
        } footer: {
            Text(Copy.waterFootnote(language))
        }
        .themedSection()
    }

    private var rulesSection: some View {
        Section {
            ForEach(settings.rules) { rule in
                Button {
                    editing = rule
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(rule.reminderText.isEmpty ? (language == .zh ? "提醒" : "Reminder") : rule.reminderText)
                                .foregroundStyle(theme.primary)
                            Spacer()
                            Toggle("", isOn: enabled(rule.id))
                                .labelsHidden()
                        }
                        Text(preview(rule))
                            .font(.footnote)
                            .foregroundStyle(theme.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            .onDelete { offsets in
                settings.rules.remove(atOffsets: offsets)
            }
        } header: {
            Text(language == .zh ? "已添加" : "Added")
        }
        .themedSection()
    }

    private var napSection: some View {
        Section {
            Toggle(language == .zh ? "小睡窗口前提醒" : "Nap window reminder", isOn: $settings.napWindow.isEnabled)
            if settings.napWindow.isEnabled {
                Picker(language == .zh ? "提前" : "Lead time", selection: $settings.napWindow.leadMinutes) {
                    ForEach(NapWindowReminder.allowedLeadMinutes, id: \.self) { minutes in
                        Text(language == .zh ? "\(minutes) 分钟" : "\(minutes) min").tag(minutes)
                    }
                }
                Toggle(language == .zh ? "也包括夜间睡觉" : "Also remind for bedtime", isOn: $settings.napWindow.includeBedtime)
            }
        }
        .themedSection()
    }

    private func add(_ rule: CareRule) {
        settings.rules.append(rule)
    }

    private func enabled(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { settings.rules.first { $0.id == id }?.isEnabled ?? false },
            set: { newValue in
                guard let index = settings.rules.firstIndex(where: { $0.id == id }) else { return }
                settings.rules[index].isEnabled = newValue
            }
        )
    }

    private func preview(_ rule: CareRule) -> String {
        let loaded = ReminderInputs.load(in: context, settings: store).first { $0.id == babyID }
        var person = loaded ?? ReminderBaby(id: babyID, name: babyName, settings: settings, lastFeed: nil)
        person.settings = settings
        switch CareRulePlanner.outlook(rule: rule, baby: person, now: .now, calendar: .current) {
        case .disabled:
            return Copy.off(language)
        case .fires(let date, _):
            return (language == .zh ? "下次 " : "Next ") + date.formatted(date: .omitted, time: .shortened)
        case .noBaseline:
            return Copy.noBaseline(language)
        case .waitingForEnd:
            return Copy.waitingForEnd(language)
        case .acknowledgedUntilNextRecord:
            return Copy.acknowledged(language)
        case .overdue:
            return Copy.overdue(language)
        }
    }
}

private struct CareRuleEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var rule: CareRule
    let language: ResolvedLanguage
    let onSave: (CareRule) -> Void
    let onDelete: (UUID) -> Void

    var body: some View {
        NavigationStack {
            Form {
                TextField(language == .zh ? "提醒内容" : "Reminder", text: $rule.reminderText)
                Picker(language == .zh ? "看哪类记录" : "Count from", selection: sourceChoice) {
                    Text(language == .zh ? "任意喂养" : "Any feed").tag(SourceChoice.anyFeed)
                    Text(Copy.card(.breast, language)).tag(SourceChoice.breast)
                    Text(Copy.card(.formula, language)).tag(SourceChoice.formula)
                    Text(Copy.card(.sleep, language)).tag(SourceChoice.sleep)
                    Text(Copy.card(.wet, language)).tag(SourceChoice.wet)
                    Text(Copy.card(.dirty, language)).tag(SourceChoice.dirty)
                    Text(language == .zh ? "自定义，不对应记录" : "Custom, no record").tag(SourceChoice.custom)
                }
                Picker(language == .zh ? "怎么提醒" : "When", selection: triggerChoice) {
                    Text(language == .zh ? "距最近一次" : "After the latest").tag(TriggerChoice.interval)
                    Text(language == .zh ? "事件之后" : "Delay after it").tag(TriggerChoice.delay)
                    Text(language == .zh ? "每天固定时间" : "Fixed time").tag(TriggerChoice.fixed)
                }
                if case .fixedTime(let minutes) = rule.trigger {
                    DatePicker(
                        language == .zh ? "时间" : "Time",
                        selection: minutesBinding(minutes),
                        displayedComponents: .hourAndMinute
                    )
                } else {
                    Stepper(minuteLabel, value: minutesBindingValue, in: 1...24 * 60)
                    Picker(language == .zh ? "从何时起算" : "Measure from", selection: anchorBinding) {
                        Text(Copy.anchorStart(language)).tag(FeedIntervalAnchor.start)
                        Text(Copy.anchorEnd(language)).tag(FeedIntervalAnchor.end)
                    }
                }
                Toggle(language == .zh ? "静默时段" : "Quiet hours", isOn: quietOn)
            }
            .navigationTitle(language == .zh ? "编辑提醒" : "Edit reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language == .zh ? "取消" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(language == .zh ? "保存" : "Save") {
                        onSave(rule)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button(language == .zh ? "删除" : "Delete", role: .destructive) {
                        onDelete(rule.id)
                        dismiss()
                    }
                }
            }
        }
    }

    private var minuteLabel: String {
        let minutes = rule.clampedMinutes ?? 0
        if language == .zh {
            if minutes < 60 { return "\(minutes) 分钟" }
            return "\(minutes / 60) 小时 \(minutes % 60) 分"
        }
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60) h \(minutes % 60) min"
    }

    private var minutesBindingValue: Binding<Int> {
        Binding(
            get: { rule.clampedMinutes ?? 180 },
            set: { newValue in
                switch rule.trigger {
                case .intervalSinceLast(_, let anchor):
                    rule.trigger = .intervalSinceLast(minutes: newValue, anchor: anchor)
                case .delayAfterEvent(_, let anchor):
                    rule.trigger = .delayAfterEvent(minutes: newValue, anchor: anchor)
                case .fixedTime:
                    break
                }
            }
        )
    }

    private var anchorBinding: Binding<FeedIntervalAnchor> {
        Binding(
            get: {
                switch rule.trigger {
                case .intervalSinceLast(_, let anchor), .delayAfterEvent(_, let anchor): return anchor
                case .fixedTime: return .start
                }
            },
            set: { anchor in
                let minutes = rule.clampedMinutes ?? 180
                switch rule.trigger {
                case .intervalSinceLast:
                    rule.trigger = .intervalSinceLast(minutes: minutes, anchor: anchor)
                case .delayAfterEvent:
                    rule.trigger = .delayAfterEvent(minutes: minutes, anchor: anchor)
                case .fixedTime:
                    break
                }
            }
        )
    }

    private var quietOn: Binding<Bool> {
        Binding(
            get: { rule.quietHours != nil },
            set: { rule.quietHours = $0 ? (rule.quietHours ?? QuietHours()) : nil }
        )
    }

    private enum SourceChoice: Hashable {
        case anyFeed, breast, formula, sleep, wet, dirty, custom
    }

    private var sourceChoice: Binding<SourceChoice> {
        Binding(
            get: {
                switch rule.source {
                case .anyFeed: return .anyFeed
                case .card(.formula): return .formula
                case .card(.sleep): return .sleep
                case .card(.wet): return .wet
                case .card(.dirty): return .dirty
                case .card: return .breast
                case .custom: return .custom
                }
            },
            set: { choice in
                switch choice {
                case .anyFeed: rule.source = .anyFeed
                case .breast: rule.source = .card(.breast)
                case .formula: rule.source = .card(.formula)
                case .sleep: rule.source = .card(.sleep)
                case .wet: rule.source = .card(.wet)
                case .dirty: rule.source = .card(.dirty)
                case .custom: rule.source = .custom
                }
            }
        )
    }

    private enum TriggerChoice: Hashable { case interval, delay, fixed }

    private var triggerChoice: Binding<TriggerChoice> {
        Binding(
            get: {
                switch rule.trigger {
                case .intervalSinceLast: return .interval
                case .delayAfterEvent: return .delay
                case .fixedTime: return .fixed
                }
            },
            set: { choice in
                switch choice {
                case .interval:
                    rule.trigger = .intervalSinceLast(minutes: rule.clampedMinutes ?? 180, anchor: anchorBinding.wrappedValue)
                case .delay:
                    rule.trigger = .delayAfterEvent(minutes: rule.clampedMinutes ?? 30, anchor: anchorBinding.wrappedValue)
                case .fixed:
                    rule.trigger = .fixedTime(minutesOfDay: 9 * 60)
                }
            }
        )
    }

    private func minutesBinding(_ minutes: Int) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                rule.trigger = .fixedTime(minutesOfDay: (parts.hour ?? 0) * 60 + (parts.minute ?? 0))
            }
        )
    }
}
