import SwiftUI
import CoreData
import BabyLogKit

enum EditorTarget: Identifiable {
    case new(EventKind)
    case edit(LogEvent)

    var id: String {
        switch self {
        case .new(let kind):
            return "new-" + kind.rawValue
        case .edit(let event):
            return "edit-" + event.objectID.uriRepresentation().absoluteString
        }
    }
}

/// Add or edit one log entry. Edits a value-type `EventDraft`, so Cancel discards everything.
struct EventEditorView: View {
    let baby: Baby
    let target: EditorTarget

    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context
    @Environment(\.appTheme) private var theme
    @AppStorage(Prefs.volumeUnit) private var volumeUnit: VolumeUnit = Prefs.defaultVolumeUnit
    @AppStorage(Prefs.unitSystem) private var unitSystem: UnitSystem = Prefs.defaultUnitSystem

    @State private var draft: EventDraft
    @State private var confirmDelete = false

    init(baby: Baby, target: EditorTarget) {
        self.baby = baby
        self.target = target
        switch target {
        case .new(let kind):
            _draft = State(initialValue: EventDraft(kind: kind))
        case .edit(let event):
            _draft = State(initialValue: EventDraft(event: event))
        }
    }

    private var isEditing: Bool {
        if case .edit = target { return true }
        return false
    }

    private var screenTitle: String {
        let name = draft.kind == .bottle ? "奶粉" : Zh.kind(draft.kind)
        return isEditing ? "修改\(name)" : "记录\(name)"
    }

