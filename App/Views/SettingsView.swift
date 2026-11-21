import SwiftUI
import CloudKit
import CoreData
import UniformTypeIdentifiers
import BabyLogKit

private enum BabySheet: Identifiable {
    case add
    case edit(Baby)

    var id: String {
        switch self {
        case .add:
            return "add"
        case .edit(let baby):
            return "edit-" + baby.objectID.uriRepresentation().absoluteString
        }
    }
}

struct SettingsView: View {
    @Environment(\.persistence) private var persistence
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(fetchRequest: Baby.lblAllByCreation()) private var babies: FetchedResults<Baby>

    @AppStorage(Prefs.selectedBabyID) private var selectedBabyID: String = ""
    @AppStorage(Prefs.volumeUnit) private var volumeUnit: VolumeUnit = Prefs.defaultVolumeUnit
    @AppStorage(Prefs.unitSystem) private var unitSystem: UnitSystem = Prefs.defaultUnitSystem
    @AppStorage(Prefs.appearanceMode) private var appearanceMode: AppearanceMode = Prefs.defaultAppearanceMode
    @AppStorage(Prefs.nightStartMinutes) private var nightStartMinutes = NightSchedule.defaultStartMinutes
    @AppStorage(Prefs.nightEndMinutes) private var nightEndMinutes = NightSchedule.defaultEndMinutes
    @AppStorage(Prefs.dimScreenAtNight) private var dimScreenAtNight = false
    @AppStorage(Prefs.keepScreenOnWhileNursing) private var keepScreenOnWhileNursing = false
    @Environment(\.appTheme) private var theme

    @State private var babySheet: BabySheet?
    @State private var shareItem: ShareItem?
    @State private var exportError: String?
    @State private var showImporter = false
    @State private var importRequest: ImportRequest?
    @AppStorage("lastImportBatchID") private var lastImportBatch = ""
    @State private var remindersOn = false
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.storedDefault.rawValue
    @Environment(PersistenceGate.self) private var gate

    private var language: ResolvedLanguage {
        (AppLanguage(rawValue: languageRaw) ?? .zhHans).resolved()
    }

    var body: some View {
        Form {
            babiesSection
            languageSection
            remindersSection
            caregiversSection
            syncSection
            unitsSection
            appearanceSection
            nursingTimerSection
            widgetsSection
            dataSection
            aboutSection
        }
        .themedList()
        .navigationTitle(Copy.settings(language))
        .systemBarChrome()
        .sheet(item: $babySheet) { sheet in
            switch sheet {
            case .add:
                BabyFormView(baby: nil) { saved in
                    selectedBabyID = saved.uuid?.uuidString ?? selectedBabyID
                }
            case .edit(let baby):
                BabyFormView(baby: baby) { _ in }
            }
        }
        .sheet(item: $shareItem) { item in
            ActivityView(items: [item.url])
                .presentationDetents([.medium, .large])
        }
        .alert(
            "Couldn't export",
            isPresented: Binding(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.commaSeparatedText, .json, .plainText]) { result in
            guard case .success(let url) = result else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { return }
            importRequest = ImportRequest(file: StandardImporter.parse(data: data))
        }
        .sheet(item: $importRequest) { request in
            ImportPreviewSheet(file: request.file) { batch in
                lastImportBatch = batch.uuidString
            }
        }
    }

    // MARK: Sections

    private var babiesSection: some View {
        Section {
            ForEach(babies, id: \.objectID) { baby in
                Button {
                    babySheet = .edit(baby)
                } label: {
                    BabyRow(baby: baby)
                }
                .buttonStyle(.plain)
            }
            Button {
                babySheet = .add
            } label: {
                Label(UICopy.t(.addBaby, language), systemImage: "plus.circle.fill")
            }
        } header: {
            Text(language == .zh ? "宝宝" : "Babies")
        }
        .themedSection()
    }

    private var languageSection: some View {
        Section {
            Picker(Copy.languageSection(language), selection: $languageRaw) {
                ForEach(AppLanguage.allCases) { item in
                    Text(Copy.languageName(item, language)).tag(item.rawValue)
                }
            }
            .accessibilityIdentifier("app-language")
        } header: {
            Text(Copy.languageSection(language))
        }
        .themedSection()
    }

    private var remindersSection: some View {
        Section {
            NavigationLink {
                RemindersSettingsView()
            } label: {
                HStack {
                    Label(Copy.reminders(language), systemImage: "bell.badge.fill")
                    Spacer()
                    Text(remindersOn ? Copy.on(language) : Copy.off(language))
                        .foregroundStyle(theme.secondary)
                }
            }
            NavigationLink {
                HomeCardsSettingsView()
            } label: {
                Label(Copy.homeCards(language), systemImage: "square.grid.2x2.fill")
            }
            NavigationLink {
                AISettingsView()
            } label: {
                Label(language == .zh ? "AI 助手" : "Assistant", systemImage: "sparkles")
            }
        } footer: {
            Text(Copy.deviceReminders(language))
        }
        .themedSection()
        .onAppear { remindersOn = ReminderSettingsStore().hasAnythingEnabled }
    }

