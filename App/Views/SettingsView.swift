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
    @AppStorage(InterfaceStyle.storageKey) private var interfaceStyleRaw = InterfaceStyle.classic.rawValue
    @AppStorage(Prefs.nightStartMinutes) private var nightStartMinutes = NightSchedule.defaultStartMinutes
    @AppStorage(Prefs.nightEndMinutes) private var nightEndMinutes = NightSchedule.defaultEndMinutes
    @AppStorage(Prefs.dimScreenAtNight) private var dimScreenAtNight = false
    @AppStorage(Prefs.keepScreenOnWhileNursing) private var keepScreenOnWhileNursing = false
    @Environment(\.appTheme) private var theme
    @EnvironmentObject private var activity: BabyActivity

    @State private var babySheet: BabySheet?
    @State private var pendingSwitch: UUID?
    @State private var shareItem: ShareItem?
    @State private var exportError: String?
    @State private var showImporter = false
    @State private var importDoorIsAssisted = false
    @State private var importRequest: ImportRequest?
    @State private var manualTable: ManualImport?
    @State private var assistExcerpt: AssistExcerpt?
    @AppStorage("lastImportBatchID") private var lastImportBatch = ""
    @State private var remindersOn = false
    @State private var showWidgetPreview = false
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.storedDefault.rawValue
    @Environment(PersistenceGate.self) private var gate

    private var language: ResolvedLanguage {
        (AppLanguage(rawValue: languageRaw) ?? .zhHans).resolved()
    }

    var body: some View {
        Form {
            Section {
                settingsLink(language == .zh ? "宝宝与记录" : "Baby and records", "figure.and.child.holdinghands", "settings-module-records") {
                    Form {
                        babiesSection
                        NavigationLink {
                            HomeCardsSettingsView()
                        } label: {
                            Label(Copy.homeCards(language), systemImage: "square.grid.2x2.fill")
                        }
                        .accessibilityIdentifier("settings-home-cards")
                        unitsSection
                        nursingTimerSection
                    }
                    .themedList()
                    .navigationTitle(language == .zh ? "宝宝与记录" : "Baby and records")
                }
                settingsLink(language == .zh ? "外观" : "Appearance", "circle.lefthalf.filled", "settings-module-appearance") {
                    Form { appearanceSection }
                        .themedList()
                        .navigationTitle(language == .zh ? "外观" : "Appearance")
                }
                settingsLink(language == .zh ? "AI 与语音" : "Assistant", "sparkles", "settings-assistant") {
                    AISettingsView()
                }
                settingsLink(language == .zh ? "通知" : "Notifications", "bell.badge", "settings-reminders") {
                    RemindersSettingsView()
                }
                settingsLink(language == .zh ? "小组件" : "Widgets", "rectangle.3.group", "settings-module-widgets") {
                    Form { widgetsSection }
                        .themedList()
                        .navigationTitle(language == .zh ? "小组件" : "Widgets")
                }
                settingsLink(language == .zh ? "数据与同步" : "Data and sync", "arrow.triangle.2.circlepath", "settings-module-data") {
                    Form {
                        syncSection
                        caregiversSection
                        dataSection
                    }
                    .themedList()
                    .navigationTitle(language == .zh ? "数据与同步" : "Data and sync")
                }
                settingsLink(language == .zh ? "语言" : "Language", "globe", "settings-module-language") {
                    Form { languageSection }
                        .themedList()
                        .navigationTitle(Copy.languageSection(language))
                }
                settingsLink(language == .zh ? "关于" : "About", "info.circle", "settings-module-about") {
                    Form { aboutSection }
                        .themedList()
                        .navigationTitle(language == .zh ? "关于" : "About")
                }
            }
        }
        .themedList()
        .navigationTitle(Copy.settings(language))
        .systemBarChrome()
        .sheet(isPresented: $showWidgetPreview) {
            WidgetPreviewSheet()
        }
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
            language == .zh ? "导出失败" : "Couldn't export",
            isPresented: Binding(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } }
            )
        ) {
            Button(language == .zh ? "好" : "OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
        .confirmationDialog(
            language == .zh ? "这条还没保存" : "This is not saved",
            isPresented: Binding(get: { pendingSwitch != nil }, set: { if !$0 { pendingSwitch = nil } }),
            titleVisibility: .visible
        ) {
            Button(language == .zh ? "放弃并切换" : "Discard and switch", role: .destructive) {
                AITasks.shared.cancelAll()
                activity.clear()
                if let id = pendingSwitch { selectedBabyID = id.uuidString }
                pendingSwitch = nil
            }
            Button(language == .zh ? "留下" : "Stay", role: .cancel) { pendingSwitch = nil }
        } message: {
            Text(language == .zh ? "未保存的表单、录音或还在生成的回复会停在原来的宝宝，不会写到下一个宝宝。" : "The open form, recording, or reply stays with the current baby and is not written to the next one.")
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.item]) { result in
            guard case .success(let url) = result else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { return }
            acceptImport(data: data, filename: url.lastPathComponent)
        }
        .sheet(item: $importRequest) { request in
            ImportPreviewSheet(file: request.file, source: request.source, allowsModel: false) { batch in
                lastImportBatch = batch.uuidString
            }
        }
        .sheet(item: $manualTable) { table in
            ImportManualMapSheet(table: table.table) { file, source in
                importRequest = ImportRequest(file: file, source: source)
            }
        }
        .sheet(item: $assistExcerpt) { excerpt in
            ImportAssistSheet(excerpt: excerpt.text) { file in
                importRequest = ImportRequest(file: file, source: Data(excerpt.text.utf8))
            }
        }
    }

    private func settingsLink<Destination: View>(_ title: String, _ symbol: String, _ identifier: String, @ViewBuilder destination: () -> Destination) -> some View {
        NavigationLink {
            destination()
        } label: {
            Label(title, systemImage: symbol)
        }
        .accessibilityIdentifier(identifier)
    }

    // MARK: Sections

    private var babiesSection: some View {
        Section {
            ForEach(babies, id: \.objectID) { baby in
                HStack {
                    Button {
                        switchBaby(baby)
                    } label: {
                        HStack {
                            BabyRow(baby: baby)
                            if baby.uuid?.uuidString == selectedBabyID {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings-baby-switch")
                    Button(language == .zh ? "编辑" : "Edit") {
                        babySheet = .edit(baby)
                    }
                    .accessibilityIdentifier("settings-baby")
                }
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
            .accessibilityIdentifier("settings-reminders")
            NavigationLink {
                HomeCardsSettingsView()
            } label: {
                Label(Copy.homeCards(language), systemImage: "square.grid.2x2.fill")
            }
            .accessibilityIdentifier("settings-home-cards")
            NavigationLink {
                AISettingsView()
            } label: {
                Label(language == .zh ? "AI 助手" : "Assistant", systemImage: "sparkles")
            }
            .accessibilityIdentifier("settings-assistant")
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
        }
        .themedSection()
    }

    private var unitsSection: some View {
        Section {
            Picker(language == .zh ? "液体" : "Liquids", selection: $volumeUnit) {
                ForEach(VolumeUnit.allCases) { unit in
                    Text(unit.label(language)).tag(unit)
                }
            }
            Picker(language == .zh ? "体重和身长" : "Weight and length", selection: $unitSystem) {
                ForEach(UnitSystem.allCases) { system in
                    Text(system.label(language)).tag(system)
                }
            }
        } header: {
            Text(language == .zh ? "单位" : "Units")
        }
        .themedSection()
    }

    private var appearanceSection: some View {
        Section {
            ForEach(AppearanceMode.allCases) { mode in
                Button {
                    appearanceMode = mode
                } label: {
                    HStack {
                        Text(appearanceTitle(mode))
                            .foregroundStyle(theme.primaryText)
                        Spacer()
                        if appearanceMode == mode {
                            Image(systemName: "checkmark")
                                .foregroundStyle(theme.accent)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("appearance-\(mode.rawValue)")
            }
            ForEach(InterfaceStyle.allCases) { style in
                Button {
                    interfaceStyleRaw = style.rawValue
                } label: {
                    HStack {
                        Text(style == .classic ? (language == .zh ? "经典" : "Classic") : (language == .zh ? "液态玻璃" : "Liquid Glass"))
                        Spacer()
                        if interfaceStyleRaw == style.rawValue {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("style-\(style.rawValue)")
            }
        } header: {
            Text(UICopy.t(.appearance, language))
        }
        .themedSection()
    }

    private var nursingTimerSection: some View {
        Section {
            Toggle(language == .zh ? "计时中保持屏幕常亮" : "Keep screen on during nursing timer", isOn: $keepScreenOnWhileNursing)
        } header: {
            Text(UICopy.t(.nursingTimer, language))
        }
        .themedSection()
    }

    private var widgetsSection: some View {
        Section {
            Button {
                showWidgetPreview = true
            } label: {
                Label(language == .zh ? "预览" : "Preview", systemImage: "rectangle.3.group")
            }
            .accessibilityIdentifier("show-widget-preview")
        } header: {
            Text(language == .zh ? "小组件" : "Widgets")
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
                importDoorIsAssisted = false
                showImporter = true
            } label: {
                Label(language == .zh ? "普通导入" : "Import a file", systemImage: "square.and.arrow.down")
            }
            .accessibilityIdentifier("import-ordinary")
            Text(ImportIntake.ordinaryFormats)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button {
                guard AIRuntime.access().maySend else {
                    exportError = language == .zh ? "AI 已关闭或还没有可用的 Key。请用普通导入。文件不会上传。" : "The assistant is off. Use ordinary import. The file is not uploaded."
                    return
                }
                importDoorIsAssisted = true
                showImporter = true
            } label: {
                Label(language == .zh ? "用 AI 读取文件" : "Read a file with AI", systemImage: "sparkles")
            }
            .accessibilityIdentifier("import-assisted")
            Text(ImportIntake.assistedFormats)
                .font(.footnote)
                .foregroundStyle(.secondary)
            if !lastImportBatch.isEmpty {
                Button(language == .zh ? "撤销上一批导入" : "Undo last import", role: .destructive) {
                    undoLastImport()
                }
            }
        } header: {
            Text(language == .zh ? "你的数据" : "Your data")
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
        }
    }

    private func acceptImport(data: Data, filename: String) {
        if importDoorIsAssisted {
            switch ImportIntake.openAssisted(data: data, filename: filename) {
            case .schema(let file):
                importRequest = ImportRequest(file: file, source: data)
            case .text(let text):
                assistExcerpt = AssistExcerpt(text: text)
            case .unsupported(let message):
                exportError = message
            }
            return
        }
        switch ImportIntake.openOrdinary(data: data, filename: filename) {
        case .schema(let file):
            importRequest = ImportRequest(file: file, source: data)
        case .manual(let table):
            manualTable = ManualImport(table: table)
        case .rejected(let message):
            exportError = message
        }
    }

    private func switchBaby(_ baby: Baby) {
        guard let id = baby.uuid else { return }
        let known = Set(babies.compactMap(\.uuid))
        switch BabySwitch.decide(stored: selectedBabyID, target: id, known: known, work: activity.work()) {
        case .select(let chosen):
            selectedBabyID = chosen.uuidString
        case .confirmDiscard(_, let to):
            pendingSwitch = to
        case nil:
            return
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
    @State private var showRelation = false

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
            if let id = baby.uuid {
                Button {
                    showRelation = true
                } label: {
                    HStack {
                        Text(language == .zh ? "与宝宝的关系" : "Relation to this baby")
                        Spacer()
                        Text(relationTitle(id))
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("caregiver-relation")
                .sheet(isPresented: $showRelation) {
                    CaregiverRelationSheet(babyID: id, babyName: baby.displayName)
                }
            }
        }
    }

    private func relationTitle(_ id: UUID) -> String {
        let store = CaregiverRelationStore()
        let relation = store.relation(managerID: store.managerID(), babyID: id)
        return relation?.title(chinese: language == .zh) ?? (language == .zh ? "未设置" : "Not set")
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
    @Environment(\.uiLanguage) private var language

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(CloudSyncProblem.message(for: problem.kind, language: language))
                .font(.footnote)
                .foregroundStyle(theme.destructive)
                .fixedSize(horizontal: false, vertical: true)
            if !problem.technicalDetails.isEmpty {
                DisclosureGroup(language == .zh ? "详情" : "Details") {
                    Text(problem.technicalDetails)
                        .font(.caption.monospaced())
                        .foregroundStyle(theme.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.footnote)
            }
            if let onDismiss {
                Button(language == .zh ? "关闭" : "Dismiss", action: onDismiss)
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