    var body: some View {
        NavigationStack {
            Form {
                kindFields

                Section {
                    TextField("备注", text: $draft.notes, axis: .vertical)
                        .lineLimit(1...5)
                } header: {
                    Text("备注")
                } footer: {
                    if let message = draft.validationMessage {
                        Text(message)
                            .foregroundStyle(theme.destructive)
                    }
                }
                .themedSection()

                if isEditing {
                    Section {
                        Button(role: .destructive) {
                            confirmDelete = true
                        } label: {
                            Text("删除这条记录").themedDestructive()
                        }
                    }
                    .themedSection()
                }
            }
            .themedList()
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(screenTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .fontWeight(.semibold)
                        .disabled(draft.validationMessage != nil)
                        .accessibilityIdentifier("save-entry")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { UIApplication.endEditing() }
                }
            }
            .confirmationDialog("删除这条记录？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("删除", role: .destructive) { deleteEntry() }
                Button("取消", role: .cancel) {}
            }
        }
    }

    // MARK: Fields by kind

    private var kindFields: some View {
        kindSection.themedSection()
    }

    @ViewBuilder
    private var kindSection: some View {
        switch draft.kind {
        case .sleep:
            sleepFields
        case .breastfeed:
            nursingFields
        case .bottle:
            bottleFields
        case .solids:
            solidsFields
        case .diaper:
            diaperFields
        case .pump:
            pumpFields
        case .growth:
            growthFields
        case .medicine:
            medicineFields
        }
    }

    private var sleepFields: some View {
        Section {
            DatePicker("开始", selection: $draft.startDate)
            Toggle("还在睡", isOn: stillAsleep)
            if draft.endDate != nil {
                DatePicker("结束", selection: endDateBinding)
                LabeledContent("时长", value: DurationFormat.short(sleepSeconds))
            }
        }
    }

    private var nursingFields: some View {
        Section {
            DatePicker("开始", selection: $draft.startDate)
            if draft.isRunning {
                Text("计时还在进行。回到今天页面可以换边或结束。")
                    .font(.subheadline)
                    .foregroundStyle(theme.secondary)
            } else {
                NumberField("左侧分钟", value: minutesBinding(\.leftSeconds), unit: "分钟")
                NumberField("右侧分钟", value: minutesBinding(\.rightSeconds), unit: "分钟")
                Picker("最后一侧", selection: $draft.lastSide) {
                    Text("无").tag(BreastSide?.none)
                    ForEach(BreastSide.allCases) { side in
                        Text(Zh.side(side)).tag(Optional(side))
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var bottleFields: some View {
        Section {
            DatePicker("时间", selection: $draft.startDate)
            NumberField("奶量", value: volumeBinding(\.amountML), unit: volumeUnit.symbol, identifier: "bottle-amount")
            Picker("内容", selection: $draft.bottleContent) {
                ForEach(BottleContent.allCases) { content in
                    Text(Zh.bottle(content)).tag(content)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var solidsFields: some View {
        Section {
            DatePicker("Time", selection: $draft.startDate)
            TextField("Food", text: $draft.foodName)
                .textInputAutocapitalization(.sentences)
        }
    }

    private var diaperFields: some View {
        Section {
            DatePicker("时间", selection: $draft.startDate)
            Picker("尿布", selection: $draft.diaperKind) {
                ForEach(DiaperKind.allCases) { kind in
                    Text(Zh.diaper(kind)).tag(kind)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var pumpFields: some View {
        Section {
            DatePicker("Start", selection: $draft.startDate)
            NumberField("Duration", value: minutesBinding(\.pumpDuration), unit: "min")
            NumberField("Left", value: volumeBinding(\.leftML), unit: volumeUnit.symbol)
            NumberField("Right", value: volumeBinding(\.rightML), unit: volumeUnit.symbol)
        }
    }

    private var growthFields: some View {
        Section {
            DatePicker("Time", selection: $draft.startDate)
            if unitSystem == .metric {
                NumberField("Weight", value: $draft.weightKg, unit: "kg", digits: 3)
            } else {
                NumberField("Weight", value: poundsBinding, unit: "lb", digits: 0)
                NumberField("Ounces", value: ouncesBinding, unit: "oz", digits: 1)
            }
            NumberField("Length", value: lengthBinding(\.lengthCm), unit: unitSystem.lengthSymbol)
            NumberField("Head", value: lengthBinding(\.headCm), unit: unitSystem.lengthSymbol)
        }
    }

    private var medicineFields: some View {
        Section {
            DatePicker("Time", selection: $draft.startDate)
            TextField("Medicine", text: $draft.medicineName)
                .textInputAutocapitalization(.words)
            TextField("Dose, e.g. 2.5 ml", text: $draft.dose)
        }
    }

    // MARK: Bindings

    private var sleepSeconds: TimeInterval {
        guard let end = draft.endDate else { return 0 }
        return max(0, end.timeIntervalSince(draft.startDate))
    }

    private var stillAsleep: Binding<Bool> {
        Binding(
            get: { draft.endDate == nil },
            set: { asleep in
                if asleep {
                    draft.endDate = nil
                } else {
                    draft.endDate = max(Date.now, draft.startDate.addingTimeInterval(60))
                }
            }
        )
    }

    private var endDateBinding: Binding<Date> {
        Binding(
            get: { draft.endDate ?? draft.startDate },
            set: { draft.endDate = $0 }
        )
    }

    private func minutesBinding(_ keyPath: WritableKeyPath<EventDraft, TimeInterval>) -> Binding<Double> {
        Binding(
            get: { draft[keyPath: keyPath] / 60 },
            set: { draft[keyPath: keyPath] = $0 * 60 }
        )
    }

    private func volumeBinding(_ keyPath: WritableKeyPath<EventDraft, Double>) -> Binding<Double> {
        Binding(
            get: { volumeUnit.value(fromMilliliters: draft[keyPath: keyPath]) },
            set: { draft[keyPath: keyPath] = volumeUnit.milliliters(from: $0) }
        )
    }

    private func lengthBinding(_ keyPath: WritableKeyPath<EventDraft, Double>) -> Binding<Double> {
        Binding(
            get: { unitSystem.lengthValue(fromCentimeters: draft[keyPath: keyPath]) },
            set: { draft[keyPath: keyPath] = unitSystem.centimeters(fromLength: $0) }
        )
    }

    private var poundsBinding: Binding<Double> {
        Binding(
            get: { Double(UnitSystem.poundsOunces(fromKilograms: draft.weightKg).pounds) },
            set: { pounds in
                let ounces = UnitSystem.poundsOunces(fromKilograms: draft.weightKg).ounces
                draft.weightKg = UnitSystem.kilograms(pounds: pounds, ounces: ounces)
            }
        )
    }

    private var ouncesBinding: Binding<Double> {
        Binding(
            get: { UnitSystem.poundsOunces(fromKilograms: draft.weightKg).ounces },
            set: { ounces in
                let pounds = Double(UnitSystem.poundsOunces(fromKilograms: draft.weightKg).pounds)
                draft.weightKg = UnitSystem.kilograms(pounds: pounds, ounces: ounces)
            }
        )
    }

    // MARK: Actions

    private func save() {
        switch target {
        case .new(let kind):
            let event = LogEvent.create(kind: kind, for: baby, start: draft.startDate, in: context)
            draft.apply(to: event)
        case .edit(let event):
            draft.apply(to: event)
        }
        context.saveIfNeeded()
        Haptics.success()
        dismiss()
    }

    private func deleteEntry() {
        if case .edit(let event) = target {
            context.delete(event)
            context.saveIfNeeded()
        }
        dismiss()
    }
}

#Preview("New bottle") {
    EventEditorView(baby: PreviewData.baby, target: .new(.bottle))
        .previewEnvironment()
}

#Preview("New growth") {
    EventEditorView(baby: PreviewData.baby, target: .new(.growth))
        .previewEnvironment()
}