    private var syncSection: some View {
        Section {
            ICloudSyncRow()
        } header: {
            Text(Copy.iCloud(language))
        } footer: {
            Text(language == .zh
                 ? "开关只决定这台设备是否把同一份本地数据库交给 iCloud。关闭不会删除记录。容器已关联，但还没有记录类型，也还没有部署到 Production。两台手机是否同步，要等 schema 和 Push 都就绪后再用真机确认。"
                 : "This switch chooses whether this device hands the same local database to iCloud. Turning it off does not delete records. The container is associated, but it still has no record types and Production has not been deployed. Two phones can be checked only after the schema and Push are ready.")
        }
        .themedSection()
    }

    private var caregiversSection: some View {
        Section {
            ForEach(babies, id: \.objectID) { baby in
                CaregiverRow(baby: baby)
            }
        } header: {
            Text(UICopy.t(.caregivers, language))
        } footer: {
            Text(language == .zh
                 ? "分享依赖 iCloud。这里没有验证过邀请是否成功，失败时会显示系统给出的原因。"
                 : "Sharing depends on iCloud. An invitation has not been verified here; a failure shows the system reason.")
        }
        .themedSection()
    }

    private var unitsSection: some View {
        Section {
            Picker(language == .zh ? "液体" : "Liquids", selection: $volumeUnit) {
                ForEach(VolumeUnit.allCases) { unit in
                    Text(unit.title).tag(unit)
                }
            }
            Picker(language == .zh ? "体重和身长" : "Weight and length", selection: $unitSystem) {
                ForEach(UnitSystem.allCases) { system in
                    Text(system.title).tag(system)
                }
            }
        } header: {
            Text(language == .zh ? "单位" : "Units")
        }
        .themedSection()
    }

    private var appearanceSection: some View {
        Section {
            Picker(UICopy.t(.appearance, language), selection: $appearanceMode) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(appearanceTitle(mode))
                        .tag(mode)
                        .accessibilityIdentifier("appearance-\(mode.rawValue)")
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()

            if appearanceMode == .nightSchedule {
                DatePicker(language == .zh ? "从" : "From", selection: minutesBinding($nightStartMinutes), displayedComponents: .hourAndMinute)
                DatePicker(language == .zh ? "到" : "To", selection: minutesBinding($nightEndMinutes), displayedComponents: .hourAndMinute)
            }

            if appearanceMode.canShowNight {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle(language == .zh ? "夜间降低亮度" : "Dim screen at night", isOn: $dimScreenAtNight)
                    BatteryImpactNote(language == .zh ? "夜间界面会降低屏幕亮度，更省电。" : "Lowers the screen brightness while Night is showing, which saves battery.", effect: .saves)
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text(UICopy.t(.appearance, language))
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if appearanceMode == .nightSchedule {
                    Text(UICopy.t(.nightSchedule, language))
                } else if appearanceMode == .night {
                    Text(UICopy.t(.nightLook, language))
                }
                Text(UICopy.t(.widgetAppearance, language))
            }
        }
        .themedSection()
    }

    private var nursingTimerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Toggle(language == .zh ? "计时中保持屏幕常亮" : "Keep screen on during nursing timer", isOn: $keepScreenOnWhileNursing)
                BatteryImpactNote(language == .zh ? "计时页面打开时屏幕不熄灭，会更耗电。" : "Keeps your screen on while the timer is open, which uses more battery.")
            }
            .padding(.vertical, 2)
        } header: {
            Text(UICopy.t(.nursingTimer, language))
        }
        .themedSection()
    }

    private var widgetsSection: some View {
        Section {
            Label {
                Text(UICopy.t(.widgetHelp, language))
            } icon: {
                Image(systemName: "rectangle.3.group.fill")
                    .foregroundStyle(theme.accent)
            }
            Label {
                Text(UICopy.t(.lockHelp, language))
            } icon: {
                Image(systemName: "lock.fill")
                    .foregroundStyle(theme.accent)
            }
        } header: {
            Text(language == .zh ? "小组件" : "Widgets")
        } footer: {
            Text(UICopy.t(.widgetBaby, language))
        }
        .themedSection()
    }

    private var dataSection: some View {
        Section {
            Button {
                exportCSV()
            } label: {
                Label(language == .zh ? "导出全部数据 (CSV)" : "Export all data (CSV)", systemImage: "square.and.arrow.up")
            }
            Button {
                showImporter = true
            } label: {
                Label(language == .zh ? "导入标准 CSV / JSON" : "Import standard CSV / JSON", systemImage: "square.and.arrow.down")
            }
            if !lastImportBatch.isEmpty {
                Button(language == .zh ? "撤销上一批导入" : "Undo last import", role: .destructive) {
                    undoLastImport()
                }
            }
        } header: {
            Text(language == .zh ? "你的数据" : "Your data")
        } footer: {
            Text(UICopy.t(.dataFootnote, language))
        }
        .themedSection()
    }

    private var aboutSection: some View {
        Section {
            LabeledContent(language == .zh ? "版本" : "Version", value: AppConfig.versionString)
            Link(destination: AppConfig.sourceCodeURL) {
                Label(language == .zh ? "GitHub 源代码" : "GitHub source", systemImage: "chevron.left.forwardslash.chevron.right")
            }
            Link(destination: AppConfig.upstreamSourceCodeURL) {
                Label("上游 Little Baby Log", systemImage: "arrow.turn.up.right")
            }
        } header: {
            Text(UICopy.t(.about, language))
        } footer: {
            Text(UICopy.t(.aboutBody, language))
        }
        .themedSection()
    }

    // MARK: Times

    /// A time-of-day picker value for a stored "minutes since midnight".
    private func minutesBinding(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: minutes.wrappedValue / 60, minute: minutes.wrappedValue % 60, second: 0, of: .now) ?? .now
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                minutes.wrappedValue = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
    }

    private static func timeString(_ minutes: Int) -> String {
        let date = Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }

    // MARK: Export

    private func appearanceTitle(_ mode: AppearanceMode) -> String {
        switch mode {
        case .system: return language == .zh ? "跟随系统" : "System"
        case .light: return language == .zh ? "浅色" : "Light"
        case .dark: return language == .zh ? "深色" : "Dark"
        case .night: return language == .zh ? "夜间" : "Night"
        case .nightSchedule: return language == .zh ? "按时夜间" : "Night on a schedule"
        }
    }

    private func undoLastImport() {
        guard let id = UUID(uuidString: lastImportBatch) else { return }
        do {
            _ = try ImportCommit.undo(batchID: id, in: context)
            lastImportBatch = ""
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func exportCSV() {
        let request: NSFetchRequest<LogEvent> = LogEvent.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "startDate", ascending: true)]
        do {
            let events = try context.fetch(request)
            let csv = CSVExporter.csv(for: events)

            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            let filename = "LittleBabyLog-\(formatter.string(from: .now)).csv"

            let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            try csv.write(to: url, atomically: true, encoding: .utf8)
            shareItem = ShareItem(url: url)
        } catch {
            exportError = error.localizedDescription
        }
    }
}

/// A baby's name and age. Observes the baby so renames show up immediately.
private struct BabyRow: View {
    @ObservedObject var baby: Baby
    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(baby.displayName)
                    .font(.headline)
                    .foregroundStyle(theme.primary)
                if let birthDate = baby.birthDate {
                    Text(BabyAge.description(birthDate: birthDate))
                        .font(.subheadline)
                        .foregroundStyle(theme.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

/// One baby's sharing status plus an Invite / Manage button.
struct CaregiverRow: View {
    @ObservedObject var baby: Baby

    @Environment(\.persistence) private var persistence
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.storedDefault.rawValue

    private var language: ResolvedLanguage {
        (AppLanguage(rawValue: languageRaw) ?? .zhHans).resolved()
    }
    @State private var coordinator: CloudSharingCoordinator?
    @State private var isWorking = false
    @State private var refreshTick = 0
    @State private var problem: CloudSyncProblem?

    var body: some View {
        let _ = refreshTick
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(baby.displayName)
                        .font(.headline)
                    Text(statusText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if isWorking {
                    ProgressView()
                } else {
                    Button(shareButtonTitle) {
                        startSharing()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!persistence.isCloudSyncEnabled)
                }
            }
            if let problem {
                SyncProblemView(problem: problem) { self.problem = nil }
            }
        }
    }

    private var shareButtonTitle: String {
        if persistence.isShared(baby) {
            return language == .zh ? "管理" : "Manage"
        }
        return language == .zh ? "邀请" : "Invite"
    }

    private var statusText: String {
        guard persistence.isCloudSyncEnabled else {
            return language == .zh ? "同步已暂停，记录仍在这台手机" : "Sync is paused. Records stay on this phone"
        }

        if persistence.isInSharedStore(baby) {
            if let share = persistence.existingShare(for: baby),
               let components = share.owner.userIdentity.nameComponents {
                let name = PersonNameComponentsFormatter().string(from: components)
                if !name.isEmpty {
                    return language == .zh ? "由 \(name) 分享给你" : "Shared with you by \(name)"
                }
            }
            return language == .zh ? "分享给你的" : "Shared with you"
        }

        if let share = persistence.existingShare(for: baby) {
            let others = share.participants.filter { $0.role != .owner }.count
            switch others {
            case 0: return language == .zh ? "未分享" : "Not shared"
            case 1: return language == .zh ? "已分享给 1 人" : "Shared with 1 person"
            default: return language == .zh ? "已分享给 \(others) 人" : "Shared with \(others) people"
            }
        }
        return language == .zh ? "未分享" : "Not shared"
    }

    private func startSharing() {
        problem = nil
        // No point waiting for CloudKit to fail when we already know there's no iCloud account.
        if CloudSyncStatus.shared.state == .notSignedIn {
            problem = CloudSyncProblem(
                kind: .notSignedIn,
                message: CloudSyncProblem.message(for: .notSignedIn),
                technicalDetails: "iCloud account status: no account (CKAccountStatus.noAccount)"
            )
            return
        }
        isWorking = true
        let newCoordinator = CloudSharingCoordinator(persistence: persistence, baby: baby) {
            refreshTick += 1
        }
        coordinator = newCoordinator
        Task {
            do {
                try await newCoordinator.present()
            } catch {
                problem = CloudSyncProblem.classify(error)
            }
            isWorking = false
        }
    }
}

/// The "iCloud sync" status line: Syncing / Up to date / Not signed in / Error, with the plain-language reason and a
/// Details disclosure on errors.
private struct ICloudSyncRow: View {
    @State private var status = CloudSyncStatus.shared
    @Environment(\.appTheme) private var theme
    @Environment(PersistenceGate.self) private var gate
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.storedDefault.rawValue

    private var language: ResolvedLanguage {
        (AppLanguage(rawValue: languageRaw) ?? .zhHans).resolved()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(
                get: { gate.cloudSyncEnabled },
                set: { gate.setCloudSync($0) }
            )) {
                Label {
                    Text(Copy.iCloud(language))
                } icon: {
                    Image(systemName: symbol)
                        .foregroundStyle(tint)
                }
            }
            .disabled(!gate.canToggle)
            HStack {
                if status.state == .syncing {
                    ProgressView()
                }
                Text(title)
                    .foregroundStyle(theme.secondary)
                Spacer()
                if case .error = status.state {
                    Button(Copy.retry(language)) { status.refreshAccount() }
                        .buttonStyle(.borderless)
                }
            }
            if case .error(let problem) = status.state {
                SyncProblemView(problem: problem, onDismiss: nil)
            } else if status.state == .notSignedIn {
                Text(UICopy.t(.signInICloud, language))
                    .font(.footnote)
                    .foregroundStyle(theme.secondary)
            } else if status.state == .unavailable {
                Text(UICopy.t(.iCloudRestricted, language))
                    .font(.footnote)
                    .foregroundStyle(theme.secondary)
            }
        }
        .padding(.vertical, 2)
        .onAppear { status.refreshAccount() }
    }

    private var title: String {
        switch status.state {
        case .off: return language == .zh ? "已暂停" : "Paused"
        case .checking: return language == .zh ? "正在检查" : "Checking"
        case .notSignedIn: return language == .zh ? "未登录 iCloud" : "Not signed in"
        case .unavailable: return language == .zh ? "暂不可用" : "Unavailable"
        case .syncing: return language == .zh ? "同步中" : "Syncing"
        case .upToDate: return language == .zh ? "已同步" : "Up to date"
        case .error: return language == .zh ? "出错" : "Error"
        }
    }

    private var symbol: String {
        switch status.state {
        case .off, .checking: return "icloud.slash"
        case .notSignedIn, .unavailable: return "icloud.slash"
        case .syncing: return "arrow.triangle.2.circlepath.icloud"
        case .upToDate: return "checkmark.icloud"
        case .error: return "exclamationmark.icloud"
        }
    }

    private var tint: Color {
        switch status.state {
        case .upToDate: return theme.isNight ? theme.accent : .green
        case .error: return theme.destructive
        case .notSignedIn, .unavailable: return theme.isNight ? theme.accent : .orange
        default: return theme.isNight ? theme.accent : .accentColor
        }
    }
}

/// A sync or sharing problem in plain language, with the technical text behind a "Details" disclosure so testers
/// can still copy it into a bug report.
private struct SyncProblemView: View {
    let problem: CloudSyncProblem
    var onDismiss: (() -> Void)?

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(problem.message)
                .font(.footnote)
                .foregroundStyle(theme.destructive)
                .fixedSize(horizontal: false, vertical: true)
            if !problem.technicalDetails.isEmpty {
                DisclosureGroup("Details") {
                    Text(problem.technicalDetails)
                        .font(.caption.monospaced())
                        .foregroundStyle(theme.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.footnote)
            }
            if let onDismiss {
                Button("Dismiss", action: onDismiss)
                    .font(.footnote)
                    .buttonStyle(.borderless)
            }
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .previewEnvironment()
}
